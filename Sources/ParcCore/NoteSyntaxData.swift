import Foundation

private typealias Ch = NoteSyntaxChar

extension NoteSyntaxScanner {
    mutating func lexYAML() {
        var blockScalarIndent: Int?
        var flowDepth = 0
        while pos < end {
            let lineStart = pos
            let stop = lineEnd(from: pos)
            let content = skipSpaces(from: pos)
            let indent = content - lineStart
            if let parent = blockScalarIndent {
                if content == stop || indent > parent {
                    emit(content, stop, .string)
                    pos = stop + 1
                    continue
                }
                blockScalarIndent = nil
            }
            if content == stop {
                pos = stop + 1
                continue
            }
            pos = content
            if flowDepth > 0 {
                _ = lexYAMLValue(flowDepth: &flowDepth)
                pos = lineEnd(from: pos) + 1
                continue
            }
            if at(content) == Ch.hash {
                emit(content, stop, .comment)
                pos = stop + 1
                continue
            }
            if indent == 0 && at(content) == Ch.percent {
                emit(content, stop, .meta)
                pos = stop + 1
                continue
            }
            var cursor = content
            if indent == 0 && (matches("---", at: cursor) || matches("...", at: cursor))
                && (cursor + 3 == stop || Ch.isSpace(at(cursor + 3))) {
                emit(cursor, cursor + 3, .meta)
                cursor = skipSpaces(from: cursor + 3)
            }
            while (at(cursor) == Ch.minus || at(cursor) == Ch.question) && (cursor + 1 == stop || Ch.isSpace(at(cursor + 1))) {
                emit(cursor, cursor + 1, .punctuation)
                cursor = skipSpaces(from: cursor + 1)
            }
            if let key = yamlKey(at: cursor, stop: stop) {
                emit(cursor, key.end, .property)
                emit(key.colon, key.colon + 1, .punctuation)
                cursor = skipSpaces(from: key.colon + 1)
            }
            pos = cursor
            if lexYAMLValue(flowDepth: &flowDepth) { blockScalarIndent = indent }
            pos = lineEnd(from: pos) + 1
        }
        pos = min(pos, end)
    }

    private func yamlKey(at index: Int, stop: Int) -> (end: Int, colon: Int)? {
        let first = at(index)
        if first == Ch.quote || first == Ch.apostrophe {
            var cursor = index + 1
            while cursor < stop && units[cursor] != first {
                cursor += units[cursor] == Ch.backslash && first == Ch.quote ? 2 : 1
            }
            guard cursor < stop else { return nil }
            let colon = skipSpaces(from: cursor + 1)
            guard at(colon) == Ch.colon, colon + 1 >= stop || Ch.isSpace(at(colon + 1)) else { return nil }
            return (cursor + 1, colon)
        }
        guard first != 0, !"[]{}&*!|>%@`#,".utf16.contains(first) else { return nil }
        var cursor = index
        while cursor < stop {
            let c = units[cursor]
            if c == Ch.hash && cursor > index && Ch.isSpace(units[cursor - 1]) { return nil }
            if c == Ch.colon && (cursor + 1 == stop || Ch.isSpace(units[cursor + 1])) {
                var keyEnd = cursor
                while keyEnd > index && Ch.isSpace(units[keyEnd - 1]) { keyEnd -= 1 }
                return keyEnd > index ? (keyEnd, cursor) : nil
            }
            cursor += 1
        }
        return nil
    }

