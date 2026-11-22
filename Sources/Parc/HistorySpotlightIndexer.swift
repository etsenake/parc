import AppKit
import Combine
import CoreSpotlight
import ParcCore
import UniformTypeIdentifiers

@MainActor
final class HistorySpotlightIndexer {
    static let activityType = CSSearchableItemActionType

    static func url(continuing activity: NSUserActivity) -> URL? {
        guard activity.activityType == CSSearchableItemActionType,
              let address = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              HistorySpotlight.site(of: address) != nil else { return nil }
        return URL(string: address)
    }

    private let store: BrowserStore
    private let sync = HistorySpotlightSync()
    private var subscription: AnyCancellable?
    private var submittedRevision: UInt64?
    private var submittedRemovals: UInt64
    private var pending: DispatchWorkItem?

    init?(store: BrowserStore) {
        guard CSSearchableIndex.isIndexingAvailable() else { return nil }
        self.store = store
        submittedRemovals = store.historyRemovalRevision
        sync.resyncRequested = { [weak self] delay in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.schedule(after: delay, force: true) } }
        }
        subscription = store.statePublisher.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.historyMayHaveChanged() }
        }
        schedule(after: 3, force: true)
    }

    func flush() {
        if pending != nil || store.historyRevision != submittedRevision || store.historyRemovalRevision != submittedRemovals {
            submit()
        }
        sync.drain(waitingUpTo: 2)
    }

    private func historyMayHaveChanged() {
        if store.historyRemovalRevision != submittedRemovals { return schedule(after: 0, force: false) }
        guard store.historyRevision != submittedRevision, pending == nil else { return }
        schedule(after: 2, force: false)
    }

    private func schedule(after delay: TimeInterval, force: Bool) {
        if force { submittedRevision = nil }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.submit() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func submit() {
        pending?.cancel()
        pending = nil
        submittedRevision = store.historyRevision
        submittedRemovals = store.historyRemovalRevision
        sync.update(store.state.history)
    }
}

final class HistorySpotlightSync: NSObject, CSSearchableIndexDelegate, @unchecked Sendable {
    private static let batchSize = 500
    private static let firstRetry: TimeInterval = 60
    private static let lastRetry: TimeInterval = 3600
    private static let patience: DispatchTimeInterval = .seconds(120)
    private let index = CSSearchableIndex(name: "History")
    private let queue = DispatchQueue(label: "org.parc.Browser.HistorySpotlight", qos: .utility)
    private var indexed: [String: HistorySpotlightItem]?
    private var trustsClientState = true
    private var retryDelay = HistorySpotlightSync.firstRetry
    var resyncRequested: ((TimeInterval) -> Void)?

    override init() {
        super.init()
        index.indexDelegate = self
    }

    func update(_ history: [BrowserHistoryEntry]) {
        queue.async { self.apply(HistorySpotlight.items(from: history)) }
    }

    func drain(waitingUpTo seconds: TimeInterval) {
        let done = DispatchSemaphore(value: 0)
        queue.async { done.signal() }
        _ = done.wait(timeout: .now() + seconds)
    }

    private func apply(_ items: [String: HistorySpotlightItem]) {
        let state = HistorySpotlight.clientState(for: items)
        var base: [String: HistorySpotlightItem]
        if let indexed {
            base = indexed
        } else {
            if trustsClientState, lastClientState() == state { indexed = items; return }
            guard run({ done in index.deleteAllSearchableItems(completionHandler: done) }) else { return failed() }
            trustsClientState = true
            base = [:]
        }
        let (upserts, removals) = HistorySpotlight.changes(from: base, to: items)
        if indexed != nil, upserts.isEmpty, removals.isEmpty { return }
        indexed = nil
        let group = DispatchGroup()
        let lock = NSLock()
        var succeeded = true
        let finish: (Error?) -> Void = { error in
            if error != nil { lock.lock(); succeeded = false; lock.unlock() }
            group.leave()
        }
        index.beginBatch()
        for start in stride(from: 0, to: removals.count, by: Self.batchSize) {
            group.enter()
            index.deleteSearchableItems(withIdentifiers: Array(removals[start..<min(start + Self.batchSize, removals.count)]),
                                        completionHandler: finish)
        }
        for start in stride(from: 0, to: upserts.count, by: Self.batchSize) {
            group.enter()
            index.indexSearchableItems(upserts[start..<min(start + Self.batchSize, upserts.count)].map(Self.item),
                                       completionHandler: finish)
        }
        group.enter()
        index.endBatch(withClientState: state, completionHandler: finish)
        let answered = group.wait(timeout: .now() + Self.patience) == .success
        lock.lock(); let completed = answered && succeeded; lock.unlock()
        guard completed else { return failed() }
        indexed = items
        retryDelay = Self.firstRetry
    }

    private func failed() {
        indexed = nil
        trustsClientState = false
        index.deleteAllSearchableItems(completionHandler: nil)
        resyncRequested?(retryDelay)
        retryDelay = min(retryDelay * 2, Self.lastRetry)
    }

    private func lastClientState() -> Data? {
        let done = DispatchSemaphore(value: 0)
        var state: Data?
        let lock = NSLock()
        index.fetchLastClientState { stored, error in
            lock.lock(); state = error == nil ? stored : nil; lock.unlock()
            done.signal()
        }
        guard done.wait(timeout: .now() + Self.patience) == .success else { return nil }
        lock.lock(); defer { lock.unlock() }
        return state
    }

    private func run(_ operation: (@escaping (Error?) -> Void) -> Void) -> Bool {
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var succeeded = false
        operation { error in
            lock.lock(); succeeded = error == nil; lock.unlock()
            done.signal()
        }
        guard done.wait(timeout: .now() + Self.patience) == .success else { return false }
        lock.lock(); defer { lock.unlock() }
        return succeeded
    }

    private static func item(_ entry: HistorySpotlightItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.title = entry.title
        attributes.displayName = entry.title
        attributes.contentDescription = entry.site
        attributes.keywords = [entry.site]
        attributes.lastUsedDate = entry.lastVisit
        attributes.rankingHint = NSNumber(value: entry.visits)
        let item = CSSearchableItem(uniqueIdentifier: entry.url, domainIdentifier: "history", attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }

    func searchableIndex(_ searchableIndex: CSSearchableIndex,
                         reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        queue.async {
            self.indexed = nil
            self.trustsClientState = false
            acknowledgementHandler()
            self.resyncRequested?(0)
        }
    }

    func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String],
                         acknowledgementHandler: @escaping () -> Void) {
        queue.async {
            guard let indexed = self.indexed else {
                self.trustsClientState = false
                acknowledgementHandler()
                self.resyncRequested?(0)
                return
            }
            let present = identifiers.compactMap { indexed[$0] }.map(Self.item)
            let absent = identifiers.filter { indexed[$0] == nil }
            let restored = present.isEmpty || self.run { done in self.index.indexSearchableItems(present, completionHandler: done) }
            let removed = absent.isEmpty || self.run { done in self.index.deleteSearchableItems(withIdentifiers: absent, completionHandler: done) }
            acknowledgementHandler()
            if !restored || !removed { self.failed() }
        }
    }
}
