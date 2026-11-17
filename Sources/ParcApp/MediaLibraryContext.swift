import AppKit

struct MediaLibraryNavigation: Equatable {
    let index: Int?
    private let previous: String?
    private let next: String?
    init(index: Int?, previous: String?, next: String?) {
        self.index = index; self.previous = index == nil ? nil : previous; self.next = index == nil ? nil : next
    }
    init(orderedIDs: [String], selectedID: String) {
        let index = orderedIDs.firstIndex(of: selectedID)
        self.init(index: index, previous: index.flatMap { $0 > 0 ? orderedIDs[$0 - 1] : nil },
                  next: index.flatMap { $0 + 1 < orderedIDs.count ? orderedIDs[$0 + 1] : nil })
    }
    var ordinal: Int { index.map { $0 + 1 } ?? 0 }
    func neighbor(_ offset: Int) -> String? { offset == -1 ? previous : offset == 1 ? next : nil }
}

struct MediaLibraryActionTicket {
    let generation: UInt64
    func canCommit(generation current: UInt64, ownerValid: Bool, itemCurrent: Bool) -> Bool {
        generation == current && ownerValid && itemCurrent
    }
}

final class MediaLibraryThumbnailOperation: @unchecked Sendable {
    typealias Completion = (Result<Data, Error>) -> Void
    private let start: (@escaping Completion) -> Void
    private let stop: () -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var cancelled = false
    private var finished = false
    init(start: @escaping (@escaping Completion) -> Void, stop: @escaping () -> Void) {
        self.start = start; self.stop = stop
    }
    func value() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled || finished { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation; lock.unlock()
                start { [weak self] result in self?.finish(result) }
                lock.lock(); let cancelAfterStart = cancelled; lock.unlock()
                if cancelAfterStart { stop() }
            }
        } onCancel: { self.cancel() }
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; let continuation = self.continuation; self.continuation = nil
        lock.unlock(); continuation?.resume(with: result)
    }
    private func cancel() {
        lock.lock(); cancelled = true
        let shouldStop = !finished; finished = true
        let continuation = self.continuation; self.continuation = nil
        lock.unlock()
        if shouldStop { stop() }
        continuation?.resume(throwing: CancellationError())
    }
}

@MainActor
final class MediaLibraryLatestWork<Value: Sendable> {
    typealias Work = @Sendable () throws -> Value
    typealias Finish = @MainActor (Value) -> Void
    typealias Request = @MainActor () -> (work: Work, finish: Finish)?
    private let replacementsBeforeFinishing = 2
    private var task: Task<Void, Never>?
    private var ticket: UInt64 = 0
    private var replaced = 0
    private var queued: Request?
    var isRunning: Bool { task != nil }
    deinit { task?.cancel() }
    func start(_ request: @escaping Request) {
        if task != nil, replaced >= replacementsBeforeFinishing { queued = request; return }
        replaced = task == nil ? 0 : replaced + 1
        task?.cancel(); task = nil; ticket &+= 1; queued = nil
        guard let next = request() else { return }
        let current = ticket, work = next.work, finish = next.finish
        let worker = Task.detached(priority: .userInitiated) { try work() }
        task = Task { [weak self] in
            let value = await withTaskCancellationHandler { try? await worker.value } onCancel: { worker.cancel() }
            guard let self, self.ticket == current else { return }
            self.task = nil; self.replaced = 0
            if let value { finish(value) }
            if let waiting = self.queued { self.queued = nil; self.start(waiting) }
        }
    }
    func cancel() { ticket &+= 1; task?.cancel(); task = nil; replaced = 0; queued = nil }
}

