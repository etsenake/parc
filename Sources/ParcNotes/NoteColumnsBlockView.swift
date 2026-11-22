import AppKit

@MainActor
final class NoteColumnsBlockView: NoteBlockView {
    override func measureHeight(width: CGFloat) -> CGFloat { 0 }

    override var handleAnchorY: CGFloat { 0 }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func isAccessibilityElement() -> Bool { false }
}
