import AppKit

@MainActor private final class WindowMenuTarget: NSObject {
    @objc func openTaskManager(_ sender: Any?) {}
    @objc func downloads(_ sender: Any?) {}
}

@main @MainActor struct TaskManagerTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        var asked: [String] = []
        func answer(_ route: String, _ value: Bool) -> Bool { asked.append(route); return value }
        func route(showsPage: Bool, page: Bool, window: Bool) -> TaskManagerRoute? {
            asked = []
            return TaskManagerRoute.resolve(showsNativePage: showsPage, pageCanOpen: answer("page", page),
                                            windowCanOpen: answer("window", window))
        }
        expect(route(showsPage: false, page: false, window: true) == .window && asked == ["window"],
               "With no page showing, the window opens Task Manager without asking a page")
        expect(route(showsPage: false, page: true, window: false) == nil && asked == ["window"],
               "With no page showing, a window that can't open it means it isn't offered")
        expect(route(showsPage: true, page: true, window: false) == .page && asked == ["page"],
               "A showing page keeps its own route")
        expect(route(showsPage: true, page: false, window: true) == nil && asked == ["page"],
               "A page that refuses isn't bypassed through the window")

        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-task-manager-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = KeyboardShortcuts(); registry.configure(directory: root)
        let main = NSMenu(), parent = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window"); parent.submenu = windowMenu; main.addItem(parent)
        NSApp.mainMenu = main
        let target = WindowMenuTarget()
        let downloads = NSMenuItem(title: "View Downloads", action: #selector(WindowMenuTarget.downloads(_:)), keyEquivalent: "j")
        downloads.keyEquivalentModifierMask = [.command, .shift]; downloads.target = target
        windowMenu.addItem(downloads); registry.register(downloads, group: windowMenu.title)

        let item = TaskManagerMenu.add(to: windowMenu, target: target, shortcuts: registry)
        expect(windowMenu.items.last === item && item.title == "Task Manager", "Window gains a Task Manager item")
        expect(item.action == #selector(WindowMenuTarget.openTaskManager(_:)) && item.target === target,
               "The item sends openTaskManager: to the app's menu target")
        expect(item.keyEquivalent.isEmpty && registry.shortcut(for: "openTaskManager:") == nil, "Task Manager has no default shortcut")
        let command = registry.commands.first { $0.id == "openTaskManager:" }
        expect(command?.title == "Task Manager" && command?.group == "Window" && command?.defaultShortcut == nil,
               "Settings → Shortcuts lists it under Window with no default")

        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [], backing: .buffered, defer: true)
        host.isReleasedWhenClosed = false
        let rows = registry.menuCommands(in: host).map(\.id)
        expect(rows.contains("downloads:"), "Other Window items still appear as command-bar rows")
        expect(!rows.contains("openTaskManager:"), "The command bar keeps a single Task Manager row, its typed command")

        let chord = KeyboardShortcut(key: "t", flags: [.command, .option, .control])
        try registry.set(chord, for: "openTaskManager:")
        expect(registry.shortcut(for: "openTaskManager:") == chord && item.keyEquivalent == "t"
               && item.keyEquivalentModifierMask == chord.flags, "A shortcut assigned in Settings lands on the menu item")
        try registry.reset("openTaskManager:")
        expect(item.keyEquivalent.isEmpty && item.keyEquivalentModifierMask.isEmpty, "Resetting it leaves the item without a key")
        print("TaskManagerTests: \(count) assertions passed")
    }
}
