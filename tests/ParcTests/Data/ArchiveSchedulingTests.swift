import Foundation
import Testing
@testable import Parc

@MainActor
struct ArchiveSchedulingTests {
    private final class Clock {
        struct Pending {
            let job: ArchiveScheduling.Job
            let action: @MainActor () -> Void
            var cancelled = false
        }

        var pending: [Pending] = []

        func schedule(_ job: ArchiveScheduling.Job,
                      action: @escaping @MainActor () -> Void) -> ArchiveScheduling.Cancellation {
            let index = pending.count
            pending.append(Pending(job: job, action: action))
            return ArchiveScheduling.Cancellation { [weak self] in self?.pending[index].cancelled = true }
        }
    }

    private final class Events {
        var jobs: [ArchiveScheduling.Job] = []
    }

    struct Recipe: Sendable, CustomTestStringConvertible {
        let job: ArchiveScheduling.Job
        let delay: Double
        let interval: Double?
        let tolerance: Double
        var testDescription: String { "\(job)" }
    }

    nonisolated static let recipes = [
        Recipe(job: .initialArchive, delay: 1, interval: nil, tolerance: 0),
        Recipe(job: .initialCleanup, delay: 5, interval: nil, tolerance: 0),
        Recipe(job: .archive, delay: 300, interval: 300, tolerance: 30),
        Recipe(job: .cleanup, delay: 21_600, interval: 21_600, tolerance: 2_160),
        Recipe(job: .activity, delay: 60, interval: 60, tolerance: 60),
        Recipe(job: .discard, delay: 300, interval: 300, tolerance: 60),
    ]

    private static func startedEveryJob(_ clock: Clock, _ events: Events) -> ArchiveScheduling {
        let scheduler = ArchiveScheduling(schedule: clock.schedule)
        for job in ArchiveScheduling.Job.allCases { scheduler.start(job) { events.jobs.append(job) } }
        return scheduler
    }

    private static func index(of job: ArchiveScheduling.Job, in clock: Clock) -> Int {
        clock.pending.firstIndex { $0.job == job }!
    }

    @Test func launchRunsNeitherArchiveNorCleanupSynchronously() {
        let events = Events()
        _ = Self.startedEveryJob(Clock(), events)
        #expect(events.jobs.isEmpty)
    }

    @Test(arguments: recipes)
    func eachJobKeepsItsRecoveredSchedule(recipe: Recipe) {
        #expect(recipe.job.delay == recipe.delay)
        #expect(recipe.job.interval == recipe.interval)
        #expect(recipe.job.tolerance == recipe.tolerance)
    }

    @Test func restartingAnActiveJobKeepsItsOriginalOwnerAndTimer() {
        let clock = Clock()
        let scheduler = Self.startedEveryJob(clock, Events())
        for job in ArchiveScheduling.Job.allCases {
            scheduler.start(job) { Issue.record("a duplicate job replaced its original owner") }
        }
        #expect(clock.pending.count == ArchiveScheduling.Job.allCases.count)
    }

    @Test func aOneShotCallbackRunsOnceAndRetiresBeforeItsAction() {
        let clock = Clock(), events = Events()
        let scheduler = Self.startedEveryJob(clock, events)
        let first = Self.index(of: .initialArchive, in: clock)
        clock.pending[first].action()
        clock.pending[first].action()
        #expect(events.jobs == [.initialArchive])
        withExtendedLifetime(scheduler) {}
    }

    @Test func aFinishedOneShotReleasesItsSource() {
        let clock = Clock()
        let scheduler = Self.startedEveryJob(clock, Events())
        let first = Self.index(of: .initialArchive, in: clock)
        clock.pending[first].action()
        #expect(clock.pending[first].cancelled)
        withExtendedLifetime(scheduler) {}
    }

    @Test func aPeriodicCallbackRemainsLive() {
        let clock = Clock(), events = Events()
        let scheduler = Self.startedEveryJob(clock, events)
        let archive = Self.index(of: .archive, in: clock)
        clock.pending[archive].action()
        clock.pending[archive].action()
        #expect(events.jobs == [.archive, .archive])
        withExtendedLifetime(scheduler) {}
    }

    @Test func shutdownCancelsDelayedAndPeriodicSources() {
        let clock = Clock()
        let scheduler = Self.startedEveryJob(clock, Events())
        scheduler.cancel()
        #expect(clock.pending.allSatisfy { $0.cancelled })
    }

