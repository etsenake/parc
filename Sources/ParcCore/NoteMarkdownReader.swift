import Foundation

struct NoteMDAttributes: Equatable {
    var flags: Set<String> = []
    var values: [String: String] = [:]

    var isEmpty: Bool { flags.isEmpty && values.isEmpty }

    static let kindNames: [String: NoteBlockKind] = [
        "paragraph": .paragraph, "image": .image, "video": .video, "audio": .audio, "file": .file,
        "embed": .embed, "bookmark": .bookmark, "pdf": .pdf, "breadcrumb": .breadcrumb,
    ]

    var kind: NoteBlockKind? {
        for (name, kind) in Self.kindNames where flags.contains(name) { return kind }
        return nil
    }

    var color: NoteColorStyle? { values["color"].flatMap(NoteMDColor.style) }

    static func parse(_ comment: String) -> NoteMDAttributes? {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->"), trimmed.count >= 7 else { return nil }
        let inner = Array(trimmed.dropFirst(4).dropLast(3).utf8)
        var index = 0
        while index < inner.count, NoteMDByte.isWhitespace(inner[index]) { index += 1 }
        guard NoteMDHTML.matches(inner, at: index, upTo: inner.count, ascii: "parc") else { return nil }
        index += 4
        guard index >= inner.count || NoteMDByte.isWhitespace(inner[index]) else { return nil }
        var result = NoteMDAttributes()
        while index < inner.count {
            while index < inner.count, NoteMDByte.isWhitespace(inner[index]) { index += 1 }
            guard index < inner.count else { break }
            let nameStart = index
            while index < inner.count, NoteMDByte.isAlphanumeric(inner[index]) || inner[index] == 45 || inner[index] == 95 { index += 1 }
            guard index > nameStart else { return nil }
            let name = NoteMDByte.string(inner[nameStart..<index]).lowercased()
            if index < inner.count, inner[index] == 61 {
                index += 1
                guard index < inner.count, inner[index] == 34 else { return nil }
                let valueStart = index + 1
                index = valueStart
                while index < inner.count, inner[index] != 34 { index += 1 }
                guard index < inner.count else { return nil }
                result.values[name] = NoteMDText.unescapeEntities(inner[valueStart..<index])
                index += 1
            } else {
                result.flags.insert(name)
            }
        }
        return result
    }
}

enum NoteMDSynced {
    static let flag = "synced"
    static let sourceKey = "from"
    static let closer = "<!-- parc /synced -->"

    static func isCloser(_ node: NoteMDBlock) -> Bool {
        guard node.kind == .html else { return false }
        let inner = NoteMDByte.string(NoteMDText.trimmed(node.content[...]))
        guard inner.hasPrefix("<!--"), inner.hasSuffix("-->") else { return false }
        let words = inner.dropFirst(4).dropLast(3).split(whereSeparator: \.isWhitespace)
        return words.count == 2 && words[0].lowercased() == "parc" && words[1].lowercased() == "/" + flag
    }

    static func isOpener(_ node: NoteMDBlock) -> Bool {
        node.kind == .html && NoteMDAttributes.parse(NoteMDByte.string(node.content))?.flags.contains(flag) == true
    }

    static func matchingClose(_ nodes: ArraySlice<NoteMDBlock>, after index: Int) -> Int? {
        var depth = 0
        var probe = index + 1
        while probe < nodes.endIndex {
            let node = nodes[probe]
            if isCloser(node) {
                if depth == 0 { return probe }
                depth -= 1
            } else if isOpener(node) {
                depth += 1
            }
            probe += 1
        }
        return nil
    }
}

enum NoteMDColor {
    static func style(_ value: String) -> NoteColorStyle? {
        let lowered = value.lowercased()
        for suffix in ["_background", "-background", "_bg", "-bg"] where lowered.hasSuffix(suffix) {
            return NoteColor(rawValue: String(lowered.dropLast(suffix.count))).map(NoteColorStyle.background)
        }
        return NoteColor(rawValue: lowered).map(NoteColorStyle.text)
    }

    static func name(_ style: NoteColorStyle) -> String {
        switch style {
        case .text(let color): return color.rawValue
        case .background(let color): return color.rawValue + "_background"
        }
    }
}

enum NoteMDMedia {
    static func carriesCredit(_ kind: NoteBlockKind) -> Bool {
        kind.isMedia || kind == .embed
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "heif", "tif", "tiff", "bmp", "ico", "avif", "apng", "jfif"]
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "ogv", "mkv", "avi", "mpg", "mpeg", "3gp"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "oga", "opus", "aif", "aiff", "caf", "weba", "mid", "midi"]
    static let embedHosts: Set<String> = [
        "youtube.com", "youtu.be", "vimeo.com", "twitter.com", "x.com", "figma.com", "codepen.io", "loom.com",
        "open.spotify.com", "soundcloud.com", "gist.github.com", "codesandbox.io", "miro.com", "maps.google.com",
    ]

    static func writesFraming(_ kind: NoteBlockKind) -> Bool {
        kind == .image || kind == .video || kind == .audio || kind == .file || kind == .embed
    }

    static func pathExtension(_ source: String) -> String {
        var path = Substring(source)
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = path[..<cut] }
        guard let slash = path.lastIndex(of: "/").map({ path.index(after: $0) }) ?? Optional(path.startIndex) else { return "" }
        let name = path[slash...]
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    static func host(_ source: String) -> String? {
        guard let components = URLComponents(string: source), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", var host = components.host?.lowercased() else { return nil }
        for prefix in ["www.", "m.", "player."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        return host
    }

    static func inferredKind(_ source: String) -> NoteBlockKind {
        if let host = host(source), embedHosts.contains(host) || (host == "google.com" && source.contains("/maps")) { return .embed }
        let ext = pathExtension(source)
        if ext.isEmpty || imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        return .file
    }
}

