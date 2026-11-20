import Foundation

private typealias Ch = NoteSyntaxChar

extension NoteSyntaxScanner {
    mutating func lexCode(_ g: NoteSyntaxGrammar, closing: UInt16 = 0) {
        let opening: UInt16 = closing == Ch.closeParen ? Ch.openParen
            : closing == Ch.closeBrace ? Ch.openBrace
            : closing == Ch.closeBracket ? Ch.openBracket : 0
        let shell = g.features.contains(.shell)
        var nesting = 0
        while pos < end {
            let c = units[pos]
            if c == Ch.newline {
                pos += 1
                state.atLineStart = true
                if shell { state.commandPosition = true }
                if !heredocs.isEmpty { readHeredocs(g) }
                continue
            }
            if Ch.isSpace(c) {
                pos += 1
                continue
            }
            if closing != 0 {
                if c == closing && nesting == 0 { return }
                if c == opening { nesting += 1 } else if c == closing { nesting -= 1 }
            }
            if lexTrivia(g, c) { continue }
            let lineStart = state.atLineStart
            let member = state.memberAccess
            let declaration = state.pendingDeclaration
            state.atLineStart = false
            state.memberAccess = false
            state.pendingDeclaration = nil
            if lexSpecial(g, c, lineStart: lineStart) { continue }
            if lexStringRules(g, c) { continue }
            if startsNumber(g, c, member: member) {
                lexNumber(g)
                continue
            }
            if g.isWordStart(c) {
                lexWord(g, member: member, declaration: declaration, lineStart: lineStart)
                continue
            }
            lexSymbol(g, c)
        }
    }

    private func startsNumber(_ g: NoteSyntaxGrammar, _ c: UInt16, member: Bool) -> Bool {
        if Ch.isDigit(c) {
            guard g.features.contains(.shell) else { return true }
            var cursor = pos
            while cursor < end && Ch.isDigit(units[cursor]) { cursor += 1 }
            return !g.isWord(at(cursor))
        }
        if c == Ch.dot { return Ch.isDigit(peek()) && !state.operandEnded && !member && !g.isWord(at(pos - 1)) }
        if c == Ch.minus && g.features.contains(.signedNumbers) { return Ch.isDigit(peek()) && !state.operandEnded }
        return false
    }

    mutating func lexTrivia(_ g: NoteSyntaxGrammar, _ c: UInt16) -> Bool {
        let features = g.features
        if features.contains(.luaLongBrackets) && c == Ch.minus && peek() == Ch.minus,
           let level = longBracketLevel(at: pos + 2) {
            lexLongBracket(level: level, from: pos, bracketAt: pos + 2, kind: .comment)
            return true
        }
        if features.contains(.rubyLiterals) && c == Ch.equals && (pos == 0 || at(pos - 1) == Ch.newline)
            && matches("=begin", at: pos) {
            var cursor = lineEnd(from: pos)
            while cursor < end {
                cursor += 1
                if matches("=end", at: cursor) {
                    cursor = lineEnd(from: cursor)
                    break
                }
                cursor = lineEnd(from: cursor)
            }
            emit(pos, cursor, .comment)
            pos = cursor
            return true
        }
        for rule in g.blockComments where c == rule.open[0] && matches(rule.open, at: pos) {
            lexBlockComment(rule)
            return true
        }
        for marker in g.lineComments where c == marker[0] && matches(marker, at: pos) {
            if features.contains(.shell) && !atShellWordBoundary() { continue }
            if features.contains(.phpLiterals) && c == Ch.hash && peek() == Ch.openBracket { continue }
            if features.contains(.haskellDashes) && dashesFormOperator() { continue }
            let stop = lineEnd(from: pos)
            emit(pos, stop, .comment)
            pos = stop
            return true
        }
        return false
    }

