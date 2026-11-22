import Foundation

private typealias Ch = NoteSyntaxChar

enum NoteSyntaxStyleMode {
    case statementStart, selector, atRule, property, value
}

extension NoteSyntaxScanner {
    mutating func lexStyles(scss: Bool) {
        var mode = NoteSyntaxStyleMode.statementStart
        var atRuleName = ""
        while pos < end {
            let c = units[pos]
            if Ch.isSpaceOrNewline(c) {
                pos += 1
                continue
            }
            if lexStyleComment(scss: scss) { continue }
            if mode == .statementStart {
                mode = styleMode(scss: scss)
                atRuleName = ""
            }
            switch c {
            case Ch.openBrace:
                emit(pos, pos + 1, .punctuation)
                pos += 1
                mode = .statementStart
            case Ch.closeBrace:
                emit(pos, pos + 1, .punctuation)
                pos += 1
                mode = .statementStart
            case Ch.semicolon:
                emit(pos, pos + 1, .punctuation)
                pos += 1
                mode = .statementStart
            case Ch.quote, Ch.apostrophe:
                lexStyleString()
            default:
                switch mode {
                case .selector:
                    lexSelectorToken(scss: scss)
                case .property:
                    if c == Ch.colon {
                        emit(pos, pos + 1, .punctuation)
                        pos += 1
                        mode = .value
                    } else {
                        lexPropertyToken(scss: scss)
                    }
                case .atRule:
                    if c == Ch.at && atRuleName.isEmpty {
                        let stop = styleWordEnd(from: pos + 1)
                        atRuleName = text(pos + 1, stop)
                        emit(pos, stop, .keyword)
                        pos = stop
                    } else {
                        lexStyleValueToken(scss: scss, atRule: atRuleName)
                    }
                case .value, .statementStart:
                    lexStyleValueToken(scss: scss, atRule: nil)
                }
            }
        }
    }

    private mutating func lexStyleComment(scss: Bool) -> Bool {
        guard units[pos] == Ch.slash else { return false }
        if peek() == Ch.star {
            let stop = find([Ch.star, Ch.slash], from: pos + 2).map { $0 + 2 } ?? end
            emit(pos, stop, .comment)
            pos = stop
            return true
        }
        if scss && peek() == Ch.slash && !(pos > 0 && at(pos - 1) == Ch.colon) {
            let stop = lineEnd(from: pos)
            emit(pos, stop, .comment)
            pos = stop
            return true
        }
        return false
    }

    private mutating func lexStyleString() {
        let start = pos
        let quote = units[pos]
        pos += 1
        lexStringBody(NoteSyntaxStringRule(quote == Ch.quote ? "\"" : "'"), from: start, grammar: nil)
    }

    private func styleMode(scss: Bool) -> NoteSyntaxStyleMode {
        let c = units[pos]
        if c == Ch.at { return .atRule }
        var cursor = pos
        while cursor < end {
            let unit = units[cursor]
            if unit == Ch.quote || unit == Ch.apostrophe {
                cursor += 1
                while cursor < end && units[cursor] != unit && units[cursor] != Ch.newline {
                    cursor += units[cursor] == Ch.backslash ? 2 : 1
                }
            } else if unit == Ch.slash && at(cursor + 1) == Ch.star {
                cursor = find([Ch.star, Ch.slash], from: cursor + 2).map { $0 + 1 } ?? end
            } else if unit == Ch.hash && at(cursor + 1) == Ch.openBrace {
                cursor = find([Ch.closeBrace], from: cursor + 2) ?? end
            } else if unit == Ch.openBrace {
                return .selector
            } else if unit == Ch.semicolon || unit == Ch.closeBrace {
                return .property
            }
            cursor += 1
        }
        return find([Ch.colon], from: pos, limit: lineEnd(from: pos)) == nil ? .selector : .property
    }

    private func styleWordEnd(from index: Int) -> Int {
        var cursor = index
        while cursor < end && (Ch.isWord(units[cursor]) || units[cursor] == Ch.minus) { cursor += 1 }
        return cursor
    }

