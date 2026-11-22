import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

struct EaselTextStyleTestsParagraphMarkdown {
    private typealias Editor = EaselTextStyleTestsSupport.Editor

    struct Heading: CustomTestStringConvertible {
        let prefix: String
        let level: Int
        let size: CGFloat
        var testDescription: String { "Heading \(level)" }

        static let cases = [
            Self(prefix: "# ", level: 1, size: 32),
            Self(prefix: "## ", level: 2, size: 26),
            Self(prefix: "### ", level: 3, size: 22),
            Self(prefix: "#### ", level: 4, size: 19),
        ]
    }

    @MainActor @Test(arguments: Heading.cases)
    func aTypedHeadingPrefixAppliesItsLevelAndSize(_ heading: Heading) {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type(heading.prefix)
        #expect(view.string.isEmpty && view.selectedRange().location == 0, "Heading prefix transforms at the typed space")
        #expect((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headerLevel == heading.level, "Empty heading retains semantic typing state")
        editor.type("Heading")
        #expect((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == heading.size, "Typed heading uses recovered paragraph size")
    }

    @MainActor @Test(arguments: Heading.cases)
    func returnAfterATypedHeadingContinuesInBodyStyle(_ heading: Heading) {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type(heading.prefix)
        editor.type("Heading")
        editor.grouped { view.insertNewline(nil) }; editor.type("body")
        #expect((view.attributedString().attribute(.paragraphStyle, at: view.attributedString().length - 1, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel == 0, "Heading Return retains existing body continuation")
    }

    @MainActor @Test(arguments: ["- ", "* ", "1. ", "1.\t", "1.\n"])
    func aTypedListPrefixCreatesANativeMarker(_ prefix: String) {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type(String(prefix.dropLast()))
        editor.grouped {
            if prefix.last == "\t" { view.insertTab(nil) }
            else if prefix.last == "\n" { view.insertNewline(nil) }
            else { view.insertText(" ", replacementRange: view.selectedRange()) }
        }
        let numbered = prefix.hasPrefix("1.")
        #expect(view.string == (numbered ? "\t1.\t" : "\t•\t"), "List prefix becomes an actual native marker: \(prefix.debugDescription)")
    }

    @MainActor @Test(arguments: ["- ", "* ", "1. ", "1.\t", "1.\n"])
    func returnContinuesATypedList(_ prefix: String) {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type(String(prefix.dropLast()))
        editor.grouped {
            if prefix.last == "\t" { view.insertTab(nil) }
            else if prefix.last == "\n" { view.insertNewline(nil) }
            else { view.insertText(" ", replacementRange: view.selectedRange()) }
        }
        let numbered = prefix.hasPrefix("1.")
        editor.type("Item"); editor.grouped { view.insertNewline(nil) }
        #expect(view.string.hasSuffix(numbered ? "\n\t2.\t" : "\n\t•\t"), "Typed list continues through existing paragraph authoring")
    }

    @MainActor @Test(arguments: ["- ", "* ", "1. ", "1.\t", "1.\n"])
    func returnExitsAnEmptyTypedList(_ prefix: String) {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(""); editor.type(String(prefix.dropLast()))
        editor.grouped {
            if prefix.last == "\t" { view.insertTab(nil) }
            else if prefix.last == "\n" { view.insertNewline(nil) }
            else { view.insertText(" ", replacementRange: view.selectedRange()) }
        }
        editor.type("Item"); editor.grouped { view.insertNewline(nil) }
        editor.grouped { view.insertNewline(nil) }
        #expect(view.paragraphKind() == .text, "Empty item exits the typed list using the existing native command")
    }

    @MainActor @Test(arguments: [1, 6])
    func tabPrefixesChooseTheListDepth(_ depth: Int) {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(String(repeating: "\t", count: depth)); editor.type("- ")
        #expect((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.count == depth + 1, "Recovered tab prefix maps to actual nested list depth")
    }

    @MainActor @Test
    func anUnsupportedListDepthStaysLiteral() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load(String(repeating: "\t", count: 7)); editor.type("- ")
        #expect(view.string == String(repeating: "\t", count: 7) + "- ", "Unsupported eighth list depth remains literal")
    }

    @MainActor @Test
    func aHeadingRefusesListConversion() {
        let editor = Editor(usesMarkdownTyping: true)
        let view = editor.view
        editor.load("# "); editor.grouped { view.changeParagraph(.heading1) }; editor.type("- ")
        #expect(view.string == "# - ", "Existing heading metadata guards list conversion")
    }
}