    private mutating func lexYAMLValue(flowDepth: inout Int) -> Bool {
        while pos < end && units[pos] != Ch.newline {
            let c = units[pos]
            if Ch.isSpace(c) {
                pos += 1
                continue
            }
            switch c {
            case Ch.hash where pos == 0 || Ch.isSpaceOrNewline(at(pos - 1)):
                let stop = lineEnd(from: pos)
                emit(pos, stop, .comment)
                pos = stop
            case Ch.ampersand, Ch.star:
                let start = pos
                pos += 1
                while pos < end && !Ch.isSpaceOrNewline(units[pos]) && !",[]{}".utf16.contains(units[pos]) { pos += 1 }
                emit(start, pos, .variable)
            case Ch.bang:
                let start = pos
                while pos < end && !Ch.isSpaceOrNewline(units[pos]) { pos += 1 }
                emit(start, pos, .type)
            case Ch.pipe where flowDepth == 0, Ch.greater where flowDepth == 0:
                let start = pos
                pos += 1
                while pos < end && (units[pos] == Ch.minus || units[pos] == Ch.plus || Ch.isDigit(units[pos])) { pos += 1 }
                emit(start, pos, .punctuation)
                let rest = skipSpaces(from: pos)
                if at(rest) == Ch.hash {
                    let stop = lineEnd(from: rest)
                    emit(rest, stop, .comment)
                    pos = stop
                }
                return true
            case Ch.quote:
                let start = pos
                pos += 1
                lexStringBody(NoteSyntaxStringRule("\"", multiline: true), from: start, grammar: nil)
                yamlKeyAfterQuote(from: start)
            case Ch.apostrophe:
                let start = pos
                pos += 1
                lexStringBody(NoteSyntaxStringRule("'", multiline: true, escapes: false, doubledClose: true),
                              from: start, grammar: nil)
                yamlKeyAfterQuote(from: start)
            case Ch.openBracket, Ch.openBrace:
                flowDepth += 1
                emit(pos, pos + 1, .punctuation)
                pos += 1
            case Ch.closeBracket, Ch.closeBrace:
                flowDepth = max(0, flowDepth - 1)
                emit(pos, pos + 1, .punctuation)
                pos += 1
            case Ch.comma where flowDepth > 0:
                emit(pos, pos + 1, .punctuation)
                pos += 1
            case Ch.colon where flowDepth > 0 || pos + 1 >= end || Ch.isSpaceOrNewline(at(pos + 1)):
                emit(pos, pos + 1, .punctuation)
                pos += 1
            default:
                lexYAMLPlainScalar(inFlow: flowDepth > 0)
            }
        }
        return false
    }

    private mutating func yamlKeyAfterQuote(from start: Int) {
        let colon = skipSpaces(from: pos)
        if at(colon) == Ch.colon && (Ch.isSpaceOrNewline(at(colon + 1)) || at(colon + 1) == 0 || at(colon + 1) == Ch.comma) {
            retag(from: start, to: pos, as: .property)
        }
    }

    private mutating func lexYAMLPlainScalar(inFlow: Bool) {
        let start = pos
        var cursor = pos
        var stop = pos
        while cursor < end {
            let c = units[cursor]
            if c == Ch.newline { break }
            if c == Ch.hash && cursor > start && Ch.isSpace(units[cursor - 1]) { break }
            if c == Ch.colon && (Ch.isSpaceOrNewline(at(cursor + 1)) || at(cursor + 1) == 0 || (inFlow && ",[]{}".utf16.contains(at(cursor + 1)))) {
                break
            }
            if inFlow && ",[]{}".utf16.contains(c) { break }
            cursor += 1
            if !Ch.isSpace(c) { stop = cursor }
        }
        pos = max(stop, start + 1)
        let colon = skipSpaces(from: pos)
        if at(colon) == Ch.colon && (Ch.isSpaceOrNewline(at(colon + 1)) || at(colon + 1) == 0 || inFlow) {
            emit(start, pos, .property)
            return
        }
        emit(start, pos, yamlScalarKind(start, pos))
    }

    private func yamlScalarKind(_ start: Int, _ stop: Int) -> NoteSyntaxKind {
        let word = text(start, stop).lowercased()
        if ["true", "false", "yes", "no", "on", "off", "null", "~"].contains(word) { return .constant }
        if [".inf", "-.inf", "+.inf", ".nan"].contains(word) { return .number }
        var sawDigit = false
        for index in start..<stop {
            let unit = units[index]
            if Ch.isDigit(unit) {
                sawDigit = true
            } else if !"+-._:xXoObBeEtTzZ".utf16.contains(unit) && !Ch.isHexDigit(unit) {
                return .string
            }
        }
        guard sawDigit, Ch.isDigit(units[start]) || "+-.".utf16.contains(units[start]) else { return .string }
        return .number
    }

