import Foundation

private typealias Ch = NoteSyntaxChar

extension NoteSyntaxScanner {
    mutating func lexMarkup(html: Bool, stopAtPHP: Bool = false) {
        while pos < end {
            let c = units[pos]
            if c == Ch.less {
                if stopAtPHP && peek() == Ch.question { return }
                lexMarkupAngle(html: html)
            } else if c == Ch.ampersand {
                if !lexEntity() { pos += 1 }
            } else {
                pos += 1
            }
        }
    }

    private mutating func lexMarkupAngle(html: Bool) {
        if matches("<!--", at: pos) {
            let stop = find(Array("-->".utf16), from: pos + 4).map { $0 + 3 } ?? end
            emit(pos, stop, .comment)
            pos = stop
            return
        }
        if matches("<![CDATA[", at: pos) {
            let stop = find(Array("]]>".utf16), from: pos + 9).map { $0 + 3 } ?? end
            emit(pos, pos + 9, .meta)
            emit(pos + 9, max(pos + 9, stop - 3), .string)
            emit(max(pos + 9, stop - 3), stop, .meta)
            pos = stop
            return
        }
        if peek() == Ch.bang || peek() == Ch.question {
            let close: [UInt16] = peek() == Ch.question ? [Ch.question, Ch.greater] : [Ch.greater]
            let stop = find(close, from: pos + 2).map { $0 + close.count } ?? end
            emit(pos, stop, .meta)
            pos = stop
            return
        }
        if peek() == Ch.slash && isTagNameStart(peek(2)) {
            emit(pos, pos + 2, .punctuation)
            pos += 2
            let nameStart = pos
            skipTagName()
            emit(nameStart, pos, .tag)
            pos = skipSpaces(from: pos)
            if at(pos) == Ch.greater {
                emit(pos, pos + 1, .punctuation)
                pos += 1
            }
            return
        }
        guard isTagNameStart(peek()) else {
            pos += 1
            return
        }
        lexOpenTag(html: html)
    }

    private func isTagNameStart(_ c: UInt16) -> Bool { Ch.isLetter(c) || c == Ch.underscore || c >= 0x80 }

    private mutating func skipTagName() {
        while pos < end {
            let c = units[pos]
            guard Ch.isWord(c) || c == Ch.minus || c == Ch.colon || c == Ch.dot else { break }
            pos += 1
        }
    }

    mutating func lexOpenTag(html: Bool) {
        emit(pos, pos + 1, .punctuation)
        pos += 1
        let nameStart = pos
        skipTagName()
        emit(nameStart, pos, .tag)
        let name = text(nameStart, pos).lowercased()
        var typeValue = ""
        var lastAttribute = ""
        while pos < end {
            let c = units[pos]
            if Ch.isSpaceOrNewline(c) {
                pos += 1
            } else if c == Ch.slash && peek() == Ch.greater {
                emit(pos, pos + 2, .punctuation)
                pos += 2
                return
            } else if c == Ch.greater {
                emit(pos, pos + 1, .punctuation)
                pos += 1
                if html { lexRawTextElement(name, type: typeValue) }
                return
            } else if c == Ch.equals {
                emit(pos, pos + 1, .punctuation)
                pos += 1
                pos = skipSpaces(from: pos)
                let valueStart = pos
                let quote = at(pos)
                if quote == Ch.quote || quote == Ch.apostrophe {
                    let stop = find([quote], from: pos + 1).map { $0 + 1 } ?? end
                    lexAttributeValue(from: valueStart, to: stop)
                    if lastAttribute == "type" { typeValue = text(valueStart + 1, stop - 1).lowercased() }
                    pos = stop
                } else {
                    while pos < end && !Ch.isSpaceOrNewline(units[pos]) && units[pos] != Ch.greater { pos += 1 }
                    emit(valueStart, pos, .string)
                    if lastAttribute == "type" { typeValue = text(valueStart, pos).lowercased() }
                }
            } else if c == Ch.less {
                return
            } else {
                let start = pos
                while pos < end {
                    let unit = units[pos]
                    if Ch.isSpaceOrNewline(unit) || unit == Ch.equals || unit == Ch.greater || unit == Ch.less
                        || (unit == Ch.slash && peek() == Ch.greater) { break }
                    pos += 1
                }
                if pos == start { pos += 1 }
                emit(start, pos, .attribute)
                lastAttribute = text(start, pos).lowercased()
            }
        }
    }