    @Test func queuedCallbacksAreInertAfterShutdown() {
        let clock = Clock(), events = Events()
        let scheduler = Self.startedEveryJob(clock, events)
        scheduler.cancel()
        clock.pending.forEach { $0.action() }
        #expect(events.jobs.isEmpty)
    }

    @Test func anOldGenerationCannotRefreshAReplacementWindow() {
        let clock = Clock(), events = Events()
        let scheduler = Self.startedEveryJob(clock, events)
        let old = Self.index(of: .activity, in: clock)
        scheduler.cancel()
        scheduler.start(.activity) { events.jobs.append(.activity) }
        clock.pending[old].action()
        #expect(events.jobs.isEmpty)
    }

    @Test func aReplacementGenerationReceivesItsOwnCallback() {
        let clock = Clock(), events = Events()
        let scheduler = Self.startedEveryJob(clock, events)
        scheduler.cancel()
        scheduler.start(.activity) { events.jobs.append(.activity) }
        clock.pending[clock.pending.count - 1].action()
        #expect(events.jobs == [.activity])
    }

    @Test func destroyingTheOwnerCancelsItsSource() {
        let clock = Clock()
        var scheduler: ArchiveScheduling? = ArchiveScheduling(schedule: clock.schedule)
        scheduler?.start(.activity) {}
        scheduler = nil
        #expect(clock.pending[0].cancelled)
    }

    @Test func aDeadOwnerReceivesNoQueuedWork() {
        let clock = Clock(), events = Events()
        var scheduler: ArchiveScheduling? = ArchiveScheduling(schedule: clock.schedule)
        scheduler?.start(.activity) { events.jobs.append(.activity) }
        scheduler = nil
        clock.pending[0].action()
        #expect(events.jobs.isEmpty)
    }

    @Test func closingOneWindowPreservesTheOthersActivityClock() {
        let clock = Clock()
        let closing = ArchiveScheduling(schedule: clock.schedule)
        let staying = ArchiveScheduling(schedule: clock.schedule)
        var closingTicks = 0, stayingTicks = 0
        closing.start(.activity) { closingTicks += 1 }
        staying.start(.activity) { stayingTicks += 1 }
        closing.cancel()
        clock.pending.forEach { $0.action() }
        #expect(closingTicks == 0)
        #expect(stayingTicks == 1)
    }

    @Test func injectedImmediateDeliveryIsSafe() {
        let scheduler = ArchiveScheduling(schedule: { _, action in
            action()
            return ArchiveScheduling.Cancellation {}
        })
        var calls = 0
        scheduler.start(.initialCleanup) { calls += 1 }
        #expect(calls == 1)
    }

    struct Deadline: Sendable, CustomTestStringConvertible {
        let last: Double?
        let now: Double
        let interval: Double
        let expected: Double
        let reason: String
        var testDescription: String { reason }
    }

    nonisolated static let deadlines = [
        Deadline(last: nil, now: 0, interval: 60, expected: 60, reason: "activity starts after a full interval"),
        Deadline(last: 60, now: 60, interval: 60, expected: 120, reason: "normal ticks retain their deadline"),
        Deadline(last: 60, now: 119, interval: 60, expected: 120, reason: "ordinary main-actor delay does not shift the cadence"),
        Deadline(last: 60, now: 120, interval: 60, expected: 120, reason: "the exact boundary may deliver its pending tick"),
        Deadline(last: 60, now: 130, interval: 60, expected: 120, reason: "late delivery follows the nearest missed boundary"),
        Deadline(last: 60, now: 3_660, interval: 60, expected: 3_600, reason: "sleep coalesces a long backlog"),
        Deadline(last: 3_600, now: 3_660, interval: 60, expected: 3_660, reason: "coalescing converges to the future"),
        Deadline(last: 3_660, now: 3_660, interval: 60, expected: 3_720, reason: "the converged tick advances one period"),
        Deadline(last: 300, now: 86_450, interval: 300, expected: 86_400, reason: "archive uses the same continuous cadence"),
    ]

    @Test(arguments: deadlines)
    func theNextDeadlineFollowsTheContinuousCadence(case deadline: Deadline) {
        let origin = ContinuousClock.now
        let next = ArchiveScheduling.nextDeadline(
            last: deadline.last.map { origin.advanced(by: .seconds($0)) },
            now: origin.advanced(by: .seconds(deadline.now)), interval: .seconds(deadline.interval))
        #expect(origin.duration(to: next) / .seconds(1) == deadline.expected)
    }
}
