import AppKit
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteBlockSelectionInteractionTests {
    private enum Edge: CaseIterable {
        case home, end

        var code: UInt16 { self == .home ? 115 : 119 }
        var characters: String { self == .home ? "\u{F729}" : "\u{F72B}" }
    }

    @MainActor private struct Fixture {
        let editor: NotePageEditor
        let window: NSWindow

        init(_ blocks: [NoteBlock]) {
            _ = NSApplication.shared
            let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
            let environment = NoteDetachedEnvironment(files: IsolatedNoteFiles.make())
            editor = NotePageEditor(session: NotePageSession(page: NotePage(blocks: blocks)), environment: environment)
            editor.canvas.frame = frame
            window.contentView = editor.canvas
            editor.canvas.layoutSubtreeIfNeeded()
        }

        func press(_ edge: Edge, shift: Bool = false) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.function, .shift] : [.function],
                                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                       characters: edge.characters, charactersIgnoringModifiers: edge.characters,
                                                       isARepeat: false, keyCode: edge.code))
            let responder = try #require(window.firstResponder)
            responder.keyDown(with: event)
        }
    }

    @Test(arguments: Edge.allCases, [false, true])
    private func homeAndEndAddressTheEditedBlock(edge: Edge, shift: Bool) throws {
        let block = NoteEditorBlocks.para("one\ntwo 🌻")
        let fixture = Fixture([NoteEditorBlocks.para("Above"), block, NoteEditorBlocks.para("Below")])
        let start = NotePosition(block.id, 5)
        fixture.editor.selection.select(.caret(start))
        try fixture.press(edge, shift: shift)
        let target = NotePosition(block.id, edge == .home ? 0 : 10)
        #expect(fixture.editor.session.selection == (shift ? .text(anchor: start, head: target) : .caret(target)))
    }

    @Test func endFromAWholeBlockSelectionEntersItsLastTextBlock() throws {
        let first = NoteEditorBlocks.para("First")
        let second = NoteEditorBlocks.para("Second")
        let fixture = Fixture([first, second])
        fixture.editor.selection.select(.blocks([first.id, second.id]))
        try fixture.press(.end)
        #expect(fixture.editor.session.selection == .caret(NotePosition(second.id, 6)))
    }

    @Test func endUsesTheLengthOfTheEditedCaption() throws {
        let file = NoteEditorBlocks.block(.file) {
            $0.source = URL(fileURLWithPath: #filePath).absoluteString
            $0.caption = "Summer"
        }
        let fixture = Fixture([file])
        let start = NotePosition(file.id, 2, field: .caption)
        fixture.editor.selection.select(.caret(start))
        let caption = try #require(fixture.editor.canvas.textHost(for: start)?.textView)
        try #require(fixture.window.firstResponder === caption)
        try fixture.press(.end)
        #expect(fixture.editor.session.selection == .caret(NotePosition(file.id, 6, field: .caption)))
    }

    @Test func shiftHomeKeepsTheAnchorInAnotherBlock() throws {
        let first = NoteEditorBlocks.para("First")
        let second = NoteEditorBlocks.para("Second")
        let fixture = Fixture([first, second])
        let anchor = NotePosition(first.id, 2)
        fixture.editor.selection.select(.text(anchor: anchor, head: NotePosition(second.id, 4)))
        try fixture.press(.home, shift: true)
        #expect(fixture.editor.session.selection == .text(anchor: anchor, head: NotePosition(second.id, 0)))
    }

    @Test func blockOptionsTargetsBothSelectedBlocksAndSkipsTheBlockBetweenThem() throws {
        let first = NoteEditorBlocks.para("First")
        let second = NoteEditorBlocks.para("Middle")
        let last = NoteEditorBlocks.para("Last")
        let fixture = Fixture([first, second, last])
        let ids = [first.id, last.id]
        fixture.editor.selection.select(.blocks(ids))
        try #require(fixture.editor.formatBar.focusToolbar())
        fixture.editor.formatBar.perform(.actions)
        #expect(fixture.editor.handles.menu.isOpen)
        #expect(fixture.editor.handles.menu.targets == ids)
    }

    @Test func selectingTableCellsClearsThePreviousTextHighlight() throws {
        let first = NoteEditorBlocks.para("First block")
        let table = NoteEditorBlocks.block(.table)
        let fixture = Fixture([first, table])
        let start = NotePosition(first.id, 1)
        fixture.editor.selection.select(.text(anchor: start, head: NotePosition(first.id, 4)))
        let firstView = try #require(fixture.editor.canvas.textHost(for: start)?.textView)
        try #require(!firstView.selectedOffsets.isEmpty)
        let tableView = try #require(fixture.editor.canvas.blockView(for: table.id) as? NoteTableBlockView)
        tableView.selectWholeTable()
        #expect(firstView.selectedOffsets.isEmpty)
    }

    @Test func placingTheCaretInAnotherBlockClearsThePreviousNativeHighlight() throws {
        let first = NoteEditorBlocks.para("First block")
        let second = NoteEditorBlocks.para("Second block")
        let fixture = Fixture([first, second])
        let firstView = try #require(fixture.editor.canvas.textHost(for: NotePosition(first.id, 0))?.textView)
        let secondView = try #require(fixture.editor.canvas.textHost(for: NotePosition(second.id, 0))?.textView)
        try #require(fixture.window.makeFirstResponder(firstView))
        firstView.selectedOffsets = 1..<5
        try #require(firstView.selectedOffsets == 1..<5)
        try #require(fixture.window.makeFirstResponder(secondView))
        secondView.selectedOffsets = 3..<3
        #expect(firstView.selectedOffsets.isEmpty)
        #expect(fixture.editor.session.selection == .caret(NotePosition(second.id, 3)))
    }
}