    private mutating func lexAttributeValue(from start: Int, to stop: Int) {
        var segment = start
        var cursor = start + 1
        while cursor < stop - 1 {
            if units[cursor] == Ch.ampersand {
                emit(segment, cursor, .string)
                let saved = pos
                pos = cursor
                if lexEntity() {
                    cursor = pos
                    segment = cursor
                    pos = saved
                    continue
                }
                pos = saved
            }
            cursor += 1
        }
        emit(segment, stop, .string)
    }

    private mutating func lexRawTextElement(_ name: String, type: String) {
        let lexer: NoteSyntaxLexer?
        switch name {
        case "script":
            if type.isEmpty || type.contains("javascript") || type.contains("ecmascript") || type == "module" {
                lexer = .code(NoteSyntaxGrammars.javascript)
            } else if type.contains("json") {
                lexer = .code(NoteSyntaxGrammars.json)
            } else if type.contains("babel") || type.contains("jsx") {
                lexer = .code(NoteSyntaxGrammars.jsx)
            } else if type.contains("typescript") {
                lexer = .code(NoteSyntaxGrammars.typescript)
            } else {
                lexer = nil
            }
        case "style":
            lexer = .css
        case "textarea", "title":
            lexer = nil
        default:
            return
        }
        let close = Array("</\(name)".utf16)
        let stop = find(close, from: pos, ignoringCase: true) ?? end
        if let lexer {
            embed(lexer, until: stop)
        } else {
            while pos < stop {
                if units[pos] == Ch.ampersand && name != "script" && lexEntity() { continue }
                pos += 1
            }
        }
        pos = stop
    }

    mutating func lexPHPDocument() {
        let open = Array("<?".utf16)
        guard find(open, from: pos) != nil else {
            lexCode(NoteSyntaxGrammars.php)
            return
        }
        while pos < end {
            guard let tag = find(open, from: pos) else {
                embedMarkup(until: end)
                return
            }
            embedMarkup(until: tag)
            var tagEnd = tag + 2
            if matchesIgnoringCase(Array("php".utf16), at: tagEnd) {
                tagEnd += 3
            } else if at(tagEnd) == Ch.equals {
                tagEnd += 1
            }
            emit(tag, tagEnd, .meta)
            pos = tagEnd
            let close = find([Ch.question, Ch.greater], from: pos) ?? end
            embed(.code(NoteSyntaxGrammars.php), until: close)
            if close < end {
                emit(close, close + 2, .meta)
                pos = close + 2
            }
        }
    }

    private mutating func embedMarkup(until stop: Int) {
        guard stop > pos else { return }
        let savedEnd = end
        end = stop
        lexMarkup(html: true)
        end = savedEnd
        pos = stop
    }

    mutating func lexMarkdown() {
        if matches("---", at: pos) && lineEnd(from: pos) == skipSpaces(from: pos + 3) {
            var cursor = lineEnd(from: pos) + 1
            while cursor < end {
                let stop = lineEnd(from: cursor)
                if (matches("---", at: cursor) || matches("...", at: cursor)) && skipSpaces(from: cursor + 3) == stop {
                    emit(pos, pos + 3, .meta)
                    pos = lineEnd(from: pos) + 1
                    embed(.yaml, until: cursor)
                    emit(cursor, stop, .meta)
                    pos = stop
                    break
                }
                cursor = stop + 1
            }
        }
        while pos < end {
            let lineStart = pos
            let stop = lineEnd(from: pos)
            let indentEnd = skipSpaces(from: pos)
            if indentEnd == stop {
                pos = min(end, stop + 1)
                continue
            }
            if indentEnd - lineStart < 4, let fence = fenceOpening(at: indentEnd) {
                lexFencedCode(fence, lineStart: lineStart, openingEnd: stop)
                continue
            }
            let next = lexMarkdownLine(contentStart: indentEnd, stop: stop)
            pos = min(end, next + 1)
        }
    }

    private func fenceOpening(at index: Int) -> (marker: UInt16, count: Int)? {
        let marker = at(index)
        guard marker == Ch.backtick || marker == Ch.tilde else { return nil }
        var cursor = index
        while at(cursor) == marker { cursor += 1 }
        let count = cursor - index
        guard count >= 3 else { return nil }
        if marker == Ch.backtick, find([Ch.backtick], from: cursor, limit: lineEnd(from: cursor)) != nil { return nil }
        return (marker, count)
    }