    mutating func lexTOML() {
        var stack: [UInt16] = []
        var expectKey = true
        while pos < end {
            let c = units[pos]
            if c == Ch.newline {
                pos += 1
                if stack.isEmpty { expectKey = true }
                continue
            }
            if Ch.isSpace(c) {
                pos += 1
                continue
            }
            switch c {
            case Ch.hash:
                let stop = lineEnd(from: pos)
                emit(pos, stop, .comment)
                pos = stop
            case Ch.openBracket where stack.isEmpty && expectKey && isLineStart(pos):
                let double = peek() == Ch.openBracket
                let width = double ? 2 : 1
                let limit = lineEnd(from: pos)
                let close = find(Array(repeating: Ch.closeBracket, count: width), from: pos + width, limit: limit) ?? limit
                emit(pos, pos + width, .punctuation)
                emit(pos + width, close, .type)
                emit(close, min(limit, close + width), .punctuation)
                pos = min(limit, close + width)
                expectKey = false
            case Ch.quote, Ch.apostrophe:
                let start = pos
                let triple = peek() == c && peek(2) == c
                let delimiter = Array(repeating: c, count: triple ? 3 : 1)
                let rule = NoteSyntaxStringRule(units: delimiter, close: delimiter, multiline: triple,
                                                escapes: c == Ch.quote, interpolation: nil)
                pos += delimiter.count
                lexStringBody(rule, from: start, grammar: nil)
                if expectKey { retag(from: start, to: pos, as: .property) }
            case Ch.equals:
                emit(pos, pos + 1, .operatorSymbol)
                pos += 1
                expectKey = false
            case Ch.dot, Ch.comma:
                emit(pos, pos + 1, .punctuation)
                pos += 1
                if c == Ch.comma && stack.last == Ch.openBrace { expectKey = true }
            case Ch.openBrace, Ch.openBracket:
                stack.append(c)
                emit(pos, pos + 1, .punctuation)
                pos += 1
                expectKey = c == Ch.openBrace
            case Ch.closeBrace, Ch.closeBracket:
                if !stack.isEmpty { stack.removeLast() }
                emit(pos, pos + 1, .punctuation)
                pos += 1
                expectKey = false
            default:
                let start = pos
                if expectKey {
                    while pos < end && (Ch.isWord(units[pos]) || units[pos] == Ch.minus) { pos += 1 }
                    if pos == start { pos += 1 } else { emit(start, pos, .property) }
                } else {
                    while pos < end && !Ch.isSpaceOrNewline(units[pos]) && !",]}#".utf16.contains(units[pos]) { pos += 1 }
                    if pos == start {
                        pos += 1
                    } else {
                        let word = text(start, pos)
                        if word == "true" || word == "false" {
                            emit(start, pos, .constant)
                        } else if Ch.isDigit(units[start]) || "+-".utf16.contains(units[start]) || word == "inf" || word == "nan" {
                            emit(start, pos, .number)
                        }
                    }
                }
            }
        }
    }

    mutating func lexDiff() {
        var oldRemaining = 0
        var newRemaining = 0
        while pos < end {
            let start = pos
            let stop = lineEnd(from: pos)
            let c = at(start)
            if matches("@@", at: start) {
                let close = find(Array("@@".utf16), from: start + 2, limit: stop).map { $0 + 2 } ?? stop
                emit(start, close, .meta)
                let counts = hunkCounts(start, close)
                oldRemaining = counts.old
                newRemaining = counts.new
            } else if oldRemaining > 0 || newRemaining > 0 {
                switch c {
                case Ch.plus:
                    emit(start, stop, .inserted)
                    newRemaining -= 1
                case Ch.minus:
                    emit(start, stop, .deleted)
                    oldRemaining -= 1
                case Ch.backslash:
                    emit(start, stop, .comment)
                default:
                    oldRemaining -= 1
                    newRemaining -= 1
                }
            } else if matches("+++ ", at: start) || matches("--- ", at: start) || matches("*** ", at: start) {
                emit(start, stop, .heading)
            } else if ["diff ", "index ", "new file mode", "deleted file mode", "similarity index", "rename from",
                       "rename to", "old mode", "new mode", "Binary files", "Only in ", "copy from", "copy to"]
                        .contains(where: { matches($0, at: start) }) {
                emit(start, stop, .meta)
            } else if c == Ch.plus {
                emit(start, stop, .inserted)
            } else if c == Ch.minus {
                emit(start, stop, .deleted)
            } else if c == Ch.backslash {
                emit(start, stop, .comment)
            }
            pos = min(end, stop + 1)
        }
    }

    private func hunkCounts(_ start: Int, _ stop: Int) -> (old: Int, new: Int) {
        func count(after sign: UInt16) -> Int {
            guard let marker = find([sign], from: start + 2, limit: stop) else { return 0 }
            var cursor = marker + 1
            while Ch.isDigit(at(cursor)) { cursor += 1 }
            guard at(cursor) == Ch.comma else { return 1 }
            cursor += 1
            var value = 0
            while Ch.isDigit(at(cursor)) && value < 1_000_000_000 {
                value = value * 10 + Int(units[cursor] - 48)
                cursor += 1
            }
            return value
        }
        return (count(after: Ch.minus), count(after: Ch.plus))
    }

