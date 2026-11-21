import Foundation

package enum NoteSyntaxChar {
    package static var newline: UInt16 { 10 }
    package static var tab: UInt16 { 9 }
    package static var carriageReturn: UInt16 { 13 }
    package static var space: UInt16 { 32 }
    package static var bang: UInt16 { 33 }
    package static var quote: UInt16 { 34 }
    package static var hash: UInt16 { 35 }
    package static var dollar: UInt16 { 36 }
    package static var percent: UInt16 { 37 }
    package static var ampersand: UInt16 { 38 }
    package static var apostrophe: UInt16 { 39 }
    package static var openParen: UInt16 { 40 }
    package static var closeParen: UInt16 { 41 }
    package static var star: UInt16 { 42 }
    package static var plus: UInt16 { 43 }
    package static var comma: UInt16 { 44 }
    package static var minus: UInt16 { 45 }
    package static var dot: UInt16 { 46 }
    package static var slash: UInt16 { 47 }
    package static var colon: UInt16 { 58 }
    package static var semicolon: UInt16 { 59 }
    package static var less: UInt16 { 60 }
    package static var equals: UInt16 { 61 }
    package static var greater: UInt16 { 62 }
    package static var question: UInt16 { 63 }
    package static var at: UInt16 { 64 }
    package static var openBracket: UInt16 { 91 }
    package static var backslash: UInt16 { 92 }
    package static var closeBracket: UInt16 { 93 }
    package static var caret: UInt16 { 94 }
    package static var underscore: UInt16 { 95 }
    package static var backtick: UInt16 { 96 }
    package static var openBrace: UInt16 { 123 }
    package static var pipe: UInt16 { 124 }
    package static var closeBrace: UInt16 { 125 }
    package static var tilde: UInt16 { 126 }

    @inline(__always) package static func isDigit(_ c: UInt16) -> Bool { c &- 48 < 10 }
    @inline(__always) package static func isHexDigit(_ c: UInt16) -> Bool { c &- 48 < 10 || (c | 0x20) &- 97 < 6 }
    @inline(__always) package static func isLetter(_ c: UInt16) -> Bool { (c | 0x20) &- 97 < 26 }
    @inline(__always) package static func isUpper(_ c: UInt16) -> Bool { c &- 65 < 26 }
    @inline(__always) package static func isLower(_ c: UInt16) -> Bool { c &- 97 < 26 }
    @inline(__always) package static func isWordStart(_ c: UInt16) -> Bool { isLetter(c) || c == 95 || c >= 0x80 }
    @inline(__always) package static func isWord(_ c: UInt16) -> Bool { isWordStart(c) || isDigit(c) }
    @inline(__always) package static func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 13 || c == 12 || c == 11 }
    @inline(__always) package static func isSpaceOrNewline(_ c: UInt16) -> Bool { isSpace(c) || c == 10 }
    @inline(__always) package static func lowered(_ c: UInt16) -> UInt16 { isUpper(c) ? c | 0x20 : c }

    package static func units(_ text: String) -> [UInt16] { Array(text.utf16) }

    package static func closer(for opener: UInt16) -> UInt16 {
        switch opener {
        case openParen: return closeParen
        case openBracket: return closeBracket
        case openBrace: return closeBrace
        case less: return greater
        default: return opener
        }
    }
}

package enum NoteSyntaxWordRole: Sendable {
    case plain, declaresFunction, declaresType, operand, startsCommand
}