    private func atShellWordBoundary() -> Bool {
        guard pos > 0 else { return true }
        let previous = units[pos - 1]
        return Ch.isSpaceOrNewline(previous) || previous == Ch.semicolon || previous == Ch.openParen
            || previous == Ch.pipe || previous == Ch.ampersand || previous == Ch.openBrace
    }

    private func dashesFormOperator() -> Bool {
        var cursor = pos
        while at(cursor) == Ch.minus { cursor += 1 }
        let next = at(cursor)
        return next != 0 && "!#$%&*+./<=>?@\\^|~:".utf16.contains(next)
    }

    mutating func lexBlockComment(_ rule: NoteSyntaxBlockComment) {
        let start = pos
        pos += rule.open.count
        var level = 1
        let closeFirst = rule.close[0]
        let openFirst = rule.open[0]
        while pos < end {
            let c = units[pos]
            if c == closeFirst && matches(rule.close, at: pos) {
                pos += rule.close.count
                level -= 1
                if level == 0 { break }
                continue
            }
            if rule.nests && c == openFirst && matches(rule.open, at: pos) {
                pos += rule.open.count
                level += 1
                continue
            }
            pos += 1
        }
        pos = min(pos, end)
        emit(start, pos, rule.kind)
    }

    mutating func lexStringRules(_ g: NoteSyntaxGrammar, _ c: UInt16) -> Bool {
        for rule in g.strings where rule.open[0] == c && matches(rule.open, at: pos) {
            let start = pos
            pos += rule.open.count
            lexStringBody(rule, from: start, grammar: g)
            finishString(g, from: start)
            return true
        }
        return false
    }

    mutating func finishString(_ g: NoteSyntaxGrammar, from start: Int) {
        state.operandEnded = true
        guard g.features.contains(.keysBeforeColon) else { return }
        let next = skipSpaces(from: pos)
        if at(next) == Ch.colon && at(next + 1) != Ch.colon { retag(from: start, to: pos, as: .property) }
    }

    mutating func lexStringBody(_ rule: NoteSyntaxStringRule, from start: Int, grammar g: NoteSyntaxGrammar?) {
        var segment = start
        let kind = rule.kind
        let closeFirst = rule.close.first ?? 0
        let closeCount = rule.close.count
        while pos < end {
            let c = units[pos]
            if c == closeFirst && closeFirst != 0 && matches(rule.close, at: pos) {
                if rule.doubledClose && matches(rule.close, at: pos + closeCount) {
                    pos += closeCount * 2
                    continue
                }
                pos += closeCount
                if kind == .regex { while Ch.isLetter(at(pos)) { pos += 1 } }
                emit(segment, pos, kind)
                return
            }
            if c == Ch.newline && !rule.multiline {
                emit(segment, pos, kind)
                return
            }
            if c == rule.escape && rule.escapes {
                if rule.rawEscapes || kind == .regex {
                    pos = min(end, pos + 2)
                    continue
                }
                var cursor = pos + 1
                if rule.escapeHashes > 0 {
                    var count = 0
                    while count < rule.escapeHashes && at(cursor) == Ch.hash {
                        count += 1
                        cursor += 1
                    }
                    if count < rule.escapeHashes {
                        pos += 1
                        continue
                    }
                }
                if rule.interpolation == .shell && !"$`\"\\\n".utf16.contains(at(cursor)) {
                    pos += 1
                    continue
                }
                if rule.interpolation == .backslashParen && at(cursor) == Ch.openParen, let g {
                    emit(segment, pos, kind)
                    emit(pos, cursor + 1, .punctuation)
                    pos = cursor + 1
                    lexInterpolation(g, closing: Ch.closeParen)
                    segment = pos
                    continue
                }
                let stop = escapeEnd(from: cursor)
                emit(segment, pos, kind)
                emit(pos, stop, .escape)
                pos = stop
                segment = pos
                continue
            }
            if let interpolation = rule.interpolation, let g,
               lexStringInterpolation(interpolation, c, grammar: g, kind: kind, segment: &segment) {
                continue
            }
            pos += 1
        }
        emit(segment, pos, kind)
    }

