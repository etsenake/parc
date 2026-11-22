import AppKit
import ParcTestSupport
import Testing
@testable import ParcCore
@testable import ParcKit
@testable import ParcCommandBar

struct TaskManagerTests {
    @MainActor private final class Window: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isVisible: Bool { true }
    }

    @MainActor private final class MenuTarget: NSObject, NSMenuItemValidation {
        var canOpen = true
        var opened = 0

        var route: TaskManagerRoute? {
            TaskManagerRoute.resolve(showsNativePage: false, pageCanOpen: false, windowCanOpen: canOpen)
        }

        func validateMenuItem(_ item: NSMenuItem) -> Bool { route != nil }

        @objc func openTaskManager(_ sender: NSMenuItem?) {
            _ = route?.perform(openPage: { false }, openWindow: { self.opened += 1; return true })
        }
    }

    @MainActor private final class Fixture {
        let window: Window
        let menu = NSMenu(title: "Window")
        let target = MenuTarget()
        let registry: KeyboardShortcuts
        let item: NSMenuItem

        init() {
            _ = NSApplication.shared
            window = Window(contentRect: NSRect(x: 0, y: 0, width: 450, height: 400), styleMask: .borderless,
                            backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let owner = window, root = menu
            registry = KeyboardShortcuts(mainMenu: { root }, mainWindow: { owner },
                                         applicationIsActive: { true }, observesKeyboardLayout: false)
            item = TaskManagerMenu.add(to: menu, target: target, shortcuts: registry)
        }

        func bar() throws -> CommandBar {
            let defaults = try #require(TestDefaults("Parc.TaskManagerTests."))
            let bar = CommandBar(parent: window, tabs: [], history: [], currentURL: nil, profilePath: "", page: nil,
                                 initialEdit: ("task manager", NSRange(location: 12, length: 0)), shortcuts: registry,
                                 privacyDefaults: defaults, makeOmnibox: { _, _, _ in nil }, loadFavicon: { _, _, _ in })
            bar.canPerformTypedCommand = { [target] in $0.kind == .openTaskManager && target.route != nil }
            bar.onPerformTypedCommand = { [target] _ in target.openTaskManager(nil) }
            bar.updateTypedCommands(CommandBarTypedCommand.windowTools)
            return bar
        }
    }

    @Test(arguments: [(false, false, true), (false, true, false), (true, true, false), (true, false, true)])
    func routingOnlyAsksTheOriginalSurface(showsPage: Bool, page: Bool, window: Bool) {
        var asked: [String] = []
        func answer(_ surface: String, _ value: Bool) -> Bool { asked.append(surface); return value }
        let route = TaskManagerRoute.resolve(showsNativePage: showsPage, pageCanOpen: answer("page", page),
                                             windowCanOpen: answer("window", window))
        #expect(asked == [showsPage ? "page" : "window"])
        let expected: TaskManagerRoute? = showsPage ? (page ? .page : nil) : (window ? .window : nil)
        #expect(route == expected)
    }

    @Test @MainActor func theWindowMenuRegistersTaskManagerWithoutADefaultBinding() {
        let fixture = Fixture()
        #expect(fixture.item.action == TaskManagerMenu.action)
        #expect(fixture.item.target === fixture.target)
        #expect(fixture.registry.commands.contains { command in
            command.id == "openTaskManager:" && command.group == "Window" && command.defaultShortcut == nil
        })
        #expect(fixture.registry.menuCommands(in: fixture.window).allSatisfy { $0.id != "openTaskManager:" })
    }

    @Test(arguments: [true, false])
    @MainActor func typedAvailabilityMatchesWindowMenuValidation(canOpen: Bool) throws {
        let fixture = Fixture()
        fixture.target.canOpen = canOpen
        fixture.menu.update()
        let bar = try fixture.bar()
        let table = NSTableView()
        #expect(fixture.item.isEnabled == canOpen)
        let labels = (0..<bar.numberOfRows(in: table)).compactMap { row in
            (bar.tableView(table, viewFor: nil, row: row) as? CommandResultCell)?.accessibilityLabel()
        }
        #expect(labels.filter { $0 == "Open Task Manager" }.count == (canOpen ? 1 : 0))
    }

    @Test @MainActor func theTypedCommandOpensTaskManagerWithoutAPage() throws {
        let fixture = Fixture()
        let bar = try fixture.bar()
        let row = try #require(bar.tableView(NSTableView(), rowViewForRow: 0) as? CommandResultRowView)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        #expect(row.onPress?(event) == true)
        #expect(fixture.target.opened == 1)
    }

    @Test @MainActor func aTaskManagerBindingCanBeAssignedAndReset() throws {
        let fixture = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        fixture.registry.configure(directory: directory)
        let shortcut = KeyboardShortcut(key: "t", flags: [.command, .option, .control])
        try fixture.registry.set(shortcut, for: "openTaskManager:")
        #expect(fixture.item.keyEquivalent == shortcut.key)
        #expect(fixture.item.keyEquivalentModifierMask == shortcut.flags)
        try fixture.registry.reset("openTaskManager:")
        #expect(fixture.item.keyEquivalent.isEmpty)
        #expect(fixture.item.keyEquivalentModifierMask.isEmpty)
    }
}
