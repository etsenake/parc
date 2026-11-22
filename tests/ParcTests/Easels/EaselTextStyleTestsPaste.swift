import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

struct EaselTextStyleTestsPaste {
    @MainActor @Test
    func theEditorAdvertisesUrlOnlyPaste() throws {
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        #expect(view.readablePasteboardTypes.contains(.URL), "URL-only native paste is advertised")
    }

    @MainActor @Test
    func urlPasteLinksTheUnicodeLabel() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("Read café 👩🏽‍💻 now", style: .init(), color: "#194B93"))
        let label = (original.string as NSString).range(of: "café 👩🏽‍💻")
        original.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: label)
        view.textStorage?.setAttributedString(original); view.setSelectedRange(label)
        board.clearContents(); board.setString("https://example.com/new?q=one%20two", forType: .URL)
        view.localUndo.beginUndoGrouping(); #expect(view.pasteContent(from: board), "URL-only clipboard links the original selected words"); view.localUndo.endUndoGrouping()
        let pasted = try EaselRichTextCodec.snapshot(view.attributedString())
        #expect(view.string == original.string && pasted.runs.contains(where: { $0.attributes.link == "https://example.com/new?q=one%20two" && $0.length == label.length }), "Link paste keeps exact Unicode label and UTF-16 range")
        #expect((view.attributedString().attribute(.underlineStyle, at: label.location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue, "Existing label styling survives link paste")
        #expect(view.typingAttributes[.link] == nil && view.selectedRange() == NSRange(location: NSMaxRange(label), length: 0), "New typing stays outside the pasted link")
    }

    @MainActor @Test
    func nativeUndoAndRedoRestoreThePastedLink() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let original = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("Read café 👩🏽‍💻 now", style: .init(), color: "#194B93"))
        let label = (original.string as NSString).range(of: "café 👩🏽‍💻")
        original.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: label)
        view.textStorage?.setAttributedString(original); view.setSelectedRange(label)
        let stored = NSAttributedString(attributedString: view.attributedString())
        board.clearContents(); board.setString("https://example.com/new?q=one%20two", forType: .URL)
        view.localUndo.beginUndoGrouping(); _ = view.pasteContent(from: board); view.localUndo.endUndoGrouping()
        let pasted = try EaselRichTextCodec.snapshot(view.attributedString())
        view.undo(nil)
        #expect(view.attributedString().isEqual(to: stored) && view.selectedRange() == label, "One native undo restores original text, attributes and selection")
        view.redo(nil); #expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == pasted, "Redo restores exact pasted-link ranges")
    }

    @MainActor @Test
    func pastingOverASelfLabelledURLReplacesItsLabel() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        board.clearContents(); board.setString("https://example.com/new?q=one%20two", forType: .URL)
        let selfURL = "https://example.com/old"
        view.textStorage?.setAttributedString(NSAttributedString(string: selfURL, attributes: [.font: NSFont.systemFont(ofSize: 15), .link: URL(string: selfURL)!]))
        view.setSelectedRange(NSRange(location: 0, length: selfURL.utf16.count))
        view.localUndo.beginUndoGrouping(); #expect(view.pasteContent(from: board), "An existing self-labelled link accepts replacement"); view.localUndo.endUndoGrouping()
        #expect(view.string == "https://example.com/new?q=one%20two", "Self-labelled URL replacement changes both label and destination")
    }

    @MainActor @Test
    func urlTextPastesAtTheCaretAsALink() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        board.clearContents(); board.setString("https://example.org/", forType: .string)
        view.localUndo.beginUndoGrouping(); #expect(view.pasteContent(from: board), "Plain-string HTTP URL works at a caret"); view.localUndo.endUndoGrouping()
        #expect(view.string.hasSuffix("https://example.org/"), "Caret URL paste inserts its own label")
    }

    @MainActor @Test
    func plainPasteInsertsURLWordsWithoutALink() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        view.string = "Replace me"
        board.clearContents(); board.setString("https://example.org/", forType: .string)
        view.setSelectedRange(NSRange(location: 0, length: view.attributedString().length))
        view.localUndo.beginUndoGrouping(); #expect(view.pasteContent(from: board, plain: true), "Explicit plain paste bypasses selected-word linking"); view.localUndo.endUndoGrouping()
        #expect(view.string == "https://example.org/" && view.attributedString().attribute(.link, at: 0, effectiveRange: nil) == nil, "Plain paste inserts URL words without an active link")
    }

    @MainActor @Test
    func theRichCarrierTakesPriorityOverAURLShapedFallback() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let rich = EaselStyledText(text: "https://example.com/rich", style: .init(family: .mono, size: .h2), color: "#194B93")
        try rich.write(to: board)
        #expect(try! EaselClipboardURL.read(from: board) == nil, "Private rich carrier stays authoritative over its URL-shaped plain fallback")
    }

    @MainActor @Test(arguments: ["javascript:alert(1)", "file:///tmp/private", "https://user:password@example.com/", "two https://example.com links"])
    func unsupportedURLsRemainAvailableAsPlainText(_ raw: String) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString(raw, forType: .URL)
        #expect(try! EaselClipboardURL.read(from: board) == nil, "Non-web, credential and multiword values are not actionable URL pastes")
        #expect(try! EaselStyledText.plainText(from: board) == raw, "URL-only unsupported values remain available to explicit plain paste")
    }

    @MainActor @Test
    func anActiveCompositionRefusesURLPaste() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        board.clearContents(); board.setString("https://example.com/", forType: .URL)
        view.localUndo.beginUndoGrouping()
        view.setMarkedText("composing", selectedRange: NSRange(location: 9, length: 0), replacementRange: NSRange(location: 0, length: view.attributedString().length))
        view.localUndo.endUndoGrouping()
        let composition = NSAttributedString(attributedString: view.attributedString())
        #expect(!view.pasteContent(from: board) && view.hasMarkedText() && view.attributedString().isEqual(to: composition), "URL paste refuses native composition atomically")
        view.unmarkText()
    }

    @MainActor @Test
    func nonImageRtfAttachmentRefusesRichPaste() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let wrapper = FileWrapper(regularFileWithContents: Data("non-image file bytes".utf8)); wrapper.preferredFilename = "attachment.txt"
        let file = NSTextAttachment(fileWrapper: wrapper)
        let mixed = NSMutableAttributedString(string: "before ")
        mixed.append(NSAttributedString(attachment: file)); mixed.append(NSAttributedString(string: " after"))
        let rtfd = try mixed.data(from: NSRange(location: 0, length: mixed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        board.clearContents(); board.setData(rtfd, forType: .rtfd)
        let before = NSAttributedString(attributedString: view.attributedString()), selection = view.selectedRange(), generation = board.changeCount
        var failure: Error?; view.onClipboardError = { failure = $0 }
        let result = view.pasteContent(from: board)
        #expect(!result && failure is EaselTextClipboardError, "Non-image RTFD explicitly refuses instead of inventing file persistence")
        #expect(view.attributedString().isEqual(to: before) && view.selectedRange() == selection && board.changeCount == generation, "Refused attachment preserves selection, text and source clipboard")
    }

    @MainActor @Test
    func plainRtfPasteKeepsTheWordsAroundANonImageAttachment() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let wrapper = FileWrapper(regularFileWithContents: Data("non-image file bytes".utf8)); wrapper.preferredFilename = "attachment.txt"
        let file = NSTextAttachment(fileWrapper: wrapper)
        let mixed = NSMutableAttributedString(string: "before ")
        mixed.append(NSAttributedString(attachment: file)); mixed.append(NSAttributedString(string: " after"))
        let rtfd = try mixed.data(from: NSRange(location: 0, length: mixed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        board.clearContents(); board.setData(rtfd, forType: .rtfd)
        #expect(try! EaselStyledText.plainText(from: board) == "before  after", "Explicit plain fallback keeps surrounding words and omits the non-image attachment")
    }

    @MainActor @Test
    func plainPasteJoiningParagraphsNormalizesTheirStyle() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let paragraphs = NSMutableAttributedString(string: "one\ntwo", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        let first = NSMutableParagraphStyle(); first.alignment = .center
        let second = NSMutableParagraphStyle(); second.alignment = .right; second.headIndent = 20
        paragraphs.addAttribute(.paragraphStyle, value: first, range: NSRange(location: 0, length: 4))
        paragraphs.addAttribute(.paragraphStyle, value: second, range: NSRange(location: 4, length: 3))
        view.textStorage?.setAttributedString(paragraphs); view.setSelectedRange(NSRange(location: 2, length: 3))
        board.clearContents(); board.setString("X", forType: .string)
        view.localUndo.beginUndoGrouping(); let joined = view.pasteContent(from: board, plain: true); view.localUndo.endUndoGrouping()
        #expect(joined && view.string == "onXwo", "Plain paste joining differently styled paragraphs reports native success")
        let joinedParagraph = view.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(joinedParagraph == view.attributedString().attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle, "Native paragraph normalization gives the joined line one paragraph style")
    }

    @MainActor @Test
    func undoingAPlainPasteRestoresBothParagraphStyles() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = EaselStyledTextView(frame: .zero)
        view.isEditable = true; view.isRichText = true; view.allowsUndo = true
        view.localUndo.groupsByEvent = false
        let paragraphs = NSMutableAttributedString(string: "one\ntwo", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        let first = NSMutableParagraphStyle(); first.alignment = .center
        let second = NSMutableParagraphStyle(); second.alignment = .right; second.headIndent = 20
        paragraphs.addAttribute(.paragraphStyle, value: first, range: NSRange(location: 0, length: 4))
        paragraphs.addAttribute(.paragraphStyle, value: second, range: NSRange(location: 4, length: 3))
        view.textStorage?.setAttributedString(paragraphs); view.setSelectedRange(NSRange(location: 2, length: 3))
        let beforeJoin = NSAttributedString(attributedString: view.attributedString())
        board.clearContents(); board.setString("X", forType: .string)
        view.localUndo.beginUndoGrouping(); _ = view.pasteContent(from: board, plain: true); view.localUndo.endUndoGrouping()
        view.undo(nil)
        #expect(view.attributedString().isEqual(to: beforeJoin) && view.selectedRange() == NSRange(location: 2, length: 3), "One undo restores both original paragraph styles and selection")
    }

    @MainActor @Test
    func urlPasteRefusesTextOverItsByteBudget() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString(String(repeating: "x", count: 1_048_577), forType: .URL)
        #expect(throws: (any Error).self, "URL payloads obey the text byte budget") { _ = try EaselClipboardURL.read(from: board) }
    }
}
