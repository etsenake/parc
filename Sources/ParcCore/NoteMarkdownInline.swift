import Foundation

struct NoteMDInlineNode {
    enum Kind { case root, text, softBreak, hardBreak, code, emphasis, strong, strike, highlight, link, image, html, math, rawSource, wiki, autolink }

    var kind: Kind
    var literal = ""
    var destination = ""
    var title: String?
    var decoded = false
    var sourceStart = 0
    var sourceEnd = 0
    var parent = -1
    var first = -1
    var last = -1
    var next = -1
    var previous = -1
}

struct NoteMDInlineTree {
    var nodes: [NoteMDInlineNode]
    var source: [UInt8]

    func children(of index: Int) -> [Int] {
        var result: [Int] = []
        var child = nodes[index].first
        while child != -1 {
            result.append(child)
            child = nodes[child].next
        }
        return result
    }

    func source(of index: Int) -> String {
        let node = nodes[index]
        guard node.sourceEnd > node.sourceStart, node.sourceEnd <= source.count else { return node.literal }
        return NoteMDByte.string(source[node.sourceStart..<node.sourceEnd])
    }

    func plainText(of index: Int) -> String {
        var result = ""
        func walk(_ node: Int, _ depth: Int = 0) {
            let value = nodes[node]
            guard depth <= NoteMDReader.maximumInlineDepth else { return }
            switch value.kind {
            case .text, .code, .autolink, .math: result += value.literal
            case .softBreak, .hardBreak: result += " "
            case .wiki: result += value.title ?? value.destination
            default: break
            }
            var child = value.first
            while child != -1 {
                walk(child, depth + 1)
                child = nodes[child].next
            }
        }
        walk(index)
        return result
    }
}

final class NoteMDInlineParser {
    private struct Delimiter {
        var node: Int
        var character: UInt8
        var count: Int
        var original: Int
        var canOpen: Bool
        var canClose: Bool
        var previous: Int
        var next: Int
    }

    private struct Bracket {
        var node: Int
        var previous: Int
        var previousDelimiter: Int
        var index: Int
        var sourceStart: Int
        var image: Bool
        var active: Bool
        var bracketAfter: Bool
    }

    private let bytes: [UInt8]
    private let end: Int
    private let references: [String: NoteMDLinkReference]
    private let footnotes: Set<String>
    private var nodes: [NoteMDInlineNode] = [NoteMDInlineNode(kind: .root)]
    private var position = 0
    private var delimiters: [Delimiter] = []
    private var topDelimiter = -1
    private var brackets: [Bracket] = []
    private var topBracket = -1
    private var pending: [UInt8] = []
    private var trailingLiteralWhitespace = 0
    private var trailingLiteralSpaces = 0
    private var backtickRuns: [Int: [Int]]?
    private var backtickCursor: [Int: Int] = [:]

    init(_ bytes: [UInt8], references: [String: NoteMDLinkReference], footnotes: Set<String>) {
        self.bytes = bytes
        end = bytes.count
        self.references = references
        self.footnotes = footnotes
    }

    static func parse(_ bytes: [UInt8], references: [String: NoteMDLinkReference] = [:], footnotes: Set<String> = []) -> NoteMDInlineTree {
        var content = bytes[...]
        while let first = content.first, NoteMDByte.isWhitespace(first) { content = content.dropFirst() }
        while let last = content.last, NoteMDByte.isWhitespace(last) { content = content.dropLast() }
        let parser = NoteMDInlineParser(Array(content), references: references, footnotes: footnotes)
        return parser.run()
    }

    static func parseVerbatim(_ bytes: [UInt8], references: [String: NoteMDLinkReference] = [:], footnotes: Set<String> = []) -> NoteMDInlineTree {
        NoteMDInlineParser(bytes, references: references, footnotes: footnotes).run()
    }

    private func run() -> NoteMDInlineTree {
        while position < end { step() }
        flush()
        processEmphasis(-1)
        return NoteMDInlineTree(nodes: nodes, source: bytes)
    }

    private func append(_ node: NoteMDInlineNode) -> Int {
        var value = node
        let index = nodes.count
        value.parent = 0
        value.previous = nodes[0].last
        value.next = -1
        nodes.append(value)
        if nodes[0].last != -1 { nodes[nodes[0].last].next = index } else { nodes[0].first = index }
        nodes[0].last = index
        return index
    }

