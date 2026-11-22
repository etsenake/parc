import AppKit
import Carbon.HIToolbox
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcCommandBar

extension ShortcutDetailTestsSupport {
    struct ShortcutDetailConflictsTests {
        private static func hotKey(_ code: Int, _ modifiers: Int, enabled: Bool = true) -> [String: Any] {
            [kHISymbolicHotKeyCode as String: code, kHISymbolicHotKeyModifiers as String: modifiers,
             kHISymbolicHotKeyEnabled as String: enabled]
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

        @Test @MainActor func onlyCompleteEnabledTranslatedSystemShortcutsWarn() {
            let chord = KeyboardShortcut(key: " ", flags: [.control, .option, .command, .shift])
            let records = [Self.hotKey(49, controlKey | optionKey | cmdKey | shiftKey), Self.hotKey(49, cmdKey, enabled: false),
                           Self.hotKey(-1, cmdKey), Self.hotKey(65536, cmdKey), Self.hotKey(49, 0),
                           [kHISymbolicHotKeyEnabled as String: true]]
            #expect(KeyboardShortcut.systemShortcuts(records: records) == [chord])
        }

        struct SystemKey: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let code: Int
            let key: String

            static let cases: [Self] = [
                .init(testDescription: "Left Arrow", code: 123, key: "\u{f702}"),
                .init(testDescription: "F1", code: 122, key: "\u{f704}"),
            ]
        }

        @Test(arguments: SystemKey.cases)
        @MainActor func systemArrowAndFunctionKeysKeepTheirPhysicalIdentity(_ sample: SystemKey) {
            #expect(KeyboardShortcut.systemShortcuts(records: [Self.hotKey(sample.code, controlKey)]) == [KeyboardShortcut(key: sample.key, flags: .control)])
        }

        struct ConflictCount: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let owners: Int
            let suffix: String

            static let cases: [Self] = [
                .init(testDescription: "One other action", owners: 2, suffix: "and one other action"),
                .init(testDescription: "Two other actions", owners: 3, suffix: "and 2 other actions"),
            ]
        }

        @Test(arguments: ConflictCount.cases)
        @MainActor func conflictHelpCountsTheOtherOwners(_ sample: ConflictCount) {
            let other = KeyboardShortcuts.Command(id: "other", title: "Other", group: "File", defaultShortcut: nil)
            let chord = KeyboardShortcut(key: " ", flags: [.control, .option, .command, .shift])
            #expect(ShortcutsSettingsView.conflictDescription(chord, conflicts: Array(repeating: other, count: sample.owners)).hasSuffix(sample.suffix))
        }

        @Test @MainActor func aMatchingSystemRecordShowsAPassiveWarning() throws {
            let warnings = try Warnings()
            let help = "System shortcuts may take priority over this shortcut"
            #expect(try cell("closeTab:", in: warnings.view).subviews.contains { ($0 as? NSImageView)?.toolTip == help })
        }

        @Test @MainActor func anUnassignedActionHasNoSystemWarning() throws {
            let warnings = try Warnings()
            #expect(try !cell("captureFullPage:", in: warnings.view).subviews.contains { $0 is NSImageView })
        }

        @MainActor private func browserConflict() throws -> Warnings {
            let warnings = try Warnings()
            warnings.view.selectCommand("captureFullPage:")
            let proposed = try recorder("captureFullPage:", in: warnings.view)
            proposed.onBegin?()
            let closeBinding = try #require(warnings.fixture.registry.shortcut(for: "closeTab:"))
            try #require(proposed.onChange?(closeBinding) == true)
            return warnings
        }

        @MainActor private func revealButton(in conflicted: NSView) throws -> NSButton {
            try #require(conflicted.subviews.compactMap { $0 as? NSButton }.first)
        }

        @Test @MainActor func aBrowserConflictTakesPrecedenceOverTheSystemWarning() throws {
            let warnings = try browserConflict()
            let conflicted = try cell("captureFullPage:", in: warnings.view)
            let reveal = try revealButton(in: conflicted)
            #expect(reveal.frame.size == NSSize(width: 16, height: 16) && reveal.contentTintColor == .systemRed)
            #expect(!conflicted.subviews.contains { $0 is NSImageView })
            #expect(reveal.toolTip?.contains("Archive Tab") == true)
        }

