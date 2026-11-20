import Foundation

struct NoteEquationArt {
    struct Link: Equatable {
        var key: String
        var rect: CGRect
    }

    var url: URL
    var links: [Link] = []
}

enum NotePageHTML {
    static func fragment(_ blocks: [NoteBlock], assets: ((String) -> URL?)? = nil) -> String {
        var writer = NotePageHTMLWriter(mode: .fragment, assets: assets ?? { _ in nil }, embedImages: false,
                                        equationArt: nil, blocks: blocks)
        writer.write(blocks)
        return writer.output
    }

    static func document(_ page: NotePage, title: String, assets: (String) -> URL?, embedImages: Bool,
                         equationArt: ((String, Bool, NoteMathNumberingContext) -> NoteEquationArt?)? = nil,
                         diagramArt: ((NoteBlock) -> NoteDiagramArt?)? = nil) -> String {
        withoutActuallyEscaping(assets) { assets in
            var writer = NotePageHTMLWriter(mode: .document, assets: assets, embedImages: embedImages,
                                            equationArt: equationArt, blocks: page.blocks)
            writer.diagramArt = diagramArt
            writer.write(page.blocks)
            let settings = page.settings
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? "Untitled" : trimmed
            var classes = ["page-font-" + settings.font.rawValue]
            if settings.smallText { classes.append("small-text") }
            if settings.fullWidth { classes.append("full-width") }
            if settings.cover != nil { classes.append("has-cover") }
            if settings.icon != nil { classes.append("has-icon") }
            var html = "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
            html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
            html += "<meta name=\"generator\" content=\"Parc\">\n"
            html += "<title>" + NotePageHTMLWriter.escape(name) + "</title>\n<style>\n" + NotePageHTMLStyle.css + "</style>\n</head>\n"
            html += "<body class=\"" + classes.joined(separator: " ") + "\">\n"
            if let cover = settings.cover {
                let position = Int((min(max(cover.position, 0), 1) * 100).rounded())
                let image = "<img class=\"page-cover\" alt=\"\" src=\"" + NotePageHTMLWriter.attribute(writer.source(cover.source))
                    + "\" style=\"object-position:center " + String(position) + "%\">"
                if let credit = cover.credit, !credit.name.isEmpty {
                    html += "<div class=\"page-cover-frame\">" + image + "<p class=\"cover-credit\">" + NotePageHTMLWriter.credit(credit) + "</p></div>\n"
                } else {
                    html += image + "\n"
                }
            }
            html += "<article class=\"page\">\n<header class=\"page-header\">\n"
            if let icon = settings.icon, !icon.isEmpty {
                if let custom = writer.customEmojiSource(icon) {
                    html += "<img class=\"page-icon page-icon-image custom-emoji\" alt=\"" + NotePageHTMLWriter.attribute(icon) + "\" src=\""
                        + NotePageHTMLWriter.attribute(custom) + "\">\n"
                } else if NotePageHTMLWriter.isImageReference(icon) {
                    html += "<img class=\"page-icon page-icon-image\" alt=\"\" src=\"" + NotePageHTMLWriter.attribute(writer.source(icon)) + "\">\n"
                } else {
                    html += "<div class=\"page-icon\">" + NotePageHTMLWriter.escape(icon) + "</div>\n"
                }
            }
            html += "<h1 class=\"page-title\">" + NotePageHTMLWriter.escape(name) + "</h1>\n"
            if !settings.properties.isEmpty { html += NotePageHTMLWriter.properties(settings.properties) }
            html += "</header>\n<main class=\"page-body\">\n" + writer.output + "\n</main>\n</article>\n</body>\n</html>\n"
            return html
        }
    }
}

struct NotePageHTMLWriter {
    enum Mode { case fragment, document }

    let mode: Mode
    let assets: (String) -> URL?
    let embedImages: Bool
    let equationArt: ((String, Bool, NoteMathNumberingContext) -> NoteEquationArt?)?
    var diagramArt: ((NoteBlock) -> NoteDiagramArt?)?
    private(set) var output = ""
    private var anchors: [NoteBlockID: String] = [:]
    private var mathNumbering = NotePageMathNumbering()
    private var equationAnchors: [String: String] = [:]
    private var outline: [(level: Int, anchor: String, title: String)] = []