    private mutating func lexFencedCode(_ fence: (marker: UInt16, count: Int), lineStart: Int, openingEnd: Int) {
        let fenceStart = skipSpaces(from: lineStart)
        let infoStart = skipSpaces(from: fenceStart + fence.count)
        emit(fenceStart, fenceStart + fence.count, .punctuation)
        emit(infoStart, openingEnd, .attribute)
        let info = text(infoStart, openingEnd)
        var cursor = min(end, openingEnd + 1)
        let bodyStart = cursor
        var closeLine: Int?
        while cursor < end {
            let stop = lineEnd(from: cursor)
            let markStart = skipSpaces(from: cursor)
            var markEnd = markStart
            while at(markEnd) == fence.marker { markEnd += 1 }
            if markEnd - markStart >= fence.count && skipSpaces(from: markEnd) == stop && markStart - cursor < 4 {
                closeLine = cursor
                break
            }
            cursor = stop + 1
        }
        let bodyEnd = closeLine ?? end
        pos = bodyStart
        if bodyEnd > bodyStart {
            if let language = NoteCodeLanguage.named(info), let lexer = NoteSyntaxLexer.lexer(for: language.id) {
                embed(lexer, until: bodyEnd)
            } else {
                emit(bodyStart, bodyEnd, .string)
            }
        }
        pos = bodyEnd
        if let closeLine {
            let stop = lineEnd(from: closeLine)
            emit(skipSpaces(from: closeLine), stop, .punctuation)
            pos = min(end, stop + 1)
        }
    }

    private mutating func lexMarkdownLine(contentStart: Int, stop: Int) -> Int {
        var cursor = contentStart
        while at(cursor) == Ch.greater {
            emit(cursor, cursor + 1, .punctuation)
            cursor = skipSpaces(from: cursor + 1)
        }
        if cursor >= stop { return stop }
        let c = at(cursor)
        if c == Ch.hash {
            var level = cursor
            while at(level) == Ch.hash { level += 1 }
            if level - cursor <= 6 && (level == stop || Ch.isSpace(at(level))) {
                emit(cursor, stop, .heading)
                return stop
            }
        }
        if isThematicBreak(from: cursor, to: stop) {
            emit(cursor, stop, .punctuation)
            return stop
        }
        let nextLine = stop + 1
        if nextLine < end && cursor == contentStart {
            let nextIndent = skipSpaces(from: nextLine)
            let nextStop = lineEnd(from: nextLine)
            let marker = at(nextIndent)
            if (marker == Ch.equals || marker == Ch.minus) && nextIndent - nextLine < 4 && nextStop > nextIndent {
                var probe = nextIndent
                while at(probe) == marker { probe += 1 }
                if skipSpaces(from: probe) == nextStop && !startsListItem(at: cursor) && c != Ch.pipe {
                    emit(cursor, stop, .heading)
                    emit(nextIndent, nextStop, .punctuation)
                    return nextStop
                }
            }
        }
        if let markerEnd = listMarkerEnd(at: cursor, stop: stop) {
            emit(cursor, markerEnd, .punctuation)
            cursor = skipSpaces(from: markerEnd)
            if at(cursor) == Ch.openBracket && at(cursor + 2) == Ch.closeBracket
                && " xX".utf16.contains(at(cursor + 1)) {
                emit(cursor, cursor + 3, .keyword)
                cursor += 3
            }
        } else if c == Ch.openBracket, let definition = linkDefinition(at: cursor, stop: stop) {
            emit(cursor, definition.labelEnd, .link)
            emit(definition.labelEnd, definition.labelEnd + 1, .punctuation)
            emit(definition.urlStart, stop, .string)
            return stop
        }
        lexMarkdownInline(from: cursor, to: stop)
        return stop
    }

    private func isThematicBreak(from start: Int, to stop: Int) -> Bool {
        let marker = at(start)
        guard marker == Ch.star || marker == Ch.minus || marker == Ch.underscore else { return false }
        var count = 0
        for index in start..<stop {
            let unit = units[index]
            if unit == marker { count += 1 } else if !Ch.isSpace(unit) { return false }
        }
        return count >= 3
    }

    private func startsListItem(at index: Int) -> Bool { listMarkerEnd(at: index, stop: lineEnd(from: index)) != nil }

