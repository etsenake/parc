import AppKit
import Testing
@testable import Parc

struct EssentialsTests {
    @MainActor private final class Owner: NSWindow {
        var key = true
        var shown = true
        var testSheet: NSWindow?
        override var isKeyWindow: Bool { key }
        override var isVisible: Bool { shown }
        override var attachedSheet: NSWindow? { testSheet }

        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: 475, height: 388), styleMask: .borderless,
                       backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let menu = NSMenu(title: "Commands")
        let registry: KeyboardShortcuts
        let controller: ShortcutEssentialsWindow

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let root = menu
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            let bindings: [(String, String, NSEvent.ModifierFlags)] = [
                ("newTab:", "t", .command), ("cycleToNextRecentTab:", "\t", .control),
                ("copyCurrentURL:", "c", [.command, .shift]), ("split:", "=", [.control, .shift]),
            ]
            for (id, key, flags) in bindings {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = flags
                menu.addItem(item)
                registry.register(item, group: menu.title)
            }
            registry.configure(directory: directory)
            controller = ShortcutEssentialsWindow(shortcuts: registry)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func surface() throws -> NSView { try #require(controller.window?.contentView) }

        func summary() throws -> NSAccessibilityElement {
            try #require(surface().accessibilityChildren()?.compactMap { $0 as? NSAccessibilityElement }.first)
        }

        func cap(for id: String) throws -> ShortcutKeycapView {
            let index = try #require(ShortcutEssentialsWindow.commandIDs.firstIndex(of: id))
            let caps = try surface().subviews.compactMap { $0 as? ShortcutKeycapView }
            try #require(caps.indices.contains(index))
            return caps[index]
        }
    }

    static let commands = ["newTab:", "cycleToNextRecentTab:", "copyCurrentURL:", "split:"]

    @Test(arguments: commands)
    @MainActor func eachLessonShowsItsLiveShortcut(id: String) throws {
        let fixture = try Fixture()
        let cap = try fixture.cap(for: id)
        let expected = try #require(fixture.registry.activeShortcut(for: id)?.spokenDisplay)
        #expect(cap.accessibilityValue() as? String == expected)
        #expect(!cap.acceptsFirstResponder)
    }

    @Test @MainActor func theRecentTabLessonSpellsOutTab() throws {
        let fixture = try Fixture()
        let cap = try fixture.cap(for: "cycleToNextRecentTab:")
        #expect(cap.symbols == ["⌃", "TAB"])
    }

    @Test @MainActor func aChangedShortcutUpdatesTheOpenLessonAndItsInstructions() throws {
        let fixture = try Fixture()
        let cap = try fixture.cap(for: "newTab:")
        let summary = try fixture.summary()
        try fixture.registry.set(KeyboardShortcut(key: " ", flags: .control), for: "newTab:")
        #expect(cap.accessibilityValue() as? String == "⌃Space")
        #expect((summary.accessibilityValue() as? String)?.contains("⌃Space") == true)
    }

    @Test @MainActor func aDisabledShortcutLeavesNoMisleadingInstruction() throws {
        let fixture = try Fixture()
        try fixture.registry.set(nil, for: "newTab:")
        let cap = try fixture.cap(for: "newTab:")
        let summary = try fixture.summary()
        #expect(cap.isHidden)
        #expect((summary.accessibilityValue() as? String)?.contains("Open a New Tab") == false)
    }

    @Test @MainActor func conflictingShortcutsDisappearFromTheLesson() throws {
        let fixture = try Fixture()
        let chord = try #require(fixture.registry.activeShortcut(for: "copyCurrentURL:"))
        try fixture.registry.set(chord, for: "newTab:")
        let newTab = try fixture.cap(for: "newTab:")
        let copy = try fixture.cap(for: "copyCurrentURL:")
        #expect(newTab.isHidden && copy.isHidden)
    }

    @Test @MainActor func theInstructionSummaryIsPassive() throws {
        let fixture = try Fixture()
        let summary = try fixture.summary()
        #expect(summary.accessibilityRole() == .staticText)
        #expect(summary.accessibilityChildren()?.isEmpty == true)
        #expect(!summary.accessibilityPerformPress())
    }

    @Test(arguments: [(false, false, true, EssentialsCopyRoute.unavailable), (true, false, true, .commandWindow),
                      (true, true, true, .currentURL), (true, false, false, .currentURL)])
    func theCopyRouteUsesTheOriginalAddressSource(url: Bool, bar: Bool, page: Bool, expected: EssentialsCopyRoute) {
        #expect(EssentialsCopyRoute(hasURL: url, commandBarOpen: bar, hasNativePage: page) == expected)
    }

    @Test(arguments: commands, [true, false])
    @MainActor func anEssentialsCommandRequiresTheSameWindowAdmission(id: String, admitted: Bool) {
        _ = NSApplication.shared
        let registry = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
        let controller = ShortcutEssentialsWindow(shortcuts: registry)
        let original = Owner()
        controller.window = original
        controller.isOwnerAvailable = { admitted }
        var invoked: [String] = []
        controller.onCommand = { invoked.append($0); _ = $1 }
        #expect(controller.canActivateCommand(id) == admitted)
        #expect(controller.activateCommand(id) == admitted)
        #expect(invoked == (admitted ? [id] : []))
    }

    @Test(arguments: [true, false])
    @MainActor func copyChecksItsCommandWindowCapabilityAfterItOwnsThePresentation(canCopy: Bool) {
        _ = NSApplication.shared
        let controller = ShortcutEssentialsWindow(shortcuts: KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false))
        let original = Owner()
        controller.window = original
        var checks: [String] = []
        controller.isOwnerAvailable = { true }
        controller.canPerformCommand = { checks.append($0); return canCopy }
        #expect(controller.activateCommand("copyCurrentURL:") == canCopy)
        #expect(checks == ["copyCurrentURL:"])
    }
}
