import Foundation

struct SuperCopyUpsell {
    static let lastSeenKey = "superCopyUpsellLastSeen"
    static let prefix = "Copy links faster by pressing"
    let defaults: UserDefaults
    var calendar = Calendar.current
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func message(copied: String, pageURL: String?, shortcut: KeyboardShortcut?, now: Date = Date()) -> String? {
        guard let pageURL, !pageURL.isEmpty, copied == pageURL, let shortcut else { return nil }
        if let last = defaults.object(forKey: Self.lastSeenKey) as? Date,
           (calendar.dateComponents([.day], from: last, to: now).day ?? 0) < 2 { return nil }
        return "\(Self.prefix) \(shortcut.display)"
    }
    func recordShown(now: Date = Date()) { defaults.set(now, forKey: Self.lastSeenKey) }
}

extension ParcToastContent {
    static func superCopyUpsell(shortcut: String, message: String) -> ParcToastContent {
        ParcToastContent(body: .shortcut(leading: SuperCopyUpsell.prefix, shortcut: shortcut, trailing: nil),
                        accessibilityText: message)
    }
}