package struct NoteSyntaxWords: Sendable {
    package struct Entry: Sendable {
        package let word: [UInt16]
        package let kind: NoteSyntaxKind
        package let role: NoteSyntaxWordRole

        package init(word: [UInt16], kind: NoteSyntaxKind, role: NoteSyntaxWordRole) {
            self.word = word
            self.kind = kind
            self.role = role
        }
    }

    package let caseInsensitive: Bool
    private var buckets: [UInt64: [Entry]] = [:]

    package init(caseInsensitive: Bool = false) {
        self.caseInsensitive = caseInsensitive
    }

    package var isEmpty: Bool { buckets.isEmpty }

    package mutating func add(_ list: String, _ kind: NoteSyntaxKind, role: NoteSyntaxWordRole = .plain) {
        for word in list.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            var units = Array(String(word).utf16)
            if caseInsensitive { units = units.map(NoteSyntaxChar.lowered) }
            let key = Self.hash(units, 0, units.count, folding: false)
            var bucket = buckets[key] ?? []
            bucket.removeAll { $0.word == units }
            bucket.append(Entry(word: units, kind: kind, role: role))
            buckets[key] = bucket
        }
    }

    package func lookup(_ units: [UInt16], _ start: Int, _ stop: Int) -> Entry? {
        guard stop > start, !buckets.isEmpty else { return nil }
        guard let bucket = buckets[Self.hash(units, start, stop, folding: caseInsensitive)] else { return nil }
        let length = stop - start
        for entry in bucket where entry.word.count == length {
            var same = true
            for offset in 0..<length {
                let unit = caseInsensitive ? NoteSyntaxChar.lowered(units[start + offset]) : units[start + offset]
                if unit != entry.word[offset] { same = false; break }
            }
            if same { return entry }
        }
        return nil
    }

    @inline(__always) package static func hash(_ units: [UInt16], _ start: Int, _ stop: Int, folding: Bool) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for index in start..<stop {
            let unit = folding ? NoteSyntaxChar.lowered(units[index]) : units[index]
            value = (value ^ UInt64(unit)) &* 0x100_0000_01b3
        }
        return value
    }
}

package struct NoteSyntaxHeredoc {
    package let terminator: [UInt16]
    package let indented: Bool
    package let interpolates: Bool
    package let trailingPunctuation: Bool
}

package struct NoteSyntaxScanState {
    package var atLineStart = true
    package var operandEnded = false
    package var memberAccess = false
    package var commandPosition = true
    package var pendingDeclaration: NoteSyntaxKind?
}