enum NoteMDLinks {
    static func isRelativeMarkdown(_ destination: String) -> Bool {
        guard !destination.isEmpty, !destination.hasPrefix("#"), !destination.hasPrefix("//") else { return false }
        if let colon = destination.firstIndex(of: ":") {
            let scheme = destination[..<colon]
            if let first = scheme.first, first.isLetter, scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+.-".contains($0) }) { return false }
        }
        let ext = NoteMDMedia.pathExtension(destination)
        return NoteFileKind.markdownExtensions.contains(ext)
    }

    static func stem(_ destination: String) -> String {
        var path = Substring(destination)
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = path[..<cut] }
        let name = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? String(path)
        let decoded = name.removingPercentEncoding ?? name
        guard let dot = decoded.lastIndex(of: "."), dot != decoded.startIndex else { return decoded }
        return String(decoded[..<dot])
    }
}

struct NoteMDReader {
    let references: [String: NoteMDLinkReference]
    let footnotes: Set<String>
    var customEmoji: Set<String> = []

    private struct Event {
        enum Content {
            case text(String)
            case atom(NoteAtom)
            case tag(NoteMDTag, String)
        }
        var content: Content
        var marks: NoteMarks
    }

    private enum TagMeaning {
        case none, bold, italic, strike, underline, code, color(NoteColorStyle), link(String)
        case date(NoteDateMention), mention(String), equation(String)
    }

    static let maximumInlineDepth = 96

    private static let pairableTags: Set<String> = ["b", "strong", "i", "em", "s", "del", "strike", "u", "ins", "code", "mark", "span", "a", "time"]

    func sequence(_ nodes: ArraySlice<NoteMDBlock>, documentEdges: Bool, trailingBlank: Int) -> [NoteBlock] {
        var result: [NoteBlock] = []
        var lastNumber: Int?
        var index = nodes.startIndex
        func appendEmpties(_ count: Int) {
            guard count > 0 else { return }
            for _ in 0..<count { result.append(NoteBlock.paragraph()) }
            lastNumber = nil
        }
        while index < nodes.endIndex {
            let node = nodes[index]
            let isFirst = index == nodes.startIndex
            if node.kind == .html, let attributes = NoteMDAttributes.parse(NoteMDByte.string(node.content)) {
                if attributes.flags.contains(NoteMDSynced.flag) {
                    appendEmpties(isFirst && documentEdges ? node.blankBefore : max(0, node.blankBefore - 1))
                    lastNumber = nil
                    guard let close = NoteMDSynced.matchingClose(nodes, after: index) else {
                        result.append(NoteBlock(.html, text: NoteText(NoteMDByte.string(node.content))))
                        index += 1
                        continue
                    }
                    result.append(synced(attributes, children: nodes[(index + 1)..<close], trailing: max(0, nodes[close].blankBefore - 1)))
                    index = close + 1
                    continue
                }
                if let kind = attributes.kind, kind == .paragraph || kind == .breadcrumb {
                    appendEmpties(isFirst && documentEdges ? node.blankBefore : max(0, node.blankBefore - 1))
                    var block = kind == .paragraph ? NoteBlock.paragraph() : NoteBlock(.breadcrumb)
                    apply(attributes, to: &block)
                    result.append(block)
                    lastNumber = nil
                    index += 1
                    continue
                }
                if !isFirst, node.blankBefore == 0, let last = result.last, last.kind != .html, last.kind != .raw {
                    apply(attributes, to: &result[result.count - 1])
                    index += 1
                    continue
                }
            }
            appendEmpties(isFirst && documentEdges ? node.blankBefore : max(0, node.blankBefore - 1))
            switch node.kind {
            case .html:
                let trimmed = NoteMDByte.string(NoteMDText.trimmed(node.content[...]))
                if trimmed == "<!-- -->", index > nodes.startIndex, index + 1 < nodes.endIndex,
                   nodes[index - 1].kind == .list, nodes[index - 1].ordered, nodes[index + 1].kind == .list, nodes[index + 1].ordered {
                    index += 1
                    continue
                }
                if trimmed.lowercased() == "<!-- toc -->" {
                    result.append(NoteBlock(.tableOfContents))
                    lastNumber = nil
                    index += 1
                    continue
                }
                if let opener = Self.details(node.content) {
                    if opener.closed {
                        result.append(toggle(opener, children: [][...], trailing: 0))
                        lastNumber = nil
                        index += 1
                        continue
                    }
                    if let close = matchingDetailsClose(nodes, after: index) {
                        let children = nodes[(index + 1)..<close]
                        result.append(toggle(opener, children: children, trailing: max(0, nodes[close].blankBefore - 1)))
                        lastNumber = nil
                        index = close + 1
                        continue
                    }
                }
                result.append(NoteBlock(.html, text: NoteText(NoteMDByte.string(node.content))))
                lastNumber = nil
            case .list:
                for (offset, item) in node.children.enumerated() {
                    var block = listItem(item, in: node)
                    if node.ordered {
                        let number = node.start + offset
                        let expected = lastNumber.map { $0 + 1 } ?? 1
                        if offset == 0, number != expected { block.props.listStart = number }
                        lastNumber = number
                    }
                    result.append(block)
                }
                if !node.ordered { lastNumber = nil }
            case .directive where node.directiveName == NoteMDDirective.indent:
                var children = sequence(node.children[...], documentEdges: false, trailingBlank: node.trailingBlank)
                if result.last?.kind.isListItem == true {
                    while let tail = children.last, NoteMDWriter.isBareEmptyParagraph(tail) { children.removeLast() }
                }
                if let last = result.indices.last, result[last].acceptsChildren, !result[last].kind.isColumnStructure {
                    result[last].children += children
                } else if !children.isEmpty {
                    result.append(NoteBlock(.paragraph, children: children))
                    lastNumber = nil
                }
            default:
                var converted = block(node)
                if converted.kind == .code, converted.props.fence == "    ", !NoteMDWriter.writesIndentedCode(converted, afterList: Self.followsList(result)) {
                    converted.props.fence = nil
                }
                result.append(converted)
                lastNumber = nil
            }
            index += 1
        }
        appendEmpties(documentEdges ? trailingBlank : max(0, trailingBlank - 1))
        return result
    }

