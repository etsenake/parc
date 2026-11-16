import AppKit

@main @MainActor struct SidebarWindowKeyLoopTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarWindowKeyLoop: \(message)") }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = Flipped(frame: NSRect(x: 0, y: 0, width: 1000, height: 700)); window.contentView = root
        let container = Flipped(frame: NSRect(x: 0, y: 0, width: 228, height: 700)); root.addSubview(container)
        let sidebar = StandInSidebar(frame: container.bounds); container.addSubview(sidebar)
        let pageHost = Flipped(frame: NSRect(x: 228, y: 10, width: 520, height: 680)); root.addSubview(pageHost)
        let parked = Flipped(frame: pageHost.frame); parked.isHidden = true; root.addSubview(parked)
        let parkedStop = Stop("parked", NSRect(x: 0, y: 0, width: 20, height: 20)); parked.addSubview(parkedStop)
        let pane1 = Flipped(frame: NSRect(x: 0, y: 0, width: 260, height: 680)); pageHost.addSubview(pane1)
        let header1 = Stop("header1", NSRect(x: 10, y: 4, width: 200, height: 24)), close1 = Stop("close1", NSRect(x: 230, y: 4, width: 24, height: 24))
        pane1.addSubview(close1); pane1.addSubview(header1)
        AppKitLoop.compute(window, from: header1)
        let page1 = StandInPage(frame: NSRect(x: 0, y: 30, width: 260, height: 650)); pane1.addSubview(page1)
        check(page1.renderer.nextValidKeyView == nil && page1.renderer.previousValidKeyView == nil,
              "a page added after the window's loop has no way out")
        _ = window.makeFirstResponder(page1.renderer); window.selectNextKeyView(nil)
        check(window.firstResponder === page1.renderer, "Tab from its renderer stays in the page")

        let pane2 = Flipped(frame: NSRect(x: 260, y: 0, width: 260, height: 680)); pageHost.addSubview(pane2)
        let header2 = Stop("header2", NSRect(x: 10, y: 4, width: 200, height: 24)); pane2.addSubview(header2)
        let page2 = StandInPage(frame: NSRect(x: 0, y: 30, width: 260, height: 650), infobar: true); pane2.addSubview(page2)
        let capture = CaptureLike(frame: page1.bounds); page1.addSubview(capture)
        let panel = StandInPage(frame: NSRect(x: 760, y: 10, width: 230, height: 680)); root.addSubview(panel)
        let find = Flipped(frame: NSRect(x: 500, y: 20, width: 240, height: 30)); root.addSubview(find)
        let findField = NSTextField(string: "find"); findField.identifier = .init("findField")
        findField.frame = NSRect(x: 0, y: 0, width: 180, height: 22); find.addSubview(findField)
        let findDone = Stop("findDone", NSRect(x: 200, y: 0, width: 22, height: 22)); find.addSubview(findDone)
        let loop = WindowKeyViewLoop(root: root, sidebar: sidebar, excluded: { $0 === container || $0 === parked },
                                     isPage: { $0 is StandInPage })
        loop.attach(to: window)
        check(loop.relink(), "first relink installs the page-side chain")
        let chain = WindowKeyViewLoop.pageSide(in: root, excluded: { $0 === container || $0 === parked }, isPage: { $0 is StandInPage })
        check(names(chain) == ["header1", "close1", "renderer", "header2", "infobar", "renderer", "renderer", "findField", "findDone"],
              "the page side in AppKit's geometric order: \(names(chain))")
        check(WindowKeyViewLoop.isInstalled(chain, entry: sidebar.keyViewEntry, exit: sidebar.keyViewExit),
              "isInstalled matches after a fresh relink")
        check(WindowKeyViewLoop.isInstalled([], entry: sidebar.keyViewEntry, exit: nil),
              "an empty chain with a nil exit is already installed")
        check(!WindowKeyViewLoop.isInstalled([], entry: sidebar.keyViewEntry, exit: header1),
              "an empty chain rejects a non-nil exit")
        check(!loop.relink(), "a second relink with an unchanged tree is a no-op")
        check(WindowKeyViewLoop.isInstalled(chain, entry: sidebar.keyViewEntry, exit: sidebar.keyViewExit),
              "the no-op leaves the installed chain and gate links intact")
        findDone.nextKeyView = nil
        check(!WindowKeyViewLoop.isInstalled(chain, entry: sidebar.keyViewEntry, exit: sidebar.keyViewExit),
              "isInstalled is false when a page-side next link is broken")
        check(loop.relink(), "a broken gate link reinstalls")
        let headerFrame = header1.frame, closeFrame = close1.frame
        header1.frame = closeFrame; close1.frame = headerFrame
        check(loop.relink(), "a geometric reorder of page-side stops reinstalls")
        header1.frame = headerFrame; close1.frame = closeFrame
        check(loop.relink(), "restoring frames reinstalls the original order")
        check(!chain.contains { $0 === page1.host || $0 === page2.host || $0 === panel.host },
              "a page host that forwards to its renderer is no stop")
        check(!chain.contains { $0 === capture || $0.isDescendant(of: capture) || $0 === parkedStop || $0.isDescendant(of: container) },
              "a closed loop, parked panes and the sidebar are not on the page side")
        check(capture.nextKeyView === capture.viewport && capture.viewport.nextKeyView === capture.cancel
              && capture.cancel.nextKeyView === capture && capture.previousKeyView === capture.cancel
              && capture.viewport.previousKeyView === capture, "page capture keeps its own loop")
        check(sidebar.keyViewExit === header1 && findDone.nextKeyView === sidebar.keyViewEntry, "the sidebar's ends join the page side's")
        func intoSidebar() -> [NSView] {
            descendants(of: root).filter { view in
                SidebarAccessibility.takesFocus(view) && !view.isDescendant(of: container)
                    && view.nextKeyView.map { $0.isDescendant(of: container) && $0 !== sidebar.keyViewEntry } == true
            }
        }
        check(intoSidebar().isEmpty, "no page-side key view links into a sidebar member other than the gate")

        func focused() -> String {
            let responder = window.firstResponder
            if let editor = responder as? NSTextView, editor.isFieldEditor { return names([editor.delegate as? NSView].compactMap { $0 }).first ?? "?" }
            if responder === window { return "window" }
            return (responder as? NSView).map { names([$0])[0] } ?? "?"
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
        let locked = ["header1", "close1", "renderer", "header2", "infobar", "renderer", "renderer", "findField", "findDone",
                      "toggle", "address", "list", "plus", "header1"]
        check(tabs(from: sidebar.plus, 14) == locked, "locked, Tab runs the page side, the sidebar after its gate, and back: \(tabs(from: sidebar.plus, 14))")
        check(tabs(from: header1, 14, backward: true) == locked.dropLast().reversed() + ["plus"],
              "locked, Shift-Tab runs it backwards: \(tabs(from: header1, 14, backward: true))")
        check(tabs(from: page1.renderer, 1, backward: true) == ["close1"] && tabs(from: page2.renderer, 1, backward: true) == ["infobar"],
              "Shift-Tab leaves a page from its renderer, not into its forwarding host")
        capture.removeFromSuperview()
        window.recalculateKeyViewLoop()
        check(findDone.nextKeyView !== sidebar.keyViewEntry && sidebar.plus.nextKeyView !== header1,
              "AppKit's computed loop replaces both sides' links")
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        check(tabs(from: sidebar.plus, 14) == locked && tabs(from: header1, 14, backward: true) == locked.dropLast().reversed() + ["plus"],
              "becoming key restores the loop in both directions: \(tabs(from: sidebar.plus, 14)) \(tabs(from: header1, 14, backward: true))")
        check(intoSidebar().isEmpty && sidebar.keyViewEntry.previousKeyView === findDone,
              "no page-side key view links into another sidebar member, and the gate's way back is the page side's end")
        page1.addSubview(capture); loop.relink()
        check(tabs(from: sidebar.plus, 14) == locked && capture.nextKeyView === capture.viewport && capture.cancel.nextKeyView === capture
              && capture.previousKeyView === capture.cancel, "a capture opened later keeps its loop through relinks")
        let portrait = Flipped(frame: NSRect(x: 20, y: 40, width: 200, height: 120)); pane2.addSubview(portrait)
        let shoot = Stop("shoot", NSRect(x: 10, y: 8, width: 100, height: 24))
        let shade = Stop("shade", NSRect(x: 10, y: 40, width: 100, height: 24)), quit = Stop("quit", NSRect(x: 10, y: 80, width: 100, height: 24))
        [shoot, shade, quit].forEach(portrait.addSubview)
        shoot.nextKeyView = shade; shade.nextKeyView = quit; quit.nextKeyView = shoot
        loop.relink()
        check(shoot.nextKeyView === shade && shade.nextKeyView === quit && quit.nextKeyView === shoot, "the portrait card keeps its loop")
        check(tabs(from: shade, 3) == ["quit", "shoot", "shade"], "Tab stays in the portrait card: \(tabs(from: shade, 3))")
        check(tabs(from: sidebar.plus, 14) == locked, "the page side passes the portrait card: \(tabs(from: sidebar.plus, 14))")
        portrait.removeFromSuperview(); loop.relink()

        container.frame.origin.x = -238; sidebar.isPresented = false
        let pageLoop = Array(locked.prefix(9))
        check(tabs(from: findDone, 10) == pageLoop + ["header1"], "hidden, Tab from the page side's end returns to its start: \(tabs(from: findDone, 10))")
        check(tabs(from: header1, 10, backward: true) == pageLoop.reversed() + ["findDone"],
              "hidden, Shift-Tab from its start returns to its end: \(tabs(from: header1, 10, backward: true))")
        sidebar.isPresented = true; container.isHidden = true; sidebar.isPresented = false
        check(tabs(from: findDone, 10) == pageLoop + ["header1"] && tabs(from: header1, 1, backward: true) == ["findDone"],
              "without a sidebar the page side loops on itself")
        container.isHidden = false; container.frame.origin.x = 0; sidebar.isPresented = true

        pane2.removeFromSuperview(); pane1.frame.size.width = 520
        let pane3 = Flipped(frame: NSRect(x: 0, y: 0, width: 520, height: 680)); parked.addSubview(pane3)
        let header3 = Stop("header3", NSRect(x: 10, y: 4, width: 200, height: 24)); pane3.addSubview(header3)
        loop.relink()
        check(tabs(from: sidebar.plus, 6) == ["header1", "close1", "renderer", "renderer", "findField", "findDone"]
              && tabs(from: page1.renderer, 1) == ["renderer"] && tabs(from: panel.renderer, 1, backward: true) == ["renderer"],
              "a removed pane leaves the chain")
        pane3.removeFromSuperview(); pane3.frame.origin.x = 520; pane1.frame.size.width = 260; pageHost.addSubview(pane3)
        loop.relink()
        check(tabs(from: page1.renderer, 2) == ["header3", "renderer"] && intoSidebar().isEmpty, "an added pane joins in place")

        let swapped = Stop("swapped", page1.renderer.frame)
        page1.renderer.removeFromSuperview(); page1.contents.addSubview(swapped, positioned: .below, relativeTo: nil)
        page1.contents.nextKeyView = swapped
        check(swapped.nextKeyView == nil, "the swapped-in renderer starts unlinked")
        _ = window.makeFirstResponder(findField)
        check(swapped.nextKeyView == nil, "focus in a field editor does not relink")
        check(tabs(from: swapped, 1) == ["header3"] && tabs(from: swapped, 1, backward: true) == ["close1"],
              "focus reaching it relinks the page side")

        let library = Flipped(frame: NSRect(x: 0, y: 0, width: 228, height: 700)); root.addSubview(library)
        let librarySearch = Stop("library", NSRect(x: 10, y: 40, width: 200, height: 24)); library.addSubview(librarySearch)
        container.isHidden = true; sidebar.isPresented = false
        loop.relink()
        check(sidebar.keyViewExit === librarySearch && tabs(from: findDone, 1) == ["library"]
              && tabs(from: librarySearch, 1, backward: true) == ["findDone"], "Library's controls start the page side")
        library.removeFromSuperview()
        let popupBar = Flipped(frame: NSRect(x: 8, y: 0, width: 984, height: 9)); root.addSubview(popupBar)
        let popupBack = Stop("popupBack", NSRect(x: 4, y: 0, width: 9, height: 9)); popupBar.addSubview(popupBack)
        loop.relink()
        check(sidebar.keyViewExit === popupBack && tabs(from: findDone, 1) == ["popupBack"], "a popup's bar starts the page side")
        check(intoSidebar().isEmpty, "the window owner never links into other sidebar members")

        let plain = WindowKeyViewLoop.pageSide(in: root, excluded: { $0 === container || $0 === parked }, isPage: { _ in false })
        check(plain.contains { $0 === panel.host }, "without the page rule the host is a stop")
        WindowKeyViewLoop.link(plain, to: sidebar.keyViewEntry)
        _ = window.makeFirstResponder(panel.renderer); window.selectPreviousKeyView(nil)
        check(window.firstResponder === panel.host, "Shift-Tab from the renderer lands on its host")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        check(window.firstResponder === panel.renderer, "which forwards focus back to the renderer")
        window.close()
        previewsAndPeek()
        print("Sidebar window key-view loop checks: \(count) passed")
    }

    static func previewsAndPeek() {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = Flipped(frame: NSRect(x: 0, y: 0, width: 1000, height: 700)); window.contentView = root
        let container = Flipped(frame: NSRect(x: 0, y: 0, width: 228, height: 700)); root.addSubview(container)
        let sidebar = StandInSidebar(frame: container.bounds); container.addSubview(sidebar)
        let pageHost = Flipped(frame: NSRect(x: 228, y: 10, width: 760, height: 680)); root.addSubview(pageHost)
        let parked = Flipped(frame: pageHost.frame); parked.isHidden = true; root.addSubview(parked)
        let peekLayer = Flipped(frame: root.bounds); root.addSubview(peekLayer)
        let pane = Flipped(frame: pageHost.bounds); pageHost.addSubview(pane)
        let header = Stop("header", NSRect(x: 10, y: 4, width: 200, height: 24)); pane.addSubview(header)
        let page = StandInPage(frame: NSRect(x: 0, y: 30, width: 760, height: 650)); pane.addSubview(page)
        var peek: NSView?
        let excluded: (NSView) -> Bool = {
            WindowKeyViewLoop.windowExcludes($0, sidebarContainer: container, parkedPages: parked, pageHost: pageHost,
                                             peekLayer: peekLayer, activePeek: { peek })
        }
        let isPage: (NSView) -> Bool = { $0 is StandInPage }, passesThrough: (NSView) -> Bool = { $0 is PeekLike }
        let loop = WindowKeyViewLoop(root: root, sidebar: sidebar, excluded: excluded, isPage: isPage, passesThrough: passesThrough)
        loop.attach(to: window)
        func side() -> [NSView] { WindowKeyViewLoop.pageSide(in: root, excluded: excluded, isPage: isPage, passesThrough: passesThrough) }
        func step(from view: NSView, backward: Bool = false) -> String {
            _ = window.makeFirstResponder(view)
            if backward { window.selectPreviousKeyView(nil) } else { window.selectNextKeyView(nil) }
            return (window.firstResponder as? NSView).map { names([$0])[0] } ?? "window"
        }
        loop.relink()
        check(names(side()) == ["header", "renderer"], "the page side without a card or Peek: \(names(side()))")

        let card = SidebarPreviewSurface(frame: NSRect(x: 236, y: 120, width: 260, height: 300))
        let create = Stop("cardCreate", NSRect(x: 12, y: 12, width: 24, height: 24)), search = Stop("cardSearch", NSRect(x: 44, y: 12, width: 180, height: 24))
        card.content.addSubview(create); card.content.addSubview(search)
        root.addSubview(card, positioned: .above, relativeTo: nil)
        loop.relink()
        check(names(side()) == ["header", "renderer"] && !side().contains { $0.isDescendant(of: card) },
              "a preview card's controls are not on the page side: \(names(side()))")
        check(step(from: page.renderer) == "toggle" && step(from: sidebar.toggle, backward: true) == "renderer",
              "Tab from the page's end reaches the gate, and back")
        check(create.nextKeyView == nil && search.nextKeyView == nil, "the window owner links no card control")
        _ = window.makeFirstResponder(search)
        check(search.nextKeyView == nil, "focus inside a card relinks nothing into it")
        card.retire(); loop.relink()
        check(!side().contains { $0.isDescendant(of: card) } && step(from: page.renderer) == "toggle",
              "a retired card leaving the window is off the page side too")
        let unguarded = WindowKeyViewLoop.pageSide(in: root, excluded: { $0 === container || $0 === parked }, isPage: isPage)
        check(unguarded.contains { $0 === create } && unguarded.contains { $0 === search },
              "without the card rule its controls would join the page side")
        card.removeFromSuperview()

        let peekView = PeekLike(frame: pageHost.frame)
        peekLayer.addSubview(peekView, positioned: .above, relativeTo: nil); peek = peekView
        loop.relink()
        check(names(side()) == ["peekClose", "renderer"] && side().last === peekView.page.renderer,
              "a Peek's controls and page are the page side: \(names(side()))")
        check(!side().contains { $0 === peekView || $0 === page.renderer || $0 === header }, "the dimmed pane and the Peek's host are no stops")
        check(step(from: sidebar.plus) == "peekClose" && step(from: peekView.page.renderer) == "toggle"
              && step(from: peekView.close, backward: true) == "plus" && step(from: sidebar.toggle, backward: true) == "renderer",
              "Tab and Shift-Tab pass between the Peek and the sidebar")
        let other = PeekLike(frame: pageHost.frame); other.isHidden = true; peekLayer.addSubview(other, positioned: .below, relativeTo: peekView)
        loop.relink()
        check(!side().contains { $0.isDescendant(of: other) }, "another Peek in the host is off the page side")
        other.removeFromSuperview()
        check(WindowKeyViewLoop.pageSide(in: root, excluded: excluded, isPage: isPage).first === peekView,
              "without the pass-through the Peek's host would be a stop")
        let undimmed = WindowKeyViewLoop.pageSide(in: root, excluded: { $0 === container || $0 === parked }, isPage: isPage,
                                                  passesThrough: passesThrough)
        check(undimmed.first === header && undimmed.contains { $0 === page.renderer }, "without the Peek rule the dimmed pane would be")
        peekView.removeFromSuperview(); peek = nil
        loop.relink()
        check(names(side()) == ["header", "renderer"] && step(from: sidebar.plus) == "header" && step(from: page.renderer) == "toggle",
              "the pane returns to the page side when the Peek closes")
        window.close()
    }

    static func names(_ views: [NSView]) -> [String] { views.map { $0.identifier?.rawValue ?? "?" } }
    static func descendants(of view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants(of: $0) } }
}

