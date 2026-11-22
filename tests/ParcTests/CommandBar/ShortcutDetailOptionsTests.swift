import AppKit
import Carbon.HIToolbox
import Testing
@testable import Parc
@testable import ParcCore

extension ShortcutDetailTestsSupport {
    struct ShortcutDetailOptionsTests {
        struct NumberedItem: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let number: Int
            let ninthMode: Bool
            let showsFavorites: Bool
            let showsNinth: Bool

            static let cases: [Self] = [
                .init(testDescription: "First item", number: 1, ninthMode: false, showsFavorites: true, showsNinth: false),
                .init(testDescription: "Last item", number: 9, ninthMode: false, showsFavorites: false, showsNinth: true),
                .init(testDescription: "Ninth item", number: 9, ninthMode: true, showsFavorites: true, showsNinth: true),
            ]
        }

        @Test(arguments: NumberedItem.cases)
        @MainActor func numberedItemSettingsMatchTheSelectedCommand(_ sample: NumberedItem) throws {
            let fixture = try Fixture()
            fixture.defaults.set(sample.ninthMode, forKey: NumberedTarget.ninthItemKey)
            try #require(fixture.view.selectCommand(NumberedTarget.itemBindingID(sample.number)))
            let favorites = try fixture.button("Include Favorites in ordering.")
            let ninth = try fixture.button("Switch to ninth tab.")
            #expect(favorites.isHidden == !sample.showsFavorites)
            #expect(ninth.isHidden == !sample.showsNinth)
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

        @Test @MainActor func theFirstItemExposesOnlyTheIncludedFavoritesToggle() throws {
            let fixture = try Fixture()
            let favorites = try fixture.button("Include Favorites in ordering.")
            let ninth = try fixture.button("Switch to ninth tab.")
            #expect(fixture.view.selectCommand("item1"))
            #expect(!favorites.isHidden && ninth.isHidden && favorites.state == .on)
        }

        @Test @MainActor func theLastItemExposesOnlyTheNinthItemToggle() throws {
            let fixture = try Fixture()
            let favorites = try fixture.button("Include Favorites in ordering.")
            let ninth = try fixture.button("Switch to ninth tab.")
            #expect(fixture.view.selectCommand("item9"))
            #expect(favorites.isHidden && !ninth.isHidden && ninth.state == .off)
        }

        @Test @MainActor func theNinthItemShowsFavoritesBelowItsToggleWhenEnabled() throws {
            let fixture = try Fixture()
            let favorites = try fixture.button("Include Favorites in ordering.")
            let ninth = try fixture.button("Switch to ninth tab.")
            fixture.view.selectCommand("item9")
            ninth.sendClick()
            #expect(!favorites.isHidden && ninth.frame.maxY < favorites.frame.minY)
        }

        @Test @MainActor func theFavoritesToggleSavesItsInverseAndRefreshesTheDescription() throws {
            let fixture = try Fixture()
            let favorites = try fixture.button("Include Favorites in ordering.")
            let ninth = try fixture.button("Switch to ninth tab.")
            fixture.view.selectCommand("item9")
            ninth.sendClick()
            favorites.sendClick()
            #expect(fixture.defaults.bool(forKey: NumberedTarget.excludeFavoritesKey))
            #expect(labels(fixture).contains { $0.stringValue.contains("after your Favorites") })
        }

        @Test @MainActor func theNinthItemAndFirstItemShareFavoritesOrdering() throws {
            let fixture = try Fixture()
            let favorites = try fixture.button("Include Favorites in ordering.")
            let ninth = try fixture.button("Switch to ninth tab.")
            fixture.view.selectCommand("item9")
            ninth.sendClick()
            favorites.sendClick()
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

        @Test @MainActor func theCaptureDragControlIsEnabledByDefault() throws {
            let fixture = try Fixture()
            let drag = try fixture.button("Hold Command and Shift to start a Capture.")
            #expect(fixture.view.selectCommand("capturePage:"))
            #expect(!drag.isHidden && drag.state == .on)
        }

        @Test @MainActor func selectingAnotherCommandHidesTheCaptureDragControl() throws {
            let fixture = try Fixture()
            let drag = try fixture.button("Hold Command and Shift to start a Capture.")
            fixture.view.selectCommand("capturePage:")
            fixture.view.selectCommand("closeTab:")
            #expect(drag.isHidden)
        }

        @Test @MainActor func enablingTheCaptureDragNeverRecreatesAClearedChord() throws {
            let fixture = try Fixture()
            let drag = try fixture.button("Hold Command and Shift to start a Capture.")
            try fixture.registry.set(nil, for: "capturePage:")
            fixture.view.selectCommand("capturePage:")
            #expect(!drag.isHidden && drag.state == .on && fixture.picker.isHidden)
            drag.sendClick()
            drag.sendClick()
            #expect(CaptureGesturePreference.isEnabled(defaults: fixture.defaults))
            #expect(fixture.registry.shortcut(for: "capturePage:") == nil)
        }

        @Test @MainActor func theCaptureDragControlFitsAboveFeedbackForAClearedChord() throws {
            let fixture = try Fixture()
            let drag = try fixture.button("Hold Command and Shift to start a Capture.")
            try fixture.registry.set(nil, for: "capturePage:")
            fixture.view.selectCommand("capturePage:")
            drag.sendClick()
            drag.sendClick()
            let status = try #require(labels(fixture).first { $0.accessibilityLabel() == "Shortcut status" })
            #expect(drag.frame.height > 20 && drag.frame.maxY < status.frame.minY)
        }

        struct DragModifiers: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let flags: NSEvent.ModifierFlags
            let permitted: Bool

            static let cases: [Self] = [
                .init(testDescription: "Command and Shift", flags: [.command, .shift], permitted: true),
                .init(testDescription: "Command, Shift, Option and Control", flags: [.command, .shift, .option, .control], permitted: true),
                .init(testDescription: "Command only", flags: .command, permitted: false),
                .init(testDescription: "Shift only", flags: .shift, permitted: false),
            ]
        }

        @Test(arguments: DragModifiers.cases)
        func theDragMaskRequiresBothFlagsAndAllowsExtras(_ sample: DragModifiers) {
            #expect(CaptureGesturePreference.permits(sample.flags) == sample.permitted)
        }
    }
}