    mutating func lexDockerfile() {
        var seenInstruction = false
        let bash = NoteSyntaxLexer.code(NoteSyntaxGrammars.bash)
        let json = NoteSyntaxLexer.code(NoteSyntaxGrammars.json)
        while pos < end {
            let c = units[pos]
            if Ch.isSpaceOrNewline(c) {
                pos += 1
                continue
            }
            if c == Ch.hash {
                let stop = lineEnd(from: pos)
                let directive = !seenInstruction && find([Ch.equals], from: pos, limit: stop) != nil
                emit(pos, stop, directive ? .meta : .comment)
                pos = stop
                continue
            }
            let wordEnd = skipWord(from: pos)
            let word = text(pos, wordEnd).uppercased()
            guard wordEnd > pos, NoteSyntaxGrammars.dockerInstructions.contains(word) else {
                let stop = dockerInstructionEnd(from: pos)
                lexDockerArguments("", until: stop)
                continue
            }
            seenInstruction = true
            emit(pos, wordEnd, .keyword)
            pos = wordEnd
            if word == "ONBUILD" { continue }
            let stop = dockerInstructionEnd(from: pos)
            switch word {
            case "RUN", "CMD", "ENTRYPOINT", "SHELL", "HEALTHCHECK":
                lexDockerFlags(until: stop)
                if word == "HEALTHCHECK" {
                    let next = skipSpaces(from: pos)
                    let nextEnd = skipWord(from: next)
                    let inner = text(next, nextEnd).uppercased()
                    guard inner == "CMD" else {
                        lexDockerArguments(word, until: stop)
                        continue
                    }
                    emit(next, nextEnd, .keyword)
                    pos = nextEnd
                }
                let argument = skipSpaces(from: pos)
                pos = argument
                embed(at(argument) == Ch.openBracket ? json : bash, until: stop)
            default:
                lexDockerArguments(word, until: stop)
            }
            pos = stop
        }
    }

    private func dockerInstructionEnd(from index: Int) -> Int {
        var cursor = index
        var terminators: [(word: [UInt16], indented: Bool)] = []
        var firstLine = true
        while cursor < end {
            let stop = lineEnd(from: cursor)
            if firstLine {
                var probe = cursor
                while let marker = find([Ch.less, Ch.less], from: probe, limit: stop) {
                    var wordStart = marker + 2
                    let indented = at(wordStart) == Ch.minus
                    if indented { wordStart += 1 }
                    let quote = at(wordStart)
                    if quote == Ch.quote || quote == Ch.apostrophe { wordStart += 1 }
                    let wordEnd = skipWord(from: wordStart)
                    if wordEnd > wordStart { terminators.append((Array(units[wordStart..<wordEnd]), indented)) }
                    probe = max(wordEnd, marker + 2)
                }
                firstLine = false
            }
            var last = stop
            while last > cursor && Ch.isSpace(units[last - 1]) { last -= 1 }
            if last > cursor && units[last - 1] == Ch.backslash && stop < end {
                cursor = stop + 1
                continue
            }
            cursor = stop
            break
        }
        for terminator in terminators {
            var line = min(end, cursor + 1)
            while line < end {
                let stop = lineEnd(from: line)
                let start = terminator.indented ? skipSpaces(from: line) : line
                if matches(terminator.word, at: start) && skipSpaces(from: start + terminator.word.count) == stop {
                    cursor = stop
                    break
                }
                line = stop + 1
                cursor = min(end, line)
            }
        }
        return min(cursor, end)
    }

    private mutating func lexDockerFlags(until stop: Int) {
        while true {
            let flag = skipSpaces(from: pos)
            guard flag < stop, at(flag) == Ch.minus, at(flag + 1) == Ch.minus else { return }
            var nameEnd = flag + 2
            while nameEnd < stop && (Ch.isWord(units[nameEnd]) || units[nameEnd] == Ch.minus) { nameEnd += 1 }
            emit(flag, nameEnd, .attribute)
            var valueEnd = nameEnd
            if at(nameEnd) == Ch.equals {
                emit(nameEnd, nameEnd + 1, .operatorSymbol)
                valueEnd = nameEnd + 1
                while valueEnd < stop && !Ch.isSpaceOrNewline(units[valueEnd]) { valueEnd += 1 }
                emit(nameEnd + 1, valueEnd, .string)
            }
            pos = valueEnd
        }
    }

