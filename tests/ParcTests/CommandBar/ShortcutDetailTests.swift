import AppKit
import Carbon.HIToolbox
import Testing
@testable import Parc
@testable import ParcCore

struct ShortcutDetailTests {
    @MainActor private final class Window: NSWindow {
        var permitsCommands = true
        override var isKeyWindow: Bool { permitsCommands }
        override var isVisible: Bool { true }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "Parc.ShortcutDetail." + UUID().uuidString
        let registry: KeyboardShortcuts
        let view: ShortcutsSettingsView
        let window: Window
        let caps: ShortcutKeycapView
        let picker: NSPopUpButton
        let defaults: UserDefaults

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let menu = NSMenu(title: "File")
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
            for (id, title, key) in [("closeTab:", "Archive Tab", "w"), ("captureFullPage:", "Capture Full Page", ""), ("capturePage:", "Capture Portion…", "2"),
                                       ("nextSplitPane:", "Switch to next Split View", "")] {
                let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = .command
                menu.addItem(item)
                registry.register(item, group: menu.title)
            }
            for number in [1, 9] {
                let item = NSMenuItem(title: "Go to Sidebar Item " + String(number),
                    action: NSSelectorFromString("goToSidebarItem:"), keyEquivalent: String(number))
                item.keyEquivalentModifierMask = .command
                menu.addItem(item)
                registry.register(item, group: "Tabs", bindingID: NumberedTarget.itemBindingID(number))
            }
            defaults = try #require(UserDefaults(suiteName: suite))
            view = ShortcutsSettingsView(shortcuts: registry, numberedTargetDefaults: defaults)
            window = Window(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            caps = try #require(view.subviews.compactMap { $0 as? ShortcutKeycapView }.first)
            picker = try #require(view.subviews.compactMap { $0 as? NSPopUpButton }.first)
        }

        deinit {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        func removeAction() throws -> NSMenuItem {
            try #require(view.commandMenu(for: "closeTab:")?.items.first { $0.title == "Remove Shortcut" })
        }

        func button(_ title: String) throws -> NSButton {
            let matches = view.subviews.compactMap { $0 as? NSButton }
            return try #require(matches.first { $0.title == title })
        }

        func invoke(_ item: NSMenuItem) throws {
            _ = NSApp.sendAction(try #require(item.action), to: item.target, from: item)
        }
    }

    @Test @MainActor func theIntroductionShowsArtworkWithoutABinding() throws {
        let fixture = try Fixture()
        #expect(fixture.caps.presentation == .introduction)
        #expect(fixture.caps.symbols.isEmpty)
        #expect(fixture.caps.accessibilityValue() as? String == "Customize keyboard shortcuts")
        #expect(fixture.picker.isHidden)
    }

    @Test(arguments: ["closeTab:", "captureFullPage:"])
    @MainActor func detailShowsTheSelectedCommandsRealBinding(id: String) throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand(id))
        let chord = fixture.registry.shortcut(for: id)
        #expect(fixture.caps.presentation == (chord == nil ? .unassigned : .binding))
        #expect(fixture.caps.accessibilityValue() as? String == (chord?.spokenDisplay ?? "No shortcut"))
        #expect(fixture.picker.isHidden == (chord == nil))
    }

