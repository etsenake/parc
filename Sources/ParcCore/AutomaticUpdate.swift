import Foundation

///
/// MacLifecycle inactivity timer and `AppState+AutoUpdate` checks; see
/// docs/software-update.md, "Automatic restart"). The Mac is away while it
/// sleeps, its displays sleep, the screen saver runs or the screen is locked.
/// Five minutes into that, and every five minutes after while it stays away,
/// Parc installs and relaunches unless a restart would interrupt something.
/// The caller waits on awake time, which stops while the Mac sleeps: time
/// asleep doesn't count, awake time already spent away does.
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
        /// Seconds since the last keyboard, pointer or other input.
        var idleTime: TimeInterval = .infinity
    }

    ///
    static let delay: TimeInterval = 300
    ///
    static let requiredIdleTime: TimeInterval = 3

    private(set) var away: Set<Away> = []
    /// When the pending check is due; nil while the Mac is in use.
    private(set) var nextCheck: TimeInterval?

    /// The first reason starts an away period and returns its check's time.
    mutating func began(_ reason: Away, at now: TimeInterval) -> TimeInterval? {
        defer { away.insert(reason) }
        guard away.isEmpty else { return nil }
        nextCheck = now + Self.delay
        return nextCheck
    }

    mutating func ended(_ reason: Away) {
        away.remove(reason)
        if away.isEmpty { nextCheck = nil }
    }

    /// The check scheduled for `due` fired. If it is still the pending one it
    /// arms the next and returns its time, and the caller checks `allows`; a
    /// check from an away period that has ended returns nil.
    mutating func checkFired(due: TimeInterval, at now: TimeInterval) -> TimeInterval? {
        guard due == nextCheck else { return nil }
        nextCheck = now + Self.delay
        return nextCheck
    }

    ///
    ///
    /// being down, is the caller's request that follows.
    static func allows(_ activity: Activity) -> Bool {
        activity.enabled && activity.updateReady && !activity.pageInUse && !activity.downloading
            && !activity.dialogOpen && !activity.privateWindowOpen && activity.idleTime >= requiredIdleTime
    }
}
