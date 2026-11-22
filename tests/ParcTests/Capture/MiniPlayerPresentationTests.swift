import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import ParcCore
@testable import ParcSidebar

extension MiniPlayerTestsSupport {
    struct MiniPlayerPresentationTests {
        @MainActor @Test func collapsedCardsStackWithTheirOriginalOffsets() throws {
            let fixture = try MiniPlayerFixture(["a", "b", "c"])
            let front = try fixture.row("a"), middle = try fixture.row("b"), back = try fixture.row("c")
            #expect(fixture.deck.desiredHeight == 69)
            #expect([front, middle, back].map { $0.frame.height } == [33, 33, 33])
            #expect(front.frame.minY - middle.frame.minY == 7 && middle.frame.minY - back.frame.minY == 7)
            #expect(front.frame.width - middle.frame.width == 10 && middle.frame.width - back.frame.width == 10)
        }

        @MainActor @Test func reorderingTheDeckRetainsTheRowsBackingLayer() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            let row = try fixture.row("a")
            let layer = try #require(row.layer)
            try fixture.update(["b", "a"])
            #expect(try fixture.row("a").layer === layer)
        }

        @MainActor @Test func collapsedChromeKeepsTransportAndHidesTheTitle() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            let front = try fixture.row("a")
            #expect(try fixture.button("Back to Tab — a", in: front).isHidden)
            #expect(try !fixture.button("Previous Track", in: front).isHidden)
            #expect(try !fixture.button("Adjust Tab Volume", in: front).isHidden)
        }

        @MainActor @Test func expandingTheDeckRelinksItsKeyboardViews() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            let relinks = fixture.relinks
            try fixture.toggleExpansion()
            #expect(fixture.relinks > relinks)
        }

        @MainActor @Test func expandedCardsUseTheirFullHeightAndShowTheirTitle() throws {
            let fixture = try MiniPlayerFixture(["a", "b", "c"])
            try fixture.toggleExpansion("Show All Mini Players (3)")
            #expect(fixture.deck.desiredHeight == 230)
            #expect(try fixture.row("b").frame.height == 66)
            #expect(try !fixture.button("Back to Tab — b").isHidden)
        }

        @MainActor @Test(arguments: [false, true])
        func theVolumeSliderOnlyAcceptsInteractionWhileOpen(_ open: Bool) throws {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.deck.updateHover(true)
            if open { try fixture.toggleVolume(in: "a") }
            fixture.layout()
            let slider = try fixture.volume(in: "a")
            #expect(slider.alphaValue == (open ? 1 : 0))
            #expect(slider.refusesFirstResponder != open)
            #expect(slider.isAccessibilityHidden() != open)
            if !open { #expect(slider.hitTest(CGPoint(x: slider.frame.midX, y: slider.frame.midY)) == nil) }
        }

        @MainActor @Test func losingVolumeCapabilityWithdrawsTheSliderAndItsButton() throws {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.deck.updateHover(true)
            try fixture.toggleVolume(in: "a")
            fixture.engine("a").canSetVolume = false
            try fixture.update(["a"])
            let slider = try fixture.volume(in: "a")
            #expect(slider.isAccessibilityHidden() && slider.refusesFirstResponder)
            #expect(try fixture.button("Adjust Tab Volume").isHidden)
        }

        @MainActor @Test func restoredVolumeCapabilityStartsClosed() throws {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.deck.updateHover(true)
            try fixture.toggleVolume(in: "a")
            fixture.engine("a").canSetVolume = false
            try fixture.update(["a"])
            fixture.engine("a").canSetVolume = true
            try fixture.update(["a"])
            #expect(try fixture.volume(in: "a").alphaValue == 0)
        }

        @MainActor @Test func collapsingWithTheSliderFocusedMovesFocusToTheCard() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            try fixture.toggleExpansion()
            try fixture.toggleVolume(in: "a")
            let slider = try fixture.volume(in: "a")
            try #require(fixture.window.makeFirstResponder(slider))
            try fixture.toggleExpansion("Collapse Mini Players")
            #expect(try fixture.window.firstResponder === fixture.row("a"))
            #expect(fixture.deck.desiredHeight == 62)
        }

        @MainActor @Test func leavingSchedulesOneCollapseAtTheHoverDelay() throws {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.deck.updateHover(true)
            fixture.deck.updateHover(false)
            #expect(fixture.collapses.map(\.delay) == [2])
            #expect(fixture.deck.desiredHeight == 66)
        }

        @MainActor @Test func aStaleHoverOffCannotCloseTheNewHoverSession() throws {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.deck.updateHover(true)
            try fixture.toggleVolume(in: "a")
            fixture.deck.updateHover(false)
            let stale = try #require(fixture.collapses.last)
            fixture.deck.updateHover(true)
            fixture.deck.updateHover(false)
            stale.job()
            fixture.layout()
            #expect(fixture.deck.desiredHeight == 99)
        }

        @MainActor @Test func theDueHoverOffClosesTheVolumeAndReturnsToCompactTransport() throws {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.deck.updateHover(true)
            try fixture.toggleVolume(in: "a")
            fixture.deck.updateHover(false)
            let due = try #require(fixture.collapses.last)
            due.job()
            fixture.layout()
            #expect(fixture.deck.desiredHeight == 33)
            #expect(try fixture.volume(in: "a").alphaValue == 0)
        }

        @MainActor @Test func aDueHoverOffWaitsForFocusToLeaveTheDeck() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            try fixture.toggleExpansion()
            try fixture.toggleVolume(in: "a")
            try #require(fixture.window.makeFirstResponder(fixture.volume(in: "a")))
            fixture.deck.updateHover(false)
            try #require(fixture.collapses.last).job()
            let expandedHeight = fixture.deck.desiredHeight
            #expect(expandedHeight > 62)
            _ = fixture.window.makeFirstResponder(nil)
            NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: fixture.window)
            #expect(fixture.deck.desiredHeight == 62)
        }

        @MainActor @Test func aNewEpisodeAfterDismissalStartsCollapsed() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            try fixture.toggleExpansion()
            try fixture.button("Close Mini Player", in: fixture.row("a")).actionBlock?()
            try fixture.update(["b", "new"])
            #expect(fixture.deck.desiredHeight == 62)
        }

        @MainActor @Test func thePictureInPictureButtonDoesNotRevealTheTab() throws {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.deck.updateHover(true)
            fixture.layout()
            try fixture.button("Open Picture in Picture").actionBlock?()
            #expect(fixture.engine("a").actions.map(\.intValue) == [Int(PCNativeMediaAction.enterPictureInPicture.rawValue)])
            #expect(fixture.revealed.isEmpty)
        }
    }
}
