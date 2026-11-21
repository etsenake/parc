import Foundation

package struct NoteMathSource {
    package var characters: [Character]
    package var origins: [Range<Int>]
    package var length: Int

    package init(_ source: String) {
        characters = Array(source)
        origins = []
        origins.reserveCapacity(characters.count)
        var running = 0
        for character in characters {
            let next = running + character.utf16.count
            origins.append(running..<next)
            running = next
        }
        length = running
    }

    package init(characters: [Character], origins: [Range<Int>], length: Int) {
        self.characters = characters
        self.origins = origins
        self.length = length
    }
}

package struct NoteMathExpander {
    package enum Kind: Equatable {
        case control(String)
        case character(Character)
        case hash
        case space
        case marker
    }

    package struct Token {
        package var kind: Kind
        package var raw: String
        package var start: Int
        package var invocation: Range<Int>?
        package var noexpand = false
        package var fromCsname = false

        package init(kind: Kind, raw: String, start: Int, invocation: Range<Int>? = nil, noexpand: Bool = false, fromCsname: Bool = false) {
            self.kind = kind
            self.raw = raw
            self.start = start
            self.invocation = invocation
            self.noexpand = noexpand
            self.fromCsname = fromCsname
        }

        package var origin: Range<Int> {
            if let invocation { return invocation }
            let trailing = kind == .space ? 0 : raw.reversed().prefix { $0.isWhitespace }.reduce(0) { $0 + $1.utf16.count }
            return start..<(start + raw.utf16.count - trailing)
        }
    }

    package struct Macro {
        package var arity = 0
        package var defaultArgument: [Token]?
        package var body: [Token] = []
        package var alias: Token?
        package var prefix: [Token] = []
        package var delimiters: [[Token]] = []
        package var braceDelimited = false
    }

    private struct Frame {
        enum Kind { case root, brace, cell }
        var kind: Kind
        var macros: [String: Macro] = [:]

        package init(kind: Kind, macros: [String: Macro] = [:]) {
            self.kind = kind
            self.macros = macros
        }
    }

    package static let maximumExpansions = 1000
    package static let maximumLength = 100_000
    private static let triggers: Set<String> = [
        "newcommand", "renewcommand", "providecommand", "def", "gdef", "edef", "xdef", "let", "global", "ce", "pu",
        "expandafter", "noexpand", "csname",
    ]
    private static let expansionPrimitives: Set<String> = ["expandafter", "noexpand", "csname"]

    private let tokens: [Token]
    private let sourceLength: Int
    private var position = 0
    private var pending: [Token] = []
    private var frames: [Frame] = [Frame(kind: .root)]
    private var awaitsEnvironmentName = false
    private var environmentNameDepth: Int?
    private var expansions = 0
    private var characters: [Character] = []
    private var origins: [Range<Int>] = []
    private var capture: [Token]?
    private var afterControlWord = false
    private var globalPrefix = false

    private init(tokens: [Token], length: Int) {
        self.tokens = tokens
        sourceLength = length
    }

    package static func expand(_ source: String) throws(NoteMathParseError) -> NoteMathSource {
        let tokens = tokenize(source, start: 0, invocation: nil)
        let wanted = tokens.contains { token in
            if case .control(let name) = token.kind { return triggers.contains(name) }
            return false
        }
        guard wanted else { return NoteMathSource(source) }
        var expander = NoteMathExpander(tokens: tokens, length: source.utf16.count)
        try expander.run()
        return NoteMathSource(characters: expander.characters, origins: expander.origins, length: expander.sourceLength)
    }

    package static func tokenize(_ text: String, start: Int, invocation: Range<Int>?) -> [Token] {
        let characters = Array(text)
        var result: [Token] = []
        var index = 0
        var offset = start
        func isLetter(_ character: Character) -> Bool { character.isASCII && character.isLetter }
        while index < characters.count {
            let first = index
            let character = characters[index]
            var kind: Kind
            if character == "\\" {
                index += 1
                if index < characters.count, isLetter(characters[index]) {
                    while index < characters.count, isLetter(characters[index]) { index += 1 }
                    kind = .control(String(characters[(first + 1)..<index]))
                    while index < characters.count, characters[index].isWhitespace { index += 1 }
                } else if index < characters.count {
                    kind = .control(String(characters[index]))
                    index += 1
                } else {
                    kind = .control("")
                }
            } else if character == "%" {
                while index < characters.count, !characters[index].isNewline { index += 1 }
                if index < characters.count { index += 1 }
                offset += String(characters[first..<index]).utf16.count
                continue
            } else if character.isWhitespace {
                while index < characters.count, characters[index].isWhitespace { index += 1 }
                kind = .space
            } else if character == "#" {
                index += 1
                kind = .hash
            } else {
                index += 1
                kind = .character(character)
            }
            let raw = String(characters[first..<index])
            result.append(Token(kind: kind, raw: raw, start: offset, invocation: invocation))
            offset += raw.utf16.count
        }
        return result
    }

    private func failure(_ message: String, _ range: Range<Int>) -> NoteMathParseError {
        NoteMathParseError(message: message, offset: range.lowerBound, length: max(range.count, 1))
    }

    private mutating func next() -> Token? {
        if let token = pending.popLast() { return token }
        guard position < tokens.count else { return nil }
        position += 1
        return tokens[position - 1]
    }

    private mutating func push(_ items: [Token]) {
        pending.append(contentsOf: items.reversed())
    }

    private mutating func nextSignificant() -> Token? {
        while let token = next() {
            if token.kind != .space { return token }
        }
        return nil
    }

    private mutating func peekSignificant() -> Token? {
        var skipped: [Token] = []
        defer { push(skipped) }
        while let token = next() {
            skipped.append(token)
            if token.kind != .space { return token }
        }
        return nil
    }

    private func lookup(_ name: String) -> Macro? {
        for frame in frames.reversed() {
            if let macro = frame.macros[name] { return macro }
        }
        return nil
    }

    private mutating func define(_ name: String, _ macro: Macro, global: Bool) {
        if global {
            for index in frames.indices { frames[index].macros[name] = nil }
            frames[0].macros[name] = macro
        } else {
            frames[frames.count - 1].macros[name] = macro
        }
    }

    private func isExpandable(_ name: String) -> Bool {
        Self.expansionPrimitives.contains(name) || lookup(name) != nil
    }

    private mutating func run() throws(NoteMathParseError) {
        while let token = next() {
            try process(token)
        }
    }

    private mutating func process(_ token: Token) throws(NoteMathParseError) {
        guard !token.noexpand, case .control(let name) = token.kind else {
            emit(token)
            return
        }
        let global = globalPrefix
        globalPrefix = false
        switch name {
        case "global":
            globalPrefix = true
        case "newcommand", "renewcommand", "providecommand":
            try defineCommand(name, token, global: global)
        case "def", "gdef", "edef", "xdef":
            try defineMacro(name, token, global: global || name == "gdef" || name == "xdef")
        case "let":
            try defineLet(token, global: global)
        case "ce", "pu":
            try expandChemistry(name, token)
        case "expandafter":
            try expandAfter(token)
        case "noexpand":
            guard var target = next(), target.kind != .marker else { throw failure("\\noexpand needs something after it", token.origin) }
            if capture != nil {
                target.noexpand = false
                emit(target)
            } else if case .control(let inner) = target.kind, lookup(inner) != nil || !NoteMathParser.isBuiltIn(inner) {
                return
            } else {
                emit(target)
            }
        case "csname":
            try expandCsname(token)
        default:
            if let macro = lookup(name) {
                try expand(macro, name: name, token)
            } else if token.fromCsname, !NoteMathParser.isBuiltIn(name) {
                return
            } else {
                emit(token)
            }
        }
    }

    private mutating func expandOnce(_ token: Token) throws(NoteMathParseError) {
        guard !token.noexpand, case .control(let name) = token.kind else {
            push([token])
            return
        }
        switch name {
        case "expandafter":
            try expandAfter(token)
        case "noexpand":
            guard var target = next(), target.kind != .marker else { throw failure("\\noexpand needs something after it", token.origin) }
            target.noexpand = true
            push([target])
        case "csname":
            try expandCsname(token)
        case "ce", "pu":
            try expandChemistry(name, token)
        default:
            if let macro = lookup(name) {
                try expand(macro, name: name, token)
            } else {
                push([token])
            }
        }
    }

    private mutating func expandAfter(_ call: Token) throws(NoteMathParseError) {
        try countExpansion("expandafter", call)
        guard let first = next(), first.kind != .marker, let second = next(), second.kind != .marker else {
            throw failure("\\expandafter needs two things after it", call.origin)
        }
        try expandOnce(second)
        push([first])
    }

    private mutating func expandCsname(_ call: Token) throws(NoteMathParseError) {
        try countExpansion("csname", call)
        var name = ""
        var end = call.origin.upperBound
        while true {
            guard let token = next(), token.kind != .marker else {
                throw failure("\\csname needs an \\endcsname to finish the name", call.origin)
            }
            end = max(end, token.origin.upperBound)
            switch token.kind {
            case .control("endcsname"):
                let invocation = call.invocation ?? call.origin.lowerBound..<end
                var result = Token(kind: .control(name), raw: "\\" + name, start: invocation.lowerBound, invocation: invocation)
                result.fromCsname = true
                push([result])
                return
            case .character(let character):
                name.append(character)
            case .space:
                name.append(" ")
            case .hash:
                name.append("#")
            case .control(let inner):
                if !token.noexpand, isExpandable(inner) {
                    try expandOnce(token)
                    continue
                }
                throw failure("\\csname builds names from letters and symbols, so \\\(inner) can't go inside", token.origin)
            case .marker:
                break
            }
        }
    }

    private mutating func emit(_ token: Token) {
        if capture != nil {
            capture?.append(token)
            return
        }
        trackScope(token)
        var offset = token.start
        for (index, character) in token.raw.enumerated() {
            let width = character.utf16.count
            let origin = token.invocation ?? offset..<(offset + width)
            if index == 0, afterControlWord, character.isASCII, character.isLetter {
                characters.append(" ")
                origins.append(origin)
            }
            characters.append(character)
            origins.append(origin)
            offset += width
        }
        if case .control(let name) = token.kind, let last = name.last, last.isASCII, last.isLetter {
            afterControlWord = token.raw.last.map { !$0.isWhitespace } ?? false
        } else if !token.raw.isEmpty {
            afterControlWord = false
        }
    }

    private mutating func trackScope(_ token: Token) {
        if token.kind == .space { return }
        let opensName = awaitsEnvironmentName && token.kind == .character("{")
        awaitsEnvironmentName = false
        switch token.kind {
        case .character("{"):
            if opensName { environmentNameDepth = frames.count }
            frames.append(Frame(kind: .brace))
        case .character("}"):
            guard let brace = frames.lastIndex(where: { $0.kind == .brace }) else { return }
            frames.removeSubrange(brace...)
            if environmentNameDepth == frames.count {
                environmentNameDepth = nil
                frames.append(Frame(kind: .cell))
            }
        case .character("&"), .control("\\"), .control("cr"), .control("newline"):
            if frames.last?.kind == .cell { frames[frames.count - 1] = Frame(kind: .cell) }
        case .control("begin"):
            awaitsEnvironmentName = true
        case .control("end"):
            if frames.last?.kind == .cell { frames.removeLast() }
        default:
            break
        }
    }

    private mutating func readGroup(after open: Token, closing: Character = "}") throws(NoteMathParseError) -> (tokens: [Token], end: Int) {
        var depth = 0
        var collected: [Token] = []
        while let token = next() {
            switch token.kind {
            case .character("{"):
                depth += 1
            case .character("}") where closing == "}" && depth == 0:
                return (collected, token.origin.upperBound)
            case .character("}"):
                if depth == 0 { throw failure("Missing ] to close this [", open.origin) }
                depth -= 1
            case .character(let character) where character == closing && depth == 0:
                return (collected, token.origin.upperBound)
            default:
                break
            }
            collected.append(token)
        }
        throw failure(closing == "}" ? "Missing } to close this {" : "Missing ] to close this [", open.origin)
    }

    private mutating func readArgument(_ message: String, at call: Token) throws(NoteMathParseError) -> (tokens: [Token], end: Int) {
        guard let token = nextSignificant() else { throw failure(message, call.origin) }
        switch token.kind {
        case .character("{"):
            return try readGroup(after: token)
        case .character("}"), .character("&"), .character("$"), .control("\\"), .control("end"), .control("right"),
             .control("middle"), .character("^"), .character("_"):
            push([token])
            throw failure(message, token.origin)
        default:
            return ([token], token.origin.upperBound)
        }
    }

    private mutating func readOptional() throws(NoteMathParseError) -> (tokens: [Token], end: Int)? {
        guard let token = peekSignificant(), token.kind == .character("[") else { return nil }
        let open = nextSignificant()!
        return try readGroup(after: open, closing: "]")
    }

    private mutating func readName(for command: String, at call: Token) throws(NoteMathParseError) -> (name: String, token: Token) {
        let example = command == "let" ? "\\let\\foo\\bar" : command.hasSuffix("def") ? "\\\(command)\\foo{…}" : "\\\(command){\\foo}{…}"
        let message = "\\\(command) needs a command name, like \(example)"
        guard var token = nextSignificant() else { throw failure(message, call.origin) }
        var braced = false
        if token.kind == .character("{"), !command.hasSuffix("def"), command != "let" {
            braced = true
            guard let inner = nextSignificant() else { throw failure(message, call.origin) }
            token = inner
        }
        guard case .control(let name) = token.kind, !name.isEmpty else { throw failure(message, token.origin) }
        if braced {
            guard let close = nextSignificant(), close.kind == .character("}") else { throw failure(message, token.origin) }
        }
        return (name, token)
    }

    private func referencedParameters(_ body: [Token]) -> [(Int, Token)] {
        var found: [(Int, Token)] = []
        var index = 0
        while index < body.count {
            if body[index].kind == .hash, index + 1 < body.count {
                if case .character(let digit) = body[index + 1].kind, let value = digit.wholeNumberValue, value > 0 {
                    found.append((value, body[index]))
                }
                index += 2
                continue
            }
            index += 1
        }
        return found
    }

    private func isDefined(_ name: String) -> Bool {
        lookup(name) != nil || NoteMathParser.isBuiltIn(name)
    }

    private mutating func defineCommand(_ command: String, _ call: Token, global: Bool) throws(NoteMathParseError) {
        if let star = peekSignificant(), star.kind == .character("*") { _ = nextSignificant() }
        let (name, nameToken) = try readName(for: command, at: call)
        var macro = Macro()
        if let count = try readOptional() {
            let text = count.tokens.map(\.raw).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard let arity = Int(text), (0...9).contains(arity) else {
                throw failure("The number of arguments has to be 0 to 9", nameToken.start..<count.end)
            }
            macro.arity = arity
            if arity > 0, let fallback = try readOptional() { macro.defaultArgument = fallback.tokens }
        }
        macro.body = try readArgument("\\\(command){\\\(name)} needs a definition in braces", at: nameToken).tokens
        for (value, token) in referencedParameters(macro.body) where value > macro.arity {
            let takes = macro.arity == 0 ? "takes no arguments" : macro.arity == 1 ? "only takes 1 argument" : "only takes \(macro.arity) arguments"
            throw failure("\\\(name) \(takes), so there's no #\(value)", token.origin.lowerBound..<(token.origin.upperBound + 1))
        }
        switch command {
        case "newcommand" where isDefined(name):
            throw failure("\\\(name) already means something; use \\renewcommand to change it", nameToken.origin)
        case "renewcommand" where !isDefined(name):
            throw failure("\\\(name) isn't defined yet, so use \\newcommand", nameToken.origin)
        case "providecommand" where isDefined(name):
            return
        default:
            define(name, macro, global: global)
        }
    }

    private mutating func defineMacro(_ command: String, _ call: Token, global: Bool) throws(NoteMathParseError) {
        let (name, nameToken) = try readName(for: command, at: call)
        var macro = Macro()
        while true {
            guard let token = next() else {
                throw failure("\\\(command)\\\(name) needs a definition in braces", nameToken.origin)
            }
            if token.kind == .character("{") {
                macro.body = try readGroup(after: token).tokens
                break
            }
            if token.kind == .character("}") {
                throw failure("\\\(command)\\\(name) has a } before its definition starts", token.origin)
            }
            guard token.kind == .hash else {
                if macro.arity == 0 {
                    macro.prefix.append(token)
                } else {
                    macro.delimiters[macro.arity - 1].append(token)
                }
                continue
            }
            guard let digit = next() else {
                throw failure("\\\(command)\\\(name) needs a definition in braces", nameToken.origin)
            }
            if digit.kind == .character("{") {
                macro.braceDelimited = true
                macro.body = try readGroup(after: digit).tokens
                break
            }
            guard case .character(let character) = digit.kind, character.wholeNumberValue == macro.arity + 1 else {
                throw failure("\\\(command) parameters have to be #1, #2, … in order, then the definition in braces",
                              token.origin)
            }
            macro.arity += 1
            macro.delimiters.append([])
            if macro.arity > 9 { throw failure("A macro takes at most 9 arguments", token.origin) }
        }
        for (value, token) in referencedParameters(macro.body) where value > macro.arity {
            throw failure("\\\(name) has no #\(value)", token.origin.lowerBound..<(token.origin.upperBound + 1))
        }
        if command == "edef" || command == "xdef" { macro.body = try expandFully(macro.body) }
        define(name, macro, global: global)
    }

    private mutating func defineLet(_ call: Token, global: Bool) throws(NoteMathParseError) {
        let (name, nameToken) = try readName(for: "let", at: call)
        var target = nextSignificant()
        if target?.kind == .character("=") {
            target = next()
            if target?.kind == .space { target = next() }
        }
        guard let target else { throw failure("\\let\\\(name) needs something to copy, like \\let\\\(name)\\alpha", nameToken.origin) }
        if case .control(let other) = target.kind, let existing = lookup(other) {
            define(name, existing, global: global)
        } else {
            define(name, Macro(alias: target), global: global)
        }
    }

    private mutating func expandFully(_ body: [Token]) throws(NoteMathParseError) -> [Token] {
        let saved = capture
        capture = []
        pending.append(Token(kind: .marker, raw: "", start: 0))
        push(body)
        while let token = next(), token.kind != .marker {
            try process(token)
        }
        let result = capture ?? []
        capture = saved
        return result
    }

    private mutating func countExpansion(_ name: String, _ call: Token) throws(NoteMathParseError) {
        expansions += 1
        if expansions > Self.maximumExpansions {
            throw failure("\\\(name) keeps expanding (over 1,000 times). Is it calling itself?", call.origin)
        }
        if characters.count + pending.count > Self.maximumLength {
            throw failure("\\\(name) grows this equation too big to draw", call.origin)
        }
    }

    private mutating func expand(_ macro: Macro, name: String, _ call: Token) throws(NoteMathParseError) {
        try countExpansion(name, call)
        if var alias = macro.alias {
            alias.invocation = call.invocation ?? call.origin
            alias.noexpand = true
            push([alias])
            return
        }
        var arguments: [[Token]] = []
        var end = call.origin.upperBound
        let message = macro.arity == 1 ? "\\\(name) needs something after it" : "\\\(name) needs \(macro.arity) arguments"
        for expected in macro.prefix {
            guard let token = next(), token.kind == expected.kind else {
                throw failure("\\\(name) has to be followed by \u{201C}\(Self.spelled(macro.prefix))\u{201D}, the way it was defined",
                              call.origin)
            }
            end = max(end, token.origin.upperBound)
        }
        for index in 0..<macro.arity {
            if index == 0, let fallback = macro.defaultArgument {
                if let optional = try readOptional() {
                    arguments.append(optional.tokens)
                    end = max(end, optional.end)
                } else {
                    arguments.append(fallback)
                }
                continue
            }
            let delimiter = index < macro.delimiters.count ? macro.delimiters[index] : []
            let stopsAtBrace = macro.braceDelimited && index == macro.arity - 1
            if delimiter.isEmpty && !stopsAtBrace {
                let argument = try readArgument(message, at: call)
                arguments.append(argument.tokens)
                end = max(end, argument.end)
            } else {
                let argument = try readDelimited(delimiter, stopsAtBrace: stopsAtBrace, name: name, at: call)
                arguments.append(argument.tokens)
                end = max(end, argument.end)
            }
        }
        if macro.braceDelimited, macro.arity == 0 {
            guard let brace = peekSignificant(), brace.kind == .character("{") else {
                throw failure("\\\(name) has to be followed by {", call.origin)
            }
        }
        let invocation = call.invocation ?? call.origin.lowerBound..<max(end, call.origin.upperBound)
        var result: [Token] = []
        var index = 0
        let body = macro.body
        while index < body.count {
            if body[index].kind == .hash, index + 1 < body.count {
                if case .character(let digit) = body[index + 1].kind, let value = digit.wholeNumberValue, value > 0,
                   value <= arguments.count {
                    for var token in arguments[value - 1] {
                        token.invocation = token.invocation ?? invocation
                        result.append(token)
                    }
                    index += 2
                    continue
                }
                if body[index + 1].kind == .hash {
                    var token = body[index]
                    token.invocation = invocation
                    result.append(token)
                    index += 2
                    continue
                }
            }
            var token = body[index]
            token.invocation = invocation
            result.append(token)
            index += 1
        }
        push(result)
    }

    private static func spelled(_ tokens: [Token]) -> String {
        tokens.map { token in
            switch token.kind {
            case .control(let name): return "\\" + name + (name.last?.isLetter == true ? " " : "")
            case .space: return " "
            default: return token.raw
            }
        }.joined().trimmingCharacters(in: .whitespaces)
    }

    private mutating func readDelimited(_ delimiter: [Token], stopsAtBrace: Bool, name: String,
                                        at call: Token) throws(NoteMathParseError) -> (tokens: [Token], end: Int) {
        var collected: [Token] = []
        var depth = 0
        var end = call.origin.upperBound
        let wanted = delimiter.map(\.kind)
        while true {
            guard let token = next(), token.kind != .marker else {
                let ending = stopsAtBrace ? "{" : Self.spelled(delimiter)
                throw failure("\\\(name) never finds the \u{201C}\(ending)\u{201D} that ends its argument", call.origin)
            }
            if stopsAtBrace, depth == 0, token.kind == .character("{") {
                push([token])
                break
            }
            switch token.kind {
            case .character("{"):
                depth += 1
            case .character("}"):
                if depth == 0 {
                    push([token])
                    throw failure("\\\(name)'s argument has an extra }", token.origin)
                }
                depth -= 1
            default:
                break
            }
            collected.append(token)
            end = max(end, token.origin.upperBound)
            if depth == 0, !wanted.isEmpty, collected.count >= wanted.count,
               zip(collected.suffix(wanted.count), wanted).allSatisfy({ $0.kind == $1 }) {
                collected.removeLast(wanted.count)
                break
            }
        }
        return (Self.strippingOuterBraces(collected), end)
    }

    private static func strippingOuterBraces(_ tokens: [Token]) -> [Token] {
        guard tokens.count >= 2, tokens.first?.kind == .character("{"), tokens.last?.kind == .character("}") else { return tokens }
        var depth = 0
        for (index, token) in tokens.enumerated() {
            if token.kind == .character("{") { depth += 1 }
            if token.kind == .character("}") {
                depth -= 1
                if depth == 0, index < tokens.count - 1 { return tokens }
            }
        }
        return Array(tokens.dropFirst().dropLast())
    }

    private mutating func expandChemistry(_ name: String, _ call: Token) throws(NoteMathParseError) {
        try countExpansion(name, call)
        let argument = try readArgument("\\\(name) needs {…} after it", at: call)
        let invocation = call.invocation ?? call.origin.lowerBound..<argument.end
        let text = argument.tokens.map(\.raw).joined()
        let converted: String
        do {
            converted = name == "ce" ? try NoteMathChemistry.formula(text) : try NoteMathChemistry.units(text)
        } catch {
            throw failure(error.message, invocation)
        }
        push(Self.tokenize("{" + converted + "}", start: invocation.lowerBound, invocation: invocation))
    }
}
