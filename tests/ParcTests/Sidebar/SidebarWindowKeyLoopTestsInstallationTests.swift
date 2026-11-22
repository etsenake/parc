import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarWindowKeyLoopTestsInstallationTests {
    private typealias Support = SidebarWindowKeyLoopTestsSupport
    private typealias Flipped = Support.Flipped
    private typealias Stop = Support.Stop
    private typealias StandInPage = Support.StandInPage
    private typealias World = Support.World

    private func names(_ views: [NSView]) -> [String] { views.map { $0.identifier?.rawValue ?? "?" } }

    @Test func aPageAddedAfterTheWindowsLoopHasNoWayOut() {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = Flipped(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        window.contentView = root
        let pane = Flipped(frame: NSRect(x: 0, y: 0, width: 260, height: 680))
        root.addSubview(pane)
        let header = Stop("header1", NSRect(x: 10, y: 4, width: 200, height: 24))
        pane.addSubview(header)
        _ = window.makeFirstResponder(header)
        window.recalculateKeyViewLoop()
        let page = StandInPage(frame: NSRect(x: 0, y: 30, width: 260, height: 650))
        pane.addSubview(page)
        #expect(page.renderer.nextValidKeyView == nil)
        #expect(page.renderer.previousValidKeyView == nil)
        window.close()
    }

    @Test func theFirstRelinkInstallsThePageSideChain() {
        let w = World()
        #expect(w.loop.relink() == false)
        #expect(names(w.chain) == ["header1", "close1", "renderer", "header2", "infobar", "renderer", "renderer", "findField", "findDone"])
    }

    @Test func isInstalledMatchesAfterAFreshRelink() {
        let w = World()
        #expect(WindowKeyViewLoop.isInstalled(w.chain, entry: w.sidebar.keyViewEntry, exit: w.sidebar.keyViewExit))
    }

    @Test func anEmptyChainWithANilExitIsAlreadyInstalled() {
        let w = World()
        #expect(WindowKeyViewLoop.isInstalled([], entry: w.sidebar.keyViewEntry, exit: nil))
    }

    @Test func anEmptyChainRejectsANonNilExit() {
        let w = World()
        #expect(!WindowKeyViewLoop.isInstalled([], entry: w.sidebar.keyViewEntry, exit: w.header1))
    }

    @Test func aSecondRelinkWithAnUnchangedTreeIsANoOp() {
        let w = World()
        #expect(!w.loop.relink())
        #expect(WindowKeyViewLoop.isInstalled(w.chain, entry: w.sidebar.keyViewEntry, exit: w.sidebar.keyViewExit))
    }

    @Test func isInstalledIsFalseWhenAPageSideNextLinkIsBroken() {
        let w = World()
        w.findDone.nextKeyView = nil
        #expect(!WindowKeyViewLoop.isInstalled(w.chain, entry: w.sidebar.keyViewEntry, exit: w.sidebar.keyViewExit))
    }

    @Test func aBrokenGateLinkReinstalls() {
        let w = World()
        w.findDone.nextKeyView = nil
        #expect(w.loop.relink())
    }

    @Test func aGeometricReorderOfPageSideStopsReinstalls() {
        let w = World()
        let headerFrame = w.header1.frame
        let closeFrame = w.close1.frame
        w.header1.frame = closeFrame
        w.close1.frame = headerFrame
        #expect(w.loop.relink())
    }

    @Test func restoringFramesReinstallsTheOriginalOrder() {
        let w = World()
        let headerFrame = w.header1.frame
        let closeFrame = w.close1.frame
        w.header1.frame = closeFrame
        w.close1.frame = headerFrame
        _ = w.loop.relink()
        w.header1.frame = headerFrame
        w.close1.frame = closeFrame
        #expect(w.loop.relink())
    }

    @Test func aPageHostThatForwardsToItsRendererIsNoStop() {
        let w = World()
        #expect(!w.chain.contains { $0 === w.page1.host || $0 === w.page2.host || $0 === w.panel.host })
    }

    @Test func aClosedLoopParkedPanesAndTheSidebarAreNotOnThePageSide() {
        let w = World()
        #expect(!w.chain.contains { $0 === w.capture || $0.isDescendant(of: w.capture) || $0 === w.parkedStop || $0.isDescendant(of: w.container) })
    }

    @Test func pageCaptureKeepsItsOwnLoop() {
        let w = World()
        let c = w.capture
        #expect(c.nextKeyView === c.viewport)
        #expect(c.viewport.nextKeyView === c.cancel)
        #expect(c.cancel.nextKeyView === c)
        #expect(c.previousKeyView === c.cancel)
        #expect(c.viewport.previousKeyView === c)
    }

    @Test func theSidebarsEndsJoinThePageSides() {
        let w = World()
        #expect(w.sidebar.keyViewExit === w.header1)
        #expect(w.findDone.nextKeyView === w.sidebar.keyViewEntry)
    }

    @Test func noPageSideKeyViewLinksIntoASidebarMemberOtherThanTheGate() {
        #expect(World().intoSidebar().isEmpty)
    }
}
