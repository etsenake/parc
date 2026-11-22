import Foundation
import Testing
@testable import ParcCore

struct NoteMermaidModeTests {
    private func diagram(_ source: String, mode: NoteDiagramMode? = nil, language: String = "mermaid") -> NoteBlock {
        var block = NoteBlock(.code, text: NoteText(source))
        block.props.language = language
        block.props.diagramMode = mode
        return block
    }

    struct Mode: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let mode: NoteDiagramMode
        let editing: Bool
        let expected: NoteDiagramMode
    }

    private static let modes = [
        Mode(testDescription: "preview while editing", mode: .preview, editing: true, expected: .split),
        Mode(testDescription: "preview at rest", mode: .preview, editing: false, expected: .preview),
        Mode(testDescription: "code while editing", mode: .code, editing: true, expected: .code),
        Mode(testDescription: "split at rest", mode: .split, editing: false, expected: .split),
    ]

    @Test func mermaidHasACanonicalLanguageName() {
        #expect(NoteCodeLanguage.named("mermaid")?.name == "Mermaid", "Mermaid is a real code language")
    }

    @Test func mmdResolvesToTheMermaidLanguage() {
        #expect(NoteCodeLanguage.named("mmd")?.id == "mermaid", "the .mmd alias names Mermaid")
    }

    @Test func mermaidLanguageMatchingIgnoresCaseAndPadding() {
        #expect(NoteMermaid.isMermaid("Mermaid") && NoteMermaid.isMermaid(" mermaid "), "language matching ignores case and padding")
    }

    @Test func otherLanguagesAreNotMermaid() {
        #expect(!NoteMermaid.isMermaid("markdown") && !NoteMermaid.isMermaid(""), "other languages aren't diagrams")
    }

    @Test func mermaidCodeIsRecognizedAsADiagram() {
        #expect(NoteMermaid.isDiagram(diagram("graph TD")), "a mermaid code block is a diagram")
    }

    @Test func nonCodeBlocksAreNotDiagrams() {
        #expect(!NoteMermaid.isDiagram(NoteBlock(.paragraph, text: NoteText("mermaid"))), "only code blocks draw")
    }

    @Test func mermaidCodeGetsSyntaxHighlighting() {
        #expect(!NoteSyntaxHighlighter.tokens(in: "flowchart TD\n  A --> B %% note", language: "mermaid").isEmpty, "Mermaid code gets highlighted")
    }

    @Test func mermaidPercentMarkersStartComments() {
        let tokens = NoteSyntaxHighlighter.tokens(in: "%% hi\ngraph LR", language: "mermaid")
        #expect(tokens.contains { $0.kind == .comment && $0.range == 0..<5 }, "%% starts a comment")
    }

    @Test func mermaidDiagramTypesAreHighlightedAsKeywords() {
        let tokens = NoteSyntaxHighlighter.tokens(in: "%% hi\ngraph LR", language: "mermaid")
        #expect(tokens.contains { $0.kind == .keyword }, "diagram types read as keywords")
    }

    @Test func diagramsDefaultToPreview() {
        #expect(NoteMermaid.storedMode(of: diagram("graph TD")) == .preview, "diagrams default to Preview")
    }

    @Test func anExplicitDiagramModeIsUsed() {
        #expect(NoteMermaid.storedMode(of: diagram("graph TD", mode: .split)) == .split, "a chosen mode sticks")
    }

    @Test(arguments: modes) func thePresentedModeAccountsForEditing(_ example: Mode) {
        #expect(NoteMermaid.presentedMode(stored: example.mode, editing: example.editing) == example.expected)
    }

    @Test func theToolbarNamesItsThreeModes() {
        #expect(NoteDiagramMode.allCases.map(\.title) == ["Code", "Preview", "Split"], "the toolbar reads Code, Preview, Split")
    }

    @Test func previewShowsOnlyTheDrawing() {
        #expect(!NoteDiagramMode.preview.showsCode && NoteDiagramMode.preview.showsDiagram, "Preview hides the code")
    }

    @Test func codeShowsOnlyTheSource() {
        #expect(NoteDiagramMode.code.showsCode && !NoteDiagramMode.code.showsDiagram, "Code hides the drawing")
    }

    @Test func splitShowsSourceAndDrawing() {
        #expect(NoteDiagramMode.split.showsCode && NoteDiagramMode.split.showsDiagram, "Split shows both")
    }
}
