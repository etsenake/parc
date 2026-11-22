import Foundation

private typealias Ch = NoteSyntaxChar

extension NoteSyntaxScanner {
    mutating func lexSpecial(_ g: NoteSyntaxGrammar, _ c: UInt16, lineStart: Bool) -> Bool {
        let features = g.features
        switch c {
        case Ch.hash:
            if features.contains(.preprocessor) && lineStart {
                lexPreprocessor()
                return true
            }
            if features.contains(.swiftLiterals) { return lexSwiftHash(g) }
            if features.contains(.rustLiterals) && (peek() == Ch.openBracket || (peek() == Ch.bang && peek(2) == Ch.openBracket)) {
                lexBracketedAttribute()
                return true
            }
            if features.contains(.phpLiterals) && peek() == Ch.openBracket {
                lexBracketedAttribute()
                return true
            }
            if features.contains(.privateNames) && g.isWordStart(peek()) {
                let stop = skipWord(from: pos + 1)
                emit(pos, stop, .property)
                pos = stop
                state.operandEnded = true
                return true
            }
            return false
        case Ch.at:
            return lexAt(g, lineStart: lineStart)
        case Ch.dollar:
            return lexDollar(g)
        case Ch.apostrophe:
            return features.contains(.rustLiterals) && lexRustQuote()
        case Ch.slash:
            guard features.contains(.regexLiterals) && !state.operandEnded && pos >= regexFailUntil else { return false }
            return lexRegex()
        case Ch.less:
            if features.contains(.jsx) && !state.operandEnded && (Ch.isLetter(peek()) || peek() == Ch.greater) {
                lexJSXElement(g)
                state.operandEnded = true
                return true
            }
            if peek() == Ch.less && (features.contains(.rubyLiterals) || features.contains(.shell) || features.contains(.phpLiterals)) {
                return lexHeredocStart(g)
            }
            return false
        case Ch.percent:
            if features.contains(.rubyLiterals) { return lexPercentLiteral(g) }
            if features.contains(.percentOperators) {
                let limit = lineEnd(from: pos)
                guard let close = find([Ch.percent], from: pos + 1, limit: limit), close - pos < 24 else { return false }
                emit(pos, close + 1, .operatorSymbol)
                pos = close + 1
                state.operandEnded = false
                return true
            }
            return false
        case Ch.colon:
            if features.contains(.symbols) { return lexSymbolLiteral(g) }
            if features.contains(.sqlLiterals) && g.isWordStart(peek()) && at(pos - 1) != Ch.colon {
                let stop = skipWord(from: pos + 1)
                emit(pos, stop, .variable)
                pos = stop
                state.operandEnded = true
                return true
            }
            return false
        case Ch.tilde:
            return features.contains(.elixirSigils) && lexSigil(g)
        case Ch.backtick:
            if features.contains(.shell) {
                emit(pos, pos + 1, .punctuation)
                pos += 1
                lexInterpolation(g, closing: Ch.backtick)
                state.operandEnded = true
                return true
            }
            if features.contains(.backtickIdentifiers) {
                var cursor = pos + 1
                while cursor < end && units[cursor] != Ch.backtick && units[cursor] != Ch.newline { cursor += 1 }
                guard at(cursor) == Ch.backtick else { return false }
                pos = cursor + 1
                state.operandEnded = true
                return true
            }
            return false
        case Ch.backslash:
            if features.contains(.zigLiterals) && peek() == Ch.backslash {
                let stop = lineEnd(from: pos)
                emit(pos, stop, .string)
                pos = stop
                state.operandEnded = true
                return true
            }
            if features.contains(.shell) {
                pos = min(end, pos + 2)
                return true
            }
            return false
        case Ch.openBracket:
            if features.contains(.luaLongBrackets), let level = longBracketLevel(at: pos) {
                lexLongBracket(level: level, from: pos, bracketAt: pos, kind: .string)
                state.operandEnded = true
                return true
            }
            if features.contains(.powershell) && !state.operandEnded { return lexPowerShellType() }
            return false
        case Ch.minus:
            guard features.contains(.powershell) && Ch.isLetter(peek()) && !g.isWord(at(pos - 1)) else { return false }
            let stop = skipWord(from: pos + 1)
            let word = text(pos + 1, stop).lowercased()
            emit(pos, stop, NoteSyntaxGrammars.powershellOperators.contains(word) ? .operatorSymbol : .attribute)
            pos = stop
            state.operandEnded = false
            return true
        default:
            return false
        }
    }

