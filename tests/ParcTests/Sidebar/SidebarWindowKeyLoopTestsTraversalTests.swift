import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarWindowKeyLoopTestsTraversalTests {
    private typealias Support = SidebarWindowKeyLoopTestsSupport
    private typealias Flipped = Support.Flipped
    private typealias Stop = Support.Stop
    private typealias StandInPage = Support.StandInPage
    private typealias World = Support.World

    private let locked = ["header1", "close1", "renderer", "header2", "infobar", "renderer", "renderer", "findField", "findDone", "toggle", "address", "list", "plus", "header1"]

    @Test func tabFromAPagesRendererStaysInThePage() {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = Flipped(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        window.contentView = root
        let page = StandInPage(frame: NSRect(x: 0, y: 30, width: 260, height: 650))
        root.addSubview(page)
        _ = window.makeFirstResponder(page.renderer)
        window.selectNextKeyView(nil)
        #expect(window.firstResponder === page.renderer)
        window.close()
    }

    @Test func lockedTabRunsThePageSideTheSidebarAfterItsGateAndBack() {
        let w = World()
        #expect(w.tabs(from: w.sidebar.plus, 14) == locked)
    }

    @Test func lockedShiftTabRunsItBackwards() {
        let w = World()
        #expect(w.tabs(from: w.header1, 14, backward: true) == locked.dropLast().reversed() + ["plus"])
    }

    @Test func shiftTabLeavesAPageFromItsRendererNotIntoItsForwardingHost() {
        let w = World()
        #expect(w.tabs(from: w.page1.renderer, 1, backward: true) == ["close1"])
        #expect(w.tabs(from: w.page2.renderer, 1, backward: true) == ["infobar"])
    }

    @Test func becomingKeyRestoresTheLoopInBothDirections() {
        let w = World()
        w.capture.removeFromSuperview()
        w.window.recalculateKeyViewLoop()
        #expect(w.findDone.nextKeyView !== w.sidebar.keyViewEntry)
        #expect(w.sidebar.plus.nextKeyView !== w.header1)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: w.window)
        #expect(w.tabs(from: w.sidebar.plus, 14) == locked)
        #expect(w.tabs(from: w.header1, 14, backward: true) == locked.dropLast().reversed() + ["plus"])
    }

    @Test func theGatesWayBackIsThePageSidesEnd() {
        let w = World()
        #expect(w.sidebar.keyViewEntry.previousKeyView === w.findDone)
    }

    @Test func aCaptureOpenedLaterKeepsItsLoopThroughRelinks() {
        let w = World()
        w.capture.removeFromSuperview()
        w.window.recalculateKeyViewLoop()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: w.window)
        w.page1.addSubview(w.capture)
        _ = w.loop.relink()
        #expect(w.tabs(from: w.sidebar.plus, 14) == locked)
        #expect(w.capture.nextKeyView === w.capture.viewport)
        #expect(w.capture.cancel.nextKeyView === w.capture)
        #expect(w.capture.previousKeyView === w.capture.cancel)
    }

    private func withPortrait(_ w: World) -> (Flipped, Stop, Stop, Stop) {
        let portrait = Flipped(frame: NSRect(x: 20, y: 40, width: 200, height: 120))
        w.pane2.addSubview(portrait)
        let shoot = Stop("shoot", NSRect(x: 10, y: 8, width: 100, height: 24))
        let shade = Stop("shade", NSRect(x: 10, y: 40, width: 100, height: 24))
        let quit = Stop("quit", NSRect(x: 10, y: 80, width: 100, height: 24))
        [shoot, shade, quit].forEach(portrait.addSubview)
        shoot.nextKeyView = shade
        shade.nextKeyView = quit
        quit.nextKeyView = shoot
        _ = w.loop.relink()
        return (portrait, shoot, shade, quit)
    }

    @Test func thePortraitCardKeepsItsLoop() {
        let w = World()
        let (_, shoot, shade, quit) = withPortrait(w)
        #expect(shoot.nextKeyView === shade)
        #expect(shade.nextKeyView === quit)
        #expect(quit.nextKeyView === shoot)
    }

    @Test func tabStaysInThePortraitCard() {
        let w = World()
        let (_, _, shade, _) = withPortrait(w)
        #expect(w.tabs(from: shade, 3) == ["quit", "shoot", "shade"])
    }

    @Test func thePageSidePassesThePortraitCard() {
        let w = World()
        _ = withPortrait(w)
        #expect(w.tabs(from: w.sidebar.plus, 14) == locked)
    }

    @Test func hiddenTabFromThePageSidesEndReturnsToItsStart() {
        let w = World()
        w.container.frame.origin.x = -238
        w.sidebar.isPresented = false
        let pageLoop = Array(locked.prefix(9))
        #expect(w.tabs(from: w.findDone, 10) == pageLoop + ["header1"])
    }

    @Test func hiddenShiftTabFromItsStartReturnsToItsEnd() {
        let w = World()
        w.container.frame.origin.x = -238
        w.sidebar.isPresented = false
        let pageLoop = Array(locked.prefix(9))
        #expect(w.tabs(from: w.header1, 10, backward: true) == pageLoop.reversed() + ["findDone"])
    }

    @Test func withoutASidebarThePageSideLoopsOnItself() {
        let w = World()
        w.container.frame.origin.x = -238
        w.sidebar.isPresented = false
        w.sidebar.isPresented = true
        w.container.isHidden = true
        w.sidebar.isPresented = false
        let pageLoop = Array(locked.prefix(9))
        #expect(w.tabs(from: w.findDone, 10) == pageLoop + ["header1"])
        #expect(w.tabs(from: w.header1, 1, backward: true) == ["findDone"])
    }
}
