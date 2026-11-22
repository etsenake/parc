import Foundation
import ParcCore

@MainActor
package enum SidebarRescue {
    enum Trouble { case unreadable, missing }

    package struct Offer: Equatable {
        let trouble: Trouble
        let date: Date
        let skippedNewer: Bool
        let now: Date
    }

    struct Wording: Equatable {
        let title: String
        let message: String
        let alternative: String
    }

    struct NoBackup: LocalizedError {
        let underlying: Error
        let backupsExist: Bool
        var errorDescription: String? {
            "Parc couldn’t read the file that holds your saved sidebar, "
                + (backupsExist ? "and none of its backups can be read either. They may be damaged, or saved by a newer version of Parc. "
                                : "and there’s no backup to restore it from. ")
                + underlying.localizedDescription
        }
    }

    package static func openStore(at root: URL, keepsBackups: Bool, interactive: Bool, now: @escaping () -> Date = Date.init,
                          ask: @MainActor (Offer) -> Bool? = confirm) throws -> BrowserStore? {
        var tried = Set<URL>()
        if interactive, keepsBackups,
           !FileManager.default.fileExists(atPath: root.appendingPathComponent("session.json").path),
           let newest = SessionBackups.restorable(in: root).first {
            let date = now()
            if ask(offer(.missing, newest.backup, in: root, tried: tried, now: date)) == true {
                try SessionBackups.restore(newest.data, in: root, at: date)
                tried.insert(newest.backup.url)
            }
        }
        while true {
            do {
                return try BrowserStore(directory: root, now: now, keepsBackups: keepsBackups)
            } catch let failure as SessionFileUnreadable {
                guard interactive else { throw failure }
                let candidates = SessionBackups.restorable(in: root).filter { !tried.contains($0.backup.url) }
                guard let newest = candidates.first else {
                    throw NoBackup(underlying: failure.underlying, backupsExist: !SessionBackups.list(in: root).isEmpty)
                }
                let date = now()
                guard let restore = ask(offer(.unreadable, newest.backup, in: root, tried: tried, now: date)) else {
                    throw failure
                }
                guard restore else { return nil }
                try SessionBackups.restore(newest.data, in: root, at: date)
                tried.insert(newest.backup.url)
            }
        }
    }

    private static func offer(_ trouble: Trouble, _ backup: SessionBackups.Backup, in root: URL,
                              tried: Set<URL>, now: Date) -> Offer {
        let skippedNewer = SessionBackups.list(in: root).contains { $0.isNewer(than: backup) && !tried.contains($0.url) }
        return Offer(trouble: trouble, date: backup.date, skippedNewer: skippedNewer, now: now)
    }

    static func confirm(_ offer: Offer) -> Bool? {
        let text = wording(for: offer)
        var response: CFOptionFlags = 0
        let status = CFUserNotificationDisplayAlert(0, kCFUserNotificationCautionAlertLevel, nil, nil, nil,
                                                    text.title as CFString, text.message as CFString,
                                                    "Restore Backup" as CFString, text.alternative as CFString,
                                                    nil, &response)
        guard status == 0 else { return nil }
        return response & 0x3 == kCFUserNotificationDefaultResponse
    }

    static func wording(for offer: Offer) -> Wording {
        let age = backupAge(offer.date, now: offer.now)
        switch offer.trouble {
        case .unreadable:
            return Wording(title: "Parc couldn’t read your saved sidebar",
                           message: "The file that holds your Spaces, pinned tabs, folders and Favorites couldn’t be read. "
                               + "It may be damaged, or saved by a newer version of Parc. "
                               + backupSentence(age: age, skippedNewer: offer.skippedNewer, either: true)
                               + "Restoring it keeps the unreadable file in Parc’s folder, so nothing is deleted.",
                           alternative: "Quit")
        case .missing:
            return Wording(title: "Parc couldn’t find your saved sidebar",
                           message: "The file that holds your Spaces, pinned tabs, folders and Favorites is missing from Parc’s folder. "
                               + backupSentence(age: age, skippedNewer: offer.skippedNewer, either: false)
                               + "You can restore it, or start with an empty sidebar.",
                           alternative: "Start Empty")
        }
    }

    private static func backupSentence(age: String?, skippedNewer: Bool, either: Bool) -> String {
        let subject = skippedNewer
            ? "Newer backups couldn’t be read" + (either ? " either" : "") + ", so the most recent one that works"
            : "The most recent backup"
        guard let age else { return subject + " is dated after your Mac’s current time; its age isn’t known. " }
        return subject + " is from \(age). "
    }

    static func backupAge(_ date: Date, now: Date) -> String? {
        let elapsed = now.timeIntervalSince(date)
        if elapsed <= -60 { return nil }
        if elapsed < 60 { return "a moment ago" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
