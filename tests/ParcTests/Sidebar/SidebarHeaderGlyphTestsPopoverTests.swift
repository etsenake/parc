import AppKit
import SwiftUI
import Testing
@testable import Parc

@MainActor
struct SidebarHeaderGlyphTestsPopoverTests {
    @MainActor private final class Faded {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        let pageButton = ActionButton("Site Control Center")
        let toolbarView = ExtensionToolbarView(frame: NSRect(x: 40, y: 5, width: 56, height: 28))

        init() {
            pageButton.frame = NSRect(x: 10, y: 5, width: 25, height: 28)
            host.addSubview(pageButton)
            host.addSubview(toolbarView)
            pageButton.alphaValue = 0
            toolbarView.alphaValue = 0
        }
    }

    @Test func aTransparentButtonHitTestsByDefault() {
        let f = Faded()
        #expect(f.pageButton.hitTest(NSPoint(x: 20, y: 15)) === f.pageButton)
    }

    @Test func aTransparentToolbarHitTestsByDefault() {
        let f = Faded()
        #expect(f.toolbarView.hitTest(NSPoint(x: 60, y: 15)) === f.toolbarView)
    }

    @Test func aFadedSiteControlCenterButtonAndPinnedExtensionsPassClicksThrough() {
        let f = Faded()
        f.pageButton.hitTestsWhenTransparent = false
        f.toolbarView.hitTestsWhenTransparent = false
        #expect(f.pageButton.hitTest(NSPoint(x: 20, y: 15)) == nil)
        #expect(f.toolbarView.hitTest(NSPoint(x: 60, y: 15)) == nil)
    }

    @Test func revealedButtonsTakeClicks() {
        let f = Faded()
        f.pageButton.hitTestsWhenTransparent = false
        f.toolbarView.hitTestsWhenTransparent = false
        f.pageButton.alphaValue = 1
        f.toolbarView.alphaValue = 1
        #expect(f.pageButton.hitTest(NSPoint(x: 20, y: 15)) === f.pageButton)
        #expect(f.toolbarView.hitTest(NSPoint(x: 60, y: 15)) === f.toolbarView)
    }

    @Test func aSharedQuotePillHasCircularSevenPointCorners() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        let hoverFill = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4)
        pill.style = .sharedQuote(fill: hoverFill)
        #expect(pill.layer?.cornerRadius == 7)
        #expect(pill.layer?.cornerCurve == .circular)
    }

    @Test func aSharedQuotePillUsesTheThemeFillAtRest() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        let hoverFill = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4)
        pill.style = .sharedQuote(fill: hoverFill)
        #expect(pill.layer?.backgroundColor == hoverFill.cgColor)
    }

    @Test func hoveringASharedQuotePillKeepsTheThemeFill() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        let hoverFill = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4)
        pill.style = .sharedQuote(fill: hoverFill)
        pill.setHovered(true)
        #expect(pill.layer?.backgroundColor == hoverFill.cgColor)
    }

    @Test func backToTheURLBarTheFillAndCornersReturn() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        pill.style = .sharedQuote(fill: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4))
        pill.setHovered(true)
        pill.style = .urlBar
        #expect(pill.layer?.cornerRadius == 12)
        #expect(pill.layer?.cornerCurve == .continuous)
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: false, hovered: true).cgColor)
    }

    @Test func anotherPopoverClosingKeepsTheHold() {
        let center = NotificationCenter.default
        var ended = 0
        let hold = AddressPopoverRevealHold(nextTurn: { _ in }) { ended += 1 }
        let prompt = NSPopover()
        let other = NSPopover()
        center.post(name: NSPopover.willShowNotification, object: prompt)
        center.post(name: NSPopover.willShowNotification, object: other)
        center.post(name: NSPopover.didCloseNotification, object: other)
        #expect(ended == 0)
        withExtendedLifetime(hold) {}
    }

    @Test func closingTheOwnedPopoverReleasesTheHold() {
        let center = NotificationCenter.default
        var ended = 0
        let hold = AddressPopoverRevealHold(nextTurn: { _ in }) { ended += 1 }
        let prompt = NSPopover()
        let other = NSPopover()
        center.post(name: NSPopover.willShowNotification, object: prompt)
        center.post(name: NSPopover.willShowNotification, object: other)
        center.post(name: NSPopover.didCloseNotification, object: other)
        center.post(name: NSPopover.didCloseNotification, object: prompt)
        #expect(ended == 1)
        withExtendedLifetime(hold) {}
    }

    @Test func endedHoldsIgnoreLaterPopovers() {
        let center = NotificationCenter.default
        var ended = 0
        let hold = AddressPopoverRevealHold(nextTurn: { _ in }) { ended += 1 }
        let prompt = NSPopover()
        center.post(name: NSPopover.willShowNotification, object: prompt)
        center.post(name: NSPopover.didCloseNotification, object: prompt)
        center.post(name: NSPopover.willShowNotification, object: prompt)
        center.post(name: NSPopover.didCloseNotification, object: prompt)
        #expect(ended == 1)
        withExtendedLifetime(hold) {}
    }

    @MainActor private final class Turns {
        var pending: [@MainActor () -> Void] = []
        func run() {
            let due = pending
            pending.removeAll()
            due.forEach { $0() }
        }
    }

    @Test func aPromptThatNeverShowsKeepsItsHoldUntilTheNextTurn() {
        let turns = Turns()
        var ended = 0
        let hold = AddressPopoverRevealHold(nextTurn: { turns.pending.append($0) }) { ended += 1 }
        #expect(ended == 0)
        #expect(turns.pending.count == 1)
        withExtendedLifetime(hold) {}
    }

    @Test func aPromptThatNeverShowsEndsItsHoldOnTheNextTurn() {
        let turns = Turns()
        var ended = 0
        let hold = AddressPopoverRevealHold(nextTurn: { turns.pending.append($0) }) { ended += 1 }
        turns.run()
        #expect(ended == 1)
        withExtendedLifetime(hold) {}
    }

    @Test func aPromptThatTimesOutDoesNotEndItsHoldAgainOnNotifications() {
        let turns = Turns()
        var ended = 0
        let hold = AddressPopoverRevealHold(nextTurn: { turns.pending.append($0) }) { ended += 1 }
        turns.run()
        let prompt = NSPopover()
        NotificationCenter.default.post(name: NSPopover.willShowNotification, object: prompt)
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: prompt)
        turns.run()
        #expect(ended == 1)
        withExtendedLifetime(hold) {}
    }

    @Test func aPromptShownBeforeTheNextTurnKeepsItsHoldPastIt() {
        let turns = Turns()
        var ended = 0
        let hold = AddressPopoverRevealHold(nextTurn: { turns.pending.append($0) }) { ended += 1 }
        let prompt = NSPopover()
        NotificationCenter.default.post(name: NSPopover.willShowNotification, object: prompt)
        turns.run()
        #expect(ended == 0)
        withExtendedLifetime(hold) {}
    }

    @Test func closingAShownPromptAfterTheNextTurnEndsItsHold() {
        let turns = Turns()
        var ended = 0
        let hold = AddressPopoverRevealHold(nextTurn: { turns.pending.append($0) }) { ended += 1 }
        let prompt = NSPopover()
        NotificationCenter.default.post(name: NSPopover.willShowNotification, object: prompt)
        turns.run()
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: prompt)
        #expect(ended == 1)
        withExtendedLifetime(hold) {}
    }
}
