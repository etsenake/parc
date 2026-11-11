import Foundation

enum SidebarPreviewPreference: String, CaseIterable {
    case folders = "sidebar.preview.folders", recentPages = "sidebar.preview.recentPages"
    case tabPictures = "sidebar.preview.tabPictures"

    static let didChangeNotification = Notification.Name("ParcSidebarPreviewPreferencesDidChange")

    var settingsTitle: String {
        switch self {
        case .folders: return "Parc Folders"
        case .recentPages: return "Recent pages on Notion, Figma, Linear, and Confluence"
        case .tabPictures: return "A picture of other open tabs"
        }
    }

    var isEnabled: Bool {
        get { isEnabled(in: .standard) }
        nonmutating set { setEnabled(newValue, in: .standard) }
    }

    func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: rawValue) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool, in defaults: UserDefaults) {
        guard isEnabled(in: defaults) != enabled else { return }
        defaults.set(enabled, forKey: rawValue)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }
}