    private static func followsList(_ blocks: [NoteBlock]) -> Bool {
        guard let previous = blocks.last(where: { !NoteMDWriter.isBareEmptyParagraph($0) }) else { return false }
        return previous.kind.isListItem || (previous.kind == .raw && previous.text.string.hasPrefix("[^"))
    }

    private func block(_ node: NoteMDBlock) -> NoteBlock {
        switch node.kind {
        case .paragraph:
            return paragraph(node.content)
        case .heading:
            let (text, attributes) = inline(node.content)
            var block = NoteBlock.heading(node.level, text)
            if node.setext != 0 { block.props.fence = node.setext == 61 ? "=" : "-" }
            if let attributes { apply(attributes, to: &block) }
            return block
        case .thematicBreak:
            var block = NoteBlock(.divider)
            if node.literal != "---" { block.props.fence = node.literal }
            return block
        case .code:
            return code(node)
        case .math:
            return NoteBlock(.equation, text: NoteText(NoteMDByte.string(node.content)))
        case .quote:
            return quote(node)
        case .table:
            return table(node)
        case .directive:
            return directive(node)
        case .footnote:
            let text = node.rawLines.map { NoteMDByte.string($0) }.joined(separator: "\n")
            return NoteBlock(.raw, text: NoteText(text))
        case .definitions:
            return NoteBlock(.raw, text: NoteText(NoteMDByte.string(node.content)))
        case .html:
            return NoteBlock(.html, text: NoteText(NoteMDByte.string(node.content)))
        case .item, .list, .document:
            return NoteBlock(.paragraph)
        }
    }

