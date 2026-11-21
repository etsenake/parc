import Foundation

package final class NoteHTMLNode {
    package let name: String
    package var attributes: [String: String]
    package var text: String
    package private(set) var children: [NoteHTMLNode] = []
    package private(set) weak var parent: NoteHTMLNode?

    package static let textName = "#text"
    package static let markerName = "#mso-marker"

    package init(element name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
        text = ""
    }

    package init(text: String) {
        name = Self.textName
        attributes = [:]
        self.text = text
    }

    package var isText: Bool { name == Self.textName }
    package var isElement: Bool { !isText }

    package subscript(_ key: String) -> String? { attributes[key] }

    package func append(_ child: NoteHTMLNode) {
        if child.isText, let last = children.last, last.isText {
            last.text += child.text
            return
        }
        child.parent = self
        children.append(child)
    }

    package var classes: [String] {
        guard let value = attributes["class"], !value.isEmpty else { return [] }
        return value.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\u{0C}" }).map(String.init)
    }

    package func hasClass(_ name: String) -> Bool { classes.contains(name) }

    package var textContent: String {
        if isText { return text }
        var result = ""
        for child in children { result += child.textContent }
        return result
    }

    package var isWhitespace: Bool {
        isText && text.unicodeScalars.allSatisfy { NoteHTMLNode.isSpace($0) }
    }

    package func first(where predicate: (NoteHTMLNode) -> Bool) -> NoteHTMLNode? {
        for child in children {
            if predicate(child) { return child }
            if let found = child.first(where: predicate) { return found }
        }
        return nil
    }

    package func all(where predicate: (NoteHTMLNode) -> Bool) -> [NoteHTMLNode] {
        var result: [NoteHTMLNode] = []
        func walk(_ node: NoteHTMLNode) {
            for child in node.children {
                if predicate(child) { result.append(child) }
                walk(child)
            }
        }
        walk(self)
        return result
    }

    package func hasAncestor(_ predicate: (NoteHTMLNode) -> Bool) -> Bool {
        var current = parent
        while let node = current {
            if predicate(node) { return true }
            current = node.parent
        }
        return false
    }

    package static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\n" || scalar == "\t" || scalar == "\r" || scalar == "\u{0C}"
    }
}

package enum NoteHTMLParser {
    package static func parse(_ html: String) -> NoteHTMLNode {
        var builder = NoteHTMLTreeBuilder()
        var scanner = NoteHTMLScanner(html)
        scanner.run { builder.handle($0) }
        return builder.root
    }
}

package enum NoteHTMLToken {
    case start(String, [String: String], selfClosing: Bool)
    case end(String)
    case comment(String)
    case text(String)
    case cdata(String)
}