    private mutating func lexAt(_ g: NoteSyntaxGrammar, lineStart: Bool) -> Bool {
        let features = g.features
        let next = peek()
        if features.contains(.objcLiterals) {
            if next == Ch.quote {
                let start = pos
                pos += 2
                lexStringBody(NoteSyntaxStringRule("\""), from: start, grammar: g)
                state.operandEnded = true
                return true
            }
            if Ch.isLetter(next) {
                let stop = skipWord(from: pos + 1)
                let word = text(pos + 1, stop)
                emit(pos, stop, word == "YES" || word == "NO" ? .constant : .keyword)
                if ["interface", "implementation", "protocol", "class"].contains(word) { state.pendingDeclaration = .type }
                pos = stop
                return true
            }
            if next == Ch.openBracket || next == Ch.openBrace || next == Ch.openParen {
                emit(pos, pos + 2, .punctuation)
                pos += 2
                state.operandEnded = false
                return true
            }
            if Ch.isDigit(next) {
                emit(pos, pos + 1, .number)
                pos += 1
                lexNumber(g)
                return true
            }
            return false
        }
        if features.contains(.csharpLiterals) {
            if next == Ch.quote || (next == Ch.dollar && peek(2) == Ch.quote) {
                let start = pos
                let interpolates = next == Ch.dollar
                pos += interpolates ? 3 : 2
                var rule = NoteSyntaxStringRule("\"", multiline: true, escapes: false, doubledClose: true)
                rule.interpolation = interpolates ? .brace : nil
                lexStringBody(rule, from: start, grammar: g)
                state.operandEnded = true
                return true
            }
            if g.isWordStart(next) {
                pos = skipWord(from: pos + 1)
                state.operandEnded = true
                return true
            }
            return false
        }
        if features.contains(.zigLiterals) {
            if next == Ch.quote {
                var cursor = pos + 2
                while cursor < end && units[cursor] != Ch.quote && units[cursor] != Ch.newline {
                    cursor += units[cursor] == Ch.backslash ? 2 : 1
                }
                pos = min(end, cursor + 1)
                state.operandEnded = true
                return true
            }
            guard Ch.isLetter(next) else { return false }
            let stop = skipWord(from: pos + 1)
            emit(pos, stop, .builtin)
            pos = stop
            state.operandEnded = true
            return true
        }
        if features.contains(.powershell) {
            if (next == Ch.quote || next == Ch.apostrophe) && lineEnd(from: pos) == skipSpaces(from: pos + 2) {
                return lexPowerShellHereString(g, quote: next)
            }
            if next == Ch.openParen || next == Ch.openBrace {
                emit(pos, pos + 2, .punctuation)
                pos += 2
                state.operandEnded = false
                return true
            }
            guard g.isWordStart(next) else { return false }
            let stop = skipWord(from: pos + 1)
            emit(pos, stop, .variable)
            pos = stop
            state.operandEnded = true
            return true
        }
        if features.contains(.sqlLiterals) {
            var cursor = pos + 1
            if at(cursor) == Ch.at { cursor += 1 }
            guard g.isWordStart(at(cursor)) else { return false }
            let stop = skipWord(from: cursor)
            emit(pos, stop, .variable)
            pos = stop
            state.operandEnded = true
            return true
        }
        guard let kind = g.atKind else { return false }
        if features.contains(.decoratorsAtLineStart) && !lineStart { return false }
        var cursor = pos + 1
        if kind == .variable && at(cursor) == Ch.at { cursor += 1 }
        guard g.isWordStart(at(cursor)) else { return false }
        cursor = skipWord(from: cursor)
        if kind == .attribute {
            while at(cursor) == Ch.dot && g.isWordStart(at(cursor + 1)) { cursor = skipWord(from: cursor + 1) }
        }
        emit(pos, cursor, kind)
        pos = cursor
        state.operandEnded = true
        return true
    }