    func escapeEnd(from cursor: Int) -> Int {
        let c = at(cursor)
        if c == 0 { return cursor }
        if c == 117 || c == 120 {
            if at(cursor + 1) == Ch.openBrace {
                var probe = cursor + 2
                while probe < end && probe - cursor < 12 && Ch.isHexDigit(units[probe]) { probe += 1 }
                return at(probe) == Ch.closeBrace ? probe + 1 : cursor + 1
            }
            let limit = c == 117 ? 4 : 2
            var probe = cursor + 1
            while probe - cursor - 1 < limit && Ch.isHexDigit(at(probe)) { probe += 1 }
            return probe
        }
        if c == 85 {
            var probe = cursor + 1
            while probe - cursor - 1 < 8 && Ch.isHexDigit(at(probe)) { probe += 1 }
            return probe
        }
        if c &- 48 < 8 {
            var probe = cursor + 1
            while probe - cursor < 3 && at(probe) &- 48 < 8 { probe += 1 }
            return probe
        }
        if c &- 0xD800 < 0x400 && at(cursor + 1) &- 0xDC00 < 0x400 { return cursor + 2 }
        return cursor + 1
    }

    mutating func lexInterpolation(_ g: NoteSyntaxGrammar, closing: UInt16) {
        guard depth < Self.depthLimit else { return }
        let saved = state
        depth += 1
        state = NoteSyntaxScanState()
        lexCode(g, closing: closing)
        depth -= 1
        state = saved
        if pos < end && units[pos] == closing {
            emit(pos, pos + 1, .punctuation)
            pos += 1
        }
    }

    private mutating func openInterpolation(_ length: Int, closing: UInt16, grammar g: NoteSyntaxGrammar,
                                            kind: NoteSyntaxKind, segment: inout Int) {
        emit(segment, pos, kind)
        emit(pos, pos + length, .punctuation)
        pos += length
        lexInterpolation(g, closing: closing)
        segment = pos
    }

    private mutating func lexStringInterpolation(_ interpolation: NoteSyntaxInterpolation, _ c: UInt16,
                                                 grammar g: NoteSyntaxGrammar, kind: NoteSyntaxKind,
                                                 segment: inout Int) -> Bool {
        switch interpolation {
        case .backslashParen:
            return false
        case .dollarBrace:
            guard c == Ch.dollar && peek() == Ch.openBrace else { return false }
            openInterpolation(2, closing: Ch.closeBrace, grammar: g, kind: kind, segment: &segment)
            return true
        case .hashBrace:
            guard c == Ch.hash && peek() == Ch.openBrace else { return false }
            openInterpolation(2, closing: Ch.closeBrace, grammar: g, kind: kind, segment: &segment)
            return true
        case .dollarName:
            guard c == Ch.dollar else { return false }
            if peek() == Ch.openBrace {
                openInterpolation(2, closing: Ch.closeBrace, grammar: g, kind: kind, segment: &segment)
                return true
            }
            guard Ch.isLetter(peek()) || peek() == Ch.underscore else { return false }
            emit(segment, pos, kind)
            let stop = skipWord(from: pos + 1)
            emit(pos, stop, .variable)
            pos = stop
            segment = pos
            return true
        case .brace:
            if c == Ch.closeBrace && peek() == Ch.closeBrace {
                pos += 2
                return true
            }
            guard c == Ch.openBrace else { return false }
            if peek() == Ch.openBrace {
                pos += 2
                return true
            }
            openInterpolation(1, closing: Ch.closeBrace, grammar: g, kind: kind, segment: &segment)
            return true
        case .php:
            if c == Ch.openBrace && peek() == Ch.dollar {
                openInterpolation(1, closing: Ch.closeBrace, grammar: g, kind: kind, segment: &segment)
                return true
            }
            guard c == Ch.dollar else { return false }
            if peek() == Ch.openBrace, let close = find([Ch.closeBrace], from: pos + 2, limit: lineEnd(from: pos)) {
                emit(segment, pos, kind)
                emit(pos, close + 1, .variable)
                pos = close + 1
                segment = pos
                return true
            }
            guard Ch.isLetter(peek()) || peek() == Ch.underscore || peek() >= 0x80 else { return false }
            emit(segment, pos, kind)
            var stop = skipWord(from: pos + 1)
            emit(pos, stop, .variable)
            if at(stop) == Ch.minus && at(stop + 1) == Ch.greater && Ch.isWordStart(at(stop + 2)) {
                emit(stop, stop + 2, .operatorSymbol)
                let property = skipWord(from: stop + 2)
                emit(stop + 2, property, .property)
                stop = property
            }
            pos = stop
            segment = pos
            return true
        case .shell:
            if c == Ch.backtick {
                openInterpolation(1, closing: Ch.backtick, grammar: g, kind: kind, segment: &segment)
                return true
            }
            guard c == Ch.dollar else { return false }
            emit(segment, pos, kind)
            segment = pos
            if lexShellDollar(g) {
                segment = pos
                return true
            }
            return false
        case .powershell:
            guard c == Ch.dollar else { return false }
            emit(segment, pos, kind)
            segment = pos
            if lexPowerShellDollar(g) {
                segment = pos
                return true
            }
            return false
        }
    }

