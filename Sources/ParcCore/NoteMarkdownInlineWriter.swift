import Foundation

struct NoteMDInlineStyle {
    enum Shape { case paragraph, line, heading, cell, verbatim }

    var shape: Shape
    var taskSensitive = false
    var insideLink = false
    var htmlSafe = false
    var trailingComment = false
    var calloutSensitive = false

    static let paragraph = NoteMDInlineStyle(shape: .paragraph)
    static let line = NoteMDInlineStyle(shape: .line)
    static let heading = NoteMDInlineStyle(shape: .heading)
    static let cell = NoteMDInlineStyle(shape: .cell)
    static let verbatim = NoteMDInlineStyle(shape: .verbatim)

    var multiline: Bool { shape == .paragraph }
    var trimSensitive: Bool { shape != .verbatim }
}

struct NoteMDInlineWriter {
    let reader: NoteMDReader
    let referenceLabels: [String: String]

    private enum Mark: Equatable {
        case link(String), color(NoteColorStyle), underline, strike, bold, italic, code

        var isLink: Bool {
            if case .link = self { return true }
            return false
        }

        var rank: Int {
            switch self {
            case .link: return 0
            case .color: return 1
            case .underline: return 2
            case .strike: return 3
            case .bold: return 4
            case .italic: return 5
            case .code: return 6
            }
        }
    }

    private enum Token {
        case open(Mark)
        case close(Mark)
        case text(String)
        case lineBreak(hard: Bool)
        case atom(NoteAtom)
        case literal(String)
    }

    func write(_ text: NoteText, style: NoteMDInlineStyle) -> String {
        guard !text.isEmpty else { return "" }
        let markdown = render(text, style: style, safe: false)
        if matches(markdown, text, style: style) { return markdown }
        return render(text, style: style, safe: true)
    }

    private func matches(_ markdown: String, _ text: NoteText, style: NoteMDInlineStyle) -> Bool {
        var source = Array(markdown.utf8)
        switch style.shape {
        case .paragraph:
            let document = NoteMDBlockParser.parse(source)
            guard document.root.children.count == 1, let paragraph = document.root.children.first, paragraph.kind == .paragraph,
                  paragraph.blankBefore == 0, document.root.trailingBlank == 0 else { return false }
            source = paragraph.content
        case .heading:
            let document = NoteMDBlockParser.parse(Array("# ".utf8) + source)
            guard document.root.children.count == 1, let heading = document.root.children.first, heading.kind == .heading else { return false }
            source = heading.content
        case .cell:
            let cells = NoteMDTableRow.cells(Array("| ".utf8) + source + Array(" |".utf8))
            guard cells.count == 1 else { return false }
            source = cells[0]
        case .line, .verbatim:
            if style.insideLink {
                let tree = NoteMDInlineParser.parse(Array("[".utf8) + source + Array("](<>)".utf8), references: reader.references, footnotes: reader.footnotes)
                let children = tree.children(of: 0)
                guard children.count == 1, tree.nodes[children[0]].kind == .link else { return false }
                return reader.text(tree, children: tree.children(of: children[0])) == text
            }
        }
        let tree = style.shape == .verbatim
            ? NoteMDInlineParser.parseVerbatim(source, references: reader.references, footnotes: reader.footnotes)
            : NoteMDInlineParser.parse(source, references: reader.references, footnotes: reader.footnotes)
        return reader.text(tree, children: tree.children(of: 0)) == text
    }

    private func marks(of value: NoteMarks, atom: Bool) -> [Mark] {
        var result: [Mark] = []
        if let link = value.link { result.append(.link(link)) }
        if let color = value.color { result.append(.color(color)) }
        if value.underline { result.append(.underline) }
        if value.strikethrough { result.append(.strike) }
        if value.bold { result.append(.bold) }
        if value.italic { result.append(.italic) }
        if value.code, !atom { result.append(.code) }
        return result
    }

