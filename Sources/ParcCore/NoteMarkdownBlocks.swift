import Foundation

final class NoteMDBlock {
    package enum Kind { case document, quote, list, item, paragraph, heading, thematicBreak, code, html, table, math, directive, footnote, definitions }

    let kind: Kind
    weak var parent: NoteMDBlock?
    var children: [NoteMDBlock] = []
    var isOpen = true
    var content: [UInt8] = []
    var blankBefore = 0
    var pendingBlank = 0
    var trailingBlank = 0
    var ordered = false
    var marker: UInt8 = 0
    var start = 1
    var markerOffset = 0
    var padding = 0
    var loose = false
    var level = 0
    var setext: UInt8 = 0
    var fenced = false
    var fenceChar: UInt8 = 0
    var fenceLength = 0
    var fenceOffset = 0
    var info = ""
    var htmlType = 0
    var alignments: [NoteAlignment?] = []
    var rows: [[[UInt8]]] = []
    var literal = ""
    var directiveName = ""
    var directiveWidth: Double?
    var rawLines: [[UInt8]] = []

    init(_ kind: Kind) { self.kind = kind }

    var acceptsLines: Bool {
        switch kind {
        case .paragraph, .code, .html, .table, .math: return true
        default: return false
        }
    }

    var isContainer: Bool {
        switch kind {
        case .document, .quote, .item, .directive, .footnote: return true
        default: return false
        }
    }

    func canContain(_ child: Kind) -> Bool {
        switch kind {
        case .document, .quote, .item, .directive, .footnote: return child != .item
        case .list: return child == .item
        default: return false
        }
    }

    var lastOpenChild: NoteMDBlock? {
        guard let last = children.last, last.isOpen else { return nil }
        return last
    }
}

struct NoteMDDocument {
    var root: NoteMDBlock
    var references: [String: NoteMDLinkReference]
    var footnotes: Set<String>
}

