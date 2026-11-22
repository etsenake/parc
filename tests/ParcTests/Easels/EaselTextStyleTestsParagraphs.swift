import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

struct EaselTextStyleTestsParagraphs {
    private typealias Editor = EaselTextStyleTestsSupport.Editor

    @MainActor @Test
    func aNumberedListReportsItsOrderedMarkers() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let editor = Editor()
        let view = editor.view
        editor.load("One 👩🏽‍💻\nTwo\nThree")
        editor.grouped { view.changeParagraph(.numbers) }
        #expect(view.string == "\t1.\tOne 👩🏽‍💻\n\t2.\tTwo\n\t3.\tThree", "Numbered paragraphs have actual ordered markers: \(view.string.debugDescription)")
        #expect(view.paragraphKind() == .numbers, "Selected numbered paragraphs report actual state")
    }

    @MainActor @Test
    func headingTwoFormatsOnlyTheSelectedParagraph() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let editor = Editor()
        let view = editor.view
        editor.load("One\nTwo")
        view.setSelectedRange(NSRange(location: 1, length: 1))
        editor.grouped { view.changeParagraph(.heading2) }
        #expect((view.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 2, "Caret/range heading command formats full original paragraph")
        #expect((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 26, "Heading 2 uses recovered 26-point constant")
        #expect((view.attributedString().attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel ?? 0 == 0, "Heading stops before next paragraph")
    }

    @MainActor @Test
    func headingMetadataSurvivesThePrivateClipboard() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let editor = Editor()
        let view = editor.view
        editor.load("One\nTwo")
        view.setSelectedRange(NSRange(location: 1, length: 1))
        editor.grouped { view.changeParagraph(.heading2) }
        let rich = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        try rich.write(to: board)
        #expect(try! EaselStyledText.read(from: board) == rich, "Heading semantics persist in the shared carrier")
    }

    @MainActor @Test
    func decodingAHeadingRestoresItsLevelAndSystemFamily() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let editor = Editor()
        let view = editor.view
        editor.load("One\nTwo")
        view.setSelectedRange(NSRange(location: 1, length: 1))
        editor.grouped { view.changeParagraph(.heading2) }
        let rich = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        let decoded = try JSONDecoder().decode(EaselStyledText.self, from: JSONEncoder().encode(rich))
        #expect((decoded.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 2, "Persisted heading restores native paragraph metadata")
        #expect((decoded.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName == (view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName, "Heading's non-palette size restores actual system family without a named-font substitution")
    }

    @MainActor @Test
    func reopeningAnEaselPreservesHeadingMetadata() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let editor = Editor()
        let view = editor.view
        editor.load("One\nTwo")
        view.setSelectedRange(NSRange(location: 1, length: 1))
        editor.grouped { view.changeParagraph(.heading2) }
        let rich = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Paragraph component")
        try session.perform("Add heading") { $0.items = [EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 200, height: 100), text: rich.text, richText: rich.richText)] }
        #expect(try! EaselStore(directory: directory).load(session.document.id).document.items[0].richText == rich.richText, "Actual file-backed session preserves authored heading metadata")
    }

    @MainActor @Test
    func undoAndRedoRestoreHeadingAndListMetadata() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let editor = Editor()
        let view = editor.view
        editor.load("One 👩🏽‍💻\nTwo\nThree")
        editor.grouped { view.changeParagraph(.numbers) }
        let saved = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        editor.load("One\nTwo")
        view.setSelectedRange(NSRange(location: 1, length: 1))
        editor.grouped { view.changeParagraph(.heading2) }
        let rich = try EaselStyledText.capture(view.attributedString(), style: .init(), color: "#252525")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Paragraph component")
        try session.perform("Add heading") { $0.items = [EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 200, height: 100), text: rich.text, richText: rich.richText)] }
        try session.perform("Replace with list") { $0.items[0].text = saved.text; $0.items[0].richText = saved.richText }
        try session.undo()
        #expect(session.document.items[0].richText == rich.richText, "Document undo restores heading after list replacement")
        try session.redo()
        #expect(session.document.items[0].richText == saved.richText, "Document redo restores authored list metadata")
    }

    @MainActor @Test
    func restylingAHeadingKeepsItsParagraphSize() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let editor = Editor()
        let view = editor.view
        editor.load("One\nTwo")
        view.setSelectedRange(NSRange(location: 1, length: 1))
        editor.grouped { view.changeParagraph(.heading2) }
        #expect((view.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 2, "Caret/range heading command formats full original paragraph")
        #expect((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 26, "Heading 2 uses recovered 26-point constant")
        view.setSelectedRange(NSRange(location: 0, length: 3))
        editor.grouped { view.changeStyle(preservingSize: true) { $0.family = .mono } }
        #expect((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 26, "Family change preserves actual paragraph heading size")
        #expect(EaselTextAppearance.paletteFamily(view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as! NSFont) == .mono, "Family control actually changes a heading font")
    }

    @MainActor @Test
    func returnAfterAHeadingPreparesBodyTyping() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let editor = Editor()
        let view = editor.view
        editor.load("One\nTwo")
        view.setSelectedRange(NSRange(location: 1, length: 1))
        editor.grouped { view.changeParagraph(.heading2) }
        view.setSelectedRange(NSRange(location: 3, length: 0))
        editor.grouped { view.insertNewline(nil) }
        #expect((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headerLevel == 0, "Return after heading prepares body typing")
        #expect(view.string == "One\n\nTwo", "Heading Return keeps original content")
    }

    @MainActor @Test
    func startingAnEmptyListPlacesTheCaretAfterItsMarker() {
        let editor = Editor()
        let view = editor.view
        editor.load(""); editor.grouped { view.changeParagraph(.bullets) }
        #expect(view.string == "\t•\t" && view.selectedRange().location == 3, "Empty object list starts with a real marker and caret after it")
    }

    @MainActor @Test
    func typingInAnEmptyListKeepsItsMarker() {
        let editor = Editor()
        let view = editor.view
        editor.load(""); editor.grouped { view.changeParagraph(.bullets) }
        editor.grouped { view.insertText("Hello", replacementRange: view.selectedRange()) }
        #expect(view.string == "\t•\tHello", "Native typing retains authored list")
    }

    @MainActor @Test
    func returnContinuesTheListAfterTyping() {
        let editor = Editor()
        let view = editor.view
        editor.load(""); editor.grouped { view.changeParagraph(.bullets) }
        editor.grouped { view.insertText("Hello", replacementRange: view.selectedRange()) }
        editor.grouped { view.insertNewline(nil) }
        #expect(view.string == "\t•\tHello\n\t•\t", "Bullets continue after typed text")
        view.undo(nil)
        #expect(view.string == "\t•\tHello", "Return is one native undo transaction")
    }

    @MainActor @Test
    func paragraphFormattingExcludesAnUnselectedNextParagraph() {
        let editor = Editor()
        let view = editor.view
        editor.load("First\nSecond")
        view.setSelectedRange(NSRange(location: 0, length: 6))
        editor.grouped { view.changeParagraph(.bullets) }
        #expect(view.string == "\t•\tFirst\nSecond", "Selection ending at next paragraph start excludes that paragraph")
    }

    @MainActor @Test
    func compositionBlocksParagraphFormatCommands() {
        let editor = Editor()
        let view = editor.view
        editor.load("First\nSecond")
        view.setSelectedRange(NSRange(location: 0, length: 6))
        editor.grouped { view.changeParagraph(.bullets) }
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        editor.grouped { view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        let marked = view.attributedString()
        editor.grouped { view.changeParagraph(.heading1) }
        #expect(view.attributedString().isEqual(to: marked), "Paragraph format preserves an active native composition")
        editor.grouped { view.finishComposition() }
    }
}
