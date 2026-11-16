import Foundation

@MainActor
enum SidebarRescue {
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

    static func openStore(at root: URL, keepsBackups: Bool, interactive: Bool) throws -> BrowserStore? {
        var tried = Set<URL>()
        while true {
            do {
                return try BrowserStore(directory: root, keepsBackups: keepsBackups)
            } catch let failure as SessionFileUnreadable {
                guard interactive else { throw failure }
                let backups = SessionBackups.list(in: root)
                let candidates = SessionBackups.restorable(in: root).filter { !tried.contains($0.backup.url) }
                guard let newest = candidates.first else {
                    throw NoBackup(underlying: failure.underlying, backupsExist: !backups.isEmpty)
                }
                let now = Date()
                let skippedNewer = backups.contains { $0.date > newest.backup.date && !tried.contains($0.url) }
                guard let restore = confirmRestore(from: newest.backup.date, skippedNewer: skippedNewer, now: now) else {
                    throw failure
                }
                guard restore else { return nil }
                try SessionBackups.restore(newest.data, in: root, at: now)
                tried.insert(newest.backup.url)
            }
        }
    }

    static func confirmRestore(from date: Date, skippedNewer: Bool, now: Date) -> Bool? {
        let age = backupAge(date, now: now)
        let message = "The file that holds your Spaces, pinned tabs, folders and Favorites couldn’t be read. "
            + "It may be damaged, or saved by a newer version of Parc. "
            + (skippedNewer ? "Newer backups couldn’t be read either, so the most recent one that works is from \(age). "
                            : "The most recent backup is from \(age). ")
            + "Restoring it keeps the unreadable file in Parc’s folder, so nothing is deleted."
        var response: CFOptionFlags = 0
        let status = CFUserNotificationDisplayAlert(0, kCFUserNotificationCautionAlertLevel, nil, nil, nil,
                                                    "Parc couldn’t read your saved sidebar" as CFString,
                                                    message as CFString, "Restore Backup" as CFString,
                                                    "Quit" as CFString, nil, &response)
        guard status == 0 else { return nil }
        return response & 0x3 == kCFUserNotificationDefaultResponse
    }

    static func backupAge(_ date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 0 { return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short) }
        if elapsed < 60 { return "a moment ago" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
