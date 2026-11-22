import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarWindowKeyLoopTestsPageChangesTests {
    private typealias Support = SidebarWindowKeyLoopTestsSupport
    private typealias Flipped = Support.Flipped
    private typealias Stop = Support.Stop
    private typealias World = Support.World

    @Test func aRemovedPaneLeavesTheChain() {
        let w = World()
        w.pane2.removeFromSuperview()
        w.pane1.frame.size.width = 520
        _ = w.loop.relink()
        #expect(w.tabs(from: w.sidebar.plus, 6) == ["header1", "close1", "renderer", "renderer", "findField", "findDone"])
        #expect(w.tabs(from: w.page1.renderer, 1) == ["renderer"])
        #expect(w.tabs(from: w.panel.renderer, 1, backward: true) == ["renderer"])
    }

    @Test func anAddedPaneJoinsInPlace() {
        let w = World()
        w.pane2.removeFromSuperview()
        w.pane1.frame.size.width = 520
        let pane3 = Flipped(frame: NSRect(x: 0, y: 0, width: 520, height: 680))
        w.parked.addSubview(pane3)
        pane3.addSubview(Stop("header3", NSRect(x: 10, y: 4, width: 200, height: 24)))
        _ = w.loop.relink()
        pane3.removeFromSuperview()
        pane3.frame.origin.x = 520
        w.pane1.frame.size.width = 260
        w.pageHost.addSubview(pane3)
        _ = w.loop.relink()
        #expect(w.tabs(from: w.page1.renderer, 2) == ["header3", "renderer"])
        #expect(w.intoSidebar().isEmpty)
    }

    @Test func aSwappedInRendererStartsUnlinkedAndFocusReachingItRelinksThePageSide() {
        let w = World()
        let pane3 = Flipped(frame: NSRect(x: 520, y: 0, width: 260, height: 680))
        w.pane2.removeFromSuperview()
        w.pageHost.addSubview(pane3)
        pane3.addSubview(Stop("header3", NSRect(x: 10, y: 4, width: 200, height: 24)))
        _ = w.loop.relink()
        let swapped = Stop("swapped", w.page1.renderer.frame)
        w.page1.renderer.removeFromSuperview()
        w.page1.contents.addSubview(swapped, positioned: .below, relativeTo: nil)
        w.page1.contents.nextKeyView = swapped
        #expect(swapped.nextKeyView == nil)
        _ = w.window.makeFirstResponder(w.findField)
        #expect(swapped.nextKeyView == nil)
        #expect(w.tabs(from: swapped, 1) == ["header3"])
        #expect(w.tabs(from: swapped, 1, backward: true) == ["close1"])
    }

    @Test func libraryControlsStartThePageSide() {
        let w = World()
        let library = Flipped(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
        w.root.addSubview(library)
        let search = Stop("library", NSRect(x: 10, y: 40, width: 200, height: 24))
        library.addSubview(search)
        w.container.isHidden = true
        w.sidebar.isPresented = false
        _ = w.loop.relink()
        #expect(w.sidebar.keyViewExit === search)
        #expect(w.tabs(from: w.findDone, 1) == ["library"])
        #expect(w.tabs(from: search, 1, backward: true) == ["findDone"])
    }

    @Test func aPopupsBarStartsThePageSide() {
        let w = World()
        w.container.isHidden = true
        w.sidebar.isPresented = false
        let popupBar = Flipped(frame: NSRect(x: 8, y: 0, width: 984, height: 9))
        w.root.addSubview(popupBar)
        let back = Stop("popupBack", NSRect(x: 4, y: 0, width: 9, height: 9))
        popupBar.addSubview(back)
        _ = w.loop.relink()
        #expect(w.sidebar.keyViewExit === back)
        #expect(w.tabs(from: w.findDone, 1) == ["popupBack"])
        #expect(w.intoSidebar().isEmpty)
    }

    @Test func withoutThePageRuleTheHostIsAStop() {
        let w = World()
        let plain = WindowKeyViewLoop.pageSide(in: w.root, excluded: w.excluded, isPage: { _ in false })
        #expect(plain.contains { $0 === w.panel.host })
    }
}