    private func listMarkerEnd(at index: Int, stop: Int) -> Int? {
        let c = at(index)
        if (c == Ch.minus || c == Ch.star || c == Ch.plus) && (index + 1 == stop || Ch.isSpace(at(index + 1))) {
            return index + 1
        }
        var cursor = index
        while Ch.isDigit(at(cursor)) && cursor - index < 9 { cursor += 1 }
        guard cursor > index, at(cursor) == Ch.dot || at(cursor) == Ch.closeParen else { return nil }
        guard cursor + 1 == stop || Ch.isSpace(at(cursor + 1)) else { return nil }
        return cursor + 1
    }

    private func linkDefinition(at index: Int, stop: Int) -> (labelEnd: Int, urlStart: Int)? {
        guard let close = find([Ch.closeBracket], from: index + 1, limit: stop), at(close + 1) == Ch.colon else { return nil }
        let urlStart = skipSpaces(from: close + 2)
        guard urlStart < stop else { return nil }
        return (close + 1, urlStart)
    }

    mutating func lexMarkdownInline(from start: Int, to stop: Int) {
        pos = start
        var failedRuns = Set<Int>()
        var bracketFailure = -1
        while pos < stop {
            let c = units[pos]
            switch c {
            case Ch.backslash:
                let next = at(pos + 1)
                if pos + 1 < stop && next < 128 && !Ch.isWord(next) && !Ch.isSpace(next) {
                    emit(pos, pos + 2, .escape)
                    pos += 2
                } else {
                    pos += 1
                }
            case Ch.backtick:
                var runEnd = pos
                while runEnd < stop && units[runEnd] == Ch.backtick { runEnd += 1 }
                let run = runEnd - pos
                if !failedRuns.contains(-run), let close = closingBacktickRun(run, from: runEnd, stop: stop) {
                    emit(pos, close + run, .string)
                    pos = close + run
                } else {
                    failedRuns.insert(-run)
                    pos = runEnd
                }
            case Ch.bang where at(pos + 1) == Ch.openBracket:
                if bracketFailure < 0, lexMarkdownLink(from: pos, bracket: pos + 1, stop: stop, failure: &bracketFailure) {
                    continue
                }
                pos += 1
            case Ch.openBracket:
                if bracketFailure < 0, lexMarkdownLink(from: pos, bracket: pos, stop: stop, failure: &bracketFailure) {
                    continue
                }
                pos += 1
            case Ch.less:
                if lexAutolink(stop: stop) { continue }
                if isTagNameStart(at(pos + 1)) || (at(pos + 1) == Ch.slash && isTagNameStart(at(pos + 2))) || matches("<!--", at: pos) {
                    let savedEnd = end
                    end = stop
                    lexMarkupAngle(html: false)
                    end = savedEnd
                    continue
                }
                pos += 1
            case Ch.ampersand:
                if !lexEntity() { pos += 1 }
            case Ch.star, Ch.underscore, Ch.tilde:
                lexEmphasis(c, stop: stop, failedRuns: &failedRuns)
            case 104, 119:
                if lexBareURL(stop: stop) { continue }
                pos += 1
            default:
                pos += 1
            }
        }
        pos = stop
    }

    private func closingBacktickRun(_ run: Int, from index: Int, stop: Int) -> Int? {
        var cursor = index
        while cursor < stop {
            if units[cursor] == Ch.backtick {
                var runEnd = cursor
                while runEnd < stop && units[runEnd] == Ch.backtick { runEnd += 1 }
                if runEnd - cursor == run { return cursor }
                cursor = runEnd
            } else {
                cursor += 1
            }
        }
        return nil
    }