        @Test @MainActor func revealingABrowserConflictKeepsSelectionAndFocus() throws {
            let warnings = try browserConflict()
            let search = try #require(warnings.view.subviews.compactMap { $0 as? ShortcutSearchHeader }.first).field
            let reveal = try revealButton(in: cell("captureFullPage:", in: warnings.view))
            warnings.window.makeFirstResponder(search)
            let responder = warnings.window.firstResponder
            let table = try table(warnings.view)
            let selection = table.selectedRow
            _ = NSApp.sendAction(try #require(reveal.action), to: reveal.target, from: reveal)
            #expect(table.selectedRow == selection && warnings.window.firstResponder === responder)
        }

        @Test @MainActor func revealingABrowserConflictKeepsTheBinding() throws {
            let warnings = try browserConflict()
            let registry = warnings.fixture.registry
            let reveal = try revealButton(in: cell("captureFullPage:", in: warnings.view))
            let revision = registry.revision
            _ = NSApp.sendAction(try #require(reveal.action), to: reveal.target, from: reveal)
            #expect(registry.revision == revision && registry.shortcut(for: "captureFullPage:")?.key == "w")
        }

        @Test @MainActor func aRevealedConflictOffersRemovalThroughTheMenus() throws {
            let warnings = try browserConflict()
            let reveal = try revealButton(in: cell("captureFullPage:", in: warnings.view))
            _ = NSApp.sendAction(try #require(reveal.action), to: reveal.target, from: reveal)
            #expect(warnings.view.commandMenu(for: "captureFullPage:")?.items.first?.title == "Remove Conflicting Shortcut")
            #expect(warnings.view.moreMenu()?.items.first?.title == "Remove Conflicting Shortcut")
            #expect(!warnings.view.subviews.contains { ($0 as? NSButton)?.title == "Remove Conflicting Shortcut" })
        }

        @Test @MainActor func theConflictMenuRejectsAnOwnerThatLosesTheKeyWindow() throws {
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
        }

        @Test @MainActor func theOriginalKeyOwnerCanRemoveAConflictingShortcut() throws {
            let warnings = try Warnings()
            let registry = warnings.fixture.registry
            warnings.view.selectCommand("captureFullPage:")
            let proposed = try recorder("captureFullPage:", in: warnings.view)
            proposed.onBegin?()
            let closeBinding = try #require(registry.shortcut(for: "closeTab:"))
            _ = proposed.onChange?(closeBinding)
            let action = try #require(warnings.view.moreMenu()?.items.first)
            try warnings.fixture.invoke(action)
            #expect(registry.shortcut(for: "closeTab:") == nil && registry.shortcut(for: "captureFullPage:")?.key == "w")
        }

        @Test @MainActor func theResetAllMenuNamesItsAction() throws {
            let warnings = try Warnings()
            let all = try #require(warnings.view.moreMenu()?.items.last)
            #expect(all.title == "Reset All Shortcuts")
        }

        @Test @MainActor func aStaleResetAllReceiptCannotChangeTheRegistry() throws {
            let warnings = try Warnings()
            let registry = warnings.fixture.registry
            try registry.set(KeyboardShortcut(key: "k", flags: [.command, .control]), for: "captureFullPage:")
            let stale = try #require(warnings.view.moreMenu()?.items.last)
            try registry.setPriority(.preferParc, for: "captureFullPage:")
            let newer = registry.revision
            try warnings.fixture.invoke(stale)
            #expect(registry.revision == newer)
        }

        @Test @MainActor func resetAllRefusesAnOwnerThatLosesTheKeyWindow() throws {
            let warnings = try Warnings()
            let registry = warnings.fixture.registry
            try registry.set(KeyboardShortcut(key: "k", flags: [.command, .control]), for: "captureFullPage:")
            try registry.setPriority(.preferParc, for: "captureFullPage:")
            let newer = registry.revision
            let current = try #require(warnings.view.moreMenu()?.items.last)
            warnings.window.permitsCommands = false
            try warnings.fixture.invoke(current)
            #expect(registry.revision == newer)
        }

        @Test @MainActor func resetAllRestoresDefaultsWithoutAConfirmationSheet() throws {
            let warnings = try Warnings()
            let registry = warnings.fixture.registry
            try registry.set(KeyboardShortcut(key: "k", flags: [.command, .control]), for: "captureFullPage:")
            try registry.setPriority(.preferParc, for: "captureFullPage:")
            let current = try #require(warnings.view.moreMenu()?.items.last)
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

        @Test @MainActor func theRemovalEffectMeasuresTheActualKeycaps() throws {
            let fixture = try Fixture()
            fixture.view.selectCommand("closeTab:")
            let caps = fixture.caps
            let captured = try #require(ShortcutRemovalEffect.capture(caps, reduceMotion: false))
            #expect(caps.keycapBounds.size == NSSize(width: 132, height: 64))
            #expect(captured.screenFrame == fixture.window.convertToScreen(caps.convert(caps.keycapBounds, to: nil)))
        }

        @Test @MainActor func reducedMotionSkipsTheRemovalEffect() throws {
            let fixture = try Fixture()
            fixture.view.selectCommand("closeTab:")
            #expect(ShortcutRemovalEffect.capture(fixture.caps, reduceMotion: true) == nil)
        }

        enum EffectChange: CaseIterable {
            case keycapMovement, keyWindowLoss, detachment
        }

        @Test(arguments: EffectChange.allCases)
        @MainActor func aChangeInvalidatesTheCapturedRemovalEffect(_ change: EffectChange) throws {
            let fixture = try Fixture()
            fixture.view.selectCommand("closeTab:")
            let caps = fixture.caps
            let captured = try #require(ShortcutRemovalEffect.capture(caps, reduceMotion: false))
            switch change {
            case .keycapMovement:
                caps.frame.origin.x += 1
            case .keyWindowLoss:
                fixture.window.permitsCommands = false
            case .detachment:
                fixture.window.contentView = nil
            }
            #expect(!captured.isCurrent)
        }

        @Test @MainActor func aWindowThatLosesOwnershipCannotCaptureTheRemovalEffect() throws {
            let fixture = try Fixture()
            fixture.view.selectCommand("closeTab:")
            fixture.window.permitsCommands = false
            #expect(ShortcutRemovalEffect.capture(fixture.caps, reduceMotion: false) == nil)
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
}