    private func appendText(_ text: String, sourceStart: Int = 0, sourceEnd: Int = 0) -> Int {
        flush()
        var node = NoteMDInlineNode(kind: .text, literal: text)
        node.sourceStart = sourceStart
        node.sourceEnd = sourceEnd
        return append(node)
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        let text = NoteMDByte.string(pending)
        pending.removeAll(keepingCapacity: true)
        trailingLiteralWhitespace = 0
        trailingLiteralSpaces = 0
        _ = append(NoteMDInlineNode(kind: .text, literal: text))
    }

    private func pendingLiteral(_ byte: UInt8) {
        pending.append(byte)
        if byte == NoteMDByte.space {
            trailingLiteralWhitespace += 1
            trailingLiteralSpaces += 1
        } else if byte == NoteMDByte.tab {
            trailingLiteralWhitespace += 1
            trailingLiteralSpaces = 0
        } else {
            trailingLiteralWhitespace = 0
            trailingLiteralSpaces = 0
        }
    }

    private func pendingDecoded(_ text: String) {
        pending.append(contentsOf: Array(text.utf8))
        trailingLiteralWhitespace = 0
        trailingLiteralSpaces = 0
    }

    private func unlink(_ index: Int) {
        let node = nodes[index]
        if node.previous != -1 { nodes[node.previous].next = node.next } else if node.parent != -1 { nodes[node.parent].first = node.next }
        if node.next != -1 { nodes[node.next].previous = node.previous } else if node.parent != -1 { nodes[node.parent].last = node.previous }
        nodes[index].parent = -1
        nodes[index].next = -1
        nodes[index].previous = -1
    }

    private func insertAfter(_ anchor: Int, _ index: Int) {
        let parent = nodes[anchor].parent
        let following = nodes[anchor].next
        nodes[index].parent = parent
        nodes[index].previous = anchor
        nodes[index].next = following
        nodes[anchor].next = index
        if following != -1 { nodes[following].previous = index } else if parent != -1 { nodes[parent].last = index }
    }

    private func appendChild(_ parent: Int, _ index: Int) {
        nodes[index].parent = parent
        nodes[index].next = -1
        nodes[index].previous = nodes[parent].last
        if nodes[parent].last != -1 { nodes[nodes[parent].last].next = index } else { nodes[parent].first = index }
        nodes[parent].last = index
    }

    private func isBoundary(before index: Int) -> Bool {
        guard index > 0 else { return true }
        let byte = bytes[index - 1]
        return NoteMDByte.isWhitespace(byte) || byte == 42 || byte == 95 || byte == 126 || byte == 40
    }

    private func step() {
        let byte = bytes[position]
        switch byte {
        case NoteMDByte.newline: lineBreak(hard: false)
        case 92: backslash()
        case 96: backticks()
        case 42, 95, 126, 61: delimiterRun(byte)
        case 33:
            if position + 1 < end, bytes[position + 1] == 91 {
                if position + 2 < end, bytes[position + 2] == 91, let close = wikiClose(from: position + 3) {
                    flush()
                    var node = NoteMDInlineNode(kind: .rawSource, literal: NoteMDByte.string(bytes[position..<(close + 2)]))
                    node.sourceStart = position
                    node.sourceEnd = close + 2
                    _ = append(node)
                    position = close + 2
                } else {
                    openBracket(image: true)
                }
            } else {
                pendingLiteral(byte)
                position += 1
            }
        case 91: leftBracket()
        case 93: closeBracket()
        case 60: angle()
        case 38:
            if let (decoded, length) = NoteMDEntities.decode(bytes, at: position) {
                flush()
                var node = NoteMDInlineNode(kind: .text, literal: decoded)
                node.decoded = true
                _ = append(node)
                position += length
            } else {
                pendingLiteral(byte)
                position += 1
            }
        case 36: dollar()
        case 64: email()
        case 104, 72, 119, 87:
            if isBoundary(before: position), let (destination, length) = extendedAutolink(at: position) {
                flush()
                var node = NoteMDInlineNode(kind: .autolink, literal: NoteMDByte.string(bytes[position..<(position + length)]))
                node.destination = destination
                _ = append(node)
                position += length
            } else {
                pendingLiteral(byte)
                position += 1
            }
        default:
            var index = position
            while index < end {
                let value = bytes[index]
                if isSpecial(value) { break }
                index += 1
            }
            if index == position { index += 1 }
            for offset in position..<index { pendingLiteral(bytes[offset]) }
            position = index
        }
    }

