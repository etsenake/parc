import Foundation

package struct NoteMDWriter {
    package let reader: NoteMDReader
    package let inline: NoteMDInlineWriter
    let portable: Bool

    package init(page: NotePage, customEmoji: Set<String> = [], portable: Bool = false) {
        self.portable = portable
        var references: [String: NoteMDLinkReference] = [:]
        var labels: [String: String] = [:]
        var footnotes: Set<String> = []
        for block in page.allBlocksIncludingTemplates() where block.kind == .raw {
            let bytes = Array(block.text.string.utf8)
            var position = 0
            while position < bytes.count {
                var lineEnd = position
                while lineEnd < bytes.count, bytes[lineEnd] != NoteMDByte.newline { lineEnd += 1 }
                if bytes[position] == 91, position + 1 < bytes.count, bytes[position + 1] == 94,
                   let close = bytes[position..<lineEnd].firstIndex(of: 93), close + 1 < lineEnd, bytes[close + 1] == 58 {
                    footnotes.insert(NoteMDText.normalizeLabel(NoteMDByte.string(bytes[(position + 2)..<close])))
                }
                if bytes[position] == 91, let (label, reference, end) = NoteMDScan.reference(bytes, from: position, upTo: bytes.count) {
                    if references[label] == nil {
                        references[label] = reference
                        if reference.title == nil, labels[reference.destination] == nil,
                           let rawLabelEnd = NoteMDScan.linkLabel(bytes, from: position, upTo: bytes.count) {
                            labels[reference.destination] = NoteMDByte.string(bytes[(position + 1)..<(rawLabelEnd - 1)])
                        }
                    }
                    position = max(end, position + 1)
                    continue
                }
                position = lineEnd + 1
            }
        }
        reader = NoteMDReader(references: references, footnotes: footnotes,
                              customEmoji: customEmoji.union(NoteCustomEmojiName.names(in: page)))
        inline = NoteMDInlineWriter(reader: reader, referenceLabels: labels, portable: portable)
    }

    package func write(_ page: NotePage) -> String {
        let front = NoteMDFrontMatter.write(page.settings)
        var body = sequence(page.blocks, frame: front == nil ? .document : .documentAfterFrontMatter)
        if front == nil, let first = body.first, NoteMDFrontMatter.split(Array((body.joined(separator: "\n") + "\n").utf8)) != nil {
            body[0] = " " + first
        }
        var output = front ?? ""
        if !body.isEmpty { output += body.joined(separator: "\n") + "\n" }
        return output
    }

    package enum Frame {
        case document, documentAfterFrontMatter, container(leading: Int, trailing: Int), listItem(leading: Int)
    }

    package static func isBareEmptyParagraph(_ block: NoteBlock) -> Bool {
        block.kind == .paragraph && block.text.isEmpty && block.color == nil && block.children.isEmpty && block.props.anchor == nil
    }

    private static func orderedDelimiter(_ block: NoteBlock) -> String? {
        switch block.kind {
        case .numberedItem: return block.props.orderedDelimiter ?? "."
        case .todo: return block.props.orderedDelimiter
        default: return nil
        }
    }

    private static func listGroup(_ block: NoteBlock) -> String? {
        guard block.kind.isListItem else { return nil }
        if let delimiter = orderedDelimiter(block) { return "o" + delimiter }
        return "b" + (block.props.bulletMarker.flatMap { ["*", "+", "-"].contains($0) ? $0 : nil } ?? "-")
    }

    package func sequence(_ blocks: [NoteBlock], frame: Frame) -> [String] {
        var lines: [String] = []
        var empties = 0
        var placedAny = false
        var lastNumber: Int?
        var previousGroup: String?
        var lastListGroup: String?
        var previousWasList = false
        var index = 0
        func separator() -> Int {
            if !placedAny {
                switch frame {
                case .document: return empties
                case .documentAfterFrontMatter: return empties > 0 ? empties + 1 : 1
                case .container(let leading, _), .listItem(let leading): return empties > 0 ? empties + 1 : leading
                }
            }
            return 1 + empties
        }
        while index < blocks.count {
            let block = blocks[index]
            if Self.isBareEmptyParagraph(block) {
                empties += 1
                lastNumber = nil
                previousGroup = nil
                index += 1
                continue
            }
            if let group = Self.listGroup(block) {
                var run: [NoteBlock] = [block]
                var probe = index + 1
                while probe < blocks.count, Self.listGroup(blocks[probe]) == group { run.append(blocks[probe]); probe += 1 }
                var numbers: [Int] = []
                var segments: [[NoteBlock]] = [[]]
                var restartsFirst = false
                for (offset, item) in run.enumerated() {
                    if group.hasPrefix("o") {
                        let expected = lastNumber.map { $0 + 1 } ?? 1
                        let number = item.props.listStart ?? expected
                        if offset > 0, number != expected { segments.append([]) }
                        if offset == 0, number != expected, previousGroup == group, empties == 0 { restartsFirst = true }
                        numbers.append(number)
                        lastNumber = number
                    }
                    segments[segments.count - 1].append(item)
                }
                if empties > 0, lastListGroup == group {
                    for _ in 0..<empties {
                        lines.append(contentsOf: Array(repeating: "", count: placedAny ? 1 : 0))
                        lines.append(portable ? comment([]) : attributes([("paragraph", nil)]))
                        placedAny = true
                    }
                    empties = 0
                }
                var numberIndex = 0
                for (segmentIndex, segment) in segments.enumerated() {
                    var gap = separator()
                    if segmentIndex > 0 || restartsFirst {
                        lines.append(contentsOf: Array(repeating: "", count: max(1, gap)))
                        lines.append("<!-- -->")
                        gap = 1
                    }
                    lines.append(contentsOf: Array(repeating: "", count: gap))
                    let loose = segment.contains { $0.props.looseList }
                    for (offset, item) in segment.enumerated() {
                        if offset > 0, loose { lines.append("") }
                        let number = group.hasPrefix("o") ? numbers[numberIndex] : 0
                        numberIndex += 1
                        lines.append(contentsOf: listItem(item, number: number))
                    }
                    placedAny = true
                    empties = 0
                }
                if !group.hasPrefix("o") { lastNumber = nil }
                previousGroup = group
                lastListGroup = group
                previousWasList = true
                index = probe
                continue
            }
            lines.append(contentsOf: Array(repeating: "", count: separator()))
            lines.append(contentsOf: self.block(block, afterList: previousWasList))
            placedAny = true
            empties = 0
            lastNumber = nil
            previousGroup = nil
            lastListGroup = nil
            previousWasList = block.kind == .raw && block.text.string.hasPrefix("[^")
            index += 1
        }
        switch frame {
        case .document:
            lines.append(contentsOf: Array(repeating: "", count: empties))
        case .documentAfterFrontMatter:
            if placedAny { lines.append(contentsOf: Array(repeating: "", count: empties)) } else if empties > 0 {
                lines.append(contentsOf: Array(repeating: "", count: empties + 1))
            }
        case .container(_, let trailing):
            lines.append(contentsOf: Array(repeating: "", count: empties > 0 ? empties + 1 : (placedAny ? trailing : 0)))
        case .listItem:
            break
        }
        return lines
    }

    package func attributes(_ items: [(String, String?)]) -> String {
        guard !items.isEmpty, !portable else { return "" }
        var result = "<!-- parc"
        for (name, value) in items {
            result += " " + name
            if let value { result += "=\"" + NoteMDText.escapeAttribute(value) + "\"" }
        }
        return result + " -->"
    }

    func blockAttributes(_ block: NoteBlock) -> [(String, String?)] {
        var items: [(String, String?)] = []
        guard !portable else { return items }
        if let color = block.color { items.append(("color", NoteMDColor.name(color))) }
        if let anchor = block.props.anchor, NoteAnchor.isValid(anchor) { items.append(("id", anchor)) }
        return items
    }

    package func suffix(_ items: [(String, String?)]) -> String {
        let text = attributes(items)
        return text.isEmpty ? "" : " " + text
    }

    private func comment(_ items: [(String, String?)]) -> String {
        if portable { return "<!-- -->" }
        return items.isEmpty ? "<!-- parc -->" : attributes(items)
    }

    private func textLines(_ text: NoteText, style: NoteMDInlineStyle, attributes items: [(String, String?)],
                           marked: Bool = false, carrying carried: [(String, String?)] = [], standalone: Bool = true) -> [String] {
        var commented = style
        commented.trailingComment = !portable && (marked || !items.isEmpty || Self.endsWithAttributeComment(text))
        var lines = inline.write(text, style: commented).components(separatedBy: "\n")
        if !commented.trailingComment, !portable, Self.startsHTMLBlock(lines[0]) {
            commented.trailingComment = true
            lines = inline.write(text, style: commented).components(separatedBy: "\n")
        }
        if commented.trailingComment { lines[lines.count - 1] += " " + comment(carried + items) }
        return standalone ? Self.leadingParagraph(lines) : lines
    }

    static let paragraphLeadIn = "<b></b>"

    static func endsWithAttributeComment(_ text: NoteText) -> Bool {
        guard text.length > 0, case .raw(let source)? = text.marks(at: text.length - 1).atom else { return false }
        return NoteMDAttributes.parse(source) != nil
    }

    private func guardedSuffix(_ text: NoteText, _ items: [(String, String?)]) -> (commented: Bool, suffix: String) {
        if portable { return (false, "") }
        if !items.isEmpty { return (true, suffix(items)) }
        return Self.endsWithAttributeComment(text) ? (true, " " + comment([])) : (false, "")
    }

    static func needsLeadIn(_ line: String) -> Bool {
        guard let byte = line.utf8.first, NoteMDBlockParser.mayOpenBlock(byte) else { return false }
        return !startsParagraph(line)
    }

    private static func leadingParagraph(_ lines: [String]) -> [String] {
        guard let first = lines.first, needsLeadIn(first) else { return lines }
        return [paragraphLeadIn + first] + lines.dropFirst()
    }

    static func startsHTMLBlock(_ line: String) -> Bool {
        let bytes = Array(line.utf8)
        return NoteMDHTML.blockStart(bytes, from: 0, upTo: bytes.count, interruptsParagraph: false) != nil
    }

    static func writesAsParagraph(_ block: NoteBlock?) -> Bool {
        guard let block else { return false }
        switch block.kind {
        case .paragraph, .pageLink, .image, .video, .audio, .file, .pdf, .embed, .easel, .bookmark: return true
        default: return false
        }
    }

    private func block(_ block: NoteBlock, afterList: Bool) -> [String] {
        switch block.kind {
        case .paragraph: return indented(paragraph(block), children: block.children)
        case .heading: return block.props.toggleable ? toggle(block) : indented(heading(block), children: block.children)
        case .bulletedItem, .numberedItem, .todo: return listItem(block, number: 1)
        case .toggle: return toggle(block)
        case .quote, .callout: return quote(block)
        case .divider:
            let fence = block.props.fence.flatMap { Self.isThematicBreak($0) ? $0 : nil } ?? "---"
            return [fence] + trailingAttributes(blockAttributes(block))
        case .code: return code(block, afterList: afterList)
        case .equation: return equation(block)
        case .image, .video, .audio, .file, .pdf, .embed: return [media(block)]
        case .bookmark: return [bookmark(block)]
        case .easel: return [easel(block)]
        case .pageLink:
            var label = block.text
            label.updateMarks(in: 0..<label.length) { $0.link = nil }
            let text = inline.write(label, style: NoteMDInlineStyle(shape: .line, insideLink: true, trailingComment: true))
            return ["[" + text + "](" + NoteMDInlineWriter.destination(block.props.target ?? "") + ")" + suffix(blockAttributes(block))]
        case .table: return table(block)
        case .tableOfContents: return ["<!-- toc -->"] + trailingAttributes(blockAttributes(block))
        case .breadcrumb: return [attributes([("breadcrumb", nil)] + blockAttributes(block))]
        case .columns: return columns(block)
        case .column: return columns(NoteBlock(.columns, children: [block]))
        case .html, .raw: return block.text.string.components(separatedBy: "\n")
        case .synced: return synced(block)
        case .button: return button(block)
        }
    }

    private func synced(_ block: NoteBlock) -> [String] {
        var items: [(String, String?)] = [(NoteMDSynced.flag, nil)]
        if let source = block.props.target, !source.isEmpty { items.append((NoteMDSynced.sourceKey, source)) }
        if let anchor = block.props.anchor, NoteAnchor.isValid(anchor) { items.append(("id", anchor)) }
        let opener = attributes(items)
        if block.children.isEmpty { return [opener, NoteMDSynced.closer] }
        return [opener] + sequence(block.children, frame: .container(leading: 1, trailing: 1)) + [NoteMDSynced.closer]
    }

    private func indented(_ lines: [String], children: [NoteBlock]) -> [String] {
        guard !children.isEmpty else { return lines }
        let fence = String(repeating: ":", count: 3 + Self.directiveDepth(children))
        return lines + ["", fence + " " + NoteMDDirective.indent] + sequence(children, frame: .container(leading: 0, trailing: 0)) + [fence]
    }

    static func writesIndent(_ block: NoteBlock) -> Bool {
        !block.children.isEmpty && (block.kind == .paragraph || (block.kind == .heading && !block.props.toggleable))
    }

    static func directiveDepth(_ blocks: [NoteBlock]) -> Int {
        blocks.reduce(0) { deepest, block in
            let own: Int
            switch block.kind {
            case .columns: own = 2 + directiveDepth(block.children.flatMap { $0.kind == .column ? $0.children : [$0] })
            case .column: own = 2 + directiveDepth(block.children)
            case .button: own = directiveDepth(block.buttonValue.templateBlocks)
            default: own = (writesIndent(block) ? 1 : 0) + directiveDepth(block.children)
            }
            return max(deepest, own)
        }
    }

    private func trailingAttributes(_ items: [(String, String?)]) -> [String] {
        let text = attributes(items)
        return text.isEmpty ? [] : [text]
    }

    static func isThematicBreak(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed == value, let first = trimmed.first, "*-_".contains(first) else { return false }
        return trimmed.allSatisfy { $0 == first || $0 == " " || $0 == "\t" } && trimmed.filter({ $0 == first }).count >= 3
    }

    private func paragraph(_ block: NoteBlock) -> [String] {
        var items = blockAttributes(block)
        if block.text.isEmpty { return [attributes([("paragraph", nil)] + items)] }
        var style = NoteMDInlineStyle.paragraph
        style.trailingComment = !items.isEmpty
        var markdown = inline.write(block.text, style: style)
        if !portable, standaloneHazard(markdown) || Self.startsHTMLBlock(markdown.components(separatedBy: "\n")[0]) {
            items.insert(("paragraph", nil), at: 0)
            if !style.trailingComment {
                style.trailingComment = true
                markdown = inline.write(block.text, style: style)
            }
        }
        var lines = markdown.components(separatedBy: "\n")
        if !items.isEmpty { lines[lines.count - 1] += suffix(items) }
        return Self.leadingParagraph(lines)
    }

    private func standaloneHazard(_ markdown: String) -> Bool {
        let tree = NoteMDInlineParser.parse(Array(markdown.utf8), references: reader.references, footnotes: reader.footnotes,
                                            customEmoji: reader.customEmoji)
        let children = tree.children(of: 0)
        if let last = children.last, tree.nodes[last].kind == .html, NoteMDAttributes.parse(tree.nodes[last].literal) != nil { return true }
        guard children.count == 1 else { return false }
        let node = tree.nodes[children[0]]
        return node.kind == .image || (node.kind == .link && node.title == nil && NoteMDLinks.isRelativeMarkdown(node.destination))
    }

    private func heading(_ block: NoteBlock) -> [String] {
        let items = blockAttributes(block)
        let level = min(max(block.props.level, 1), 6)
        if level <= 2, !block.text.isEmpty, block.props.fence == (level == 1 ? "=" : "-") {
            let lines = textLines(block.text, style: .paragraph, attributes: items)
            let width = max(3, lines.map(\.count).max() ?? 3)
            return lines + [String(repeating: level == 1 ? "=" : "-", count: width)]
        }
        let tail = guardedSuffix(block.text, items)
        let content = (inline.write(block.text, style: NoteMDInlineStyle(shape: .heading, trailingComment: tail.commented)) + tail.suffix)
            .trimmingCharacters(in: .whitespaces)
        let marker = String(repeating: "#", count: level)
        return [content.isEmpty ? marker : marker + " " + content]
    }

    private func listItem(_ block: NoteBlock, number: Int) -> [String] {
        var marker: String
        if let delimiter = Self.orderedDelimiter(block) {
            marker = "\(number)\(delimiter == ")" ? ")" : ".")"
        } else {
            marker = block.props.bulletMarker.flatMap { ["*", "+", "-"].contains($0) ? $0 : nil } ?? "-"
        }
        let indent = String(repeating: " ", count: marker.count + 1)
        if block.kind == .todo { marker += block.props.checked ? " [x]" : " [ ]" }
        let items = blockAttributes(block)
        var textLines: [String]
        let firstChildIsParagraph = Self.writesAsParagraph(block.children.first)
        if block.text.isEmpty {
            textLines = !items.isEmpty || firstChildIsParagraph ? [comment(items)] : []
        } else {
            let style = NoteMDInlineStyle(shape: .paragraph, taskSensitive: block.kind != .todo)
            textLines = self.textLines(block.text, style: style, attributes: items, standalone: block.kind != .todo)
        }
        var lines: [String] = []
        if let first = textLines.first {
            lines.append(marker + " " + first)
            for line in textLines.dropFirst() { lines.append(line.isEmpty ? "" : indent + line) }
        } else {
            lines.append(marker)
        }
        if !block.children.isEmpty {
            let hasFirstLine = !textLines.isEmpty || block.kind == .todo
            var leading = hasFirstLine ? 1 : 0
            if let first = block.children.first, first.kind.isListItem, hasFirstLine {
                let firstLineHasContent = !first.text.isEmpty || first.color != nil || first.props.anchor != nil || first.kind == .todo || Self.writesAsParagraph(first.children.first)
                let interrupts = firstLineHasContent && (Self.orderedDelimiter(first) == nil || (first.props.listStart ?? 1) == 1)
                leading = interrupts ? 0 : 1
            }
            var childLines = sequence(block.children, frame: .listItem(leading: leading))
            if leading == 0, hasFirstLine, let firstChildLine = childLines.first {
                let task = block.kind == .todo ? String(marker.suffix(3)) : ""
                let paragraphLine = textLines.count > 1 ? textLines[textLines.count - 1] : [task, textLines.first ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
                let junction = NoteMDBlockParser.parse(Array((paragraphLine + "\n" + firstChildLine).utf8)).root.children.map(\.kind)
                if junction != [.paragraph, .list] { childLines = sequence(block.children, frame: .listItem(leading: 1)) }
            }
            for line in childLines {
                lines.append(line.isEmpty ? "" : indent + line)
            }
        }
        return lines
    }

    private func quote(_ block: NoteBlock) -> [String] {
        var inner: [String] = []
        let items = portable ? [] : (block.kind == .callout ? (block.props.icon.map { [("icon", $0)] } ?? []) : []) + blockAttributes(block)
        let firstChildIsParagraph = Self.writesAsParagraph(block.children.first)
        var leading = 1
        var children = block.children
        if block.kind == .callout {
            let noteAlert = NoteMDReader.noteAlert
            let marked = !portable && block.props.alert == nil
            let carried: [(String, String?)] = !portable && block.props.alert == noteAlert ? [(NoteMDReader.keepsAlertFlag, nil)] : []
            let alert = block.props.alert ?? noteAlert
            let fold = block.props.toggleable ? (block.props.expanded ? "+" : "-") : ""
            let marker = "[!\(alert)]\(fold)"
            if NoteMDReader.calloutUsesBody(block.props.alert) {
                inner.append(marker)
                let lines = block.text.isEmpty ? [] : textLines(block.text, style: .paragraph, attributes: items, marked: marked,
                                                                carrying: carried, standalone: false)
                if let first = lines.first, Self.needsLeadIn(first) {
                    let commented = marked || !items.isEmpty
                    let title = inline.write(block.text, style: NoteMDInlineStyle(shape: .line, trailingComment: commented))
                    inner[inner.count - 1] = marker + " " + title + (commented ? " " + comment(carried + items) : "")
                } else if !block.text.isEmpty {
                    inner.append(contentsOf: lines)
                } else if !items.isEmpty || firstChildIsParagraph || marked {
                    inner.append(comment(carried + items))
                }
            } else {
                let tail = guardedSuffix(block.text, items)
                let title = inline.write(block.text, style: NoteMDInlineStyle(shape: .line, trailingComment: tail.commented))
                inner.append(marker + (title.isEmpty ? "" : " " + title) + tail.suffix)
                if let first = children.first, first.kind == .paragraph, !first.text.isEmpty, first.color == nil, first.props.anchor == nil,
                   first.children.isEmpty {
                    inner.append(contentsOf: paragraph(first))
                    children.removeFirst()
                }
            }
        } else {
            if !block.text.isEmpty {
                inner.append(contentsOf: textLines(block.text, style: NoteMDInlineStyle(shape: .paragraph, calloutSensitive: true), attributes: items))
            } else if !items.isEmpty || firstChildIsParagraph {
                inner.append(comment(items))
            } else {
                leading = 0
            }
        }
        inner.append(contentsOf: sequence(children, frame: .container(leading: leading, trailing: 0)))
        if inner.isEmpty { return [">"] }
        return inner.map { $0.isEmpty ? ">" : "> " + $0 }
    }

    static func startsParagraph(_ line: String) -> Bool {
        NoteMDBlockParser.startsParagraph(Array(line.utf8)[...])
    }

    private func toggle(_ block: NoteBlock) -> [String] {
        let tail = guardedSuffix(block.text, blockAttributes(block))
        let content = inline.write(block.text, style: NoteMDInlineStyle(shape: .line, htmlSafe: true, trailingComment: tail.commented)) + tail.suffix
        let summary: String
        if block.kind == .heading {
            let level = min(max(block.props.level, 1), 6)
            summary = "<summary><h\(level)>" + content + "</h\(level)></summary>"
        } else {
            summary = "<summary>" + content + "</summary>"
        }
        let opener = block.props.expanded ? "<details open>" : "<details>"
        if block.children.isEmpty { return [opener, summary, "</details>"] }
        return [opener, summary] + sequence(block.children, frame: .container(leading: 1, trailing: 1)) + ["</details>"]
    }

    private func code(_ block: NoteBlock, afterList: Bool) -> [String] {
        let text = block.text.string
        let lines = text.components(separatedBy: "\n")
        var items: [(String, String?)] = []
        if !block.props.caption.isEmpty { items.append(("caption", inline.write(block.props.caption, style: .verbatim))) }
        if block.props.wrap { items.append(("wrap", nil)) }
        if NoteMermaid.isDiagram(block), let mode = block.props.diagramMode, mode != .preview { items.append(("view", mode.rawValue)) }
        items += blockAttributes(block)
        if Self.writesIndentedCode(block, afterList: afterList) {
            return lines.map { $0.isEmpty ? "" : "    " + $0 }
        }
        let info = block.props.language + (block.props.info.map { " " + $0 } ?? "")
        let fence = Self.fence(for: text, preferred: block.props.fence, info: info)
        let separator = info.first == fence.first ? " " : ""
        return [fence + separator + Self.escapeInfo(info)] + (text.isEmpty ? [] : lines) + [fence] + trailingAttributes(items)
    }

    static func writesIndentedCode(_ block: NoteBlock, afterList: Bool) -> Bool {
        guard block.kind == .code, block.props.fence == "    ", !afterList, block.props.language.isEmpty, block.props.info == nil,
              block.props.caption.isEmpty, !block.props.wrap, block.color == nil, !(block.props.anchor.map(NoteAnchor.isValid) ?? false) else { return false }
        let lines = block.text.string.components(separatedBy: "\n")
        func hasContent(_ line: String?) -> Bool { line?.unicodeScalars.contains { $0 != " " && $0 != "\t" } ?? false }
        return hasContent(lines.first) && hasContent(lines.last)
    }

    private static func escapeInfo(_ info: String) -> String {
        var result = ""
        let scalars = Array(info.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            if scalar == "\\", index + 1 < scalars.count, scalars[index + 1].isASCII, NoteMDByte.isPunctuation(UInt8(scalars[index + 1].value)) { result += "\\" }
            if scalar == "&", NoteMDInlineWriter.entityLike(scalars, at: index) { result += "\\" }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    static func fence(for text: String, preferred: String?, info: String) -> String {
        var character: Character = preferred?.first == "~" ? "~" : "`"
        if character == "`", info.contains("`") { character = "~" }
        var longest = 0
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.drop(while: { $0 == " " })
            guard line.count - trimmed.count < 4 else { continue }
            let run = trimmed.prefix(while: { $0 == character }).count
            guard trimmed.dropFirst(run).allSatisfy({ $0 == " " || $0 == "\t" }) else { continue }
            longest = max(longest, run)
        }
        let preferredLength = preferred.flatMap { $0.first == character && $0.allSatisfy({ $0 == character }) ? $0.count : nil } ?? 3
        return String(repeating: character, count: max(3, preferredLength, longest + 1))
    }

    private func equation(_ block: NoteBlock) -> [String] {
        let text = block.text.string
        let lines = text.components(separatedBy: "\n")
        let items = blockAttributes(block)
        if block.props.fence != nil || Self.equationNeedsFence(text) {
            let fence = Self.fence(for: text, preferred: block.props.fence, info: "math")
            return [fence + "math"] + (text.isEmpty ? [] : lines) + [fence] + trailingAttributes(items)
        }
        return ["$$"] + (text.isEmpty ? [] : lines) + ["$$"] + trailingAttributes(items)
    }

    static func equationNeedsFence(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix("$$") || trimmed.hasPrefix("$$")
        }
    }

    private func titleEscaped(_ markdown: String) -> String {
        var result = ""
        for character in markdown {
            if character == "\\" || character == "\"" || character == "&" { result.append("\\") }
            result.append(character)
        }
        return result
    }

    private func media(_ block: NoteBlock) -> String {
        let source = block.props.source ?? ""
        let alt = inline.write(NoteText(block.props.alt ?? ""), style: NoteMDInlineStyle(shape: .line, insideLink: true, trailingComment: true))
        var line = "![" + alt + "](" + NoteMDInlineWriter.destination(source)
        if !block.props.caption.isEmpty { line += " \"" + titleEscaped(inline.write(block.props.caption, style: .verbatim)) + "\"" }
        line += ")"
        var items: [(String, String?)] = []
        if NoteMDMedia.inferredKind(source) != block.kind {
            items.append((NoteMDAttributes.kindNames.first(where: { $0.value == block.kind })?.key ?? "image", nil))
        }
        if let width = block.props.width { items.append(("width", Self.number(width))) }
        if let height = block.props.height { items.append(("height", Self.number(height))) }
        if block.props.alignment != .center { items.append(("align", block.props.alignment.rawValue)) }
        if let credit = block.props.credit, !credit.name.isEmpty {
            items.append(("credit", credit.name))
            if let link = credit.link { items.append(("credit-url", link)) }
        }
        if let crop = block.props.crop { items.append(("crop", crop.attribute)) }
        if let mask = block.props.mask { items.append(("mask", mask.rawValue)) }
        if block.kind == .image, let capture = block.props.capture { items += capture.attributes }
        items += blockAttributes(block)
        return line + suffix(items)
    }

    private func easel(_ block: NoteBlock) -> String {
        let source = NoteEaselAddress.id(of: block).map(NoteEaselAddress.address) ?? block.props.source ?? ""
        let title = inline.write(NoteText(NoteEaselAddress.title(of: block)), style: NoteMDInlineStyle(shape: .line, insideLink: true, trailingComment: true))
        var items: [(String, String?)] = [("easel", nil)]
        if let width = block.props.width { items.append(("width", Self.number(width))) }
        if let height = block.props.height { items.append(("height", Self.number(height))) }
        if block.props.alignment != .center { items.append(("align", block.props.alignment.rawValue)) }
        items += blockAttributes(block)
        return "[" + title + "](" + NoteMDInlineWriter.destination(source) + ")" + suffix(items)
    }

    private func bookmark(_ block: NoteBlock) -> String {
        let source = block.props.source ?? ""
        let bookmark = block.props.bookmark ?? NoteBookmark()
        var items: [(String, String?)] = [("bookmark", nil)]
        var line: String
        let autolinkable = source.range(of: "^[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\\s<>\\x00-\\x1F]*$", options: .regularExpression) != nil
        if bookmark.title?.isEmpty ?? true, autolinkable {
            line = "<" + source + ">"
            if !block.props.caption.isEmpty { items.append(("caption", inline.write(block.props.caption, style: .verbatim))) }
        } else {
            let title = inline.write(NoteText(bookmark.title ?? ""), style: NoteMDInlineStyle(shape: .line, insideLink: true, trailingComment: true))
            line = "[" + title + "](" + NoteMDInlineWriter.destination(source)
            if !block.props.caption.isEmpty { line += " \"" + titleEscaped(inline.write(block.props.caption, style: .verbatim)) + "\"" }
            line += ")"
        }
        if let value = bookmark.summary { items.append(("summary", value)) }
        if let value = bookmark.siteName { items.append(("site", value)) }
        if let value = bookmark.iconURL { items.append(("favicon", value)) }
        if let value = bookmark.imageURL { items.append(("thumbnail", value)) }
        items += blockAttributes(block)
        return line + suffix(items)
    }

    private func table(_ block: NoteBlock) -> [String] {
        var table = block.props.table ?? NoteTable.empty()
        table.normalize()
        let rows = table.rows.map { $0.map { inline.write($0, style: .cell) } }
        let columns = table.columnCount
        var widths = Array(repeating: 3, count: columns)
        for row in rows {
            for (index, cell) in row.enumerated() { widths[index] = max(widths[index], cell.count) }
        }
        func line(_ cells: [String]) -> String {
            var parts: [String] = []
            for index in 0..<columns {
                let cell = index < cells.count ? cells[index] : ""
                parts.append(cell + String(repeating: " ", count: max(0, widths[index] - cell.count)))
            }
            return "| " + parts.joined(separator: " | ") + " |"
        }
        var delimiter: [String] = []
        for index in 0..<columns {
            let width = widths[index]
            switch table.alignments.indices.contains(index) ? table.alignments[index] : nil {
            case .left?: delimiter.append(":" + String(repeating: "-", count: width - 1))
            case .center?: delimiter.append(":" + String(repeating: "-", count: width - 2) + ":")
            case .right?: delimiter.append(String(repeating: "-", count: width - 1) + ":")
            case nil: delimiter.append(String(repeating: "-", count: width))
            }
        }
        var lines = [line(rows[0]), "| " + delimiter.joined(separator: " | ") + " |"]
        for row in rows.dropFirst() { lines.append(line(row)) }
        var items: [(String, String?)] = []
        if !table.headerRow { items.append(("no-header-row", nil)) }
        if table.headerColumn { items.append(("header-column", nil)) }
        if table.columnWidths.contains(where: { $0 != nil }) {
            items.append(("widths", table.columnWidths.map { $0.map(Self.number) ?? "" }.joined(separator: ",")))
        }
        if let merge = table.mergeAttribute { items.append(("merge", merge)) }
        if let colors = table.colorsAttribute { items.append(("colors", colors)) }
        items += blockAttributes(block)
        return lines + trailingAttributes(items)
    }

    private func columns(_ block: NoteBlock) -> [String] {
        let inner = String(repeating: ":", count: 3 + Self.directiveDepth(block.children.flatMap { $0.kind == .column ? $0.children : [$0] }))
        let outer = inner + ":"
        var lines = [outer + " columns"]
        for column in block.children {
            let children = column.kind == .column ? column.children : [column]
            if column.kind == .column, let width = column.props.width {
                lines.append(inner + " {.column width=\"\(NoteMDDirective.percent(fromRatio: width))%\"}")
            } else {
                lines.append(inner + " column")
            }
            lines.append(contentsOf: sequence(children, frame: .container(leading: 0, trailing: 0)))
            lines.append(inner)
        }
        lines.append(outer)
        return lines + trailingAttributes(blockAttributes(block))
    }

    package static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }

}