    private mutating func lexDollar(_ g: NoteSyntaxGrammar) -> Bool {
        let features = g.features
        if features.contains(.shell) { return lexShellDollar(g) }
        if features.contains(.powershell) { return lexPowerShellDollar(g) }
        if features.contains(.csharpLiterals) { return lexCSharpDollar(g) }
        if features.contains(.sqlLiterals) {
            var cursor = pos + 1
            while cursor < end && Ch.isWord(units[cursor]) && !Ch.isDigit(units[pos + 1]) { cursor += 1 }
            if at(cursor) == Ch.dollar {
                let tag = Array(units[pos...cursor])
                let close = find(tag, from: cursor + 1).map { $0 + tag.count } ?? end
                emit(pos, close, .string)
                pos = close
                state.operandEnded = true
                return true
            }
        }
        guard let kind = g.dollarKind, g.isWord(peek()) || peek() == Ch.dollar else { return false }
        let stop = skipWord(from: pos + 1)
        emit(pos, max(stop, pos + 2), kind)
        pos = max(stop, pos + 2)
        state.operandEnded = true
        return true
    }

    private mutating func lexCSharpDollar(_ g: NoteSyntaxGrammar) -> Bool {
        let start = pos
        var cursor = pos
        while at(cursor) == Ch.dollar { cursor += 1 }
        var verbatim = false
        if at(cursor) == Ch.at {
            verbatim = true
            cursor += 1
        }
        guard at(cursor) == Ch.quote else { return false }
        let raw = !verbatim && at(cursor + 1) == Ch.quote && at(cursor + 2) == Ch.quote
        var rule: NoteSyntaxStringRule
        if raw {
            rule = NoteSyntaxStringRule("\"\"\"", multiline: true, escapes: false)
            pos = cursor + 3
        } else {
            rule = NoteSyntaxStringRule("\"", multiline: verbatim, escapes: !verbatim, doubledClose: verbatim)
            pos = cursor + 1
        }
        rule.interpolation = .brace
        lexStringBody(rule, from: start, grammar: g)
        state.operandEnded = true
        return true
    }

    private mutating func lexPreprocessor() {
        let start = pos
        let wordStart = skipSpaces(from: pos + 1)
        let wordEnd = skipWord(from: wordStart)
        let directive = text(wordStart, wordEnd)
        pos = wordEnd
        switch directive {
        case "region", "endregion", "pragma", "error", "warning", "line":
            let stop = lineEnd(from: pos)
            emit(start, stop, .meta)
            pos = stop
        case "include", "import", "include_next":
            emit(start, wordEnd, .meta)
            let target = skipSpaces(from: pos)
            if at(target) == Ch.less, let close = find([Ch.greater], from: target + 1, limit: lineEnd(from: target)) {
                emit(target, close + 1, .string)
                pos = close + 1
            }
        default:
            emit(start, wordEnd, .meta)
        }
    }

    private mutating func lexSwiftHash(_ g: NoteSyntaxGrammar) -> Bool {
        var cursor = pos
        while at(cursor) == Ch.hash { cursor += 1 }
        let hashes = cursor - pos
        if at(cursor) == Ch.quote {
            let triple = at(cursor + 1) == Ch.quote && at(cursor + 2) == Ch.quote
            let quotes = triple ? 3 : 1
            let close = Array(repeating: Ch.quote, count: quotes) + Array(repeating: Ch.hash, count: hashes)
            var rule = NoteSyntaxStringRule(units: [], close: close, multiline: triple, escapes: true,
                                            interpolation: .backslashParen)
            rule.escapeHashes = hashes
            let start = pos
            pos = cursor + quotes
            lexStringBody(rule, from: start, grammar: g)
            state.operandEnded = true
            return true
        }
        if at(cursor) == Ch.slash {
            let close = [Ch.slash] + Array(repeating: Ch.hash, count: hashes)
            let limit = hashes > 1 ? end : lineEnd(from: cursor)
            guard let stop = find(close, from: cursor + 1, limit: limit) else { return false }
            emit(pos, stop + close.count, .regex)
            pos = stop + close.count
            state.operandEnded = true
            return true
        }
        guard hashes == 1 && g.isWordStart(at(cursor)) else { return false }
        let stop = skipWord(from: cursor)
        emit(pos, stop, .keyword)
        pos = stop
        return true
    }

