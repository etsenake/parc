import AppKit
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcCommandBar

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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let menu = NSMenu(title: "Tabs")
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
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

        deinit { try? FileManager.default.removeItem(at: directory) }

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

extension ShortcutSearchPresentationTests {
    @MainActor private func scroll(_ fixture: Fixture) throws -> NSScrollView {
        try #require(fixture.view.subviews.compactMap { $0 as? NSScrollView }.first)
    }

    @MainActor private func icon(_ fixture: Fixture) throws -> NSImageView {
        try #require(fixture.header.subviews.compactMap { $0 as? NSImageView }.first)
    }

    @Test @MainActor func theHeaderSitsAboveTheFullHeightList() throws {
        let fixture = try Fixture()
        #expect(fixture.header.frame == NSRect(x: 20, y: 84, width: 340, height: 41))
        #expect(fixture.field.frame == NSRect(x: 33, y: 8, width: 291, height: 24))
        let scroll = try scroll(fixture)
        #expect(scroll.frame.minY == fixture.header.frame.maxY)
        #expect(scroll.frame.maxY == 534)
    }

    @Test @MainActor func theSearchFieldIsAPlainSingleLineEditor() throws {
        let fixture = try Fixture()
        let field = fixture.field
        #expect(field.cell is NSTextFieldCell)
        #expect(!(field.cell is NSSearchFieldCell))
        #expect(!field.isBordered && !field.isBezeled && !field.drawsBackground)
        #expect(field.focusRingType == .none)
        #expect(field.maximumNumberOfLines == 1 && field.usesSingleLineMode)
        #expect(field.isEditable && field.isSelectable)
        #expect(field.accessibilityLabel() == "Search actions or shortcuts")
    }

    @Test @MainActor func theSearchImageIsNotASecondInputOwner() throws {
        let fixture = try Fixture()
        #expect(!(try icon(fixture)).acceptsFirstResponder)
    }

    @Test @MainActor func theSectionHeaderAndCommandRowsKeepTheirHeights() throws {
        let fixture = try Fixture()
        #expect(fixture.table.rect(ofRow: 0).height == 29)
        #expect(fixture.table.rect(ofRow: 1).height == 58)
        #expect(fixture.table.rect(ofRow: 2).height == 48)
    }

    @Test @MainActor func aCommandRowUsesBodyTextWithItsFullTitleAsHelp() throws {
        let fixture = try Fixture()
        let cell = try #require(fixture.table.view(atColumn: 0, row: 1, makeIfNecessary: true))
        let title = try #require(cell.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(title.font?.pointSize == NSFont.systemFontSize)
        #expect(title.frame.minX == 22)
        #expect(title.frame.width == 200)
        #expect(title.toolTip == "Archive Tab")
    }

    @Test @MainActor func aSelectedRowOwnsTheContinuousAccentShapeUntilItIsDeselected() throws {
        let fixture = try Fixture()
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let rowView = try #require(fixture.table.rowView(atRow: 1, makeIfNecessary: true))
        rowView.layoutSubtreeIfNeeded()
        let selection = try #require(rowView.layer?.sublayers?.first)
        #expect(selection.cornerRadius == 8)
        #expect(selection.cornerCurve == .continuous)
        #expect(selection.frame.height == 40)
        #expect(selection.frame.minX == 16)
        #expect(abs((selection.backgroundColor?.alpha ?? 0) - 0.1) < 0.001)
        fixture.table.deselectAll(nil)
        rowView.layoutSubtreeIfNeeded()
        #expect(selection.isHidden)
    }

    @Test @MainActor func theClearControlSitsEightPointsAfterTheFieldAndKeepsItsIdentityOnRefresh() throws {
        let fixture = try Fixture()
        _ = try fixture.enter("extensions")
        fixture.header.layoutSubtreeIfNeeded()
        #expect(fixture.field.frame.maxX + 8 == fixture.clear.frame.minX)
        fixture.header.refresh()
        #expect(fixture.header.subviews.contains { $0 === fixture.clear })
        #expect(fixture.clear.rootView.presentation.present)
        #expect(fixture.clear.rootView.presentation.active)
    }

    @Test @MainActor func theBasicsButtonActsOnlyWhileItsWindowIsKey() throws {
        let fixture = try Fixture()
        let banner = try #require(fixture.view.subviews.compactMap { $0 as? ShortcutBasicsBanner }.first)
        var actions = 0
        banner.onPress = { actions += 1 }
        banner.performPress()
        #expect(actions == 1)
        fixture.window.acceptsCommands = false
        banner.performPress()
        fixture.clear.refreshPresence()
        #expect(actions == 1)
        #expect(!fixture.clear.rootView.presentation.active)
    }

