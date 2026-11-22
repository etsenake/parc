import AppKit

enum TaskManagerRoute: Equatable {
    case page, window

    static func resolve(showsNativePage: Bool, pageCanOpen: @autoclosure () -> Bool,
                        windowCanOpen: @autoclosure () -> Bool) -> TaskManagerRoute? {
        if showsNativePage { return pageCanOpen() ? .page : nil }
        return windowCanOpen() ? .window : nil
    }
    func perform(openPage: () -> Bool, openWindow: () -> Bool) -> Bool {
        switch self {
        case .page: openPage()
        case .window: openWindow()
        }
    }
}

@MainActor
enum TaskManagerMenu {
    static let title = "Task Manager"
    static let action = NSSelectorFromString("openTaskManager:")

    @discardableResult
    static func add(to menu: NSMenu, target: AnyObject, shortcuts: KeyboardShortcuts) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = target
        menu.addItem(entry)
        shortcuts.register(entry, group: menu.title, discoverable: false)
        return entry
    }
}