@MainActor
final class MediaLibraryGridLayout: NSCollectionViewFlowLayout {
    private var styleObserver: NSObjectProtocol?
    override init() {
        super.init()
        styleObserver = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.remeasure() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let styleObserver { NotificationCenter.default.removeObserver(styleObserver) } }
    func remeasure() {
        guard side(width: gridWidth) != itemSize.width else { return }
        let context = NSCollectionViewFlowLayoutInvalidationContext()
        context.invalidateFlowLayoutDelegateMetrics = true
        invalidateLayout(with: context)
    }
    nonisolated static func side(width: CGFloat, insets: CGFloat, spacing: CGFloat) -> CGFloat {
        max(1, (width - insets - spacing) / 2)
    }
    private func side(width: CGFloat) -> CGFloat {
        Self.side(width: width, insets: sectionInset.left + sectionInset.right, spacing: minimumInteritemSpacing)
    }
    private var gridWidth: CGFloat {
        guard let collectionView else { return 0 }
        guard let scroll = collectionView.enclosingScrollView else { return collectionView.bounds.width }
        func content(scrolling: Bool) -> NSSize {
            NSScrollView.contentSize(forFrameSize: scroll.frame.size,
                horizontalScrollerClass: scroll.hasHorizontalScroller ? NSScroller.self : nil,
                verticalScrollerClass: scrolling ? NSScroller.self : nil, borderType: scroll.borderType,
                controlSize: scroll.verticalScroller?.controlSize ?? .regular, scrollerStyle: scroll.scrollerStyle)
        }
        let insets = scroll.contentInsets, full = content(scrolling: false)
        let width = full.width - insets.left - insets.right
        let visible = scroll.contentView.bounds.width - insets.left - insets.right
        let reserved = content(scrolling: true).width - insets.left - insets.right
        guard scroll.hasVerticalScroller, reserved < width else { return min(width, visible) }
        guard scroll.autohidesScrollers else { return min(reserved, visible) }
        let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        let rows = CGFloat((count + 1) / 2), tile = side(width: width)
        let height = sectionInset.top + sectionInset.bottom + rows * tile + max(0, rows - 1) * minimumLineSpacing
        return min(height > full.height - insets.top - insets.bottom - 1 ? reserved : width, visible)
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        super.shouldInvalidateLayout(forBoundsChange: newBounds) || side(width: gridWidth) != itemSize.width
    }
    override func invalidationContext(forBoundsChange newBounds: NSRect) -> NSCollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        if side(width: gridWidth) != itemSize.width {
            (context as? NSCollectionViewFlowLayoutInvalidationContext)?.invalidateFlowLayoutDelegateMetrics = true
        }
        return context
    }
    override func prepare() {
        let next = side(width: gridWidth)
        if itemSize != NSSize(width: next, height: next) { itemSize = NSSize(width: next, height: next) }
        super.prepare()
    }
}

struct MediaLibraryThumbnails<Key: Hashable, Image> {
    enum Fill { case show(Image), load(UInt64) }
    let capacity: Int
    private var images: [Key: Image] = [:]
    private var recency: [Key] = []
    private var loading: [Key: UInt64] = [:]
    private var serial: UInt64 = 0
    init(capacity: Int) { self.capacity = max(1, capacity) }
    var count: Int { images.count }
    func peek(_ key: Key) -> Image? { images[key] }
    func isLoading(_ key: Key) -> Bool { loading[key] != nil }
    mutating func fill(_ key: Key, live: Bool) -> Fill? {
        if let image = images[key] { touch(key); return .show(image) }
        guard live, loading[key] == nil else { return nil }
        serial &+= 1; loading[key] = serial
        return .load(serial)
    }
    mutating func finish(_ key: Key, ticket: UInt64, image: Image) -> Bool {
        guard loading[key] == ticket else { return false }
        loading[key] = nil; images[key] = image; touch(key)
        while recency.count > capacity { images[recency.removeFirst()] = nil }
        return true
    }
    mutating func abandon(_ key: Key, ticket: UInt64) {
        if loading[key] == ticket { loading[key] = nil }
    }
    mutating func forget<S: Sequence>(_ keys: S) where S.Element == Key {
        let gone = Set(keys)
        guard !gone.isEmpty else { return }
        for key in gone { images[key] = nil; loading[key] = nil }
        recency.removeAll { gone.contains($0) }
    }
    mutating func reset() { images = [:]; recency = []; loading = [:] }
    private mutating func touch(_ key: Key) {
        if let index = recency.lastIndex(of: key) { recency.remove(at: index) }
        recency.append(key)
    }
}