    @Test @MainActor func aSavedConflictLeavesPriorityEditable() throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand("captureFullPage:"))
        let duplicate = try #require(fixture.registry.shortcut(for: "closeTab:"))
        let tables = fixture.view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTableView }
        let table = try #require(tables.first)
        let recorders = (0..<table.numberOfRows).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true) }
            .flatMap(\.subviews).compactMap { $0 as? ShortcutRecorderView }
        let recorder = try #require(recorders.first { $0.identifier?.rawValue == "captureFullPage:" })
        try #require(recorder.onChange?(duplicate) == true)
        #expect(fixture.caps.isInConflict)
        #expect(!fixture.picker.isHidden)
        #expect(fixture.picker.isEnabled)
    }

    @Test(arguments: [false, true])
    @MainActor func aShortcutMenuNeedsTheOriginalKeyWindow(key: Bool) throws {
        let fixture = try Fixture()
        let item = try fixture.removeAction()
        fixture.window.permitsCommands = key
        try fixture.invoke(item)
        #expect((fixture.registry.shortcut(for: "closeTab:") == nil) == key)
    }

    @Test @MainActor func aMenuReceiptCannotRemoveALaterBinding() throws {
        let fixture = try Fixture()
        let item = try fixture.removeAction()
        let latest = KeyboardShortcut(key: "j", flags: [.control, .command])
        try fixture.registry.set(latest, for: "closeTab:")
        try fixture.invoke(item)
        #expect(fixture.registry.shortcut(for: "closeTab:") == latest)
    }

    @Test @MainActor func editingAnUnselectedRowKeepsTheSelectedDetail() throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand("captureFullPage:"))
        let before = fixture.caps.accessibilityValue() as? String
        try fixture.invoke(fixture.removeAction())
        #expect(fixture.registry.shortcut(for: "closeTab:") == nil)
        #expect(fixture.caps.accessibilityValue() as? String == before)
    }
}

extension ShortcutDetailTests {
    @Test(arguments: [(1, false, true, false), (9, false, false, true), (9, true, true, true)])
    @MainActor func numberedItemSettingsMatchTheSelectedCommand(number: Int, ninthMode: Bool,
                                                                 showsFavorites: Bool, showsNinth: Bool) throws {
        let fixture = try Fixture()
        fixture.defaults.set(ninthMode, forKey: NumberedTarget.ninthItemKey)
        try #require(fixture.view.selectCommand(NumberedTarget.itemBindingID(number)))
        let favorites = try fixture.button("Include Favorites in ordering.")
        let ninth = try fixture.button("Switch to ninth tab.")
        #expect(favorites.isHidden == !showsFavorites)
        #expect(ninth.isHidden == !showsNinth)
    }

    @Test @MainActor func theNinthItemTogglePersistsAndRevealsFavoritesOrdering() throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand(NumberedTarget.itemBindingID(9)))
        let favorites = try fixture.button("Include Favorites in ordering.")
        let ninth = try fixture.button("Switch to ninth tab.")
        ninth.sendClick()
        #expect(fixture.defaults.bool(forKey: NumberedTarget.ninthItemKey))
        #expect(!favorites.isHidden)
        #expect(ninth.frame.maxY <= favorites.frame.minY)
    }

    @Test(arguments: [false, true])
    @MainActor func theCaptureDragControlDoesNotChangeTheKeyboardBinding(unassigned: Bool) throws {
        let fixture = try Fixture()
        if unassigned { try fixture.registry.set(nil, for: "capturePage:") }
        let binding = fixture.registry.shortcut(for: "capturePage:")
        try #require(fixture.view.selectCommand("capturePage:"))
        let drag = try fixture.button("Hold Command and Shift to start a Capture.")
        try #require(!drag.isHidden)
        drag.sendClick()
        #expect(!CaptureGesturePreference.isEnabled(defaults: fixture.defaults))
        #expect(fixture.registry.shortcut(for: "capturePage:") == binding)
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
}

extension ShortcutDetailTests {
    @MainActor private func labels(_ fixture: Fixture) -> [NSTextField] { fixture.view.subviews.compactMap { $0 as? NSTextField } }

