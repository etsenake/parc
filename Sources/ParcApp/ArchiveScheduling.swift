import Foundation

///
/// separate lifetimes. See docs/archive.md; these clocks never reset the
/// persisted eligibility start time or substitute for native close consent.
@MainActor
final class ArchiveScheduling {
    enum Job: CaseIterable, Hashable {
        case initialArchive, initialCleanup, archive, cleanup, activity
        ///
        ///
        case discard

        var delay: TimeInterval {
            switch self {
            case .initialArchive: return 1
            case .initialCleanup: return 5
            case .archive: return 300
            case .cleanup: return 21_600
            case .activity: return 60
            case .discard: return 300
            }
        }
        var interval: TimeInterval? {
            switch self {
            case .initialArchive, .initialCleanup: return nil
            case .archive, .cleanup, .activity, .discard: return delay
            }
        }
        var tolerance: TimeInterval {
            switch self {
            case .initialArchive, .initialCleanup: return 0
            case .archive: return 30
            case .cleanup: return 2_160
            case .activity, .discard: return 60
            }
        }
    }

    final class Cancellation {
        private var cancelWork: (() -> Void)?
        init(_ cancel: @escaping () -> Void) { cancelWork = cancel }
        func cancel() { let work = cancelWork; cancelWork = nil; work?() }
        deinit { cancelWork?() }
    }

    typealias Schedule = @MainActor (Job, @escaping @MainActor () -> Void) -> Cancellation
    private let schedule: Schedule
    private struct Subscription {
        let id: UUID
        var cancellation: Cancellation?
    }
    private var subscriptions: [Job: Subscription] = [:]

    init(schedule: @escaping Schedule = ArchiveScheduling.scheduleWork) {
        self.schedule = schedule
    }

    func start(_ job: Job, action: @escaping @MainActor () -> Void) {
        guard subscriptions[job] == nil else { return }
        let id = UUID()
        subscriptions[job] = Subscription(id: id)
        let cancellation = schedule(job) { [weak self] in
            guard let self, self.subscriptions[job]?.id == id else { return }
            // A cancelled or superseded queued callback cannot reach its
            // former owner. One-shot work retires before invoking its action.
            if job.interval == nil { self.subscriptions.removeValue(forKey: job) }
            action()
        }
        if subscriptions[job]?.id == id { subscriptions[job]?.cancellation = cancellation }
        else { cancellation.cancel() }
    }

    func cancel() {
        let previous = subscriptions
        subscriptions.removeAll()
        previous.values.forEach { $0.cancellation?.cancel() }
    }

    /// The shipped Clocks timer retains its nominal deadline, skipping whole
    /// missed periods before the next sleep. It never replays every missed tick.
    static func nextDeadline(last: ContinuousClock.Instant?, now: ContinuousClock.Instant,
                             interval: Duration) -> ContinuousClock.Instant {
        let previous = last ?? now
        let next = previous.advanced(by: interval)
        guard next < now else { return next }
        let skipped = Int(ceil(next.duration(to: now) / interval))
        return previous.advanced(by: interval * skipped)
    }

    private static func scheduleWork(_ job: Job,
                                     action: @escaping @MainActor () -> Void) -> Cancellation {
        if let interval = job.interval {
            //
            // run-loop timer would give sleep a different elapsed-time policy.
            let clock = ContinuousClock(), step = Duration.seconds(interval)
            let task = Task { @MainActor in
                var deadline = nextDeadline(last: nil, now: clock.now, interval: step)
                while !Task.isCancelled {
                    do { try await clock.sleep(until: deadline, tolerance: .seconds(job.tolerance)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    action()
                    deadline = nextDeadline(last: deadline, now: clock.now, interval: step)
                }
            }
            return Cancellation { task.cancel() }
        }
        // Launch uses the independent mainQueue delay effects, not the
        // recurring continuous clock, and cancellation owns both kinds.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + job.delay)
        timer.setEventHandler { MainActor.assumeIsolated { action() } }
        timer.resume()
        return Cancellation { timer.setEventHandler {}; timer.cancel() }
    }
}
