import AppKit
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
