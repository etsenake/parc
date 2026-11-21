import Foundation
import Testing
@testable import ParcCore

struct AutomaticUpdateTests {
    let busy: TimeInterval = 10

    func idle(_ seconds: TimeInterval) -> AutomaticUpdate.Activity { .init(idleTime: seconds) }

    @Test func aMacInUseIsNotAway() {
        let schedule = AutomaticUpdate()
        #expect(!schedule.isAway(at: 10_000, idle(busy)))
    }

    @Test func aLockCountsAsAwayOnlyAfterFiveMinutes() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenLock, at: 100)
        #expect(!schedule.isAway(at: 399, idle(busy)))
        #expect(schedule.isAway(at: 400, idle(busy)))
    }

    @Test func aSecondReasonJoinsTheSameAwayPeriod() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenLock, at: 100)
        schedule.began(.displaySleep, at: 160)
        #expect(schedule.awaySince == 100)
    }

    @Test func theMacStaysAwayWhileTheScreenIsLocked() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenLock, at: 100)
        schedule.began(.displaySleep, at: 160)
        schedule.ended(.displaySleep)
        #expect(schedule.isAway(at: 400, idle(busy)))
    }

    @Test func justAfterWakingTheLockHasNotCountedYet() {
        var schedule = AutomaticUpdate()
        schedule.began(.sleep, at: 50)
        schedule.began(.screenLock, at: 50)
        schedule.ended(.sleep)
        #expect(!schedule.isAway(at: 60, idle(busy)))
    }

    @Test func fiveAwakeMinutesAfterWakingTheLockHasCounted() {
        var schedule = AutomaticUpdate()
        schedule.began(.sleep, at: 50)
        schedule.began(.screenLock, at: 50)
        schedule.ended(.sleep)
        #expect(schedule.isAway(at: 350, idle(busy)))
    }

    @Test func theScreenSaverCountsAfterTenMinutes() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenSaver, at: 0)
        #expect(schedule.isAway(at: 600, idle(busy)))
    }

    @Test func stoppingTheScreenSaverReturnsTheMacToUse() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenSaver, at: 0)
        schedule.ended(.screenSaver)
        #expect(schedule.away.isEmpty)
        #expect(schedule.awaySince == nil)
        #expect(!schedule.isAway(at: 601, idle(busy)))
    }

    @Test func aNewLockWaitsItsOwnFiveMinutes() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenSaver, at: 0)
        schedule.ended(.screenSaver)
        schedule.began(.screenLock, at: 700)
        #expect(!schedule.isAway(at: 760, idle(busy)))
    }

    @Test func justUnderHalfAnHourWithoutInputIsNotAway() {
        #expect(!AutomaticUpdate().isAway(at: 10_000, idle(1799)))
    }

    @Test func halfAnHourWithoutInputIsAway() {
        #expect(AutomaticUpdate().isAway(at: 10_000, idle(AutomaticUpdate.idleAwayTime)))
    }

    @Test func anIdleMacInstallsWithNothingInUse() {
        #expect(AutomaticUpdate().allows(AutomaticUpdate.Activity(idleTime: 1800), at: 10_000))
    }

    @Test func aVideoPlayingThroughTheNightStillHoldsTheRestart() {
        var media = AutomaticUpdate.Activity(idleTime: 7200)
        media.pageInUse = true
        #expect(!AutomaticUpdate().allows(media, at: 10_000))
    }

    @Test func aCallOrFilmInAnotherAppKeepsTheDisplayOnSoTheMacIsNotAway() {
        var call = AutomaticUpdate.Activity(idleTime: 2700)
        call.displayKeptOn = true
        #expect(!AutomaticUpdate().isAway(at: 10_000, call))
    }

    @Test func aLockStillCountsWhileTheDisplayIsKeptOn() {
        var call = AutomaticUpdate.Activity(idleTime: 2700)
        call.displayKeptOn = true
        var locked = AutomaticUpdate()
        locked.began(.screenLock, at: 0)
        #expect(locked.isAway(at: 300, call))
    }

    @Test func aReadyUpdateInstallsFiveMinutesIntoALock() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenLock, at: 0)
        #expect(schedule.allows(AutomaticUpdate.Activity(idleTime: busy), at: 300))
    }

    @Test func theRestartNeverHappensWhileTheMacIsInUse() {
        #expect(!AutomaticUpdate().allows(AutomaticUpdate.Activity(idleTime: busy), at: 300))
    }

    enum Hold: String, CaseIterable, Sendable {
        case automaticUpdatesOff = "Automatic Updates off"
        case noDownloadedUpdate = "no downloaded update"
        case pageInUse = "media, capture, Picture in Picture or typed text"
        case runningDownload = "a running download"
        case openDialog = "an open sheet or alert"
        case privateWindow = "a private window"
        case recentInput = "input in the last three seconds"

        func apply(to activity: inout AutomaticUpdate.Activity) {
            switch self {
            case .automaticUpdatesOff: activity.enabled = false
            case .noDownloadedUpdate: activity.updateReady = false
            case .pageInUse: activity.pageInUse = true
            case .runningDownload: activity.downloading = true
            case .openDialog: activity.dialogOpen = true
            case .privateWindow: activity.privateWindowOpen = true
            case .recentInput: activity.idleTime = 2.9
            }
        }
    }

    @Test(arguments: Hold.allCases)
    func everyGuardHoldsTheRestart(hold: Hold) {
        var schedule = AutomaticUpdate()
        schedule.began(.screenLock, at: 0)
        var activity = AutomaticUpdate.Activity(idleTime: busy)
        hold.apply(to: &activity)
        #expect(!schedule.allows(activity, at: 300), "Holds the restart: \(hold.rawValue)")
    }

    @Test func exactlyThreeIdleSecondsIsEnough() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenLock, at: 0)
        var activity = AutomaticUpdate.Activity(idleTime: busy)
        activity.idleTime = AutomaticUpdate.requiredIdleTime
        #expect(schedule.allows(activity, at: 300))
    }
}
