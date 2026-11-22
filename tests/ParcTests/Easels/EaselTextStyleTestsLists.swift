import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

struct EaselTextStyleTestsLists {
    private typealias Editor = EaselTextStyleTestsSupport.Editor

    @MainActor @Test(arguments: ["{disc}", "{decimal}."])
    func removingListMetadataKeepsOrdinaryTabDelimitedWords(_ marker: String) {
        let editor = Editor()
        let view = editor.view
        editor.load("\tImportant\tKeep this text")
        let imported = NSMutableParagraphStyle()
        imported.textLists = [NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: marker), options: 0)]
        view.textStorage!.addAttribute(.paragraphStyle, value: imported, range: view.selectedRange())
        let original = view.attributedString()
        editor.grouped { view.changeParagraph(.text) }
        #expect(view.string == original.string, "Removing imported list metadata preserves ordinary tab-delimited words")
        view.undo(nil)
        #expect(view.attributedString().isEqual(to: original), "Imported content and metadata restore together on undo")
    }

    @MainActor @Test(arguments: ["{disc}", "{decimal}."])
    func outdentingAnImportedListKeepsItsNonMarkerPrefix(_ marker: String) {
        let editor = Editor()
        let view = editor.view
        editor.load("\tImportant\tKeep this text")
        let imported = NSMutableParagraphStyle()
        imported.textLists = [NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: marker), options: 0)]
        view.textStorage!.addAttribute(.paragraphStyle, value: imported, range: view.selectedRange())
        let original = view.attributedString()
        view.setSelectedRange(NSRange(location: 1, length: 0))
        editor.grouped { view.insertBacktab(nil) }
        #expect(view.string == original.string, "Outdenting imported list metadata preserves a non-marker prefix")
    }

    @MainActor @Test
    func changingToNumbersCreatesOrderedMarkers() throws {
        let editor = Editor()
        let view = editor.view
        editor.load("One 👩🏽‍💻\nTwo\nThree")
        editor.grouped { view.changeParagraph(.numbers) }
        #expect(view.string == "\t1.\tOne 👩🏽‍💻\n\t2.\tTwo\n\t3.\tThree", "Numbered paragraphs have actual ordered markers: \(view.string.debugDescription)")
        #expect(view.paragraphKind() == .numbers, "Selected numbered paragraphs report actual state")
    }

    @MainActor @Test
    func copyingAnOrderedListKeepsItsNativeMetadata() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let editor = Editor()
        let view = editor.view
        editor.load("One 👩🏽‍💻\nTwo\nThree")
        editor.grouped { view.changeParagraph(.numbers) }
        let saved = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        try saved.write(to: board)
        #expect(try! EaselStyledText.read(from: board) == saved, "Authored lists preserve marker text and native metadata in private copy")
    }

    @MainActor @Test
    func undoingListFormattingRestoresTheOriginalAttributes() throws {
        let editor = Editor()
        let view = editor.view
        editor.load("One 👩🏽‍💻\nTwo\nThree")
        let source = view.attributedString()
        editor.grouped { view.changeParagraph(.numbers) }
        view.undo(nil)
        #expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == EaselRichTextCodec.snapshot(source), "List command undo restores original words and attributes")
    }

    @MainActor @Test
    func returnContinuesAndRenumbersAnOrderedList() throws {
        let editor = Editor()
        let view = editor.view
        editor.load("One 👩🏽‍💻\nTwo\nThree")
        editor.grouped { view.changeParagraph(.numbers) }
        let endFirst = (view.string as NSString).range(of: "\n").location
        view.setSelectedRange(NSRange(location: endFirst, length: 0))
        editor.grouped { view.insertNewline(nil) }
        #expect(view.string.contains("\t2.\t\n\t3.\tTwo\n\t4.\tThree"), "Return inserts and renumbers the actual next item")
    }

    @MainActor @Test
    func returnOnAnEmptyItemExitsTheList() throws {
        let editor = Editor()
        let view = editor.view
        editor.load("One 👩🏽‍💻\nTwo\nThree")
        editor.grouped { view.changeParagraph(.numbers) }
        let endFirst = (view.string as NSString).range(of: "\n").location
        view.setSelectedRange(NSRange(location: endFirst, length: 0))
        editor.grouped { view.insertNewline(nil) }
        let continued = view.attributedString(), caret = view.selectedRange()
        editor.grouped { view.insertNewline(nil) }
        #expect(!view.string.contains("\t2.\t\n"), "Return on an empty item exits the list")
        #expect(view.paragraphKind() == .text, "Exited empty item is a body paragraph")
        view.undo(nil)
        #expect(view.attributedString().isEqual(to: continued) && view.selectedRange() == caret, "Undo restores list prefix and original caret")
    }

    @MainActor @Test
    func backspaceAtTheStartOfAnItemRemovesItsListFormatting() throws {
        let editor = Editor()
        let view = editor.view
        editor.load("One 👩🏽‍💻\nTwo\nThree")
        editor.grouped { view.changeParagraph(.numbers) }
        let endFirst = (view.string as NSString).range(of: "\n").location
        view.setSelectedRange(NSRange(location: endFirst, length: 0))
        editor.grouped { view.insertNewline(nil) }
        editor.grouped { view.deleteBackward(nil) }
        #expect(view.paragraphKind() == .text, "Backspace at item content start removes list formatting without deleting words")
    }

    @MainActor @Test
    func tabNestsAnOrderedListItem() {
        let editor = Editor()
        let view = editor.view
        editor.load("A\nB\nC"); editor.grouped { view.changeParagraph(.numbers) }
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "B").location, length: 0))
        editor.grouped { view.insertTab(nil) }
        #expect((view.attributedString().attribute(.paragraphStyle, at: view.selectedRange().location, effectiveRange: nil) as? NSParagraphStyle)?.textLists.count == 2, "Tab changes real list nesting")
        #expect(view.string == "\t1.\tA\n\t1.\tB\n\t2.\tC", "Nested numbering preserves parent sequence")
    }

    @MainActor @Test
    func backtabRestoresTheParentListNumbering() {
        let editor = Editor()
        let view = editor.view
        editor.load("A\nB\nC"); editor.grouped { view.changeParagraph(.numbers) }
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "B").location, length: 0))
        editor.grouped { view.insertTab(nil) }
        editor.grouped { view.insertBacktab(nil) }
        #expect(view.string == "\t1.\tA\n\t2.\tB\n\t3.\tC", "Shift-Tab restores parent list and numbering")
    }

    @MainActor @Test
    func forwardDeleteJoinsAndRenumbersListContent() {
        let editor = Editor()
        let view = editor.view
        editor.load("A\nB\nC"); editor.grouped { view.changeParagraph(.numbers) }
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "\n").location, length: 0))
        editor.grouped { view.deleteForward(nil) }
        #expect(view.string == "\t1.\tAB\n\t2.\tC", "Forward delete joins list content and renumbers without a stray marker")
    }

    @MainActor @Test
    func plainMultilineInsertionKeepsListContinuation() {
        let editor = Editor()
        let view = editor.view
        editor.load("A\nB\nC"); editor.grouped { view.changeParagraph(.numbers) }
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "B").location + 1, length: 0))
        editor.grouped { view.insertText("\nPasted\nMore", replacementRange: view.selectedRange()) }
        #expect(view.string.contains("\t3.\tPasted\n\t4.\tMore\n\t5.\tC"), "Multiline native insertion keeps list structure and subsequent numbering")
        view.undo(nil)
        #expect(view.string == "\t1.\tA\n\t2.\tB\n\t3.\tC", "Multiline list insertion is one undo transaction")
    }
}
