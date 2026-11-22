import AppKit
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct SidebarWindowKeyLoopTestsPeekTests {
    private typealias Support = SidebarWindowKeyLoopTestsSupport
    private typealias Flipped = Support.Flipped
    private typealias Stop = Support.Stop
    private typealias StandInPage = Support.StandInPage
    private typealias StandInSidebar = Support.StandInSidebar

    private final class PeekLike: Flipped {
        let close = Stop("peekClose", NSRect(x: 40, y: 20, width: 32, height: 32))
        let page = StandInPage(frame: NSRect(x: 90, y: 20, width: 620, height: 640))
        override init(frame: NSRect) { super.init(frame: frame); addSubview(page); addSubview(close) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var acceptsFirstResponder: Bool { true }
    }

    @MainActor private final class Peeking {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1000, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let root = Flipped(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let container = Flipped(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
        let sidebar: StandInSidebar
        let pageHost = Flipped(frame: NSRect(x: 228, y: 10, width: 760, height: 680))
        let parked: Flipped
        let peekLayer: Flipped
        let pane: Flipped
        let header = Stop("header", NSRect(x: 10, y: 4, width: 200, height: 24))
        let page = StandInPage(frame: NSRect(x: 0, y: 30, width: 760, height: 650))
        private final class Box { var view: NSView? }
        private let box = Box()
        var peek: NSView? {
            get { box.view }
            set { box.view = newValue }
        }
        let loop: WindowKeyViewLoop
        let excluded: (NSView) -> Bool
        let isPage: (NSView) -> Bool = { $0 is StandInPage }
        let passesThrough: (NSView) -> Bool = { $0 is PeekLike }

        init() {
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.addSubview(container)
            sidebar = StandInSidebar(frame: container.bounds)
            container.addSubview(sidebar)
            root.addSubview(pageHost)
            parked = Flipped(frame: pageHost.frame)
            parked.isHidden = true
            root.addSubview(parked)
            peekLayer = Flipped(frame: root.bounds)
            root.addSubview(peekLayer)
            pane = Flipped(frame: pageHost.bounds)
            pageHost.addSubview(pane)
            pane.addSubview(header)
            pane.addSubview(page)
            let container = self.container, parked = self.parked, pageHost = self.pageHost, peekLayer = self.peekLayer
            let box = self.box
            excluded = {
                WindowKeyViewLoop.windowExcludes($0, sidebarContainer: container, parkedPages: parked, pageHost: pageHost, peekLayer: peekLayer, activePeek: { box.view })
            }
            loop = WindowKeyViewLoop(root: root, sidebar: sidebar, excluded: excluded, isPage: isPage, passesThrough: passesThrough)
            loop.attach(to: window)
            _ = loop.relink()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func side() -> [NSView] { WindowKeyViewLoop.pageSide(in: root, excluded: excluded, isPage: isPage, passesThrough: passesThrough) }

        func step(from view: NSView, backward: Bool = false) -> String {
            _ = window.makeFirstResponder(view)
            if backward { window.selectPreviousKeyView(nil) } else { window.selectNextKeyView(nil) }
            return (window.firstResponder as? NSView).map { $0.identifier?.rawValue ?? "?" } ?? "window"
        }
    }

    @Test func thePageSideWithoutACardOrPeek() {
        let p = Peeking()
        #expect(p.side().map { $0.identifier?.rawValue ?? "?" } == ["header", "renderer"])
    }

    @Test func aPreviewCardsControlsAreNotOnThePageSide() {
        let p = Peeking()
        let card = SidebarPreviewSurface(frame: NSRect(x: 236, y: 120, width: 260, height: 300))
        card.content.addSubview(Stop("cardCreate", NSRect(x: 12, y: 12, width: 24, height: 24)))
        card.content.addSubview(Stop("cardSearch", NSRect(x: 44, y: 12, width: 180, height: 24)))
        p.root.addSubview(card, positioned: .above, relativeTo: nil)
        #expect(p.side().map { $0.identifier?.rawValue ?? "?" } == ["header", "renderer"])
        #expect(!p.side().contains { $0.isDescendant(of: card) })
    }

    @Test func withoutTheCardRuleItsControlsWouldJoinThePageSide() {
        let p = Peeking()
        let card = SidebarPreviewSurface(frame: NSRect(x: 236, y: 120, width: 260, height: 300))
        let create = Stop("cardCreate", NSRect(x: 12, y: 12, width: 24, height: 24))
        card.content.addSubview(create)
        p.root.addSubview(card, positioned: .above, relativeTo: nil)
        let container = p.container, parked = p.parked
        let unguarded = WindowKeyViewLoop.pageSide(in: p.root, excluded: { $0 === container || $0 === parked }, isPage: p.isPage)
        #expect(unguarded.contains { $0 === create })
    }

    @Test func aPeeksControlsAndPageAreThePageSide() {
        let p = Peeking()
        let peekView = PeekLike(frame: p.pageHost.frame)
        p.peekLayer.addSubview(peekView, positioned: .above, relativeTo: nil)
        p.peek = peekView
        #expect(p.side().map { $0.identifier?.rawValue ?? "?" } == ["peekClose", "renderer"])
        #expect(p.side().last === peekView.page.renderer)
        #expect(!p.side().contains { $0 === peekView || $0 === p.page.renderer || $0 === p.header })
    }

    @Test func anotherPeekInTheHostIsOffThePageSide() {
        let p = Peeking()
        let peekView = PeekLike(frame: p.pageHost.frame)
        p.peekLayer.addSubview(peekView, positioned: .above, relativeTo: nil)
        p.peek = peekView
        let other = PeekLike(frame: p.pageHost.frame)
        other.isHidden = true
        p.peekLayer.addSubview(other, positioned: .below, relativeTo: peekView)
        #expect(!p.side().contains { $0.isDescendant(of: other) })
    }

    @Test func withoutThePassThroughThePeeksHostWouldBeAStop() {
        let p = Peeking()
        let peekView = PeekLike(frame: p.pageHost.frame)
        p.peekLayer.addSubview(peekView, positioned: .above, relativeTo: nil)
        p.peek = peekView
        #expect(WindowKeyViewLoop.pageSide(in: p.root, excluded: p.excluded, isPage: p.isPage).first === peekView)
    }

    @Test func withoutThePeekRuleTheDimmedPaneWouldBeOnThePageSide() {
        let p = Peeking()
        let peekView = PeekLike(frame: p.pageHost.frame)
        p.peekLayer.addSubview(peekView, positioned: .above, relativeTo: nil)
        p.peek = peekView
        let container = p.container, parked = p.parked
        let undimmed = WindowKeyViewLoop.pageSide(in: p.root, excluded: { $0 === container || $0 === parked }, isPage: p.isPage, passesThrough: p.passesThrough)
        #expect(undimmed.contains { $0 === p.header })
        #expect(undimmed.contains { $0 === p.page.renderer })
    }

    @Test func thePaneReturnsToThePageSideWhenThePeekCloses() {
        let p = Peeking()
        let peekView = PeekLike(frame: p.pageHost.frame)
        p.peekLayer.addSubview(peekView, positioned: .above, relativeTo: nil)
        p.peek = peekView
        peekView.removeFromSuperview()
        p.peek = nil
        #expect(p.side().map { $0.identifier?.rawValue ?? "?" } == ["header", "renderer"])
    }

    @Test func tabFromThePagesEndReachesTheGateAndBackWithACardOpen() {
        let p = Peeking()
        let card = SidebarPreviewSurface(frame: NSRect(x: 236, y: 120, width: 260, height: 300))
        card.content.addSubview(Stop("cardCreate", NSRect(x: 12, y: 12, width: 24, height: 24)))
        p.root.addSubview(card, positioned: .above, relativeTo: nil)
        _ = p.loop.relink()
        #expect(p.step(from: p.page.renderer) == "toggle")
        #expect(p.step(from: p.sidebar.toggle, backward: true) == "renderer")
    }

    @Test func theWindowOwnerLinksNoCardControl() {
        let p = Peeking()
        let card = SidebarPreviewSurface(frame: NSRect(x: 236, y: 120, width: 260, height: 300))
        let create = Stop("cardCreate", NSRect(x: 12, y: 12, width: 24, height: 24))
        let search = Stop("cardSearch", NSRect(x: 44, y: 12, width: 180, height: 24))
        card.content.addSubview(create)
        card.content.addSubview(search)
        p.root.addSubview(card, positioned: .above, relativeTo: nil)
        _ = p.loop.relink()
        _ = p.window.makeFirstResponder(search)
        #expect(create.nextKeyView == nil)
        #expect(search.nextKeyView == nil)
    }

    @Test func tabAndShiftTabPassBetweenThePeekAndTheSidebar() {
        let p = Peeking()
        let peekView = PeekLike(frame: p.pageHost.frame)
        p.peekLayer.addSubview(peekView, positioned: .above, relativeTo: nil)
        p.peek = peekView
        _ = p.loop.relink()
        #expect(p.step(from: p.sidebar.plus) == "peekClose")
        #expect(p.step(from: peekView.page.renderer) == "toggle")
        #expect(p.step(from: peekView.close, backward: true) == "plus")
        #expect(p.step(from: p.sidebar.toggle, backward: true) == "renderer")
    }
}
