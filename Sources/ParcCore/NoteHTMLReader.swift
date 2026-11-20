import Foundation

enum NoteHTMLReader {
    static func blocks(from html: String, baseURL: URL?) -> [NoteBlock] {
        NoteHTMLConversion(document: NoteHTMLParser.parse(html), baseURL: baseURL).run()
    }

    static func tidy(_ blocks: [NoteBlock], parent: NoteBlockKind? = nil) -> [NoteBlock] {
        var result: [NoteBlock] = []
        for var block in blocks {
            block.children = tidy(block.children, parent: block.kind)
            if block.kind == .columns {
                let columns = block.children.filter { $0.kind == .column && !$0.children.isEmpty }
                if columns.count < 2 {
                    result.append(contentsOf: columns.flatMap(\.children))
                    continue
                }
                block.children = columns
            } else if block.kind == .column && parent != .columns {
                result.append(contentsOf: block.children)
                continue
            }
            if !block.acceptsChildren && !block.children.isEmpty {
                let lifted = block.children
                block.children = []
                result.append(block)
                result.append(contentsOf: lifted)
                continue
            }
            result.append(block)
        }
        return result
    }
}

struct NoteHTMLInline {
    enum Spacing { case collapse, preserve, preserveBreaks }
    enum Script { case normal, sub, sup }

    var marks = NoteMarks.plain
    var textColor: NoteColor?
    var backgroundColor: NoteColor?
    var spacing = Spacing.collapse
    var script = Script.normal
    var inLink = false

    var resolved: NoteMarks {
        var value = marks
        if let backgroundColor { value.color = .background(backgroundColor) }
        else if let textColor { value.color = .text(textColor) }
        else { value.color = nil }
        return value
    }

    mutating func apply(_ style: NoteColorStyle) {
        switch style {
        case .text(let color): textColor = color
        case .background(let color): backgroundColor = color
        }
    }
}

struct NoteHTMLLine {
    private(set) var pieces: [(text: String, marks: NoteMarks)] = []
    private var pendingSpace: NoteMarks?
    private var atLineStart = true

    var hasContent: Bool {
        pieces.contains { piece in piece.marks.atom != nil || piece.text.contains { !$0.isWhitespace } }
    }

    private mutating func write(_ scalar: Unicode.Scalar, _ marks: NoteMarks) {
        if let last = pieces.last, last.marks == marks, marks.atom == nil {
            pieces[pieces.count - 1].text.unicodeScalars.append(scalar)
        } else {
            pieces.append((String(Character(scalar)), marks))
        }
    }

    private mutating func flushSpace() {
        if let space = pendingSpace { write(" ", space) }
        pendingSpace = nil
    }

    mutating func append(_ value: String, _ style: NoteHTMLInline) {
        let marks = style.resolved
        let source = style.script == .normal ? value : Self.shifted(value, style.script)
        for scalar in source.unicodeScalars {
            if scalar == "\u{200B}" || scalar == "\u{FEFF}" { continue }
            if NoteHTMLNode.isSpace(scalar) {
                switch style.spacing {
                case .preserve:
                    flushSpace()
                    write(scalar == "\u{0C}" ? " " : scalar, marks)
                    atLineStart = scalar == "\n"
                case .preserveBreaks where scalar == "\n":
                    pendingSpace = nil
                    write("\n", marks)
                    atLineStart = true
                default:
                    if !atLineStart && pendingSpace == nil { pendingSpace = marks }
                }
                continue
            }
            flushSpace()
            write(scalar == "\u{A0}" ? " " : scalar, marks)
            atLineStart = false
        }
    }

    mutating func lineBreak(_ style: NoteHTMLInline) {
        pendingSpace = nil
        var marks = style.resolved
        marks.link = nil
        write("\n", marks)
        atLineStart = true
    }

    mutating func atom(_ atom: NoteAtom, _ style: NoteHTMLInline) {
        flushSpace()
        var marks = style.resolved
        marks.link = nil
        marks.atom = atom
        write("\u{FFFC}", marks)
        atLineStart = false
    }

    func text() -> NoteText {
        var list = pieces
        let trim: (Character) -> Bool = { $0 == " " || $0 == "\n" }
        while let first = list.first {
            let rest = String(first.text.drop(while: trim))
            if rest.isEmpty { list.removeFirst() } else { list[0].text = rest; break }
        }
        while let last = list.last {
            var rest = last.text
            while let tail = rest.last, trim(tail) { rest.removeLast() }
            if rest.isEmpty { list.removeLast() } else { list[list.count - 1].text = rest; break }
        }
        return NoteText(pieces: list.map { ($0.text, $0.marks) })
    }

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ"
    ]
    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "h": "ₕ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "p": "ₚ", "s": "ₛ", "t": "ₜ"
    ]

    static func shifted(_ value: String, _ script: NoteHTMLInline.Script) -> String {
        let table = script == .sup ? superscripts : subscripts
        guard value.contains(where: { !$0.isWhitespace }) else { return value }
        var result = ""
        for character in value {
            if character == " " { result.append(character); continue }
            guard let mapped = table[character] else { return value }
            result.append(mapped)
        }
        return result
    }
}

final class NoteHTMLConversion {
    private final class Sink {
        var blocks: [NoteBlock] = []
        var line = NoteHTMLLine()
    }

    private let document: NoteHTMLNode
    private let baseURL: URL?
    private let sheet: NoteHTMLStyleSheet
    private var levels: [NoteBlockID: Int] = [:]
    private var skipped: Set<ObjectIdentifier> = []
    private var sizeHeadings: [ObjectIdentifier: Int] = [:]