    mutating func lexNumber(_ g: NoteSyntaxGrammar) {
        let start = pos
        if units[pos] == Ch.minus || units[pos] == Ch.plus { pos += 1 }
        let separators = g.digitSeparators
        let first = at(pos)
        let marker = Ch.lowered(at(pos + 1))
        func isSeparator(_ unit: UInt16) -> Bool { !separators.isEmpty && separators.contains(unit) }
        if first == 48 && marker == 120 && Ch.isHexDigit(at(pos + 2)) {
            pos += 2
            while Ch.isHexDigit(at(pos)) || (isSeparator(at(pos)) && Ch.isHexDigit(at(pos + 1))) { pos += 1 }
            if at(pos) == Ch.dot && Ch.isHexDigit(at(pos + 1)) {
                pos += 1
                while Ch.isHexDigit(at(pos)) { pos += 1 }
            }
            if Ch.lowered(at(pos)) == 112 { consumeExponent() }
        } else if first == 48 && (marker == 98 || marker == 111) && Ch.isDigit(at(pos + 2)) {
            pos += 2
            while Ch.isDigit(at(pos)) || (isSeparator(at(pos)) && Ch.isDigit(at(pos + 1))) { pos += 1 }
        } else {
            while Ch.isDigit(at(pos)) || (isSeparator(at(pos)) && Ch.isDigit(at(pos + 1))) { pos += 1 }
            if at(pos) == Ch.dot && Ch.isDigit(at(pos + 1)) {
                pos += 1
                while Ch.isDigit(at(pos)) || (isSeparator(at(pos)) && Ch.isDigit(at(pos + 1))) { pos += 1 }
            }
            if Ch.lowered(at(pos)) == 101 { consumeExponent() }
        }
        while pos < end && g.isWord(units[pos]) && units[pos] != Ch.minus { pos += 1 }
        emit(start, pos, .number)
        state.operandEnded = true
    }

    private mutating func consumeExponent() {
        let next = at(pos + 1)
        if Ch.isDigit(next) {
            pos += 1
        } else if (next == Ch.plus || next == Ch.minus) && Ch.isDigit(at(pos + 2)) {
            pos += 2
        } else {
            return
        }
        while Ch.isDigit(at(pos)) || at(pos) == Ch.underscore { pos += 1 }
    }

