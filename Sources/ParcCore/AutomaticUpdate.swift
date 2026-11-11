import Foundation

///
/// MacLifecycle inactivity timer and `AppState+AutoUpdate` checks; see
/// docs/software-update.md, "Automatic restart"). Parc checks every five
/// minutes, and installs when the Mac is away and a restart would interrupt
/// nothing. The Mac is away five minutes into a sleep, display sleep, screen
///
/// pointer input while nothing keeps the display on (the user's addition, for a
/// Mac that never sleeps or locks).
/// Times are awake time, which stops while the Mac sleeps: time asleep doesn't
/// count, awake time already spent away does.
struct AutomaticUpdate {
    enum Away: Hashable { case sleep, displaySleep, screenSaver, screenLock }

    /// What a restart would interrupt, read when a check is due.
    struct Activity {
        /// The update-ready banner's Automatic Updates checkbox.
        var enabled = true
        ///
        /// `availableUpdate`.
        var updateReady = true
        /// A page plays, records or captures media, is in Picture in Picture
        /// or holds typed text.
        var pageInUse = false
        var downloading = false
        var dialogOpen = false
        /// A private window, which a relaunch doesn't restore.
        var privateWindowOpen = false
        /// Seconds since the last keyboard or pointer input (IOHIDSystem's
        /// HIDIdleTime).
        var idleTime: TimeInterval = .infinity
        /// A display-sleep assertion is held, as by a call or a film in any
        /// app: someone may be there without touching the Mac.
        var displayKeptOn = false
    }

    ///
    /// `auto-update-inactivity-delay-in-seconds` default.
    static let delay: TimeInterval = 300
    ///
    static let requiredIdleTime: TimeInterval = 3
    ///
    static let idleAwayTime: TimeInterval = 1800

    private(set) var away: Set<Away> = []
    /// Awake time when the current away period began.
    private(set) var awaySince: TimeInterval?

    mutating func began(_ reason: Away, at now: TimeInterval) {
        if away.isEmpty { awaySince = now }
        away.insert(reason)
    }

    mutating func ended(_ reason: Away) {
        away.remove(reason)
        if away.isEmpty { awaySince = nil }
    }

    func isAway(at now: TimeInterval, _ activity: Activity) -> Bool {
        if let awaySince, now - awaySince >= Self.delay { return true }
        return activity.idleTime >= Self.idleAwayTime && !activity.displayKeptOn
    }

    ///
    ///
    /// being down, is the caller's request that follows.
    func allows(_ activity: Activity, at now: TimeInterval) -> Bool {
        isAway(at: now, activity) && activity.enabled && activity.updateReady
            && !activity.pageInUse && !activity.downloading && !activity.dialogOpen
            && !activity.privateWindowOpen && activity.idleTime >= Self.requiredIdleTime
    }
}