    private mutating func lexMarkdownLink(from start: Int, bracket: Int, stop: Int, failure: inout Int) -> Bool {
        var cursor = bracket + 1
        var level = 1
        let labelLimit = min(stop, bracket + 1000)
        while cursor < labelLimit {
            let c = units[cursor]
            if c == Ch.backslash {
                cursor += 2
                continue
            }
            if c == Ch.openBracket { level += 1 } else if c == Ch.closeBracket {
                level -= 1
                if level == 0 { break }
            }
            cursor += 1
        }
        guard cursor < labelLimit, at(cursor) == Ch.closeBracket else {
            if labelLimit == stop { failure = bracket }
            return false
        }
        let labelEnd = cursor + 1
        if at(labelEnd) == Ch.openParen {
            var close = labelEnd + 1
            var depth = 1
            while close < stop {
                let c = units[close]
                if c == Ch.openParen { depth += 1 } else if c == Ch.closeParen {
                    depth -= 1
                    if depth == 0 { break }
                }
                close += 1
            }
            guard close < stop else { return false }
            if start < bracket { emit(start, bracket, .punctuation) }
            emit(bracket, labelEnd, .link)
            emit(labelEnd, labelEnd + 1, .punctuation)
            emit(labelEnd + 1, close, .string)
            emit(close, close + 1, .punctuation)
            pos = close + 1
            return true
        }
        if at(labelEnd) == Ch.openBracket, let close = find([Ch.closeBracket], from: labelEnd + 1, limit: stop) {
            if start < bracket { emit(start, bracket, .punctuation) }
            emit(bracket, labelEnd, .link)
            emit(labelEnd, close + 1, .string)
            pos = close + 1
            return true
        }
        if at(bracket + 1) == Ch.caret || at(bracket + 1) == Ch.bang {
            emit(start, labelEnd, .link)
            pos = labelEnd
            return true
        }
        return false
    }

    private mutating func lexAutolink(stop: Int) -> Bool {
        var cursor = pos + 1
        var sawColonOrAt = false
        while cursor < stop {
            let c = units[cursor]
            if c == Ch.greater { break }
            if Ch.isSpace(c) || c == Ch.less { return false }
            if c == Ch.colon || c == Ch.at { sawColonOrAt = true }
            cursor += 1
        }
        guard cursor < stop, sawColonOrAt, Ch.isLetter(at(pos + 1)) else { return false }
        emit(pos, cursor + 1, .link)
        pos = cursor + 1
        return true
    }

    private mutating func lexBareURL(stop: Int) -> Bool {
        guard pos == 0 || !Ch.isWord(at(pos - 1)) else { return false }
        guard matches("https://", at: pos) || matches("http://", at: pos) || matches("www.", at: pos) else { return false }
        var cursor = pos
        while cursor < stop && !Ch.isSpace(units[cursor]) && units[cursor] != Ch.less { cursor += 1 }
        while cursor > pos && ".,:;!?)'\"*_~".utf16.contains(units[cursor - 1]) { cursor -= 1 }
        emit(pos, cursor, .link)
        pos = cursor
        return true
    }

    private mutating func lexEmphasis(_ marker: UInt16, stop: Int, failedRuns: inout Set<Int>) {
        var runEnd = pos
        while runEnd < stop && units[runEnd] == marker { runEnd += 1 }
        let run = runEnd - pos
        let key = Int(marker) * 16 + min(run, 15)
        let leftFlanking = runEnd < stop && !Ch.isSpace(units[runEnd])
        let intraword = marker == Ch.underscore && pos > 0 && Ch.isWord(at(pos - 1))
        guard leftFlanking, !intraword, run <= 3, !failedRuns.contains(key) else {
            pos = runEnd
            return
        }
        var cursor = runEnd
        var close: Int?
        while cursor < stop {
            let c = units[cursor]
            if c == Ch.backslash {
                cursor += 2
                continue
            }
            if c == Ch.backtick {
                var tickEnd = cursor
                while tickEnd < stop && units[tickEnd] == Ch.backtick { tickEnd += 1 }
                if let closing = closingBacktickRun(tickEnd - cursor, from: tickEnd, stop: stop) {
                    cursor = closing + (tickEnd - cursor)
                } else {
                    cursor = tickEnd
                }
                continue
            }
            if c == marker {
                var closeEnd = cursor
                while closeEnd < stop && units[closeEnd] == marker { closeEnd += 1 }
                let rightFlanking = !Ch.isSpace(units[cursor - 1])
                let closesWord = marker != Ch.underscore || closeEnd == stop || !Ch.isWord(units[closeEnd])
                if closeEnd - cursor == run && rightFlanking && closesWord {
                    close = cursor
                    break
                }
                cursor = closeEnd
                continue
            }
            cursor += 1
        }
        guard let close else {
            failedRuns.insert(key)
            pos = runEnd
            return
        }
        let kind: NoteSyntaxKind = marker == Ch.tilde ? .deleted : run >= 2 ? .strong : .emphasis
        emit(pos, close + run, kind)
        pos = close + run
    }
}