    @MainActor private func table(_ view: ShortcutsSettingsView) throws -> NSTableView {
        let found: NSTableView? = view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTableView }.first
        return try #require(found)
    }

    @MainActor private func cell(_ id: String, in view: ShortcutsSettingsView) throws -> NSView {
        let table = try table(view)
        let found = (0..<table.numberOfRows).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true) }.first {
            $0.subviews.contains { ($0 as? ShortcutRecorderView)?.identifier?.rawValue == id }
        }
        return try #require(found)
    }

    @MainActor private func recorder(_ id: String, in view: ShortcutsSettingsView) throws -> ShortcutRecorderView {
        try #require(try cell(id, in: view).subviews.compactMap { $0 as? ShortcutRecorderView }.first)
    }

    @Test @MainActor func theIntroductionKeepsItsOriginalGeometry() throws {
        let fixture = try Fixture()
        let all = labels(fixture)
        let heading = try #require(all.first { $0.stringValue == "Custom Shortcuts" })
        let explanation = try #require(all.first { $0.stringValue.hasPrefix("Change shortcuts") })
        #expect(fixture.caps.frame.size == NSSize(width: 200, height: 64))
        #expect(heading.font?.pointSize == 14)
        #expect(heading.frame.minY == fixture.caps.frame.maxY + 24)
        #expect(explanation.frame.height > 40)
        #expect(explanation.frame.minY == heading.frame.maxY + 8)
    }

    @Test @MainActor func theFirstSelectionDrawsTheSameWrappedDescriptionAsAReselection() throws {
        let fixture = try Fixture()
        let explanation = try #require(labels(fixture).first { $0.stringValue.hasPrefix("Change shortcuts") })
        let search = try #require(fixture.view.subviews.compactMap { $0 as? ShortcutSearchHeader }.first).field
        fixture.window.makeFirstResponder(search)
        let responder = fixture.window.firstResponder
        func rendered() throws -> Data {
            let bitmap = try #require(explanation.bitmapImageRepForCachingDisplay(in: explanation.bounds))
            explanation.cacheDisplay(in: explanation.bounds, to: bitmap)
            return Data(bytes: try #require(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        try #require(fixture.view.selectCommand("closeTab:"))
        let frame = explanation.frame
        let first = try rendered()
        #expect(first.contains { $0 != 0 })
        fixture.view.selectCommand("captureFullPage:")
        fixture.view.selectCommand("closeTab:")
        #expect(explanation.frame == frame)
        #expect(try rendered() == first)
        #expect(fixture.window.firstResponder === responder)
    }

    @Test @MainActor func selectingAnUnassignedCommandNeverStartsARecorderOrStealsSearchFocus() throws {
        let fixture = try Fixture()
        let search = try #require(fixture.view.subviews.compactMap { $0 as? ShortcutSearchHeader }.first).field
        fixture.window.makeFirstResponder(search)
        let responder = fixture.window.firstResponder
        try #require(fixture.view.selectCommand("captureFullPage:"))
        #expect(fixture.caps.presentation == .unassigned)
        #expect(fixture.caps.accessibilityValue() as? String == "No shortcut")
        #expect(fixture.picker.isHidden)
        #expect(fixture.window.firstResponder === responder)
    }

    @Test @MainActor func aModifierPreviewDoesNotCreatePriorityForAnUnassignedAction() throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand("captureFullPage:"))
        let recorder = try recorder("captureFullPage:", in: fixture.view)
        recorder.onBegin?()
        recorder.onPreview?(["⌘"])
        #expect(fixture.caps.presentation == .binding)
        #expect(fixture.picker.isHidden)
    }

    @Test @MainActor func aRecordedConflictPublishesOneRevisionAndSurvivesEndingCapture() throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand("captureFullPage:"))
        let recorder = try recorder("captureFullPage:", in: fixture.view)
        let duplicate = try #require(fixture.registry.shortcut(for: "closeTab:"))
        recorder.onBegin?()
        let revision = fixture.registry.revision
        #expect(recorder.onChange?(duplicate) == true)
        #expect(fixture.registry.revision == revision + 1)
        #expect(fixture.registry.shortcut(for: "captureFullPage:") == duplicate)
        fixture.view.endRecording()
        #expect(fixture.caps.isInConflict && fixture.registry.isConflicting("closeTab:"))
    }

    @Test @MainActor func aBoundActionShowsItsBindingWithNaturalDividerSpacing() throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand("closeTab:"))
        let divider = try #require(fixture.view.subviews.compactMap { $0 as? NSBox }.first)
        let description = try #require(labels(fixture).filter { !$0.isHidden && $0.frame.maxY < divider.frame.minY }
            .max { $0.frame.maxY < $1.frame.maxY })
        #expect(fixture.caps.presentation == .binding)
        #expect(fixture.caps.symbols == ["⌘", "W"])
        #expect(!fixture.picker.isHidden && fixture.picker.isEnabled)
        #expect(divider.frame.minY == description.frame.maxY + 24)
        #expect(!fixture.caps.acceptsFirstResponder && fixture.caps.hitTest(.zero) == nil)
    }

    @Test(arguments: [(1, 64.0), (2, 64.0), (3, 64.0), (4, 47.75), (5, 37.6)])
    @MainActor func theKeycapColumnSizesByKeyCount(count: Int, side: Double) {
        #expect(abs(ShortcutKeycapView.largeSide(width: 200, count: count) - side) < 0.001)
    }

    @Test @MainActor func theDetailFollowsEachBindingChange() throws {
        let fixture = try Fixture()
        let wide = KeyboardShortcut(key: "k", flags: [.command, .option, .control, .shift])
        try fixture.registry.set(wide, for: "closeTab:")
        fixture.view.selectCommand("closeTab:")
        #expect(fixture.caps.symbols == wide.symbols)
        #expect(fixture.caps.accessibilityValue() as? String == wide.spokenDisplay)
        try fixture.registry.set(KeyboardShortcut(key: " ", flags: .control), for: "closeTab:")
        fixture.view.selectCommand("closeTab:")
        #expect(fixture.caps.symbols == ["⌃", "⎵"])
        #expect(fixture.caps.accessibilityValue() as? String == "⌃Space")
        try fixture.registry.set(KeyboardShortcut(key: "\t", flags: .control), for: "closeTab:")
        fixture.view.selectCommand("closeTab:")
        #expect(fixture.caps.symbols == ["⌃", "⇥"])
        try fixture.registry.set(nil, for: "closeTab:")
        fixture.view.selectCommand("closeTab:")
        #expect(fixture.caps.presentation == .unassigned && fixture.picker.isHidden)
        try fixture.registry.reset("closeTab:")
        fixture.view.selectCommand("closeTab:")
        #expect(fixture.caps.presentation == .binding && !fixture.picker.isHidden)
    }

    @Test @MainActor func splitCommandsCarryTheirShortcutDescription() throws {
        let fixture = try Fixture()
        #expect(fixture.view.selectCommand("nextSplitPane:"))
        #expect(labels(fixture).contains { $0.stringValue == "Jumps to the next Split View page in your current window." })
    }

    @Test @MainActor func firstEightItemsExposeIncludedFavoritesAndLastItemExposesOnlyTheNinthToggle() throws {
        let fixture = try Fixture()
        let favorites = try fixture.button("Include Favorites in ordering.")
        let ninth = try fixture.button("Switch to ninth tab.")
        #expect(fixture.view.selectCommand("item1"))
        #expect(!favorites.isHidden && ninth.isHidden && favorites.state == .on)
        #expect(fixture.view.selectCommand("item9"))
        #expect(favorites.isHidden && !ninth.isHidden && ninth.state == .off)
    }

    @Test @MainActor func theFavoritesToggleSavesItsInverseRefreshesTheDescriptionAndSharesTheOrdering() throws {
        let fixture = try Fixture()
        let favorites = try fixture.button("Include Favorites in ordering.")
        let ninth = try fixture.button("Switch to ninth tab.")
        fixture.view.selectCommand("item9")
        ninth.sendClick()
        #expect(!favorites.isHidden && ninth.frame.maxY < favorites.frame.minY)
        favorites.sendClick()
        #expect(fixture.defaults.bool(forKey: NumberedTarget.excludeFavoritesKey))
        #expect(labels(fixture).contains { $0.stringValue.contains("after your Favorites") })
        ninth.sendClick()
        #expect(favorites.isHidden && fixture.defaults.bool(forKey: NumberedTarget.excludeFavoritesKey))
        #expect(fixture.view.selectCommand("item1"))
        #expect(favorites.state == .off && !favorites.isHidden && ninth.isHidden)
    }

    @Test @MainActor func numberedControlsLeaveTheStatusFieldVisibleAtTheLongestPriorityDescription() throws {
        let fixture = try Fixture()
        let favorites = try fixture.button("Include Favorites in ordering.")
        let ninth = try fixture.button("Switch to ninth tab.")
        fixture.view.selectCommand("item9")
        ninth.sendClick()
        try fixture.registry.setPriority(.useBoth, for: "item9")
        fixture.view.selectCommand("item9")
        let status = try #require(labels(fixture).first { $0.accessibilityLabel() == "Shortcut status" })
        #expect(favorites.frame.maxY < status.frame.minY && status.frame.height > 0)
    }

    @Test @MainActor func anUnrelatedCommandRemovesTheNumberedControls() throws {
        let fixture = try Fixture()
        let favorites = try fixture.button("Include Favorites in ordering.")
        let ninth = try fixture.button("Switch to ninth tab.")
        fixture.view.selectCommand("item1")
        fixture.view.selectCommand("closeTab:")
        #expect(favorites.isHidden && ninth.isHidden)
    }

    @Test @MainActor func theCaptureDragControlIsEnabledByDefaultAndScopedToItsCommand() throws {
        let fixture = try Fixture()
        let drag = try fixture.button("Hold Command and Shift to start a Capture.")
        #expect(fixture.view.selectCommand("capturePage:"))
        #expect(!drag.isHidden && drag.state == .on)
        fixture.view.selectCommand("closeTab:")
        #expect(drag.isHidden)
    }

    @Test @MainActor func enablingTheDragNeverRecreatesAClearedChordAndFitsAboveFeedback() throws {
        let fixture = try Fixture()
        let drag = try fixture.button("Hold Command and Shift to start a Capture.")
        try fixture.registry.set(nil, for: "capturePage:")
        fixture.view.selectCommand("capturePage:")
        #expect(!drag.isHidden && drag.state == .on && fixture.picker.isHidden)
        drag.sendClick()
        drag.sendClick()
        #expect(CaptureGesturePreference.isEnabled(defaults: fixture.defaults))
        #expect(fixture.registry.shortcut(for: "capturePage:") == nil)
        let status = try #require(labels(fixture).first { $0.accessibilityLabel() == "Shortcut status" })
        #expect(drag.frame.height > 20 && drag.frame.maxY < status.frame.minY)
    }

    @Test(arguments: [
        (NSEvent.ModifierFlags([.command, .shift]), true), (NSEvent.ModifierFlags([.command, .shift, .option, .control]), true),
        (NSEvent.ModifierFlags.command, false), (NSEvent.ModifierFlags.shift, false),
    ])
    func theDragMaskRequiresBothFlagsAndAllowsExtras(flags: NSEvent.ModifierFlags, permitted: Bool) {
        #expect(CaptureGesturePreference.permits(flags) == permitted)
    }

    @Test @MainActor func filteringTheSelectedActionAwayRestoresTheIntroduction() throws {
        let fixture = try Fixture()
        let search = try #require(fixture.view.subviews.compactMap { $0 as? ShortcutSearchHeader }.first).field
        fixture.view.selectCommand("closeTab:")
        search.stringValue = "not an action"
        fixture.view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        #expect(fixture.caps.presentation == .introduction)
        #expect(fixture.picker.isHidden)
    }
}

