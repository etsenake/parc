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

@MainActor struct TopmostCursor {
    private(set) var isSet = false
    mutating func update(_ cursor: NSCursor?, in view: NSView) {
        if let cursor {
            cursor.set()
        } else if isSet {
            NSCursor.arrow.set()
            view.window?.invalidateCursorRects(for: view)
        }
        isSet = cursor != nil
    }
    mutating func release() { isSet = false }
}
