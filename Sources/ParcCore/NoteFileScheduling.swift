import Foundation

@MainActor
final class NoteFileTimer {
    private var cancellation: (@MainActor () -> Void)?

    init(cancel: @escaping @MainActor () -> Void) { cancellation = cancel }

    func cancel() {
        cancellation?()
        cancellation = nil
    }
}

@MainActor
protocol NoteFileClock: AnyObject {
    var now: Date { get }
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> NoteFileTimer
}

private final class NoteFileMainAction: @unchecked Sendable {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    func run() { MainActor.assumeIsolated { action() } }
}

@MainActor
final class NoteFileSystemClock: NoteFileClock {
    static let shared = NoteFileSystemClock()

    var now: Date { Date() }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> NoteFileTimer {
        let box = NoteFileMainAction(action)
        let item = DispatchWorkItem { box.run() }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return NoteFileTimer { item.cancel() }
    }
}

final class NoteFileWorker: @unchecked Sendable {
    static let files = NoteFileWorker(label: "org.parc.notes.files")
    static let index = NoteFileWorker(label: "org.parc.notes.index", qos: .utility)
    static let inline = NoteFileWorker()

    private let queue: DispatchQueue?

    init(label: String, qos: DispatchQoS = .userInitiated) {
        queue = DispatchQueue(label: label, qos: qos)
    }

    private init() { queue = nil }

    var isInline: Bool { queue == nil }

    @MainActor
    func perform<Value>(_ work: @escaping () -> Value, then finish: @escaping @MainActor (Value) -> Void) {
        guard let queue else {
            finish(work())
            return
        }
        let job = NoteFileJob(work: work, finish: finish)
        queue.async { job.run() }
    }

    func sync<Value>(_ work: () throws -> Value) rethrows -> Value {
        guard let queue else { return try work() }
        return try queue.sync(execute: work)
    }
}

private final class NoteFileJob<Value>: @unchecked Sendable {
    private let work: () -> Value
    private let finish: @MainActor (Value) -> Void
    private var value: Value?

    init(work: @escaping () -> Value, finish: @escaping @MainActor (Value) -> Void) {
        self.work = work
        self.finish = finish
    }

    func run() {
        value = work()
        DispatchQueue.main.async { self.complete() }
    }

    private func complete() {
        MainActor.assumeIsolated {
            guard let value else { return }
            finish(value)
        }
    }
}