    private func tokens(_ text: NoteText) -> [Token] {
        struct Segment {
            var token: Token
            var marks: [Mark]
        }
        var segments: [Segment] = []
        let string = text.string as NSString
        for run in text.runs() {
            if let atom = run.marks.atom {
                segments.append(Segment(token: .atom(atom), marks: marks(of: run.marks, atom: true)))
                continue
            }
            let value = string.substring(with: NSRange(location: run.range.lowerBound, length: run.range.count))
            let runMarks = marks(of: run.marks, atom: false)
            var current = ""
            for character in value {
                if character == "\n" || character == "\u{2028}" {
                    if !current.isEmpty { segments.append(Segment(token: .text(current), marks: runMarks)) }
                    current = ""
                    segments.append(Segment(token: .lineBreak(hard: character == "\n"), marks: runMarks.filter { $0 != .code }))
                } else {
                    current.append(character)
                }
            }
            if !current.isEmpty { segments.append(Segment(token: .text(current), marks: runMarks)) }
        }
        var result: [Token] = []
        var stack: [Mark] = []
        for (index, segment) in segments.enumerated() {
            let desired = segment.marks
            var keep = 0
            while keep < stack.count, desired.contains(stack[keep]), stack[keep] != .code || desired == stack { keep += 1 }
            if keep < stack.count {
                for mark in stack[keep...].reversed() { result.append(.close(mark)) }
                stack.removeSubrange(keep...)
            }
            var missing = desired.filter { !stack.contains($0) }
            if !missing.isEmpty {
                func extent(_ mark: Mark) -> Int {
                    var count = 0
                    var probe = index
                    while probe < segments.count, segments[probe].marks.contains(mark), count < 64 { count += 1; probe += 1 }
                    return count
                }
                missing.sort { left, right in
                    if left == .code { return false }
                    if right == .code { return true }
                    let a = extent(left), b = extent(right)
                    return a != b ? a > b : left.rank < right.rank
                }
                for mark in missing {
                    result.append(.open(mark))
                    stack.append(mark)
                }
            }
            result.append(segment.token)
        }
        for mark in stack.reversed() { result.append(.close(mark)) }
        return result
    }

    private struct Rendered {
        var prefix = ""
        var text: [Unicode.Scalar]?
        var suffix = ""
        var insideLink = false
        var isLinkOpen = false
        var delimiter: Unicode.Scalar?
        var opens = false
    }

    private func render(_ text: NoteText, style: NoteMDInlineStyle, safe: Bool) -> String {
        var items = tokens(text)
        collapseAutolinks(&items, safe: safe)
        var pieces: [Rendered] = []
        var linkDepth = style.insideLink ? 1 : 0
        var index = 0
        while index < items.count {
            switch items[index] {
            case .open(.code):
                var content = ""
                var probe = index + 1
                while probe < items.count, case .text(let value) = items[probe] { content += value; probe += 1 }
                if probe < items.count, case .close(.code) = items[probe] { probe += 1 }
                if safe || style.htmlSafe && content.contains("</summary") {
                    pieces.append(Rendered(prefix: "<code>"))
                    pieces.append(Rendered(text: Array(content.unicodeScalars), insideLink: linkDepth > 0))
                    pieces.append(Rendered(prefix: "</code>"))
                } else {
                    pieces.append(Rendered(prefix: codeSpan(content, pipes: false)))
                }
                index = probe
                continue
            case .open(let mark):
                if case .link = mark { linkDepth += 1 }
                let open = openString(mark, safe: safe)
                pieces.append(Rendered(prefix: open, isLinkOpen: mark.isLink, delimiter: Self.delimiter(open), opens: true))
            case .close(let mark):
                if case .link(let url) = mark {
                    linkDepth -= 1
                    pieces.append(Rendered(prefix: "](" + Self.destination(url) + ")"))
                    if !safe, let label = referenceLabels[url] {
                        var content = ""
                        var probe = index - 1
                        var plain = true
                        while probe >= 0 {
                            if case .open(.link(let opened)) = items[probe], opened == url { break }
                            if case .text(let value) = items[probe] { content = value + content } else { plain = false }
                            probe -= 1
                        }
                        let following = nextCharacter(items, after: index)
                        if plain, NoteMDText.normalizeLabel(content) == NoteMDText.normalizeLabel(label) {
                            pieces[pieces.count - 1].prefix = following == "(" || following == "[" || following == ":" ? "][]" : "]"
                        } else {
                            pieces[pieces.count - 1].prefix = "][" + label + "]"
                        }
                    }
                } else {
                    let close = closeString(mark, safe: safe)
                    pieces.append(Rendered(prefix: close, delimiter: Self.delimiter(close), opens: false))
                }
            case .text(let value):
                pieces.append(Rendered(text: Array(value.unicodeScalars), insideLink: linkDepth > 0))
            case .literal(let value):
                pieces.append(Rendered(prefix: value))
            case .lineBreak(let hard):
                let isLast = index == items.count - 1 || items[(index + 1)...].allSatisfy { if case .close = $0 { return true } else { return false } }
                let isFirst = items[..<index].allSatisfy { if case .open = $0 { return true } else { return false } }
                let previousContent = items[..<index].reversed().first { if case .open = $0 { return false } else if case .close = $0 { return false } else { return true } }
                let followsBreak = previousContent.map { if case .lineBreak = $0 { return true } else { return false } } ?? false
                var opensWithTag = false
                if case .atom(.raw(let source))? = previousContent, source.hasPrefix("<"),
                   items[..<index].filter({ if case .open = $0 { return false } else if case .close = $0 { return false } else { return true } }).count == 1 {
                    opensWithTag = true
                }
                var beforeBlockTag = false
                if index + 1 < items.count, case .atom(.raw(let source)) = items[index + 1] {
                    let bytes = Array(source.utf8)
                    beforeBlockTag = NoteMDHTML.blockStart(bytes, from: 0, upTo: bytes.count, interruptsParagraph: true) != nil
                }
                if style.multiline, beforeBlockTag {
                    pieces.append(Rendered(prefix: hard ? (isFirst || followsBreak ? "&#10;" : "<br>") : "&#x2028;"))
                } else if style.multiline {
                    if hard { pieces.append(Rendered(prefix: isLast ? (isFirst || followsBreak ? "&#10;" : "<br>") : "\\\n")) }
                    else { pieces.append(Rendered(prefix: isLast || isFirst || followsBreak || opensWithTag ? "&#x2028;" : "\n")) }
                } else {
                    pieces.append(Rendered(prefix: hard ? "<br>" : "&#x2028;"))
                }
            case .atom(let atom):
                var markup = atomString(atom, safe: safe, next: nextCharacter(items, after: index))
                if style.multiline, case .raw = atom, markup.contains("\n") { markup = Self.continuationSafe(markup) }
                pieces.append(Rendered(prefix: markup))
            }
            index += 1
        }
        return escape(pieces, style: style, safe: safe)
    }

