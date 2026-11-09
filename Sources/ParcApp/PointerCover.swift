import AppKit

extension NSView {
    /// Whether a press at `point` (window coordinates) would land on this view,
    /// not on something drawn over it in the window, such as the command bar.
    /// Hover follows the same rule.
    func isTopmost(atWindowPoint point: NSPoint) -> Bool {
        guard let content = window?.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point) else { return true }
        return hit.isDescendant(of: self) || isDescendant(of: hit)
    }
}