    private func code(_ node: NoteMDBlock) -> NoteBlock {
        let text = NoteText(NoteMDByte.string(node.content))
        guard node.fenced else {
            var block = NoteBlock(.code, text: text)
            block.props.fence = "    "
            return block
        }
        let fence = String(repeating: Character(UnicodeScalar(node.fenceChar)), count: node.fenceLength)
        let info = node.info.trimmingCharacters(in: .whitespaces)
        let language: String, extra: String?
        if let space = info.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            language = String(info[..<space])
            let rest = info[space...].trimmingCharacters(in: .whitespaces)
            extra = rest.isEmpty ? nil : rest
        } else {
            language = info
            extra = nil
        }
        if language == "math", extra == nil {
            var block = NoteBlock(.equation, text: text)
            let canonical = NoteMDWriter.equationNeedsFence(text.string) && fence == NoteMDWriter.fence(for: text.string, preferred: nil, info: "math")
            block.props.fence = canonical ? nil : fence
            return block
        }
        var block = NoteBlock(.code, text: text)
        block.props.language = language
        block.props.info = extra
        if fence != NoteMDWriter.fence(for: text.string, preferred: nil, info: info) { block.props.fence = fence }
        return block
    }

    func paragraph(_ content: [UInt8]) -> NoteBlock {
        var tree = NoteMDInlineParser.parse(content, references: references, footnotes: footnotes, customEmoji: customEmoji)
        var children = tree.children(of: 0)
        let attributes = Self.stripTrailingAttributes(&tree, &children)
        let kindHint = attributes?.kind
        if children.count == 1 {
            let node = tree.nodes[children[0]]
            if node.kind == .image, kindHint == nil || (kindHint != .paragraph && kindHint != .bookmark && kindHint != .breadcrumb) {
                var block = NoteBlock(kindHint ?? NoteMDMedia.inferredKind(node.destination))
                block.props.source = node.destination
                let alt = tree.plainText(of: children[0])
                block.props.alt = alt.isEmpty ? nil : alt
                if let title = node.title { block.props.caption = caption(title) }
                if let attributes { apply(attributes, to: &block) }
                return block
            }
            if node.kind == .link, kindHint == .pdf {
                var block = NoteBlock(.pdf)
                block.props.source = node.destination
                let alt = tree.plainText(of: children[0])
                block.props.alt = alt.isEmpty ? nil : alt
                if let title = node.title { block.props.caption = caption(title) }
                if let attributes { apply(attributes, to: &block) }
                return block
            }
            if node.kind == .link, kindHint == .bookmark {
                var block = NoteBlock(.bookmark)
                block.props.source = node.destination
                var bookmark = NoteBookmark()
                let title = tree.plainText(of: children[0])
                bookmark.title = title.isEmpty ? nil : title
                block.props.bookmark = bookmark
                if let title = node.title { block.props.caption = caption(title) }
                if let attributes { apply(attributes, to: &block) }
                return block
            }
            if node.kind == .autolink, kindHint == .bookmark {
                var block = NoteBlock(.bookmark)
                block.props.source = node.destination
                block.props.bookmark = NoteBookmark()
                if let attributes { apply(attributes, to: &block) }
                return block
            }
            if node.kind == .link, kindHint == nil, node.title == nil, NoteMDLinks.isRelativeMarkdown(node.destination) {
                var block = NoteBlock(.pageLink, text: text(tree, children: tree.children(of: children[0])))
                block.props.target = node.destination
                if let attributes { apply(attributes, to: &block) }
                return block
            }
        }
        var block = NoteBlock.paragraph(text(tree, children: children))
        if let attributes { apply(attributes, to: &block) }
        return block
    }

    func caption(_ title: String) -> NoteText {
        let tree = NoteMDInlineParser.parseVerbatim(Array(title.utf8), references: references, footnotes: footnotes, customEmoji: customEmoji)
        return text(tree, children: tree.children(of: 0))
    }

    private func listItem(_ node: NoteMDBlock, in list: NoteMDBlock) -> NoteBlock {
        var children = node.children[...]
        var text = NoteText()
        var attributes: NoteMDAttributes?
        var task: Bool?
        if let first = children.first {
            if first.kind == .html, let parsed = NoteMDAttributes.parse(NoteMDByte.string(first.content)), parsed.kind == nil {
                attributes = parsed
                children = children.dropFirst()
            } else if first.kind == .paragraph {
                var content = first.content
                if content.count >= 3, content[0] == 91, content[2] == 93, content[1] == 32 || content[1] == 120 || content[1] == 88,
                   content.count == 3 || NoteMDByte.isWhitespace(content[3]) {
                    task = content[1] != 32
                    content.removeFirst(min(4, content.count))
                }
                (text, attributes) = inline(content)
                children = children.dropFirst()
            }
        }
        var block: NoteBlock
        if let checked = task {
            block = NoteBlock(.todo, text: text)
            block.props.checked = checked
            if list.ordered { block.props.orderedDelimiter = String(UnicodeScalar(list.marker)) }
        } else {
            block = NoteBlock(list.ordered ? .numberedItem : .bulletedItem, text: text)
            if list.ordered, list.marker == 41 { block.props.orderedDelimiter = ")" }
        }
        if !list.ordered, list.marker != 45 { block.props.bulletMarker = String(UnicodeScalar(list.marker)) }
        block.props.looseList = list.loose
        block.children = sequence(children, documentEdges: false, trailingBlank: 0)
        if let attributes { apply(attributes, to: &block) }
        return block
    }

    private static let githubAlerts: Set<String> = ["TIP", "IMPORTANT", "WARNING", "CAUTION"]

    static let noteAlert = "NOTE"
    static let keepsAlertFlag = "alert"

    static func calloutUsesBody(_ alert: String?) -> Bool {
        guard let alert else { return true }
        return githubAlerts.contains(alert) || alert == noteAlert
    }

    private func quote(_ node: NoteMDBlock) -> NoteBlock {
        var children = node.children[...]
        var text = NoteText()
        var attributes: NoteMDAttributes?
        var extra: [NoteBlock] = []
        var block = NoteBlock(.quote)
        if let first = children.first, first.kind == .paragraph, let marker = Self.calloutMarker(first.content) {
            block.kind = .callout
            block.props.alert = marker.type
            if let fold = marker.fold {
                block.props.toggleable = true
                block.props.expanded = fold == "+"
            }
            children = children.dropFirst()
            let body = Self.calloutUsesBody(block.props.alert)
            let title = NoteMDText.trimmed(marker.title[...])
            if !title.isEmpty {
                (text, attributes) = inline(Array(title))
                if !marker.rest.isEmpty { extra.append(paragraph(marker.rest)) }
            } else if !marker.rest.isEmpty {
                if body { (text, attributes) = inline(marker.rest) } else { extra.append(paragraph(marker.rest)) }
            } else if let next = children.first {
                if next.kind == .html, let parsed = NoteMDAttributes.parse(NoteMDByte.string(next.content)), parsed.kind == nil {
                    attributes = parsed
                    children = children.dropFirst()
                } else if body, next.kind == .paragraph {
                    (text, attributes) = inline(next.content)
                    children = children.dropFirst()
                }
            }
        } else if let first = children.first {
            if first.kind == .html, let parsed = NoteMDAttributes.parse(NoteMDByte.string(first.content)), parsed.kind == nil {
                attributes = parsed
                children = children.dropFirst()
            } else if first.kind == .paragraph {
                (text, attributes) = inline(first.content)
                children = children.dropFirst()
            }
        }
        block.text = text
        block.children = extra + sequence(children, documentEdges: false, trailingBlank: node.trailingBlank)
        if block.props.alert == Self.noteAlert, let attributes, !attributes.flags.contains(Self.keepsAlertFlag) { block.props.alert = nil }
        if let attributes { apply(attributes, to: &block) }
        return block
    }

    private struct CalloutMarker {
        var type: String
        var fold: Character?
        var title: [UInt8]
        var rest: [UInt8]
    }

    private static func calloutMarker(_ content: [UInt8]) -> CalloutMarker? {
        guard content.count >= 4, content[0] == 91, content[1] == 33 else { return nil }
        var index = 2
        guard index < content.count, NoteMDByte.isLetter(content[index]) else { return nil }
        while index < content.count, NoteMDByte.isAlphanumeric(content[index]) || content[index] == 45 || content[index] == 95 { index += 1 }
        guard index < content.count, content[index] == 93 else { return nil }
        let type = NoteMDByte.string(content[2..<index])
        index += 1
        var fold: Character?
        if index < content.count, content[index] == 43 || content[index] == 45 {
            fold = Character(UnicodeScalar(content[index]))
            index += 1
        }
        guard index >= content.count || NoteMDByte.isWhitespace(content[index]) else { return nil }
        var lineEnd = index
        while lineEnd < content.count, content[lineEnd] != NoteMDByte.newline { lineEnd += 1 }
        let title = Array(content[index..<lineEnd])
        var rest = lineEnd < content.count ? Array(content[(lineEnd + 1)...]) : []
        while let last = rest.last, NoteMDByte.isWhitespace(last) { rest.removeLast() }
        return CalloutMarker(type: type, fold: fold, title: title, rest: rest)
    }

    struct DetailsOpener {
        var open: Bool
        var level: Int?
        var summary: [UInt8]
        var closed: Bool
    }

    static func details(_ content: [UInt8]) -> DetailsOpener? {
        var index = 0
        let end = content.count
        func skip() { while index < end, NoteMDByte.isWhitespace(content[index]) { index += 1 } }
        skip()
        guard let (tag, tagEnd) = NoteMDHTML.tag(content, from: index, upTo: end), tag.name == "details", !tag.closing, !tag.selfClosing else { return nil }
        guard tag.attributes.allSatisfy({ $0.0 == "open" }) else { return nil }
        var opener = DetailsOpener(open: tag.attribute("open") != nil, level: nil, summary: [], closed: false)
        index = tagEnd
        skip()
        if NoteMDHTML.matches(content, at: index, upTo: end, ascii: "<summary>", caseInsensitive: true) {
            let summaryStart = index + 9
            var probe = summaryStart
            var found = -1
            while probe + 10 <= end {
                if NoteMDHTML.matches(content, at: probe, upTo: end, ascii: "</summary>", caseInsensitive: true) { found = probe; break }
                probe += 1
            }
            guard found >= 0 else { return nil }
            var summary = Array(content[summaryStart..<found])
            let trimmed = Array(NoteMDText.trimmed(summary[...]))
            if trimmed.count >= 9, trimmed[0] == 60, NoteMDByte.lowered(trimmed[1]) == 104, (49...54).contains(trimmed[2]), trimmed[3] == 62 {
                let level = Int(trimmed[2] - 48)
                let closing = Array("</h\(level)>".utf8)
                let tail = Array(trimmed.suffix(5)).map(NoteMDByte.lowered)
                if tail == closing {
                    opener.level = level
                    summary = Array(trimmed[4..<(trimmed.count - 5)])
                }
            }
            opener.summary = summary
            index = found + 10
            skip()
        }
        if NoteMDHTML.matches(content, at: index, upTo: end, ascii: "</details>", caseInsensitive: true) {
            opener.closed = true
            index += 10
            skip()
        }
        return index >= end ? opener : nil
    }

    static func isDetailsClose(_ node: NoteMDBlock) -> Bool {
        node.kind == .html && NoteMDByte.string(NoteMDText.trimmed(node.content[...])).lowercased() == "</details>"
    }

    func matchingDetailsClose(_ nodes: ArraySlice<NoteMDBlock>, after index: Int) -> Int? {
        var depth = 0
        var probe = index + 1
        while probe < nodes.endIndex {
            let node = nodes[probe]
            if Self.isDetailsClose(node) {
                if depth == 0 { return probe }
                depth -= 1
            } else if node.kind == .html, let opener = Self.details(node.content), !opener.closed {
                depth += 1
            }
            probe += 1
        }
        return nil
    }

    private func toggle(_ opener: DetailsOpener, children: ArraySlice<NoteMDBlock>, trailing: Int) -> NoteBlock {
        let (text, attributes) = inline(opener.summary)
        if let attributes, opener.level == nil, attributes.flags.contains(NoteMDButtonFormat.flag) {
            return button(opener, label: text, attributes: attributes, children: children, trailing: trailing)
        }
        var block: NoteBlock
        if let level = opener.level {
            block = NoteBlock.heading(level, text)
            block.props.toggleable = true
        } else {
            block = NoteBlock(.toggle, text: text)
        }
        block.props.expanded = opener.open
        if children.isEmpty {
            block.children = Array(repeating: NoteBlock.paragraph(), count: trailing)
        } else {
            block.children = sequence(children, documentEdges: false, trailingBlank: trailing + 1)
        }
        if let attributes { apply(attributes, to: &block) }
        return block
    }

    private func synced(_ attributes: NoteMDAttributes, children: ArraySlice<NoteMDBlock>, trailing: Int) -> NoteBlock {
        var block = NoteBlock(.synced)
        if let anchor = attributes.values["id"], NoteAnchor.isValid(anchor) { block.props.anchor = anchor }
        if let source = attributes.values[NoteMDSynced.sourceKey], !source.isEmpty { block.props.target = source }
        if children.isEmpty {
            block.children = Array(repeating: NoteBlock.paragraph(), count: trailing)
        } else {
            block.children = sequence(children, documentEdges: false, trailingBlank: trailing + 1)
        }
        return block
    }

    private func table(_ node: NoteMDBlock) -> NoteBlock {
        let columns = node.alignments.count
        let rows = node.rows.map { row -> [NoteText] in
            var cells = row.prefix(columns).map { cellText($0) }
            while cells.count < columns { cells.append(NoteText()) }
            return cells
        }
        var table = NoteTable(rows: rows)
        table.alignments = node.alignments
        table.normalize()
        var block = NoteBlock(.table)
        block.props.table = table
        return block
    }

    private func directive(_ node: NoteMDBlock) -> NoteBlock {
        if node.directiveName == NoteMDDirective.indent {
            return NoteBlock(.paragraph, children: sequence(node.children[...], documentEdges: false, trailingBlank: node.trailingBlank))
        }
        if node.directiveName == "column" {
            var columns = NoteBlock(.columns)
            columns.children = [column(node)]
            return columns
        }
        var block = NoteBlock(.columns)
        var loose: [NoteMDBlock] = []
        func flushLoose() {
            guard !loose.isEmpty else { return }
            block.children.append(NoteBlock(.column, children: sequence(loose[...], documentEdges: false, trailingBlank: 0)))
            loose = []
        }
        for child in node.children {
            if child.kind == .directive, child.directiveName == "column" {
                flushLoose()
                block.children.append(column(child))
            } else {
                loose.append(child)
            }
        }
        flushLoose()
        return block
    }

    private func column(_ node: NoteMDBlock) -> NoteBlock {
        var block = NoteBlock(.column, children: sequence(node.children[...], documentEdges: false, trailingBlank: node.trailingBlank))
        block.props.width = node.directiveWidth
        return block
    }

    func apply(_ attributes: NoteMDAttributes, to block: inout NoteBlock) {
        if let color = attributes.color { block.color = color }
        let values = attributes.values
        if let icon = values["icon"] { block.props.icon = icon }
        if let width = values["width"], let number = Double(width) { block.props.width = number }
        if let height = values["height"], let number = Double(height) { block.props.height = number }
        if let align = values["align"], let alignment = NoteAlignment(rawValue: align.lowercased()) { block.props.alignment = alignment }
        if NoteMDMedia.writesFraming(block.kind) {
            if let value = values["crop"], let crop = NoteImageCrop(attribute: value) { block.props.crop = crop }
            if let value = values["mask"], let mask = NoteImageMask(rawValue: value.lowercased()) { block.props.mask = mask }
        }
        if let caption = values["caption"] { block.props.caption = self.caption(caption) }
        if let anchor = values["id"], NoteAnchor.isValid(anchor) { block.props.anchor = anchor }
        if attributes.flags.contains("wrap") { block.props.wrap = true }
        if block.kind == .code, let view = values["view"], let mode = NoteDiagramMode(rawValue: view.lowercased()) {
            block.props.diagramMode = mode == .preview ? nil : mode
        }
        if NoteMDMedia.carriesCredit(block.kind), let credit = NoteMediaCredit(name: values["credit"], link: values["credit-url"]) {
            block.props.credit = credit
        }
        if block.kind == .bookmark {
            var bookmark = block.props.bookmark ?? NoteBookmark()
            if let value = values["summary"] { bookmark.summary = value }
            if let value = values["site"] { bookmark.siteName = value }
            if let value = values["favicon"] { bookmark.iconURL = value }
            if let value = values["thumbnail"] { bookmark.imageURL = value }
            block.props.bookmark = bookmark
        }
        if block.kind == .table, var table = block.props.table {
            if attributes.flags.contains("no-header-row") { table.headerRow = false }
            if attributes.flags.contains("header-column") { table.headerColumn = true }
            if let widths = values["widths"] {
                let parts = widths.split(separator: ",", omittingEmptySubsequences: false)
                table.columnWidths = parts.map { Double($0.trimmingCharacters(in: .whitespaces)) }
                table.normalize()
            }
            if let merge = values["merge"] { table.applyMergeAttribute(merge) }
            if let colors = values["colors"] { table.applyColorsAttribute(colors) }
            block.props.table = table
        }
        if block.kind == .code, block.props.fence == "    ", !NoteMDWriter.writesIndentedCode(block, afterList: false) { block.props.fence = nil }
    }

    func inline(_ content: [UInt8]) -> (NoteText, NoteMDAttributes?) {
        var tree = NoteMDInlineParser.parse(content, references: references, footnotes: footnotes, customEmoji: customEmoji)
        var children = tree.children(of: 0)
        let attributes = Self.stripTrailingAttributes(&tree, &children)
        return (text(tree, children: children), attributes)
    }

    func cellText(_ content: [UInt8]) -> NoteText {
        let tree = NoteMDInlineParser.parse(content, references: references, footnotes: footnotes, customEmoji: customEmoji)
        return text(tree, children: tree.children(of: 0))
    }

    private static func stripTrailingAttributes(_ tree: inout NoteMDInlineTree, _ children: inout [Int]) -> NoteMDAttributes? {
        guard let last = children.last, tree.nodes[last].kind == .html,
              let attributes = NoteMDAttributes.parse(tree.nodes[last].literal) else { return nil }
        children.removeLast()
        if let previous = children.last, tree.nodes[previous].kind == .text, !tree.nodes[previous].decoded {
            var literal = tree.nodes[previous].literal
            while let character = literal.last, character == " " || character == "\t" { literal.removeLast() }
            if literal.isEmpty { children.removeLast() } else { tree.nodes[previous].literal = literal }
        }
        return attributes
    }

    func text(_ tree: NoteMDInlineTree, children: [Int]) -> NoteText {
        var events: [Event] = []
        for child in children { flatten(tree, child, marks: .plain, depth: 0, into: &events) }
        return build(events)
    }

    private func flatten(_ tree: NoteMDInlineTree, _ index: Int, marks: NoteMarks, depth: Int, into events: inout [Event]) {
        let node = tree.nodes[index]
        if depth > Self.maximumInlineDepth, node.first != -1 {
            events.append(Event(content: .atom(.raw(tree.source(of: index))), marks: marks))
            return
        }
        func recurse(_ marks: NoteMarks) {
            for child in tree.children(of: index) { flatten(tree, child, marks: marks, depth: depth + 1, into: &events) }
        }
        switch node.kind {
        case .root:
            recurse(marks)
        case .text:
            if !node.literal.isEmpty { events.append(Event(content: .text(node.literal), marks: marks)) }
        case .softBreak:
            events.append(Event(content: .text("\u{2028}"), marks: marks))
        case .hardBreak:
            events.append(Event(content: .text("\n"), marks: marks))
        case .code:
            var value = marks
            value.code = true
            if !node.literal.isEmpty { events.append(Event(content: .text(node.literal), marks: value)) }
        case .emphasis:
            var value = marks
            value.italic = true
            recurse(value)
        case .strong:
            var value = marks
            value.bold = true
            recurse(value)
        case .strike:
            var value = marks
            value.strikethrough = true
            recurse(value)
        case .highlight:
            var value = marks
            value.color = .background(.yellow)
            recurse(value)
        case .link:
            let kids = tree.children(of: index)
            if node.title != nil || marks.link != nil {
                events.append(Event(content: .atom(.raw(tree.source(of: index))), marks: marks))
            } else if NoteMDLinks.isRelativeMarkdown(node.destination), !kids.isEmpty, kids.allSatisfy({ tree.nodes[$0].kind == .text }),
                      kids.map({ tree.nodes[$0].literal }).joined() == NoteMDLinks.stem(node.destination) {
                events.append(Event(content: .atom(.page(target: node.destination, title: NoteMDLinks.stem(node.destination))), marks: marks))
            } else {
                var value = marks
                value.link = node.destination
                recurse(value)
            }
        case .autolink:
            var value = marks
            if value.link == nil { value.link = node.destination }
            events.append(Event(content: .text(node.literal), marks: value))
        case .image, .rawSource:
            events.append(Event(content: .atom(.raw(tree.source(of: index))), marks: marks))
        case .math:
            events.append(Event(content: .atom(.equation(node.literal)), marks: marks))
        case .customEmoji:
            events.append(Event(content: .atom(.customEmoji(node.literal)), marks: marks))
        case .wiki:
            events.append(Event(content: .atom(.page(target: node.destination, title: node.title ?? node.destination)), marks: marks))
        case .html:
            if let (tag, tagEnd) = NoteMDHTML.tag(Array(node.literal.utf8), from: 0, upTo: node.literal.utf8.count),
               tagEnd == node.literal.utf8.count, tag.name == "br" || Self.pairableTags.contains(tag.name) {
                events.append(Event(content: .tag(tag, node.literal), marks: marks))
            } else {
                events.append(Event(content: .atom(.raw(node.literal)), marks: marks))
            }
        }
    }

    private func meaning(of tag: NoteMDTag) -> TagMeaning {
        switch tag.name {
        case "b", "strong": return tag.attributes.isEmpty ? .bold : .none
        case "i", "em": return tag.attributes.isEmpty ? .italic : .none
        case "s", "del", "strike": return tag.attributes.isEmpty ? .strike : .none
        case "u", "ins": return tag.attributes.isEmpty ? .underline : .none
        case "code": return tag.attributes.isEmpty ? .code : .none
        case "mark":
            if tag.attributes.isEmpty { return .color(.background(.yellow)) }
            if tag.attributes.count == 1, case .some(.some(let value)) = tag.attribute("data-color"), let style = NoteMDColor.style(value) { return .color(style) }
            return .none
        case "span":
            guard tag.attributes.count == 1 else { return .none }
            if case .some(.some(let value)) = tag.attribute("data-color"), let style = NoteMDColor.style(value) { return .color(style) }
            if case .some(.some(let value)) = tag.attribute("data-equation") { return .equation(value) }
            return .none
        case "a":
            guard case .some(.some(let href)) = tag.attribute("href") else { return .none }
            if tag.attributes.count == 2, tag.attribute("data-mention") != nil { return .mention(href) }
            return tag.attributes.count == 1 ? .link(href) : .none
        case "time":
            guard let mention = NoteDateMarkup.mention(from: tag.attributes) else { return .none }
            return .date(mention)
        default:
            return .none
        }
    }

    private func build(_ events: [Event]) -> NoteText {
        var partner = Array(repeating: -1, count: events.count)
        var stack: [(String, Int)] = []
        for index in events.indices {
            guard case .tag(let tag, _) = events[index].content, tag.name != "br", !tag.selfClosing else { continue }
            if !tag.closing {
                stack.append((tag.name, index))
            } else if let position = stack.lastIndex(where: { $0.0 == tag.name }) {
                partner[stack[position].1] = index
                partner[index] = stack[position].1
                stack.removeSubrange(position...)
            }
        }
        var meanings: [Int: TagMeaning] = [:]
        var pieces: [(String, NoteMarks)] = []
        var bold = 0, italic = 0, strike = 0, underline = 0, code = 0
        var colors: [NoteColorStyle] = []
        var links: [String] = []
        func current(_ marks: NoteMarks) -> NoteMarks {
            var value = marks
            if bold > 0 { value.bold = true }
            if italic > 0 { value.italic = true }
            if strike > 0 { value.strikethrough = true }
            if underline > 0 { value.underline = true }
            if code > 0 { value.code = true }
            if let color = colors.last { value.color = color }
            if value.link == nil, let link = links.last { value.link = link }
            return value
        }
        func push(_ text: String, _ marks: NoteMarks) {
            if marks.atom == nil, let last = pieces.last, last.1 == marks, last.1.atom == nil {
                pieces[pieces.count - 1].0 += text
            } else {
                pieces.append((text, marks))
            }
        }
        func pushAtom(_ atom: NoteAtom, _ marks: NoteMarks) {
            var value = marks
            value.atom = atom
            pieces.append((NoteAtom.character, value))
        }
        var index = 0
        while index < events.count {
            let event = events[index]
            let marks = current(event.marks)
            switch event.content {
            case .text(let value):
                push(value, marks)
            case .atom(let atom):
                pushAtom(atom, marks.withoutAtom)
            case .tag(let tag, let raw):
                if tag.name == "br", !tag.closing {
                    push("\n", marks)
                    break
                }
                guard partner[index] != -1 else {
                    pushAtom(.raw(raw), marks)
                    break
                }
                if !tag.closing {
                    let value = meaning(of: tag)
                    meanings[index] = value
                    switch value {
                    case .none: pushAtom(.raw(raw), marks)
                    case .bold: bold += 1
                    case .italic: italic += 1
                    case .strike: strike += 1
                    case .underline: underline += 1
                    case .code: code += 1
                    case .color(let style): colors.append(style)
                    case .link(let url): links.append(url)
                    case .date(let date):
                        pushAtom(.date(date), marks)
                        index = partner[index]
                    case .equation(let source):
                        pushAtom(.equation(source), marks)
                        index = partner[index]
                    case .mention(let url):
                        var title = ""
                        for inner in (index + 1)..<partner[index] {
                            switch events[inner].content {
                            case .text(let value): title += value
                            case .atom(let atom): title += atom.fallbackText
                            case .tag: break
                            }
                        }
                        pushAtom(.link(url: url, title: title.replacingOccurrences(of: "\u{2028}", with: " ")), marks)
                        index = partner[index]
                    }
                } else {
                    switch meanings[partner[index]] ?? TagMeaning.none {
                    case .none: pushAtom(.raw(raw), marks)
                    case .bold: bold -= 1
                    case .italic: italic -= 1
                    case .strike: strike -= 1
                    case .underline: underline -= 1
                    case .code: code -= 1
                    case .color: if !colors.isEmpty { colors.removeLast() }
                    case .link: if !links.isEmpty { links.removeLast() }
                    case .date, .equation, .mention: break
                    }
                }
            }
            index += 1
        }
        return NoteText(pieces: pieces)
    }
}