    private mutating func lexBracketedAttribute() {
        let start = pos
        var cursor = pos + 1
        while at(cursor) != Ch.openBracket { cursor += 1 }
        cursor += 1
        var level = 1
        while cursor < end {
            let c = units[cursor]
            if c == Ch.quote {
                cursor += 1
                while cursor < end && units[cursor] != Ch.quote {
                    cursor += units[cursor] == Ch.backslash ? 2 : 1
                }
            } else if c == Ch.openBracket {
                level += 1
            } else if c == Ch.closeBracket {
                level -= 1
                if level == 0 {
                    cursor += 1
                    break
                }
            }
            cursor += 1
        }
        pos = min(cursor, end)
        emit(start, pos, .attribute)
    }

    private mutating func lexRustQuote() -> Bool {
        let start = pos
        let next = peek()
        if next == Ch.backslash {
            let stop = escapeEnd(from: pos + 2)
            guard at(stop) == Ch.apostrophe else { return false }
            emit(start, start + 1, .string)
            emit(start + 1, stop, .escape)
            emit(stop, stop + 1, .string)
            pos = stop + 1
            state.operandEnded = true
            return true
        }
        if Ch.isWordStart(next) {
            let stop = skipWord(from: pos + 1)
            if at(stop) == Ch.apostrophe {
                emit(start, stop + 1, .string)
                pos = stop + 1
            } else {
                emit(start, stop, .variable)
                pos = stop
            }
            state.operandEnded = true
            return true
        }
        let width = next &- 0xD800 < 0x400 ? 2 : 1
        guard next != 0 && next != Ch.newline && at(pos + 1 + width) == Ch.apostrophe else { return false }
        emit(start, pos + 2 + width, .string)
        pos += 2 + width
        state.operandEnded = true
        return true
    }

    private mutating func lexRegex() -> Bool {
        var cursor = pos + 1
        var inClass = false
        while cursor < end {
            let c = units[cursor]
            if c == Ch.newline { break }
            if c == Ch.backslash {
                cursor += 2
                continue
            }
            if c == Ch.openBracket {
                inClass = true
            } else if c == Ch.closeBracket {
                inClass = false
            } else if c == Ch.slash && !inClass {
                break
            }
            cursor += 1
        }
        guard cursor < end, at(cursor) == Ch.slash, cursor > pos + 1 else {
            regexFailUntil = lineEnd(from: pos)
            return false
        }
        cursor += 1
        while Ch.isLetter(at(cursor)) { cursor += 1 }
        emit(pos, cursor, .regex)
        pos = cursor
        state.operandEnded = true
        return true
    }

