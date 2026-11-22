import Foundation
import Testing
@testable import ParcCore

struct EaselCodeBlockExportTests {
    func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Code", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    @Test
    func codeBlocksExportAsLabelledEscapedCards() {
        let block = EaselCodeBlock.item(at: .init(x: 10, y: 20), language: "swift", zIndex: 0, width: 300, text: "let x = \"<a>\"")
        let fallback = EaselVectorExport.element(block, art: .init())
        #expect(fallback.contains("class=\"easel-code\""), "code blocks export as a card")
        #expect(fallback.contains(">Swift</text>"), "the card is labelled with its language")
        #expect(fallback.contains("let x = &quot;&lt;a&gt;&quot;"), "code is escaped")
        #expect(fallback.contains("var(--easel-code)"), "the card colour follows light and dark")
    }

    @Test
    func highlightedCodeExportsItsRunsWithSyntaxStyles() {
        let block = EaselCodeBlock.item(at: .init(x: 10, y: 20), language: "swift", zIndex: 0, width: 300, text: "let x = \"<a>\"")
        var keyword = EaselVectorTextRun(x: 16, y: 50, text: "let", fontFamily: EaselVectorExport.codeFontFamily, fontSize: 14)
        keyword.color = "#6A1FC9"
        keyword.syntax = "keyword"
        var comment = EaselVectorTextRun(x: 16, y: 72, text: "// hi", fontFamily: EaselVectorExport.codeFontFamily, fontSize: 14)
        comment.italic = true
        comment.syntax = "comment"
        let plainRun = EaselVectorTextRun(x: 50, y: 50, text: " x", fontFamily: EaselVectorExport.codeFontFamily, fontSize: 14)
        var art = EaselVectorArt()
        art.texts[block.id] = EaselVectorText(runs: [keyword, comment, plainRun])
        let svg = EaselVectorExport.element(block, art: art)
        #expect(svg.contains("fill:var(--easel-syntax-keyword,#6A1FC9)"), "keywords export highlighted with a light fallback")
        #expect(svg.contains("font-style:italic;fill:var(--easel-syntax-comment,var(--easel-code-ink))"), "comments keep their italic")
        #expect(svg.contains("fill:var(--easel-code-ink,var(--easel-code-ink))") || svg.contains("fill:var(--easel-code-ink"), "plain code uses the code ink")
        #expect(svg.contains("translate(10 20)"), "runs are placed relative to the block")
    }

    @Test
    func aPlainCodeCardIsLabelledPlainText() {
        var block = EaselCodeBlock.item(at: .init(x: 10, y: 20), language: "swift", zIndex: 0, width: 300, text: "let x = \"<a>\"")
        block.language = nil
        #expect(EaselVectorExport.element(block, art: .init()).contains(">Plain Text</text>"), "plain blocks say so")
    }

    @Test
    func exportedStylesIncludeBothSyntaxPalettes() {
        let css = EaselVectorExport.codeCSS(.standard)
        #expect(css.contains("--easel-syntax-keyword:#6A1FC9") && css.contains("--easel-syntax-keyword:#C0A6FF"), "both syntax palettes are inlined")
        #expect(css.contains("prefers-color-scheme:dark"), "dark colours follow the viewer")
    }

    @Test
    func invalidSyntaxNamesStayOutOfTheStylesheet() {
        var hostile = EaselCodePalette.standard
        hostile.light.syntax["bad;x"] = "red"
        #expect(!EaselVectorExport.codeCSS(hostile).contains("bad;x"), "odd palette names never reach the stylesheet")
    }

    @Test
    func htmlExportsIncludeCodeBlocksAndTheirColours() {
        var block = EaselCodeBlock.item(at: .init(x: 10, y: 20), language: "swift", zIndex: 0, width: 300, text: "let x = \"<a>\"")
        block.language = nil
        let html = EaselVectorExport.htmlDocument(document([block]), art: .init())
        #expect(html.contains("--easel-code:") && html.contains("class=\"easel-code\""), "HTML exports carry code blocks and their colours")
    }
}
