import AppKit

@main
struct EaselCodeBlockStyleTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    @MainActor static func main() {
        styles()
        cache()
        restyling()
        layout()
        export()
        print("EaselCodeBlockStyleTests: \(assertions) assertions passed")
    }

    @MainActor static func oblique(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        ((attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0
    }

    @MainActor static func underlined(_ storage: NSAttributedString) -> Bool {
        var found = false
        storage.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if ((value as? NSNumber)?.intValue ?? 0) != 0 { found = true; stop.pointee = true }
        }
        return found
    }

    @MainActor static func styles() {
        let python = EaselCodeBlockStyle.attributed("# note\nreturn 1", language: "python")
        let comment = python.attributes(at: 0, effectiveRange: nil)
        expect(oblique(comment), "comments slant like Notes' code blocks")
        expect(comment[.easelSyntaxFamily] as? String == "comment", "comments carry their family for export")
        expect((comment[.foregroundColor] as? NSColor) == NoteTheme.syntaxColor("comment"), "comments use the Notes comment colour")
        let keyword = python.attributes(at: 7, effectiveRange: nil)
        expect(keyword[.easelSyntaxFamily] as? String == "keyword" && !oblique(keyword), "keywords are coloured but upright")
        let markdown = EaselCodeBlockStyle.attributed("# Heading\n\nSee [docs](https://example.com)", language: "markdown")
        let heading = markdown.attributes(at: 2, effectiveRange: nil)
        let font = heading[.font] as? NSFont
        expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "headings turn bold")
        expect(underlined(markdown), "links are underlined")
        let plain = EaselCodeBlockStyle.attributed("let x = 1", language: nil)
        expect(plain.attributes(at: 0, effectiveRange: nil)[.easelSyntaxFamily] == nil, "plain text has no highlighting")
    }

    @MainActor static func cache() {
        let code = "let value\(UInt32.random(in: 1...UInt32.max)) = 1"
        let before = EaselCodeTokenCache.misses
        _ = EaselCodeLayout(code: code, language: "swift", width: 300)
        _ = EaselCodeLayout(code: code, language: "swift", width: 520)
        _ = EaselCodeLayout(code: code, language: "swift", width: 180)
        expect(EaselCodeTokenCache.misses == before + 1, "resizing re-lays out the code without re-reading it")
        _ = EaselCodeLayout(code: code, language: "python", width: 300)
        expect(EaselCodeTokenCache.misses == before + 2, "a new language reads the code again")
        expect(EaselCodeTokenCache.cached(code, language: "swift") != nil, "tokens are kept by text and language")
    }

    @MainActor static func restyling() {
        let base = EaselCodeBlockStyle.attributes(language: "python")
        let storage = NSTextStorage(string: "# hi\nx = 1", attributes: base)
        EaselCodeBlockStyle.apply(EaselCodeTokenCache.tokens(storage.string, language: EaselCodeBlock.language("python")), to: storage, base: base)
        expect(oblique(storage.attributes(at: 0, effectiveRange: nil)), "the editor's storage gets the slant too")
        storage.replaceCharacters(in: NSRange(location: 0, length: 4), with: "y = ")
        EaselCodeBlockStyle.apply(EaselCodeTokenCache.tokens(storage.string, language: EaselCodeBlock.language("python")), to: storage, base: base)
        expect(!oblique(storage.attributes(at: 0, effectiveRange: nil)), "restyling clears styles that no longer apply")
        expect(storage.string == "y = \nx = 1", "restyling never touches the text")
        let empty = NSTextStorage(string: "", attributes: base)
        EaselCodeBlockStyle.apply([], to: empty, base: base)
        expect(empty.length == 0, "an empty block restyles safely")
    }

    @MainActor static func layout() {
        expect(EaselCodeLayout(code: EaselCodeBlock.starterText, language: "typescript", width: 440).lineCount == 4, "a new block lays out four lines")
        expect(EaselCodeLayout(code: "a\nb\nc", language: nil, width: 440).lineCount == 3, "each line counts once")
        let long = String(repeating: "word ", count: 60)
        expect(EaselCodeLayout(code: long, language: nil, width: 200).lineCount > 1, "long lines wrap at the card's edge")
        expect(EaselCodeLayout(code: long, language: nil, width: 4000).lineCount == 1, "wide cards keep long lines whole")
        let item = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "swift", zIndex: 0, width: 200, text: long)
        expect(EaselCodeLayoutCache.height(for: item) == EaselCodeBlock.height(lines: EaselCodeLayout(code: long, language: "swift", width: 200).lineCount),
               "the cached height follows the wrapped lines")
    }

    @MainActor static func export() {
        let item = EaselCodeBlock.item(at: .init(x: 10, y: 20), language: "python", zIndex: 0, width: 400, text: "# hi\nreturn\tx")
        let runs = EaselCodeLayout.vectorText(item).runs
        let comment = runs.first { $0.text == "# hi" }
        expect(comment?.italic == true && comment?.syntax == "comment", "exported comments stay italic and know their colour")
        let keyword = runs.first { $0.text == "return" }
        expect(keyword?.syntax == "keyword" && keyword?.italic == false, "exported keywords keep their colour")
        expect(runs.allSatisfy { !$0.text.contains("\t") && !$0.text.contains("\n") }, "tabs and newlines split runs")
        let x = runs.first { $0.text == "x" }
        expect((x?.x ?? 0) > (keyword?.x ?? 0) + 30, "text after a tab starts at the tab stop")
        expect(runs.allSatisfy { $0.x >= EaselCodeBlock.sidePadding && $0.y > EaselCodeBlock.headerHeight }, "runs sit inside the code area")
        let link = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "markdown", zIndex: 0, text: "[docs](https://example.com)")
        expect(EaselCodeLayout.vectorText(link).runs.contains { $0.underline }, "exported links stay underlined")
        let rects = EaselCodeLayout.rects(for: 0..<4, in: item) ?? []
        expect(!rects.isEmpty && rects.allSatisfy { $0.minX >= 10 + EaselCodeBlock.sidePadding - 3 && $0.minY >= 20 + EaselCodeBlock.headerHeight - 2 },
               "find highlights land on the code itself")
        expect(EaselCodeLayout.rects(for: 0..<999, in: item) == nil, "out-of-range matches draw nothing")
    }
}
