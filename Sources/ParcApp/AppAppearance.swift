import AppKit

@MainActor
enum AppAppearance: String, CaseIterable {
    case automatic, light, dark

    static let header = "Websites, Easels, and Notes will use:"
    private static let defaultsKey = "parc.appAppearance.v1"

    var title: String {
        switch self { case .automatic: return "Automatic"; case .light: return "Light"; case .dark: return "Dark" }
    }
    var selector: Selector {
        switch self {
        case .automatic: return NSSelectorFromString("setAutomaticAppearance:")
        case .light: return NSSelectorFromString("setLightAppearance:")
        case .dark: return NSSelectorFromString("setDarkAppearance:")
        }
    }
    static func forSelector(_ selector: Selector?) -> AppAppearance? { allCases.first { $0.selector == selector } }

    private var appearance: NSAppearance? {
        switch self {
        case .automatic: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    static var current: AppAppearance {
        switch NSApp.appearance?.name {
        case NSAppearance.Name.aqua?: return .light
        case NSAppearance.Name.darkAqua?: return .dark
        default: return .automatic
        }
    }

    static func restore(defaults: UserDefaults = .standard) {
        guard let raw = defaults.string(forKey: defaultsKey), let saved = AppAppearance(rawValue: raw) else { return }
        NSApp.appearance = saved.appearance
    }

    static func preview(_ value: AppAppearance) { NSApp.appearance = value.appearance }

    @discardableResult static func endPreview(_ applied: AppAppearance, defaults: UserDefaults = .standard) -> Bool {
        guard current == applied else { return false }
        let saved = defaults.string(forKey: defaultsKey).flatMap(AppAppearance.init(rawValue:)) ?? .automatic
        NSApp.appearance = saved.appearance
        return true
    }

    @discardableResult static func apply(_ value: AppAppearance, defaults: UserDefaults = .standard) -> Bool {
        let changed = value != current
        if changed { NSApp.appearance = value.appearance }
        if value == .automatic { defaults.removeObject(forKey: defaultsKey) }
        else { defaults.set(value.rawValue, forKey: defaultsKey) }
        return changed
    }

    static func addMenu(to view: NSMenu, target: AnyObject) {
        let menu = NSMenu(title: "")
        let header = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for value in allCases {
            let item = NSMenuItem(title: value.title, action: value.selector, keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        let root = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        root.submenu = menu
        view.addItem(root)
    }
}
