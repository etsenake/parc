import AppKit

@MainActor protocol ResizeHandleView: NSView {}

extension NSView {
    func isTopmost(atWindowPoint point: NSPoint) -> Bool {
        guard let content = window?.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point) else { return true }
        return hit.isDescendant(of: self) || isDescendant(of: hit)
            || sequence(first: hit, next: \.superview).contains { $0 is ResizeHandleView }
    }
}