package struct NoteSyntaxScanner {
    package static let depthLimit = 40

    package let units: [UInt16]
    package var pos = 0
    package var end: Int
    package var tokens: [NoteSyntaxToken] = []
    package var state = NoteSyntaxScanState()
    package var heredocs: [NoteSyntaxHeredoc] = []
    package var depth = 0
    package var makeMode = false
    package var regexFailUntil = -1

    package init(_ code: String) {
        units = Array(code.utf16)
        end = units.count
        tokens.reserveCapacity(units.count / 5)
    }

    @inline(__always) package func at(_ index: Int) -> UInt16 {
        index >= 0 && index < end ? units[index] : 0
    }

    @inline(__always) package var current: UInt16 { at(pos) }

    @inline(__always) package func peek(_ offset: Int = 1) -> UInt16 { at(pos + offset) }

    package func matches(_ pattern: [UInt16], at index: Int) -> Bool {
        let count = pattern.count
        guard count > 0, index >= 0, index + count <= end else { return false }
        for offset in 0..<count where units[index + offset] != pattern[offset] { return false }
        return true
    }

    package func matchesIgnoringCase(_ pattern: [UInt16], at index: Int) -> Bool {
        let count = pattern.count
        guard count > 0, index >= 0, index + count <= end else { return false }
        for offset in 0..<count where NoteSyntaxChar.lowered(units[index + offset]) != pattern[offset] { return false }
        return true
    }

    package func matches(_ text: String, at index: Int) -> Bool {
        var cursor = index
        for unit in text.utf16 {
            if at(cursor) != unit { return false }
            cursor += 1
        }
        return true
    }

    package func find(_ pattern: [UInt16], from index: Int, limit: Int? = nil, ignoringCase: Bool = false) -> Int? {
        guard let first = pattern.first else { return nil }
        var cursor = index
        let stop = min(limit ?? end, end)
        let lowerFirst = NoteSyntaxChar.lowered(first)
        while cursor + pattern.count <= stop {
            let unit = units[cursor]
            if ignoringCase ? NoteSyntaxChar.lowered(unit) == lowerFirst : unit == first {
                if ignoringCase ? matchesIgnoringCase(pattern, at: cursor) : matches(pattern, at: cursor) { return cursor }
            }
            cursor += 1
        }
        return nil
    }

    package func lineEnd(from index: Int) -> Int {
        var cursor = index
        while cursor < end && units[cursor] != NoteSyntaxChar.newline { cursor += 1 }
        return cursor
    }

    package func skipSpaces(from index: Int) -> Int {
        var cursor = index
        while cursor < end && NoteSyntaxChar.isSpace(units[cursor]) { cursor += 1 }
        return cursor
    }

    package func skipWord(from index: Int) -> Int {
        var cursor = index
        while cursor < end && NoteSyntaxChar.isWord(units[cursor]) { cursor += 1 }
        return cursor
    }

    package func isLineStart(_ index: Int) -> Bool {
        var cursor = index - 1
        while cursor >= 0 && NoteSyntaxChar.isSpace(units[cursor]) { cursor -= 1 }
        return cursor < 0 || units[cursor] == NoteSyntaxChar.newline
    }

    package func text(_ start: Int, _ stop: Int) -> String {
        String(decoding: units[max(0, start)..<min(units.count, stop)], as: UTF16.self)
    }

    package mutating func emit(_ start: Int, _ stop: Int, _ kind: NoteSyntaxKind) {
        var lower = start
        if let last = tokens.last {
            if lower < last.range.upperBound { lower = last.range.upperBound }
            guard stop > lower else { return }
            if last.kind == kind && last.range.upperBound == lower {
                tokens[tokens.count - 1] = NoteSyntaxToken(range: last.range.lowerBound..<stop, kind: kind)
                return
            }
        }
        guard stop > lower else { return }
        tokens.append(NoteSyntaxToken(range: lower..<stop, kind: kind))
    }

    package mutating func retag(from start: Int, to stop: Int, as kind: NoteSyntaxKind) {
        while let last = tokens.last, last.range.lowerBound >= start { tokens.removeLast() }
        if let last = tokens.last, last.range.upperBound > start {
            tokens[tokens.count - 1] = NoteSyntaxToken(range: last.range.lowerBound..<start, kind: last.kind)
        }
        emit(start, stop, kind)
    }

    package mutating func run(_ lexer: NoteSyntaxLexer) {
        switch lexer {
        case .code(let grammar): lexCode(grammar)
        case .html: lexMarkup(html: true)
        case .xml: lexMarkup(html: false)
        case .css: lexStyles(scss: false)
        case .scss: lexStyles(scss: true)
        case .markdown: lexMarkdown()
        case .yaml: lexYAML()
        case .toml: lexTOML()
        case .diff: lexDiff()
        case .dockerfile: lexDockerfile()
        case .makefile: lexMakefile()
        case .php: lexPHPDocument()
        }
    }

    package mutating func embed(_ lexer: NoteSyntaxLexer, until stop: Int, makeMode make: Bool = false) {
        let limit = min(stop, end)
        guard depth < Self.depthLimit, limit > pos else {
            pos = max(pos, limit)
            return
        }
        let savedEnd = end
        let savedState = state
        let savedHeredocs = heredocs
        let savedMake = makeMode
        end = limit
        depth += 1
        state = NoteSyntaxScanState()
        heredocs = []
        makeMode = make
        run(lexer)
        depth -= 1
        end = savedEnd
        state = savedState
        heredocs = savedHeredocs
        makeMode = savedMake
        pos = limit
    }

    package mutating func lexEntity() -> Bool {
        let start = pos
        var cursor = pos + 1
        if at(cursor) == NoteSyntaxChar.hash {
            cursor += 1
            if NoteSyntaxChar.lowered(at(cursor)) == 120 {
                cursor += 1
                while NoteSyntaxChar.isHexDigit(at(cursor)) { cursor += 1 }
            } else {
                while NoteSyntaxChar.isDigit(at(cursor)) { cursor += 1 }
            }
        } else {
            while NoteSyntaxChar.isLetter(at(cursor)) || NoteSyntaxChar.isDigit(at(cursor)) { cursor += 1 }
        }
        guard cursor > start + 1, cursor - start < 34, at(cursor) == NoteSyntaxChar.semicolon else { return false }
        pos = cursor + 1
        emit(start, pos, .escape)
        return true
    }
}
