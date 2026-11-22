import AppKit
import Carbon.HIToolbox
import Testing
@testable import Parc
@testable import ParcCore

extension ShortcutDetailTestsSupport {
    struct ShortcutDetailSelectionTests {
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

        @Test @MainActor func recordingAConflictPublishesOneRevision() throws {
            let fixture = try Fixture()
            try #require(fixture.view.selectCommand("captureFullPage:"))
            let recorder = try recorder("captureFullPage:", in: fixture.view)
            let duplicate = try #require(fixture.registry.shortcut(for: "closeTab:"))
            recorder.onBegin?()
            let revision = fixture.registry.revision
            #expect(recorder.onChange?(duplicate) == true)
            #expect(fixture.registry.revision == revision + 1)
            #expect(fixture.registry.shortcut(for: "captureFullPage:") == duplicate)
        }

        @Test @MainActor func aRecordedConflictSurvivesEndingCapture() throws {
            let fixture = try Fixture()
            try #require(fixture.view.selectCommand("captureFullPage:"))
            let recorder = try recorder("captureFullPage:", in: fixture.view)
            let duplicate = try #require(fixture.registry.shortcut(for: "closeTab:"))
            recorder.onBegin?()
            _ = recorder.onChange?(duplicate)
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

        struct KeycapCount: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let count: Int
            let side: Double

            static let cases: [Self] = [
                .init(testDescription: "One key", count: 1, side: 64.0),
                .init(testDescription: "Two keys", count: 2, side: 64.0),
                .init(testDescription: "Three keys", count: 3, side: 64.0),
                .init(testDescription: "Four keys", count: 4, side: 47.75),
                .init(testDescription: "Five keys", count: 5, side: 37.6),
            ]
        }

        @Test(arguments: KeycapCount.cases)
        @MainActor func theKeycapColumnSizesByKeyCount(_ sample: KeycapCount) {
            #expect(abs(ShortcutKeycapView.largeSide(width: 200, count: sample.count) - sample.side) < 0.001)
        }

        @Test @MainActor func aWideBindingShowsAndSpeaksEachKey() throws {
            let fixture = try Fixture()
            let wide = KeyboardShortcut(key: "k", flags: [.command, .option, .control, .shift])
            try fixture.registry.set(wide, for: "closeTab:")
            fixture.view.selectCommand("closeTab:")
            #expect(fixture.caps.symbols == wide.symbols)
            #expect(fixture.caps.accessibilityValue() as? String == wide.spokenDisplay)
        }

        @Test @MainActor func aSpaceBindingShowsTheGlyphAndSpeaksSpace() throws {
            let fixture = try Fixture()
            try fixture.registry.set(KeyboardShortcut(key: "k", flags: [.command, .option, .control, .shift]), for: "closeTab:")
            fixture.view.selectCommand("closeTab:")
            try fixture.registry.set(KeyboardShortcut(key: " ", flags: .control), for: "closeTab:")
            fixture.view.selectCommand("closeTab:")
            #expect(fixture.caps.symbols == ["⌃", "⎵"])
            #expect(fixture.caps.accessibilityValue() as? String == "⌃Space")
        }

        @Test @MainActor func aTabBindingShowsTheTabGlyph() throws {
            let fixture = try Fixture()
            try fixture.registry.set(KeyboardShortcut(key: " ", flags: .control), for: "closeTab:")
            fixture.view.selectCommand("closeTab:")
            try fixture.registry.set(KeyboardShortcut(key: "\t", flags: .control), for: "closeTab:")
            fixture.view.selectCommand("closeTab:")
            #expect(fixture.caps.symbols == ["⌃", "⇥"])
        }

        @Test @MainActor func clearingABindingShowsTheUnassignedDetail() throws {
            let fixture = try Fixture()
            try fixture.registry.set(KeyboardShortcut(key: "\t", flags: .control), for: "closeTab:")
            fixture.view.selectCommand("closeTab:")
            try fixture.registry.set(nil, for: "closeTab:")
            fixture.view.selectCommand("closeTab:")
            #expect(fixture.caps.presentation == .unassigned && fixture.picker.isHidden)
        }

        @Test @MainActor func resettingAClearedBindingShowsTheRestoredDetail() throws {
            let fixture = try Fixture()
            try fixture.registry.set(nil, for: "closeTab:")
            try fixture.registry.reset("closeTab:")
            fixture.view.selectCommand("closeTab:")
            #expect(fixture.caps.presentation == .binding && !fixture.picker.isHidden)
        }

        @Test @MainActor func splitCommandsCarryTheirShortcutDescription() throws {
            let fixture = try Fixture()
            #expect(fixture.view.selectCommand("nextSplitPane:"))
            #expect(labels(fixture).contains { $0.stringValue == "Jumps to the next Split View page in your current window." })
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
}
