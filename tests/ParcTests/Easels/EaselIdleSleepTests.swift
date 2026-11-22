import Foundation
import Testing
@testable import Parc
@testable import ParcEasels

struct EaselIdleSleepTests {
    private struct Clock {
        var now = Date(timeIntervalSince1970: 30_000)

        mutating func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    @Test(arguments: [-1.0, 0.0, 1.0])
    func aSettledUnseenEaselCanSleepAfterTheIdlePeriod(_ offset: TimeInterval) {
        var clock = Clock()
        let lastAccessed = clock.now
        let idlePeriod: TimeInterval = 14_400
        clock.advance(by: idlePeriod + offset)

        let eligible = EaselIdleSleep.isEligible(lastAccessed: lastAccessed, shown: false,
                                                 closing: false, transferring: false,
                                                 idleFor: idlePeriod, now: { clock.now }, settled: true)
        #expect(eligible == (offset > 0))
    }

    enum Activity: CaseIterable {
        case shown, closing, transferring, unsettled, missing
    }

    @Test(arguments: Activity.allCases)
    func anEaselWithActiveWorkOrNoOpenTabStaysAwake(_ activity: Activity) {
        let clock = Clock()
        let lastAccessed = activity == .missing ? nil : clock.now.addingTimeInterval(-18_000)

        #expect(!EaselIdleSleep.isEligible(lastAccessed: lastAccessed, shown: activity == .shown,
                                          closing: activity == .closing, transferring: activity == .transferring,
                                          idleFor: 14_400, now: { clock.now }, settled: activity != .unsettled))
    }
}
