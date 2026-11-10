import Foundation

@main
struct AutomaticUpdateTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(value(), message)
    }

    static func main() {
        awayStartsOneCheck()
        checksRepeatWhileAway()
        returningCancelsTheCheck()
        staleChecksDoNothing()
        everyGuardHoldsTheRestart()
        print("AutomaticUpdateTests: \(checks) checks passed")
    }

    static func awayStartsOneCheck() {
        var schedule = AutomaticUpdate()
        check(schedule.nextCheck == nil, "In use, nothing is scheduled")
        check(schedule.began(.screenLock, at: 100) == 400, "Locking schedules a check five minutes later")
        check(schedule.began(.displaySleep, at: 160) == nil, "A second reason joins the same away period")
        check(schedule.began(.screenLock, at: 170) == nil, "A repeated notice changes nothing")
        check(schedule.nextCheck == 400, "The first reason's time stands")
        schedule.ended(.displaySleep)
        check(schedule.nextCheck == 400, "The Mac stays away while the screen is locked")
    }

    static func checksRepeatWhileAway() {
        var schedule = AutomaticUpdate()
        let due = schedule.began(.screenSaver, at: 0)!
        check(schedule.checkFired(due: due, at: 300) == 600, "A check arms the next five minutes on")
        check(schedule.checkFired(due: 600, at: 600) == 900, "And again while the Mac stays away")
        // The wait counts awake time, so a sleep in between only delays it.
        check(schedule.began(.sleep, at: 650) == nil, "Sleeping while the screen saver runs stays one period")
        check(schedule.checkFired(due: 900, at: 900) == 1200, "The pending check survives the sleep")
    }

    static func returningCancelsTheCheck() {
        var schedule = AutomaticUpdate()
        let due = schedule.began(.sleep, at: 50)!
        _ = schedule.began(.screenLock, at: 50)
        schedule.ended(.sleep)
        check(schedule.nextCheck == due, "Waking to a locked screen keeps the check")
        schedule.ended(.screenLock)
        check(schedule.away.isEmpty && schedule.nextCheck == nil, "Unlocking returns the Mac to use")
        check(schedule.checkFired(due: due, at: 350) == nil, "The cancelled check does nothing")
        check(schedule.nextCheck == nil, "And arms nothing")
    }

    static func staleChecksDoNothing() {
        var schedule = AutomaticUpdate()
        let first = schedule.began(.displaySleep, at: 0)!
        schedule.ended(.displaySleep)
        let second = schedule.began(.displaySleep, at: 100)!
        check(second == 400, "A new away period waits its own five minutes")
        check(schedule.checkFired(due: first, at: 300) == nil, "The earlier period's timer is ignored")
        check(schedule.nextCheck == second, "And leaves the current check pending")
        check(schedule.checkFired(due: second, at: 400) == 700, "The current check runs on time")
    }

    static func everyGuardHoldsTheRestart() {
        let quiet = AutomaticUpdate.Activity()
        check(AutomaticUpdate.allows(quiet), "A ready update installs when nothing is in use")
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
            check(!AutomaticUpdate.allows(activity), "Holds the restart: \(reason)")
        }
        var idle = quiet
        idle.idleTime = AutomaticUpdate.requiredIdleTime
        check(AutomaticUpdate.allows(idle), "Exactly three idle seconds is enough")
    }
}
