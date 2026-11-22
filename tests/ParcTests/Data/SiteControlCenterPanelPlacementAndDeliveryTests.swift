import AppKit
import ParcCore
import SwiftUI
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct SiteControlCenterPanelPlacementAndDeliveryTests {
    struct Hang: CustomTestStringConvertible {
        let name: String
        let anchor: CGRect
        let card: CGFloat
        let parent: CGRect
        let screen: CGRect
        let check: @Sendable (CGRect, CGFloat, Bool, CGFloat) -> Bool
        var testDescription: String { name }
    }

    nonisolated static let hangs: [Hang] = {
        let window = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        return [
            Hang(name: "near the window's edge", anchor: CGRect(x: -6, y: 700, width: 32, height: 32), card: 300,
                 parent: window, screen: window) { frame, tail, _, edge in frame.minX == 0 && tail == edge },
            Hang(name: "a window running off the screen", anchor: CGRect(x: 1420, y: 800, width: 32, height: 32), card: 300,
                 parent: CGRect(x: 900, y: 300, width: 700, height: 575), screen: screen) { frame, _, _, _ in frame.maxX == screen.maxX },
            Hang(name: "no room on either side in the window", anchor: CGRect(x: 500, y: 350, width: 32, height: 32), card: 380,
                 parent: CGRect(x: 0, y: 0, width: 1000, height: 400), screen: screen) { frame, _, below, _ in
                     !below && frame.minY == 382 && frame.maxX <= 1000 },
            Hang(name: "no room on either side anywhere", anchor: CGRect(x: 500, y: 400, width: 32, height: 32), card: 600,
                 parent: CGRect(x: 0, y: 0, width: 1000, height: 875), screen: screen) { frame, _, below, _ in
                     !below && frame.maxY == screen.maxY },
            Hang(name: "a card taller than the window", anchor: CGRect(x: 500, y: 560, width: 32, height: 32), card: 400,
                 parent: CGRect(x: 0, y: 300, width: 1000, height: 300), screen: screen) { frame, _, below, _ in
                     below && frame.maxY == 560 && frame.minY >= screen.minY },
        ]
    }()

    @Test(arguments: hangs)
    func theCardStaysOnScreenAndBesideItsButton(_ hang: Hang) {
        let placed = SiteControlCenterPlacement.windowFrame(anchor: hang.anchor, card: CGSize(width: 232, height: hang.card),
                                                             below: true, parent: hang.parent, screen: hang.screen)
        let edge = SidebarPlusMenuPlacement.cornerRadius + SidebarPlusMenuPlacement.tailBase / 2
        #expect(hang.check(placed.frame, placed.tailX, placed.below, edge))
    }

    @Test func aHangingCardsTailTipIsAboveIt() {
        let content = NSView(frame: .zero)
        let colors = SiteControlCenterColors(theme: SpaceTheme()).menu
        let chrome = ParcMenuChrome(content: content, size: NSSize(width: 232, height: 100), colors: colors, tailX: 116, tailOnTop: true)

        #expect(content.frame == NSRect(x: 0, y: 0, width: 232, height: 100))
        #expect(chrome.tailTip == NSPoint(x: 116, y: 106))
    }

    @Test func thePlusMenuKeepsItsCardAboveATailPointingDown() {
        let colors = SiteControlCenterColors(theme: SpaceTheme()).menu
        let menu = SidebarPlusMenuView(rows: SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true,
                                                                       canCreateNote: true, canSplit: true),
                                       colors: colors) { _ in }
        let chrome = SidebarPlusMenuChrome(card: menu, tailX: 50)

        #expect(menu.frame.origin.y == SidebarPlusMenuPlacement.tailHeight)
        #expect(chrome.tailTip == NSPoint(x: 50, y: 0))
    }

    @Test func anActionAfterClosingAShownCardWaitsForTheNextTurn() {
        var scheduled: [@MainActor () -> Void] = []
        let dismissal = SiteControlCenterDismissal { scheduled.append($0) }
        var ran = 0

        dismissal.close(SiteControlCenterController(model: SiteControlCenterModel())) { ran += 1 }
        #expect(ran == 0)
        scheduled.forEach { $0() }

        #expect(ran == 1)
    }

    @Test func anActionWithNoCardToCloseRunsAtOnce() {
        let dismissal = SiteControlCenterDismissal { _ in }
        var ran = 0

        dismissal.close(nil) { ran += 1 }

        #expect(ran == 1)
    }

    @Test func aMismatchedImmediateAnchorCannotShow() {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let owner = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        let other = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        let anchor = NSView(frame: frame)
        other.contentView?.addSubview(anchor)
        var ordered = false
        let presenter = SiteControlCenterController(model: SiteControlCenterModel(), orderPanel: { _, _ in ordered = true })
        var closed = 0
        presenter.onClose = { closed += 1 }

        presenter.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY, expectedWindow: owner, when: { true })

        #expect(!ordered)
        #expect(!presenter.isShown)
        #expect(closed == 1)
    }
}
