import AppKit
@testable import Parc
@testable import ParcSidebar

@MainActor
enum SidebarRowActionButtonTestsSupport {
    @MainActor final class Owner {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let button = SidebarRowActionButton("Archive Tab")
        let reset = SidebarRowResetRegion()
        var available = true
        var accepts = true
        var dispatches = 0
        var queries = 0
        var revision = 0
        var menus = 0

        init(attached: Bool = true) {
            window.isReleasedWhenClosed = false
            button.frame = NSRect(x: 10, y: 10, width: 24, height: 25)
            button.prepareAction = { [unowned self] in
                queries += 1
                guard available else { return nil }
                let original = revision
                var used = false
                return { [unowned self] in
                    guard available, accepts, original == revision, !used else { return false }
                    used = true
                    dispatches += 1
                    return true
                }
            }
            reset.frame = NSRect(x: 40, y: 10, width: 30, height: 35)
            reset.prepareAction = button.prepareAction
            if attached {
                window.contentView!.addSubview(button)
                button.refreshAvailability()
            }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func attachReset() {
            window.contentView!.addSubview(reset)
            reset.refreshAvailability()
        }

        func rightMouseDown() -> NSEvent {
            NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
    }

    static func components(_ cg: CGColor?) -> [CGFloat] {
        let c = NSColor(cgColor: cg!)!.usingColorSpace(.displayP3)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
    }
}
