import Foundation
import Testing
@testable import ParcCore

struct NoteMermaidHtmlTests {
    private func diagram(_ source: String, mode: NoteDiagramMode? = nil, language: String = "mermaid") -> NoteBlock {
        var block = NoteBlock(.code, text: NoteText(source))
        block.props.language = language
        block.props.diagramMode = mode
        return block
    }

    private func html(_ mode: NoteDiagramMode?, art: NoteDiagramArt?) -> String {
        let source = "graph TD\n  A --> B"
        return NotePageHTML.document(NotePage(blocks: [diagram(source, mode: mode)]), title: "T", assets: { _ in nil }, embedImages: false,
                              diagramArt: { _ in art })
    }

    private let art = NoteDiagramArt(light: "<svg id=\"light\"></svg>", dark: "<svg id=\"dark\"></svg>")

    @Test func previewExportsTheLightAndDarkDrawingsWithoutSource() {
        let preview = html(nil, art: art)
        #expect(preview.contains("<figure data-language=\"mermaid\" class=\"diagram\">"), "Preview exports a diagram figure")
        #expect(preview.contains("<div class=\"diagram-art diagram-light\"><svg id=\"light\"></svg></div>"), "the light SVG is embedded")
        #expect(preview.contains("<div class=\"diagram-art diagram-dark\"><svg id=\"dark\"></svg></div>"), "the dark SVG rides along")
        #expect(!preview.contains("<pre>"), "Preview leaves the code out")
    }

    @Test func splitExportsTheSourceBeforeTheDrawing() {
        let split = html(.split, art: art)
        #expect(split.contains("class=\"diagram split\""), "Split marks the figure")
        guard let code = split.range(of: "<pre><code class=\"language-mermaid\">"), let drawing = split.range(of: "<div class=\"diagram-art diagram-light\">") else {
            Issue.record("Split exports code and drawing: \(split)")
            return
        }
        #expect(code.lowerBound < drawing.lowerBound, "Split puts the code above the drawing")
    }

    @Test func codeModeExportsOnlyTheSource() {
        let codeOnly = html(.code, art: art)
        let codeBody = codeOnly.components(separatedBy: "<main").last ?? codeOnly
        #expect(!codeBody.contains("diagram-art") && codeBody.contains("data-language=\"mermaid\"><code"), "Code exports a plain code block")
    }

    @Test func aMissingDrawingFallsBackToCode() {
        let missing = html(nil, art: nil)
        let missingBody = missing.components(separatedBy: "<main").last ?? missing
        #expect(!missingBody.contains("diagram-art") && missingBody.contains("language-mermaid"), "without a drawing the code still exports")
    }

    @Test func lightModeHidesTheDarkDrawing() {
        #expect(NotePageHTMLStyle.css.contains(".diagram-dark{display:none}"), "the dark drawing hides in light mode")
    }

    @Test func clipboardHtmlKeepsPlainMermaidCode() {
        let source = "graph TD\n  A --> B"
        let fragment = NotePageHTML.fragment([diagram(source)])
        #expect(fragment.contains("language-mermaid") && !fragment.contains("diagram-art"), "clipboard HTML keeps plain code")
    }
}
