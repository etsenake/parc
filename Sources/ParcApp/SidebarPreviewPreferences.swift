import Foundation

enum SidebarPreviewPreference: String, CaseIterable {
    case folders = "sidebar.preview.folders", recentPages = "sidebar.preview.recentPages"

    static let didChangeNotification = Notification.Name("ParcSidebarPreviewPreferencesDidChange")

    var title: String {
        self == .folders ? "Folder previews" : "Recent pages in Notion, Figma, Linear and Confluence"
    }

    var settingsTitle: String {
        self == .folders ? "Parc Folders" : "Recent pages on Notion, Figma, Linear, and Confluence"
    }

    var isEnabled: Bool {
        get { isEnabled(in: .standard) }
        nonmutating set { setEnabled(newValue, in: .standard) }
    }

    func isEnabled(in defaults: UserDefaults) -> Bool {
        // Keep existing installations and their original fallback intact.
        defaults.object(forKey: rawValue) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool, in defaults: UserDefaults) {
        guard isEnabled(in: defaults) != enabled else { return }
        defaults.set(enabled, forKey: rawValue)
        // Reconcile every live preview and sidebar action before returning to
        // the event loop. UserDefaults also supplies its ordinary notification.
        NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }
}