    init(mode: Mode, assets: @escaping (String) -> URL?, embedImages: Bool,
         equationArt: ((String, Bool, NoteMathNumberingContext) -> NoteEquationArt?)?, blocks: [NoteBlock]) {
        self.mode = mode
        self.assets = assets
        self.embedImages = embedImages
        self.equationArt = equationArt
        var all: [NoteBlock] = []
        func walk(_ list: [NoteBlock]) { for block in list { all.append(block); walk(block.children) } }
        walk(blocks)
        if mode == .document { mathNumbering = NotePageMathNumberer().numbering(for: NotePage(blocks: blocks)) }
        guard mode == .document || all.contains(where: { $0.kind == .tableOfContents }) else { return }
        var used: Set<String> = []
        for block in all where block.kind == .heading {
            let title = block.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = Self.slug(title)
            var anchor = base
            var suffix = 2
            while used.contains(anchor) {
                anchor = base + "-" + String(suffix)
                suffix += 1
            }
            used.insert(anchor)
            anchors[block.id] = anchor
            outline.append((block.props.level, anchor, title))
        }
        for block in all where block.kind == .equation {
            for key in mathNumbering.entries[block.id]?.labels ?? [] {
                let base = "eq-" + Self.slug(key.replacingOccurrences(of: ":", with: "-"))
                var anchor = base
                var suffix = 2
                while used.contains(anchor) {
                    anchor = base + "-" + String(suffix)
                    suffix += 1
                }
                used.insert(anchor)
                equationAnchors[key] = anchor
            }
        }
    }