    mutating func lexWord(_ g: NoteSyntaxGrammar, member: Bool, declaration: NoteSyntaxKind?, lineStart: Bool) {
        let start = pos
        pos += 1
        while pos < end && g.isWord(units[pos]) { pos += 1 }
        if g.features.contains(.powershell) {
            while at(pos) == Ch.minus && Ch.isLetter(at(pos + 1)) {
                pos += 1
                while pos < end && g.isWord(units[pos]) { pos += 1 }
            }
        }
        if !g.wordSuffixes.isEmpty && g.wordSuffixes.contains(at(pos)) && at(pos + 1) != Ch.equals {
            pos += 1
        }
        let next = at(pos)
        if g.prefixes != .none && (next == Ch.quote || next == Ch.apostrophe || next == Ch.hash)
            && lexPrefixedString(g, wordStart: start) {
            return
        }
        if let kind = classifyWord(g, start: start, member: member, declaration: declaration, lineStart: lineStart) {
            emit(start, pos, kind)
        }
    }

    private mutating func classifyWord(_ g: NoteSyntaxGrammar, start: Int, member: Bool,
                                       declaration: NoteSyntaxKind?, lineStart: Bool) -> NoteSyntaxKind? {
        let features = g.features
        let next = at(pos)
        state.operandEnded = true
        if features.contains(.symbols) && next == Ch.colon && at(pos + 1) != Ch.colon && !member {
            pos += 1
            state.operandEnded = false
            return .constant
        }
        if features.contains(.keysBeforeColon) && !member {
            let colon = skipSpaces(from: pos)
            if at(colon) == Ch.colon && at(colon + 1) != Ch.colon { return .property }
        }
        if features.contains(.shell) && next == Ch.equals && state.commandPosition {
            state.commandPosition = false
            return .variable
        }
        if member && features.contains(.memberProperties) {
            return next == Ch.openParen && features.contains(.callsAreFunctions) ? .function : .property
        }
        if let entry = g.words.lookup(units, start, pos) {
            switch entry.role {
            case .declaresFunction: state.pendingDeclaration = .function
            case .declaresType: state.pendingDeclaration = .type
            default: break
            }
            if features.contains(.shell) { state.commandPosition = entry.role == .startsCommand }
            state.operandEnded = entry.role == .operand || entry.kind != .keyword
            return entry.kind
        }
        if let declaration { return declaration }
        if features.contains(.shell) {
            defer { state.commandPosition = false }
            return state.commandPosition && units[start] != Ch.minus ? .function : nil
        }
        if features.contains(.lineStartFunctions) && lineStart && (start == 0 || units[start - 1] == Ch.newline)
            && Ch.isLower(units[start]) {
            return .function
        }
        if features.contains(.callsAreFunctions) && next == Ch.openParen { return .function }
        if features.contains(.powershell) && units[start..<pos].contains(Ch.minus) { return .function }
        if features.contains(.taggedTemplates) && next == Ch.backtick { return .function }
        if features.contains(.rustLiterals) && next == Ch.bang && at(pos + 1) != Ch.equals {
            pos += 1
            return .function
        }
        if features.contains(.zigLiterals) && pos - start > 1 && (units[start] == 105 || units[start] == 117) {
            var digits = true
            for index in (start + 1)..<pos where !Ch.isDigit(units[index]) { digits = false }
            if digits { return .type }
        }
        if features.contains(.capsConstants) && isAllCaps(start, pos) { return .constant }
        if features.contains(.capitalizedTypes) && Ch.isUpper(units[start]) { return .type }
        return nil
    }

    private func isAllCaps(_ start: Int, _ stop: Int) -> Bool {
        guard stop - start > 1 else { return false }
        var letters = 0
        for index in start..<stop {
            let unit = units[index]
            if Ch.isUpper(unit) { letters += 1 } else if !Ch.isDigit(unit) && unit != Ch.underscore { return false }
        }
        return letters > 1
    }