    private mutating func lexJSXElement(_ g: NoteSyntaxGrammar) {
        guard depth < Self.depthLimit else {
            pos += 1
            return
        }
        depth += 1
        defer { depth -= 1 }
        emit(pos, pos + 1, .punctuation)
        pos += 1
        if at(pos) == Ch.greater {
            emit(pos, pos + 1, .punctuation)
            pos += 1
            lexJSXChildren(g)
            return
        }
        let nameStart = pos
        while pos < end && (g.isWord(units[pos]) || units[pos] == Ch.dot || units[pos] == Ch.minus || units[pos] == Ch.colon) {
            pos += 1
        }
        emit(nameStart, pos, .tag)
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
                lexJSXChildren(g)
                return
            } else if c == Ch.openBrace {
                emit(pos, pos + 1, .punctuation)
                pos += 1
                lexInterpolation(g, closing: Ch.closeBrace)
            } else if c == Ch.equals {
                emit(pos, pos + 1, .operatorSymbol)
                pos += 1
            } else if c == Ch.quote || c == Ch.apostrophe {
                let start = pos
                pos += 1
                lexStringBody(NoteSyntaxStringRule(c == Ch.quote ? "\"" : "'", multiline: true, escapes: false),
                              from: start, grammar: nil)
            } else if c == Ch.less && Ch.isLetter(peek()) {
                lexJSXElement(g)
            } else if g.isWordStart(c) {
                let start = pos
                while pos < end && (g.isWord(units[pos]) || units[pos] == Ch.minus || units[pos] == Ch.colon) { pos += 1 }
                emit(start, pos, .attribute)
            } else if lexTrivia(g, c) {
                continue
            } else {
                return
            }
        }
    }

    private mutating func lexJSXChildren(_ g: NoteSyntaxGrammar) {
        while pos < end {
            let c = units[pos]
            if c == Ch.openBrace {
                emit(pos, pos + 1, .punctuation)
                pos += 1
                lexInterpolation(g, closing: Ch.closeBrace)
            } else if c == Ch.less && peek() == Ch.slash {
                emit(pos, pos + 2, .punctuation)
                pos += 2
                let nameStart = pos
                while pos < end && (g.isWord(units[pos]) || units[pos] == Ch.dot || units[pos] == Ch.minus || units[pos] == Ch.colon) {
                    pos += 1
                }
                emit(nameStart, pos, .tag)
                pos = skipSpaces(from: pos)
                if at(pos) == Ch.greater {
                    emit(pos, pos + 1, .punctuation)
                    pos += 1
                }
                return
            } else if c == Ch.less && (Ch.isLetter(peek()) || peek() == Ch.greater) {
                lexJSXElement(g)
            } else if c == Ch.ampersand && lexEntity() {
                continue
            } else {
                pos += 1
            }
        }
    }

    private mutating func lexHeredocStart(_ g: NoteSyntaxGrammar) -> Bool {
        let features = g.features
        let start = pos
        var cursor = pos + 2
        var indented = false
        var trailing = false
        if features.contains(.phpLiterals) {
            guard at(cursor) == Ch.less else { return false }
            cursor = skipSpaces(from: cursor + 1)
            indented = true
            trailing = true
        } else if features.contains(.shell) {
            if at(cursor) == Ch.less {
                emit(pos, pos + 3, .operatorSymbol)
                pos += 3
                state.commandPosition = false
                return true
            }
            if at(cursor) == Ch.minus {
                indented = true
                cursor += 1
            }
            cursor = skipSpaces(from: cursor)
        } else {
            if at(cursor) == Ch.tilde || at(cursor) == Ch.minus {
                indented = true
                cursor += 1
            } else {
                let next = at(cursor)
                guard Ch.isUpper(next) || next == Ch.quote || next == Ch.apostrophe else { return false }
                guard !state.operandEnded || at(pos - 1) == Ch.space else { return false }
            }
        }
        var quoted = false
        let delimiterStart = cursor
        let open = at(cursor)
        let wordStart: Int
        let wordEnd: Int
        if open == Ch.quote || open == Ch.apostrophe {
            quoted = open == Ch.apostrophe || features.contains(.shell)
            wordStart = cursor + 1
            var probe = wordStart
            while probe < end && units[probe] != open && units[probe] != Ch.newline { probe += 1 }
            guard at(probe) == open, probe > wordStart else { return false }
            wordEnd = probe
            cursor = probe + 1
        } else {
            if open == Ch.backslash && features.contains(.shell) {
                quoted = true
                cursor += 1
            }
            wordStart = cursor
            var probe = cursor
            while probe < end && (Ch.isWord(units[probe]) || (features.contains(.shell) && units[probe] == Ch.minus)) { probe += 1 }
            guard probe > wordStart else { return false }
            wordEnd = probe
            cursor = probe
        }
        emit(start, delimiterStart, .operatorSymbol)
        emit(delimiterStart, cursor, .string)
        heredocs.append(NoteSyntaxHeredoc(terminator: Array(units[wordStart..<wordEnd]), indented: indented,
                                          interpolates: !quoted, trailingPunctuation: trailing))
        pos = cursor
        state.operandEnded = true
        state.commandPosition = false
        return true
    }

    private mutating func lexPercentLiteral(_ g: NoteSyntaxGrammar) -> Bool {
        guard !state.operandEnded || (at(pos - 1) == Ch.space && !Ch.isSpaceOrNewline(peek()) && peek() != Ch.equals) else {
            return false
        }
        var cursor = pos + 1
        var type: UInt16 = 0
        if Ch.isLetter(at(cursor)) {
            type = at(cursor)
            guard "qQwWiIrsx".utf16.contains(type) else { return false }
            cursor += 1
        }
        let open = at(cursor)
        guard open != 0, !Ch.isWord(open), !Ch.isSpaceOrNewline(open) else { return false }
        if type == 0 && open == Ch.equals { return false }
        let close = Ch.closer(for: open)
        let interpolates = type == 0 || "QWIrx".utf16.contains(type)
        let kind: NoteSyntaxKind = type == 114 ? .regex : type == 115 ? .constant : .string
        let start = pos
        var segment = start
        var level = 1
        pos = cursor + 1
        while pos < end {
            let c = units[pos]
            if c == Ch.backslash {
                pos += 2
                continue
            }
            if close != open && c == open {
                level += 1
            } else if c == close {
                level -= 1
                if level == 0 {
                    pos += 1
                    break
                }
            } else if interpolates && c == Ch.hash && peek() == Ch.openBrace {
                emit(segment, pos, kind)
                emit(pos, pos + 2, .punctuation)
                pos += 2
                lexInterpolation(g, closing: Ch.closeBrace)
                segment = pos
                continue
            }
            pos += 1
        }
        pos = min(pos, end)
        if kind == .regex { while Ch.isLetter(at(pos)) { pos += 1 } }
        emit(segment, pos, kind)
        state.operandEnded = true
        return true
    }

    private mutating func lexSymbolLiteral(_ g: NoteSyntaxGrammar) -> Bool {
        let next = peek()
        guard at(pos - 1) != Ch.colon && next != Ch.colon && !g.isWord(at(pos - 1)) else { return false }
        if g.isWordStart(next) {
            var stop = skipWord(from: pos + 1)
            if (at(stop) == Ch.question || at(stop) == Ch.bang) && at(stop + 1) != Ch.equals { stop += 1 }
            emit(pos, stop, .constant)
            pos = stop
            state.operandEnded = true
            return true
        }
        if next == Ch.quote {
            let start = pos
            pos += 2
            var rule = NoteSyntaxStringRule("\"", kind: .constant)
            rule.interpolation = .hashBrace
            lexStringBody(rule, from: start, grammar: g)
            state.operandEnded = true
            return true
        }
        return false
    }

    private mutating func lexSigil(_ g: NoteSyntaxGrammar) -> Bool {
        var cursor = pos + 1
        let letter = at(cursor)
        guard Ch.isLetter(letter) else { return false }
        cursor += 1
        if Ch.isUpper(letter) { while Ch.isUpper(at(cursor)) { cursor += 1 } }
        let open = at(cursor)
        guard "/|\"'([{<".utf16.contains(open) else { return false }
        let interpolates = Ch.isLower(letter)
        let kind: NoteSyntaxKind = Ch.lowered(letter) == 114 ? .regex : .string
        let triple = (open == Ch.quote || open == Ch.apostrophe) && at(cursor + 1) == open && at(cursor + 2) == open
        let delimiter = triple ? [open, open, open] : [open]
        var rule = NoteSyntaxStringRule(units: delimiter, close: triple ? delimiter : [Ch.closer(for: open)], multiline: true,
                                        escapes: true, interpolation: interpolates ? .hashBrace : nil)
        rule.kind = kind
        rule.rawEscapes = !interpolates
        let start = pos
        pos = cursor + delimiter.count
        lexStringBody(rule, from: start, grammar: g)
        let modifiers = pos
        while Ch.isLetter(at(pos)) { pos += 1 }
        emit(modifiers, pos, kind)
        state.operandEnded = true
        return true
    }

    func longBracketLevel(at index: Int) -> Int? {
        guard at(index) == Ch.openBracket else { return nil }
        var cursor = index + 1
        while at(cursor) == Ch.equals { cursor += 1 }
        return at(cursor) == Ch.openBracket ? cursor - index - 1 : nil
    }

    mutating func lexLongBracket(level: Int, from start: Int, bracketAt bracket: Int, kind: NoteSyntaxKind) {
        let close = [Ch.closeBracket] + Array(repeating: Ch.equals, count: level) + [Ch.closeBracket]
        let stop = find(close, from: bracket + level + 2).map { $0 + close.count } ?? end
        emit(start, stop, kind)
        pos = stop
    }

    mutating func lexShellDollar(_ g: NoteSyntaxGrammar) -> Bool {
        let start = pos
        if makeMode {
            if peek() == Ch.dollar {
                pos += 1
                if lexShellDollarCore(g, tokenStart: start) { return true }
                emit(start, start + 2, .variable)
                pos = start + 2
                return true
            }
            return lexMakeReference()
        }
        return lexShellDollarCore(g, tokenStart: start)
    }

    private mutating func lexShellDollarCore(_ g: NoteSyntaxGrammar, tokenStart: Int) -> Bool {
        let next = peek()
        switch next {
        case Ch.openParen:
            if peek(2) == Ch.openParen {
                emit(tokenStart, pos + 3, .punctuation)
                pos += 3
                lexInterpolation(g, closing: Ch.closeParen)
                if at(pos) == Ch.closeParen {
                    emit(pos, pos + 1, .punctuation)
                    pos += 1
                }
            } else {
                emit(tokenStart, pos + 2, .punctuation)
                pos += 2
                lexInterpolation(g, closing: Ch.closeParen)
            }
        case Ch.openBrace:
            var cursor = pos + 2
            var level = 1
            while cursor < end {
                let c = units[cursor]
                if c == Ch.newline { break }
                if c == Ch.openBrace {
                    level += 1
                } else if c == Ch.closeBrace {
                    level -= 1
                    if level == 0 {
                        cursor += 1
                        break
                    }
                }
                cursor += 1
            }
            emit(tokenStart, cursor, .variable)
            pos = cursor
        case Ch.apostrophe:
            pos += 2
            lexStringBody(NoteSyntaxStringRule("'", multiline: true), from: tokenStart, grammar: g)
        case Ch.quote:
            pos += 2
            var rule = NoteSyntaxStringRule("\"", multiline: true)
            rule.interpolation = .shell
            lexStringBody(rule, from: tokenStart, grammar: g)
        default:
            if Ch.isLetter(next) || next == Ch.underscore {
                var cursor = pos + 1
                while cursor < end && (Ch.isLetter(units[cursor]) || Ch.isDigit(units[cursor]) || units[cursor] == Ch.underscore) {
                    cursor += 1
                }
                emit(tokenStart, cursor, .variable)
                pos = cursor
            } else if Ch.isDigit(next) || "@*#?$!-".utf16.contains(next) {
                emit(tokenStart, pos + 2, .variable)
                pos += 2
            } else {
                return false
            }
        }
        state.operandEnded = true
        state.commandPosition = false
        return true
    }

    mutating func lexMakeReference() -> Bool {
        let start = pos
        let next = peek()
        if next == Ch.openParen || next == Ch.openBrace {
            let close = Ch.closer(for: next)
            let nameStart = pos + 2
            var nameEnd = nameStart
            while nameEnd < end && (Ch.isWord(units[nameEnd]) || units[nameEnd] == Ch.minus) { nameEnd += 1 }
            if Ch.isSpace(at(nameEnd)) && NoteSyntaxGrammars.makeFunctions.contains(text(nameStart, nameEnd)) {
                emit(start, nameStart, .punctuation)
                emit(nameStart, nameEnd, .builtin)
                pos = nameEnd
                lexMakeArguments(open: next, close: close)
                return true
            }
            var cursor = pos + 2
            var level = 1
            while cursor < end {
                let c = units[cursor]
                if c == Ch.newline { break }
                if c == next {
                    level += 1
                } else if c == close {
                    level -= 1
                    if level == 0 {
                        cursor += 1
                        break
                    }
                }
                cursor += 1
            }
            emit(start, cursor, .variable)
            pos = cursor
            return true
        }
        guard next != 0 && !Ch.isSpaceOrNewline(next) else { return false }
        emit(start, pos + 2, .variable)
        pos += 2
        return true
    }

    private mutating func lexMakeArguments(open: UInt16, close: UInt16) {
        var level = 0
        while pos < end {
            let c = units[pos]
            if c == Ch.newline && at(pos - 1) != Ch.backslash { return }
            if c == Ch.dollar && lexMakeReference() { continue }
            if c == open {
                level += 1
            } else if c == close {
                if level == 0 {
                    emit(pos, pos + 1, .punctuation)
                    pos += 1
                    return
                }
                level -= 1
            } else if c == Ch.comma {
                emit(pos, pos + 1, .punctuation)
            }
            pos += 1
        }
    }

    mutating func lexPowerShellDollar(_ g: NoteSyntaxGrammar) -> Bool {
        let start = pos
        let next = peek()
        if next == Ch.openParen {
            emit(pos, pos + 2, .punctuation)
            pos += 2
            lexInterpolation(g, closing: Ch.closeParen)
            state.operandEnded = true
            return true
        }
        if next == Ch.openBrace, let close = find([Ch.closeBrace], from: pos + 2, limit: lineEnd(from: pos)) {
            emit(pos, close + 1, .variable)
            pos = close + 1
            state.operandEnded = true
            return true
        }
        if Ch.isWordStart(next) {
            var stop = skipWord(from: pos + 1)
            if at(stop) == Ch.colon && Ch.isWordStart(at(stop + 1)) { stop = skipWord(from: stop + 1) }
            let name = text(start + 1, stop).lowercased()
            emit(start, stop, ["true", "false", "null"].contains(name) ? .constant : .variable)
            pos = stop
            state.operandEnded = true
            return true
        }
        if next == Ch.question || next == Ch.caret || next == Ch.dollar {
            emit(pos, pos + 2, .variable)
            pos += 2
            state.operandEnded = true
            return true
        }
        return false
    }

    private mutating func lexPowerShellHereString(_ g: NoteSyntaxGrammar, quote: UInt16) -> Bool {
        let start = pos
        var lineStart = lineEnd(from: pos) + 1
        var close = end
        while lineStart < end {
            if at(lineStart) == quote && at(lineStart + 1) == Ch.at {
                close = lineStart + 2
                break
            }
            lineStart = lineEnd(from: lineStart) + 1
        }
        if quote == Ch.apostrophe {
            emit(start, close, .string)
            pos = close
        } else {
            let savedEnd = end
            end = close
            pos = start + 2
            var rule = NoteSyntaxStringRule(units: [], close: [], multiline: true, escapes: true, interpolation: .powershell)
            rule.escape = Ch.backtick
            lexStringBody(rule, from: start, grammar: g)
            end = savedEnd
            pos = close
        }
        state.operandEnded = true
        return true
    }

    private mutating func lexPowerShellType() -> Bool {
        var cursor = pos + 1
        guard Ch.isLetter(at(cursor)) else { return false }
        var level = 1
        let limit = lineEnd(from: pos)
        while cursor < limit {
            let c = units[cursor]
            if c == Ch.openBracket {
                level += 1
            } else if c == Ch.closeBracket {
                level -= 1
                if level == 0 { break }
            } else if !(Ch.isWord(c) || c == Ch.dot || c == Ch.comma || c == Ch.space || c == Ch.backtick) {
                return false
            }
            cursor += 1
        }
        guard at(cursor) == Ch.closeBracket else { return false }
        emit(pos, pos + 1, .punctuation)
        emit(pos + 1, cursor, .type)
        emit(cursor, cursor + 1, .punctuation)
        pos = cursor + 1
        state.operandEnded = false
        return true
    }
}