    private static func delimiter(_ markup: String) -> Unicode.Scalar? {
        guard let first = markup.unicodeScalars.first, first == "*" || first == "~" || first == "=" else { return nil }
        return first
    }

    private func nextCharacter(_ items: [Token], after index: Int) -> Unicode.Scalar? {
        guard index + 1 < items.count else { return nil }
        switch items[index + 1] {
        case .text(let value): return value.unicodeScalars.first
        case .open(.link): return "["
        case .close(.link): return "]"
        case .open, .close: return "*"
        case .lineBreak: return nil
        case .atom, .literal: return "x"
        }
    }

    private func collapseAutolinks(_ items: inout [Token], safe: Bool) {
        var index = 0
        while index + 2 < items.count {
            if case .open(.link(let url)) = items[index], case .text(let value) = items[index + 1], case .close(.link(let closing)) = items[index + 2], url == closing,
               let form = autolinkForm(url: url, text: value, before: index > 0 ? previousCharacter(items, before: index) : nil,
                                       following: followingWord(items, after: index + 2), safe: safe) {
                items.replaceSubrange(index...(index + 2), with: [.literal(form)])
            }
            index += 1
        }
    }

    private func followingWord(_ items: [Token], after index: Int) -> String? {
        guard index + 1 < items.count else { return "" }
        switch items[index + 1] {
        case .text(let value): return String(value.prefix(while: { !$0.isWhitespace }))
        case .lineBreak: return ""
        default: return nil
        }
    }

    private func previousCharacter(_ items: [Token], before index: Int) -> Unicode.Scalar? {
        guard index > 0 else { return nil }
        switch items[index - 1] {
        case .text(let value): return value.unicodeScalars.last
        case .open, .close: return "*"
        case .lineBreak: return nil
        case .atom, .literal: return "x"
        }
    }

