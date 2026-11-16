import Foundation

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