    private func isSpecial(_ byte: UInt8) -> Bool {
        switch byte {
        case NoteMDByte.newline, 92, 96, 42, 95, 126, 61, 33, 91, 93, 60, 38, 36, 64, 104, 72, 119, 87: return true
        default: return false
        }
    }

    private func lineBreak(hard: Bool) {
        let isHard = hard || trailingLiteralSpaces >= 2
        if trailingLiteralWhitespace > 0 {
            pending.removeLast(min(trailingLiteralWhitespace, pending.count))
        }
        flush()
        _ = append(NoteMDInlineNode(kind: isHard ? .hardBreak : .softBreak))
        position += 1
        while position < end, NoteMDByte.isSpaceOrTab(bytes[position]) { position += 1 }
    }

    private func backslash() {
        if position + 1 < end {
            let next = bytes[position + 1]
            if next == NoteMDByte.newline {
                position += 1
                lineBreak(hard: true)
                return
            }
            if NoteMDByte.isPunctuation(next) {
                pendingDecoded(String(UnicodeScalar(next)))
                position += 2
                return
            }
        }
        pendingLiteral(92)
        position += 1
    }

    private func backticks() {
        let start = position
        var index = position
        while index < end, bytes[index] == 96 { index += 1 }
        let length = index - start
        if backtickRuns == nil {
            var runs: [Int: [Int]] = [:]
            var probe = 0
            while probe < end {
                if bytes[probe] == 96 {
                    let runStart = probe
                    while probe < end, bytes[probe] == 96 { probe += 1 }
                    runs[probe - runStart, default: []].append(runStart)
                } else {
                    probe += 1
                }
            }
            backtickRuns = runs
        }
        if let candidates = backtickRuns?[length] {
            var cursor = backtickCursor[length] ?? 0
            while cursor < candidates.count, candidates[cursor] < index { cursor += 1 }
            backtickCursor[length] = cursor
            if cursor < candidates.count {
                let close = candidates[cursor]
                var content = Array(bytes[index..<close])
                for offset in content.indices where content[offset] == NoteMDByte.newline { content[offset] = NoteMDByte.space }
                if content.count >= 2, content.first == NoteMDByte.space, content.last == NoteMDByte.space,
                   content.contains(where: { $0 != NoteMDByte.space }) {
                    content.removeFirst()
                    content.removeLast()
                }
                flush()
                var node = NoteMDInlineNode(kind: .code, literal: NoteMDByte.string(content))
                node.sourceStart = start
                node.sourceEnd = close + length
                _ = append(node)
                position = close + length
                return
            }
        }
        for _ in 0..<length { pendingLiteral(96) }
        position = index
    }