    private static let skippedNames: Set<String> = [
        "script", "style", "noscript", "template", "head", "title", "meta", "link", "base", "svg", "canvas", "button",
        "select", "option", "optgroup", "textarea", "nav", "dialog", "map", "param", "source", "track", "frame",
        "frameset", "datalist", "progress", "meter", "xml", "colgroup", "col", "clipboard-copy", "tool-tip",
        NoteHTMLNode.markerName
    ]
    private static let hiddenClasses: Set<String> = ["sr-only", "visually-hidden", "visuallyhidden", "screen-reader-text",
                                                     "a11y-hidden", "element-invisible", "katex-html"]
    private static let containers: Set<String> = [
        "p", "div", "section", "article", "main", "header", "footer", "address", "center", "form", "fieldset", "legend",
        "hgroup", "figcaption", "summary", "dl", "dd", "caption", "tr", "td", "th", "thead", "tbody", "tfoot", "search",
        "aside", "body", "html"
    ]
    private static let embedHosts = [
        "youtube.com", "youtube-nocookie.com", "youtu.be", "vimeo.com", "loom.com", "spotify.com", "soundcloud.com",
        "codepen.io", "codesandbox.io", "figma.com", "miro.com", "airtable.com", "docs.google.com", "maps.google.com",
        "google.com", "twitter.com", "x.com", "instagram.com", "tiktok.com", "gist.github.com", "replit.com",
        "excalidraw.com", "whimsical.com", "typeform.com", "calendly.com", "player.twitch.tv", "bandcamp.com"
    ]
    private static let alerts: [String: String] = [
        "note": "NOTE", "info": "NOTE", "information": "NOTE", "abstract": "NOTE", "tip": "TIP", "hint": "TIP",
        "success": "TIP", "important": "IMPORTANT", "warning": "WARNING", "attention": "WARNING", "caution": "CAUTION",
        "danger": "CAUTION", "error": "CAUTION", "failure": "CAUTION", "bug": "CAUTION"
    ]

    init(document: NoteHTMLNode, baseURL: URL?) {
        self.document = document
        self.baseURL = baseURL
        sheet = NoteHTMLStyleSheet(document)
        sizeHeadings = measureSizeHeadings()
    }

    func run() -> [NoteBlock] {
        NoteHTMLReader.tidy(flow(document.children, NoteHTMLInline()))
    }

    private func flow(_ nodes: [NoteHTMLNode], _ style: NoteHTMLInline) -> [NoteBlock] {
        let sink = Sink()
        for node in nodes { collect(node, style, sink) }
        flush(sink)
        return nest(sink.blocks)
    }

    private func flowText(_ nodes: [NoteHTMLNode], _ style: NoteHTMLInline) -> NoteText {
        var result = NoteText()
        for block in flow(nodes, style) where block.kind.hasRichText {
            if !result.isEmpty { result.append(NoteText("\n")) }
            result.append(block.text)
        }
        return result
    }

    private func flush(_ sink: Sink) {
        if sink.line.hasContent { sink.blocks.append(.paragraph(sink.line.text())) }
        sink.line = NoteHTMLLine()
    }

    private func collect(_ node: NoteHTMLNode, _ style: NoteHTMLInline, _ sink: Sink) {
        if node.isText {
            sink.line.append(node.text, style)
            return
        }
        if skipped.contains(ObjectIdentifier(node)) { return }
        let css = sheet.declarations(for: node)
        if isHidden(node, css) { return }
        if let blocks = block(node, style, css) {
            flush(sink)
            if node.hasClass("indented") || node["data-block"] == "indent", let last = sink.blocks.indices.last,
               sink.blocks[last].acceptsChildren, !sink.blocks[last].kind.isColumnStructure {
                sink.blocks[last].children += blocks
            } else {
                sink.blocks.append(contentsOf: blocks)
            }
            return
        }
        inline(node, style, css, sink)
    }

    private func isHidden(_ node: NoteHTMLNode, _ css: [String: String]) -> Bool {
        if node["data-block"] != nil { return false }
        if node.name == "nav", node.hasClass("table_of_contents") { return false }
        if Self.skippedNames.contains(node.name) || node.name.hasPrefix("v:") { return true }
        if node["hidden"] != nil || node["aria-hidden"] == "true" { return true }
        if node.name == "img", node["aria-roledescription"] == "checkbox" { return true }
        if css["display"]?.lowercased() == "none" { return true }
        if let visibility = css["visibility"]?.lowercased(), visibility == "hidden" || visibility == "collapse" { return true }
        if css["mso-hide"]?.lowercased() == "all" || css["mso-list"]?.lowercased() == "ignore" { return true }
        if let role = node["role"]?.lowercased(), ["navigation", "menubar", "toolbar"].contains(role) { return true }
        return node.classes.contains { Self.hiddenClasses.contains($0) }
    }