    private mutating func lexDockerArguments(_ instruction: String, until stop: Int) {
        let keyed = ["ENV", "ARG", "LABEL"].contains(instruction)
        let bash = NoteSyntaxGrammars.bash
        var argumentIndex = 0
        var heredocBody: Int?
        while pos < stop {
            let c = units[pos]
            if let body = heredocBody, c == Ch.newline {
                emit(body, stop, .string)
                pos = stop
                return
            }
            if c == Ch.backslash && (at(pos + 1) == Ch.newline || at(pos + 1) == Ch.carriageReturn) {
                pos += 2
                continue
            }
            if Ch.isSpaceOrNewline(c) {
                pos += 1
                continue
            }
            if c == Ch.hash && isLineStart(pos) {
                let end = lineEnd(from: pos)
                emit(pos, end, .comment)
                pos = end
                continue
            }
            if c == Ch.openBracket && argumentIndex == 0 {
                embed(.code(NoteSyntaxGrammars.json), until: stop)
                return
            }
            if c == Ch.minus && peek() == Ch.minus && argumentIndex == 0 {
                lexDockerFlags(until: stop)
                continue
            }
            if c == Ch.less && peek() == Ch.less {
                var wordEnd = pos + 2
                while wordEnd < stop && !Ch.isSpaceOrNewline(units[wordEnd]) { wordEnd += 1 }
                emit(pos, pos + 2, .operatorSymbol)
                emit(pos + 2, wordEnd, .string)
                pos = wordEnd
                heredocBody = lineEnd(from: pos) < stop ? lineEnd(from: pos) + 1 : nil
                continue
            }
            if c == Ch.quote || c == Ch.apostrophe {
                let start = pos
                pos += 1
                var rule = NoteSyntaxStringRule(c == Ch.quote ? "\"" : "'", escapes: c == Ch.quote)
                if c == Ch.quote { rule.interpolation = .shell }
                lexStringBody(rule, from: start, grammar: bash)
                argumentIndex += 1
                continue
            }
            if c == Ch.dollar {
                if !lexShellDollar(bash) { pos += 1 }
                continue
            }
            if c == Ch.equals {
                emit(pos, pos + 1, .operatorSymbol)
                pos += 1
                continue
            }
            let start = pos
            while pos < stop && !Ch.isSpaceOrNewline(units[pos]) && !"=\"'$".utf16.contains(units[pos]) { pos += 1 }
            if pos == start {
                pos += 1
                continue
            }
            let word = text(start, pos)
            if keyed && (at(pos) == Ch.equals || argumentIndex == 0) {
                emit(start, pos, .property)
            } else if instruction == "FROM" && word.uppercased() == "AS" {
                emit(start, pos, .keyword)
            } else if instruction == "EXPOSE" || instruction == "STOPSIGNAL" {
                if let first = word.utf16.first, Ch.isDigit(first) { emit(start, pos, .number) }
            }
            argumentIndex += 1
        }
        pos = stop
    }

    mutating func lexMakefile() {
        var inRule = false
        var inDefine = false
        let bash = NoteSyntaxLexer.code(NoteSyntaxGrammars.bash)
        while pos < end {
            let lineStart = pos
            let stop = makeLineEnd(from: pos)
            if at(lineStart) == Ch.tab && inRule && !inDefine {
                var cursor = skipSpaces(from: lineStart)
                while cursor < stop && "@-+".utf16.contains(units[cursor]) {
                    emit(cursor, cursor + 1, .operatorSymbol)
                    cursor += 1
                }
                pos = cursor
                embed(bash, until: stop, makeMode: true)
                pos = min(end, stop + 1)
                continue
            }
            let content = skipSpaces(from: lineStart)
            if content == stop {
                pos = min(end, stop + 1)
                continue
            }
            if inDefine {
                if matches("endef", at: content) && skipWord(from: content) == content + 5 {
                    emit(content, content + 5, .keyword)
                    inDefine = false
                } else {
                    lexMakeText(from: content, to: stop)
                }
                pos = min(end, stop + 1)
                continue
            }
            if at(content) == Ch.hash {
                emit(content, stop, .comment)
                pos = min(end, stop + 1)
                continue
            }
            var wordEnd = content
            while wordEnd < stop && (Ch.isWord(units[wordEnd]) || units[wordEnd] == Ch.minus) { wordEnd += 1 }
            let word = text(content, wordEnd)
            if NoteSyntaxGrammars.makeDirectives.contains(word) && (wordEnd == stop || Ch.isSpace(at(wordEnd)) || at(wordEnd) == Ch.openParen) {
                emit(content, wordEnd, .keyword)
                if word == "define" {
                    inDefine = true
                    let name = skipSpaces(from: wordEnd)
                    var nameEnd = name
                    while nameEnd < stop && !Ch.isSpace(units[nameEnd]) { nameEnd += 1 }
                    emit(name, nameEnd, .variable)
                    lexMakeText(from: nameEnd, to: stop)
                } else if ["export", "override", "private", "unexport"].contains(word) {
                    lexMakeStatement(from: skipSpaces(from: wordEnd), to: stop, inRule: &inRule, bash: bash)
                } else {
                    lexMakeText(from: wordEnd, to: stop)
                }
                pos = min(end, stop + 1)
                continue
            }
            lexMakeStatement(from: content, to: stop, inRule: &inRule, bash: bash)
            pos = min(end, stop + 1)
        }
    }

