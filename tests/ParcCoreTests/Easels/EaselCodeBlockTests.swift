import Foundation
import Testing
@testable import ParcCore
@MainActor struct EaselCodeBlockTests {
    func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Code", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    func accepts(_ items: [EaselItem]) -> Bool {
        (try? EaselSession(inMemory: document(items), assets: [:])) != nil
    }

    @Test func aNewCodeBlockStartsEmptyWithItsLanguageSaved() throws {
        let block = EaselCodeBlock.item(at: .init(x: 10, y: 20), language: "typescript", zIndex: 3)
        #expect(block.kind == .code && block.text == "\n\n\n", "a new code block starts with four empty lines")
        #expect(block.frame.height == EaselCodeBlock.height(lines: 4), "a new code block is four lines tall")
        #expect(block.frame.width == EaselCodeBlock.defaultWidth && block.zIndex == 3, "a new code block takes the default width and layer")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(block)) ?? Data()
        #expect(String(decoding: data, as: UTF8.self).contains("\"language\":\"typescript\""), "the language is saved")
        #expect((try? JSONDecoder().decode(EaselItem.self, from: data)) == block, "a code block round-trips")
        let note = EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 10, height: 10))
        let plain = String(decoding: (try? encoder.encode(note)) ?? Data(), as: UTF8.self)
        #expect(!plain.contains("language"), "objects without a language leave it out of the file")
        let older = Data("{\"id\":\"\(UUID().uuidString)\",\"kind\":\"text\",\"frame\":{\"x\":0,\"y\":0,\"width\":10,\"height\":10},\"zIndex\":0,\"text\":\"\",\"color\":\"#252525\",\"points\":[]}".utf8)
        #expect((try? JSONDecoder().decode(EaselItem.self, from: older))?.language == nil, "older files open without a language")
        #expect(EaselCodeBlock.lineCount("") == 1 && EaselCodeBlock.lineCount("a\nb") == 2, "lines are counted by newlines")
        #expect(EaselCodeBlock.lineCount("a\r\nb\n") == 3, "Windows line endings count once per line")
        #expect(!EaselItemKind.code.holdsText, "code blocks keep plain text, never rich text")
    }

    @Test func codeBlockLanguagesAreValidatedWhenADocumentOpens() {
        let block = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "python", zIndex: 0)
        #expect(accepts([block]), "a code block with a language saves")
        var plain = block
        plain.language = nil
        #expect(accepts([plain]), "a plain text code block saves without a language")
        var future = block
        future.language = "future-lang2"
        #expect(accepts([future]), "a language from a newer Parc still opens")
        var spaced = block
        spaced.language = "Type Script"
        #expect(!accepts([spaced]), "a malformed language is refused")
        var long = block
        long.language = String(repeating: "a", count: 33)
        #expect(!accepts([long]), "an overlong language is refused")
        var empty = block
        empty.language = ""
        #expect(!accepts([empty]), "an empty language is refused")
        var text = EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 10, height: 10))
        text.language = "swift"
        #expect(!accepts([text]), "a language on a non-code object is refused")
        var rich = block
        rich.text = "let a = 1"
        rich.richText = EaselRichText(runs: [])
        #expect(!accepts([rich]), "rich text on a code block is refused")
    }

    @Test func aNewCodeBlockReusesTheLastLanguage() {
        #expect(EaselCodeBlock.newLanguage(remembered: nil) == "typescript", "the first block starts in TypeScript")
        #expect(EaselCodeBlock.newLanguage(remembered: "py") == "python", "the last language is reused")
        #expect(EaselCodeBlock.newLanguage(remembered: "plaintext") == nil, "plain text is remembered too")
        #expect(EaselCodeBlock.newLanguage(remembered: "klingon") == "typescript", "an unknown memory falls back to TypeScript")
        #expect(EaselCodeBlock.rememberedValue(nil) == "plaintext" && EaselCodeBlock.rememberedValue("swift") == "swift",
               "plain text and real languages are remembered distinctly")
        #expect(EaselCodeBlock.displayName(nil) == "Plain Text", "no language reads as plain text")
        #expect(EaselCodeBlock.displayName("typescript") == "TypeScript", "known languages use their proper names")
        #expect(EaselCodeBlock.displayName("future-lang") == "future-lang", "unknown languages show what was saved")
        #expect(EaselCodeBlock.language("tsx").id == "tsx" && EaselCodeBlock.language("nope").id == "plaintext", "languages resolve for highlighting")
        #expect(EaselCodeBlock.stored(.plainText) == nil, "plain text is stored as no language")
        #expect(NoteCodeLanguage.all.allSatisfy { EaselItem.isValidLanguage($0.id) }, "every Notes language is a valid stored value")
    }

    @Test func newCodeBlocksLandInTheMiddleAndCascade() {
        let visible = EaselRect(x: 100, y: 200, width: 800, height: 600)
        let origin = EaselCodeBlock.placedOrigin(in: visible, width: 440, height: 136, occupied: [])
        #expect(origin.x == 280 && origin.y == 320, "a typed code block lands in the middle of the view")
        let cascaded = EaselCodeBlock.placedOrigin(in: visible, width: 440, height: 136,
                                                   occupied: [.init(x: 280, y: 320, width: 440, height: 136)])
        #expect(cascaded.x == 304 && cascaded.y == 344, "a second block cascades instead of hiding the first")
        let source = EaselRect(x: 50, y: 60, width: 300, height: 100)
        let below = EaselCodeBlock.originBelow(source, height: 136, occupied: [source])
        #expect(below.x == 50 && below.y == 184, "the next block sits just below")
        let blocker = EaselRect(x: 80, y: 190, width: 100, height: 50)
        let skipped = EaselCodeBlock.originBelow(source, height: 136, occupied: [source, blocker])
        #expect(skipped.y == 264, "the next block skips past anything already below")
        let original = EaselRect(x: 100, y: 100, width: 400, height: 136)
        let wider = EaselCodeBlock.settledFrame(.init(x: 100, y: 90, width: 500, height: 300), original: original, lines: 5, keepsTop: true)
        #expect(wider == EaselRect(x: 100, y: 100, width: 500, height: EaselCodeBlock.height(lines: 5)), "height follows the lines and the top stays put")
        let narrow = EaselCodeBlock.settledFrame(.init(x: 450, y: 100, width: 50, height: 136), original: original, lines: 9, keepsTop: true)
        #expect(narrow.x == 340 && narrow.width == EaselCodeBlock.minimumWidth, "narrowing from the left keeps the right edge at the minimum width")
        let moved = EaselCodeBlock.settledFrame(.init(x: 140, y: 160, width: 400, height: 136), original: original, lines: 4, keepsTop: false)
        #expect(moved.y == 160 && moved.x == 140, "group transforms keep their placement")
    }

    @Test func codeBlocksExportAsLabelledEscapedCards() {
        var block = EaselCodeBlock.item(at: .init(x: 10, y: 20), language: "swift", zIndex: 0, width: 300, text: "let x = \"<a>\"")
        let fallback = EaselVectorExport.element(block, art: .init())
        #expect(fallback.contains("class=\"easel-code\""), "code blocks export as a card")
        #expect(fallback.contains(">Swift</text>"), "the card is labelled with its language")
        #expect(fallback.contains("let x = &quot;&lt;a&gt;&quot;"), "code is escaped")
        #expect(fallback.contains("var(--easel-code)"), "the card colour follows light and dark")
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
        block.language = nil
        #expect(EaselVectorExport.element(block, art: .init()).contains(">Plain Text</text>"), "plain blocks say so")
        let css = EaselVectorExport.codeCSS(.standard)
        #expect(css.contains("--easel-syntax-keyword:#6A1FC9") && css.contains("--easel-syntax-keyword:#C0A6FF"), "both syntax palettes are inlined")
        #expect(css.contains("prefers-color-scheme:dark"), "dark colours follow the viewer")
        var hostile = EaselCodePalette.standard
        hostile.light.syntax["bad;x"] = "red"
        #expect(!EaselVectorExport.codeCSS(hostile).contains("bad;x"), "odd palette names never reach the stylesheet")
        let html = EaselVectorExport.htmlDocument(document([block]), art: .init())
        #expect(html.contains("--easel-code:") && html.contains("class=\"easel-code\""), "HTML exports carry code blocks and their colours")
    }
}