    static func slug(_ title: String) -> String {
        var result = ""
        var pendingDash = false
        for character in title.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingDash && !result.isEmpty { result.append("-") }
                pendingDash = false
                result.append(character)
            } else if character == " " || character == "-" || character == "_" {
                pendingDash = true
            }
        }
        return result.isEmpty ? "section" : result
    }

    static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func credit(_ credit: NoteMediaCredit) -> String {
        "<span class=\"credit\">" + credit.parts.map { part -> String in
            switch part {
            case .text(let text): return escape(text)
            case .link(let text, let url): return "<a href=\"" + attribute(url.absoluteString) + "\">" + escape(text) + "</a>"
            }
        }.joined() + "</span>"
    }

    static func attribute(_ value: String) -> String {
        escape(value).replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func isImageReference(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.hasPrefix("http:") || lowered.hasPrefix("https:") || lowered.hasPrefix("data:") || lowered.hasPrefix("file:") { return true }
        let ext = (lowered as NSString).pathExtension
        return value.contains("/") || NotePageHTMLStyle.mimeTypes[ext] != nil
    }

    static func properties(_ list: [NotePageProperty]) -> String {
        var html = "<dl class=\"page-properties\">\n"
        for property in list {
            let value: String
            switch property.value {
            case .text(let text): value = escape(text)
            case .number(let number):
                value = number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
            case .checkbox(let checked): value = checked ? "\u{2713}" : "\u{2014}"
            case .date(let date): value = escape(date)
            case .list(let items): value = items.map { "<span class=\"property-chip\">" + escape($0) + "</span>" }.joined(separator: " ")
            }
            html += "<div><dt>" + escape(property.key) + "</dt><dd>" + value + "</dd></div>\n"
        }
        return html + "</dl>\n"
    }

    func link(_ value: String) -> String {
        if let url = URL(string: value), url.scheme != nil { return value }
        return assets(value)?.absoluteString ?? value
    }

    func customEmojiSource(_ value: String) -> String? {
        guard NoteCustomEmojiName.isReference(value), assets(value) != nil else { return nil }
        return source(value)
    }

    func source(_ value: String) -> String {
        if value.lowercased().hasPrefix("data:") { return value }
        let url = assets(value) ?? URL(string: value).flatMap { $0.scheme != nil ? $0 : nil }
        guard let url else { return value }
        if embedImages, url.isFileURL, let mime = NotePageHTMLStyle.mimeTypes[url.pathExtension.lowercased()],
           let data = try? Data(contentsOf: url) {
            return "data:" + mime + ";base64," + data.base64EncodedString()
        }
        return url.absoluteString
    }

    private func colorAttributes(_ style: NoteColorStyle?) -> String {
        guard let style else { return "" }
        let token = NoteHTMLColor.token(style)
        switch mode {
        case .document:
            return " class=\"block-color-" + token + "\""
        case .fragment:
            let palette = NotePageHTMLStyle.palette[style.color] ?? NotePageHTMLStyle.palette[.gray]!
            let css = style.isBackground ? "background-color:#" + palette.background : "color:#" + palette.text
            return " data-color=\"" + token + "\" style=\"" + css + "\""
        }
    }

    private func colorClass(_ style: NoteColorStyle?, adding classes: [String]) -> String {
        var list = classes
        var extra = ""
        if let style {
            let token = NoteHTMLColor.token(style)
            if mode == .document { list.append("block-color-" + token) } else {
                let palette = NotePageHTMLStyle.palette[style.color] ?? NotePageHTMLStyle.palette[.gray]!
                extra = " data-color=\"" + token + "\" style=\"" + (style.isBackground ? "background-color:#" + palette.background
                                                                    : "color:#" + palette.text) + "\""
            }
        }
        return (list.isEmpty ? "" : " class=\"" + list.joined(separator: " ") + "\"") + extra
    }

    mutating func write(_ blocks: [NoteBlock]) {
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            guard block.kind.isListItem else {
                write(block)
                index += 1
                continue
            }
            var end = index + 1
            while end < blocks.count, blocks[end].kind == block.kind,
                  !(block.kind == .numberedItem && blocks[end].props.listStart != nil) { end += 1 }
            list(Array(blocks[index..<end]))
            index = end
        }
    }

    private mutating func lead(_ text: NoteText, children: [NoteBlock]) {
        if !text.isEmpty { output += "<p>" + inline(text) + "</p>" }
        else if children.first?.kind == .paragraph { output += "<p data-block=\"paragraph\"><br></p>" }
    }

    private mutating func list(_ items: [NoteBlock]) {
        let kind = items[0].kind
        let tag = kind == .numberedItem ? "ol" : "ul"
        switch kind {
        case .numberedItem:
            let start = items[0].props.listStart ?? 1
            output += start == 1 ? "<ol>" : "<ol start=\"" + String(start) + "\">"
        case .todo:
            output += mode == .fragment ? "<ul class=\"contains-task-list\" style=\"list-style:none;padding-left:0.4em\">"
                : "<ul class=\"contains-task-list\">"
        default:
            output += "<ul>"
        }
        for item in items {
            if kind == .todo {
                output += "<li" + colorClass(item.color, adding: ["task-list-item"] + (item.props.checked ? ["checked"] : [])) + ">"
                output += "<input type=\"checkbox\" disabled" + (item.props.checked ? " checked" : "") + "> "
                output += mode == .document ? "<span class=\"todo-text\">" + inline(item.text) + "</span>" : inline(item.text)
            } else {
                output += "<li" + colorAttributes(item.color) + ">" + inline(item.text)
            }
            if item.text.isEmpty, item.children.first?.kind == .paragraph { output += "<p data-block=\"paragraph\"><br></p>" }
            write(item.children)
            output += "</li>"
        }
        output += "</" + tag + ">"
    }

    private mutating func write(_ block: NoteBlock) {
        let color = colorAttributes(block.color)
        switch block.kind {
        case .paragraph:
            output += block.text.isEmpty ? "<p data-block=\"paragraph\"" + color + "><br></p>" : "<p" + color + ">" + inline(block.text) + "</p>"
            indented(block.children)
        case .heading:
            let level = min(max(block.props.level, 1), 6)
            let anchor = anchors[block.id].map { " id=\"" + Self.attribute($0) + "\"" } ?? ""
            let heading = "<h" + String(level) + anchor + (block.props.toggleable ? "" : color) + ">" + inline(block.text) + "</h" + String(level) + ">"
            if block.props.toggleable {
                details(block, summary: heading)
            } else {
                output += heading
                indented(block.children)
            }
        case .bulletedItem, .numberedItem, .todo:
            list([block])
        case .toggle:
            details(block, summary: inline(block.text))
        case .quote:
            output += "<blockquote" + color + ">"
            lead(block.text, children: block.children)
            write(block.children)
            output += "</blockquote>"
        case .callout:
            callout(block)
        case .divider:
            output += "<hr>"
        case .code:
            code(block)
        case .equation:
            equation(block)
        case .image, .video, .audio:
            media(block)
        case .file:
            let source = block.props.source ?? ""
            let name = block.props.alt ?? (source.removingPercentEncoding.map { ($0 as NSString).lastPathComponent } ?? source)
            let named = block.props.alt.map { " data-name=\"" + Self.attribute($0) + "\"" } ?? ""
            let anchor = "<a class=\"file-link\" href=\"" + Self.attribute(link(source)) + "\"><span class=\"file-icon\">\u{1F4CE}</span> "
                + Self.escape(name.isEmpty ? "File" : name) + "</a>"
            figure("file", block, attributes: " data-source=\"" + Self.attribute(source) + "\"" + named, content: anchor)
        case .pdf:
            pdf(block)
        case .bookmark:
            bookmark(block)
        case .embed:
            let source = block.props.source ?? ""
            let anchor = "<a class=\"embed-link\" href=\"" + Self.attribute(link(source)) + "\">" + Self.escape(source) + "</a>"
            figure("embed", block, attributes: " data-source=\"" + Self.attribute(source) + "\"", content: anchor)
        case .table:
            table(block)
        case .tableOfContents:
            contents(block)
        case .columns:
            let style = mode == .fragment ? " style=\"display:flex;gap:24px\"" : ""
            output += "<div data-block=\"columns\" class=\"columns\"" + style + ">"
            for column in block.children {
                output += "<div data-block=\"column\" class=\"column\"" + (mode == .fragment ? " style=\"flex:1 1 0;min-width:0\"" : "") + ">"
                write(column.kind == .column ? column.children : [column])
                output += "</div>"
            }
            output += "</div>"
        case .column:
            write(block.children)
        case .pageLink:
            let target = block.props.target ?? ""
            var title = block.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                title = ((target.removingPercentEncoding ?? target) as NSString).lastPathComponent
                title = (title as NSString).deletingPathExtension
            }
            output += "<p data-block=\"pageLink\" data-target=\"" + Self.attribute(target) + "\"" + colorClass(block.color, adding: ["page-link"])
                + "><a href=\"" + Self.attribute(link(target)) + "\"><span class=\"page-icon\">\u{1F4C4}</span> "
                + Self.escape(title.isEmpty ? "Untitled" : title) + "</a></p>"
        case .html:
            let source = block.text.string
            output += "<div data-block=\"html\" data-source=\"" + Self.attribute(source) + "\">" + source + "</div>"
        case .raw:
            let source = block.text.string
            output += "<pre data-block=\"raw\" data-source=\"" + Self.attribute(source) + "\">" + Self.escape(source) + "</pre>"
        }
    }

    private mutating func indented(_ children: [NoteBlock]) {
        guard !children.isEmpty else { return }
        output += mode == .fragment ? "<div class=\"indented\" style=\"padding-left:1.5em\">" : "<div class=\"indented\">"
        write(children)
        output += "</div>"
    }

    private mutating func details(_ block: NoteBlock, summary: String) {
        let open = mode == .document || block.props.expanded ? " open" : ""
        output += "<details" + open + colorClass(block.color, adding: mode == .document ? ["toggle"] : []) + "><summary>" + summary + "</summary>"
        if mode == .document { output += "<div class=\"toggle-body\">" }
        write(block.children)
        if mode == .document { output += "</div>" }
        output += "</details>"
    }

    private mutating func callout(_ block: NoteBlock) {
        let explicitIcon = block.props.icon.flatMap { $0.isEmpty ? nil : $0 }
        let icon = block.props.icon == "" ? "" : block.calloutDisplayIcon ?? "\u{1F4A1}"
        let fallbackColor = block.color == nil ? block.calloutDisplayColor : nil
        var attributes = " data-block=\"callout\"" + (explicitIcon.map { " data-icon=\"" + Self.attribute($0) + "\"" } ?? "")
        if let alert = block.props.alert { attributes += " data-alert=\"" + Self.attribute(alert) + "\"" }
        if mode == .fragment {
            let shown = block.color ?? fallbackColor
            let palette = shown.flatMap { NotePageHTMLStyle.palette[$0.color] } ?? NotePageHTMLStyle.palette[.gray]!
            if let style = block.color { attributes += " data-color=\"" + NoteHTMLColor.token(style) + "\"" }
            let ink = shown.map { $0.isBackground ? "" : "color:#" + palette.text + ";" } ?? ""
            let fill = shown?.isBackground == false ? "border:1px solid #E3E2E0;" : "background-color:#" + palette.background + ";"
            attributes += " style=\"display:flex;gap:10px;padding:12px 16px;border-radius:8px;margin:4px 0;" + fill + ink + "\""
            output += "<aside class=\"callout\"" + attributes + ">"
        } else {
            let tint = fallbackColor.map { " style=\"background:var(--" + $0.color.rawValue + "-bg)\"" } ?? ""
            output += "<aside" + colorClass(block.color, adding: ["callout"]) + attributes + tint + ">"
        }
        let fallback = explicitIcon == nil ? " data-default-icon=\"true\"" : ""
        if let custom = customEmojiSource(icon) {
            let sizing = mode == .fragment ? " style=\"width:1.4em;height:1.4em;object-fit:contain\"" : ""
            output += "<img class=\"callout-icon custom-emoji\"" + sizing + " alt=\"" + Self.attribute(icon) + "\" src=\"" + Self.attribute(custom) + "\">"
        } else if Self.isImageReference(icon) {
            output += "<img class=\"callout-icon\"" + fallback + " alt=\"\" src=\"" + Self.attribute(source(icon)) + "\">"
        } else {
            output += "<span class=\"callout-icon\"" + fallback + ">" + Self.escape(icon) + "</span>"
        }
        output += "<div class=\"callout-body\">"
        lead(block.text, children: block.children)
        write(block.children)
        output += "</div></aside>"
    }

    private mutating func figure(_ kind: String, _ block: NoteBlock, attributes: String = "", content: String) {
        let style = mode == .fragment ? " style=\"margin:1em 0\"" : ""
        output += "<figure data-block=\"" + kind + "\"" + attributes + colorClass(block.color, adding: [kind]) + style + ">" + content
        figureCaption(block)
        output += "</figure>"
    }

    private mutating func figureCaption(_ block: NoteBlock) {
        let credit = NoteMDMedia.carriesCredit(block.kind) ? block.props.credit.map(Self.credit) : nil
        guard !block.props.caption.isEmpty || credit != nil else { return }
        output += "<figcaption>"
        if !block.props.caption.isEmpty { output += inline(block.props.caption) }
        if let credit { output += (block.props.caption.isEmpty ? "" : "<br>") + credit }
        output += "</figcaption>"
    }

    private mutating func code(_ block: NoteBlock) {
        let language = block.props.language.trimmingCharacters(in: .whitespaces)
        let languageClass = language.isEmpty ? "" : " class=\"language-" + Self.attribute(language) + "\""
        let stored = NoteMermaid.storedMode(of: block)
        if mode == .document, NoteMermaid.isDiagram(block), stored != .code, let art = diagramArt?(block) {
            diagram(block, art: art, showsCode: stored == .split, languageClass: languageClass)
            return
        }
        var pre = "<pre" + colorAttributes(block.color)
        if !language.isEmpty, mode == .document { pre += " data-language=\"" + Self.attribute(language) + "\"" }
        let body = block.text.string
        pre += "><code" + languageClass + ">" + (body.hasPrefix("\n") ? "\n" : "") + Self.escape(body) + "</code></pre>"
        guard !block.props.caption.isEmpty else {
            output += pre
            return
        }
        output += "<figure class=\"code\"" + (mode == .fragment ? " style=\"margin:1em 0\"" : "") + ">" + pre
            + "<figcaption>" + inline(block.props.caption) + "</figcaption></figure>"
    }

    private mutating func diagram(_ block: NoteBlock, art: NoteDiagramArt, showsCode: Bool, languageClass: String) {
        var html = "<figure data-language=\"mermaid\"" + colorClass(block.color, adding: ["diagram"] + (showsCode ? ["split"] : [])) + ">"
        if showsCode {
            let body = block.text.string
            html += "<pre><code" + languageClass + ">" + (body.hasPrefix("\n") ? "\n" : "") + Self.escape(body) + "</code></pre>"
        }
        html += "<div class=\"diagram-art diagram-light\">" + art.light + "</div>"
        if let dark = art.dark { html += "<div class=\"diagram-art diagram-dark\">" + dark + "</div>" }
        if !block.props.caption.isEmpty { html += "<figcaption>" + inline(block.props.caption) + "</figcaption>" }
        output += html + "</figure>"
    }

    private mutating func equation(_ block: NoteBlock) {
        let tex = block.text.string
        let labelAnchors = (mathNumbering.entries[block.id]?.labels ?? []).compactMap { equationAnchors[$0] }
        let id = labelAnchors.first.map { " id=\"" + Self.attribute($0) + "\"" } ?? ""
        var html = "<div data-block=\"equation\"" + id + " data-tex=\"" + Self.attribute(tex) + "\"" + colorClass(block.color, adding: ["equation"]) + ">"
        html += labelAnchors.dropFirst().map { "<span id=\"" + Self.attribute($0) + "\"></span>" }.joined()
        if let art = equationArt?(tex, true, mathNumbering.context(for: block.id)) {
            html += equationImage(art, tex: tex, attributes: "")
        } else if mode == .document {
            html += "<span class=\"tex\">" + Self.escape(tex) + "</span>"
        } else {
            html += "$$" + Self.escape(tex) + "$$"
        }
        output += html + "</div>"
    }

    private mutating func media(_ block: NoteBlock) {
        let raw = block.props.source ?? ""
        var classes = [block.kind.rawValue]
        if mode == .document, block.kind == .image, block.props.alignment != .center { classes.append("align-" + block.props.alignment.rawValue) }
        var style = mode == .fragment ? "margin:1em 0;" : ""
        if mode == .document, block.kind == .image, let width = block.props.width, width > 0 {
            style += width <= 1 ? "width:" + String(Int((width * 100).rounded())) + "%;" : "width:" + String(Int(width.rounded())) + "px;"
        }
        output += "<figure" + colorClass(block.color, adding: classes) + (style.isEmpty ? "" : " style=\"" + style + "\"") + ">"
        switch block.kind {
        case .image:
            let alt = block.props.alt.map { " alt=\"" + Self.attribute($0) + "\"" } ?? " alt=\"\""
            output += "<img src=\"" + Self.attribute(source(raw)) + "\"" + alt + ">"
        case .video:
            output += "<video src=\"" + Self.attribute(link(raw)) + "\" controls preload=\"metadata\"></video>"
        default:
            output += "<audio src=\"" + Self.attribute(link(raw)) + "\" controls preload=\"metadata\"></audio>"
        }
        figureCaption(block)
        output += "</figure>"
    }

    private mutating func pdf(_ block: NoteBlock) {
        let raw = block.props.source ?? ""
        let fallback = raw.removingPercentEncoding.map { ($0 as NSString).lastPathComponent } ?? raw
        let name = block.props.alt.flatMap { $0.isEmpty ? nil : $0 } ?? (fallback.isEmpty ? "PDF" : fallback)
        var attributes = " data-source=\"" + Self.attribute(raw) + "\""
        if let alt = block.props.alt { attributes += " data-name=\"" + Self.attribute(alt) + "\"" }
        if let width = block.props.width, width > 0 { attributes += " data-width=\"" + NoteMDWriter.number(width) + "\"" }
        if block.props.alignment != .center { attributes += " data-align=\"" + block.props.alignment.rawValue + "\"" }
        var classes = ["pdf"]
        var style = ""
        switch mode {
        case .document:
            if block.props.alignment != .center { classes.append("align-" + block.props.alignment.rawValue) }
            if let width = block.props.width, width > 0 {
                style = width <= 1 ? "width:" + String(Int((width * 100).rounded())) + "%" : "width:" + String(Int(width.rounded())) + "px"
            }
        case .fragment:
            style = "margin:1em 0"
        }
        let anchor = "<a class=\"file-link\" href=\"" + Self.attribute(link(raw)) + "\"><span class=\"file-icon\">\u{1F4C4}</span> "
            + Self.escape(name) + "</a>"
        output += "<figure data-block=\"pdf\"" + attributes + colorClass(block.color, adding: classes)
            + (style.isEmpty ? "" : " style=\"" + style + "\"") + ">"
        if mode == .document, !raw.isEmpty {
            output += "<object class=\"pdf-frame\" data=\"" + Self.attribute(pdfSource(raw)) + "\" type=\"application/pdf\" aria-label=\""
                + Self.attribute(name) + "\">" + anchor + "</object>"
        } else {
            output += anchor
        }
        if !block.props.caption.isEmpty { output += "<figcaption>" + inline(block.props.caption) + "</figcaption>" }
        output += "</figure>"
    }

    static let embeddedPDFLimit = 25_000_000

    func pdfSource(_ value: String) -> String {
        let url = assets(value) ?? URL(string: value).flatMap { $0.scheme != nil ? $0 : nil }
        guard let url else { return value }
        if embedImages, url.isFileURL,
           let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= Self.embeddedPDFLimit,
           let data = try? Data(contentsOf: url) {
            return "data:application/pdf;base64," + data.base64EncodedString()
        }
        return url.absoluteString
    }

    private mutating func bookmark(_ block: NoteBlock) {
        let raw = block.props.source ?? ""
        let metadata = block.props.bookmark
        var attributes = " data-source=\"" + Self.attribute(raw) + "\""
        if let title = metadata?.title { attributes += " data-title=\"" + Self.attribute(title) + "\"" }
        if let summary = metadata?.summary { attributes += " data-summary=\"" + Self.attribute(summary) + "\"" }
        if let site = metadata?.siteName { attributes += " data-site=\"" + Self.attribute(site) + "\"" }
        if let icon = metadata?.iconURL { attributes += " data-icon-url=\"" + Self.attribute(icon) + "\"" }
        if let image = metadata?.imageURL { attributes += " data-image=\"" + Self.attribute(image) + "\"" }
        let href = Self.attribute(link(raw))
        let title = metadata?.title?.isEmpty == false ? metadata!.title! : raw
        figure("bookmark", block, attributes: attributes, content: bookmarkCard(href: href, title: title, raw: raw, metadata: metadata))
    }

    private func bookmarkCard(href: String, title: String, raw: String, metadata: NoteBookmark?) -> String {
        guard mode == .document else { return "<a href=\"" + href + "\">" + Self.escape(title) + "</a>" }
        var card = "<a class=\"bookmark-card\" href=\"" + href + "\"><span class=\"bookmark-text\"><span class=\"bookmark-title\">"
            + Self.escape(title) + "</span>"
        if let summary = metadata?.summary, !summary.isEmpty { card += "<span class=\"bookmark-summary\">" + Self.escape(summary) + "</span>" }
        card += "<span class=\"bookmark-url\">"
        if let icon = metadata?.iconURL { card += "<img class=\"bookmark-favicon\" alt=\"\" src=\"" + Self.attribute(source(icon)) + "\">" }
        card += Self.escape(metadata?.siteName ?? URL(string: raw)?.host ?? raw) + "</span></span>"
        if let image = metadata?.imageURL { card += "<img class=\"bookmark-image\" alt=\"\" src=\"" + Self.attribute(source(image)) + "\">" }
        return card + "</a>"
    }

    private mutating func table(_ block: NoteBlock) {
        guard var grid = block.props.table else { return }
        grid.normalize()
        let border = mode == .fragment ? "border:1px solid #D9D8E3;padding:6px 10px;vertical-align:top;" : ""
        output += "<table" + colorClass(block.color, adding: []) + (mode == .fragment ? " style=\"border-collapse:collapse\"" : "") + ">"
        func cell(_ tag: String, _ text: NoteText, column: Int, scope: String) -> String {
            var style = border
            if grid.alignments.indices.contains(column), let alignment = grid.alignments[column] { style += "text-align:" + alignment.rawValue + ";" }
            return "<" + tag + scope + (style.isEmpty ? "" : " style=\"" + style + "\"") + ">" + inline(text) + "</" + tag + ">"
        }
        var rows = grid.rows[...]
        if grid.headerRow, let head = rows.first {
            output += "<thead><tr>" + head.enumerated().map { cell("th", $0.element, column: $0.offset, scope: " scope=\"col\"") }.joined() + "</tr></thead>"
            rows = rows.dropFirst()
        }
        output += "<tbody>"
        for row in rows {
            output += "<tr>"
            for (column, text) in row.enumerated() {
                output += grid.headerColumn && column == 0 ? cell("th", text, column: column, scope: " scope=\"row\"") : cell("td", text, column: column, scope: "")
            }
            output += "</tr>"
        }
        output += "</tbody></table>"
    }

    private mutating func contents(_ block: NoteBlock) {
        output += "<nav data-block=\"tableOfContents\"" + colorClass(block.color, adding: ["table-of-contents"]) + "><ul>"
        let base = outline.map(\.level).min() ?? 1
        for entry in outline {
            output += "<li class=\"toc-level-" + String(entry.level - base + 1) + "\"><a href=\"#" + Self.attribute(entry.anchor) + "\">"
                + Self.escape(entry.title.isEmpty ? "Untitled" : entry.title) + "</a></li>"
        }
        output += "</ul></nav>"
    }

    func inline(_ text: NoteText) -> String {
        let string = text.string as NSString
        let runs = text.runs()
        var html = ""
        var index = 0
        while index < runs.count {
            let link = runs[index].marks.atom == nil ? runs[index].marks.link : nil
            var end = index + 1
            if link != nil {
                while end < runs.count, runs[end].marks.atom == nil, runs[end].marks.link == link { end += 1 }
            }
            var inner = ""
            for run in runs[index..<end] { inner += self.run(run.range, run.marks, string) }
            if let link { html += "<a href=\"" + Self.attribute(self.link(link)) + "\">" + inner + "</a>" } else { html += inner }
            index = end
        }
        return html
    }

    private func run(_ range: Range<Int>, _ marks: NoteMarks, _ string: NSString) -> String {
        if let atom = marks.atom { return self.atom(atom) }
        var body = Self.escapeText(string, range)
        if marks.code { body = "<code>" + body + "</code>" }
        if marks.strikethrough { body = "<s>" + body + "</s>" }
        if marks.underline { body = "<u>" + body + "</u>" }
        if marks.italic { body = "<em>" + body + "</em>" }
        if marks.bold { body = "<strong>" + body + "</strong>" }
        if let color = marks.color {
            let token = NoteHTMLColor.token(color)
            let palette = NotePageHTMLStyle.palette[color.color] ?? NotePageHTMLStyle.palette[.gray]!
            switch (mode, color.isBackground) {
            case (.document, true): body = "<mark class=\"highlight-" + token + "\">" + body + "</mark>"
            case (.document, false): body = "<span class=\"highlight-" + token + "\">" + body + "</span>"
            case (.fragment, true):
                body = "<mark data-color=\"" + token + "\" style=\"background-color:#" + palette.background + ";color:inherit\">" + body + "</mark>"
            case (.fragment, false):
                body = "<span data-color=\"" + token + "\" style=\"color:#" + palette.text + "\">" + body + "</span>"
            }
        }
        return body
    }

    private static func escapeText(_ string: NSString, _ range: Range<Int>) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(range.count)
        func add(_ literal: String) { units.append(contentsOf: literal.utf16) }
        let length = string.length
        for offset in range {
            let unit = string.character(at: offset)
            switch unit {
            case 38: add("&amp;")
            case 60: add("&lt;")
            case 62: add("&gt;")
            case 10: add("<br>")
            case 9: add("<span style=\"white-space:pre\">\t</span>")
            case 0xA0: add("&nbsp;")
            case 32:
                let previous = offset > 0 ? string.character(at: offset - 1) : 10
                let next = offset + 1 < length ? string.character(at: offset + 1) : 10
                if previous == 32 || previous == 10 || next == 10 { add("&nbsp;") } else { units.append(unit) }
            default: units.append(unit)
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    private func equationImage(_ art: NoteEquationArt, tex: String, attributes: String) -> String {
        let image = "<img" + attributes + " alt=\"" + Self.attribute(tex) + "\" src=\"" + Self.attribute(source(art.url.absoluteString)) + "\""
        let areas = art.links.compactMap { link -> String? in
            guard let anchor = equationAnchors[link.key] else { return nil }
            let corners = [link.rect.minX.rounded(.down), link.rect.minY.rounded(.down), link.rect.maxX.rounded(.up), link.rect.maxY.rounded(.up)]
            return "<area shape=\"rect\" coords=\"" + corners.map { String(Int($0)) }.joined(separator: ",") + "\" href=\"#"
                + Self.attribute(anchor) + "\" alt=\"" + Self.attribute(referenceDescription(link.key)) + "\">"
        }
        guard !areas.isEmpty else { return image + ">" }
        let map = areas.joined()
        let name = "equation-links-" + Self.fingerprint(map)
        return image + " usemap=\"#" + name + "\"><map name=\"" + name + "\">" + map + "</map>"
    }

    private func referenceDescription(_ key: String) -> String {
        let number = (mathNumbering.references[key] ?? []).compactMap { node -> String? in
            if case .text(let value, _) = node { return value }
            return nil
        }.joined()
        return "Equation " + (number.isEmpty ? key : number)
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
    }

    private func atom(_ atom: NoteAtom) -> String {
        if case .equation(let tex) = atom {
            let data = " data-tex=\"" + Self.attribute(tex) + "\""
            if let art = equationArt?(tex, false, mathNumbering.inlineContext) {
                return equationImage(art, tex: tex, attributes: " class=\"equation\"" + data)
            }
            if mode == .document { return "<span class=\"equation\"" + data + "><span class=\"tex\">" + Self.escape(tex) + "</span></span>" }
            return "<span class=\"equation\"" + data + ">$" + Self.escape(tex) + "$</span>"
        }
        if case .page(let target, let title) = atom {
            return "<a class=\"page-mention\" data-mention=\"page\" data-target=\"" + Self.attribute(target) + "\" href=\""
                + Self.attribute(link(target)) + "\">" + Self.escape(title.isEmpty ? "Untitled" : title) + "</a>"
        }
        if case .date(let date) = atom {
            var stamp = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
            if let hour = date.hour { stamp += String(format: "T%02d:%02d", hour, date.minute ?? 0) }
            return "<time class=\"date-mention\" data-mention=\"date\" datetime=\"" + stamp + "\"" + (date.remind ? " data-remind=\"true\"" : "")
                + ">@" + Self.escape(Self.formatted(date)) + "</time>"
        }
        if case .link(let url, let title) = atom {
            return "<a class=\"link-mention\" data-mention=\"link\" href=\"" + Self.attribute(url) + "\">"
                + Self.escape(title.isEmpty ? url : title) + "</a>"
        }
        if case .customEmoji = atom, let custom = customEmojiSource(atom.fallbackText) {
            let sizing = mode == .fragment ? " style=\"height:1.2em;width:auto;vertical-align:-0.2em\"" : ""
            return "<img class=\"custom-emoji inline-emoji\"" + sizing + " alt=\"" + Self.attribute(atom.fallbackText) + "\" title=\""
                + Self.attribute(atom.fallbackText) + "\" src=\"" + Self.attribute(custom) + "\">"
        }
        return Self.escape(atom.fallbackText)
    }

    private static func formatted(_ date: NoteDateMention) -> String {
        let calendar = Calendar(identifier: .gregorian)
        guard let value = calendar.date(from: date.components) else { return NoteAtom.date(date).fallbackText }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .long
        formatter.timeStyle = date.includesTime ? .short : .none
        return formatter.string(from: value)
    }
}