@MainActor enum AppKitLoop {
    static func compute(_ window: NSWindow, from view: NSView) { _ = window.makeFirstResponder(view); window.recalculateKeyViewLoop() }
}

private class Flipped: NSView { override var isFlipped: Bool { true } }

private final class Stop: NSView {
    init(_ name: String, _ frame: NSRect) { super.init(frame: frame); identifier = .init(name) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
}

private final class StandInPage: Flipped {
    let host = ForwardingHost(), contents = Flipped(), renderer = Stop("renderer", .zero)
    init(frame: NSRect, infobar: Bool = false) {
        super.init(frame: frame)
        host.frame = bounds; addSubview(host)
        contents.frame = host.bounds.insetBy(dx: 0, dy: infobar ? 15 : 0).offsetBy(dx: 0, dy: infobar ? 15 : 0); host.addSubview(contents)
        renderer.frame = contents.bounds; contents.addSubview(renderer); contents.nextKeyView = renderer
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
    let viewport = Stop("viewport", NSRect(x: 10, y: 10, width: 40, height: 20)), cancel = Stop("cancel", NSRect(x: 60, y: 10, width: 40, height: 20))
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(viewport); addSubview(cancel)
        nextKeyView = viewport; viewport.nextKeyView = cancel; cancel.nextKeyView = self
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
    let gate = NSView(), toggle = Stop("toggle", NSRect(x: 76, y: 7, width: 32, height: 32))
    let address = Stop("address", NSRect(x: 8, y: 46, width: 212, height: 36)), plus = Stop("plus", NSRect(x: 188, y: 650, width: 32, height: 32))
    var keyViewEntry: NSView { gate }
    weak var keyViewExit: NSView? { didSet { if keyViewExit !== oldValue { link() } } }
    var isPresented = true { didSet { link() } }
    override init(frame: NSRect) {
        super.init(frame: frame); identifier = .init("list")
        [gate, toggle, address, plus].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { isPresented && super.becomeFirstResponder() }
    override var canBecomeKeyView: Bool { super.canBecomeKeyView && isPresented }
    func setNeedsKeyViewLinking() { link() }
    func link() { SidebarAccessibility.link([gate, toggle, address, self, plus], within: self, exit: keyViewExit, bypassed: !isPresented) }
}
