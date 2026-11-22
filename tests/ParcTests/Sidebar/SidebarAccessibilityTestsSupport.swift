import AppKit
@testable import Parc

@MainActor
enum SidebarAccessibilityTestsSupport {
    final class FlippedView: NSView { override var isFlipped: Bool { true } }

    final class ListStopView: NSView, OffscreenPresenting {
        var presented = true
        var isPresented: Bool { presented }
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool { presented && super.becomeFirstResponder() }
        override var canBecomeKeyView: Bool { super.canBecomeKeyView && presented }
    }

    static func navigation() -> NavigationControlButton {
        let navigation = NavigationControlButton(SidebarAccessibility.goBack, symbol: "arrow.left", history: true)
        navigation.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        return navigation
    }

    @MainActor final class Region {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 240, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        let sidebar = FlippedView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        let region = FlippedView(frame: NSRect(x: 0, y: 40, width: 240, height: 300))

        init() {
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.addSubview(sidebar)
            sidebar.addSubview(region)
        }

        deinit { MainActor.assumeIsolated { window.close() } }
    }

    @MainActor final class Offscreen {
        let browser = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 900, height: 600),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let page = NSTextField(string: "page")
        let pageEnd = NSTextField(string: "end")
        let container: NSView
        let sidebar: ListStopView
        let headerToggle = ActionButton(SidebarAccessibility.hideSidebar, symbol: "sidebar.left")
        let address = NSTextField(string: "address")

        init() {
            browser.isReleasedWhenClosed = false
            browser.contentView = content
            page.frame = NSRect(x: 300, y: 300, width: 200, height: 22)
            content.addSubview(page)
            pageEnd.frame = NSRect(x: 300, y: 200, width: 200, height: 22)
            content.addSubview(pageEnd)
            container = NSView(frame: SidebarPresentationFrame.locked.rect(width: 228, in: content.bounds))
            content.addSubview(container)
            sidebar = ListStopView(frame: container.bounds)
            container.addSubview(sidebar)
            headerToggle.frame = NSRect(x: 76, y: 7, width: 32, height: 32)
            address.frame = NSRect(x: 8, y: 46, width: 212, height: 36)
            sidebar.addSubview(headerToggle)
            sidebar.addSubview(address)
        }

        deinit { MainActor.assumeIsolated { browser.close() } }

        func exposed(_ view: NSView) -> AnyObject? { NSAccessibility.unignoredDescendant(of: view) as AnyObject? }

        func listed(_ elements: [Any]?, _ view: NSView) -> Bool {
            NSAccessibility.unignoredChildren(from: elements ?? []).contains { $0 as AnyObject === exposed(view) }
        }

        func hits(_ point: NSPoint) -> (view: Bool, element: Bool) {
            let view = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
            let element = browser.accessibilityHitTest(browser.convertPoint(toScreen: point)) as AnyObject?
            return (view.map { $0 === address || $0.isDescendant(of: address) } == true, element != nil && element === exposed(address))
        }

        func hide() { container.frame = SidebarPresentationFrame.hidden.rect(width: 228, in: content.bounds) }
        var addressCentre: NSPoint { address.convert(NSPoint(x: address.bounds.midX, y: address.bounds.midY), to: nil) }
        func forward(from view: NSView) -> [NSView] { Array(sequence(first: view) { $0.nextValidKeyView }.prefix(8).dropFirst()) }
        func backward(from view: NSView) -> [NSView] { Array(sequence(first: view) { $0.previousValidKeyView }.prefix(8).dropFirst()) }
        func inside(_ views: [NSView]) -> Bool { views.contains { $0.isDescendant(of: container) } }
    }

    static func chain(_ o: Offscreen) -> [NSView] {
        let gate = NSView()
        o.sidebar.addSubview(gate)
        return [gate, o.headerToggle, o.address, o.sidebar]
    }
}