    private mutating func lexStyleInterpolation(scss: Bool) -> Bool {
        guard scss && units[pos] == Ch.hash && peek() == Ch.openBrace else { return false }
        emit(pos, pos + 2, .punctuation)
        pos += 2
        while pos < end && units[pos] != Ch.closeBrace {
            if Ch.isSpaceOrNewline(units[pos]) {
                pos += 1
            } else if units[pos] == Ch.quote || units[pos] == Ch.apostrophe {
                lexStyleString()
            } else {
                lexStyleValueToken(scss: scss, atRule: nil)
            }
        }
        if pos < end {
            emit(pos, pos + 1, .punctuation)
            pos += 1
        }
        return true
    }

    private mutating func lexSelectorToken(scss: Bool) {
        let c = units[pos]
        if lexStyleInterpolation(scss: scss) { return }
        switch c {
        case Ch.dot, Ch.hash, Ch.percent:
            let stop = styleWordEnd(from: pos + 1)
            if stop > pos + 1 {
                emit(pos, stop, .attribute)
                pos = stop
            } else {
                pos += 1
            }
        case Ch.colon:
            var cursor = pos + 1
            if at(cursor) == Ch.colon { cursor += 1 }
            let stop = styleWordEnd(from: cursor)
            emit(pos, stop, .keyword)
            pos = stop
        case Ch.openBracket:
            emit(pos, pos + 1, .punctuation)
            pos += 1
            let nameStart = skipSpaces(from: pos)
            let nameEnd = styleWordEnd(from: nameStart)
            emit(nameStart, nameEnd, .attribute)
            pos = nameEnd
            while pos < end && units[pos] != Ch.closeBracket && units[pos] != Ch.newline {
                let unit = units[pos]
                if unit == Ch.quote || unit == Ch.apostrophe {
                    lexStyleString()
                } else if "=~|^$*".utf16.contains(unit) {
                    emit(pos, pos + 1, .operatorSymbol)
                    pos += 1
                } else if Ch.isWordStart(unit) || unit == Ch.minus {
                    let stop = styleWordEnd(from: pos)
                    emit(pos, stop, .string)
                    pos = stop
                } else {
                    pos += 1
                }
            }
            if at(pos) == Ch.closeBracket {
                emit(pos, pos + 1, .punctuation)
                pos += 1
            }
        case Ch.ampersand:
            emit(pos, pos + 1, .keyword)
            pos += 1
        case Ch.star:
            emit(pos, pos + 1, .tag)
            pos += 1
        case Ch.greater, Ch.plus, Ch.tilde:
            emit(pos, pos + 1, .operatorSymbol)
            pos += 1
        case Ch.comma, Ch.openParen, Ch.closeParen:
            emit(pos, pos + 1, .punctuation)
            pos += 1
        case Ch.dollar where scss:
            let stop = styleWordEnd(from: pos + 1)
            emit(pos, stop, .variable)
            pos = stop
        default:
            if Ch.isDigit(c) {
                lexStyleNumber()
            } else if Ch.isWordStart(c) || c == Ch.minus {
                let stop = styleWordEnd(from: pos)
                emit(pos, max(stop, pos + 1), .tag)
                pos = max(stop, pos + 1)
            } else {
                pos += 1
            }
        }
    }

    private mutating func lexPropertyToken(scss: Bool) {
        let c = units[pos]
        if lexStyleInterpolation(scss: scss) { return }
        if c == Ch.dollar || (c == Ch.minus && peek() == Ch.minus) {
            let stop = styleWordEnd(from: pos + 1)
            emit(pos, stop, .variable)
            pos = stop
        } else if Ch.isWordStart(c) || c == Ch.minus || c == Ch.star {
            let stop = styleWordEnd(from: pos + 1)
            emit(pos, stop, .property)
            pos = stop
        } else {
            lexStyleValueToken(scss: scss, atRule: nil)
        }
    }

