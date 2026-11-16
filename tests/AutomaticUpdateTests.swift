import Foundation

@main
struct AutomaticUpdateTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(value(), message)
    }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        awayEventsCountAfterFiveMinutes()
        sleepTimeDoesNotCount()
        returningEndsTheAwayPeriod()
        inputIdleCountsAsAway()
        everyGuardHoldsTheRestart()
        print("AutomaticUpdateTests: \(checks) checks passed")
    }

    static let busy: TimeInterval = 10
    static func idle(_ seconds: TimeInterval) -> AutomaticUpdate.Activity { .init(idleTime: seconds) }

    static func awayEventsCountAfterFiveMinutes() {
        var schedule = AutomaticUpdate()
        check(!schedule.isAway(at: 10_000, idle(busy)), "In use, the Mac isn't away")
        schedule.began(.screenLock, at: 100)
        check(!schedule.isAway(at: 399, idle(busy)), "Not yet five minutes into the lock")
        check(schedule.isAway(at: 400, idle(busy)), "Five minutes into the lock")
        schedule.began(.displaySleep, at: 160)
        check(schedule.awaySince == 100, "A second reason joins the same away period")
        schedule.ended(.displaySleep)
        check(schedule.isAway(at: 400, idle(busy)), "The Mac stays away while the screen is locked")
    }

    static func sleepTimeDoesNotCount() {
        var schedule = AutomaticUpdate()
        schedule.began(.sleep, at: 50)
        schedule.began(.screenLock, at: 50)
        schedule.ended(.sleep)
        check(!schedule.isAway(at: 60, idle(busy)), "Just after waking, the lock hasn't counted yet")
        check(schedule.isAway(at: 350, idle(busy)), "Five awake minutes later it has")
    }

    static func returningEndsTheAwayPeriod() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenSaver, at: 0)
        check(schedule.isAway(at: 600, idle(busy)), "The screen saver has run ten minutes")
        schedule.ended(.screenSaver)
        check(schedule.away.isEmpty && schedule.awaySince == nil, "Stopping it returns the Mac to use")
        check(!schedule.isAway(at: 601, idle(busy)), "And the Mac is no longer away")
        schedule.began(.screenLock, at: 700)
        check(!schedule.isAway(at: 760, idle(busy)), "A new lock waits its own five minutes")
    }

    static func inputIdleCountsAsAway() {
        let schedule = AutomaticUpdate()
        check(!schedule.isAway(at: 10_000, idle(1799)), "Just under half an hour without input")
        check(schedule.isAway(at: 10_000, idle(AutomaticUpdate.idleAwayTime)), "Half an hour without input")
        check(schedule.allows(AutomaticUpdate.Activity(idleTime: 1800), at: 10_000),
              "An idle Mac installs with nothing in use")
        var media = AutomaticUpdate.Activity(idleTime: 7200)
        media.pageInUse = true
        check(!schedule.allows(media, at: 10_000), "A video playing through the night still holds it")
        var call = AutomaticUpdate.Activity(idleTime: 2700)
        call.displayKeptOn = true
        check(!schedule.isAway(at: 10_000, call), "A call or film in another app keeps the display on: not away")
        var locked = AutomaticUpdate()
        locked.began(.screenLock, at: 0)
        check(locked.isAway(at: 300, call), "A lock still counts while the display is kept on")
    }

    static func everyGuardHoldsTheRestart() {
        var schedule = AutomaticUpdate()
        schedule.began(.screenLock, at: 0)
        let quiet = AutomaticUpdate.Activity(idleTime: busy)
        check(schedule.allows(quiet, at: 300), "A ready update installs five minutes into a lock")
        check(!AutomaticUpdate().allows(quiet, at: 300), "Never while the Mac is in use")
        let holds: [(String, (inout AutomaticUpdate.Activity) -> Void)] = [
            ("Automatic Updates off", { $0.enabled = false }),
            ("no downloaded update", { $0.updateReady = false }),
            ("media, capture, Picture in Picture or typed text", { $0.pageInUse = true }),
            ("a running download", { $0.downloading = true }),
            ("an open sheet or alert", { $0.dialogOpen = true }),
            ("a private window", { $0.privateWindowOpen = true }),
            ("input in the last three seconds", { $0.idleTime = 2.9 }),
        ]
        for (reason, change) in holds {
            var activity = quiet
            change(&activity)
            check(!schedule.allows(activity, at: 300), "Holds the restart: \(reason)")
        }
        var idle = quiet
        idle.idleTime = AutomaticUpdate.requiredIdleTime
        check(schedule.allows(idle, at: 300), "Exactly three idle seconds is enough")
    }
}