    private func autolinkForm(url: String, text: String, before: Unicode.Scalar?, following: String?, safe: Bool) -> String? {
        let bareBefore = before == nil || NoteMDByte.isUnicodeWhitespace(before) || "*_~(".unicodeScalars.contains(before!)
        let bareAfter = following != nil
        func extendsFully(_ value: String) -> Bool {
            let bytes = Array((value + (following ?? "")).utf8)
            guard let (_, length) = NoteMDAutolink.extended(bytes, at: 0, upTo: bytes.count) else { return false }
            return length == value.utf8.count
        }
        let schemeLike = url.range(of: "^[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\\s<>\\x00-\\x1F]*$", options: .regularExpression) != nil
        if url == text, schemeLike {
            let lower = url.lowercased()
            if !safe, bareBefore, bareAfter, lower.hasPrefix("http://") || lower.hasPrefix("https://"), extendsFully(url) { return url }
            return "<" + url + ">"
        }
        if url == "mailto:" + text, text.range(of: "^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$", options: .regularExpression) != nil {
            return "<" + text + ">"
        }
        if !safe, url == "http://" + text, text.lowercased().hasPrefix("www."), bareBefore, bareAfter, extendsFully(text) { return text }
        return nil
    }

    private func openString(_ mark: Mark, safe: Bool) -> String {
        switch mark {
        case .link: return "["
        case .color(let style): return Self.colorOpen(style, safe: safe)
        case .underline: return "<u>"
        case .strike: return safe ? "<s>" : "~~"
        case .bold: return safe ? "<b>" : "**"
        case .italic: return safe ? "<i>" : "*"
        case .code: return "<code>"
        }
    }

    private func closeString(_ mark: Mark, safe: Bool) -> String {
        switch mark {
        case .link: return "]"
        case .color(let style): return Self.colorClose(style, safe: safe)
        case .underline: return "</u>"
        case .strike: return safe ? "</s>" : "~~"
        case .bold: return safe ? "</b>" : "**"
        case .italic: return safe ? "</i>" : "*"
        case .code: return "</code>"
        }
    }

    private static func colorOpen(_ style: NoteColorStyle, safe: Bool) -> String {
        switch style {
        case .background(.yellow): return safe ? "<mark>" : "=="
        case .background: return "<mark data-color=\"\(NoteMDColor.name(style))\">"
        case .text: return "<span data-color=\"\(NoteMDColor.name(style))\">"
        }
    }

    private static func colorClose(_ style: NoteColorStyle, safe: Bool) -> String {
        switch style {
        case .background(.yellow): return safe ? "</mark>" : "=="
        case .background: return "</mark>"
        case .text: return "</span>"
        }
    }

    private func codeSpan(_ content: String, pipes: Bool) -> String {
        var longest = 0, current = 0
        for character in content {
            if character == "`" { current += 1; longest = max(longest, current) } else { current = 0 }
        }
        let fence = String(repeating: "`", count: longest + 1)
        let needsPadding = content.hasPrefix("`") || content.hasSuffix("`")
            || (content.hasPrefix(" ") && content.hasSuffix(" ") && content.contains(where: { $0 != " " }))
        var body = needsPadding ? " " + content + " " : content
        if pipes { body = body.replacingOccurrences(of: "|", with: "\\|") }
        return fence + body + fence
    }