extension ShortcutDetailTests {
    private static func artwork() throws -> ShortcutSmileyArtwork {
        let url = try #require(Bundle.module.url(forResource: "smiley", withExtension: "json", subdirectory: "CommandBarFixtures"))
        return try #require(ShortcutSmileyArtwork(data: Data(contentsOf: url)))
    }

    private static func pixels(_ artwork: ShortcutSmileyArtwork, _ seconds: Double) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        artwork.draw(in: NSRect(x: 0, y: 0, width: 100, height: 100), seconds: seconds, context: context)
        return Data(bytes: try #require(context.data), count: 40000)
    }

    @Test func theBundledWinkTimelineIsThirtyFramesForFiveSeconds() throws {
        let artwork = try Self.artwork()
        #expect(artwork.frameRate == 30 && artwork.duration == 5)
    }

    @Test func faceEyesAndMouthChangeTheRenderedVectors() throws {
        let artwork = try Self.artwork()
        let initial = try Self.pixels(artwork, 0), middle = try Self.pixels(artwork, 1), final = try Self.pixels(artwork, 5)
        #expect(initial != middle && middle != final)
    }

    @Test func thePlayOnceEndpointClampsAndTheInitialFrameIsStable() throws {
        let artwork = try Self.artwork()
        #expect(try Self.pixels(artwork, 5) == Self.pixels(artwork, 50))
        #expect(try Self.pixels(artwork, 0) == Self.pixels(artwork, -1))
    }

