import AppKit
import ObjectiveC
@testable import Parc

final class SidebarTestWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
    var pointer: NSPoint?
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer ?? super.mouseLocationOutsideOfEventStream }
}

final class SidebarAreaEvent: NSEvent {
    var area: NSTrackingArea?
    override var trackingArea: NSTrackingArea? { area }
}

func sidebarDescendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(sidebarDescendants) }

@MainActor
func sidebarTestWindow(containing view: NSView, deferred: Bool = true) -> SidebarTestWindow {
    let window = SidebarTestWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: deferred)
    window.isReleasedWhenClosed = false
    window.contentView = view
    return window
}

enum SidebarApplicationActivity {
    nonisolated(unsafe) static var override: Bool?
    nonisolated(unsafe) private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        guard let original = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.isActive)),
              let replacement = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.sidebarObservedIsActive)) else {
            preconditionFailure("missing -[NSApplication isActive]")
        }
        method_exchangeImplementations(original, replacement)
    }

    static func set(_ active: Bool?) {
        install()
        override = active
    }
}

extension NSApplication {
    @objc dynamic var sidebarObservedIsActive: Bool { SidebarApplicationActivity.override ?? self.sidebarObservedIsActive }
}
