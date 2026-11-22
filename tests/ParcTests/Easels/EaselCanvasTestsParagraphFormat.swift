import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsParagraphFormat {
    private typealias FormatBoard = EaselCanvasTestsSupport.FormatBoard
    private typealias RecordingPanels = EaselCanvasTestsSupport.RecordingPanels

    @MainActor @Test
    func indentIsUnavailableForBodyText() throws {
        let board = try FormatBoard()
        defer { board.close() }
        _ = try board.startEditing()
        #expect(!board.validate(.increaseIndent), "List indent waits for a list paragraph")
    }

    @MainActor @Test
    func bulletedListAppliesAndChecksItsParagraph() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        board.run(.bulletedList, in: editor)
        #expect(editor.paragraphKind() == .bullets && board.state(.bulletedList) == .on && board.validate(.increaseIndent), "Bulleted List applies, checks and admits indent")
    }

    @MainActor @Test
    func increaseIndentNestsABulletedItem() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        board.run(.bulletedList, in: editor)
        board.run(.increaseIndent, in: editor)
        let nested = editor.attributedString().attribute(.paragraphStyle, at: editor.selectedRange().location, effectiveRange: nil) as? NSParagraphStyle
        #expect(nested?.textLists.count == 2, "Increase indents the list item like Tab")
    }

    @MainActor @Test
    func decreaseIndentOutdentsABulletedItem() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        board.run(.bulletedList, in: editor)
        board.run(.increaseIndent, in: editor)
        board.run(.decreaseIndent, in: editor)
        let outdented = editor.attributedString().attribute(.paragraphStyle, at: editor.selectedRange().location, effectiveRange: nil) as? NSParagraphStyle
        #expect(outdented?.textLists.count == 1, "Decrease outdents the list item like Shift-Tab")
    }

    @MainActor @Test
    func headingTwoChecksOnlyTheMatchingHeading() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        board.run(.bulletedList, in: editor)
        board.run(.increaseIndent, in: editor)
        board.run(.decreaseIndent, in: editor)
        board.run(.heading2, in: editor)
        #expect(editor.paragraphKind() == .heading2 && board.validate(.heading2) && board.state(.heading2) == .on && board.state(.heading1) == .off, "Heading 2 applies and checks only itself")
    }

    @MainActor @Test
    func bodyReturnsAHeadingToBodyText() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        board.run(.bulletedList, in: editor)
        board.run(.increaseIndent, in: editor)
        board.run(.decreaseIndent, in: editor)
        board.run(.heading2, in: editor)
        board.run(.body, in: editor)
        #expect(editor.paragraphKind() == .text && board.state(.body) == .on, "Body returns to body text")
    }

    @MainActor @Test
    func paragraphCommandsRequireASingleRange() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        editor.selectedRanges = [NSValue(range: NSRange(location: 0, length: 2)), NSValue(range: NSRange(location: 4, length: 2))]
        #expect(board.validate(.bold) && !board.validate(.heading1), "Paragraph styles need one selection, like the style bar")
    }

    @MainActor @Test
    func addLinkIsAvailableForSelectedWords() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        editor.setSelectedRange(NSRange(location: 0, length: 6))
        #expect(board.validate(.link) && board.items[.link]!.title == TextFormatCommand.addLinkTitle, "Add Link is offered for selected text")
    }

    @MainActor @Test
    func theLinkPanelAnchorsToTheSelectedRange() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let editor = try board.startEditing()
        editor.setSelectedRange(NSRange(location: 0, length: 6))
        let panels = RecordingPanels()
        canvas.panels = panels
        board.run(.link, in: editor)
        let request = try #require(panels.links.first)
        #expect(request.host === editor && request.webOnly == false)
        #expect(!request.anchor.isEmpty && editor.bounds.contains(request.anchor) && request.anchor.width < editor.bounds.width)
    }

    @MainActor @Test
    func committingALinkOffersEditLinkForItsRange() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let editor = try board.startEditing()
        editor.setSelectedRange(NSRange(location: 0, length: 6))
        let panels = RecordingPanels()
        canvas.panels = panels
        board.run(.link, in: editor)
        let request = try #require(panels.links.first)
        editor.localUndo.beginUndoGrouping()
        request.commit("https://example.com/")
        editor.localUndo.endUndoGrouping()
        #expect(editor.hasLink() && board.validate(.link) && board.items[.link]!.title == TextFormatCommand.editLinkTitle, "A linked selection offers Edit Link")
    }

    @MainActor @Test
    func linkingRequiresSelectedText() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let editor = try board.startEditing()
        editor.setSelectedRange(NSRange(location: 0, length: 6))
        let panels = RecordingPanels()
        canvas.panels = panels
        board.run(.link, in: editor)
        let request = try #require(panels.links.first)
        editor.localUndo.beginUndoGrouping()
        request.commit("https://example.com/")
        editor.localUndo.endUndoGrouping()
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(!board.validate(.link), "Linking needs selected text")
    }
}
