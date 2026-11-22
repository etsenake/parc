import AppKit
import Testing
@testable import Parc
@testable import ParcKit

struct MenuCommandAvailabilityTests {
    @MainActor private final class Owner: NSWindow {
        var key = true
        override var isVisible: Bool { true }
        override var isKeyWindow: Bool { key }
    }

    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        let owner: Owner
        var received: NSMenuItem?
        var runs = 0
        init(owner: Owner) { self.owner = owner }
        @objc func showReleaseNotes(_ item: NSMenuItem) { received = item; runs += 1 }
        func validateMenuItem(_ item: NSMenuItem) -> Bool { owner.isKeyWindow }
    }

    @MainActor private final class Fixture {
        let owner: Owner
        let target: Target
        let menu = NSMenu(title: "Help")
        let item: NSMenuItem
        var mainWindow: NSWindow?
        lazy var registry = KeyboardShortcuts(mainMenu: { [weak self] in self?.menu },
            mainWindow: { [weak self] in self?.mainWindow }, applicationIsActive: { true }, observesKeyboardLayout: false)

        init() {
            _ = NSApplication.shared
            owner = Owner(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: .borderless, backing: .buffered, defer: false)
            owner.isReleasedWhenClosed = false
            mainWindow = owner
            target = Target(owner: owner)
            item = NSMenuItem(title: "Release Notes", action: #selector(Target.showReleaseNotes(_:)), keyEquivalent: "")
            item.target = target
            menu.addItem(item)
            registry.register(item, group: menu.title)
        }

        var row: KeyboardShortcuts.MenuCommand? { registry.menuCommands(in: owner).first }
    }

    @Test @MainActor func aCommandBarFieldDoesNotBlockACommandInItsOriginalWindow() throws {
        let fixture = Fixture()
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 22))
        fixture.owner.contentView?.addSubview(field)
        try #require(fixture.owner.makeFirstResponder(field))
        let row = try #require(fixture.row)
        #expect(fixture.registry.performMenuCommand(row))
        #expect(fixture.target.received === fixture.item)
    }

    @Test @MainActor func aWindowThatLostTheKeyRefusesTheCommand() throws {
        let fixture = Fixture()
        let row = try #require(fixture.row)
        fixture.owner.key = false
        #expect(!fixture.registry.performMenuCommand(row))
        #expect(fixture.target.received == nil)
    }

    @Test @MainActor func losingTheMainWindowRefusesTheCommand() throws {
        let fixture = Fixture()
        let row = try #require(fixture.row)
        fixture.mainWindow = nil
        #expect(!fixture.registry.canPerformMenuCommand(row))
    }

    @Test @MainActor func aRegistryChangeExpiresRetainedRows() throws {
        let fixture = Fixture()
        let retained = try #require(fixture.row)
        let item = NSMenuItem(title: "Settings", action: #selector(NSResponder.cancelOperation(_:)), keyEquivalent: "")
        fixture.registry.register(item, group: "Help")
        #expect(!fixture.registry.canPerformMenuCommand(retained))
        let fresh = try #require(fixture.row)
        #expect(fixture.registry.canPerformMenuCommand(fresh))
    }

    @Test @MainActor func removingAnItemRetiresItsCommand() throws {
        let fixture = Fixture()
        let retained = try #require(fixture.row)
        fixture.menu.removeItem(fixture.item)
        #expect(!fixture.registry.canPerformMenuCommand(retained))
        #expect(fixture.row == nil)
    }

    @Test @MainActor func aKeyGatedRowIsOfferedAndRunsOnceWhileTheFieldHasFocus() throws {
        let fixture = Fixture()
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 22))
        fixture.owner.contentView?.addSubview(field)
        try #require(fixture.owner.makeFirstResponder(field))
        let row = try #require(fixture.row)
        #expect(fixture.registry.canPerformMenuCommand(row))
        #expect(fixture.registry.performMenuCommand(row))
        #expect(fixture.target.runs == 1)
    }

    @Test @MainActor func aBrowserThatIsNotKeyIsNotOfferedTheRow() throws {
        let fixture = Fixture()
        let row = try #require(fixture.row)
        fixture.owner.key = false
        #expect(!fixture.registry.canPerformMenuCommand(row))
        #expect(!fixture.registry.performMenuCommand(row))
        #expect(fixture.target.runs == 0)
    }
}
