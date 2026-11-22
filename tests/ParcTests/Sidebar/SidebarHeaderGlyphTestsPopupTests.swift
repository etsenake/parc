import AppKit
import SwiftUI
import Testing
@testable import Parc

@MainActor
struct SidebarHeaderGlyphTestsPopupTests {
    @MainActor private final class Popup {
        let center = NotificationCenter.default
        let popupWindow = Popup.window()
        let otherWindow = Popup.window()
        let browserWindow = Popup.window()

        static func window() -> NSWindow {
            let result = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: true)
            result.isReleasedWhenClosed = false
            return result
        }

        init() { browserWindow.addChildWindow(popupWindow, ordered: .above) }
        deinit { MainActor.assumeIsolated { browserWindow.removeChildWindow(popupWindow) } }
    }

    @Test func aPagePopupInThisBrowserWindowPlacedAtTheSidebarTakesAHold() {
        let p = Popup()
        #expect(SidebarAddressButtonsReveal.holdsExtensionPopup(p.popupWindow, of: p.browserWindow, showsPage: true, atSidebar: true))
    }

    @Test func aChildWindowWithoutAPageTakesNoHold() {
        let p = Popup()
        #expect(!SidebarAddressButtonsReveal.holdsExtensionPopup(p.popupWindow, of: p.browserWindow, showsPage: false, atSidebar: true))
    }

    @Test func aPopupPlacedAwayFromTheSidebarTakesNoHold() {
        let p = Popup()
        #expect(!SidebarAddressButtonsReveal.holdsExtensionPopup(p.popupWindow, of: p.browserWindow, showsPage: true, atSidebar: false))
    }

    @Test func anotherWindowsPopupTakesNoHold() {
        let p = Popup()
        #expect(!SidebarAddressButtonsReveal.holdsExtensionPopup(p.otherWindow, of: p.browserWindow, showsPage: true, atSidebar: true))
    }

    @Test func anAttachedPopupIsOpen() {
        let p = Popup()
        #expect(SidebarAddressButtonsReveal.extensionPopupOpen(p.popupWindow, of: p.browserWindow))
    }

    @Test func aPopupWhoseBrowserWindowIsGoneIsClosed() {
        let p = Popup()
        #expect(!SidebarAddressButtonsReveal.extensionPopupOpen(p.popupWindow, of: nil))
    }

    @Test func aPopupTheEngineDetachedIsClosed() {
        let p = Popup()
        p.browserWindow.removeChildWindow(p.popupWindow)
        #expect(!SidebarAddressButtonsReveal.extensionPopupOpen(p.popupWindow, of: p.browserWindow))
    }

    @Test func anExtensionPopupThatLosesFocusButStaysOpenKeepsItsHold() {
        let p = Popup()
        var ended = 0
        let open = true
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { $0 === p.popupWindow && open }) { ended += 1 }
        p.center.post(name: NSWindow.didResignKeyNotification, object: p.popupWindow)
        hold.endIfWindowClosed()
        #expect(ended == 0)
    }

    @Test func anotherWindowResigningOrClosingKeepsThePopupsHold() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in true }) { ended += 1 }
        p.center.post(name: NSWindow.didResignKeyNotification, object: p.otherWindow)
        p.center.post(name: NSWindow.willCloseNotification, object: p.otherWindow)
        #expect(ended == 0)
        withExtendedLifetime(hold) {}
    }

    @Test func aPopupDetachedFromItsBrowserWindowEndsItsHoldAsItLosesFocusAndOnlyOnce() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in false }) { ended += 1 }
        p.center.post(name: NSWindow.didResignKeyNotification, object: p.popupWindow)
        #expect(ended == 1)
        p.center.post(name: NSWindow.willCloseNotification, object: p.popupWindow)
        hold.endIfWindowClosed()
        #expect(ended == 1)
    }

    @Test func closingThePopupEndsItsHoldWhateverClosedIt() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in true }) { ended += 1 }
        p.center.post(name: NSWindow.willCloseNotification, object: p.popupWindow)
        #expect(ended == 1)
        withExtendedLifetime(hold) {}
    }

    @Test func aSweepEndsAHoldWhosePopupIsNoLongerOpen() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in false }) { ended += 1 }
        hold.endIfWindowClosed()
        #expect(ended == 1)
    }

    @Test func aPopupSweepLeavesTheSitePanelsPopoverHoldAlone() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold(nextTurn: { _ in }) { ended += 1 }
        let panel = NSPopover()
        p.center.post(name: NSPopover.willShowNotification, object: panel)
        hold.endIfWindowClosed()
        #expect(ended == 0)
        p.center.post(name: NSPopover.didCloseNotification, object: panel)
        #expect(ended == 1)
    }

    @MainActor private final class Holds {
        var holders = Set<ObjectIdentifier>()

        func shown(voiceOver: Bool = false) -> Bool {
            SidebarAddressButtonsReveal.revealed(sidebarHovered: false, showingMenu: !holders.isEmpty, anchored: true, voiceOverRunning: voiceOver)
        }

        func hold(_ owner: AnyObject, _ make: (@escaping () -> Void) -> AddressPopoverRevealHold) -> AddressPopoverRevealHold {
            holders.insert(ObjectIdentifier(owner))
            return make { [weak self] in self?.holders.remove(ObjectIdentifier(owner)) }
        }
    }

    @Test func aDockedSidebarHidesItsButtonsWithThePointerAwayAndNothingOpen() {
        #expect(!Holds().shown())
    }

    @Test func anOpenExtensionPopupKeepsTheButtonsRevealed() {
        let p = Popup()
        let h = Holds()
        let hold = h.hold(p.popupWindow) { AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in true }, onEnd: $0) }
        #expect(h.shown())
        withExtendedLifetime(hold) {}
    }

    @Test func closingTheSitePanelLeavesThePopupsHoldInPlace() {
        let p = Popup()
        let h = Holds()
        let hold = h.hold(p.popupWindow) { AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in true }, onEnd: $0) }
        let sitePanel = NSPopover()
        let owner = NSObject()
        let siteHold = h.hold(owner) { AddressPopoverRevealHold(onEnd: $0) }
        p.center.post(name: NSPopover.willShowNotification, object: sitePanel)
        p.center.post(name: NSPopover.didCloseNotification, object: sitePanel)
        #expect(h.shown())
        withExtendedLifetime((hold, siteHold)) {}
    }

    @Test func theButtonsFadeOnceThePopupCloses() {
        let p = Popup()
        let h = Holds()
        var open = true
        let hold = h.hold(p.popupWindow) { AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in open }, onEnd: $0) }
        open = false
        p.center.post(name: NSWindow.didResignKeyNotification, object: p.popupWindow)
        #expect(!h.shown())
        withExtendedLifetime(hold) {}
    }

    @Test func voiceOverStillRevealsTheButtonsAfterThePopupCloses() {
        let p = Popup()
        let h = Holds()
        var open = true
        let hold = h.hold(p.popupWindow) { AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in open }, onEnd: $0) }
        open = false
        p.center.post(name: NSWindow.didResignKeyNotification, object: p.popupWindow)
        #expect(h.shown(voiceOver: true))
        withExtendedLifetime(hold) {}
    }
}