    @Test @MainActor func aDetachedViewRetiresTheClearSubtreeAndRefusesTheBasicsButton() throws {
        let fixture = try Fixture()
        _ = try fixture.enter("extensions")
        let banner = try #require(fixture.view.subviews.compactMap { $0 as? ShortcutBasicsBanner }.first)
        var actions = 0
        banner.onPress = { actions += 1 }
        let revision = fixture.registry.revision
        fixture.window.contentView = nil
        fixture.clear.performPress()
        banner.performPress()
        #expect(!fixture.clear.rootView.presentation.present)
        #expect(!fixture.clear.rootView.presentation.active)
        #expect(actions == 0)
        #expect(fixture.field.stringValue == "extensions")
        #expect(fixture.registry.revision == revision)
    }

    @Test @MainActor func appearanceAndLayoutChangesKeepTheEditorsSelection() throws {
        let fixture = try Fixture()
        let editor = try fixture.enter("extensions")
        let responder = fixture.window.firstResponder
        editor.setSelectedRange(NSRange(location: 1, length: 3))
        fixture.header.appearance = NSAppearance(named: .aqua)
        fixture.header.layoutSubtreeIfNeeded()
        #expect(fixture.window.firstResponder === responder)
        #expect(editor.selectedRange() == NSRange(location: 1, length: 3))
    }

    @Test @MainActor func clearingKeepsTheCaretAndFocusAndHidesTheControl() throws {
        let fixture = try Fixture()
        let editor = try fixture.enter("extensions")
        let responder = fixture.window.firstResponder
        editor.setSelectedRange(NSRange(location: 1, length: 3))
        fixture.clear.performPress()
        #expect(fixture.field.stringValue.isEmpty)
        #expect(editor.string.isEmpty)
        #expect(fixture.clear.isHidden)
        #expect(fixture.window.firstResponder === responder)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test @MainActor func theCurrentOwnerCanStillClearAfterARefusedAttempt() throws {
        let fixture = try Fixture()
        _ = try fixture.enter("command")
        fixture.window.acceptsCommands = false
        fixture.clear.performPress()
        #expect(fixture.field.stringValue == "command")
        fixture.window.acceptsCommands = true
        fixture.view.isHidden = true
        fixture.clear.performPress()
        #expect(fixture.field.stringValue == "command")
        fixture.view.isHidden = false
        fixture.clear.performPress()
        #expect(fixture.field.stringValue.isEmpty)
    }

    @Test(arguments: [(NSAppearance.Name.aqua, 0.93, 0.561), (NSAppearance.Name.darkAqua, 0.158, 0.439)])
    @MainActor func theSeparatorAndSearchImageFollowTheAppearance(name: NSAppearance.Name, rule: Double, ink: Double) throws {
        let fixture = try Fixture()
        fixture.header.appearance = NSAppearance(named: name)
        let bitmap = try #require(fixture.header.bitmapImageRepForCachingDisplay(in: fixture.header.bounds))
        fixture.header.cacheDisplay(in: fixture.header.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / fixture.header.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / fixture.header.bounds.height
        let sample = try #require(bitmap.colorAt(x: Int((170 + 0.5) * scaleX), y: Int((40 + 0.5) * scaleY)))
        #expect(abs(sample.redComponent - rule) < 0.02)
        let tint = try #require(try icon(fixture).contentTintColor?.usingColorSpace(.sRGB))
        #expect(abs(tint.redComponent - ink) < 0.01)
    }

    @Test @MainActor func aChangedBindingFilesUnderTheCustomizedSectionAndItsSelectedConflictIsRed() throws {
        let fixture = try Fixture()
        try fixture.registry.set(KeyboardShortcut(key: "w", flags: .command), for: "extensions:")
        #expect(fixture.view.selectCommand("extensions:"))
        let section = try #require(fixture.table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        #expect(section.subviews.compactMap { $0 as? NSTextField }.first?.stringValue == "Customized Shortcuts")
        let rowView = try #require(fixture.table.rowView(atRow: fixture.table.selectedRow, makeIfNecessary: true))
        rowView.layoutSubtreeIfNeeded()
        let layer = try #require(rowView.layer?.sublayers?.first)
        #expect(abs((layer.backgroundColor?.alpha ?? 0) - 0.2) < 0.001)
        #expect(fixture.registry.isConflicting("extensions:"))
        #expect(fixture.registry.isConflicting("closeTab:"))
    }
}