    private func makeLineEnd(from index: Int) -> Int {
        var cursor = lineEnd(from: index)
        while cursor < end && cursor > index && units[cursor - 1] == Ch.backslash { cursor = lineEnd(from: cursor + 1) }
        return cursor
    }

    private mutating func lexMakeStatement(from start: Int, to stop: Int, inRule: inout Bool, bash: NoteSyntaxLexer) {
        var cursor = start
        var depth = 0
        while cursor < stop {
            let c = units[cursor]
            if c == Ch.dollar && (at(cursor + 1) == Ch.openParen || at(cursor + 1) == Ch.openBrace) {
                depth += 1
                cursor += 2
                continue
            }
            if depth > 0 {
                if c == Ch.closeParen || c == Ch.closeBrace { depth -= 1 }
                cursor += 1
                continue
            }
            if c == Ch.hash { break }
            if c == Ch.equals {
                var operatorStart = cursor
                while operatorStart > start && ":?+!".utf16.contains(units[operatorStart - 1]) { operatorStart -= 1 }
                var nameEnd = operatorStart
                while nameEnd > start && Ch.isSpace(units[nameEnd - 1]) { nameEnd -= 1 }
                lexMakeText(from: start, to: nameEnd, kind: .variable)
                emit(operatorStart, cursor + 1, .operatorSymbol)
                lexMakeText(from: cursor + 1, to: stop)
                inRule = false
                return
            }
            if c == Ch.colon {
                var colonEnd = cursor + 1
                if at(colonEnd) == Ch.colon { colonEnd += 1 }
                if at(colonEnd) == Ch.equals {
                    cursor = colonEnd
                    continue
                }
                lexMakeTargets(from: start, to: cursor)
                emit(cursor, colonEnd, .operatorSymbol)
                let recipe = find([Ch.semicolon], from: colonEnd, limit: stop)
                lexMakeText(from: colonEnd, to: recipe ?? stop)
                if let recipe {
                    emit(recipe, recipe + 1, .punctuation)
                    pos = recipe + 1
                    embed(bash, until: stop, makeMode: true)
                }
                inRule = true
                return
            }
            cursor += 1
        }
        lexMakeText(from: start, to: stop)
    }

    private mutating func lexMakeTargets(from start: Int, to stop: Int) {
        pos = start
        while pos < stop {
            let c = units[pos]
            if Ch.isSpaceOrNewline(c) || c == Ch.backslash {
                pos += 1
            } else if c == Ch.dollar {
                if !lexMakeReference() { pos += 1 }
            } else {
                let wordStart = pos
                while pos < stop && !Ch.isSpaceOrNewline(units[pos]) && units[pos] != Ch.dollar { pos += 1 }
                emit(wordStart, pos, units[wordStart] == Ch.dot && Ch.isUpper(at(wordStart + 1)) ? .builtin : .function)
            }
        }
    }

    private mutating func lexMakeText(from start: Int, to stop: Int, kind: NoteSyntaxKind? = nil) {
        pos = start
        while pos < stop {
            let c = units[pos]
            if c == Ch.dollar {
                if !lexMakeReference() { pos += 1 }
            } else if c == Ch.hash && (pos == start || Ch.isSpace(at(pos - 1))) && kind == nil {
                emit(pos, stop, .comment)
                pos = stop
            } else if c == Ch.backslash {
                pos += 2
            } else if let kind, !Ch.isSpaceOrNewline(c) {
                let wordStart = pos
                while pos < stop && !Ch.isSpaceOrNewline(units[pos]) && units[pos] != Ch.dollar { pos += 1 }
                emit(wordStart, pos, kind)
            } else {
                pos += 1
            }
        }
        pos = min(pos, stop)
    }
}
