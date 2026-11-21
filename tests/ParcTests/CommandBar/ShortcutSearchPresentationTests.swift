import AppKit
import Testing
@testable import Parc

struct ShortcutSearchPresentationTests {
    @MainActor private final class Window: NSWindow {
        var acceptsCommands = true
        override var isKeyWindow: Bool { acceptsCommands }
        override var isVisible: Bool { true }
    }

    @MainActor private final class Fixture {
        let registry: KeyboardShortcuts
        let view: ShortcutsSettingsView
        let window: Window
        let header: ShortcutSearchHeader
        let clear: ShortcutSearchClearControl
        let table: NSTableView

        init() throws {
            _ = NSApplication.shared
            let menu = NSMenu(title: "Tabs")
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            for (title, id, key) in [("Archive Tab", "closeTab:", "w"), ("Open Extensions", "extensions:", "e")] {
                let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = .command
                menu.addItem(item)
                registry.register(item, group: "Tabs")
            }
            view = ShortcutsSettingsView(shortcuts: registry)
            window = Window(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            header = try #require(view.subviews.compactMap { $0 as? ShortcutSearchHeader }.first)
            clear = try #require(header.subviews.compactMap { $0 as? ShortcutSearchClearControl }.first)
            let scroll = try #require(view.subviews.compactMap { $0 as? NSScrollView }.first)
            table = try #require(scroll.documentView as? NSTableView)
            view.layoutSubtreeIfNeeded()
        }

        var field: NSTextField { header.field }

        func enter(_ text: String) throws -> NSTextView {
            try #require(window.makeFirstResponder(field))
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.insertText(text, replacementRange: NSRange(location: 0, length: 0))
            return editor
        }
    }

    @Test @MainActor func keyboardInputFiltersTheActualShortcutTable() throws {
        let fixture = try Fixture()
        #expect(fixture.clear.isHidden)
        _ = try fixture.enter("extensions")
        #expect(fixture.table.numberOfRows == 2)
        #expect(!fixture.clear.isHidden)
    }

    @Test @MainActor func clearingSearchRestoresTheResultsAndKeepsTheEditor() throws {
        let fixture = try Fixture()
        let editor = try fixture.enter("extensions")
        let revision = fixture.registry.revision
        fixture.clear.performPress()
        #expect(editor.string.isEmpty)
        #expect(fixture.window.firstResponder === editor)
        #expect(fixture.table.numberOfRows == 3)
        #expect(fixture.registry.revision == revision)
    }

    enum Obstacle: CaseIterable { case keyLoss, hidden, detached }

    @Test(arguments: Obstacle.allCases)
    @MainActor func aRetiredSearchOwnerCannotClearItsQuery(obstacle: Obstacle) throws {
        let fixture = try Fixture()
        _ = try fixture.enter("extensions")
        switch obstacle {
        case .keyLoss: fixture.window.acceptsCommands = false
        case .hidden: fixture.view.isHidden = true
        case .detached: fixture.window.contentView = nil
        }
        fixture.clear.performPress()
        #expect(fixture.field.stringValue == "extensions")
    }

    @Test @MainActor func aHeaderRefreshPreservesMarkedText() throws {
        let fixture = try Fixture()
        let editor = try fixture.enter("")
        editor.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let range = editor.markedRange()
        fixture.header.refresh()
        fixture.header.layoutSubtreeIfNeeded()
        #expect(editor.hasMarkedText())
        #expect(editor.markedRange() == range)
    }

    @Test @MainActor func aShortcutCueRevealsItsCommandThroughAnOldSearch() throws {
        let fixture = try Fixture()
        _ = try fixture.enter("does not match")
        let revision = fixture.registry.revision
        #expect(fixture.view.selectCommand("extensions:"))
        #expect(fixture.field.stringValue.isEmpty)
        #expect(fixture.table.selectedRow >= 0)
        #expect(fixture.registry.revision == revision)
    }

    @Test @MainActor func aSearchGroupHeaderCannotBeSelected() throws {
        let fixture = try Fixture()
        #expect(fixture.table.delegate?.tableView?(fixture.table, isGroupRow: 0) == true)
        #expect(fixture.table.delegate?.tableView?(fixture.table, shouldSelectRow: 0) == false)
    }

    @Test @MainActor func theClearButtonDoesNotOverlapTheEditor() throws {
        let fixture = try Fixture()
        _ = try fixture.enter("extensions")
        fixture.header.layoutSubtreeIfNeeded()
        #expect(fixture.field.frame.maxX < fixture.clear.frame.minX)
    }
}

extension ShortcutSearchPresentationTests {
    @Test @MainActor func revealingAnUnknownCommandKeepsTheCurrentSearch() throws {
        let fixture = try Fixture()
        _ = try fixture.enter("extensions")
        #expect(!fixture.view.selectCommand("missing:"))
        #expect(fixture.field.stringValue == "extensions")
    }

    @Test @MainActor func revealingACommandDoesNotBeginRecording() throws {
        let fixture = try Fixture()
        _ = try fixture.enter("does not match")
        try #require(fixture.view.selectCommand("extensions:"))
        let recordings = (0..<fixture.table.numberOfRows)
            .compactMap { fixture.table.view(atColumn: 0, row: $0, makeIfNecessary: true) }
            .flatMap(\.subviews).compactMap { $0 as? ShortcutRecorderView }
        #expect(!recordings.isEmpty)
        #expect(!recordings.contains { $0.isRecording })
    }
}