final class NoteMDBlockParser {
    private let bytes: [UInt8]
    private let document = NoteMDBlock(.document)
    private var tip: NoteMDBlock
    private var oldTip: NoteMDBlock
    private var lastMatchedContainer: NoteMDBlock
    private var lineStart = 0
    private var lineEnd = 0
    private var offset = 0
    private var column = 0
    private var nextNonspace = 0
    private var nextNonspaceColumn = 0
    private var indent = 0
    private var indented = false
    private var blank = false
    private var partiallyConsumedTab = false
    private var allClosed = true
    private var lineConsumed = false
    private var openedContainerThisLine = false
    private var provisionalFootnote: (NoteMDBlock, [UInt8])?
    private var references: [String: NoteMDLinkReference] = [:]
    private var footnotes: Set<String> = []

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
        tip = document
        oldTip = document
        lastMatchedContainer = document
    }

    static func parse(_ bytes: [UInt8]) -> NoteMDDocument {
        let parser = NoteMDBlockParser(bytes)
        return parser.run()
    }

    private func run() -> NoteMDDocument {
        var index = 0
        let count = bytes.count
        while index < count {
            var end = index
            while end < count, bytes[end] != NoteMDByte.newline, bytes[end] != NoteMDByte.carriageReturn { end += 1 }
            incorporate(start: index, end: end)
            if end < count, bytes[end] == NoteMDByte.carriageReturn, end + 1 < count, bytes[end + 1] == NoteMDByte.newline { index = end + 2 } else { index = end + 1 }
        }
        while tip !== document { finalize(tip) }
        finalize(document)
        return NoteMDDocument(root: document, references: references, footnotes: footnotes)
    }

    private func peek(_ position: Int) -> UInt8 { position < lineEnd ? bytes[position] : 0 }

    private func findNextNonspace() {
        var index = offset, columns = column
        while index < lineEnd {
            let byte = bytes[index]
            if byte == NoteMDByte.space { index += 1; columns += 1 }
            else if byte == NoteMDByte.tab { index += 1; columns += 4 - (columns % 4) }
            else { break }
        }
        blank = index >= lineEnd
        nextNonspace = index
        nextNonspaceColumn = columns
        indent = columns - column
        indented = indent >= 4
    }

    private func advanceNextNonspace() {
        offset = nextNonspace
        column = nextNonspaceColumn
        partiallyConsumedTab = false
    }

    private func advanceOffset(_ amount: Int, columns: Bool) {
        var count = amount
        while count > 0, offset < lineEnd {
            if bytes[offset] == NoteMDByte.tab {
                let charsToTab = 4 - (column % 4)
                if columns {
                    partiallyConsumedTab = charsToTab > count
                    let charsToAdvance = min(charsToTab, count)
                    column += charsToAdvance
                    if !partiallyConsumedTab { offset += 1 }
                    count -= charsToAdvance
                } else {
                    partiallyConsumedTab = false
                    column += charsToTab
                    offset += 1
                    count -= 1
                }
            } else {
                partiallyConsumedTab = false
                offset += 1
                column += 1
                count -= 1
            }
        }
    }

    private func remainderBytes() -> [UInt8] {
        var result: [UInt8] = []
        var start = offset
        if partiallyConsumedTab {
            start += 1
            result.append(contentsOf: repeatElement(NoteMDByte.space, count: 4 - (column % 4)))
        }
        if start < lineEnd { result.append(contentsOf: bytes[start..<lineEnd]) }
        return result
    }

    private func addLine() {
        tip.content.append(contentsOf: remainderBytes())
        tip.content.append(NoteMDByte.newline)
    }

    private func addChild(_ kind: NoteMDBlock.Kind) -> NoteMDBlock {
        while !tip.canContain(kind) { finalize(tip) }
        let child = NoteMDBlock(kind)
        child.parent = tip
        child.blankBefore = tip.pendingBlank
        tip.pendingBlank = 0
        tip.children.append(child)
        tip = child
        return child
    }

    private func closeUnmatchedBlocks() {
        guard !allClosed else { return }
        while oldTip !== lastMatchedContainer {
            guard let parent = oldTip.parent else { break }
            finalize(oldTip)
            oldTip = parent
        }
        allClosed = true
    }

    private enum Continuation { case matched, failed, consumed }

    private func incorporate(start: Int, end: Int) {
        lineStart = start
        lineEnd = end
        offset = start
        column = 0
        blank = false
        partiallyConsumedTab = false
        lineConsumed = false
        openedContainerThisLine = false
        provisionalFootnote = nil
        var container = document
        oldTip = tip
        allClosed = true
        while let child = container.lastOpenChild {
            container = child
            findNextNonspace()
            let result = continuation(of: container)
            if result == .consumed { return }
            if result == .failed {
                container = container.parent ?? document
                allClosed = false
                break
            }
        }
        allClosed = container === oldTip
        lastMatchedContainer = container
        var matchedLeaf = container.kind != .paragraph && container.kind != .table && container.acceptsLines
        starts: while !matchedLeaf {
            findNextNonspace()
            if !indented, !Self.mayOpenBlock(peek(nextNonspace)) {
                advanceNextNonspace()
                break starts
            }
            switch tryBlockStart(container) {
            case .none:
                advanceNextNonspace()
                break starts
            case .container:
                container = tip
                openedContainerThisLine = true
            case .leaf:
                container = tip
                matchedLeaf = true
            }
            if lineConsumed { return }
        }
        if !allClosed, !blank, tip.kind == .paragraph {
            if let (footnote, line) = provisionalFootnote { footnote.rawLines.append(line) }
            addLine()
            return
        }
        closeUnmatchedBlocks()
        if blank {
            if container.acceptsLines, container.kind == .code || container.kind == .math || (container.kind == .html && container.htmlType <= 5) {
                addLine()
                if container.kind == .html, NoteMDHTML.blockEnds(container.htmlType, bytes, from: offset, upTo: lineEnd) { finalize(container) }
                return
            }
            guard !openedContainerThisLine else { return }
            var target = container
            while !target.isContainer, target.kind != .list, let parent = target.parent { target = parent }
            target.pendingBlank += 1
            return
        }
        switch container.kind {
        case .table:
            container.rows.append(NoteMDTableRow.cells(remainderBytes()))
        case .paragraph, .code, .html, .math:
            addLine()
            if container.kind == .html, container.htmlType >= 1, container.htmlType <= 5,
               NoteMDHTML.blockEnds(container.htmlType, bytes, from: offset, upTo: lineEnd) {
                finalize(container)
            }
        default:
            if offset < lineEnd {
                _ = addChild(.paragraph)
                advanceNextNonspace()
                addLine()
            }
        }
    }

    static func mayOpenBlock(_ byte: UInt8) -> Bool {
        switch byte {
        case 35, 96, 126, 42, 43, 45, 95, 61, 60, 62, 124, 58, 36, 91: return true
        default: return NoteMDByte.isDigit(byte)
        }
    }

    private func continuation(of block: NoteMDBlock) -> Continuation {
        switch block.kind {
        case .document, .list:
            return .matched
        case .quote:
            if !indented, peek(nextNonspace) == 62 {
                advanceNextNonspace()
                advanceOffset(1, columns: false)
                if NoteMDByte.isSpaceOrTab(peek(offset)) { advanceOffset(1, columns: true) }
                return .matched
            }
            return .failed
        case .item:
            if blank {
                if block.children.isEmpty { return .failed }
                advanceNextNonspace()
                return .matched
            }
            if indent >= block.markerOffset + block.padding {
                advanceOffset(block.markerOffset + block.padding, columns: true)
                return .matched
            }
            return .failed
        case .footnote:
            block.rawLines.append(remainderBytes())
            if blank { advanceNextNonspace(); return .matched }
            if indent >= 4 { advanceOffset(4, columns: true); return .matched }
            provisionalFootnote = (block, block.rawLines.removeLast())
            return .failed
        case .heading, .thematicBreak, .definitions:
            return .failed
        case .code:
            if block.fenced {
                if !indented, peek(nextNonspace) == block.fenceChar {
                    var index = nextNonspace
                    while index < lineEnd, bytes[index] == block.fenceChar { index += 1 }
                    if index - nextNonspace >= block.fenceLength {
                        var rest = index
                        while rest < lineEnd, NoteMDByte.isSpaceOrTab(bytes[rest]) { rest += 1 }
                        if rest >= lineEnd {
                            finalize(block)
                            return .consumed
                        }
                    }
                }
                var remaining = block.fenceOffset
                while remaining > 0, NoteMDByte.isSpaceOrTab(peek(offset)) {
                    advanceOffset(1, columns: true)
                    remaining -= 1
                }
                return .matched
            }
            if indent >= 4 { advanceOffset(4, columns: true); return .matched }
            if blank { advanceNextNonspace(); return .matched }
            return .failed
        case .html:
            return blank && (block.htmlType == 6 || block.htmlType == 7) ? .failed : .matched
        case .paragraph, .table:
            return blank ? .failed : .matched
        case .math:
            var end = lineEnd
            while end > offset, NoteMDByte.isSpaceOrTab(bytes[end - 1]) { end -= 1 }
            if end - offset >= 2, bytes[end - 1] == 36, bytes[end - 2] == 36, end - 3 < offset || bytes[end - 3] != 92 {
                var contentEnd = end - 2
                while contentEnd > offset, NoteMDByte.isSpaceOrTab(bytes[contentEnd - 1]) { contentEnd -= 1 }
                if contentEnd > nextNonspace {
                    block.content.append(contentsOf: bytes[offset..<contentEnd])
                    block.content.append(NoteMDByte.newline)
                }
                finalize(block)
                return .consumed
            }
            return .matched
        case .directive:
            if !indented, isDirectiveCloser(), !tipIsVerbatim(below: block), !hasOpenDirective(below: block) {
                while tip !== block, tip !== document { finalize(tip) }
                finalize(block)
                return .consumed
            }
            return .matched
        }
    }

    private func tipIsVerbatim(below block: NoteMDBlock) -> Bool {
        guard tip !== block else { return false }
        guard tip.kind == .code && tip.fenced || tip.kind == .math || tip.kind == .html && tip.htmlType <= 5 else { return false }
        var node: NoteMDBlock? = tip.parent
        while let current = node {
            if current === block { return true }
            node = current.parent
        }
        return false
    }

    private func hasOpenDirective(below block: NoteMDBlock) -> Bool {
        var node = block.lastOpenChild
        while let current = node {
            if current.kind == .directive { return true }
            node = current.lastOpenChild
        }
        return false
    }

    private func isDirectiveCloser() -> Bool {
        var index = nextNonspace
        while index < lineEnd, bytes[index] == 58 { index += 1 }
        guard index - nextNonspace >= 3 else { return false }
        while index < lineEnd, NoteMDByte.isSpaceOrTab(bytes[index]) { index += 1 }
        return index >= lineEnd
    }

    private enum StartResult { case none, container, leaf }

    static let maximumDepth = 64

    private func tryBlockStart(_ container: NoteMDBlock) -> StartResult {
        let first = peek(nextNonspace)
        var depth = 0
        var ancestor: NoteMDBlock? = container
        while let current = ancestor { depth += 1; ancestor = current.parent }
        let nests = depth < Self.maximumDepth
        if !indented {
            if first == 62, nests {
                advanceNextNonspace()
                advanceOffset(1, columns: false)
                if NoteMDByte.isSpaceOrTab(peek(offset)) { advanceOffset(1, columns: true) }
                closeUnmatchedBlocks()
                _ = addChild(.quote)
                return .container
            }
            if first == 35, let result = atxHeading() { return result }
            if first == 96 || first == 126, let result = fencedCode() { return result }
            if first == 60, let type = NoteMDHTML.blockStart(bytes, from: nextNonspace, upTo: lineEnd,
                                                              interruptsParagraph: container.kind == .paragraph || (!allClosed && tip.kind == .paragraph)) {
                closeUnmatchedBlocks()
                let block = addChild(.html)
                block.htmlType = type
                return .leaf
            }
            if (first == 61 || first == 45), container.kind == .paragraph, let result = setextHeading(container) { return result }
            if container.kind == .paragraph, (first == 124 || first == 58 || first == 45), let result = tableStart(container) { return result }
            if (first == 42 || first == 45 || first == 95), let result = thematicBreak() { return result }
        }
        if nests, !indented || container.kind == .list, let result = listItem(container) { return result }
        if indented, tip.kind != .paragraph, !blank {
            advanceOffset(4, columns: true)
            closeUnmatchedBlocks()
            _ = addChild(.code)
            return .leaf
        }
        if !indented {
            if first == 36, container.kind != .paragraph, let result = mathBlock() { return result }
            if first == 58, nests, let result = directive() { return result }
            if first == 91, nests, let result = footnoteDefinition() { return result }
        }
        return .none
    }

    private func atxHeading() -> StartResult? {
        var index = nextNonspace
        while index < lineEnd, bytes[index] == 35, index - nextNonspace < 7 { index += 1 }
        let level = index - nextNonspace
        guard level >= 1, level <= 6, index >= lineEnd || NoteMDByte.isSpaceOrTab(bytes[index]) else { return nil }
        closeUnmatchedBlocks()
        let heading = addChild(.heading)
        heading.level = level
        var contentStart = index
        while contentStart < lineEnd, NoteMDByte.isSpaceOrTab(bytes[contentStart]) { contentStart += 1 }
        var contentEnd = lineEnd
        while contentEnd > contentStart, NoteMDByte.isSpaceOrTab(bytes[contentEnd - 1]) { contentEnd -= 1 }
        var closing = contentEnd
        while closing > contentStart, bytes[closing - 1] == 35 { closing -= 1 }
        if closing < contentEnd {
            if closing == contentStart {
                contentEnd = contentStart
            } else if NoteMDByte.isSpaceOrTab(bytes[closing - 1]) {
                contentEnd = closing
                while contentEnd > contentStart, NoteMDByte.isSpaceOrTab(bytes[contentEnd - 1]) { contentEnd -= 1 }
            }
        }
        heading.content = Array(bytes[contentStart..<contentEnd])
        offset = lineEnd
        finalize(heading)
        lineConsumed = true
        return .leaf
    }

    private func fencedCode() -> StartResult? {
        let fenceChar = peek(nextNonspace)
        var index = nextNonspace
        while index < lineEnd, bytes[index] == fenceChar { index += 1 }
        let length = index - nextNonspace
        guard length >= 3 else { return nil }
        let info = NoteMDText.trimmed(bytes[index..<lineEnd])
        if fenceChar == 96, info.contains(96) { return nil }
        closeUnmatchedBlocks()
        let block = addChild(.code)
        block.fenced = true
        block.fenceChar = fenceChar
        block.fenceLength = length
        block.fenceOffset = indent
        block.info = NoteMDText.unescape(info)
        offset = lineEnd
        lineConsumed = true
        return .leaf
    }

    private func setextHeading(_ container: NoteMDBlock) -> StartResult? {
        let underline = peek(nextNonspace)
        var index = nextNonspace
        while index < lineEnd, bytes[index] == underline { index += 1 }
        while index < lineEnd, NoteMDByte.isSpaceOrTab(bytes[index]) { index += 1 }
        guard index >= lineEnd else { return nil }
        closeUnmatchedBlocks()
        let paragraph = container
        let consumed = extractReferences(from: paragraph)
        guard consumed < paragraph.content.count else { return nil }
        if consumed > 0, !Self.startsParagraph(paragraph.content[consumed...]), let parent = paragraph.parent,
           let position = parent.children.firstIndex(where: { $0 === paragraph }) {
            let underline = Array(NoteMDText.trimmed(bytes[nextNonspace..<lineEnd]))
            parent.children[position] = definitionsBlock(paragraph, length: consumed, continuation: paragraph.content[consumed...], closing: underline)
            tip = parent
            offset = lineEnd
            lineConsumed = true
            return .leaf
        }
        let heading = NoteMDBlock(.heading)
        heading.level = underline == 61 ? 1 : 2
        heading.setext = underline
        heading.content = Array(NoteMDText.trimmed(paragraph.content[consumed...]))
        heading.parent = paragraph.parent
        heading.isOpen = false
        if let parent = paragraph.parent, let position = parent.children.firstIndex(where: { $0 === paragraph }) {
            heading.blankBefore = consumed > 0 ? 0 : paragraph.blankBefore
            if consumed > 0 {
                let definitions = definitionsBlock(paragraph, length: consumed)
                parent.children[position] = definitions
                parent.children.insert(heading, at: position + 1)
            } else {
                parent.children[position] = heading
            }
            tip = parent
        }
        offset = lineEnd
        lineConsumed = true
        return .leaf
    }

    private func tableStart(_ container: NoteMDBlock) -> StartResult? {
        let row = Array(bytes[nextNonspace..<lineEnd])
        guard let alignments = NoteMDTableRow.delimiter(row) else { return nil }
        var lines = container.content.split(separator: NoteMDByte.newline, omittingEmptySubsequences: false).map(Array.init)
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        guard let headerLine = lines.last else { return nil }
        let header = NoteMDTableRow.cells(headerLine)
        guard header.count == alignments.count, headerLine.contains(124) || row.contains(124) else { return nil }
        closeUnmatchedBlocks()
        let paragraph = container
        let table = NoteMDBlock(.table)
        table.alignments = alignments
        table.rows = [header]
        table.parent = paragraph.parent
        guard let parent = paragraph.parent, let position = parent.children.firstIndex(where: { $0 === paragraph }) else { return nil }
        if lines.count > 1 {
            paragraph.content = Array(lines.dropLast().joined(separator: [NoteMDByte.newline])) + [NoteMDByte.newline]
            finalize(paragraph)
            parent.children.append(table)
        } else {
            table.blankBefore = paragraph.blankBefore
            parent.children[position] = table
        }
        tip = table
        offset = lineEnd
        lineConsumed = true
        return .leaf
    }

    private func thematicBreak() -> StartResult? {
        let character = peek(nextNonspace)
        var count = 0
        var index = nextNonspace
        while index < lineEnd {
            let byte = bytes[index]
            if byte == character { count += 1 } else if !NoteMDByte.isSpaceOrTab(byte) { return nil }
            index += 1
        }
        guard count >= 3 else { return nil }
        closeUnmatchedBlocks()
        let block = addChild(.thematicBreak)
        block.literal = NoteMDByte.string(NoteMDText.trimmed(bytes[nextNonspace..<lineEnd]))
        finalize(block)
        offset = lineEnd
        lineConsumed = true
        return .leaf
    }

    private func listItem(_ container: NoteMDBlock) -> StartResult? {
        guard indent < 4 else { return nil }
        let first = peek(nextNonspace)
        var ordered = false
        var marker: UInt8 = 0
        var start = 1
        var markerLength = 0
        if first == 42 || first == 43 || first == 45 {
            let after = peek(nextNonspace + 1)
            guard after == 0 || NoteMDByte.isSpaceOrTab(after) else { return nil }
            marker = first
            markerLength = 1
        } else if NoteMDByte.isDigit(first) {
            var index = nextNonspace
            var value = 0
            while index < lineEnd, NoteMDByte.isDigit(bytes[index]), index - nextNonspace < 9 {
                value = value * 10 + Int(bytes[index] - 48)
                index += 1
            }
            guard index < lineEnd, bytes[index] == 46 || bytes[index] == 41 else { return nil }
            let after = peek(index + 1)
            guard after == 0 || NoteMDByte.isSpaceOrTab(after) else { return nil }
            if container.kind == .paragraph, value != 1 { return nil }
            ordered = true
            marker = bytes[index]
            start = value
            markerLength = index + 1 - nextNonspace
        } else {
            return nil
        }
        if container.kind == .paragraph {
            var probe = nextNonspace + markerLength
            while probe < lineEnd, NoteMDByte.isSpaceOrTab(bytes[probe]) { probe += 1 }
            if probe >= lineEnd { return nil }
        }
        let markerOffset = indent
        advanceNextNonspace()
        advanceOffset(markerLength, columns: true)
        let spacesStartColumn = column
        let spacesStartOffset = offset
        repeat {
            advanceOffset(1, columns: true)
        } while column - spacesStartColumn < 5 && NoteMDByte.isSpaceOrTab(peek(offset))
        let blankItem = offset >= lineEnd
        let spacesAfterMarker = column - spacesStartColumn
        var padding: Int
        if spacesAfterMarker >= 5 || spacesAfterMarker < 1 || blankItem {
            padding = markerLength + 1
            column = spacesStartColumn
            offset = spacesStartOffset
            partiallyConsumedTab = false
            if NoteMDByte.isSpaceOrTab(peek(offset)) { advanceOffset(1, columns: true) }
        } else {
            padding = markerLength + spacesAfterMarker
        }
        closeUnmatchedBlocks()
        if tip.kind != .list || tip.ordered != ordered || tip.marker != marker {
            let list = addChild(.list)
            list.ordered = ordered
            list.marker = marker
            list.start = start
        }
        let item = addChild(.item)
        item.ordered = ordered
        item.marker = marker
        item.start = start
        item.markerOffset = markerOffset
        item.padding = padding
        return .container
    }

    private func mathBlock() -> StartResult? {
        guard peek(nextNonspace + 1) == 36 else { return nil }
        let restStart = nextNonspace + 2
        var restEnd = lineEnd
        while restEnd > restStart, NoteMDByte.isSpaceOrTab(bytes[restEnd - 1]) { restEnd -= 1 }
        closeUnmatchedBlocks()
        let block = addChild(.math)
        if restEnd - restStart >= 2, bytes[restEnd - 1] == 36, bytes[restEnd - 2] == 36 {
            let inner = NoteMDText.trimmed(bytes[restStart..<(restEnd - 2)])
            block.content = Array(inner) + [NoteMDByte.newline]
            block.literal = "inline"
            finalize(block)
        } else {
            let first = NoteMDText.trimmed(bytes[restStart..<restEnd])
            if !first.isEmpty {
                block.content = Array(first) + [NoteMDByte.newline]
                block.literal = "opening"
            }
        }
        offset = lineEnd
        lineConsumed = true
        return .leaf
    }

    private func directive() -> StartResult? {
        var index = nextNonspace
        while index < lineEnd, bytes[index] == 58 { index += 1 }
        guard index - nextNonspace >= 3 else { return nil }
        let rest = NoteMDByte.string(NoteMDText.trimmed(bytes[index..<lineEnd]))
        guard let (name, width) = NoteMDDirective.parse(rest) else { return nil }
        closeUnmatchedBlocks()
        let block = addChild(.directive)
        block.directiveName = name
        block.directiveWidth = width
        block.literal = NoteMDByte.string(bytes[nextNonspace..<index])
        offset = lineEnd
        lineConsumed = true
        return .container
    }

    private func footnoteDefinition() -> StartResult? {
        guard peek(nextNonspace + 1) == 94 else { return nil }
        var index = nextNonspace + 2
        while index < lineEnd, bytes[index] != 93, !NoteMDByte.isWhitespace(bytes[index]) { index += 1 }
        guard index > nextNonspace + 2, index + 1 < lineEnd + 1, peek(index) == 93, peek(index + 1) == 58 else { return nil }
        let label = NoteMDText.normalizeLabel(NoteMDByte.string(bytes[(nextNonspace + 2)..<index]))
        closeUnmatchedBlocks()
        let block = addChild(.footnote)
        block.rawLines.append(remainderBytes())
        footnotes.insert(label)
        advanceNextNonspace()
        advanceOffset(index + 2 - nextNonspace, columns: false)
        return .container
    }

    private func extractReferences(from paragraph: NoteMDBlock) -> Int {
        var position = 0
        let content = paragraph.content
        while position < content.count, content[position] == 91,
              let (label, reference, end) = NoteMDScan.reference(content, from: position, upTo: content.count) {
            if references[label] == nil { references[label] = reference }
            position = end
        }
        return position
    }

    private func definitionsBlock(_ paragraph: NoteMDBlock, length: Int, continuation: ArraySlice<UInt8> = [], closing: [UInt8] = []) -> NoteMDBlock {
        let block = NoteMDBlock(.definitions)
        block.parent = paragraph.parent
        block.isOpen = false
        block.blankBefore = paragraph.blankBefore
        var text = Array(paragraph.content[0..<length])
        while let last = text.last, NoteMDByte.isWhitespace(last) { text.removeLast() }
        for line in continuation.split(separator: NoteMDByte.newline) {
            text.append(NoteMDByte.newline)
            text.append(contentsOf: repeatElement(NoteMDByte.space, count: 4))
            text.append(contentsOf: line)
        }
        if !closing.isEmpty {
            text.append(NoteMDByte.newline)
            text.append(contentsOf: closing)
        }
        block.content = text
        return block
    }

    static func startsParagraph(_ content: ArraySlice<UInt8>) -> Bool {
        let firstLine = content.prefix { $0 != NoteMDByte.newline }
        let document = NoteMDBlockParser.parse(Array(firstLine))
        return document.root.children.count == 1 && document.root.children[0].kind == .paragraph
    }

    private func finalize(_ block: NoteMDBlock) {
        guard block.isOpen else {
            if tip === block, let parent = block.parent { tip = parent }
            return
        }
        block.isOpen = false
        let parent = block.parent
        switch block.kind {
        case .paragraph:
            let consumed = extractReferences(from: block)
            if consumed > 0, let parent, let position = parent.children.firstIndex(where: { $0 === block }) {
                if consumed >= block.content.count || NoteMDText.trimmed(block.content[consumed...]).isEmpty {
                    parent.children[position] = definitionsBlock(block, length: consumed)
                } else if !Self.startsParagraph(block.content[consumed...]) {
                    parent.children[position] = definitionsBlock(block, length: consumed, continuation: block.content[consumed...])
                } else {
                    let definitions = definitionsBlock(block, length: consumed)
                    block.content = Array(block.content[consumed...])
                    block.blankBefore = 0
                    parent.children.insert(definitions, at: position)
                }
            }
        case .code:
            if !block.fenced {
                var lines = block.content.split(separator: NoteMDByte.newline, omittingEmptySubsequences: false).map(Array.init)
                if let last = lines.last, last.isEmpty { lines.removeLast() }
                var trailing = 0
                while let last = lines.last, last.allSatisfy(NoteMDByte.isSpaceOrTab) { lines.removeLast(); trailing += 1 }
                block.content = Array(lines.joined(separator: [NoteMDByte.newline]))
                parent?.pendingBlank += trailing
            } else if block.content.last == NoteMDByte.newline {
                block.content.removeLast()
            }
        case .html, .math:
            if block.content.last == NoteMDByte.newline { block.content.removeLast() }
            if block.kind == .html {
                let leading = block.content.prefix(while: NoteMDByte.isSpaceOrTab).count
                block.content.removeFirst(leading)
            }
        case .item:
            block.trailingBlank = block.pendingBlank
            block.pendingBlank = 0
        case .list:
            let items = block.children
            for (index, item) in items.enumerated() {
                if index > 0, item.blankBefore > 0 { block.loose = true }
                if index < items.count - 1, item.trailingBlank > 0 { block.loose = true }
            }
            parent?.pendingBlank += (items.last?.trailingBlank ?? 0) + block.pendingBlank
            block.pendingBlank = 0
        case .footnote:
            if var first = block.rawLines.first {
                while first.first == NoteMDByte.space || first.first == NoteMDByte.tab { first.removeFirst() }
                block.rawLines[0] = first
            }
            var trailing = 0
            while let last = block.rawLines.last, last.allSatisfy(NoteMDByte.isSpaceOrTab) { block.rawLines.removeLast(); trailing += 1 }
            parent?.pendingBlank += max(trailing, block.pendingBlank)
            block.pendingBlank = 0
        case .document, .quote, .directive:
            block.trailingBlank = block.pendingBlank
            block.pendingBlank = 0
        default:
            break
        }
        if tip === block, let parent { tip = parent }
    }
}

