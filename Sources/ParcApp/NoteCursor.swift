import AppKit

extension NSView {
    func ownsPointer(atWindowPoint point: NSPoint) -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        return visibleRect.contains(convert(point, from: nil)) && NoteFloatingPanel.allowsHover(for: self, at: point)
    }

    @discardableResult
    func applyNoteCursor(_ cursor: NSCursor?, for event: NSEvent) -> Bool {
        guard let cursor, ownsPointer(atWindowPoint: event.locationInWindow) else { return false }
        cursor.set()
        return true
    }
}

extension NSWindow {
    func refreshCursorUnderPointer() {
        guard isKeyWindow, let content = contentView else { return }
        let point = mouseLocationOutsideOfEventStream
        guard content.frame.contains(content.superview?.convert(point, from: nil) ?? point),
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point),
              let event = NSEvent.enterExitEvent(with: .cursorUpdate, location: point, modifierFlags: NSEvent.modifierFlags,
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
                                                 context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)
        else { return }
        hit.cursorUpdate(with: event)
    }
}

@MainActor
class NoteCursorTextView: NSTextView {
    private var cursorArea: NSTrackingArea?

    func pointerCursor(at point: NSPoint, modifiers: NSEvent.ModifierFlags) -> NSCursor {
        isSelectable || isEditable ? .iBeam : .arrow
    }

    func pointerMoved(with event: NSEvent) {}

    func pointerExited(with event: NSEvent) {}

    override func resetCursorRects() {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorArea { removeTrackingArea(cursorArea) }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        cursorArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        guard ownsPointer(atWindowPoint: event.locationInWindow) else { return }
        pointerCursor(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags).set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard ownsPointer(atWindowPoint: event.locationInWindow) else {
            pointerExited(with: event)
            return
        }
        super.mouseMoved(with: event)
        pointerMoved(with: event)
        pointerCursor(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags).set()
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === cursorArea else { super.mouseEntered(with: event); return }
        guard ownsPointer(atWindowPoint: event.locationInWindow) else { return }
        pointerMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === cursorArea else { super.mouseExited(with: event); return }
        pointerExited(with: event)
    }

    func refreshPointerCursor(modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        guard let window, window.isKeyWindow else { return }
        let point = window.mouseLocationOutsideOfEventStream
        guard ownsPointer(atWindowPoint: point) else { return }
        pointerCursor(at: convert(point, from: nil), modifiers: modifiers).set()
    }
}

@MainActor
final class NoteFieldEditor: NoteCursorTextView {
    static func make() -> NoteFieldEditor {
        let editor = NoteFieldEditor(frame: .zero)
        editor.isFieldEditor = true
        return editor
    }
}

@MainActor
final class NoteInputFieldCell: NSTextFieldCell {
    private var editor: NoteFieldEditor?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if let editor { return editor }
        let made = NoteFieldEditor.make()
        editor = made
        return made
    }

    override func resetCursorRect(_ cellFrame: NSRect, in controlView: NSView) {}
}

@MainActor
class NoteInputField: NSTextField {
    override class var cellClass: AnyClass? {
        get { NoteInputFieldCell.self }
        set {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addCursorUpdateArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }

    override func resetCursorRects() {}

    override func cursorUpdate(with event: NSEvent) {
        guard isEnabled, isEditable || isSelectable else { super.cursorUpdate(with: event); return }
        applyNoteCursor(.iBeam, for: event)
    }
}
