import AppKit

/// A strip that takes presses only to resize what's beside it, such as the
/// sidebar's edge. It covers nothing for hover.
@MainActor protocol ResizeHandleView: NSView {}

extension NSView {
    /// Whether the pointer at `point` (window coordinates) is on this view, not
    /// on something drawn over it in the window, such as the command bar: where
    /// a press would land, except that a resize strip covers nothing.
    func isTopmost(atWindowPoint point: NSPoint) -> Bool {
        guard let content = window?.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point) else { return true }
        return hit.isDescendant(of: self) || isDescendant(of: hit)
            || sequence(first: hit, next: \.superview).contains { $0 is ResizeHandleView }
    }
}