    mutating func lexSymbol(_ g: NoteSyntaxGrammar, _ c: UInt16) {
        let start = pos
        pos += 1
        let shell = g.features.contains(.shell)
        if g.punctuation.contains(c) {
            emit(start, pos, .punctuation)
            switch c {
            case Ch.closeParen, Ch.closeBracket, Ch.closeBrace:
                state.operandEnded = true
            case Ch.dot:
                state.operandEnded = false
                if at(pos) != Ch.dot && at(start - 1) != Ch.dot { state.memberAccess = true }
            default:
                state.operandEnded = false
            }
            if shell { state.commandPosition = c == Ch.openParen || c == Ch.openBrace || c == Ch.semicolon }
            return
        }
        if g.operators.contains(c) {
            if c == Ch.minus && at(pos) == Ch.greater && g.features.contains(.arrowMembers) {
                pos += 1
                emit(start, pos, .operatorSymbol)
                state.memberAccess = true
                state.operandEnded = false
                return
            }
            emit(start, pos, .operatorSymbol)
            state.operandEnded = false
            if shell {
                state.commandPosition = c == Ch.pipe || c == Ch.ampersand || c == Ch.semicolon || c == Ch.bang
            }
            return
        }
        state.operandEnded = false
    }

    mutating func lexPrefixedString(_ g: NoteSyntaxGrammar, wordStart start: Int) -> Bool {
        let prefix = text(start, pos)
        let lower = prefix.lowercased()
        let quote = at(pos)
        switch g.prefixes {
        case .none:
            return false
        case .python:
            let valid: Set<String> = ["r", "u", "b", "f", "t", "br", "rb", "fr", "rf", "tr", "rt"]
            guard quote != Ch.hash, valid.contains(lower) else { return false }
            let interpolates = lower.contains("f") || lower.contains("t")
            lexQuoted(from: start, escapes: true, rawEscapes: lower.contains("r"),
                      interpolation: interpolates ? .brace : nil, tripleIsRaw: false, grammar: g)
        case .dart:
            guard quote != Ch.hash, prefix == "r" else { return false }
            lexQuoted(from: start, escapes: false, rawEscapes: false, interpolation: nil, tripleIsRaw: false, grammar: g)
        case .scala:
            guard quote == Ch.quote else { return false }
            lexQuoted(from: start, escapes: prefix != "raw", rawEscapes: false, interpolation: .dollarName,
                      tripleIsRaw: true, grammar: g)
        case .rust:
            guard ["b", "r", "br", "c", "cr"].contains(prefix) else { return false }
            if prefix.contains("r") {
                var cursor = pos
                while at(cursor) == Ch.hash { cursor += 1 }
                guard at(cursor) == Ch.quote else { return false }
                let close = [Ch.quote] + Array(repeating: Ch.hash, count: cursor - pos)
                pos = cursor + 1
                let rule = NoteSyntaxStringRule(units: [], close: close, multiline: true, escapes: false, interpolation: nil)
                lexStringBody(rule, from: start, grammar: g)
            } else if quote == Ch.apostrophe && prefix == "b" {
                pos += 1
                lexStringBody(NoteSyntaxStringRule("'"), from: start, grammar: g)
            } else {
                guard quote == Ch.quote else { return false }
                pos += 1
                lexStringBody(NoteSyntaxStringRule("\"", multiline: true), from: start, grammar: g)
            }
        case .cpp:
            guard ["L", "u", "U", "u8", "R", "LR", "uR", "UR", "u8R"].contains(prefix), quote != Ch.hash else { return false }
            if prefix.hasSuffix("R") {
                guard quote == Ch.quote else { return false }
                var cursor = pos + 1
                while cursor < end && cursor - pos <= 17 && units[cursor] != Ch.openParen
                        && !Ch.isSpaceOrNewline(units[cursor]) && units[cursor] != Ch.backslash { cursor += 1 }
                guard at(cursor) == Ch.openParen else { return false }
                let close = [Ch.closeParen] + Array(units[(pos + 1)..<cursor]) + [Ch.quote]
                pos = cursor + 1
                let rule = NoteSyntaxStringRule(units: [], close: close, multiline: true, escapes: false, interpolation: nil)
                lexStringBody(rule, from: start, grammar: g)
            } else {
                pos += 1
                lexStringBody(NoteSyntaxStringRule(quote == Ch.quote ? "\"" : "'"), from: start, grammar: g)
            }
        case .r:
            guard lower == "r", quote != Ch.hash else { return false }
            var cursor = pos + 1
            while at(cursor) == Ch.minus { cursor += 1 }
            let bracket = at(cursor)
            guard bracket == Ch.openParen || bracket == Ch.openBracket || bracket == Ch.openBrace else { return false }
            let close = [Ch.closer(for: bracket)] + Array(units[(pos + 1)..<cursor]) + [quote]
            pos = cursor + 1
            let rule = NoteSyntaxStringRule(units: [], close: close, multiline: true, escapes: false, interpolation: nil)
            lexStringBody(rule, from: start, grammar: g)
        case .sql:
            guard quote == Ch.apostrophe, ["e", "n", "x", "b"].contains(lower) else { return false }
            pos += 1
            let rule = NoteSyntaxStringRule("'", multiline: true, escapes: lower == "e", doubledClose: true)
            lexStringBody(rule, from: start, grammar: g)
        }
        finishString(g, from: start)
        return true
    }

