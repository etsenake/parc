import AppKit

@MainActor package protocol ResizeHandleView: NSView {}

extension NSView {
    package func isTopmost(atWindowPoint point: NSPoint) -> Bool {
        guard let content = window?.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point) else { return true }
        return hit.isDescendant(of: self) || isDescendant(of: hit)
            || sequence(first: hit, next: \.superview).contains { $0 is ResizeHandleView }
    }
}

@MainActor package struct TopmostCursor {
    package init() {}
    private(set) var isSet = false
    package mutating func update(_ cursor: NSCursor?, in view: NSView) {
        if let cursor {
            cursor.set()
        } else if isSet {
            NSCursor.arrow.set()
            view.window?.invalidateCursorRects(for: view)
        }
        isSet = cursor != nil
    }
    package mutating func release() { isSet = false }
}
