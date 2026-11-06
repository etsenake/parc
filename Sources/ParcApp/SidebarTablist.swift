import AppKit

/// BaseAssets.NoBackgroundScroller, the tablist's vertical scroller: it is
///
///
///
final class SidebarTablistScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class var preferredScrollerStyle: NSScroller.Style { .overlay }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        scrollerStyle == .legacy ? 8 : super.scrollerWidth(for: controlSize, scrollerStyle: scrollerStyle)
    }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

extension NSScrollView {
    ///
    ///
    ///
    /// (docs/sidebar-resize.md), so legacy scrollers take 8 points from a list
    /// taller than its clip.
    func adoptTablistScroller() {
        verticalScroller = SidebarTablistScroller()
        verticalScroller?.controlSize = .small
        hasVerticalScroller = true; autohidesScrollers = true
    }
}
