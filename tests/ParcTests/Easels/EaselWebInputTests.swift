import AppKit
import Testing
@testable import Parc

struct EaselWebInputTests {
    @MainActor
    private func editableField(in controller: EaselWebInput) throws -> NSTextField {
        try #require(controller.view.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
    }

    @MainActor @Test(arguments: [false, true])
    func compositionKeepsEnterAndEscapeInTheField(_ escape: Bool) throws {
        var submitted = false
        var closed = false
        let controller = EaselWebInput(validOwner: { true }, submit: { _, _ in submitted = true; return true })
        controller.onClose = { closed = true }
        let field = try editableField(in: controller)
        let editor = NSTextView(frame: .zero)
        editor.setMarkedText("composing", selectedRange: NSRange(location: 9, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        try #require(editor.hasMarkedText())
        let command = escape ? #selector(NSResponder.cancelOperation(_:)) : #selector(NSResponder.insertNewline(_:))

        #expect(!controller.control(field, textView: editor, doCommandBy: command))
        #expect(!closed && !submitted)
    }

    @MainActor @Test
    func escapeClosesOnlyOnce() throws {
        var closes = 0
        let controller = EaselWebInput(validOwner: { true }, submit: { _, _ in false })
        controller.onClose = { closes += 1 }
        let field = try editableField(in: controller)
        let editor = NSTextView(frame: .zero)

        #expect(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        controller.cancel()
        #expect(closes == 1)
    }

    @MainActor @Test
    func enterCannotSubmitForAnExpiredOwner() throws {
        var submitted = false
        var closed = false
        let controller = EaselWebInput(draft: .init(mode: .search, text: "example"), validOwner: { false },
                                       submit: { _, _ in submitted = true; return true })
        controller.onClose = { closed = true }
        let field = try editableField(in: controller)
        let editor = NSTextView(frame: .zero)

        #expect(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(closed && !submitted)
    }

    @MainActor @Test
    func anUnownedAnchorCannotPresentTheEditor() {
        let controller = EaselWebInput(validOwner: { false }, submit: { _, _ in false })
        #expect(!controller.show(from: NSView(frame: .zero)))
    }

    @MainActor @Test
    func linkOnlyControlsFitBesideEachOther() throws {
        let controller = EaselWebInput(submitTitle: "Add Link", allowsSearch: false, validOwner: { false }, submit: { _, _ in false })
        defer { controller.cancel(restoreFocus: false) }
        let field = try editableField(in: controller)
        let frames = controller.view.subviews.filter { !$0.isHidden }.map(\.frame)
        #expect(field.placeholderString == "Paste a URL")
        #expect(frames.allSatisfy { controller.view.bounds.contains($0) })
        #expect(frames.enumerated().allSatisfy { index, frame in
            frames.dropFirst(index + 1).allSatisfy { !$0.intersects(frame) }
        })
    }
}
