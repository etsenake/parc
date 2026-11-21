import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteMermaidTests {
    func diagram(_ source: String, mode: NoteDiagramMode? = nil, language: String = "mermaid") -> NoteBlock {
        var block = NoteBlock(.code, text: NoteText(source))
        block.props.language = language
        block.props.diagramMode = mode
        return block
    }

    @Test func language() {
        #expect(NoteCodeLanguage.named("mermaid")?.name == "Mermaid", "Mermaid is a real code language")
        #expect(NoteCodeLanguage.named("mmd")?.id == "mermaid", "the .mmd alias names Mermaid")
        #expect(NoteMermaid.isMermaid("Mermaid") && NoteMermaid.isMermaid(" mermaid "), "language matching ignores case and padding")
        #expect(!NoteMermaid.isMermaid("markdown") && !NoteMermaid.isMermaid(""), "other languages aren't diagrams")
        #expect(NoteMermaid.isDiagram(diagram("graph TD")), "a mermaid code block is a diagram")
        #expect(!NoteMermaid.isDiagram(NoteBlock(.paragraph, text: NoteText("mermaid"))), "only code blocks draw")
        #expect(!NoteSyntaxHighlighter.tokens(in: "flowchart TD\n  A --> B %% note", language: "mermaid").isEmpty, "Mermaid code gets highlighted")
        let tokens = NoteSyntaxHighlighter.tokens(in: "%% hi\ngraph LR", language: "mermaid")
        #expect(tokens.contains { $0.kind == .comment && $0.range == 0..<5 }, "%% starts a comment")
        #expect(tokens.contains { $0.kind == .keyword }, "diagram types read as keywords")
    }

    @Test func modes() {
        #expect(NoteMermaid.storedMode(of: diagram("graph TD")) == .preview, "diagrams default to Preview")
        #expect(NoteMermaid.storedMode(of: diagram("graph TD", mode: .split)) == .split, "a chosen mode sticks")
        #expect(NoteMermaid.presentedMode(stored: .preview, editing: true) == .split, "editing a previewed diagram shows the code too")
        #expect(NoteMermaid.presentedMode(stored: .preview, editing: false) == .preview, "resting diagrams show just the drawing")
        #expect(NoteMermaid.presentedMode(stored: .code, editing: true) == .code, "Code stays Code while typing")
        #expect(NoteMermaid.presentedMode(stored: .split, editing: false) == .split, "Split stays Split")
        #expect(NoteDiagramMode.allCases.map(\.title) == ["Code", "Preview", "Split"], "the toolbar reads Code, Preview, Split")
        #expect(!NoteDiagramMode.preview.showsCode && NoteDiagramMode.preview.showsDiagram, "Preview hides the code")
        #expect(NoteDiagramMode.code.showsCode && !NoteDiagramMode.code.showsDiagram, "Code hides the drawing")
        #expect(NoteDiagramMode.split.showsCode && NoteDiagramMode.split.showsDiagram, "Split shows both")
    }

    @Test func markdown() {
        let source = "flowchart TD\n  A --> B"
        let plain = NoteMarkdown.serialize(NotePage(blocks: [diagram(source)]))
        #expect(plain == "```mermaid\n" + source + "\n```\n", "a previewed diagram stays a plain fence GitHub draws: \(plain.debugDescription)")
        let explicitPreview = NoteMarkdown.serialize(NotePage(blocks: [diagram(source, mode: .preview)]))
        #expect(explicitPreview == plain, "Preview is the default, so it writes nothing extra")
        for mode in [NoteDiagramMode.code, .split] {
            let written = NoteMarkdown.serialize(NotePage(blocks: [diagram(source, mode: mode)]))
            #expect(written.hasPrefix("```mermaid\n" + source + "\n```\n"), "the fence itself stays plain in \(mode.title)")
            #expect(written.contains("<!-- parc view=\"\(mode.rawValue)\" -->"), "\(mode.title) rides along in invisible metadata: \(written)")
            let read = NoteMarkdown.parse(written).blocks
            #expect(read.count == 1 && read[0].kind == .code, "the metadata doesn't become a block")
            #expect(read[0].props.diagramMode == mode, "\(mode.title) survives the round trip")
            #expect(read[0].props.language == "mermaid" && read[0].text.string == source, "the diagram source survives the round trip")
            #expect(NoteMarkdown.serialize(NotePage(blocks: read)) == written, "\(mode.title) writes back byte for byte")
        }
        let wrapped = diagram(source, mode: .split)
        var both = wrapped
        both.props.wrap = true
        let combined = NoteMarkdown.serialize(NotePage(blocks: [both]))
        let reread = NoteMarkdown.parse(combined).blocks.first
        #expect(reread?.props.wrap == true && reread?.props.diagramMode == .split, "view shares the comment with wrap: \(combined)")
        let other = NoteMarkdown.serialize(NotePage(blocks: [diagram("print(1)", mode: .split, language: "python")]))
        #expect(!other.contains("view="), "only Mermaid blocks remember a view")
        let previewTag = NoteMarkdown.parse("```mermaid\ngraph TD\n```\n<!-- parc view=\"preview\" -->\n").blocks.first
        #expect(previewTag?.props.diagramMode == nil, "an explicit preview tag reads as the default")
        let junk = NoteMarkdown.parse("```mermaid\ngraph TD\n```\n<!-- parc view=\"sideways\" -->\n").blocks.first
        #expect(junk?.props.diagramMode == nil && junk?.text.string == "graph TD", "unknown views are ignored")
        let archived = try? JSONDecoder().decode(NoteBlock.self, from: JSONEncoder().encode(wrapped))
        #expect(archived?.props.diagramMode == .split, "the clipboard archive keeps the view")
    }

    @Test func exportHTML() {
        let source = "graph TD\n  A --> B"
        let art = NoteDiagramArt(light: "<svg id=\"light\"></svg>", dark: "<svg id=\"dark\"></svg>")
        func html(_ mode: NoteDiagramMode?, art: NoteDiagramArt?) -> String {
            NotePageHTML.document(NotePage(blocks: [diagram(source, mode: mode)]), title: "T", assets: { _ in nil }, embedImages: false,
                                  diagramArt: { _ in art })
        }
        let preview = html(nil, art: art)
        #expect(preview.contains("<figure data-language=\"mermaid\" class=\"diagram\">"), "Preview exports a diagram figure")
        #expect(preview.contains("<div class=\"diagram-art diagram-light\"><svg id=\"light\"></svg></div>"), "the light SVG is embedded")
        #expect(preview.contains("<div class=\"diagram-art diagram-dark\"><svg id=\"dark\"></svg></div>"), "the dark SVG rides along")
        #expect(!preview.contains("<pre>"), "Preview leaves the code out")
        let split = html(.split, art: art)
        #expect(split.contains("class=\"diagram split\""), "Split marks the figure")
        guard let code = split.range(of: "<pre><code class=\"language-mermaid\">"), let drawing = split.range(of: "<div class=\"diagram-art diagram-light\">") else {
            Issue.record("Split exports code and drawing: \(split)")
            return
        }
        #expect(code.lowerBound < drawing.lowerBound, "Split puts the code above the drawing")
        let codeOnly = html(.code, art: art)
        let codeBody = codeOnly.components(separatedBy: "<main").last ?? codeOnly
        #expect(!codeBody.contains("diagram-art") && codeBody.contains("data-language=\"mermaid\"><code"), "Code exports a plain code block")
        let missing = html(nil, art: nil)
        let missingBody = missing.components(separatedBy: "<main").last ?? missing
        #expect(!missingBody.contains("diagram-art") && missingBody.contains("language-mermaid"), "without a drawing the code still exports")
        #expect(NotePageHTMLStyle.css.contains(".diagram-dark{display:none}"), "the dark drawing hides in light mode")
        let fragment = NotePageHTML.fragment([diagram(source)])
        #expect(fragment.contains("language-mermaid") && !fragment.contains("diagram-art"), "clipboard HTML keeps plain code")
    }

    @Test func theme() {
        let light = NoteMermaidTheme.note(dark: false)
        let dark = NoteMermaidTheme.note(dark: true)
        #expect(light != dark, "light and dark themes differ")
        #expect(light.variables["primaryTextColor"] == "#1F1B2E" && dark.variables["primaryTextColor"] == "#EDEBFA", "labels use Parc's note ink")
        #expect(light.fontFamily.hasPrefix("\"Nunito\"") && light.faces.contains("700 16px \"Nunito\""), "standard pages draw in Nunito")
        #expect(NoteMermaidTheme.note(dark: false, font: .serif).fontFamily.hasPrefix("\"EB Garamond\""), "serif pages draw in EB Garamond")
        #expect(NoteMermaidTheme.note(dark: false, font: .mono).fontFamily.hasPrefix("\"Space Mono\""), "mono pages draw in Space Mono")
        #expect(NoteMermaidTheme.note(dark: false, font: .wide).fontFamily.hasPrefix("\"ParcWide\""), "wide pages draw in ParcWide")
        #expect(NoteMermaidTheme.note(dark: false, small: true).fontSize < light.fontSize, "small text shrinks diagram labels")
        let configuration = light.configuration(seed: "seed")
        #expect(configuration["securityLevel"] as? String == "strict", "diagrams run in strict security")
        #expect(configuration["suppressErrorRendering"] as? Bool == true, "Mermaid's own error bomb stays hidden")
        #expect(configuration["theme"] as? String == "base" && configuration["deterministicIDSeed"] as? String == "seed", "the base theme carries Parc's variables with stable ids")
        let variables = configuration["themeVariables"] as? [String: Any]
        #expect(variables?["darkMode"] as? Bool == false && (variables?["xyChart"] as? [String: String])?["plotColorPalette"] != nil, "theme variables include dark mode and the chart palette")
        for index in 0..<12 {
            #expect(light.variables["cScale\(index)"] != nil && dark.variables["cScale\(index)"] != nil, "section colour \(index) is themed")
            #expect(light.variables["pie\(index + 1)"] != nil, "pie slice \(index + 1) is themed")
        }
        let parsed = (try? JSONSerialization.jsonObject(with: Data(NoteMermaidRequest(source: "x", theme: light).configurationJSON.utf8))) as? [String: Any]
        #expect(parsed?["fontFamily"] as? String == light.fontFamily, "the configuration is valid JSON")
        let faces = (try? JSONSerialization.jsonObject(with: Data(light.facesJSON.utf8))) as? [String]
        #expect(faces == light.faces, "font faces travel as a JSON list")
        #expect(NoteMermaidPalette.cssSize(16) == "16px" && NoteMermaidPalette.cssSize(13.5) == "13.5px", "sizes print as CSS")
    }

    @Test func requests() {
        let light = NoteMermaidTheme.note(dark: false)
        let dark = NoteMermaidTheme.note(dark: true)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        let b = NoteMermaidRequest(source: "graph TD\nA-->B", theme: light)
        #expect(a.source == "graph TD\nA-->B" && a == b && a.key == b.key, "line endings don't split the cache")
        #expect(NoteMermaidRequest(source: "graph TD\nA-->C", theme: light).key != a.key, "different sources get different keys")
        #expect(NoteMermaidRequest(source: "graph TD\nA-->B", theme: dark).key != a.key, "appearance is part of the key")
        #expect(NoteMermaidRequest(source: "graph TD\nA-->B", theme: .note(dark: false, font: .serif)).key != a.key, "page fonts are part of the key")
        #expect(a.elementID == "parc-mermaid-" + a.key, "each drawing gets its own element id")
        #expect(NoteMermaidRequest(source: "graph TD\nA-->B", theme: dark).layoutKey == a.layoutKey, "light and dark share a layout, so heights hold steady across appearances")
        #expect(NoteMermaidRequest(source: "graph TD\nA-->B", theme: .note(dark: false, small: true)).layoutKey != a.layoutKey, "text size changes the layout")
        #expect(NoteMermaidRequest(source: "graph TD\nA-->C", theme: light).layoutKey != a.layoutKey, "sources change the layout")
        #expect(a.elementID.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }, "element ids are CSS-safe")
        #expect(Set([a, b]).count == 1, "equal requests hash together")
        #expect(NoteMermaid.hasContent(" \n graph") && !NoteMermaid.hasContent(" \n\t "), "blank sources don't draw")
        #expect(NoteMermaid.fingerprint("a") == NoteMermaid.fingerprint("a") && NoteMermaid.fingerprint("a") != NoteMermaid.fingerprint("b"), "fingerprints are stable")
    }

    @Test func replies() {
        let good: [String: Any] = ["ok": true, "svg": "<svg/>", "x": 0, "y": 2, "width": 120.4, "height": 80]
        guard let parsed = NoteMermaidOutcome.parse(good), let drawing = parsed.outcome.drawing else {
            Issue.record("a good reply parses")
            return
        }
        #expect(drawing.svg == "<svg/>" && drawing.size == CGSize(width: 121, height: 80) && parsed.origin == CGPoint(x: 0, y: 2), "sizes round up to whole points")
        let bad: [String: Any] = ["ok": false, "message": "  Parse error on line 2:\nA -->\n  "]
        if case .failure(let message)? = NoteMermaidOutcome.parse(bad)?.outcome {
            #expect(message == "Parse error on line 2:\nA -->", "error messages are trimmed")
        } else {
            Issue.record("a failed reply becomes a failure")
            return
        }
        if case .failure(let message)? = NoteMermaidOutcome.parse(["ok": false])?.outcome {
            #expect(message == NoteMermaidProblem.fallback, "a silent failure still says something")
        } else {
            Issue.record("a failure without a message still fails")
            return
        }
        #expect(NoteMermaidOutcome.parse(nil) == nil && NoteMermaidOutcome.parse("nope") == nil, "garbage replies don't parse")
        #expect(NoteMermaidOutcome.parse(["ok": true, "svg": "<svg/>", "width": 0, "height": 10]) == nil, "empty drawings don't parse")
        #expect(NoteMermaidOutcome.failure("x").isCacheable && !NoteMermaidOutcome.unavailable("x").isCacheable, "Mermaid's verdicts cache, broken renderers retry")
    }

    @Test func problems() {
        let message = "Parse error on line 3:\n...lowchart TD  A -->\n---------------------^\nExpecting 'AMP', got 'EOF'"
        let problem = NoteMermaidProblem(message: message)
        #expect(problem.headline == "Parse error on line 3", "the first line headlines without its colon")
        #expect(problem.detail == "...lowchart TD  A -->\n---------------------^\nExpecting 'AMP', got 'EOF'", "the pointer stays verbatim")
        #expect(problem.line == 3, "the line number is read")
        let unknown = NoteMermaidProblem(message: "No diagram type detected matching given configuration for text: hi")
        #expect(unknown.detail == nil && unknown.line == nil, "one-line errors have no detail")
        #expect(NoteMermaidProblem(message: "   ").headline == NoteMermaidProblem.fallback, "empty errors still explain")
        #expect(NoteMermaidProblem(message: "Lexical error on line 12. Unrecognized text.").line == 12, "lexical errors find their line")
        let source = "flowchart TD\n  A -->"
        let range = problem.range(in: source)
        #expect(range == 13..<20, "an error past the end points at the last real line: \(String(describing: range))")
        #expect(NoteMermaidProblem(message: "Parse error on line 1:").range(in: source) == 0..<12, "line one is the first line")
        #expect(NoteMermaidProblem(message: "Parse error on line 2:").range(in: "graph\n\n") == 0..<5, "blank lines step back to text")
        #expect(unknown.range(in: source) == nil, "no line, no range")
    }

    @Test func cache() {
        var cache = NoteMermaidCache<String>(capacity: 3, costLimit: 100)
        cache.insert("a", for: "a", cost: 10)
        cache.insert("b", for: "b", cost: 10)
        cache.insert("c", for: "c", cost: 10)
        #expect(cache.value(for: "a") == "a", "hits return the value")
        cache.insert("d", for: "d", cost: 10)
        #expect(cache.peek("b") == nil && cache.count == 3, "the least recently used entry goes first")
        #expect(cache.keys == ["c", "a", "d"], "touching an entry refreshes it")
        cache.insert("big", for: "big", cost: 85)
        #expect(cache.totalCost <= 100 && cache.peek("big") == "big", "cost limits evict old entries but keep the new one")
        cache.insert("huge", for: "huge", cost: 500)
        #expect(cache.count == 1 && cache.peek("huge") == "huge", "an oversized entry still caches alone")
        cache.insert("huge2", for: "huge", cost: 5)
        #expect(cache.totalCost == 5 && cache.peek("huge") == "huge2", "replacing an entry fixes its cost")
        cache.remove("huge")
        #expect(cache.count == 0 && cache.totalCost == 0, "removing clears the cost")
        cache.insert("x", for: "x", cost: 1)
        cache.removeAll()
        #expect(cache.count == 0 && cache.totalCost == 0, "clearing empties everything")
    }

    @Test func queue() {
        let theme = NoteMermaidTheme.note(dark: false)
        func request(_ source: String) -> NoteMermaidRequest { NoteMermaidRequest(source: source, theme: theme) }
        var queue = NoteMermaidQueue()
        let one = request("graph TD\nA"), two = request("graph TD\nAB"), three = request("graph TD\nABC")
        queue.submit(one, client: 1)
        queue.submit(one, client: 2)
        #expect(queue.pendingKeys == [one.key], "two blocks with the same diagram share one render")
        #expect(queue.start() == one && queue.start() == nil, "one render runs at a time")
        queue.submit(two, client: 1)
        queue.submit(three, client: 1)
        #expect(queue.pendingKeys == [three.key], "typing replaces a block's stale request")
        #expect(queue.finish(one.key) == [2], "only blocks still waiting on a drawing hear about it")
        #expect(queue.isIdle && queue.start() == three, "the latest request runs next")
        queue.withdraw(1)
        #expect(!queue.wants(three.key) && queue.finish(three.key).isEmpty, "a withdrawn block hears nothing")
        queue.submit(one, client: 3)
        queue.submit(two, client: 4)
        queue.withdraw(3)
        #expect(queue.pendingKeys == [two.key], "withdrawn requests leave the line")
        #expect(queue.start() == two, "the next request starts")
        queue.requeueRunning()
        #expect(queue.isIdle && queue.pendingKeys == [two.key], "a crashed render goes back to the front")
        queue.submit(three, client: 5)
        #expect(queue.start() == two, "requeued renders run first")
        queue.withdraw(4)
        queue.requeueRunning()
        #expect(queue.pendingKeys == [three.key], "nobody wants a crashed render, so it isn't retried")
        #expect(queue.key(for: 5) == three.key, "clients know what they wait for")
        #expect(queue.failAll() == [5] && queue.isIdle && queue.pendingKeys.isEmpty, "a dead renderer tells everyone and clears the line")
    }
}