    private mutating func lexQuoted(from start: Int, escapes: Bool, rawEscapes: Bool,
                                    interpolation: NoteSyntaxInterpolation?, tripleIsRaw: Bool,
                                    grammar g: NoteSyntaxGrammar) {
        let quote = at(pos)
        let triple = at(pos + 1) == quote && at(pos + 2) == quote
        let delimiter = Array(repeating: quote, count: triple ? 3 : 1)
        var rule = NoteSyntaxStringRule(units: delimiter, close: delimiter, multiline: triple,
                                        escapes: escapes && !(triple && tripleIsRaw), interpolation: interpolation)
        rule.rawEscapes = rawEscapes
        if rawEscapes { rule.escapes = true }
        pos += delimiter.count
        lexStringBody(rule, from: start, grammar: g)
    }

    mutating func readHeredocs(_ g: NoteSyntaxGrammar) {
        let pending = heredocs
        heredocs = []
        for (index, doc) in pending.enumerated() {
            let bodyStart = pos
            var lineStart = pos
            var found: (line: Int, start: Int, stop: Int)?
            while lineStart < end {
                let stop = lineEnd(from: lineStart)
                let cursor = doc.indented ? skipSpaces(from: lineStart) : lineStart
                if matches(doc.terminator, at: cursor) {
                    let after = cursor + doc.terminator.count
                    let rest = skipSpaces(from: after)
                    if rest == stop || (doc.trailingPunctuation && !Ch.isWord(at(after))) {
                        found = (lineStart, cursor, after)
                        break
                    }
                }
                lineStart = stop + 1
            }
            let bodyEnd = found?.line ?? end
            lexHeredocBody(doc, from: bodyStart, to: bodyEnd, grammar: g)
            guard let found else {
                pos = end
                return
            }
            emit(found.start, found.stop, .string)
            pos = found.stop
            if index < pending.count - 1 { pos = min(end, lineEnd(from: pos) + 1) }
        }
    }

    private mutating func lexHeredocBody(_ doc: NoteSyntaxHeredoc, from start: Int, to stop: Int, grammar g: NoteSyntaxGrammar) {
        guard stop > start else {
            pos = stop
            return
        }
        let interpolation: NoteSyntaxInterpolation? = g.features.contains(.shell) ? .shell
            : g.features.contains(.rubyLiterals) ? .hashBrace
            : g.features.contains(.phpLiterals) ? .php : nil
        guard doc.interpolates, let interpolation else {
            emit(start, stop, .string)
            pos = stop
            return
        }
        let savedEnd = end
        end = stop
        pos = start
        let rule = NoteSyntaxStringRule(units: [], close: [], multiline: true, escapes: true, interpolation: interpolation)
        lexStringBody(rule, from: start, grammar: g)
        end = savedEnd
        pos = stop
    }
}
