import Foundation

@main
struct ArchiveSchedulingTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor
    static func runChecks() {
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            guard value() else { fatalError(message) }
        }
        final class Clock {
            struct Pending {
                let job: ArchiveScheduling.Job
                let action: @MainActor () -> Void
                var cancelled = false
            }
            var pending: [Pending] = []
            @MainActor
            func schedule(_ job: ArchiveScheduling.Job,
                          action: @escaping @MainActor () -> Void) -> ArchiveScheduling.Cancellation {
                let index = pending.count
                pending.append(Pending(job: job, action: action))
                return ArchiveScheduling.Cancellation { [weak self] in self?.pending[index].cancelled = true }
            }
        }

        let clock = Clock()
        var scheduler: ArchiveScheduling? = ArchiveScheduling(schedule: clock.schedule)
        var events: [ArchiveScheduling.Job] = []
        for job in ArchiveScheduling.Job.allCases {
            scheduler?.start(job) { events.append(job) }
        }
        expect(events.isEmpty, "launch must not run archive or cleanup synchronously")
        let recipes: [(ArchiveScheduling.Job, Double, Double?, Double)] = [
            (.initialArchive, 1, nil, 0), (.initialCleanup, 5, nil, 0),
            (.archive, 300, 300, 30), (.cleanup, 21_600, 21_600, 2_160), (.activity, 60, 60, 60),
            (.discard, 300, 300, 60)
        ]
        for (job, delay, interval, tolerance) in recipes {
            expect(job.delay == delay && job.interval == interval && job.tolerance == tolerance,
                   "recovered schedule changed for \(job)")
            scheduler?.start(job) { fatalError("duplicate job replaced its original owner") }
        }
        expect(clock.pending.count == 6, "restarting an active job duplicates its timer")
        clock.pending[0].action()
        clock.pending[0].action()
        expect(events == [.initialArchive], "one-shot callback must retire before its action")
        expect(clock.pending[0].cancelled, "finished one-shot must release its source")
        clock.pending[2].action(); clock.pending[2].action()
        expect(events == [.initialArchive, .archive, .archive], "periodic callback must remain live")
        scheduler?.cancel()
        expect(clock.pending.allSatisfy(\.cancelled), "shutdown must cancel delayed and periodic sources")
        let count = events.count
        clock.pending.forEach { $0.action() }
        expect(events.count == count, "queued callbacks must be inert after shutdown")
        scheduler?.start(.activity) { events.append(.activity) }
        clock.pending[4].action()
        expect(events.count == count, "old generation must not refresh a replacement window")
        clock.pending[6].action()
        expect(events.last == .activity, "replacement generation must receive its own callback")
        scheduler = nil
        expect(clock.pending[6].cancelled, "owner destruction must cancel its source")
        clock.pending[6].action()
        expect(events.count == count + 1, "dead owner must not receive queued work")

        let otherClock = Clock()
        let firstWindow = ArchiveScheduling(schedule: otherClock.schedule)
        let secondWindow = ArchiveScheduling(schedule: otherClock.schedule)
        var firstTicks = 0, secondTicks = 0
        firstWindow.start(.activity) { firstTicks += 1 }
        secondWindow.start(.activity) { secondTicks += 1 }
        firstWindow.cancel()
        otherClock.pending.forEach { $0.action() }
        expect(firstTicks == 0 && secondTicks == 1, "closing one window must preserve the other's activity clock")

        let synchronous = ArchiveScheduling(schedule: { _, action in
            action()
            return ArchiveScheduling.Cancellation {}
        })
        var synchronousCalls = 0
        synchronous.start(.initialCleanup) { synchronousCalls += 1 }
        expect(synchronousCalls == 1, "injected immediate delivery must be safe")

        let origin = ContinuousClock.now
        func deadline(_ last: Double?, _ now: Double, _ interval: Double = 60) -> Double {
            let value = ArchiveScheduling.nextDeadline(last: last.map { origin.advanced(by: .seconds($0)) },
                now: origin.advanced(by: .seconds(now)), interval: .seconds(interval))
            return origin.duration(to: value) / .seconds(1)
        }
        expect(deadline(nil, 0) == 60, "activity starts after a full interval")
        expect(deadline(60, 60) == 120, "normal ticks retain their deadline")
        expect(deadline(60, 119) == 120, "ordinary main-actor delay must not shift the cadence")
        expect(deadline(60, 120) == 120, "exact boundary may deliver its pending tick")
        expect(deadline(60, 130) == 120, "late delivery follows the recovered nearest missed boundary")
        expect(deadline(60, 3_660) == 3_600, "sleep must coalesce a long backlog")
        expect(deadline(3_600, 3_660) == 3_660 && deadline(3_660, 3_660) == 3_720,
               "coalescing converges to the future without replaying every missed period")
        expect(deadline(300, 86_450, 300) == 86_400, "archive uses the same continuous cadence")
        print("Archive scheduling: \(assertions) assertions passed")
    }
}