package struct NoteHTMLScanner {
    private let input: [Unicode.Scalar]
    private var index = 0

    private static let rawText: Set<String> = ["script", "style", "xmp", "iframe", "noembed", "noframes", "noscript"]
    private static let escapableRawText: Set<String> = ["textarea", "title"]

    package init(_ html: String) {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(html.unicodeScalars.count)
        var previousCR = false
        for scalar in html.unicodeScalars {
            if scalar == "\r" { scalars.append("\n"); previousCR = true; continue }
            if scalar == "\n" && previousCR { previousCR = false; continue }
            previousCR = false
            if scalar == "\u{0}" { continue }
            scalars.append(scalar)
        }
        input = scalars
    }

    package mutating func run(_ emit: (NoteHTMLToken) -> Void) {
        var textStart = 0
        while index < input.count {
            guard input[index] == "<" else { index += 1; continue }
            let tagStart = index
            guard let token = scanMarkup() else { index = tagStart + 1; continue }
            if textStart < tagStart { emit(.text(NoteHTMLEntities.decode(input[textStart..<tagStart]))) }
            emit(token)
            if case .start(let name, _, let selfClosing) = token, !selfClosing,
               Self.rawText.contains(name) || Self.escapableRawText.contains(name) {
                let end = closingTag(name, from: index) ?? input.count
                if index < end {
                    let content = input[index..<end]
                    emit(.text(Self.escapableRawText.contains(name) ? NoteHTMLEntities.decode(content) : Self.string(content)))
                }
                index = end
            }
            textStart = index
        }
        if textStart < input.count { emit(.text(NoteHTMLEntities.decode(input[textStart..<input.count]))) }
    }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private func peek(_ offset: Int) -> Unicode.Scalar? {
        index + offset < input.count ? input[index + offset] : nil
    }

    private func matches(_ literal: String, at position: Int, caseInsensitive: Bool = false) -> Bool {
        var cursor = position
        for scalar in literal.unicodeScalars {
            guard cursor < input.count else { return false }
            let candidate = caseInsensitive ? Self.lowercased(input[cursor]) : input[cursor]
            if candidate != scalar { return false }
            cursor += 1
        }
        return true
    }

    private func find(_ literal: String, from position: Int) -> Int? {
        guard let first = literal.unicodeScalars.first else { return nil }
        var cursor = position
        while cursor < input.count {
            if input[cursor] == first && matches(literal, at: cursor) { return cursor }
            cursor += 1
        }
        return nil
    }

    private func closingTag(_ name: String, from position: Int) -> Int? {
        var cursor = position
        while cursor + 1 < input.count {
            if input[cursor] == "<" && input[cursor + 1] == "/" && matches(name, at: cursor + 2, caseInsensitive: true) {
                let after = cursor + 2 + name.unicodeScalars.count
                if after >= input.count || NoteHTMLNode.isSpace(input[after]) || input[after] == ">" || input[after] == "/" {
                    return cursor
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func lowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if scalar.value >= 65 && scalar.value <= 90 { return Unicode.Scalar(scalar.value + 32)! }
        return scalar
    }

    private static func isLetter(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
    }

    private mutating func scanMarkup() -> NoteHTMLToken? {
        switch peek(1) {
        case "!":
            if matches("<!--", at: index) {
                let start = index + 4
                if let close = find("-->", from: start) {
                    defer { index = close + 3 }
                    return .comment(Self.string(input[start..<close]))
                }
                defer { index = input.count }
                return .comment(Self.string(input[min(start, input.count)..<input.count]))
            }
            if matches("<![cdata[", at: index, caseInsensitive: true) {
                let start = index + 9
                let close = find("]]>", from: start) ?? input.count
                defer { index = min(close + 3, input.count) }
                return .cdata(Self.string(input[min(start, close)..<close]))
            }
            return bogusComment(from: index + 2)
        case "?":
            return bogusComment(from: index + 2)
        case "/":
            if Self.isLetter(peek(2)) {
                index += 2
                let name = readName()
                skipToTagEnd()
                return .end(name)
            }
            if peek(2) == ">" {
                index += 3
                return .comment("")
            }
            return bogusComment(from: index + 2)
        default:
            guard Self.isLetter(peek(1)) else { return nil }
            index += 1
            let name = readName()
            let (attributes, selfClosing) = readAttributes()
            return .start(name, attributes, selfClosing: selfClosing)
        }
    }

    private mutating func bogusComment(from start: Int) -> NoteHTMLToken {
        let close = find(">", from: start) ?? input.count
        defer { index = min(close + 1, input.count) }
        return .comment(Self.string(input[min(start, close)..<close]))
    }

    private mutating func readName() -> String {
        var name = String.UnicodeScalarView()
        while index < input.count {
            let scalar = input[index]
            if NoteHTMLNode.isSpace(scalar) || scalar == "/" || scalar == ">" { break }
            name.append(Self.lowercased(scalar))
            index += 1
        }
        return String(name)
    }

    private mutating func skipToTagEnd() {
        var quote: Unicode.Scalar?
        while index < input.count {
            let scalar = input[index]
            index += 1
            if let open = quote {
                if scalar == open { quote = nil }
            } else if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == ">" {
                return
            }
        }
    }

    private mutating func skipSpaces() {
        while index < input.count, NoteHTMLNode.isSpace(input[index]) { index += 1 }
    }

    private mutating func readAttributes() -> ([String: String], Bool) {
        var attributes: [String: String] = [:]
        while index < input.count {
            let scalar = input[index]
            if NoteHTMLNode.isSpace(scalar) { index += 1; continue }
            if scalar == ">" { index += 1; return (attributes, false) }
            if scalar == "/" {
                if peek(1) == ">" { index += 2; return (attributes, true) }
                index += 1
                continue
            }
            var name = String.UnicodeScalarView([Self.lowercased(scalar)])
            index += 1
            while index < input.count {
                let next = input[index]
                if NoteHTMLNode.isSpace(next) || next == "/" || next == ">" || next == "=" { break }
                name.append(Self.lowercased(next))
                index += 1
            }
            skipSpaces()
            var value = ""
            if index < input.count, input[index] == "=" {
                index += 1
                skipSpaces()
                if index < input.count, input[index] == "\"" || input[index] == "'" {
                    let quote = input[index]
                    index += 1
                    let start = index
                    while index < input.count, input[index] != quote { index += 1 }
                    value = NoteHTMLEntities.decode(input[start..<index], attribute: true)
                    index = min(index + 1, input.count)
                } else {
                    let start = index
                    while index < input.count, !NoteHTMLNode.isSpace(input[index]), input[index] != ">" { index += 1 }
                    value = NoteHTMLEntities.decode(input[start..<index], attribute: true)
                }
            }
            let key = String(name)
            if attributes[key] == nil { attributes[key] = value }
        }
        return (attributes, false)
    }
}

package struct NoteHTMLTreeBuilder {
    package let root = NoteHTMLNode(element: "#document")
    private var stack: [NoteHTMLNode]

    package init() { stack = [root] }

    private var current: NoteHTMLNode { stack[stack.count - 1] }

    package static let void: Set<String> = ["area", "base", "basefont", "bgsound", "br", "col", "embed", "frame", "hr", "img",
                                    "input", "keygen", "link", "meta", "param", "source", "track", "wbr"]
    package static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl", "fieldset",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "li",
        "listing", "main", "menu", "nav", "ol", "p", "pre", "section", "summary", "table", "ul", "dd", "dt", "xmp", "search"
    ]
    package static let scopeBoundary: Set<String> = ["#document", "table", "td", "th", "caption", "button", "object", "marquee",
                                             "template", "applet"]
    package static let special: Set<String> = closesParagraph.union(["body", "html", "tbody", "thead", "tfoot", "tr", "td", "th",
                                                             "caption", "colgroup", "iframe", "img", "br", "frameset",
                                                             "select", "textarea", "#document", "#mso-marker"])
    package static let headings: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]

    package mutating func handle(_ token: NoteHTMLToken) {
        switch token {
        case .text(let value):
            guard !value.isEmpty else { return }
            current.append(NoteHTMLNode(text: value))
        case .comment(let value):
            comment(value)
        case .cdata(let value):
            if !value.isEmpty, stack.contains(where: { $0.name == "svg" || $0.name == "math" }) {
                current.append(NoteHTMLNode(text: value))
            }
        case .start(let name, let attributes, let selfClosing):
            start(name, attributes, selfClosing: selfClosing)
        case .end(let name):
            end(name)
        }
    }

    private mutating func comment(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[if"), trimmed.contains("supportLists") {
            let marker = NoteHTMLNode(element: NoteHTMLNode.markerName)
            current.append(marker)
            stack.append(marker)
        } else if trimmed == "[endif]", let index = stack.lastIndex(where: { $0.name == NoteHTMLNode.markerName }) {
            stack.removeSubrange(index...)
        }
    }

    private mutating func start(_ name: String, _ attributes: [String: String], selfClosing: Bool) {
        if name == "html" || name == "body" || name == "head" { return }
        closeImplied(before: name)
        let node = NoteHTMLNode(element: name, attributes: attributes)
        current.append(node)
        if !selfClosing && !Self.void.contains(name) { stack.append(node) }
    }

    private func openIndex(_ names: Set<String>, stoppingAt boundary: Set<String>) -> Int? {
        for index in stack.indices.reversed() {
            let name = stack[index].name
            if names.contains(name) { return index }
            if boundary.contains(name) { return nil }
        }
        return nil
    }

    private mutating func popThrough(_ index: Int) {
        stack.removeSubrange(max(1, index)...)
    }

    private mutating func closeImplied(before name: String) {
        if Self.closesParagraph.contains(name), let index = openIndex(["p"], stoppingAt: Self.scopeBoundary) {
            popThrough(index)
        }
        switch name {
        case "li":
            if let index = openIndex(["li"], stoppingAt: Self.scopeBoundary.union(["ul", "ol", "menu", "dir"])) { popThrough(index) }
        case "dt", "dd":
            if let index = openIndex(["dt", "dd"], stoppingAt: Self.scopeBoundary.union(["dl"])) { popThrough(index) }
        case "h1", "h2", "h3", "h4", "h5", "h6":
            if Self.headings.contains(current.name) { popThrough(stack.count - 1) }
        case "tr":
            if let index = openIndex(["tr"], stoppingAt: ["table", "#document"]) ?? openIndex(["td", "th"], stoppingAt: ["table", "#document"]) {
                popThrough(index)
            }
        case "td", "th":
            if let index = openIndex(["td", "th"], stoppingAt: ["tr", "table", "#document"]) { popThrough(index) }
        case "thead", "tbody", "tfoot":
            if let index = openIndex(["thead", "tbody", "tfoot", "tr", "td", "th", "caption", "colgroup"], stoppingAt: ["table", "#document"]) {
                popThrough(index)
            }
        case "a":
            if let index = openIndex(["a"], stoppingAt: Self.scopeBoundary) { popThrough(index) }
        case "option":
            if current.name == "option" { popThrough(stack.count - 1) }
        default:
            break
        }
    }

    private mutating func end(_ name: String) {
        if name == "html" || name == "body" || name == "head" { return }
        if name == "br" {
            current.append(NoteHTMLNode(element: "br"))
            return
        }
        let isSpecial = Self.special.contains(name)
        let boundary = isSpecial ? Self.scopeBoundary.subtracting([name]) : Self.scopeBoundary
        for index in stack.indices.reversed() where index > 0 {
            let open = stack[index].name
            if open == name || (Self.headings.contains(name) && Self.headings.contains(open)) {
                popThrough(index)
                return
            }
            if boundary.contains(open) { return }
            if !isSpecial && Self.special.contains(open) { return }
        }
    }
}