    @Test func theFaceRendersThreeStrokesWithEyesInPlaceAndNoSolidRectangle() throws {
        let initial = try Self.pixels(Self.artwork(), 0)
        let covered = stride(from: 3, to: initial.count, by: 4).filter { initial[$0] != 0 }
        #expect(covered.count > 500 && covered.count < 1800)
        #expect(initial[(60 * 100 + 39) * 4 + 3] > 0 && initial[(60 * 100 + 60) * 4 + 3] > 0)
    }

    @Test @MainActor func theAnimatedDecorationIsPassiveAndHiddenFromAccessibility() {
        _ = NSApplication.shared
        let smiley = ShortcutSmileyView(frame: .zero)
        #expect(!smiley.acceptsFirstResponder && smiley.hitTest(.zero) == nil && !smiley.isAccessibilityElement())
    }
}

extension ShortcutDetailTests {
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

    @Test @MainActor func aHiddenOrReparentedSettingsOwnerRejectsTheMenuAction() throws {
        let fixture = try Fixture()
        let hidden = try #require(fixture.view.commandMenu(for: "closeTab:"))
        fixture.view.isHidden = true
        try fixture.invoke(hidden.items[0])
        #expect(fixture.registry.shortcut(for: "closeTab:") != nil)
        fixture.view.isHidden = false
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

extension ShortcutDetailTests {
    private static func hotKey(_ code: Int, _ modifiers: Int, enabled: Bool = true) -> [String: Any] {
        [kHISymbolicHotKeyCode as String: code, kHISymbolicHotKeyModifiers as String: modifiers,
         kHISymbolicHotKeyEnabled as String: enabled]
    }

    @Test @MainActor func onlyCompleteEnabledTranslatedSystemShortcutsWarn() {
        let chord = KeyboardShortcut(key: " ", flags: [.control, .option, .command, .shift])
        let records = [Self.hotKey(49, controlKey | optionKey | cmdKey | shiftKey), Self.hotKey(49, cmdKey, enabled: false),
                       Self.hotKey(-1, cmdKey), Self.hotKey(65536, cmdKey), Self.hotKey(49, 0),
                       [kHISymbolicHotKeyEnabled as String: true]]
        #expect(KeyboardShortcut.systemShortcuts(records: records) == [chord])
    }

    @Test(arguments: [(123, "\u{f702}"), (122, "\u{f704}")])
    @MainActor func systemArrowAndFunctionKeysKeepTheirPhysicalIdentity(code: Int, key: String) {
        #expect(KeyboardShortcut.systemShortcuts(records: [Self.hotKey(code, controlKey)]) == [KeyboardShortcut(key: key, flags: .control)])
    }

    @Test(arguments: [(2, "and one other action"), (3, "and 2 other actions")])
    @MainActor func conflictHelpCountsTheOtherOwners(owners: Int, suffix: String) {
        let other = KeyboardShortcuts.Command(id: "other", title: "Other", group: "File", defaultShortcut: nil)
        let chord = KeyboardShortcut(key: " ", flags: [.control, .option, .command, .shift])
        #expect(ShortcutsSettingsView.conflictDescription(chord, conflicts: Array(repeating: other, count: owners)).hasSuffix(suffix))
    }

    @MainActor private final class SnapshotBox {
        var value: Set<KeyboardShortcut>
        init(_ value: Set<KeyboardShortcut>) { self.value = value }
    }

    @MainActor private final class Warnings {
        let fixture: Fixture
        let box: SnapshotBox
        let view: ShortcutsSettingsView
        let window: Window

        init() throws {
            let fixture = try Fixture()
            let closeBinding = try #require(fixture.registry.shortcut(for: "closeTab:"))
            let box = SnapshotBox([closeBinding])
            self.fixture = fixture
            self.box = box
            view = ShortcutsSettingsView(shortcuts: fixture.registry, systemShortcutProvider: { box.value })
            window = Window(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
        }
    }

    @Test @MainActor func aMatchingSystemRecordShowsAPassiveWarningAndAnUnassignedActionShowsNone() throws {
        let warnings = try Warnings()
        let help = "System shortcuts may take priority over this shortcut"
        #expect(try cell("closeTab:", in: warnings.view).subviews.contains { ($0 as? NSImageView)?.toolTip == help })
        #expect(try !cell("captureFullPage:", in: warnings.view).subviews.contains { $0 is NSImageView })
    }

    @Test @MainActor func aBrowserConflictTakesPrecedenceAndItsRevealNeverSelectsOrStealsFocus() throws {
        let warnings = try Warnings()
        let registry = warnings.fixture.registry
        let search = try #require(warnings.view.subviews.compactMap { $0 as? ShortcutSearchHeader }.first).field
        warnings.view.selectCommand("captureFullPage:")
        let proposed = try recorder("captureFullPage:", in: warnings.view)
        proposed.onBegin?()
        let closeBinding = try #require(registry.shortcut(for: "closeTab:"))
        #expect(proposed.onChange?(closeBinding) == true)
        let conflicted = try cell("captureFullPage:", in: warnings.view)
        let reveal = try #require(conflicted.subviews.compactMap { $0 as? NSButton }.first)
        #expect(reveal.frame.size == NSSize(width: 16, height: 16) && reveal.contentTintColor == .systemRed)
        #expect(!conflicted.subviews.contains { $0 is NSImageView })
        #expect(reveal.toolTip?.contains("Archive Tab") == true)
        warnings.window.makeFirstResponder(search)
        let responder = warnings.window.firstResponder
        let table = try table(warnings.view)
        let selection = table.selectedRow
        let revision = registry.revision
        _ = NSApp.sendAction(try #require(reveal.action), to: reveal.target, from: reveal)
        #expect(table.selectedRow == selection && warnings.window.firstResponder === responder)
        #expect(registry.revision == revision && registry.shortcut(for: "captureFullPage:")?.key == "w")
        #expect(warnings.view.commandMenu(for: "captureFullPage:")?.items.first?.title == "Remove Conflicting Shortcut")
        #expect(warnings.view.moreMenu()?.items.first?.title == "Remove Conflicting Shortcut")
        #expect(!warnings.view.subviews.contains { ($0 as? NSButton)?.title == "Remove Conflicting Shortcut" })
    }

    @Test @MainActor func theConflictMenuCommitsOnlyForTheOriginalKeyOwner() throws {
        let warnings = try Warnings()
        let registry = warnings.fixture.registry
        warnings.view.selectCommand("captureFullPage:")
        let proposed = try recorder("captureFullPage:", in: warnings.view)
        proposed.onBegin?()
        let closeBinding = try #require(registry.shortcut(for: "closeTab:"))
        _ = proposed.onChange?(closeBinding)
        let action = try #require(warnings.view.moreMenu()?.items.first)
        let revision = registry.revision
        warnings.window.permitsCommands = false
        try warnings.fixture.invoke(action)
        #expect(registry.revision == revision)
        warnings.window.permitsCommands = true
        try warnings.fixture.invoke(action)
        #expect(registry.shortcut(for: "closeTab:") == nil && registry.shortcut(for: "captureFullPage:")?.key == "w")
    }

    @Test @MainActor func resetAllIsDirectAndRefusesStaleMenusAndLostOwners() throws {
        let warnings = try Warnings()
        let registry = warnings.fixture.registry
        let all = try #require(warnings.view.moreMenu()?.items.last)
        try registry.set(KeyboardShortcut(key: "k", flags: [.command, .control]), for: "captureFullPage:")
        let stale = try #require(warnings.view.moreMenu()?.items.last)
        try registry.setPriority(.preferParc, for: "captureFullPage:")
        let newer = registry.revision
        #expect(all.title == "Reset All Shortcuts")
        try warnings.fixture.invoke(stale)
        #expect(registry.revision == newer)
        let current = try #require(warnings.view.moreMenu()?.items.last)
        warnings.window.permitsCommands = false
        try warnings.fixture.invoke(current)
        #expect(registry.revision == newer)
        warnings.window.permitsCommands = true
        try warnings.fixture.invoke(current)
        #expect(!registry.hasOverrides)
        #expect(registry.shortcut(for: "closeTab:")?.key == "w" && registry.shortcut(for: "captureFullPage:") == nil)
        #expect(warnings.window.attachedSheet == nil)
        #expect(warnings.view.moreMenu()?.items.last?.isEnabled == false)
    }

    @Test @MainActor func refreshingSystemShortcutsRemovesObsoleteWarningsWithoutChangingBindingsOrFocus() throws {
        let warnings = try Warnings()
        let search = try #require(warnings.view.subviews.compactMap { $0 as? ShortcutSearchHeader }.first).field
        warnings.window.makeFirstResponder(search)
        let responder = warnings.window.firstResponder
        let binding = warnings.fixture.registry.shortcut(for: "closeTab:")
        warnings.box.value = []
        warnings.view.viewDidMoveToWindow()
        #expect(try !cell("closeTab:", in: warnings.view).subviews.contains { $0 is NSImageView })
        #expect(warnings.fixture.registry.shortcut(for: "closeTab:") == binding)
        #expect(warnings.window.firstResponder === responder)
    }

    @Test @MainActor func aSpaceConflictShowsTheGlyphButSpeaksSpace() throws {
        let warnings = try Warnings()
        for id in ["closeTab:", "captureFullPage:"] {
            warnings.view.selectCommand(id)
            let recorder = try recorder(id, in: warnings.view)
            recorder.onBegin?()
            _ = recorder.onChange?(KeyboardShortcut(key: " ", flags: .control))
            warnings.view.endRecording()
        }
        let warning = try #require(try cell("captureFullPage:", in: warnings.view).subviews.compactMap { $0 as? NSButton }.first)
        #expect(warning.toolTip?.hasPrefix("⌃⎵ is already in use by “") == true)
        #expect(warning.accessibilityLabel()?.hasPrefix("⌃Space is already in use by “") == true)
    }

    @Test @MainActor func theRemovalEffectMeasuresTheActualKeycapsAndCancelsOnAnyChange() throws {
        let fixture = try Fixture()
        fixture.view.selectCommand("closeTab:")
        let caps = fixture.caps
        let captured = try #require(ShortcutRemovalEffect.capture(caps, reduceMotion: false))
        #expect(caps.keycapBounds.size == NSSize(width: 132, height: 64))
        #expect(captured.screenFrame == fixture.window.convertToScreen(caps.convert(caps.keycapBounds, to: nil)))
        #expect(ShortcutRemovalEffect.capture(caps, reduceMotion: true) == nil)
        caps.frame.origin.x += 1
        #expect(!captured.isCurrent)
        caps.frame.origin.x -= 1
        fixture.window.permitsCommands = false
        #expect(!captured.isCurrent)
        #expect(ShortcutRemovalEffect.capture(caps, reduceMotion: false) == nil)
        fixture.window.permitsCommands = true
        fixture.window.contentView = nil
        #expect(!captured.isCurrent)
    }

    @Test @MainActor func tearingDownThePresentationNeverPersistsBindings() throws {
        let fixture = try Fixture()
        try fixture.registry.set(KeyboardShortcut(key: "k", flags: [.command, .control]), for: "closeTab:")
        let file = fixture.directory.appendingPathComponent("keyboard-shortcuts.json")
        let saved = try Data(contentsOf: file)
        fixture.view.endRecording()
        fixture.window.contentView = nil
        fixture.window.close()
        #expect(try Data(contentsOf: file) == saved)
    }
}
