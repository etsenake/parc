import AppKit
import Testing
@testable import Parc

private class Flipped: NSView { override var isFlipped: Bool { true } }

private final class Stop: NSView {
    init(_ name: String, _ frame: NSRect) { super.init(frame: frame); identifier = .init(name) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
}

private final class StandInPage: Flipped {
    let host = ForwardingHost()
    let contents = Flipped()
    let renderer = Stop("renderer", .zero)
    init(frame: NSRect, infobar: Bool = false) {
        super.init(frame: frame)
        host.frame = bounds
        addSubview(host)
        contents.frame = host.bounds.insetBy(dx: 0, dy: infobar ? 15 : 0).offsetBy(dx: 0, dy: infobar ? 15 : 0)
        host.addSubview(contents)
        renderer.frame = contents.bounds
        contents.addSubview(renderer)
        contents.nextKeyView = renderer
        host.renderer = renderer
        if infobar { host.addSubview(Stop("infobar", NSRect(x: 4, y: 0, width: 60, height: 20))) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private final class ForwardingHost: Flipped {
    weak var renderer: NSView?
    override var acceptsFirstResponder: Bool { renderer?.acceptsFirstResponder == true }
    override func becomeFirstResponder() -> Bool {
        DispatchQueue.main.async { [weak self] in
            if let self, let renderer = self.renderer, self.window?.firstResponder === self { self.window?.makeFirstResponder(renderer) }
        }
        return true
    }
}

private final class CaptureLike: Flipped {
    let viewport = Stop("viewport", NSRect(x: 10, y: 10, width: 40, height: 20))
    let cancel = Stop("cancel", NSRect(x: 60, y: 10, width: 40, height: 20))
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(viewport)
        addSubview(cancel)
        nextKeyView = viewport
        viewport.nextKeyView = cancel
        cancel.nextKeyView = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
}

private final class PeekLike: Flipped {
    let close = Stop("peekClose", NSRect(x: 40, y: 20, width: 32, height: 32))
    let page = StandInPage(frame: NSRect(x: 90, y: 20, width: 620, height: 640))
    override init(frame: NSRect) { super.init(frame: frame); addSubview(page); addSubview(close) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
}

private final class StandInSidebar: Flipped, SidebarKeyViewEnds {
    let gate = NSView()
    let toggle = Stop("toggle", NSRect(x: 76, y: 7, width: 32, height: 32))
    let address = Stop("address", NSRect(x: 8, y: 46, width: 212, height: 36))
    let plus = Stop("plus", NSRect(x: 188, y: 650, width: 32, height: 32))
    var keyViewEntry: NSView { gate }
    weak var keyViewExit: NSView? { didSet { if keyViewExit !== oldValue { link() } } }
    var isPresented = true { didSet { link() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = .init("list")
        [gate, toggle, address, plus].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { isPresented && super.becomeFirstResponder() }
    override var canBecomeKeyView: Bool { super.canBecomeKeyView && isPresented }
    func setNeedsKeyViewLinking() { link() }
    func link() { SidebarAccessibility.link([gate, toggle, address, self, plus], within: self, exit: keyViewExit, bypassed: !isPresented) }
}

@MainActor
struct SidebarWindowKeyLoopTests {
    private func names(_ views: [NSView]) -> [String] { views.map { $0.identifier?.rawValue ?? "?" } }
    private func descendants(of view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants(of: $0) } }

    @MainActor private final class World {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1000, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let root = Flipped(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let container = Flipped(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
        let sidebar: StandInSidebar
        let pageHost = Flipped(frame: NSRect(x: 228, y: 10, width: 520, height: 680))
        let parked: Flipped
        let parkedStop = Stop("parked", NSRect(x: 0, y: 0, width: 20, height: 20))
        let pane1 = Flipped(frame: NSRect(x: 0, y: 0, width: 260, height: 680))
        let header1 = Stop("header1", NSRect(x: 10, y: 4, width: 200, height: 24))
        let close1 = Stop("close1", NSRect(x: 230, y: 4, width: 24, height: 24))
        let page1 = StandInPage(frame: NSRect(x: 0, y: 30, width: 260, height: 650))
        let pane2 = Flipped(frame: NSRect(x: 260, y: 0, width: 260, height: 680))
        let header2 = Stop("header2", NSRect(x: 10, y: 4, width: 200, height: 24))
        let page2 = StandInPage(frame: NSRect(x: 0, y: 30, width: 260, height: 650), infobar: true)
        let capture: CaptureLike
        let panel = StandInPage(frame: NSRect(x: 760, y: 10, width: 230, height: 680))
        let find = Flipped(frame: NSRect(x: 500, y: 20, width: 240, height: 30))
        let findField = NSTextField(string: "find")
        let findDone = Stop("findDone", NSRect(x: 200, y: 0, width: 22, height: 22))
        let loop: WindowKeyViewLoop
        let excluded: (NSView) -> Bool
        let isPage: (NSView) -> Bool = { $0 is StandInPage }

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
            parked.addSubview(parkedStop)
            pageHost.addSubview(pane1)
            pane1.addSubview(close1)
            pane1.addSubview(header1)
            pane1.addSubview(page1)
            pageHost.addSubview(pane2)
            pane2.addSubview(header2)
            pane2.addSubview(page2)
            capture = CaptureLike(frame: page1.bounds)
            page1.addSubview(capture)
            root.addSubview(panel)
            root.addSubview(find)
            findField.identifier = .init("findField")
            findField.frame = NSRect(x: 0, y: 0, width: 180, height: 22)
            find.addSubview(findField)
            find.addSubview(findDone)
            let container = self.container
            let parked = self.parked
            excluded = { $0 === container || $0 === parked }
            loop = WindowKeyViewLoop(root: root, sidebar: sidebar, excluded: excluded, isPage: isPage)
            loop.attach(to: window)
            loop.relink()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var chain: [NSView] { WindowKeyViewLoop.pageSide(in: root, excluded: excluded, isPage: isPage) }

        func focused() -> String {
            let responder = window.firstResponder
            if let editor = responder as? NSTextView, editor.isFieldEditor {
                return [editor.delegate as? NSView].compactMap { $0 }.first.map { $0.identifier?.rawValue ?? "?" } ?? "?"
            }
            if responder === window { return "window" }
            return (responder as? NSView).map { $0.identifier?.rawValue ?? "?" } ?? "?"
        }

        func tabs(from start: NSView, _ steps: Int, backward: Bool = false) -> [String] {
            _ = window.makeFirstResponder(start)
            return (0..<steps).map { _ in
                if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView {
                    if backward { window.selectKeyView(preceding: field) } else { window.selectKeyView(following: field) }
                } else if backward { window.selectPreviousKeyView(nil) } else { window.selectNextKeyView(nil) }
                return focused()
            }
        }

        func intoSidebar() -> [NSView] {
            SidebarWindowKeyLoopTests.descendantsOf(root).filter { view in
                SidebarAccessibility.takesFocus(view) && !view.isDescendant(of: container)
                    && view.nextKeyView.map { $0.isDescendant(of: container) && $0 !== sidebar.keyViewEntry } == true
            }
        }
    }

    private static func descendantsOf(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendantsOf($0) } }

    private let locked = ["header1", "close1", "renderer", "header2", "infobar", "renderer", "renderer", "findField", "findDone", "toggle", "address", "list", "plus", "header1"]

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