    private mutating func lexStyleNumber() {
        let start = pos
        if units[pos] == Ch.minus || units[pos] == Ch.plus { pos += 1 }
        while Ch.isDigit(at(pos)) { pos += 1 }
        if at(pos) == Ch.dot && Ch.isDigit(at(pos + 1)) {
            pos += 1
            while Ch.isDigit(at(pos)) { pos += 1 }
        }
        if Ch.lowered(at(pos)) == 101 && (Ch.isDigit(at(pos + 1)) || (at(pos + 1) == Ch.minus && Ch.isDigit(at(pos + 2)))) {
            pos += 2
            while Ch.isDigit(at(pos)) { pos += 1 }
        }
        if at(pos) == Ch.percent {
            pos += 1
        } else {
            while Ch.isLetter(at(pos)) { pos += 1 }
        }
        emit(start, pos, .number)
    }

    private mutating func lexStyleValueToken(scss: Bool, atRule: String?) {
        let c = units[pos]
        if lexStyleInterpolation(scss: scss) { return }
        let previous = at(pos - 1)
        let signed = (c == Ch.minus || c == Ch.plus) && (Ch.isDigit(peek()) || (peek() == Ch.dot && Ch.isDigit(peek(2))))
            && (pos == 0 || Ch.isSpaceOrNewline(previous) || "(,:".utf16.contains(previous))
        if Ch.isDigit(c) || (c == Ch.dot && Ch.isDigit(peek())) || signed {
            lexStyleNumber()
            return
        }
        switch c {
        case Ch.hash:
            var stop = pos + 1
            while Ch.isHexDigit(at(stop)) { stop += 1 }
            if stop - pos > 3 && !Ch.isWord(at(stop)) {
                emit(pos, stop, .constant)
                pos = stop
            } else {
                stop = styleWordEnd(from: pos + 1)
                emit(pos, max(stop, pos + 1), .attribute)
                pos = max(stop, pos + 1)
            }
        case Ch.bang:
            let stop = styleWordEnd(from: skipSpaces(from: pos + 1))
            emit(pos, stop, .keyword)
            pos = max(stop, pos + 1)
        case Ch.dollar where scss:
            let stop = styleWordEnd(from: pos + 1)
            emit(pos, stop, .variable)
            pos = max(stop, pos + 1)
        case Ch.at:
            let stop = styleWordEnd(from: pos + 1)
            emit(pos, stop, .keyword)
            pos = max(stop, pos + 1)
        case Ch.ampersand:
            emit(pos, pos + 1, .keyword)
            pos += 1
        case Ch.openParen, Ch.closeParen, Ch.comma, Ch.colon:
            emit(pos, pos + 1, .punctuation)
            pos += 1
        case Ch.plus, Ch.minus, Ch.star, Ch.slash, Ch.equals, Ch.greater, Ch.less, Ch.percent:
            if c == Ch.minus && peek() == Ch.minus {
                let stop = styleWordEnd(from: pos + 2)
                emit(pos, stop, .variable)
                pos = stop
            } else if c == Ch.minus && Ch.isWordStart(peek()) {
                lexStyleWord(atRule: atRule)
            } else {
                emit(pos, pos + 1, .operatorSymbol)
                pos += 1
            }
        default:
            if Ch.isWordStart(c) {
                lexStyleWord(atRule: atRule)
            } else {
                pos += 1
            }
        }
    }

    private mutating func lexStyleWord(atRule: String?) {
        let start = pos
        let stop = styleWordEnd(from: pos + 1)
        pos = stop
        let word = text(start, stop).lowercased()
        if at(stop) == Ch.openParen {
            emit(start, stop, .function)
            if word == "url" && at(skipSpaces(from: stop + 1)) != Ch.quote && at(skipSpaces(from: stop + 1)) != Ch.apostrophe {
                emit(stop, stop + 1, .punctuation)
                let close = find([Ch.closeParen], from: stop + 1, limit: lineEnd(from: stop)) ?? lineEnd(from: stop)
                emit(stop + 1, close, .string)
                pos = close
            }
            return
        }
        if let atRule {
            if ["include", "extend", "mixin", "function"].contains(atRule) {
                emit(start, stop, .function)
            } else if ["and", "not", "only", "or", "from", "through", "to", "in", "if", "else", "as", "with"].contains(word) {
                emit(start, stop, .keyword)
            } else if at(skipSpaces(from: stop)) == Ch.colon {
                emit(start, stop, .property)
            } else {
                emit(start, stop, .constant)
            }
            return
        }
        emit(start, stop, .constant)
    }
}
