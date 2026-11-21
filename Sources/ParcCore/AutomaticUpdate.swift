import Foundation

package struct AutomaticUpdate {
    package enum Away: Hashable { case sleep, displaySleep, screenSaver, screenLock }

    package struct Activity {
        package var enabled = true
        package var updateReady = true
        package var pageInUse = false
        package var downloading = false
        package var dialogOpen = false
        package var privateWindowOpen = false
        package var idleTime: TimeInterval = .infinity
        package var displayKeptOn = false

        package init(enabled: Bool = true, updateReady: Bool = true, pageInUse: Bool = false, downloading: Bool = false, dialogOpen: Bool = false, privateWindowOpen: Bool = false, idleTime: TimeInterval = .infinity, displayKeptOn: Bool = false) {
            self.enabled = enabled
            self.updateReady = updateReady
            self.pageInUse = pageInUse
            self.downloading = downloading
            self.dialogOpen = dialogOpen
            self.privateWindowOpen = privateWindowOpen
            self.idleTime = idleTime
            self.displayKeptOn = displayKeptOn
        }
    }

    package static let delay: TimeInterval = 300
    package static let requiredIdleTime: TimeInterval = 3
    package static let idleAwayTime: TimeInterval = 1800

    package private(set) var away: Set<Away> = []
    package private(set) var awaySince: TimeInterval?

    package init(away: Set<Away> = [], awaySince: TimeInterval? = nil) {
        self.away = away
        self.awaySince = awaySince
    }

    package mutating func began(_ reason: Away, at now: TimeInterval) {
        if away.isEmpty { awaySince = now }
        away.insert(reason)
    }

    package mutating func ended(_ reason: Away) {
        away.remove(reason)
        if away.isEmpty { awaySince = nil }
    }

    package func isAway(at now: TimeInterval, _ activity: Activity) -> Bool {
        if let awaySince, now - awaySince >= Self.delay { return true }
        return activity.idleTime >= Self.idleAwayTime && !activity.displayKeptOn
    }

    package func allows(_ activity: Activity, at now: TimeInterval) -> Bool {
        isAway(at: now, activity) && activity.enabled && activity.updateReady
            && !activity.pageInUse && !activity.downloading && !activity.dialogOpen
            && !activity.privateWindowOpen && activity.idleTime >= Self.requiredIdleTime
    }
}