enum NoteMDTableRow {
    static func cells(_ line: [UInt8]) -> [[UInt8]] {
        var trimmed = Array(NoteMDText.trimmed(line[...]))
        if trimmed.first == 124 { trimmed.removeFirst() }
        if trimmed.last == 124, !(trimmed.count >= 2 && trimmed[trimmed.count - 2] == 92) { trimmed.removeLast() }
        var cells: [[UInt8]] = []
        var current: [UInt8] = []
        var index = 0
        while index < trimmed.count {
            let byte = trimmed[index]
            if byte == 92, index + 1 < trimmed.count, trimmed[index + 1] == 124 {
                current.append(124)
                index += 2
                continue
            }
            if byte == 92, index + 1 < trimmed.count {
                current.append(byte)
                current.append(trimmed[index + 1])
                index += 2
                continue
            }
            if byte == 124 {
                cells.append(Array(NoteMDText.trimmed(current[...])))
                current = []
            } else {
                current.append(byte)
            }
            index += 1
        }
        cells.append(Array(NoteMDText.trimmed(current[...])))
        return cells
    }

    static func delimiter(_ line: [UInt8]) -> [NoteAlignment?]? {
        var alignments: [NoteAlignment?] = []
        let raw = cellsRaw(line)
        guard !raw.isEmpty else { return nil }
        for cell in raw {
            guard !cell.isEmpty else { return nil }
            var body = cell[...]
            let left = body.first == 58
            if left { body = body.dropFirst() }
            let right = body.last == 58
            if right { body = body.dropLast() }
            guard !body.isEmpty, body.allSatisfy({ $0 == 45 }) else { return nil }
            alignments.append(left && right ? .center : left ? .left : right ? .right : nil)
        }
        return alignments
    }

