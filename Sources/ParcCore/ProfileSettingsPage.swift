import Foundation

package enum ProfileSettingsPage: String, CaseIterable {
    case search, privacy, passwords, payments, notifications, clearBrowsingData

    package var title: String {
        switch self {
        case .search: return "Search Settings…"
        case .privacy: return "Privacy and Security"
        case .passwords: return "Passwords"
        case .payments: return "Credit Cards"
        case .notifications: return "Notifications"
        case .clearBrowsingData: return "Clear Browsing Data"
        }
    }

    package var address: String {
        switch self {
        case .search: return "parc://settings/searchEngines"
        case .privacy: return "parc://settings/privacy"
        case .passwords: return "parc://password-manager/passwords"
        case .payments: return "parc://settings/payments"
        case .notifications: return "parc://settings/content/notifications"
        case .clearBrowsingData: return "parc://settings/clearBrowserData"
        }
    }

    package func canReuse(_ address: String) -> Bool {
        guard let url = URL(string: address), BrowserInternalURL.isWebUI(url),
              let destination = URL(string: self.address), url.host == destination.host,
              url.user == nil, url.password == nil, url.port == nil else { return false }
        return self == .passwords || (url.path == destination.path && url.query == nil && url.fragment == nil)
    }
}
