import AppKit

@MainActor
final class NoteSelectionResponder: NSView, @preconcurrency NSTextInputClient, NSMenuItemValidation {
    unowned let controller: NoteSelectionController
    private var pendingEvent: NSEvent?

    init(controller: NoteSelectionController) {
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Note selection")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func becomeFirstResponder() -> Bool { true }
    override func resignFirstResponder() -> Bool { true }

    private var editor: NotePageEditor { controller.editor }

    override func keyDown(with event: NSEvent) {
        if editor.handleKeyDown(event, in: nil) { return }
        pendingEvent = event
        interpretKeyEvents([event])
        pendingEvent = nil
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        if editor.handleKeyDown(event, in: nil) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func doCommand(by selector: Selector) {
        _ = controller.perform(selector)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let value = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        controller.typeText(value)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let event = pendingEvent ?? NSApp.currentEvent
        inputContext?.discardMarkedText()
        controller.beginComposition(with: event)
    }

    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    @objc override func selectAll(_ sender: Any?) { controller.selectAll() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(selectAll(_:))
    }
}