    private static func cellsRaw(_ line: [UInt8]) -> [[UInt8]] {
        var trimmed = Array(NoteMDText.trimmed(line[...]))
        if trimmed.first == 124 { trimmed.removeFirst() }
        if trimmed.last == 124 { trimmed.removeLast() }
        return trimmed.split(separator: 124, omittingEmptySubsequences: false).map { Array(NoteMDText.trimmed($0)) }
    }
}

enum NoteMDDirective {
    static let indent = "indent"
    static let names: Set<String> = ["columns", "column", indent]

    static func parse(_ rest: String) -> (String, Double?)? {
        let lowered = rest.lowercased()
        if names.contains(lowered) { return (lowered, nil) }
        guard rest.hasPrefix("{"), rest.hasSuffix("}") else { return nil }
        let inner = rest.dropFirst().dropLast()
        var name: String?
        var width: Double?
        for token in tokens(String(inner)) {
            if token.hasPrefix(".") {
                let value = token.dropFirst().lowercased()
                if names.contains(value) { name = value } else { return nil }
            } else if token.lowercased().hasPrefix("width=") {
                var value = String(token.dropFirst(6))
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
                guard value.hasSuffix("%"), let ratio = ratio(fromPercent: String(value.dropLast())) else { return nil }
                width = ratio
            } else {
                return nil
            }
        }
        guard let name else { return nil }
        return (name, name == "column" ? width : nil)
    }

    static func ratio(fromPercent text: String) -> Double? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), text.filter({ $0 == "." }).count <= 1 else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        var whole = String(parts[0])
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        while whole.count < 3 { whole = "0" + whole }
        let shifted = String(whole.dropLast(2)) + "." + String(whole.suffix(2)) + fraction
        return Double(shifted)
    }

    static func percent(fromRatio ratio: Double) -> String {
        var text = "\(ratio)"
        if text.contains("e") || text.contains("E") { text = String(format: "%.17f", ratio) }
        let negative = text.hasPrefix("-")
        if negative { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0])
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        while fraction.count < 2 { fraction += "0" }
        var integer = whole + String(fraction.prefix(2))
        while integer.count > 1, integer.hasPrefix("0") { integer.removeFirst() }
        var rest = String(fraction.dropFirst(2))
        while rest.hasSuffix("0") { rest.removeLast() }
        return (negative ? "-" : "") + integer + (rest.isEmpty ? "" : "." + rest)
    }

    private static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if character == "\"" { quoted.toggle() }
            if character == " " && !quoted {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