    private func block(_ node: NoteHTMLNode, _ style: NoteHTMLInline, _ css: [String: String]) -> [NoteBlock]? {
        let name = node.name
        if let kind = node["data-block"] { return dataBlock(kind, node, style, css) }
        if isDisplayMath(node) { return equation(tex(node)) }
        if isCallout(node) { return callout(node, derive(style, node, css, block: true)) }
        if node.hasClass("column-list") { return columns(node, style) }
        if name == "a", node.hasClass("bookmark") { return bookmark(node) }
        if name == "nav" { return [NoteBlock(.tableOfContents)] }
        if let list = css["mso-list"], let item = wordListItem(node, style, css, list) { return item }
        let inner = derive(style, node, css, block: true)
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            return heading(node, Int(name.dropFirst()) ?? 1, inner)
        case "ul", "ol", "menu", "dir":
            return list(node, ordered: name == "ol", inner)
        case "li":
            return listItem(node, ordered: node.parent?.name == "ol", checklist: false, inner)
        case "blockquote":
            return container(.quote, node, inner)
        case "pre", "xmp", "listing", "plaintext":
            return code(node)
        case "hr":
            return [NoteBlock(.divider)]
        case "table":
            return table(node, inner)
        case "details":
            return toggle(node, inner)
        case "figure":
            return figure(node, inner)
        case "video", "audio":
            return media(node)
        case "iframe", "embed", "object":
            return embed(node)
        case "dt":
            var bold = inner
            bold.marks.bold = true
            return colored(flow(node.children, bold), node)
        case "p" where node.hasClass("MsoTitle"):
            return heading(node, 1, inner)
        case "p" where node.hasClass("MsoSubtitle"):
            return heading(node, 2, inner)
        case "p" where sizeHeadings[ObjectIdentifier(node)] != nil:
            let level = sizeHeadings[ObjectIdentifier(node)] ?? 1
            let produced = heading(node, level, inner)
            if level == 3, let original = flow(node.children, inner).first, !original.text.allHave(.bold, in: 0..<original.text.length) {
                return colored(flow(node.children, inner), node)
            }
            return produced
        default:
            if Self.containers.contains(name) { return colored(flow(node.children, inner), node) }
            if let display = css["display"]?.lowercased(),
               ["block", "flex", "grid", "list-item", "table", "flow-root"].contains(display) {
                return colored(flow(node.children, inner), node)
            }
            if node["data-stringify-type"] == "paragraph-break" { return [] }
            return nil
        }
    }

    private func inline(_ node: NoteHTMLNode, _ style: NoteHTMLInline, _ css: [String: String], _ sink: Sink) {
        switch node.name {
        case "br":
            sink.line.lineBreak(style)
            return
        case "img":
            if let emoji = emojiText(node) {
                sink.line.append(emoji, style)
            } else if let image = image(node) {
                flush(sink)
                sink.blocks.append(image)
            }
            return
        case "input", "wbr":
            return
        default:
            break
        }
        let next = derive(style, node, css, block: false)
        if let atom = atom(node) {
            sink.line.atom(atom, next)
            return
        }
        if node.name == "q" { sink.line.append("\u{201C}", next) }
        for child in node.children { collect(child, next, sink) }
        if node.name == "q" { sink.line.append("\u{201D}", next) }
    }

    private func derive(_ style: NoteHTMLInline, _ node: NoteHTMLNode, _ css: [String: String], block: Bool) -> NoteHTMLInline {
        var next = style
        let named = node.classes.compactMap { token -> NoteColorStyle? in
            guard token.hasPrefix("highlight-") else { return nil }
            return NoteHTMLColor.style(token: String(token.dropFirst("highlight-".count)))
        } + (block ? [] : [node["data-color"]].compactMap { $0.flatMap(NoteHTMLColor.style(token:)) })
        switch node.name {
        case "b", "strong": next.marks.bold = true
        case "i", "em", "cite", "dfn", "var": next.marks.italic = true
        case "u", "ins": next.marks.underline = true
        case "s", "strike", "del": next.marks.strikethrough = true
        case "code", "kbd", "samp", "tt": next.marks.code = true
        case "mark": if named.isEmpty { next.backgroundColor = .yellow }
        case "sub": next.script = .sub
        case "sup": next.script = .sup
        case "a":
            if let href = node["href"], let link = resolveLink(href) {
                next.marks.link = link
                next.inLink = true
            }
        case "font":
            if !next.inLink, let value = node["color"], let reading = NoteHTMLColor.read(value) { apply(reading, &next.textColor) }
            if let face = node["face"], NoteHTMLFont(["font-family": face]).isMonospace { next.marks.code = true }
        default:
            break
        }
        let font = NoteHTMLFont(css)
        if let bold = font.bold { next.marks.bold = bold }
        if let italic = font.italic { next.marks.italic = italic }
        if font.isMonospace { next.marks.code = true }
        let decoration = ((css["text-decoration"] ?? "") + " " + (css["text-decoration-line"] ?? "")).lowercased()
        if decoration.contains("underline") && !next.inLink { next.marks.underline = true }
        if decoration.contains("line-through") { next.marks.strikethrough = true }
        switch css["vertical-align"]?.lowercased() {
        case "super": next.script = .sup
        case "sub": next.script = .sub
        default: break
        }
        if let space = css["white-space"]?.lowercased() {
            if space.hasPrefix("pre-line") { next.spacing = .preserveBreaks }
            else if space.hasPrefix("pre") || space.hasPrefix("break-spaces") { next.spacing = .preserve }
            else if space == "normal" || space == "nowrap" { next.spacing = .collapse }
        }
        if !next.inLink, !(block && blockColor(node) != nil), let value = css["color"], let reading = NoteHTMLColor.read(value) {
            apply(reading, &next.textColor)
        }
        if !block, let value = css["background-color"] ?? css["background"], let reading = NoteHTMLColor.read(value, background: true) {
            apply(reading, &next.backgroundColor)
        }
        for style in named {
            if case .text = style, node.name == "mark" { next.backgroundColor = nil }
            next.apply(style)
        }
        return next
    }

    private func apply(_ reading: NoteHTMLColor.Reading, _ slot: inout NoteColor?) {
        switch reading {
        case .transparent: break
        case .neutral: slot = nil
        case .color(let color): slot = color
        }
    }

    private func blockColor(_ node: NoteHTMLNode) -> NoteColorStyle? {
        if let value = node["data-color"], let style = NoteHTMLColor.style(token: value) { return style }
        for token in node.classes where token.hasPrefix("block-color-") {
            if let style = NoteHTMLColor.style(token: String(token.dropFirst("block-color-".count))) { return style }
        }
        return nil
    }

    private func colored(_ blocks: [NoteBlock], _ node: NoteHTMLNode) -> [NoteBlock] {
        guard let color = blockColor(node) else { return blocks }
        return blocks.map { block in
            var copy = block
            if copy.color == nil && (copy.kind.hasRichText || copy.kind == .code) { copy.color = color }
            return copy
        }
    }

    private func split(_ blocks: [NoteBlock]) -> (text: NoteText, rest: [NoteBlock]) {
        guard let first = blocks.first, first.kind == .paragraph else { return (NoteText(), blocks) }
        return (first.text, Array(blocks.dropFirst()))
    }

    private func nest(_ blocks: [NoteBlock]) -> [NoteBlock] {
        guard blocks.contains(where: { levels[$0.id] != nil }) else { return blocks }
        var output: [NoteBlock] = []
        var open: [(level: Int, block: NoteBlock)] = []
        func close(to level: Int) {
            while let last = open.last, last.level >= level {
                let finished = open.removeLast().block
                if open.isEmpty { output.append(finished) } else { open[open.count - 1].block.children.append(finished) }
            }
        }
        for block in blocks {
            if let level = levels[block.id] {
                close(to: level)
                if let parent = open.last, !parent.block.acceptsChildren { close(to: parent.level) }
                open.append((level, block))
            } else {
                close(to: Int.min)
                output.append(block)
            }
        }
        close(to: Int.min)
        return output
    }

    private func heading(_ node: NoteHTMLNode, _ level: Int, _ style: NoteHTMLInline) -> [NoteBlock] {
        var inner = flow(node.children, style)
        guard let index = inner.firstIndex(where: { $0.kind == .paragraph }) else { return inner }
        var text = inner[index].text
        text.updateMarks(in: 0..<text.length) { $0.bold = false }
        var block = NoteBlock.heading(level, text)
        block.color = blockColor(node)
        inner[index] = block
        return inner
    }

    private func container(_ kind: NoteBlockKind, _ node: NoteHTMLNode, _ style: NoteHTMLInline) -> [NoteBlock] {
        let (text, children) = split(flow(node.children, style))
        guard !text.isEmpty || !children.isEmpty else { return [] }
        return [NoteBlock(kind, text: text, color: blockColor(node), children: children)]
    }

    private func list(_ node: NoteHTMLNode, ordered: Bool, _ style: NoteHTMLInline) -> [NoteBlock] {
        let checklist = node.classes.contains { ["checklist", "to-do-list", "todo-list", "task-list"].contains($0.lowercased()) }
        var items: [NoteBlock] = []
        func attach(_ blocks: [NoteBlock]) {
            if var last = items.popLast() {
                if last.acceptsChildren {
                    last.children.append(contentsOf: blocks)
                    items.append(last)
                    return
                }
                items.append(last)
            }
            items.append(contentsOf: blocks)
        }
        for child in node.children {
            if child.isWhitespace || skipped.contains(ObjectIdentifier(child)) { continue }
            if child.isElement && isHidden(child, sheet.declarations(for: child)) { continue }
            switch child.name {
            case "li":
                let css = sheet.declarations(for: child)
                items.append(contentsOf: listItem(child, ordered: ordered, checklist: checklist, derive(style, child, css, block: true)))
            case "ul", "ol", "menu", "dir":
                let css = sheet.declarations(for: child)
                attach(list(child, ordered: child.name == "ol", derive(style, child, css, block: true)))
            default:
                for block in flow([child], style) {
                    if block.kind == .paragraph {
                        items.append(NoteBlock(ordered ? .numberedItem : .bulletedItem, text: block.text))
                    } else {
                        attach([block])
                    }
                }
            }
        }
        if ordered, let start = Int(node["start"] ?? ""), start != 1, let first = items.firstIndex(where: { $0.kind == .numberedItem }) {
            items[first].props.listStart = start
        }
        if let indent = Int(node["data-indent"] ?? "") {
            for item in items { levels[item.id] = indent + 1 }
        }
        return items
    }

    private func listItem(_ node: NoteHTMLNode, ordered: Bool, checklist: Bool, _ style: NoteHTMLInline) -> [NoteBlock] {
        let meaningful = node.children.filter { !$0.isWhitespace }
        if meaningful.count == 1, meaningful[0].name == "details" {
            return toggle(meaningful[0], derive(style, meaningful[0], sheet.declarations(for: meaningful[0]), block: true))
        }
        var kind: NoteBlockKind = ordered ? .numberedItem : .bulletedItem
        switch node["data-list"] {
        case "bullet": kind = .bulletedItem
        case "ordered": kind = .numberedItem
        default: break
        }
        var checked = checkState(node, checklist: checklist)
        var (text, children) = split(flow(node.children, style))
        if checked == nil {
            for (prefix, value) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where text.string.hasPrefix(prefix) {
                checked = value
                text = text.slice(prefix.utf16.count..<text.length)
            }
        }
        if let checked {
            kind = .todo
            if checked && text.length > 0 && text.allHave(.strikethrough, in: 0..<text.length) {
                text.updateMarks(in: 0..<text.length) { $0.strikethrough = false }
            }
        }
        guard !text.isEmpty || !children.isEmpty else { return [] }
        var block = NoteBlock(kind, text: text, color: blockColor(node), children: children)
        block.props.checked = checked ?? false
        return [block]
    }

    private func checkState(_ item: NoteHTMLNode, checklist: Bool) -> Bool? {
        if item["role"] == "checkbox" || item["aria-checked"] != nil { return item["aria-checked"] == "true" }
        if let value = item["data-checked"] { return ["true", "1", "checked", "yes"].contains(value.lowercased()) }
        if item["data-list"] == "checked" { return true }
        if item["data-list"] == "unchecked" { return false }
        if let box = leadingCheckbox(item) {
            if box.name == "input" { return box["checked"] != nil }
            if box.name == "img" { return box["alt"]?.lowercased() == "checked" || box["aria-checked"] == "true" }
            if let state = box["aria-checked"] { return state == "true" }
            return box.classes.contains { ["checkbox-on", "checked", "is-checked"].contains($0) }
        }
        if checklist { return item.classes.contains { ["checked", "done", "completed", "is-checked"].contains($0.lowercased()) } }
        return nil
    }

    private func leadingCheckbox(_ node: NoteHTMLNode) -> NoteHTMLNode? {
        for child in node.children where child.isElement {
            if ["ul", "ol", "menu", "details"].contains(child.name) { return nil }
            if child.name == "input", child["type"]?.lowercased() == "checkbox" { return child }
            if child.name == "img", child["aria-roledescription"] == "checkbox" { return child }
            if child["role"] == "checkbox" || child.hasClass("checkbox") { return child }
            if let found = leadingCheckbox(child) { return found }
        }
        return nil
    }

    private func wordListItem(_ node: NoteHTMLNode, _ style: NoteHTMLInline, _ css: [String: String], _ value: String) -> [NoteBlock]? {
        let lowered = value.lowercased()
        guard let range = lowered.range(of: "level"), !lowered.hasPrefix("ignore"), !lowered.hasPrefix("none") else { return nil }
        let level = Int(lowered[range.upperBound...].prefix(while: \.isNumber)) ?? 1
        let markerNode = node.first {
            $0.name == NoteHTMLNode.markerName
                || NoteHTMLStyleSheet.declarations($0["style"] ?? "")["mso-list"]?.lowercased() == "ignore"
        }
        let marker = (markerNode?.textContent ?? "").replacingOccurrences(of: "\u{A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let (text, rest) = split(flow(node.children, derive(style, node, css, block: true)))
        guard !text.isEmpty else { return rest }
        let block = NoteBlock(Self.isOrderedMarker(marker) ? .numberedItem : .bulletedItem, text: text, color: blockColor(node))
        levels[block.id] = level
        return [block] + rest
    }

    private static func isOrderedMarker(_ marker: String) -> Bool {
        guard let last = marker.last, last == "." || last == ")" else { return false }
        let body = marker.dropLast().trimmingCharacters(in: CharacterSet(charactersIn: "("))
        guard !body.isEmpty else { return false }
        if body.allSatisfy(\.isNumber) { return true }
        if body.count == 1, body.first?.isLetter == true { return true }
        return body.count <= 6 && body.lowercased().allSatisfy { "ivxlcdm".contains($0) }
    }

    private func code(_ node: NoteHTMLNode) -> [NoteBlock] {
        var text = preformatted(node)
        if text.hasPrefix("\n") { text.removeFirst() }
        while text.hasSuffix("\n") { text.removeLast() }
        guard text.contains(where: { !$0.isWhitespace }) else { return [] }
        var block = NoteBlock(.code, text: NoteText(text), color: blockColor(node))
        block.props.language = language(for: node)
        return [block]
    }

    private func preformatted(_ node: NoteHTMLNode) -> String {
        var result = ""
        func walk(_ current: NoteHTMLNode) {
            for child in current.children {
                if child.isText {
                    result += child.text.replacingOccurrences(of: "\u{A0}", with: " ")
                    continue
                }
                if child.name == "br" {
                    result += "\n"
                    continue
                }
                let css = sheet.declarations(for: child)
                if isHidden(child, css) || isLineNumber(child) { continue }
                let isLine = ["div", "p", "li", "tr"].contains(child.name) || css["display"]?.lowercased() == "block"
                if isLine, !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
                walk(child)
                if isLine, !result.hasSuffix("\n") { result += "\n" }
            }
        }
        walk(node)
        return result
    }

    private func isLineNumber(_ node: NoteHTMLNode) -> Bool {
        let markers = ["line-number", "lineno", "linenos", "gutter", "blob-num", "hljs-ln-numbers"]
        return node.classes.contains { token in markers.contains { token.lowercased().hasPrefix($0) } }
    }

    private func language(for node: NoteHTMLNode) -> String {
        var candidates: [NoteHTMLNode] = [node]
        if let code = node.first(where: { $0.name == "code" }) { candidates.append(code) }
        for candidate in candidates {
            for key in ["data-language", "data-lang", "lang"] {
                if let value = candidate[key], !value.isEmpty { return Self.normalizedLanguage(value) }
            }
        }
        var ancestor = node.parent
        for _ in 0..<2 {
            guard let current = ancestor else { break }
            candidates.append(current)
            ancestor = current.parent
        }
        for candidate in candidates {
            for token in candidate.classes {
                let lowered = token.lowercased()
                for prefix in ["language-", "lang-", "highlight-source-", "highlight-text-", "brush:"] where lowered.hasPrefix(prefix) {
                    return Self.normalizedLanguage(String(lowered.dropFirst(prefix.count)))
                }
            }
        }
        return ""
    }

    private static func normalizedLanguage(_ value: String) -> String {
        let lowered = value.lowercased().trimmingCharacters(in: .whitespaces)
        return ["plain", "plaintext", "plain-text", "plain text", "text", "txt", "none", "nohighlight"].contains(lowered) ? "" : lowered
    }

    private func table(_ node: NoteHTMLNode, _ style: NoteHTMLInline) -> [NoteBlock] {
        var rows: [(node: NoteHTMLNode, head: Bool)] = []
        var caption: NoteHTMLNode?
        for child in node.children where child.isElement {
            switch child.name {
            case "tr": rows.append((child, false))
            case "thead", "tbody", "tfoot":
                for row in child.children where row.name == "tr" { rows.append((row, child.name == "thead")) }
            case "caption": caption = child
            default: break
            }
        }
        let cellRows = rows.map { row in (cells: row.node.children.filter { $0.name == "td" || $0.name == "th" }, head: row.head) }
            .filter { !$0.cells.isEmpty }
        guard !cellRows.isEmpty else { return flow(node.children, style) }
        let span: (NoteHTMLNode) -> Int = { min(max(Int($0["colspan"] ?? "") ?? 1, 1), 50) }
        let columnCount = cellRows.map { $0.cells.reduce(0) { $0 + span($1) } }.max() ?? 0
        let layout = node["role"] == "presentation" || (cellRows.count == 1 && columnCount == 1) || cellRows.contains { row in
            row.cells.contains { cell in
                cell.first { ["table", "h1", "h2", "h3", "h4", "pre", "blockquote", "video", "iframe"].contains($0.name)
                    || ($0.name == "img" && emojiText($0) == nil) } != nil
            }
        }
        if layout {
            return cellRows.flatMap { row in
                row.cells.flatMap { cell in flow(cell.children, derive(style, cell, sheet.declarations(for: cell), block: true)) }
            }
        }
        var grid: [[NoteText]] = []
        var alignments: [NoteAlignment?] = []
        for (index, row) in cellRows.enumerated() {
            var values: [NoteText] = []
            for cell in row.cells {
                let css = sheet.declarations(for: cell)
                if index == 0 {
                    let alignment: NoteAlignment?
                    switch (cell["align"] ?? css["text-align"] ?? "").lowercased() {
                    case "center": alignment = .center
                    case "right", "end": alignment = .right
                    case "left", "start": alignment = .left
                    default: alignment = nil
                    }
                    alignments.append(contentsOf: Array(repeating: alignment, count: span(cell)))
                }
                values.append(cellText(cell, derive(style, cell, css, block: true)))
                values.append(contentsOf: Array(repeating: NoteText(), count: span(cell) - 1))
            }
            grid.append(values)
        }
        let allBold: (NoteText) -> Bool = { $0.allHave(.bold, in: 0..<$0.length) }
        var headerRow = cellRows[0].head || cellRows[0].cells.allSatisfy { $0.name == "th" }
        if !headerRow && grid.count > 1 {
            let first = grid[0].filter { !$0.isEmpty }, second = grid[1].filter { !$0.isEmpty }
            if !first.isEmpty && first.allSatisfy(allBold) && !(second.allSatisfy(allBold) && !second.isEmpty) {
                headerRow = true
                for column in grid[0].indices { grid[0][column].updateMarks(in: 0..<grid[0][column].length) { $0.bold = false } }
            }
        }
        let body = cellRows.dropFirst(headerRow ? 1 : 0)
        let everyCellIsHeader = cellRows.allSatisfy { $0.cells.allSatisfy { $0.name == "th" } }
        let headerColumn = !body.isEmpty && !everyCellIsHeader && body.allSatisfy { $0.cells.first?.name == "th" }
        var value = NoteTable(rows: grid, headerRow: headerRow, headerColumn: headerColumn)
        value.alignments = alignments
        value.normalize()
        var block = NoteBlock(.table, color: blockColor(node))
        block.props.table = value
        var result = caption.map { flow($0.children, style) } ?? []
        result.append(block)
        return result
    }

    private func cellText(_ cell: NoteHTMLNode, _ style: NoteHTMLInline) -> NoteText {
        var result = NoteText()
        var first = true
        func add(_ text: NoteText) {
            if !first { result.append(NoteText("\n")) }
            result.append(text)
            first = false
        }
        func walk(_ blocks: [NoteBlock], depth: Int) {
            var number = 0
            let indent = String(repeating: "  ", count: depth)
            for block in blocks {
                switch block.kind {
                case .bulletedItem:
                    add(NoteText(indent + "• ") + block.text)
                case .numberedItem:
                    number = block.props.listStart ?? number + 1
                    add(NoteText(indent + "\(number). ") + block.text)
                case .todo:
                    add(NoteText(indent + (block.props.checked ? "☑ " : "☐ ")) + block.text)
                default:
                    if block.kind.hasRichText || block.kind.hasPlainText { add(block.text) }
                }
                walk(block.children, depth: depth + (block.kind.isListItem ? 1 : 0))
            }
        }
        walk(flow(cell.children, style), depth: 0)
        return result
    }

    private func toggle(_ node: NoteHTMLNode, _ style: NoteHTMLInline) -> [NoteBlock] {
        let summary = node.children.first { $0.name == "summary" }
        var children = flow(node.children.filter { $0 !== summary }, style)
        var block: NoteBlock
        if let summary, let headingNode = summary.first(where: { NoteHTMLTreeBuilder.headings.contains($0.name) }) {
            let level = Int(headingNode.name.dropFirst()) ?? 1
            let produced = heading(headingNode, level, derive(style, headingNode, sheet.declarations(for: headingNode), block: true))
            block = produced.first { $0.kind == .heading } ?? NoteBlock.heading(level)
            block.props.toggleable = true
        } else {
            let produced = summary.map { flow($0.children, derive(style, $0, sheet.declarations(for: $0), block: true)) } ?? []
            let (text, rest) = split(produced)
            block = NoteBlock(.toggle, text: text)
            children = rest + children
        }
        block.props.expanded = node["open"] != nil
        block.children = children
        block.color = blockColor(node) ?? block.color
        guard !block.text.isEmpty || !children.isEmpty else { return [] }
        return [block]
    }

    private func isCallout(_ node: NoteHTMLNode) -> Bool {
        if node.name == "aside" || node["data-callout"] != nil || node["role"] == "note" { return true }
        return node.classes.contains { token in
            ["callout", "admonition", "markdown-alert", "alert", "notice", "confluence-information-macro"].contains(token.lowercased())
        }
    }

    private func alertType(_ node: NoteHTMLNode) -> String? {
        var names: [String] = []
        if let value = node["data-alert"] ?? node["data-callout"] { names.append(value.lowercased()) }
        for token in node.classes.map({ $0.lowercased() }) {
            for prefix in ["markdown-alert-", "admonition-", "alert-", "callout-"] where token.hasPrefix(prefix) {
                names.append(String(token.dropFirst(prefix.count)))
            }
            names.append(token)
        }
        return names.lazy.compactMap { Self.alerts[$0] }.first
    }

    private func callout(_ node: NoteHTMLNode, _ style: NoteHTMLInline) -> [NoteBlock] {
        let alert = alertType(node)
        var icon = node["data-icon"]
        let iconNode = node.first { candidate in
            candidate.isElement && candidate.classes.contains { ["icon", "callout-icon", "notion-icon", "page-icon"].contains($0.lowercased()) }
        }
        if let iconNode {
            let value = iconNode.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if icon == nil, iconNode["data-default-icon"] == nil {
                if !value.isEmpty, value.count <= 4 {
                    icon = value
                } else if let image = iconNode.name == "img" ? iconNode : iconNode.first(where: { $0.name == "img" }), let source = image["src"] {
                    icon = resolve(source)
                }
            }
            skipped.insert(ObjectIdentifier(iconNode))
        }
        if let alert, let title = node.first(where: { candidate in
            candidate.isElement && candidate.classes.contains { $0.lowercased().contains("title") || $0 == "alert-heading" }
        }) {
            let words = title.textContent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if Self.alerts[words] == alert || words == alert.lowercased() { skipped.insert(ObjectIdentifier(title)) }
        }
        var (text, children) = split(flow(node.children, style))
        if icon == nil, iconNode?["data-default-icon"] == nil, let (emoji, length) = Self.leadingEmoji(text) {
            icon = emoji
            text = text.slice(length..<text.length)
        }
        guard !text.isEmpty || !children.isEmpty else { return [] }
        var block = NoteBlock(.callout, text: text, color: blockColor(node), children: children)
        block.props.icon = icon
        block.props.alert = alert
        return [block]
    }

    private static func leadingEmoji(_ text: NoteText) -> (String, Int)? {
        guard let first = text.string.first, let scalar = first.unicodeScalars.first,
              scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && first.unicodeScalars.count > 1) else { return nil }
        let value = String(first)
        var length = (value as NSString).length
        let rest = text.string.dropFirst()
        guard rest.isEmpty || rest.first == " " else { return nil }
        if rest.first == " " { length += 1 }
        return (value, length)
    }

    private func columns(_ node: NoteHTMLNode, _ style: NoteHTMLInline) -> [NoteBlock] {
        let columns = node.children.filter { $0.hasClass("column") || $0["data-block"] == "column" }.map { column in
            NoteBlock(.column, children: flow(column.children, derive(style, column, sheet.declarations(for: column), block: true)))
        }.filter { !$0.children.isEmpty }
        if columns.count >= 2 { return [NoteBlock(.columns, children: columns)] }
        return columns.isEmpty ? flow(node.children, style) : columns.flatMap(\.children)
    }

    private func figure(_ node: NoteHTMLNode, _ style: NoteHTMLInline) -> [NoteBlock] {
        let caption = node.children.first { $0.name == "figcaption" }
        var blocks = flow(node.children.filter { $0 !== caption }, style)
        guard let caption else { return blocks }
        let text = flowText(caption.children, derive(style, caption, sheet.declarations(for: caption), block: true))
        guard !text.isEmpty else { return blocks }
        let holders = blocks.indices.filter { blocks[$0].kind.hasCaption }
        if holders.count == 1 { blocks[holders[0]].props.caption = text } else { blocks.append(.paragraph(text)) }
        return blocks
    }

    private func image(_ node: NoteHTMLNode) -> NoteBlock? {
        let srcset = node["srcset"].flatMap { $0.split(separator: ",").first?.split(separator: " ").first.map(String.init) }
        let candidates = [node["data-src"], node["data-original"], node["src"], srcset]
        guard let source = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("about:") }) else { return nil }
        if let width = Double(node["width"] ?? ""), width <= 2 { return nil }
        if let height = Double(node["height"] ?? ""), height <= 2 { return nil }
        var block = NoteBlock(.image)
        block.props.source = resolve(source)
        if let alt = node["alt"]?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty { block.props.alt = alt }
        return block
    }

    private func emojiText(_ node: NoteHTMLNode) -> String? {
        let isEmoji = node.classes.contains { $0.lowercased().contains("emoji") }
            || node["data-stringify-emoji"] != nil || node["data-emoji"] != nil
        guard isEmoji else { return nil }
        return [node["data-stringify-emoji"], node["data-emoji"], node["alt"], node["title"], node["aria-label"]]
            .compactMap { $0 }.first { !$0.isEmpty }
    }

    private func media(_ node: NoteHTMLNode) -> [NoteBlock] {
        guard let source = node["src"] ?? node.children.first(where: { $0.name == "source" && $0["src"] != nil })?["src"],
              !source.isEmpty else { return [] }
        var block = NoteBlock(node.name == "audio" ? .audio : .video)
        block.props.source = resolve(source)
        return [block]
    }

    private func embed(_ node: NoteHTMLNode) -> [NoteBlock] {
        guard let source = node["src"] ?? node["data"] else { return [] }
        let resolved = resolve(source)
        guard let host = URL(string: resolved)?.host?.lowercased(), resolved.lowercased().hasPrefix("http"),
              Self.embedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return [] }
        var block = NoteBlock(.embed)
        block.props.source = resolved
        return [block]
    }

    private func bookmark(_ node: NoteHTMLNode) -> [NoteBlock] {
        guard let href = node["href"], !href.isEmpty else { return [] }
        func text(_ name: String) -> String? {
            let value = node.first { $0.hasClass(name) }?.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        var block = NoteBlock(.bookmark)
        block.props.source = resolve(href)
        block.props.bookmark = NoteBookmark(title: text("bookmark-title"), summary: text("bookmark-description"), siteName: nil,
                                            iconURL: node.first { $0.hasClass("bookmark-icon") }?["src"].map(resolve),
                                            imageURL: node.first { $0.hasClass("bookmark-image") }?["src"].map(resolve))
        return [block]
    }

    private func dataBlock(_ kind: String, _ node: NoteHTMLNode, _ style: NoteHTMLInline, _ css: [String: String]) -> [NoteBlock] {
        let inner = derive(style, node, css, block: true)
        let caption = node.children.first { $0.name == "figcaption" }
        func captioned(_ block: NoteBlock) -> [NoteBlock] {
            var copy = block
            if let caption { copy.props.caption = flowText(caption.children, inner) }
            return [copy]
        }
        switch kind {
        case "paragraph":
            return [NoteBlock(.paragraph, text: flowText(node.children, inner), color: blockColor(node))]
        case "equation":
            return equation(tex(node), color: blockColor(node))
        case "callout":
            return callout(node, inner)
        case "columns":
            return columns(node, style)
        case "column":
            return flow(node.children, inner)
        case "tableOfContents":
            return [NoteBlock(.tableOfContents, color: blockColor(node))]
        case "bookmark", "embed", "file", "pageLink":
            let link = node.name == "a" ? node : node.first { $0.name == "a" }
            let source = node["data-source"] ?? node["data-target"] ?? link?["href"] ?? ""
            guard !source.isEmpty else { return [] }
            var block = NoteBlock(NoteBlockKind(rawValue: kind) ?? .bookmark, color: blockColor(node))
            switch block.kind {
            case .bookmark:
                block.props.source = source
                block.props.bookmark = NoteBookmark(title: node["data-title"], summary: node["data-summary"],
                                                    siteName: node["data-site"], iconURL: node["data-icon-url"],
                                                    imageURL: node["data-image"])
            case .pageLink:
                block.props.target = source
                let title = (link?.children ?? []).filter { !$0.hasClass("page-icon") }.map(\.textContent).joined()
                block.text = NoteText(title.trimmingCharacters(in: .whitespacesAndNewlines))
            default:
                block.props.source = source
                block.props.alt = node["data-name"]
            }
            return captioned(block)
        case "html", "raw":
            let value = node["data-source"] ?? node.textContent
            guard !value.isEmpty else { return [] }
            return [NoteBlock(kind == "html" ? .html : .raw, text: NoteText(value))]
        default:
            return flow(node.children, inner)
        }
    }

    private func equation(_ source: String, color: NoteColorStyle? = nil) -> [NoteBlock] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [NoteBlock(.equation, text: NoteText(trimmed), color: color)]
    }

    private func isDisplayMath(_ node: NoteHTMLNode) -> Bool {
        let classes = Set(node.classes)
        if classes.contains("equation") && (node.name == "figure" || node.name == "div") { return true }
        if classes.contains("katex-display") || classes.contains("math-display") { return true }
        if classes.contains("math") && classes.contains("display") { return true }
        if node.name == "math-renderer" {
            return classes.contains("js-display-math") || node.textContent.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("$$")
        }
        return node.name == "math" && node["display"] == "block"
    }

    private func isInlineMath(_ node: NoteHTMLNode) -> Bool {
        if node["data-tex"] != nil || node.name == "math-renderer" || node.name == "math" { return true }
        let classes = Set(node.classes)
        if classes.contains("katex") || classes.contains("notion-text-equation-token") || classes.contains("math-inline") { return true }
        if classes.contains("equation") { return true }
        return classes.contains("math") && (classes.contains("inline") || node.name == "span")
    }

    private func tex(_ node: NoteHTMLNode) -> String {
        if let value = node["data-tex"] ?? node["data-latex"] { return value }
        if let annotation = node.first(where: { $0.name == "annotation" && ($0["encoding"] ?? "").contains("tex") }) {
            return annotation.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let math = node.name == "math" ? node : node.first(where: { $0.name == "math" }), let alt = math["alttext"] {
            return alt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var value = node.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)"), ("$", "$")]
        where value.hasPrefix(open) && value.hasSuffix(close) && value.count >= open.count + close.count {
            value = String(value.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return value
    }

    private func atom(_ node: NoteHTMLNode) -> NoteAtom? {
        if let mention = node["data-mention"]?.lowercased() {
            let title = node.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            switch mention {
            case "page": return .page(target: node["data-target"] ?? node["href"] ?? "", title: title)
            case "link": return .link(url: node["href"] ?? "", title: title)
            case "date": return Self.date(node["datetime"] ?? "", remind: node["data-remind"] == "true")
            default: break
            }
        }
        if node.name == "time", node.textContent.trimmingCharacters(in: .whitespaces).hasPrefix("@"),
           let date = Self.date(node["datetime"] ?? "", remind: false) {
            return date
        }
        guard isInlineMath(node) else { return nil }
        let source = tex(node)
        return source.isEmpty ? nil : .equation(source)
    }

    private static func date(_ value: String, remind: Bool) -> NoteAtom? {
        let parts = value.split(separator: "T", maxSplits: 1)
        guard let day = parts.first?.split(separator: "-").compactMap({ Int($0) }), day.count == 3 else { return nil }
        var mention = NoteDateMention(year: day[0], month: day[1], day: day[2], remind: remind)
        if parts.count == 2 {
            let time = parts[1].prefix(5).split(separator: ":").compactMap { Int($0) }
            if time.count == 2 {
                mention.hour = time[0]
                mention.minute = time[1]
            }
        }
        return .date(mention)
    }

    private func resolveLink(_ href: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if ["javascript:", "vbscript:", "data:"].contains(where: { lowered.hasPrefix($0) }) { return nil }
        if trimmed.hasPrefix("#") && baseURL == nil { return nil }
        let resolved = resolve(trimmed)
        if let components = URLComponents(string: resolved), let host = components.host, host.hasSuffix("google.com"),
           components.path == "/url", let target = components.queryItems?.first(where: { $0.name == "q" })?.value,
           target.hasPrefix("http") {
            return target
        }
        return resolved
    }

    private func resolve(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") { return (baseURL?.scheme ?? "https") + ":" + trimmed }
        if let url = URL(string: trimmed), url.scheme != nil { return trimmed }
        guard let baseURL else { return trimmed }
        if let url = URL(string: trimmed, relativeTo: baseURL) { return url.absoluteString }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(CharacterSet(charactersIn: "%#"))) ?? trimmed
        return URL(string: encoded, relativeTo: baseURL)?.absoluteString ?? trimmed
    }

    private func measureSizeHeadings() -> [ObjectIdentifier: Int] {
        if document.first(where: { NoteHTMLTreeBuilder.headings.contains($0.name) }) != nil { return [:] }
        let paragraphs = document.all { node in
            node.name == "p" && !node.hasAncestor { ["li", "td", "th", "table", "ul", "ol", "blockquote"].contains($0.name) }
        }
        guard paragraphs.count > 1 else { return [:] }
        var weights: [Double: Int] = [:]
        var measured: [(node: NoteHTMLNode, size: Double, length: Int)] = []
        for paragraph in paragraphs {
            var sizes: [Double: Int] = [:]
            func walk(_ node: NoteHTMLNode, _ inherited: Double?) {
                for child in node.children {
                    if child.isText {
                        let count = child.text.filter { !$0.isWhitespace }.count
                        if count > 0, let inherited { sizes[inherited, default: 0] += count }
                        continue
                    }
                    walk(child, NoteHTMLFont(sheet.declarations(for: child)).size ?? inherited)
                }
            }
            walk(paragraph, NoteHTMLFont(sheet.declarations(for: paragraph)).size)
            guard let dominant = sizes.max(by: { $0.value < $1.value }) else { continue }
            let length = sizes.values.reduce(0, +)
            weights[dominant.key, default: 0] += length
            measured.append((paragraph, dominant.key, length))
        }
        guard let body = weights.max(by: { $0.value < $1.value })?.key, body > 0 else { return [:] }
        var result: [ObjectIdentifier: Int] = [:]
        for item in measured where item.length <= 120 {
            let ratio = item.size / body
            if ratio >= 1.6 { result[ObjectIdentifier(item.node)] = 1 }
            else if ratio >= 1.3 { result[ObjectIdentifier(item.node)] = 2 }
            else if ratio >= 1.12 { result[ObjectIdentifier(item.node)] = 3 }
        }
        return result
    }
}
