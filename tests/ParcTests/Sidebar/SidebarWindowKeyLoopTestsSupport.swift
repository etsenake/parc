import AppKit
@testable import Parc

@MainActor
enum SidebarWindowKeyLoopTestsSupport {
    class Flipped: NSView { override var isFlipped: Bool { true } }

    final class Stop: NSView {
        init(_ name: String, _ frame: NSRect) { super.init(frame: frame); identifier = .init(name) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var acceptsFirstResponder: Bool { true }
    }

    final class StandInPage: Flipped {
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

    final class ForwardingHost: Flipped {
        weak var renderer: NSView?
        override var acceptsFirstResponder: Bool { renderer?.acceptsFirstResponder == true }
        override func becomeFirstResponder() -> Bool {
            DispatchQueue.main.async { [weak self] in
                if let self, let renderer = self.renderer, self.window?.firstResponder === self { self.window?.makeFirstResponder(renderer) }
            }
            return true
        }
    }

    final class CaptureLike: Flipped {
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

    final class StandInSidebar: Flipped, SidebarKeyViewEnds {
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

    @MainActor final class World {
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
            SidebarWindowKeyLoopTestsSupport.descendantsOf(root).filter { view in
                SidebarAccessibility.takesFocus(view) && !view.isDescendant(of: container)
                    && view.nextKeyView.map { $0.isDescendant(of: container) && $0 !== sidebar.keyViewEntry } == true
            }
        }
    }

    static func descendantsOf(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendantsOf($0) } }
}