    static func destination(_ url: String) -> String {
        if url.isEmpty { return "<>" }
        var depth = 0
        var balanced = true
        var needsAngle = url.isEmpty ? false : url.hasPrefix("<")
        for scalar in url.unicodeScalars {
            if scalar == "(" { depth += 1 }
            if scalar == ")" {
                depth -= 1
                if depth < 0 { balanced = false }
            }
            if scalar.value <= 32 || scalar.value == 127 { needsAngle = true }
        }
        if depth != 0 || !balanced { needsAngle = true }
        if needsAngle {
            var result = "<"
            for character in url {
                if character == "<" || character == ">" || character == "\\" { result.append("\\") }
                result.append(character)
            }
            return result + ">"
        }
        var result = ""
        let scalars = Array(url.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            if scalar == "\\", index + 1 < scalars.count, scalars[index + 1].isASCII, NoteMDByte.isPunctuation(UInt8(scalars[index + 1].value)) {
                result += "\\"
            } else if scalar == "\\", index + 1 == scalars.count {
                result += "\\"
            } else if scalar == "&", Self.entityLike(scalars, at: index) {
                result += "\\"
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    static func entityLike(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        var probe = index + 1
        guard probe < scalars.count else { return false }
        if scalars[probe] == "#" {
            probe += 1
            var digits = 0
            if probe < scalars.count, scalars[probe] == "x" || scalars[probe] == "X" {
                probe += 1
                while probe < scalars.count, scalars[probe].isASCII, NoteMDByte.isHexDigit(UInt8(scalars[probe].value)), digits < 6 { probe += 1; digits += 1 }
            } else {
                while probe < scalars.count, scalars[probe].isASCII, NoteMDByte.isDigit(UInt8(scalars[probe].value)), digits < 7 { probe += 1; digits += 1 }
            }
            return digits > 0 && probe < scalars.count && scalars[probe] == ";"
        }
        var letters = 0
        while probe < scalars.count, scalars[probe].isASCII, NoteMDByte.isAlphanumeric(UInt8(scalars[probe].value)), letters < 32 { probe += 1; letters += 1 }
        return letters > 0 && probe < scalars.count && scalars[probe] == ";"
    }

    private func atomString(_ atom: NoteAtom, safe: Bool, next: Unicode.Scalar?) -> String {
        switch atom {
        case .raw(let source):
            return source
        case .equation(let source):
            let scalars = Array(source.unicodeScalars)
            var valid = !safe && !scalars.isEmpty && !NoteMDByte.isUnicodeWhitespace(scalars.first) && !NoteMDByte.isUnicodeWhitespace(scalars.last)
                && !source.contains("\n") && !source.contains("\u{2028}")
            if let next, next.isASCII, NoteMDByte.isDigit(UInt8(next.value)) || next == "$" { valid = false }
            var probe = 0
            while valid, probe < scalars.count {
                if scalars[probe] == "\\" {
                    if probe + 1 >= scalars.count { valid = false }
                    probe += 2
                    continue
                }
                if scalars[probe] == "$" { valid = false }
                probe += 1
            }
            if valid { return "$" + source + "$" }
            return "<span data-equation=\"\(NoteMDText.escapeAttribute(source))\">\(Self.escapeLight(source))</span>"
        case .page(let target, let title):
            if !safe, NoteMDLinks.isRelativeMarkdown(target), NoteMDLinks.stem(target) == title, !title.isEmpty,
               !target.contains(where: { $0 == " " || $0 == "\n" }) {
                return "[" + Self.escapeAll(title) + "](" + Self.destination(target) + ")"
            }
            if title == target { return "[[" + target + "]]" }
            return "[[" + target + "|" + title + "]]"
        case .date(let date):
            var value = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
            if let hour = date.hour { value += String(format: "T%02d:%02d", hour, date.minute ?? 0) }
            return "<time datetime=\"\(value)\"\(date.remind ? " data-remind" : "")>\(atom.fallbackText)</time>"
        case .link(let url, let title):
            return "<a href=\"\(NoteMDText.escapeAttribute(url))\" data-mention>\(Self.escapeLight(title))</a>"
        }
    }

    private static func continuationSafe(_ markup: String) -> String {
        let lines = markup.components(separatedBy: "\n")
        let indented = lines.dropFirst().map { line -> String in
            guard let first = line.utf8.first, NoteMDBlockParser.mayOpenBlock(first) else { return line }
            return "    " + line
        }
        return ([lines[0]] + indented).joined(separator: "\n")
    }

    static func escapeLight(_ text: String) -> String {
        var result = ""
        let scalars = Array(text.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            if scalar == ".", index >= 3, String(String.UnicodeScalarView(scalars[(index - 3)..<index])).lowercased() == "www",
               index == 3 || NoteMDByte.isUnicodeWhitespace(scalars[index - 4]) || "*_~(".unicodeScalars.contains(scalars[index - 4]) {
                result += "\\."
                continue
            }
            switch scalar {
            case "\n": result += "<br>"
            case "\u{2028}": result += "&#x2028;"
            case "<": result += "&lt;"
            case "\\", "*", "_", "`", "[", "]", "&", "$", "~", "=", "!", ">", "@", ":":
                result += "\\"
                result.unicodeScalars.append(scalar)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        if let first = result.unicodeScalars.first, first == " " || first == "\t" { result = (first == " " ? "&#32;" : "&#9;") + result.dropFirst() }
        if let last = result.unicodeScalars.last, last == " " || last == "\t" { result = result.dropLast() + (last == " " ? "&#32;" : "&#9;") }
        return result
    }

    static func escapeAll(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if scalar == "\n" { result += "<br>"; continue }
            if scalar == "\u{2028}" { result += "&#x2028;"; continue }
            if scalar == "<" { result += "&lt;"; continue }
            if scalar.isASCII, scalar != "|", NoteMDByte.isPunctuation(UInt8(scalar.value)) { result += "\\" }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    private struct Hazards {
        var lastDollar = -1
        var lastGreater = -1
        var lastCloseBracket = -1
        var lastLinkBracket = -1
        var backticks = 0
        var scalars: [Unicode.Scalar] = []
    }

    private func escape(_ pieces: [Rendered], style: NoteMDInlineStyle, safe: Bool) -> String {
        var hazards = Hazards()
        var offsets: [Int] = []
        for piece in pieces {
            offsets.append(hazards.scalars.count)
            if let text = piece.text { hazards.scalars.append(contentsOf: text) } else { hazards.scalars.append(contentsOf: piece.prefix.unicodeScalars) }
        }
        let all = hazards.scalars
        for (index, scalar) in all.enumerated() {
            switch scalar {
            case "$": hazards.lastDollar = index
            case ">": hazards.lastGreater = index
            case "]":
                hazards.lastCloseBracket = index
                if index + 1 < all.count, all[index + 1] == "(" || all[index + 1] == "[" { hazards.lastLinkBracket = index }
            case "`": hazards.backticks += 1
            default: break
            }
        }
        if style.trailingComment {
            hazards.lastGreater = Int.max
            hazards.lastDollar = Int.max
            hazards.backticks = Int.max
        }
        var output = String.UnicodeScalarView()
        var forced: Set<Int> = []
        var atLineStart = style.multiline
        var previous: Unicode.Scalar?
        var openDelimiters: [Unicode.Scalar: Int] = [:]
        let hasReferences = !reader.references.isEmpty
        for (pieceIndex, piece) in pieces.enumerated() {
            if let delimiter = piece.delimiter { openDelimiters[delimiter, default: 0] += piece.opens ? 1 : -1 }
            guard let text = piece.text else {
                let markup = style.shape == .cell ? piece.prefix.replacingOccurrences(of: "|", with: "\\|") : piece.prefix
                output.append(contentsOf: markup.unicodeScalars)
                if let last = piece.prefix.unicodeScalars.last {
                    previous = last
                    atLineStart = style.multiline && last == "\n"
                }
                continue
            }
            let base = offsets[pieceIndex]
            let nextPiece = pieceIndex + 1 < pieces.count ? pieces[pieceIndex + 1] : nil
            let afterText: Unicode.Scalar? = nextPiece.flatMap { $0.text?.first ?? $0.prefix.unicodeScalars.first } ?? (style.insideLink ? "]" : nil)
            let nextIsLinkOpen = nextPiece?.isLinkOpen ?? false
            let endsLine = nextPiece == nil || nextPiece!.prefix.hasPrefix("\\\n") || nextPiece!.prefix.hasPrefix("\n")
                || nextPiece!.prefix.hasPrefix("<br>") || nextPiece!.prefix.hasPrefix("&#x2028;")
            for (offset, scalar) in text.enumerated() {
                let global = base + offset
                let before: Unicode.Scalar? = offset > 0 ? text[offset - 1] : previous
                let after: Unicode.Scalar? = offset + 1 < text.count ? text[offset + 1] : afterText
                let lineStart = offset == 0 && atLineStart
                let isLastOfLine = offset == text.count - 1 && endsLine
                var escaped = false
                var entity: String?
                if style.trimSensitive, scalar == " " || scalar == "\t" {
                    if (offset == 0 && (atLineStart || (pieceIndex == 0 && !style.multiline))) || isLastOfLine {
                        entity = scalar == " " ? "&#32;" : "&#9;"
                    }
                }
                if entity == nil, forced.contains(global) { escaped = true }
                if entity == nil, !escaped {
                    if safe {
                        if scalar == "<" { entity = "&lt;" }
                        else if scalar.isASCII, NoteMDByte.isPunctuation(UInt8(scalar.value)) { escaped = true }
                    } else {
                        if lineStart, style.multiline {
                            escaped = lineStartHazard(all, at: global, forced: &forced)
                        }
                        if !escaped {
                            escaped = inlineHazard(scalar, all: all, at: global, before: before, after: after, piece: piece,
                                                   style: style, hazards: hazards, hasReferences: hasReferences,
                                                   nextIsLinkOpen: nextIsLinkOpen && offset == text.count - 1,
                                                   markupOpen: (openDelimiters[scalar] ?? 0) > 0, forced: &forced)
                        }
                        if scalar == "<", escaped, style.htmlSafe {
                            escaped = false
                            entity = "&lt;"
                        }
                    }
                }
                if let entity {
                    output.append(contentsOf: entity.unicodeScalars)
                } else {
                    if escaped { output.append("\\") }
                    output.append(scalar)
                }
                previous = scalar
            }
            atLineStart = false
        }
        return String(output)
    }

    private func lineStartHazard(_ all: [Unicode.Scalar], at index: Int, forced: inout Set<Int>) -> Bool {
        var lineEnd = index
        while lineEnd < all.count, all[lineEnd] != "\n" { lineEnd += 1 }
        let line = Array(all[index..<lineEnd])
        guard let first = line.first else { return false }
        func next(_ offset: Int) -> Unicode.Scalar? { offset < line.count ? line[offset] : nil }
        func isBlankOrEnd(_ value: Unicode.Scalar?) -> Bool { value == nil || value == " " || value == "\t" }
        func thematic(_ character: Unicode.Scalar) -> Bool {
            var count = 0
            for scalar in line {
                if scalar == character { count += 1 } else if scalar != " " && scalar != "\t" { return false }
            }
            return count >= 3
        }
        func setext(_ character: Unicode.Scalar) -> Bool {
            var index = 0
            while index < line.count, line[index] == character { index += 1 }
            return index > 0 && line[index...].allSatisfy { $0 == " " || $0 == "\t" }
        }
        switch first {
        case "#":
            var count = 0
            while count < line.count, line[count] == "#" { count += 1 }
            return count <= 6 && isBlankOrEnd(next(count))
        case ">":
            return true
        case "-", "+", "*":
            if isBlankOrEnd(next(1)) || thematic(first) { return true }
            return first == "-" && (setext("-") || Self.delimiterRowLike(line))
        case "=":
            return setext("=")
        case "_":
            return thematic("_")
        case "`", "~":
            var count = 0
            while count < line.count, line[count] == first { count += 1 }
            return count >= 3
        case "$":
            return next(1) == "$"
        case ":":
            var count = 0
            while count < line.count, line[count] == ":" { count += 1 }
            return count >= 3 || Self.delimiterRowLike(line)
        case "|":
            return Self.delimiterRowLike(line)
        case "[":
            if next(1) == "^" { return true }
            if let close = line.firstIndex(of: "]"), close + 1 < line.count, line[close + 1] == ":" { return true }
            return false
        case "<":
            if let second = next(1) {
                return second == "/" || second == "!" || second == "?" || (second.isASCII && NoteMDByte.isLetter(UInt8(second.value)))
            }
            return false
        default:
            if first.isASCII, NoteMDByte.isDigit(UInt8(first.value)) {
                var count = 0
                while count < line.count, line[count].isASCII, NoteMDByte.isDigit(UInt8(line[count].value)) { count += 1 }
                if count <= 9, count < line.count, line[count] == "." || line[count] == ")", isBlankOrEnd(next(count + 1)) {
                    forced.insert(index + count)
                }
            }
            return false
        }
    }

    private static func delimiterRowLike(_ line: [Unicode.Scalar]) -> Bool {
        guard line.contains("-") else { return false }
        return line.allSatisfy { $0 == "|" || $0 == ":" || $0 == "-" || $0 == " " || $0 == "\t" }
    }

    private func inlineHazard(_ scalar: Unicode.Scalar, all: [Unicode.Scalar], at index: Int, before: Unicode.Scalar?, after: Unicode.Scalar?,
                              piece: Rendered, style: NoteMDInlineStyle, hazards: Hazards, hasReferences: Bool,
                              nextIsLinkOpen: Bool, markupOpen: Bool, forced: inout Set<Int>) -> Bool {
        let beforeWhitespace = NoteMDByte.isUnicodeWhitespace(before)
        let afterWhitespace = NoteMDByte.isUnicodeWhitespace(after)
        let beforePunctuation = NoteMDByte.isUnicodePunctuation(before)
        let afterPunctuation = NoteMDByte.isUnicodePunctuation(after)
        let leftFlanking = !afterWhitespace && (!afterPunctuation || beforeWhitespace || beforePunctuation)
        let rightFlanking = !beforeWhitespace && (!beforePunctuation || afterWhitespace || afterPunctuation)
        switch scalar {
        case "\\":
            guard let after else { return true }
            return after.isASCII && NoteMDByte.isPunctuation(UInt8(after.value))
        case "*", "~":
            return leftFlanking || (rightFlanking && markupOpen)
        case "_":
            return leftFlanking && (!rightFlanking || beforePunctuation)
        case "=":
            if after == "=", before != "=" {
                let following: Unicode.Scalar? = index + 2 < all.count ? all[index + 2] : nil
                return following != "="
            }
            if before == "=" {
                let previous: Unicode.Scalar? = index >= 2 ? all[index - 2] : nil
                return previous != "=" && after != "="
            }
            return false
        case "`":
            return hazards.backticks >= 2
        case "[":
            if piece.insideLink || style.insideLink { return true }
            if after == "[" || after == "^" || before == "[" { return true }
            if style.calloutSensitive, index == 0, after == "!" { return true }
            if hazards.lastLinkBracket > index { return true }
            if hasReferences, hazards.lastCloseBracket > index { return true }
            if style.taskSensitive, index == 0, index + 2 < all.count, all[index + 1] == " " || all[index + 1] == "x" || all[index + 1] == "X",
               all[index + 2] == "]", index + 3 >= all.count || all[index + 3].isASCII && NoteMDByte.isWhitespace(UInt8(all[index + 3].value)) { return true }
            return false
        case "]":
            return piece.insideLink || style.insideLink
        case "!":
            return nextIsLinkOpen || after == "["
        case "<":
            guard let after else { return false }
            if after == "!" { return true }
            let opens = after == "/" || after == "?" || (after.isASCII && NoteMDByte.isLetter(UInt8(after.value)))
            return opens && (hazards.lastGreater > index || style.htmlSafe)
        case "&":
            return Self.entityLike(all, at: index)
        case "$":
            guard let after = after ?? (hazards.lastDollar == Int.max ? "x" : nil), !NoteMDByte.isUnicodeWhitespace(after) else { return false }
            if after == "$" || hazards.lastDollar == Int.max { return true }
            guard hazards.lastDollar > index else { return false }
            var probe = index + 1
            while probe < all.count, all[probe] != "$" { probe += 1 }
            guard probe < all.count else { return false }
            let closerFollower: Unicode.Scalar? = probe + 1 < all.count ? all[probe + 1] : nil
            let validFollower = closerFollower == nil || !(closerFollower!.isASCII && NoteMDByte.isDigit(UInt8(closerFollower!.value))) && closerFollower != "$"
            return probe > index + 1 && !NoteMDByte.isUnicodeWhitespace(all[probe - 1]) && validFollower
        case "@":
            guard let before, before.isASCII, NoteMDByte.isAlphanumeric(UInt8(before.value)) || "._+-".unicodeScalars.contains(before) else { return false }
            guard let after, after.isASCII, NoteMDByte.isAlphanumeric(UInt8(after.value)) || after == "-" || after == "_" else { return false }
            var probe = index + 1
            while probe < all.count, !NoteMDByte.isUnicodeWhitespace(all[probe]) {
                if all[probe] == "." { return true }
                probe += 1
            }
            return false
        case "|":
            return style.shape == .cell
        case "#":
            guard style.shape == .heading, beforeWhitespace else { return false }
            return all[index...].allSatisfy { $0 == "#" }
        case "h", "H", "w", "W":
            guard before == nil || beforeWhitespace || "*_~(".unicodeScalars.contains(before!) else { return false }
            let rest = String(String.UnicodeScalarView(all[index..<min(all.count, index + 8)])).lowercased()
            if rest.hasPrefix("https://") { forced.insert(index + 5) }
            else if rest.hasPrefix("http://") { forced.insert(index + 4) }
            else if rest.hasPrefix("www.") { forced.insert(index + 3) }
            return false
        default:
            return false
        }
    }
}
