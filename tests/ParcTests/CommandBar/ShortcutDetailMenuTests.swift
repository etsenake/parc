import AppKit
import Carbon.HIToolbox
import Testing
@testable import ParcCore
@testable import ParcKit
@testable import ParcCommandBar

extension ShortcutDetailTestsSupport {
    struct ShortcutDetailMenuTests {
        @MainActor private func rowMenu(_ fixture: Fixture, row id: String = "closeTab:") throws -> NSMenu {
            let table = try table(fixture.view)
            let row = try #require((0..<table.numberOfRows).first { row in
                table.view(atColumn: 0, row: row, makeIfNecessary: true)?.subviews.contains {
                    ($0 as? ShortcutRecorderView)?.identifier?.rawValue == id
                } == true
            })
            let frame = table.rect(ofRow: row)
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
                location: table.convert(NSPoint(x: 20, y: frame.midY), to: nil), modifierFlags: [],
                timestamp: 1, windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
            return try #require(table.menu(for: event))
        }

        @Test @MainActor func aConsumedRemoveMenuCannotChangeTheBindingAgain() throws {
            let fixture = try Fixture()
            let item = try fixture.removeAction()
            try fixture.invoke(item)
            let revision = fixture.registry.revision
            try fixture.invoke(item)
            #expect(fixture.registry.revision == revision)
        }

        @Test @MainActor func resettingAnUnboundCommandRestoresTheRealMenuBinding() throws {
            let fixture = try Fixture()
            try fixture.registry.set(nil, for: "closeTab:")
            let reset = try #require(fixture.view.commandMenu(for: "closeTab:")?.items.last)
            try #require(reset.isEnabled)
            try fixture.invoke(reset)
            #expect(fixture.registry.shortcut(for: "closeTab:") == KeyboardShortcut(key: "w", flags: .command))
        }

        @Test @MainActor func aRowsContextMenuNeverSelectsItsRowOrChangesTheDetail() throws {
            let fixture = try Fixture()
            fixture.view.selectCommand("captureFullPage:")
            let selected = fixture.caps.accessibilityValue() as? String
            let table = try table(fixture.view)
            let previous = table.selectedRow
            let menu = try rowMenu(fixture)
            #expect(table.selectedRow == previous)
            #expect(menu.items.map(\.title) == ["Remove Shortcut", "Reset Shortcut to Default"])
            #expect(menu.items[0].isEnabled && !menu.items[1].isEnabled)
            #expect(fixture.caps.accessibilityValue() as? String == selected)
        }

        @Test @MainActor func removingFromAnotherRowsMenuLeavesTheSelectedDetailAndCannotRunTwice() throws {
            let fixture = try Fixture()
            fixture.view.selectCommand("captureFullPage:")
            let selected = fixture.caps.accessibilityValue() as? String
            let menu = try rowMenu(fixture)
            try fixture.invoke(menu.items[0])
            #expect(fixture.registry.shortcut(for: "closeTab:") == nil)
            #expect(fixture.caps.accessibilityValue() as? String == selected)
            let revision = fixture.registry.revision
            try fixture.invoke(menu.items[0])
            #expect(fixture.registry.revision == revision)
        }

        @Test @MainActor func aDisabledShortcutOffersOnlyResetAndResettingDoesNotSelectAnotherCommand() throws {
            let fixture = try Fixture()
            fixture.view.selectCommand("captureFullPage:")
            let selected = fixture.caps.accessibilityValue() as? String
            try fixture.registry.set(nil, for: "closeTab:")
            let menu = try #require(fixture.view.commandMenu(for: "closeTab:"))
            #expect(!menu.items[0].isEnabled && menu.items[1].isEnabled)
            try fixture.invoke(menu.items[1])
            #expect(fixture.registry.shortcut(for: "closeTab:")?.key == "w")
            #expect(fixture.caps.accessibilityValue() as? String == selected)
        }

        @Test @MainActor func aConcurrentRegistryChangeInvalidatesTheMenuReceipt() throws {
            let fixture = try Fixture()
            let stale = try #require(fixture.view.commandMenu(for: "closeTab:"))
            try fixture.registry.set(KeyboardShortcut(key: "q", flags: [.command, .control]), for: "captureFullPage:")
            try fixture.invoke(stale.items[0])
            #expect(fixture.registry.shortcut(for: "closeTab:") != nil)
        }

        @Test @MainActor func aFailedDurableRemovalRetainsTheBinding() throws {
            let fixture = try Fixture()
            let failing = try #require(fixture.view.commandMenu(for: "closeTab:"))
            let backup = fixture.directory.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: fixture.directory, to: backup)
            try Data("blocked".utf8).write(to: fixture.directory)
            try fixture.invoke(failing.items[0])
            let retained = fixture.registry.shortcut(for: "closeTab:") != nil
            try FileManager.default.removeItem(at: fixture.directory)
            try FileManager.default.moveItem(at: backup, to: fixture.directory)
            #expect(retained)
        }

        @Test @MainActor func aHiddenSettingsOwnerRejectsTheMenuAction() throws {
            let fixture = try Fixture()
            let hidden = try #require(fixture.view.commandMenu(for: "closeTab:"))
            fixture.view.isHidden = true
            try fixture.invoke(hidden.items[0])
            #expect(fixture.registry.shortcut(for: "closeTab:") != nil)
        }

        @Test @MainActor func aReparentedSettingsOwnerRejectsTheMenuAction() throws {
            let fixture = try Fixture()
            let reparented = try #require(fixture.view.commandMenu(for: "closeTab:"))
            let other = Window(contentRect: fixture.view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false
            fixture.window.contentView = nil
            other.contentView = fixture.view
            try fixture.invoke(reparented.items[0])
            #expect(fixture.registry.shortcut(for: "closeTab:") != nil)
        }

        @Test @MainActor func resettingAnotherRowRestoresItsDefaultShowsBothConflictsAndKeepsTheSelection() throws {
            let fixture = try Fixture()
            try fixture.registry.set(KeyboardShortcut(key: "k", flags: [.command, .control]), for: "closeTab:")
            try fixture.registry.set(KeyboardShortcut(key: "w", flags: .command), for: "captureFullPage:")
            fixture.view.selectCommand("captureFullPage:")
            let menu = try #require(fixture.view.commandMenu(for: "closeTab:"))
            let before = fixture.registry.revision
            try fixture.invoke(menu.items[1])
            #expect(fixture.registry.revision == before + 1 && fixture.caps.isInConflict)
            #expect(labels(fixture).contains { $0.stringValue == "Capture Full Page" })
            let action = try #require(fixture.view.commandMenu(for: "closeTab:")?.items.first { $0.title == "Remove Conflicting Shortcut" })
            try fixture.invoke(action)
            #expect(fixture.registry.shortcut(for: "closeTab:")?.key == "w")
            #expect(fixture.registry.shortcut(for: "captureFullPage:") == nil)
            #expect(!fixture.caps.isInConflict)
        }
    }
}