    private func delimiterRun(_ character: UInt8) {
        let start = position
        var index = position
        while index < end, bytes[index] == character { index += 1 }
        let count = index - start
        if (character == 126 && count > 2) || (character == 61 && count != 2) {
            for _ in 0..<count { pendingLiteral(character) }
            position = index
            return
        }
        let before = NoteMDByte.scalar(endingBefore: start, in: bytes)
        let after = NoteMDByte.scalar(startingAt: index, in: bytes, upperBound: end)
        let beforeWhitespace = NoteMDByte.isUnicodeWhitespace(before)
        let afterWhitespace = NoteMDByte.isUnicodeWhitespace(after)
        let beforePunctuation = NoteMDByte.isUnicodePunctuation(before)
        let afterPunctuation = NoteMDByte.isUnicodePunctuation(after)
        let leftFlanking = !afterWhitespace && (!afterPunctuation || beforeWhitespace || beforePunctuation)
        let rightFlanking = !beforeWhitespace && (!beforePunctuation || afterWhitespace || afterPunctuation)
        let canOpen: Bool, canClose: Bool
        if character == 95 {
            canOpen = leftFlanking && (!rightFlanking || beforePunctuation)
            canClose = rightFlanking && (!leftFlanking || afterPunctuation)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        let node = appendText(NoteMDByte.string(bytes[start..<index]))
        position = index
        guard canOpen || canClose else { return }
        let delimiter = Delimiter(node: node, character: character, count: count, original: count, canOpen: canOpen,
                                  canClose: canClose, previous: topDelimiter, next: -1)
        delimiters.append(delimiter)
        let added = delimiters.count - 1
        if topDelimiter != -1 { delimiters[topDelimiter].next = added }
        topDelimiter = added
    }

    private func removeDelimiter(_ index: Int) {
        let delimiter = delimiters[index]
        if delimiter.previous != -1 { delimiters[delimiter.previous].next = delimiter.next }
        if delimiter.next != -1 { delimiters[delimiter.next].previous = delimiter.previous } else { topDelimiter = delimiter.previous }
    }

    private func processEmphasis(_ stackBottom: Int) {
        var openersBottom: [Int: Int] = [:]
        var closer = topDelimiter
        while closer != -1, delimiters[closer].previous != stackBottom { closer = delimiters[closer].previous }
        while closer != -1 {
            let current = delimiters[closer]
            guard current.canClose else {
                closer = current.next
                continue
            }
            let key = Int(current.character) * 8 + (current.canOpen ? 3 : 0) + current.original % 3
            let bottom = openersBottom[key] ?? stackBottom
            var opener = current.previous
            var found = false
            while opener != -1, opener != stackBottom, opener != bottom {
                let candidate = delimiters[opener]
                if candidate.character == current.character, candidate.canOpen {
                    if current.character == 42 || current.character == 95 {
                        let oddMatch = (current.canOpen || candidate.canClose) && current.original % 3 != 0
                            && (candidate.original + current.original) % 3 == 0
                        if !oddMatch { found = true; break }
                    } else if candidate.count == current.count {
                        found = true
                        break
                    }
                }
                opener = candidate.previous
            }
            if found {
                let openerValue = delimiters[opener]
                let used: Int
                let kind: NoteMDInlineNode.Kind
                switch current.character {
                case 126:
                    used = current.count
                    kind = .strike
                case 61:
                    used = 2
                    kind = .highlight
                default:
                    used = current.count >= 2 && openerValue.count >= 2 ? 2 : 1
                    kind = used == 2 ? .strong : .emphasis
                }
                delimiters[opener].count -= used
                delimiters[closer].count -= used
                let openerNode = openerValue.node, closerNode = current.node
                nodes[openerNode].literal = String(nodes[openerNode].literal.dropLast(used))
                nodes[closerNode].literal = String(nodes[closerNode].literal.dropLast(used))
                nodes.append(NoteMDInlineNode(kind: kind))
                let wrapper = nodes.count - 1
                var child = nodes[openerNode].next
                while child != -1, child != closerNode {
                    let following = nodes[child].next
                    unlink(child)
                    appendChild(wrapper, child)
                    child = following
                }
                insertAfter(openerNode, wrapper)
                var between = delimiters[closer].previous
                while between != -1, between != opener {
                    let previous = delimiters[between].previous
                    removeDelimiter(between)
                    between = previous
                }
                if delimiters[opener].count == 0 {
                    unlink(openerNode)
                    removeDelimiter(opener)
                }
                if delimiters[closer].count == 0 {
                    let following = delimiters[closer].next
                    unlink(closerNode)
                    removeDelimiter(closer)
                    closer = following
                }
            } else {
                openersBottom[key] = current.previous
                let following = current.next
                if !current.canOpen { removeDelimiter(closer) }
                closer = following
            }
        }
        while topDelimiter != -1, topDelimiter != stackBottom { removeDelimiter(topDelimiter) }
    }

    private func wikiClose(from start: Int) -> Int? {
        var index = start
        while index + 1 < end {
            let byte = bytes[index]
            if byte == 93 { return bytes[index + 1] == 93 && index > start ? index : nil }
            if byte == 91 || byte == NoteMDByte.newline { return nil }
            index += 1
        }
        return nil
    }

    private func leftBracket() {
        if position + 1 < end, bytes[position + 1] == 91, let close = wikiClose(from: position + 2) {
            let inner = NoteMDByte.string(bytes[(position + 2)..<close])
            let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let target = parts[0].trimmingCharacters(in: .whitespaces)
            if !target.isEmpty {
                flush()
                var node = NoteMDInlineNode(kind: .wiki, literal: inner)
                node.destination = target
                node.title = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
                node.sourceStart = position
                node.sourceEnd = close + 2
                _ = append(node)
                position = close + 2
                return
            }
        }
        if position + 1 < end, bytes[position + 1] == 94 {
            var index = position + 2
            while index < end, bytes[index] != 93, bytes[index] != 91, !NoteMDByte.isWhitespace(bytes[index]) { index += 1 }
            if index < end, bytes[index] == 93, index > position + 2,
               footnotes.contains(NoteMDText.normalizeLabel(NoteMDByte.string(bytes[(position + 2)..<index]))) {
                flush()
                var node = NoteMDInlineNode(kind: .rawSource, literal: NoteMDByte.string(bytes[position...index]))
                node.sourceStart = position
                node.sourceEnd = index + 1
                _ = append(node)
                position = index + 1
                return
            }
        }
        openBracket(image: false)
    }

    private func openBracket(image: Bool) {
        let start = position
        let length = image ? 2 : 1
        let node = appendText(image ? "![" : "[", sourceStart: start, sourceEnd: start + length)
        position += length
        if topBracket != -1 { brackets[topBracket].bracketAfter = true }
        brackets.append(Bracket(node: node, previous: topBracket, previousDelimiter: topDelimiter, index: position,
                                sourceStart: start, image: image, active: true, bracketAfter: false))
        topBracket = brackets.count - 1
    }

    private func removeBracket() {
        topBracket = brackets[topBracket].previous
    }

    private func skipSpacesAndNewline(_ start: Int) -> Int {
        var index = start
        while index < end, NoteMDByte.isSpaceOrTab(bytes[index]) { index += 1 }
        if index < end, bytes[index] == NoteMDByte.newline {
            index += 1
            while index < end, NoteMDByte.isSpaceOrTab(bytes[index]) { index += 1 }
        }
        return index
    }

    private func closeBracket() {
        let closeStart = position
        position += 1
        guard topBracket != -1 else {
            _ = appendText("]")
            return
        }
        let opener = brackets[topBracket]
        guard opener.active else {
            removeBracket()
            _ = appendText("]")
            return
        }
        let afterClose = position
        var matched = false
        var destination = ""
        var title: String?
        if position < end, bytes[position] == 40 {
            let destinationStart = skipSpacesAndNewline(position + 1)
            if let (value, destinationEnd) = NoteMDScan.linkDestination(bytes, from: destinationStart, upTo: end) {
                var index = destinationEnd
                let beforeTitle = index
                index = skipSpacesAndNewline(index)
                if index > beforeTitle, let (titleValue, titleEnd) = NoteMDScan.linkTitle(bytes, from: index, upTo: end) {
                    title = titleValue
                    index = skipSpacesAndNewline(titleEnd)
                } else {
                    index = skipSpacesAndNewline(beforeTitle)
                }
                if index < end, bytes[index] == 41 {
                    destination = value
                    position = index + 1
                    matched = true
                } else {
                    title = nil
                }
            }
            if !matched { position = afterClose }
        }
        if !matched {
            var length = 0
            if let labelEnd = NoteMDScan.linkLabel(bytes, from: position, upTo: end) {
                length = labelEnd - position
            } else if position + 1 < end, bytes[position] == 91, bytes[position + 1] == 93 {
                length = 2
            }
            var label: String?
            if length > 2 {
                label = NoteMDByte.string(bytes[(position + 1)..<(position + length - 1)])
            } else if !opener.bracketAfter {
                label = NoteMDByte.string(bytes[opener.index..<closeStart])
            }
            position += length
            if let label, let reference = references[NoteMDText.normalizeLabel(label)] {
                destination = reference.destination
                title = reference.title
                matched = true
            } else {
                position = afterClose
            }
        }
        guard matched else {
            removeBracket()
            position = afterClose
            _ = appendText("]")
            return
        }
        flush()
        var link = NoteMDInlineNode(kind: opener.image ? .image : .link)
        link.destination = destination
        link.title = title
        link.sourceStart = opener.sourceStart
        link.sourceEnd = position
        nodes.append(link)
        let linkIndex = nodes.count - 1
        var child = nodes[opener.node].next
        while child != -1 {
            let following = nodes[child].next
            unlink(child)
            appendChild(linkIndex, child)
            child = following
        }
        appendChild(0, linkIndex)
        processEmphasis(opener.previousDelimiter)
        removeBracket()
        unlink(opener.node)
        if !opener.image {
            var index = topBracket
            while index != -1 {
                if !brackets[index].image { brackets[index].active = false }
                index = brackets[index].previous
            }
        }
    }

    private func angle() {
        if let (destination, text, length) = autolink(at: position) {
            flush()
            var node = NoteMDInlineNode(kind: .autolink, literal: text)
            node.destination = destination
            node.sourceStart = position
            node.sourceEnd = position + length
            _ = append(node)
            position += length
            return
        }
        if let htmlEnd = NoteMDHTML.inlineHTML(bytes, from: position, upTo: end) {
            flush()
            var node = NoteMDInlineNode(kind: .html, literal: NoteMDByte.string(bytes[position..<htmlEnd]))
            node.sourceStart = position
            node.sourceEnd = htmlEnd
            _ = append(node)
            position = htmlEnd
            return
        }
        pendingLiteral(60)
        position += 1
    }

    private func autolink(at start: Int) -> (String, String, Int)? {
        var index = start + 1
        guard index < end, NoteMDByte.isLetter(bytes[index]) else { return emailAutolink(at: start) }
        let schemeStart = index
        while index < end, NoteMDByte.isAlphanumeric(bytes[index]) || bytes[index] == 43 || bytes[index] == 46 || bytes[index] == 45 { index += 1 }
        let schemeLength = index - schemeStart
        if schemeLength >= 2, schemeLength <= 32, index < end, bytes[index] == 58 {
            index += 1
            while index < end {
                let byte = bytes[index]
                if byte == 62 {
                    let text = NoteMDByte.string(bytes[(start + 1)..<index])
                    return (text, text, index + 1 - start)
                }
                if byte <= 32 || byte == 60 || byte == 127 { break }
                index += 1
            }
        }
        return emailAutolink(at: start)
    }

    private func emailAutolink(at start: Int) -> (String, String, Int)? {
        var index = start + 1
        let localStart = index
        while index < end {
            let byte = bytes[index]
            if NoteMDByte.isAlphanumeric(byte) || ".!#$%&'*+/=?^_`{|}~-".utf8.contains(byte) { index += 1 } else { break }
        }
        guard index > localStart, index < end, bytes[index] == 64 else { return nil }
        index += 1
        var labelLength = 0
        while index < end {
            let byte = bytes[index]
            if NoteMDByte.isAlphanumeric(byte) || (byte == 45 && labelLength > 0) {
                labelLength += 1
                if labelLength > 63 { return nil }
                index += 1
            } else if byte == 46, labelLength > 0, bytes[index - 1] != 45 {
                labelLength = 0
                index += 1
            } else if byte == 62, labelLength > 0, bytes[index - 1] != 45 {
                let text = NoteMDByte.string(bytes[(start + 1)..<index])
                return ("mailto:" + text, text, index + 1 - start)
            } else {
                return nil
            }
        }
        return nil
    }

    private func dollar() {
        let start = position
        var index = position
        while index < end, bytes[index] == 36 { index += 1 }
        let count = index - start
        if count == 2 {
            var probe = index
            while probe + 1 < end {
                if bytes[probe] == 92 { probe += 2; continue }
                if bytes[probe] == 36, bytes[probe + 1] == 36 {
                    if probe > index {
                        flush()
                        var node = NoteMDInlineNode(kind: .rawSource, literal: NoteMDByte.string(bytes[start..<(probe + 2)]))
                        node.sourceStart = start
                        node.sourceEnd = probe + 2
                        _ = append(node)
                        position = probe + 2
                        return
                    }
                    break
                }
                probe += 1
            }
        } else if count == 1, index < end, !NoteMDByte.isWhitespace(bytes[index]) {
            var probe = index
            while probe < end {
                let byte = bytes[probe]
                if byte == 92, probe + 1 < end { probe += 2; continue }
                if byte == 36 { break }
                probe += 1
            }
            if probe < end, probe > index, !NoteMDByte.isWhitespace(bytes[probe - 1]),
               probe + 1 >= end || (!NoteMDByte.isDigit(bytes[probe + 1]) && bytes[probe + 1] != 36) {
                flush()
                var node = NoteMDInlineNode(kind: .math, literal: NoteMDByte.string(bytes[index..<probe]))
                node.sourceStart = start
                node.sourceEnd = probe + 1
                _ = append(node)
                position = probe + 1
                return
            }
        }
        for _ in 0..<count { pendingLiteral(36) }
        position = index
    }

    private func email() {
        var localStart = pending.count
        while localStart > 0 {
            let byte = pending[localStart - 1]
            if NoteMDByte.isAlphanumeric(byte) || byte == 46 || byte == 43 || byte == 95 || byte == 45 { localStart -= 1 } else { break }
        }
        let localLength = pending.count - localStart
        let precededByBoundary = localStart == 0 ? true : !(pending[localStart - 1] >= 0x80 || NoteMDByte.isAlphanumeric(pending[localStart - 1]) || pending[localStart - 1] == 47)
        if localLength > 0, precededByBoundary, let domainLength = emailDomain(at: position + 1) {
            let local = Array(pending[localStart...])
            pending.removeLast(localLength)
            flush()
            let text = NoteMDByte.string(local) + "@" + NoteMDByte.string(bytes[(position + 1)..<(position + 1 + domainLength)])
            var node = NoteMDInlineNode(kind: .autolink, literal: text)
            node.destination = "mailto:" + text
            _ = append(node)
            position += 1 + domainLength
            return
        }
        pendingLiteral(64)
        position += 1
    }

    private func emailDomain(at start: Int) -> Int? {
        var index = start
        var periods = 0
        while index < end {
            let byte = bytes[index]
            if NoteMDByte.isAlphanumeric(byte) || byte == 45 || byte == 95 {
                index += 1
            } else if byte == 46, index + 1 < end, NoteMDByte.isAlphanumeric(bytes[index + 1]) || bytes[index + 1] == 45 || bytes[index + 1] == 95, index > start {
                periods += 1
                index += 1
            } else {
                break
            }
        }
        guard periods > 0, index > start else { return nil }
        let last = bytes[index - 1]
        guard last != 45, last != 95 else { return nil }
        return index - start
    }

    func extendedAutolink(at start: Int) -> (String, Int)? {
        NoteMDAutolink.extended(bytes, at: start, upTo: end)
    }
}

enum NoteMDAutolink {
    static func extended(_ bytes: [UInt8], at start: Int, upTo end: Int) -> (String, Int)? {
        var domainStart: Int
        var prefix = ""
        if NoteMDHTML.matches(bytes, at: start, upTo: end, ascii: "www.", caseInsensitive: true) {
            domainStart = start
            prefix = "http://"
        } else if NoteMDHTML.matches(bytes, at: start, upTo: end, ascii: "https://", caseInsensitive: true) {
            domainStart = start + 8
        } else if NoteMDHTML.matches(bytes, at: start, upTo: end, ascii: "http://", caseInsensitive: true) {
            domainStart = start + 7
        } else {
            return nil
        }
        var index = domainStart
        var segments: [(Int, Int)] = []
        var segmentStart = index
        while index < end {
            let byte = bytes[index]
            if NoteMDByte.isAlphanumeric(byte) || byte == 45 || byte == 95 || byte >= 0x80 {
                index += 1
            } else if byte == 46 {
                segments.append((segmentStart, index))
                index += 1
                segmentStart = index
            } else {
                break
            }
        }
        segments.append((segmentStart, index))
        let nonEmpty = segments.filter { $0.1 > $0.0 }
        guard nonEmpty.count >= 2 else { return nil }
        for (lower, upper) in nonEmpty.suffix(2) where bytes[lower..<upper].contains(95) { return nil }
        var linkEnd = index
        while linkEnd < end, !NoteMDByte.isWhitespace(bytes[linkEnd]), bytes[linkEnd] != 60 { linkEnd += 1 }
        while linkEnd > domainStart {
            let last = bytes[linkEnd - 1]
            if "?!.,:*_~".utf8.contains(last) {
                linkEnd -= 1
            } else if last == 41 {
                var open = 0, close = 0
                for byte in bytes[start..<linkEnd] {
                    if byte == 40 { open += 1 } else if byte == 41 { close += 1 }
                }
                if close > open { linkEnd -= 1 } else { break }
            } else if last == 59 {
                var probe = linkEnd - 2
                while probe > start, NoteMDByte.isAlphanumeric(bytes[probe]) { probe -= 1 }
                if probe >= start, bytes[probe] == 38, probe < linkEnd - 2 { linkEnd = probe } else { break }
            } else {
                break
            }
        }
        guard linkEnd > domainStart else { return nil }
        let text = NoteMDByte.string(bytes[start..<linkEnd])
        return (prefix + text, linkEnd - start)
    }
}
