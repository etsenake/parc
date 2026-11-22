import Combine
import Foundation

@MainActor
package final class NoteSyncedHold {
    private weak var engine: NoteSyncedBlocks?
    private weak var session: NotePageSession?
    private var leases: [String: NoteSyncedLease] = [:]
    private var tried = Set<String>()
    private var subscriptions = Set<AnyCancellable>()
    private var librarySubscription: AnyCancellable?
    private var libraryFolder: URL?
    private var isRefreshing = false
    private var wantsRefresh = false
    private var ended = false

    init(engine: NoteSyncedBlocks, session: NotePageSession) {
        self.engine = engine
        self.session = session
        engine.changes.sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        engine.retries.sink { [weak self] in
            self?.tried.removeAll()
            self?.refresh()
        }.store(in: &subscriptions)
        session.settled
            .filter { $0.kind == .structure || $0.kind == .replaced }
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    var heldCount: Int { leases.count }

    package func end() {
        guard !ended else { return }
        ended = true
        subscriptions.removeAll()
        librarySubscription = nil
        let held = leases.values
        leases.removeAll()
        for lease in held { lease.end() }
    }

    func refresh() {
        guard !ended else { return }
        if isRefreshing {
            wantsRefresh = true
            return
        }
        isRefreshing = true
        var rounds = 0
        repeat {
            wantsRefresh = false
            rounds += 1
            pass()
        } while wantsRefresh && rounds < 6
        isRefreshing = false
    }

    private func pass() {
        guard let engine, let session else { return }
        let own = engine.url(of: session).map(NoteFilePaths.key(for:))
        var unresolved: [(url: URL, anchor: String)] = []
        for item in engine.referencedOriginals(in: session) where !item.resolved { unresolved.append((item.url, item.anchor)) }
        for item in unresolved {
            let key = NoteFilePaths.key(for: item.url)
            let attempt = item.anchor + "\u{0}" + key
            if key != own, leases[key] == nil, tried.insert(attempt).inserted,
               let lease = engine.opener(item.url) {
                leases[key] = lease
            }
        }
        let stillMissing = engine.referencedOriginals(in: session).filter { !$0.resolved }
        if !stillMissing.isEmpty, let here = engine.url(of: session) {
            for item in stillMissing {
                for candidate in engine.originalFinder(item.anchor, here) {
                    let key = NoteFilePaths.key(for: candidate)
                    let attempt = item.anchor + "\u{0}" + key
                    guard key != own, leases[key] == nil, tried.insert(attempt).inserted, let lease = engine.opener(candidate) else { continue }
                    leases[key] = lease
                    if engine.referencedOriginals(in: session).contains(where: { $0.anchor == item.anchor && $0.resolved }) { break }
                }
            }
        }
        let references = engine.referencedOriginals(in: session)
        var wanted = Set<String>()
        for item in references where item.resolved {
            let key = NoteFilePaths.key(for: item.url)
            guard key != own else { continue }
            wanted.insert(key)
            if leases[key] == nil, let lease = engine.opener(item.url) { leases[key] = lease }
        }
        for (key, lease) in leases where !wanted.contains(key) {
            leases[key] = nil
            lease.end()
        }
        watchLibrary(needed: references.contains { !$0.resolved }, near: engine.url(of: session))
    }

    private func watchLibrary(needed: Bool, near url: URL?) {
        guard needed, let url else {
            librarySubscription = nil
            libraryFolder = nil
            return
        }
        let folder = url.deletingLastPathComponent()
        guard librarySubscription == nil || libraryFolder != folder else { return }
        libraryFolder = folder
        librarySubscription = engine?.libraryChanges(url)?.sink { [weak self] in
            self?.tried.removeAll()
            self?.refresh()
        }
    }
}
