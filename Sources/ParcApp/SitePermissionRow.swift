import Foundation

struct SitePermissionRow: Equatable {
    static let systemSettingsTitle = "Settings"
    static let systemSettingsHelp = "Location is off for Parc in macOS. Open System Settings to turn it on."

    let id: String
    let title: String
    let index: Int
    let revision: UInt
    let allowed: Bool
    let changeable: Bool
    let systemSettings: Bool

    init?(_ row: [String: Any]) {
        guard let title = row["title"] as? String, let key = row["key"] as? String,
              let index = row["index"] as? Int, let revision = row["revision"] as? UInt else { return nil }
        id = "permission:" + key
        self.title = title
        self.index = index
        self.revision = revision
        allowed = row["allowed"] as? Bool ?? false
        changeable = row["changeable"] as? Bool ?? false
        systemSettings = allowed && row["systemSettings"] as? Bool == true
    }

    var subtitle: String { systemSettings ? "Off in macOS" : allowed ? "Allowed" : "Blocked" }
    var accessibilityValue: String {
        systemSettings ? "Allowed for this site, but off for Parc in macOS System Settings" : subtitle
    }

    static func ordered(_ rows: [[String: Any]]) -> [SitePermissionRow] {
        (rows.filter { $0["autoPictureInPicture"] as? Bool == true }
            + rows.filter { $0["autoPictureInPicture"] as? Bool != true }).compactMap(SitePermissionRow.init)
    }
}
