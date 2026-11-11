import Foundation

struct AutomaticUpdate {
    enum Away: Hashable { case sleep, displaySleep, screenSaver, screenLock }

    struct Activity {
        var enabled = true
        var updateReady = true
        var pageInUse = false
        var downloading = false
        var dialogOpen = false
        var privateWindowOpen = false
        var idleTime: TimeInterval = .infinity
        var displayKeptOn = false
    }

    static let delay: TimeInterval = 300
    static let requiredIdleTime: TimeInterval = 3
    static let idleAwayTime: TimeInterval = 1800

    private(set) var away: Set<Away> = []
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

    func allows(_ activity: Activity, at now: TimeInterval) -> Bool {
        isAway(at: now, activity) && activity.enabled && activity.updateReady
            && !activity.pageInUse && !activity.downloading && !activity.dialogOpen
            && !activity.privateWindowOpen && activity.idleTime >= Self.requiredIdleTime
    }
}
