import Foundation

enum NoteMathAtomKind: Equatable, Sendable {
    case ord, op, bin, rel, open, close, punct, inner
}

enum NoteMathVariant: Equatable, Sendable {
    case normal, roman, bold, italic, boldItalic, doubleStruck, script, fraktur, sansSerif, monospace
}

enum NoteMathTextStyle: Equatable, Sendable {
    case roman, bold, italic, sansSerif, monospace
}

enum NoteMathLimits: Equatable, Sendable {
    case auto, above, beside
}

enum NoteMathStyleLevel: Equatable, Sendable {
    case display, text, script, scriptScript
}

struct NoteMathColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

struct NoteMathFraction: Equatable {
    var numerator: [NoteMathNode]
    var denominator: [NoteMathNode]
    var hasRule = true
    var level: NoteMathStyleLevel?
    var left: String?
    var right: String?
}

enum NoteMathDecoration: Equatable, Sendable {
    case accent(String)
    case wideAccent(String)
    case overArrow(String)
    case underArrow(String)
    case overline
    case underline
    case overbrace
    case underbrace
    case cancel
    case backCancel
    case crossCancel
    case strike
}

enum NoteMathLap: Equatable, Sendable {
    case left, right, center
}

enum NoteMathColumnAlignment: Equatable, Sendable {
    case left, center, right
}

enum NoteMathEnvironmentKind: Equatable, Sendable {
    case matrix, smallMatrix, cases, aligned, gathered, array
}

struct NoteMathEnvironment: Equatable {
    var kind: NoteMathEnvironmentKind
    var rows: [[[NoteMathNode]]]
    var columns: [NoteMathColumnAlignment]
    var tags: [[NoteMathNode]?] = []
    var columnRules: [Int] = []
    var rowRules: [Int] = []
    var rowSpacing: [Int: Double] = [:]
    var left: String?
    var right: String?
}

indirect enum NoteMathNode: Equatable {
    case char(String, NoteMathAtomKind)
    case largeOperator(String, NoteMathLimits)
    case function(String, NoteMathLimits)
    case operatorName([NoteMathNode], NoteMathLimits)
    case text(String, NoteMathTextStyle)
    case group([NoteMathNode])
    case scripts(base: NoteMathNode?, superscript: [NoteMathNode]?, subscript: [NoteMathNode]?)
    case fraction(NoteMathFraction)
    case radical([NoteMathNode], degree: [NoteMathNode]?)
    case fenced(left: String?, right: String?, middles: [String?], segments: [[NoteMathNode]])
    case sizedDelimiter(String?, size: Int, kind: NoteMathAtomKind)
    case decorated(NoteMathDecoration, [NoteMathNode])
    case stacked(base: [NoteMathNode], over: [NoteMathNode]?, under: [NoteMathNode]?)
    case extensibleArrow(String, over: [NoteMathNode], under: [NoteMathNode]?)
    case space(Double)
    case styled(NoteMathVariant, [NoteMathNode])
    case colored(NoteMathColor, [NoteMathNode])
    case environment(NoteMathEnvironment)
    case classed(NoteMathAtomKind, [NoteMathNode])
    case mathStyle(NoteMathStyleLevel, [NoteMathNode])
    case lines([[NoteMathNode]])
    case phantom([NoteMathNode], keepsWidth: Bool, keepsHeight: Bool)
    case boxed([NoteMathNode])
    case lap(NoteMathLap, [NoteMathNode])
    case reference(String, parenthesized: Bool, label: [NoteMathNode]?)
}

enum NoteMathLabelTarget: Equatable {
    case automatic(Int)
    case tag([NoteMathNode])
}

struct NoteMathLabel: Equatable {
    var key: String
    var target: NoteMathLabelTarget
}

struct NoteMathNumberingContext: Equatable {
    var firstNumber = 0
    var references: [String: [NoteMathNode]] = [:]
    var takenLabels: Set<String> = []
    var referenceDigest = ""

    func fingerprint(for source: String, display: Bool) -> String {
        var parts: [String] = []
        if display, source.contains("begin") { parts.append("n\(firstNumber)") }
        if display, source.contains("label"), !takenLabels.isEmpty { parts.append("t" + takenLabels.sorted().joined(separator: ",")) }
        if source.contains("ref") { parts.append("r" + referenceDigest) }
        return parts.joined(separator: ";")
    }

    static func digest(_ references: [String: [NoteMathNode]]) -> String {
        references.keys.sorted().map { "\($0)=\(String(describing: references[$0]!))" }.joined(separator: "|")
    }
}

struct NoteMathEquation: Equatable {
    var nodes: [NoteMathNode]
    var tag: [NoteMathNode]?
    var labels: [NoteMathLabel] = []
    var automaticNumbers = 0
}

struct NoteMathParseError: Error, Equatable, CustomStringConvertible {
    var message: String
    var offset: Int
    var length: Int
    var description: String { message }
}

struct NoteMathParser {
    private enum Token: Equatable {
        case command(String)
        case character(Character)
        case end
    }

    private struct Lexeme {
        var token: Token
        var start: Int
        var end: Int
    }

    private enum Scope {
        case top
        case group(Int)
        case cell(String, Int)
        case fence(Int)
        case bracket(Int)
        case inlineMath(Int)
    }

    private static let maximumDepth = 120

    private let characters: [Character]
    private let origins: [Range<Int>]
    private let sourceLength: Int
    private let display: Bool
    private var index = 0
    private var depth = 0
    private var pendingTag: (nodes: [NoteMathNode], label: [NoteMathNode], lexeme: Lexeme)?
    private var pendingLabel: (key: String, lexeme: Lexeme)?
    private var suppressesNumber = false
    private var equationNumber = 0
    private var labels: [NoteMathLabel] = []
    private let numbering: NoteMathNumberingContext

    private init(_ source: NoteMathSource, display: Bool, numbering: NoteMathNumberingContext) {
        characters = source.characters
        origins = source.origins
        sourceLength = source.length
        self.display = display
        self.numbering = numbering
    }

    static func parse(_ source: String) throws(NoteMathParseError) -> [NoteMathNode] {
        try parseEquation(source, display: true).nodes
    }

    static func parseEquation(_ source: String, display: Bool,
                              numbering: NoteMathNumberingContext = NoteMathNumberingContext()) throws(NoteMathParseError) -> NoteMathEquation {
        var parser = NoteMathParser(try NoteMathExpander.expand(source), display: display, numbering: numbering)
        let nodes = try parser.parseFormula()
        let tag = parser.pendingTag
        if let tag, !display { throw parser.failure("\\tag only works in display equations", tag.lexeme) }
        if let label = parser.pendingLabel {
            guard let tag else {
                throw parser.failure("\\label needs a numbered equation: wrap it in \\begin{equation}…\\end{equation} or add a \\tag",
                                     label.lexeme)
            }
            try parser.record(label, target: .tag(tag.label))
        }
        return NoteMathEquation(nodes: nodes, tag: tag?.nodes, labels: parser.labels, automaticNumbers: parser.equationNumber)
    }

    private mutating func record(_ label: (key: String, lexeme: Lexeme), target: NoteMathLabelTarget) throws(NoteMathParseError) {
        if labels.contains(where: { $0.key == label.key }) {
            throw failure("\u{201C}\(label.key)\u{201D} already labels another line here", label.lexeme)
        }
        if numbering.takenLabels.contains(label.key) {
            throw failure("\u{201C}\(label.key)\u{201D} already labels an earlier equation", label.lexeme)
        }
        labels.append(NoteMathLabel(key: label.key, target: target))
    }

    private mutating func parseLabel(_ lexeme: Lexeme) throws(NoteMathParseError) {
        let raw = try parseRawGroup(for: "label", what: "a name")
        let whole = Lexeme(token: lexeme.token, start: lexeme.start, end: raw.end)
        if !display { throw failure("\\label only works in display equations", whole) }
        if raw.text.isEmpty { throw failure("\\label needs a name, like \\label{eq:energy}", whole) }
        if pendingLabel != nil { throw failure("Only one \\label per line", whole) }
        pendingLabel = (raw.text, whole)
    }

    private mutating func parseReference(_ name: String, _ lexeme: Lexeme) throws(NoteMathParseError) -> NoteMathNode {
        let raw = try parseRawGroup(for: name, what: "a label")
        if raw.text.isEmpty {
            throw failure("\\\(name) needs a label, like \\\(name){eq:energy}", Lexeme(token: lexeme.token, start: lexeme.start, end: raw.end))
        }
        return .reference(raw.text, parenthesized: name == "eqref", label: numbering.references[raw.text])
    }

    static func isBuiltIn(_ name: String) -> Bool {
        NoteMathSymbols.symbols[name] != nil || NoteMathSymbols.italicCapitals[name] != nil
            || NoteMathSymbols.largeOperators[name] != nil || NoteMathSymbols.functions[name] != nil
            || NoteMathSymbols.spaces[name] != nil || fontCommands[name] != nil || textCommands[name] != nil
            || decorations[name] != nil || sizedDelimiters[name] != nil || classCommands[name] != nil
            || styleSwitches[name] != nil || fontSwitches[name] != nil || extensibleArrows[name] != nil
            || structuralCommands.contains(name)
    }

    private static let structuralCommands: Set<String> = [
        "frac", "dfrac", "tfrac", "cfrac", "binom", "dbinom", "tbinom", "sqrt", "left", "right", "middle", "begin", "end",
        "operatorname", "overset", "underset", "stackrel", "textcolor", "color", "not", "colon", "bmod", "pmod", "mod",
        "phantom", "hphantom", "vphantom", "boxed", "fbox", "llap", "mathllap", "rlap", "mathrlap", "clap", "mathclap", "hspace", "hskip", "kern", "mkern", "mskip", "limits",
        "nolimits", "displaylimits", "over", "choose", "atop", "brack", "brace", "tag", "notag", "nonumber", "hline",
        "hdashline", "\\", "cr", "newline", "newcommand", "renewcommand", "providecommand", "def", "gdef", "edef",
        "xdef", "let", "global", "ce", "pu", "label", "eqref", "ref",
    ]

    private mutating func parseFormula() throws(NoteMathParseError) -> [NoteMathNode] {
        var lines: [[NoteMathNode]] = []
        while true {
            let line = try parseList(.top)
            lines.append(line)
            let next = peek()
            guard next.token == .command("\\") else { break }
            advance(past: next)
            _ = try parseOptionalRowSpacing()
        }
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        return lines.count == 1 ? lines[0] : [.lines(lines)]
    }

    private func failure(_ message: String, from start: Int, to end: Int) -> NoteMathParseError {
        let lowerIndex = min(max(start, 0), characters.count)
        let upperIndex = min(max(end, lowerIndex), characters.count)
        let lower = lowerIndex < characters.count ? origins[lowerIndex].lowerBound : sourceLength
        let upper = upperIndex > lowerIndex ? origins[upperIndex - 1].upperBound : lower
        return NoteMathParseError(message: message, offset: lower, length: max(upper - lower, 0))
    }

    private func failure(_ message: String, _ lexeme: Lexeme) -> NoteMathParseError {
        failure(message, from: lexeme.start, to: max(lexeme.end, lexeme.start + 1))
    }

    private static func isLetter(_ character: Character) -> Bool {
        character.isASCII && character.isLetter
    }

    private func skipIndex(from position: Int) -> Int {
        var cursor = position
        while cursor < characters.count {
            let character = characters[cursor]
            if character.isWhitespace {
                cursor += 1
            } else if character == "%" {
                while cursor < characters.count, !characters[cursor].isNewline { cursor += 1 }
            } else {
                break
            }
        }
        return cursor
    }

    private func lexeme(at position: Int) -> Lexeme {
        let start = skipIndex(from: position)
        guard start < characters.count else { return Lexeme(token: .end, start: characters.count, end: characters.count) }
        let character = characters[start]
        guard character == "\\" else { return Lexeme(token: .character(character), start: start, end: start + 1) }
        var end = start + 1
        guard end < characters.count else { return Lexeme(token: .command(""), start: start, end: end) }
        if Self.isLetter(characters[end]) {
            while end < characters.count, Self.isLetter(characters[end]) { end += 1 }
        } else {
            end += 1
        }
        return Lexeme(token: .command(String(characters[(start + 1)..<end])), start: start, end: end)
    }

    private func peek() -> Lexeme { lexeme(at: index) }

    private mutating func advance(past lexeme: Lexeme) { index = lexeme.end }

    private mutating func consumeStar() -> Bool {
        if index < characters.count, characters[index] == "*" {
            index += 1
            return true
        }
        return false
    }

    private mutating func enter(_ lexeme: Lexeme) throws(NoteMathParseError) {
        depth += 1
        if depth > Self.maximumDepth { throw failure("This formula nests too deep to draw", lexeme) }
    }

    private mutating func parseList(_ scope: Scope) throws(NoteMathParseError) -> [NoteMathNode] {
        var nodes: [NoteMathNode] = []
        var infix: (name: String, numerator: [NoteMathNode], lexeme: Lexeme)?

        func finish(_ nodes: [NoteMathNode]) -> [NoteMathNode] {
            guard let infix else { return nodes }
            var fraction = NoteMathFraction(numerator: infix.numerator, denominator: nodes)
            switch infix.name {
            case "choose": fraction.hasRule = false; fraction.left = "("; fraction.right = ")"
            case "brack": fraction.hasRule = false; fraction.left = "["; fraction.right = "]"
            case "brace": fraction.hasRule = false; fraction.left = "{"; fraction.right = "}"
            case "atop": fraction.hasRule = false
            default: break
            }
            return [.fraction(fraction)]
        }

        while true {
            let lexeme = peek()
            switch lexeme.token {
            case .end:
                switch scope {
                case .top: return finish(nodes)
                case .group(let open): throw failure("Missing } to close this {", from: open, to: open + 1)
                case .cell(let name, let open): throw failure("Missing \\end{\(name)}", from: open, to: open + 1)
                case .fence(let open): throw failure("Missing \\right to close this \\left", from: open, to: open + 5)
                case .bracket(let open): throw failure("Missing ] to close this [", from: open, to: open + 1)
                case .inlineMath(let open): throw failure("Missing $ to close this $", from: open, to: open + 1)
                }
            case .character("}"):
                if case .group = scope { return finish(nodes) }
                throw failure("There's a } without a matching {", lexeme)
            case .character("]"):
                if case .bracket = scope { return finish(nodes) }
                advance(past: lexeme)
                nodes.append(.char("]", .close))
            case .character("$"):
                if case .inlineMath = scope { return finish(nodes) }
                throw failure("You're already in math mode, so drop the $", lexeme)
            case .character("&"):
                if case .cell = scope { return finish(nodes) }
                throw failure("& only works inside an environment like aligned or matrix", lexeme)
            case .command("\\"), .command("cr"), .command("newline"):
                switch scope {
                case .cell, .top: return finish(nodes)
                default: throw failure("A line break can't go here", lexeme)
                }
            case .command("end"):
                if case .cell = scope { return finish(nodes) }
                throw failure("\\end without a matching \\begin", lexeme)
            case .command("right"):
                if case .fence = scope { return finish(nodes) }
                throw failure("\\right without a matching \\left", lexeme)
            case .command("middle"):
                if case .fence = scope { return finish(nodes) }
                throw failure("\\middle only works between \\left and \\right", lexeme)
            case .command("over"), .command("choose"), .command("atop"), .command("brack"), .command("brace"):
                advance(past: lexeme)
                if infix != nil { throw failure("Only one \\over per group; add braces to say which goes where", lexeme) }
                if case .command(let name) = lexeme.token { infix = (name, nodes, lexeme) }
                nodes = []
            case .character("^"), .character("_"):
                advance(past: lexeme)
                try attachScript(to: &nodes, superscript: lexeme.token == .character("^"), at: lexeme)
            case .character("'"):
                try attachPrimes(to: &nodes, at: lexeme)
            case .command("tag"):
                advance(past: lexeme)
                try parseTag(lexeme)
            case .command("label"):
                advance(past: lexeme)
                try parseLabel(lexeme)
            case .command("notag"), .command("nonumber"):
                advance(past: lexeme)
                suppressesNumber = true
            case .command("limits"), .command("nolimits"), .command("displaylimits"):
                advance(past: lexeme)
                let limits: NoteMathLimits = lexeme.token == .command("limits") ? .above
                    : lexeme.token == .command("nolimits") ? .beside : .auto
                guard let last = nodes.popLast(), let changed = Self.withLimits(last, limits) else {
                    throw failure("\\limits has to come right after an operator like \\sum", lexeme)
                }
                nodes.append(changed)
            case .command("color"):
                advance(past: lexeme)
                let color = try parseColor(after: "color")
                let rest = try parseList(scope)
                nodes.append(.colored(color, rest))
                return finish(nodes)
            case .command(let name) where Self.styleSwitches[name] != nil:
                advance(past: lexeme)
                let rest = try parseList(scope)
                nodes.append(.mathStyle(Self.styleSwitches[name]!, rest))
                return finish(nodes)
            case .command(let name) where Self.fontSwitches[name] != nil:
                advance(past: lexeme)
                let rest = try parseList(scope)
                nodes.append(.styled(Self.fontSwitches[name]!, rest))
                return finish(nodes)
            default:
                advance(past: lexeme)
                nodes.append(try parseAtom(lexeme))
            }
        }
    }

    private static func withLimits(_ node: NoteMathNode, _ limits: NoteMathLimits) -> NoteMathNode? {
        switch node {
        case .largeOperator(let symbol, _): return .largeOperator(symbol, limits)
        case .function(let name, _): return .function(name, limits)
        case .operatorName(let content, _): return .operatorName(content, limits)
        case .scripts(let base?, let upper, let lower):
            guard let changed = withLimits(base, limits) else { return nil }
            return .scripts(base: changed, superscript: upper, subscript: lower)
        default: return nil
        }
    }

    private static func popScriptTarget(_ nodes: inout [NoteMathNode])
        -> (base: NoteMathNode?, upper: [NoteMathNode]?, lower: [NoteMathNode]?) {
        guard let last = nodes.last else { return (nil, nil, nil) }
        switch last {
        case .scripts(let base, let upper, let lower):
            nodes.removeLast()
            return (base, upper, lower)
        case .space:
            return (nil, nil, nil)
        default:
            nodes.removeLast()
            return (last, nil, nil)
        }
    }

    private mutating func attachScript(to nodes: inout [NoteMathNode], superscript: Bool,
                                       at lexeme: Lexeme) throws(NoteMathParseError) {
        let target = Self.popScriptTarget(&nodes)
        if superscript, target.upper != nil {
            throw failure("Double superscript: wrap one in braces, like {x^a}^b", lexeme)
        }
        if !superscript, target.lower != nil {
            throw failure("Double subscript: wrap one in braces, like {x_a}_b", lexeme)
        }
        let argument = try parseScriptArgument(after: lexeme, superscript: superscript)
        nodes.append(.scripts(base: target.base, superscript: superscript ? argument : target.upper,
                              subscript: superscript ? target.lower : argument))
    }

    private mutating func attachPrimes(to nodes: inout [NoteMathNode], at lexeme: Lexeme) throws(NoteMathParseError) {
        var count = 0
        while peek().token == .character("'") {
            advance(past: peek())
            count += 1
        }
        let target = Self.popScriptTarget(&nodes)
        if target.upper != nil { throw failure("Double superscript: a prime already counts as one", lexeme) }
        var upper: [NoteMathNode] = [.char(Self.primes(count), .ord)]
        let caret = peek()
        if caret.token == .character("^") {
            advance(past: caret)
            upper += try parseScriptArgument(after: caret, superscript: true)
        }
        nodes.append(.scripts(base: target.base, superscript: upper, subscript: target.lower))
    }

    private static func primes(_ count: Int) -> String {
        switch count {
        case 1: return "\u{2032}"
        case 2: return "\u{2033}"
        case 3: return "\u{2034}"
        case 4: return "\u{2057}"
        default: return String(repeating: "\u{2032}", count: count)
        }
    }

    private mutating func parseScriptArgument(after lexeme: Lexeme, superscript: Bool) throws(NoteMathParseError) -> [NoteMathNode] {
        let next = peek()
        switch next.token {
        case .end, .character("}"), .character("&"), .character("^"), .character("_"), .character("$"),
             .command("\\"), .command("end"), .command("right"), .command("middle"):
            throw failure(superscript ? "^ needs something to raise" : "_ needs something to lower", lexeme)
        case .character("{"):
            advance(past: next)
            return try parseGroupBody(open: next)
        default:
            advance(past: next)
            return [try parseAtom(next)]
        }
    }

    private mutating func parseGroupBody(open: Lexeme) throws(NoteMathParseError) -> [NoteMathNode] {
        try enter(open)
        defer { depth -= 1 }
        let nodes = try parseList(.group(open.start))
        advance(past: peek())
        return nodes
    }

    private mutating func parseArgument(for command: String, count: Int) throws(NoteMathParseError) -> [NoteMathNode] {
        let next = peek()
        let message = count == 1 ? "\\\(command) needs something after it" : "\\\(command) needs \(count) arguments"
        switch next.token {
        case .end, .character("}"), .character("&"), .character("^"), .character("_"), .character("$"),
             .command("\\"), .command("end"), .command("right"), .command("middle"):
            throw failure(message, next.token == .end ? Lexeme(token: .end, start: max(index - 1, 0), end: index) : next)
        case .character("{"):
            advance(past: next)
            return try parseGroupBody(open: next)
        default:
            advance(past: next)
            return [try parseAtom(next)]
        }
    }

    private mutating func parseAtom(_ lexeme: Lexeme) throws(NoteMathParseError) -> NoteMathNode {
        switch lexeme.token {
        case .end:
            throw failure("This formula ends too soon", lexeme)
        case .character(let character):
            switch character {
            case "{": return .group(try parseGroupBody(open: lexeme))
            case "~": return .space(1.0 / 3.0)
            case "#": throw failure("Use \\# for a # sign", lexeme)
            case "$": throw failure("You're already in math mode, so drop the $", lexeme)
            case "}": throw failure("There's a } without a matching {", lexeme)
            case "&": throw failure("& only works inside an environment like aligned or matrix", lexeme)
            case "^", "_": throw failure("\(character) needs something in front of it", lexeme)
            case "'": return .char(Self.primes(1), .ord)
            default: return Self.characterNode(character)
            }
        case .command(let name):
            return try parseCommand(name, lexeme)
        }
    }

    private static func characterNode(_ character: Character) -> NoteMathNode {
        switch character {
        case "+": return .char("+", .bin)
        case "-": return .char("\u{2212}", .bin)
        case "*": return .char("\u{2217}", .bin)
        case "=", "<", ">", ":": return .char(String(character), .rel)
        case "(", "[": return .char(String(character), .open)
        case ")", "]": return .char(String(character), .close)
        case ",", ";": return .char(String(character), .punct)
        case "!", "?": return .char(String(character), .close)
        default:
            let text = String(character)
            if let large = NoteMathSymbols.largeOperatorsByCharacter[text] {
                return .largeOperator(text, large ? .beside : .auto)
            }
            return .char(text, NoteMathSymbols.kindsByCharacter[text] ?? .ord)
        }
    }

    private mutating func parseCommand(_ name: String, _ lexeme: Lexeme) throws(NoteMathParseError) -> NoteMathNode {
        if let symbol = NoteMathSymbols.symbols[name] { return .char(symbol.0, symbol.1) }
        if let italic = NoteMathSymbols.italicCapitals[name] { return .styled(.italic, [.char(italic, .ord)]) }
        if let large = NoteMathSymbols.largeOperators[name] { return .largeOperator(large.0, large.1 ? .beside : .auto) }
        if let function = NoteMathSymbols.functions[name] { return .function(function.0, function.1 ? .auto : .beside) }
        if let space = NoteMathSymbols.spaces[name] { return .space(space) }
        if let variant = Self.fontCommands[name] {
            return .styled(variant, try parseArgument(for: name, count: 1))
        }
        if let style = Self.textCommands[name] { return try parseText(style, command: lexeme, name: name) }
        if let decoration = Self.decorations[name] {
            return .decorated(decoration, try parseArgument(for: name, count: 1))
        }
        if let sized = Self.sizedDelimiters[name] {
            return .sizedDelimiter(try parseDelimiter(after: name, at: lexeme), size: sized.0, kind: sized.1)
        }
        if let kind = Self.classCommands[name] { return .classed(kind, try parseArgument(for: name, count: 1)) }
        if let level = Self.styleSwitches[name] { return .mathStyle(level, []) }
        switch name {
        case "frac", "dfrac", "tfrac", "cfrac", "binom", "dbinom", "tbinom":
            let numerator = try parseArgument(for: name, count: 2)
            let denominator = try parseArgument(for: name, count: 2)
            var fraction = NoteMathFraction(numerator: numerator, denominator: denominator)
            if name.hasPrefix("d") || name == "cfrac" { fraction.level = .display }
            if name.hasPrefix("t") { fraction.level = .text }
            if name.hasSuffix("binom") {
                fraction.hasRule = false
                fraction.left = "("
                fraction.right = ")"
            }
            return .fraction(fraction)
        case "sqrt":
            var degree: [NoteMathNode]?
            let next = skipIndex(from: index)
            if next < characters.count, characters[next] == "[" {
                index = next + 1
                try enter(lexeme)
                degree = try parseList(.bracket(next))
                depth -= 1
                advance(past: peek())
            }
            return .radical(try parseArgument(for: name, count: 1), degree: degree)
        case "left":
            return try parseFence(lexeme)
        case "begin":
            return try parseEnvironment(lexeme)
        case "operatorname":
            let limits: NoteMathLimits = consumeStar() ? .auto : .beside
            return .operatorName(try parseArgument(for: name, count: 1), limits)
        case _ where Self.extensibleArrows[name] != nil:
            var under: [NoteMathNode]?
            let next = skipIndex(from: index)
            if next < characters.count, characters[next] == "[" {
                index = next + 1
                try enter(lexeme)
                under = try parseList(.bracket(next))
                depth -= 1
                advance(past: peek())
            }
            let over = try parseArgument(for: name, count: 1)
            return .extensibleArrow(Self.extensibleArrows[name]!, over: over, under: under)
        case "overset", "underset", "stackrel":
            let annotation = try parseArgument(for: name, count: 2)
            let base = try parseArgument(for: name, count: 2)
            if name == "underset" { return .stacked(base: base, over: nil, under: annotation) }
            let stacked = NoteMathNode.stacked(base: base, over: annotation, under: nil)
            return name == "stackrel" ? .classed(.rel, [stacked]) : stacked
        case "textcolor":
            let color = try parseColor(after: name)
            return .colored(color, try parseArgument(for: name, count: 2))
        case "color":
            let color = try parseColor(after: name)
            return .colored(color, try parseArgument(for: name, count: 1))
        case "not":
            let next = peek()
            advance(past: next)
            if case .char(let symbol, let kind) = try parseAtom(next) {
                return .char(NoteMathSymbols.negations[symbol] ?? symbol + "\u{0338}", kind)
            }
            throw failure("\\not needs a symbol after it, like \\not=", lexeme)
        case "colon":
            return .group([.space(2.0 / 18), .char(":", .punct), .space(6.0 / 18)])
        case "bmod":
            return .classed(.bin, [.function("mod", .beside)])
        case "pmod":
            let argument = try parseArgument(for: name, count: 1)
            return .group([.space(1), .char("(", .open), .text("mod", .roman), .space(1.0 / 3.0)]
                          + argument + [.char(")", .close)])
        case "mod":
            let argument = try parseArgument(for: name, count: 1)
            return .group([.space(1), .text("mod", .roman), .space(1.0 / 3.0)] + argument)
        case "phantom", "hphantom", "vphantom":
            return .phantom(try parseArgument(for: name, count: 1), keepsWidth: name != "vphantom",
                            keepsHeight: name != "hphantom")
        case "llap", "mathllap", "rlap", "mathrlap", "clap", "mathclap":
            let side: NoteMathLap = name.hasSuffix("llap") ? .left : name.hasSuffix("rlap") ? .right : .center
            return .lap(side, try parseArgument(for: name, count: 1))
        case "boxed", "fbox":
            return .boxed(try parseArgument(for: name, count: 1))
        case "hspace", "hskip", "kern", "mkern", "mskip":
            _ = consumeStar()
            return .space(try parseDimensionArgument(for: name, at: lexeme))
        case "limits", "nolimits", "displaylimits":
            throw failure("\\\(name) has to come right after an operator like \\sum", lexeme)
        case "":
            throw failure("A lone \\ needs a command name after it", lexeme)
        case "eqref", "ref":
            return try parseReference(name, lexeme)
        case "tag", "notag", "nonumber", "label":
            throw failure("\\\(name) has to stand on its own, not inside a script or argument", lexeme)
        default:
            throw failure("Unknown command \\\(name)", lexeme)
        }
    }

    private mutating func parseTag(_ lexeme: Lexeme) throws(NoteMathParseError) {
        let literal = consumeStar()
        if pendingTag != nil { throw failure("Only one \\tag per line", lexeme) }
        let label = try parseText(.roman, command: lexeme, name: "tag")
        let inner: [NoteMathNode]
        switch label {
        case .group(let parts): inner = parts
        default: inner = [label]
        }
        var nodes: [NoteMathNode]
        switch label {
        case .text(let text, let style) where !literal:
            nodes = [.text("(" + text + ")", style)]
        case .group(let parts) where !literal:
            nodes = [.text("(", .roman)] + parts + [.text(")", .roman)]
        case .group(let parts):
            nodes = parts
        default:
            nodes = literal ? [label] : [.text("(", .roman), label, .text(")", .roman)]
        }
        pendingTag = (nodes, inner, lexeme)
    }

    private mutating func rowTag(numbered: Bool) throws(NoteMathParseError) -> [NoteMathNode]? {
        defer {
            pendingTag = nil
            pendingLabel = nil
            suppressesNumber = false
        }
        if let tag = pendingTag {
            if let label = pendingLabel { try record(label, target: .tag(tag.label)) }
            return tag.nodes
        }
        guard numbered, !suppressesNumber else {
            if let label = pendingLabel {
                throw failure("\\label needs a numbered line, and this one isn't numbered", label.lexeme)
            }
            return nil
        }
        equationNumber += 1
        if let label = pendingLabel { try record(label, target: .automatic(equationNumber)) }
        return [.text("(\(numbering.firstNumber + equationNumber))", .roman)]
    }

    private mutating func parseDelimiter(after command: String, at lexeme: Lexeme) throws(NoteMathParseError) -> String? {
        let next = peek()
        switch next.token {
        case .character(let character):
            if character == "." {
                advance(past: next)
                return nil
            }
            if let delimiter = NoteMathSymbols.delimiterCharacters[character] {
                advance(past: next)
                return delimiter
            }
        case .command(let name):
            if let delimiter = NoteMathSymbols.delimiterCommands[name] {
                advance(past: next)
                return delimiter
            }
        case .end:
            break
        }
        throw failure("\\\(command) needs a delimiter after it, like ( or \\{", next.token == .end ? lexeme : next)
    }

    private mutating func parseFence(_ lexeme: Lexeme) throws(NoteMathParseError) -> NoteMathNode {
        try enter(lexeme)
        defer { depth -= 1 }
        let left = try parseDelimiter(after: "left", at: lexeme)
        var segments: [[NoteMathNode]] = []
        var middles: [String?] = []
        while true {
            segments.append(try parseList(.fence(lexeme.start)))
            let next = peek()
            advance(past: next)
            if next.token == .command("middle") {
                middles.append(try parseDelimiter(after: "middle", at: next))
                continue
            }
            let right = try parseDelimiter(after: "right", at: next)
            return .fenced(left: left, right: right, middles: middles, segments: segments)
        }
    }

    private mutating func parseRawGroup(for command: String, what: String) throws(NoteMathParseError) -> (text: String, start: Int, end: Int) {
        let start = skipIndex(from: index)
        guard start < characters.count, characters[start] == "{" else {
            throw failure("\\\(command) needs {\(what)} after it", from: max(start - 1, 0), to: start)
        }
        var end = start + 1
        while end < characters.count, characters[end] != "}" { end += 1 }
        guard end < characters.count else { throw failure("Missing } to close this {", from: start, to: start + 1) }
        index = end + 1
        let text = String(characters[(start + 1)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, start, end + 1)
    }

    private mutating func parseColor(after command: String) throws(NoteMathParseError) -> NoteMathColor {
        let raw = try parseRawGroup(for: command, what: "a colour")
        guard let color = NoteMathSymbols.color(named: raw.text) else {
            throw failure("Unknown colour \u{201C}\(raw.text)\u{201D}", from: raw.start, to: raw.end)
        }
        return color
    }

    private mutating func parseDimensionArgument(for command: String, at lexeme: Lexeme) throws(NoteMathParseError) -> Double {
        let start = skipIndex(from: index)
        if start < characters.count, characters[start] == "{" {
            let raw = try parseRawGroup(for: command, what: "a size")
            guard let value = Self.dimension(raw.text) else {
                throw failure("\u{201C}\(raw.text)\u{201D} isn't a size I understand, like 1em or 3mu", from: raw.start, to: raw.end)
            }
            return value
        }
        var end = start
        while end < characters.count, characters[end] == "-" || characters[end] == "+" || characters[end] == "."
                || characters[end].isNumber || characters[end] == " " { end += 1 }
        let unitStart = end
        while end < characters.count, end - unitStart < 2, Self.isLetter(characters[end]) { end += 1 }
        let text = String(characters[start..<end])
        guard end > start, let value = Self.dimension(text) else {
            throw failure("\\\(command) needs a size after it, like 1em or 3mu", lexeme)
        }
        index = end
        return value
    }

    static func dimension(_ text: String) -> Double? {
        let trimmed = text.replacingOccurrences(of: " ", with: "")
        var numberEnd = trimmed.startIndex
        while numberEnd < trimmed.endIndex, "+-.0123456789".contains(trimmed[numberEnd]) {
            numberEnd = trimmed.index(after: numberEnd)
        }
        let numberText = String(trimmed[..<numberEnd])
        guard let number = Double(numberText == "-" || numberText == "+" ? numberText + "1" : numberText) else { return nil }
        switch trimmed[numberEnd...].lowercased() {
        case "em": return number
        case "ex": return number * 0.43
        case "mu": return number / 18
        case "pt", "px": return number / 10
        case "bp": return number * 1.00375 / 10
        case "pc": return number * 1.2
        case "mm": return number * 0.284528
        case "cm": return number * 2.84528
        case "in": return number * 7.227
        default: return nil
        }
    }

    private mutating func parseOptionalRowSpacing() throws(NoteMathParseError) -> Double? {
        let start = skipIndex(from: index)
        guard start < characters.count, characters[start] == "[" else { return nil }
        var end = start + 1
        while end < characters.count, characters[end] != "]" { end += 1 }
        guard end < characters.count else { throw failure("Missing ] to close this [", from: start, to: start + 1) }
        let text = String(characters[(start + 1)..<end])
        guard let value = Self.dimension(text) else {
            throw failure("\u{201C}\(text)\u{201D} isn't a size I understand, like 4pt", from: start, to: end + 1)
        }
        index = end + 1
        return value
    }

    private mutating func parseText(_ style: NoteMathTextStyle, command: Lexeme, name: String) throws(NoteMathParseError) -> NoteMathNode {
        let start = skipIndex(from: index)
        guard start < characters.count, characters[start] == "{" else {
            let next = peek()
            if case .character(let character) = next.token, !"}&^_$".contains(character) {
                advance(past: next)
                return .text(String(character), style)
            }
            throw failure("\\\(name) needs {text} after it", command)
        }
        index = start + 1
        var segments: [NoteMathNode] = []
        var buffer = ""
        var nesting = 0
        func flush() {
            if !buffer.isEmpty { segments.append(.text(buffer, style)) }
            buffer = ""
        }
        while true {
            guard index < characters.count else { throw failure("Missing } to close this \\\(name)", command) }
            let character = characters[index]
            switch character {
            case "{":
                nesting += 1
                index += 1
            case "}":
                index += 1
                if nesting == 0 {
                    if segments.isEmpty { return .text(buffer, style) }
                    flush()
                    return .group(segments)
                }
                nesting -= 1
            case "$":
                let open = index
                index += 1
                flush()
                try enter(command)
                let nodes = try parseList(.inlineMath(open))
                depth -= 1
                advance(past: peek())
                segments.append(.mathStyle(.text, nodes))
            case "\\":
                let escape = lexeme(at: index)
                guard case .command(let escaped) = escape.token else { break }
                index = escape.end
                if let replacement = Self.textEscapes[escaped] {
                    buffer += replacement
                } else if escaped == "ref" || escaped == "eqref" {
                    flush()
                    segments.append(try parseReference(escaped, escape))
                } else {
                    throw failure("\\\(escaped) doesn't work inside \\\(name)", escape)
                }
            default:
                if character.isWhitespace {
                    if !buffer.hasSuffix(" ") { buffer += " " }
                } else {
                    buffer.append(character)
                }
                index += 1
            }
        }
    }

    private mutating func parseEnvironment(_ lexeme: Lexeme) throws(NoteMathParseError) -> NoteMathNode {
        try enter(lexeme)
        defer { depth -= 1 }
        let name = try parseRawGroup(for: "begin", what: "an environment name")
        guard let shape = Self.environments[name.text] else {
            throw failure("Unknown environment \u{201C}\(name.text)\u{201D}", from: name.start, to: name.end)
        }
        var environment = NoteMathEnvironment(kind: shape.kind, rows: [], columns: [], left: shape.left, right: shape.right)
        let tagsRows = display && depth == 1 && Self.numberedEnvironments[name.text] != nil
        let numbered = tagsRows && Self.numberedEnvironments[name.text] == true
        let outerTag = pendingTag
        let outerLabel = pendingLabel
        let outerSuppression = suppressesNumber
        if tagsRows {
            pendingTag = nil
            pendingLabel = nil
            suppressesNumber = false
        }
        var specified: [NoteMathColumnAlignment]?
        if shape.kind == .array {
            let spec = try parseRawGroup(for: "begin{array}", what: "columns like lcr")
            var columns: [NoteMathColumnAlignment] = []
            for character in spec.text where !character.isWhitespace {
                switch character {
                case "l": columns.append(.left)
                case "c": columns.append(.center)
                case "r": columns.append(.right)
                case "|": environment.columnRules.append(columns.count)
                default:
                    throw failure("Array columns only take l, c, r and |", from: spec.start, to: spec.end)
                }
            }
            if columns.isEmpty { throw failure("Array needs at least one column, like {cc}", from: spec.start, to: spec.end) }
            specified = columns
        }
        let maximumColumns = specified?.count ?? (shape.kind == .gathered ? 1 : shape.kind == .cases ? 2 : Int.max)
        var row: [[NoteMathNode]] = []
        consumeRowRules(into: &environment, row: 0)
        while true {
            row.append(try parseList(.cell(name.text, lexeme.start)))
            let next = peek()
            advance(past: next)
            switch next.token {
            case .character("&"):
                if row.count >= maximumColumns {
                    throw failure(shape.kind == .gathered ? "\(name.text) doesn't use &" : "This row has more columns than \(name.text) allows", next)
                }
            case .command("end"):
                let closing = try parseRawGroup(for: "end", what: "an environment name")
                guard closing.text == name.text else {
                    throw failure("\\begin{\(name.text)} ends with \\end{\(closing.text)}", from: closing.start, to: closing.end)
                }
                let trailingEmpty = row.count == 1 && row[0].isEmpty && pendingTag == nil && pendingLabel == nil
                if !trailingEmpty || environment.rows.isEmpty {
                    environment.rows.append(row)
                    if tagsRows { environment.tags.append(try rowTag(numbered: numbered)) }
                }
                if tagsRows {
                    if environment.tags.allSatisfy({ $0 == nil }) { environment.tags = [] }
                    pendingTag = outerTag
                    pendingLabel = outerLabel
                    suppressesNumber = outerSuppression
                }
                let columnCount = environment.rows.map(\.count).max() ?? 1
                environment.columns = specified ?? Self.defaultColumns(for: shape.kind, count: columnCount)
                return .environment(environment)
            default:
                environment.rows.append(row)
                if tagsRows { environment.tags.append(try rowTag(numbered: numbered)) }
                row = []
                if let spacing = try parseOptionalRowSpacing() { environment.rowSpacing[environment.rows.count - 1] = spacing }
                consumeRowRules(into: &environment, row: environment.rows.count)
            }
        }
    }

    private mutating func consumeRowRules(into environment: inout NoteMathEnvironment, row: Int) {
        while true {
            let next = peek()
            guard next.token == .command("hline") || next.token == .command("hdashline") else { return }
            advance(past: next)
            environment.rowRules.append(row)
        }
    }

    private static func defaultColumns(for kind: NoteMathEnvironmentKind, count: Int) -> [NoteMathColumnAlignment] {
        switch kind {
        case .cases: return Array(repeating: .left, count: max(count, 1))
        case .aligned: return (0..<max(count, 1)).map { $0.isMultiple(of: 2) ? .right : .left }
        default: return Array(repeating: .center, count: max(count, 1))
        }
    }

    private static let environments: [String: (kind: NoteMathEnvironmentKind, left: String?, right: String?)] = [
        "matrix": (.matrix, nil, nil), "pmatrix": (.matrix, "(", ")"), "bmatrix": (.matrix, "[", "]"),
        "Bmatrix": (.matrix, "{", "}"), "vmatrix": (.matrix, "|", "|"), "Vmatrix": (.matrix, "\u{2016}", "\u{2016}"),
        "smallmatrix": (.smallMatrix, nil, nil), "cases": (.cases, "{", nil), "rcases": (.cases, nil, "}"),
        "aligned": (.aligned, nil, nil), "align": (.aligned, nil, nil), "align*": (.aligned, nil, nil),
        "split": (.aligned, nil, nil), "gathered": (.gathered, nil, nil), "gather": (.gathered, nil, nil),
        "gather*": (.gathered, nil, nil), "array": (.array, nil, nil), "equation": (.gathered, nil, nil),
        "equation*": (.gathered, nil, nil),
    ]

    private static let numberedEnvironments: [String: Bool] = [
        "align": true, "gather": true, "equation": true, "align*": false, "gather*": false, "equation*": false,
    ]

    private static let styleSwitches: [String: NoteMathStyleLevel] = [
        "displaystyle": .display, "textstyle": .text, "scriptstyle": .script, "scriptscriptstyle": .scriptScript,
    ]

    private static let fontSwitches: [String: NoteMathVariant] = [
        "rm": .roman, "bf": .bold, "it": .italic, "sf": .sansSerif, "tt": .monospace, "cal": .script,
    ]

    private static let fontCommands: [String: NoteMathVariant] = [
        "mathrm": .roman, "mathup": .roman, "mathbf": .bold, "mathit": .italic, "mathbb": .doubleStruck,
        "mathcal": .script, "mathscr": .script, "mathfrak": .fraktur, "mathsf": .sansSerif, "mathtt": .monospace,
        "boldsymbol": .boldItalic, "bm": .boldItalic, "mathnormal": .normal, "Bbb": .doubleStruck,
    ]

    private static let textCommands: [String: NoteMathTextStyle] = [
        "text": .roman, "textrm": .roman, "textnormal": .roman, "textup": .roman, "mbox": .roman, "hbox": .roman,
        "textbf": .bold, "textit": .italic, "emph": .italic, "textsf": .sansSerif, "texttt": .monospace,
    ]

    private static let textEscapes: [String: String] = [
        "{": "{", "}": "}", "$": "$", "%": "%", "&": "&", "#": "#", "_": "_", " ": " ", "\n": " ", "\\": "\n",
        ",": "\u{2009}", "textbackslash": "\\", "ldots": "\u{2026}", "dots": "\u{2026}", "quad": "\u{2003}",
        "qquad": "\u{2003}\u{2003}", "textasciitilde": "~", "textasciicircum": "^", "S": "\u{00A7}",
        "P": "\u{00B6}", "copyright": "\u{00A9}", "textendash": "\u{2013}", "textemdash": "\u{2014}",
    ]

    private static let decorations: [String: NoteMathDecoration] = [
        "hat": .accent("\u{0302}"), "check": .accent("\u{030C}"), "tilde": .accent("\u{0303}"),
        "acute": .accent("\u{0301}"), "grave": .accent("\u{0300}"), "dot": .accent("\u{0307}"),
        "ddot": .accent("\u{0308}"), "dddot": .accent("\u{20DB}"), "breve": .accent("\u{0306}"),
        "bar": .accent("\u{0304}"), "vec": .accent("\u{20D7}"), "mathring": .accent("\u{030A}"),
        "widehat": .wideAccent("\u{0302}"), "widetilde": .wideAccent("\u{0303}"), "widecheck": .wideAccent("\u{030C}"),
        "overline": .overline, "underline": .underline, "overbrace": .overbrace, "underbrace": .underbrace,
        "overrightarrow": .overArrow("\u{2192}"), "overleftarrow": .overArrow("\u{2190}"),
        "overleftrightarrow": .overArrow("\u{2194}"), "underrightarrow": .underArrow("\u{2192}"),
        "underleftarrow": .underArrow("\u{2190}"), "underleftrightarrow": .underArrow("\u{2194}"),
        "cancel": .cancel, "bcancel": .backCancel, "xcancel": .crossCancel, "sout": .strike,
    ]

    private static let extensibleArrows: [String: String] = [
        "xrightarrow": "→", "xleftarrow": "←", "xleftrightarrow": "↔", "xRightarrow": "⇒", "xLeftarrow": "⇐",
        "xLeftrightarrow": "⇔", "xmapsto": "↦", "xhookrightarrow": "↪", "xhookleftarrow": "↩",
        "xrightharpoonup": "⇀", "xrightharpoondown": "⇁", "xleftharpoonup": "↼", "xleftharpoondown": "↽",
        "xrightleftharpoons": "⇌", "xleftrightharpoons": "⇋", "xrightleftarrows": "⇄", "xtofrom": "⇄",
        "xrightequilibrium": "⥂", "xleftequilibrium": "⥄",
    ]

    private static let sizedDelimiters: [String: (Int, NoteMathAtomKind)] = [
        "big": (1, .ord), "bigl": (1, .open), "bigr": (1, .close), "bigm": (1, .rel),
        "Big": (2, .ord), "Bigl": (2, .open), "Bigr": (2, .close), "Bigm": (2, .rel),
        "bigg": (3, .ord), "biggl": (3, .open), "biggr": (3, .close), "biggm": (3, .rel),
        "Bigg": (4, .ord), "Biggl": (4, .open), "Biggr": (4, .close), "Biggm": (4, .rel),
    ]

    private static let classCommands: [String: NoteMathAtomKind] = [
        "mathord": .ord, "mathop": .op, "mathbin": .bin, "mathrel": .rel, "mathopen": .open,
        "mathclose": .close, "mathpunct": .punct, "mathinner": .inner,
    ]
}

enum NoteMathSymbols {
    static let symbols: [String: (String, NoteMathAtomKind)] = {
        var table: [String: (String, NoteMathAtomKind)] = [:]
        for (name, symbol) in greek { table[name] = (symbol, .ord) }
        for (name, symbol) in ordinary { table[name] = (symbol, .ord) }
        for (name, symbol) in binary { table[name] = (symbol, .bin) }
        for (name, symbol) in relations { table[name] = (symbol, .rel) }
        for (name, symbol) in arrows { table[name] = (symbol, .rel) }
        for (name, symbol) in opening { table[name] = (symbol, .open) }
        for (name, symbol) in closing { table[name] = (symbol, .close) }
        for (name, symbol) in punctuation { table[name] = (symbol, .punct) }
        for (name, symbol) in inner { table[name] = (symbol, .inner) }
        return table
    }()

    static let kindsByCharacter: [String: NoteMathAtomKind] = {
        var table: [String: NoteMathAtomKind] = [:]
        for (_, entry) in symbols where table[entry.0] == nil && entry.0.unicodeScalars.count == 1 {
            table[entry.0] = entry.1
        }
        table["\u{00B7}"] = .bin
        table["|"] = .ord
        table["\u{2016}"] = .ord
        return table
    }()

    static let largeOperatorsByCharacter: [String: Bool] = {
        var table: [String: Bool] = [:]
        for (_, entry) in largeOperators { table[entry.0] = entry.1 }
        return table
    }()

    static let greek: [(String, String)] = [
        ("alpha", "α"), ("beta", "β"), ("gamma", "γ"), ("delta", "δ"), ("epsilon", "ϵ"), ("varepsilon", "ε"),
        ("zeta", "ζ"), ("eta", "η"), ("theta", "θ"), ("vartheta", "ϑ"), ("iota", "ι"), ("kappa", "κ"),
        ("varkappa", "ϰ"), ("lambda", "λ"), ("mu", "μ"), ("nu", "ν"), ("xi", "ξ"), ("omicron", "ο"), ("pi", "π"),
        ("varpi", "ϖ"), ("rho", "ρ"), ("varrho", "ϱ"), ("sigma", "σ"), ("varsigma", "ς"), ("tau", "τ"),
        ("upsilon", "υ"), ("phi", "ϕ"), ("varphi", "φ"), ("chi", "χ"), ("psi", "ψ"), ("omega", "ω"),
        ("digamma", "ϝ"), ("Gamma", "Γ"), ("Delta", "Δ"), ("Theta", "Θ"), ("Lambda", "Λ"), ("Xi", "Ξ"),
        ("Pi", "Π"), ("Sigma", "Σ"), ("Upsilon", "Υ"), ("Phi", "Φ"), ("Psi", "Ψ"), ("Omega", "Ω"),
        ("Alpha", "Α"), ("Beta", "Β"), ("Epsilon", "Ε"), ("Zeta", "Ζ"), ("Eta", "Η"), ("Iota", "Ι"),
        ("Kappa", "Κ"), ("Mu", "Μ"), ("Nu", "Ν"), ("Omicron", "Ο"), ("Rho", "Ρ"), ("Tau", "Τ"), ("Chi", "Χ"),
    ]

    static let italicCapitals: [String: String] = [
        "varGamma": "Γ", "varDelta": "Δ", "varTheta": "Θ", "varLambda": "Λ", "varXi": "Ξ", "varPi": "Π",
        "varSigma": "Σ", "varUpsilon": "Υ", "varPhi": "Φ", "varPsi": "Ψ", "varOmega": "Ω",
    ]

    static let ordinary: [(String, String)] = [
        ("infty", "∞"), ("partial", "∂"), ("nabla", "∇"), ("forall", "∀"), ("exists", "∃"), ("nexists", "∄"),
        ("emptyset", "∅"), ("varnothing", "∅"), ("neg", "¬"), ("lnot", "¬"), ("top", "⊤"), ("bot", "⊥"),
        ("angle", "∠"), ("measuredangle", "∡"), ("sphericalangle", "∢"), ("triangle", "△"), ("square", "□"),
        ("Box", "□"), ("blacksquare", "■"), ("Diamond", "◇"), ("lozenge", "◊"), ("blacklozenge", "⧫"),
        ("clubsuit", "♣"), ("diamondsuit", "♢"), ("heartsuit", "♡"), ("spadesuit", "♠"), ("flat", "♭"),
        ("natural", "♮"), ("sharp", "♯"), ("hbar", "ℏ"), ("hslash", "ℏ"), ("ell", "ℓ"), ("wp", "℘"),
        ("Re", "ℜ"), ("Im", "ℑ"), ("aleph", "ℵ"), ("beth", "ℶ"), ("gimel", "ℷ"), ("daleth", "ℸ"),
        ("prime", "′"), ("backprime", "‵"), ("imath", "ı"), ("jmath", "ȷ"), ("mho", "℧"), ("eth", "ð"),
        ("complement", "∁"), ("surd", "√"), ("checkmark", "✓"), ("dag", "†"), ("ddag", "‡"), ("S", "§"),
        ("P", "¶"), ("copyright", "©"), ("pounds", "£"), ("yen", "¥"), ("euro", "€"), ("degree", "°"),
        ("circledR", "®"), ("circledS", "Ⓢ"), ("Finv", "Ⅎ"), ("Game", "⅁"), ("backslash", "\\"),
        ("vert", "|"), ("Vert", "‖"), ("|", "‖"), ("#", "#"), ("%", "%"), ("&", "&"), ("_", "_"), ("$", "$"),
        ("vdots", "⋮"), ("bigstar", "★"), ("diagup", "╱"), ("diagdown", "╲"), ("blacktriangle", "▲"),
        ("triangledown", "▽"), ("blacktriangledown", "▼"), ("varkappa", "ϰ"), ("infin", "∞"), ("Bbbk", "𝕜"),
        ("R", "ℝ"), ("Reals", "ℝ"), ("reals", "ℝ"), ("N", "ℕ"), ("natnums", "ℕ"), ("Z", "ℤ"), ("Q", "ℚ"),
        ("C", "ℂ"), ("Complex", "ℂ"),
    ]

    static let binary: [(String, String)] = [
        ("pm", "±"), ("mp", "∓"), ("times", "×"), ("div", "÷"), ("cdot", "⋅"), ("ast", "∗"), ("star", "⋆"),
        ("circ", "∘"), ("bullet", "∙"), ("oplus", "⊕"), ("ominus", "⊖"), ("otimes", "⊗"), ("oslash", "⊘"),
        ("odot", "⊙"), ("cup", "∪"), ("cap", "∩"), ("uplus", "⊎"), ("sqcup", "⊔"), ("sqcap", "⊓"),
        ("vee", "∨"), ("lor", "∨"), ("wedge", "∧"), ("land", "∧"), ("setminus", "∖"), ("smallsetminus", "∖"),
        ("wr", "≀"), ("diamond", "⋄"), ("bigtriangleup", "△"), ("bigtriangledown", "▽"),
        ("triangleleft", "◁"), ("triangleright", "▷"), ("lhd", "⊲"), ("rhd", "⊳"), ("unlhd", "⊴"),
        ("unrhd", "⊵"), ("dagger", "†"), ("ddagger", "‡"), ("amalg", "⨿"), ("centerdot", "⋅"),
        ("ltimes", "⋉"), ("rtimes", "⋊"), ("boxplus", "⊞"), ("boxminus", "⊟"), ("boxtimes", "⊠"),
        ("boxdot", "⊡"), ("divideontimes", "⋇"), ("dotplus", "∔"), ("barwedge", "⊼"), ("veebar", "⊻"),
        ("curlyvee", "⋎"), ("curlywedge", "⋏"), ("intercal", "⊺"), ("circledast", "⊛"),
        ("circledcirc", "⊚"), ("circleddash", "⊝"),
    ]

    static let relations: [(String, String)] = [
        ("leq", "≤"), ("le", "≤"), ("geq", "≥"), ("ge", "≥"), ("neq", "≠"), ("ne", "≠"), ("approx", "≈"),
        ("equiv", "≡"), ("sim", "∼"), ("simeq", "≃"), ("cong", "≅"), ("propto", "∝"), ("in", "∈"),
        ("notin", "∉"), ("ni", "∋"), ("owns", "∋"), ("subset", "⊂"), ("supset", "⊃"), ("subseteq", "⊆"),
        ("supseteq", "⊇"), ("subsetneq", "⊊"), ("supsetneq", "⊋"), ("nsubseteq", "⊈"), ("nsupseteq", "⊉"),
        ("sqsubset", "⊏"), ("sqsupset", "⊐"), ("sqsubseteq", "⊑"), ("sqsupseteq", "⊒"), ("ll", "≪"),
        ("gg", "≫"), ("lll", "⋘"), ("ggg", "⋙"), ("prec", "≺"), ("succ", "≻"), ("preceq", "⪯"),
        ("succeq", "⪰"), ("perp", "⟂"), ("parallel", "∥"), ("mid", "∣"), ("nmid", "∤"), ("nparallel", "∦"),
        ("models", "⊨"), ("vdash", "⊢"), ("dashv", "⊣"), ("vDash", "⊨"), ("Vdash", "⊩"), ("asymp", "≍"),
        ("doteq", "≐"), ("bowtie", "⋈"), ("Join", "⋈"), ("smile", "⌣"), ("frown", "⌢"), ("coloneqq", "≔"),
        ("eqqcolon", "≕"), ("triangleq", "≜"), ("leqslant", "⩽"), ("geqslant", "⩾"), ("lesssim", "≲"),
        ("gtrsim", "≳"), ("approxeq", "≊"), ("nless", "≮"), ("ngtr", "≯"), ("nleq", "≰"), ("ngeq", "≱"),
        ("nsim", "≁"), ("ncong", "≇"), ("therefore", "∴"), ("because", "∵"), ("leqq", "≦"), ("geqq", "≧"),
        ("lneq", "⪇"), ("gneq", "⪈"), ("risingdotseq", "≓"),
        ("fallingdotseq", "≒"), ("backsim", "∽"), ("eqsim", "≂"), ("thicksim", "∼"), ("thickapprox", "≈"),
        ("varpropto", "∝"), ("between", "≬"), ("pitchfork", "⋔"), ("Subset", "⋐"),
        ("Supset", "⋑"), ("vartriangleleft", "⊲"), ("vartriangleright", "⊳"), ("trianglelefteq", "⊴"),
        ("trianglerighteq", "⊵"), ("coloneq", "≔"), ("dashleftarrow", "⇠"),
    ]

    static let arrows: [(String, String)] = [
        ("leftarrow", "←"), ("gets", "←"), ("rightarrow", "→"), ("to", "→"), ("leftrightarrow", "↔"),
        ("Leftarrow", "⇐"), ("Rightarrow", "⇒"), ("Leftrightarrow", "⇔"), ("longleftarrow", "⟵"),
        ("longrightarrow", "⟶"), ("longleftrightarrow", "⟷"), ("Longleftarrow", "⟸"), ("Longrightarrow", "⟹"),
        ("Longleftrightarrow", "⟺"), ("iff", "⟺"), ("implies", "⟹"), ("impliedby", "⟸"), ("mapsto", "↦"),
        ("longmapsto", "⟼"), ("hookleftarrow", "↩"), ("hookrightarrow", "↪"), ("uparrow", "↑"),
        ("downarrow", "↓"), ("updownarrow", "↕"), ("Uparrow", "⇑"), ("Downarrow", "⇓"), ("Updownarrow", "⇕"),
        ("nearrow", "↗"), ("searrow", "↘"), ("swarrow", "↙"), ("nwarrow", "↖"), ("leftharpoonup", "↼"),
        ("leftharpoondown", "↽"), ("rightharpoonup", "⇀"), ("rightharpoondown", "⇁"),
        ("rightleftharpoons", "⇌"), ("leftrightharpoons", "⇋"), ("leadsto", "⇝"), ("rightsquigarrow", "⇝"),
        ("twoheadrightarrow", "↠"), ("twoheadleftarrow", "↞"), ("rightarrowtail", "↣"),
        ("leftarrowtail", "↢"), ("circlearrowleft", "↺"), ("circlearrowright", "↻"), ("curvearrowleft", "↶"),
        ("curvearrowright", "↷"), ("Lsh", "↰"), ("Rsh", "↱"), ("upuparrows", "⇈"), ("downdownarrows", "⇊"),
        ("leftleftarrows", "⇇"), ("rightrightarrows", "⇉"), ("leftrightarrows", "⇆"), ("rightleftarrows", "⇄"),
        ("nleftarrow", "↚"), ("nrightarrow", "↛"), ("nLeftarrow", "⇍"), ("nRightarrow", "⇏"),
        ("nleftrightarrow", "↮"), ("nLeftrightarrow", "⇎"), ("dashrightarrow", "⇢"), ("multimap", "⊸"),
        ("upharpoonleft", "↿"), ("upharpoonright", "↾"), ("downharpoonleft", "⇃"), ("downharpoonright", "⇂"),
    ]

    static let opening: [(String, String)] = [
        ("{", "{"), ("lbrace", "{"), ("langle", "⟨"), ("lceil", "⌈"), ("lfloor", "⌊"), ("lvert", "|"),
        ("lVert", "‖"), ("lgroup", "⟮"), ("lbrack", "["), ("ulcorner", "⌜"), ("llcorner", "⌞"),
        ("llbracket", "⟦"), ("lmoustache", "⎰"),
    ]

    static let closing: [(String, String)] = [
        ("}", "}"), ("rbrace", "}"), ("rangle", "⟩"), ("rceil", "⌉"), ("rfloor", "⌋"), ("rvert", "|"),
        ("rVert", "‖"), ("rgroup", "⟯"), ("rbrack", "]"), ("urcorner", "⌝"), ("lrcorner", "⌟"),
        ("rrbracket", "⟧"), ("rmoustache", "⎱"),
    ]

    static let punctuation: [(String, String)] = [
        ("ldotp", "."), ("cdotp", "⋅"),
    ]

    static let inner: [(String, String)] = [
        ("ldots", "…"), ("dots", "…"), ("dotsc", "…"), ("dotso", "…"), ("cdots", "⋯"), ("dotsb", "⋯"),
        ("dotsm", "⋯"), ("dotsi", "⋯"), ("ddots", "⋱"), ("iddots", "⋰"),
    ]

    static let largeOperators: [String: (String, Bool)] = [
        "sum": ("∑", false), "prod": ("∏", false), "coprod": ("∐", false), "bigcup": ("⋃", false),
        "bigcap": ("⋂", false), "bigvee": ("⋁", false), "bigwedge": ("⋀", false), "bigoplus": ("⨁", false),
        "bigotimes": ("⨂", false), "bigodot": ("⨀", false), "biguplus": ("⨄", false), "bigsqcup": ("⨆", false),
        "int": ("∫", true), "iint": ("∬", true), "iiint": ("∭", true), "iiiint": ("⨌", true),
        "oint": ("∮", true), "oiint": ("∯", true), "oiiint": ("∰", true), "intop": ("∫", false),
        "smallint": ("∫", true),
    ]

    static let functions: [String: (String, Bool)] = [
        "arccos": ("arccos", false), "arcsin": ("arcsin", false), "arctan": ("arctan", false),
        "arg": ("arg", false), "cos": ("cos", false), "cosh": ("cosh", false), "cot": ("cot", false),
        "coth": ("coth", false), "csc": ("csc", false), "deg": ("deg", false), "dim": ("dim", false),
        "exp": ("exp", false), "hom": ("hom", false), "ker": ("ker", false), "lg": ("lg", false),
        "ln": ("ln", false), "log": ("log", false), "sec": ("sec", false), "sin": ("sin", false),
        "sinh": ("sinh", false), "tan": ("tan", false), "tanh": ("tanh", false), "sgn": ("sgn", false),
        "det": ("det", true), "gcd": ("gcd", true), "inf": ("inf", true), "lim": ("lim", true),
        "liminf": ("lim\u{2009}inf", true), "limsup": ("lim\u{2009}sup", true), "max": ("max", true),
        "min": ("min", true), "Pr": ("Pr", true), "sup": ("sup", true), "argmax": ("arg\u{2009}max", true),
        "argmin": ("arg\u{2009}min", true), "injlim": ("inj\u{2009}lim", true), "projlim": ("proj\u{2009}lim", true),
    ]

    static let spaces: [String: Double] = [
        ",": 3.0 / 18, "thinspace": 3.0 / 18, ":": 4.0 / 18, ">": 4.0 / 18, "medspace": 4.0 / 18,
        ";": 5.0 / 18, "thickspace": 5.0 / 18, "!": -3.0 / 18, "negthinspace": -3.0 / 18,
        "negmedspace": -4.0 / 18, "negthickspace": -5.0 / 18, "quad": 1, "qquad": 2, " ": 1.0 / 3,
        "\n": 1.0 / 3, "\t": 1.0 / 3, "enspace": 0.5, "space": 1.0 / 3, "nobreakspace": 1.0 / 3,
    ]

    static let delimiterCharacters: [Character: String] = [
        "(": "(", ")": ")", "[": "[", "]": "]", "|": "|", "/": "/", "<": "⟨", ">": "⟩",
        "⟨": "⟨", "⟩": "⟩", "‖": "‖", "⌊": "⌊", "⌋": "⌋", "⌈": "⌈", "⌉": "⌉",
    ]

    static let delimiterCommands: [String: String] = [
        "{": "{", "}": "}", "lbrace": "{", "rbrace": "}", "|": "‖", "Vert": "‖", "lVert": "‖", "rVert": "‖",
        "vert": "|", "lvert": "|", "rvert": "|", "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋",
        "lceil": "⌈", "rceil": "⌉", "backslash": "\\", "uparrow": "↑", "downarrow": "↓", "updownarrow": "↕",
        "Uparrow": "⇑", "Downarrow": "⇓", "Updownarrow": "⇕", "lbrack": "[", "rbrack": "]", "lgroup": "⟮",
        "rgroup": "⟯", "ulcorner": "⌜", "urcorner": "⌝", "llcorner": "⌞", "lrcorner": "⌟",
        "lmoustache": "⎰", "rmoustache": "⎱", "llbracket": "⟦", "rrbracket": "⟧", "mid": "∣",
    ]

    static let negations: [String: String] = [
        "=": "≠", "∈": "∉", "≡": "≢", "⊂": "⊄", "⊃": "⊅", "⊆": "⊈", "⊇": "⊉", "<": "≮", ">": "≯",
        "≤": "≰", "≥": "≱", "∼": "≁", "≈": "≉", "≅": "≇", "∋": "∌", "∃": "∄", "∣": "∤", "∥": "∦",
        "≃": "≄", "≺": "⊀", "≻": "⊁", "⊢": "⊬", "⊨": "⊭", "≍": "≭", "⊑": "⋢", "⊒": "⋣",
    ]

    static let namedColors: [String: UInt32] = [
        "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "blue": 0x0000FF,
        "cyan": 0x00FFFF, "magenta": 0xFF00FF, "yellow": 0xFFFF00, "gray": 0x808080, "grey": 0x808080,
        "orange": 0xFFA500, "purple": 0x800080, "brown": 0xA52A2A, "pink": 0xFFC0CB, "lime": 0x00FF00,
        "olive": 0x808000, "teal": 0x008080, "violet": 0xEE82EE, "darkgray": 0xA9A9A9, "darkgrey": 0xA9A9A9,
        "lightgray": 0xD3D3D3, "lightgrey": 0xD3D3D3, "navy": 0x000080, "maroon": 0x800000,
        "silver": 0xC0C0C0, "gold": 0xFFD700, "indigo": 0x4B0082, "coral": 0xFF7F50, "salmon": 0xFA8072,
        "crimson": 0xDC143C, "tomato": 0xFF6347, "turquoise": 0x40E0D0, "skyblue": 0x87CEEB,
        "royalblue": 0x4169E1, "forestgreen": 0x228B22, "seagreen": 0x2E8B57, "darkblue": 0x00008B,
        "darkred": 0x8B0000, "darkgreen": 0x006400, "darkorange": 0xFF8C00, "aqua": 0x00FFFF,
        "fuchsia": 0xFF00FF, "plum": 0xDDA0DD, "orchid": 0xDA70D6, "tan": 0xD2B48C, "khaki": 0xF0E68C,
    ]

    static func color(named raw: String) -> NoteMathColor? {
        let name = raw.lowercased()
        if let value = namedColors[name] { return color(hex: value) }
        let digits = name.hasPrefix("#") ? String(name.dropFirst()) : name
        guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 6 { return color(hex: value) }
        if digits.count == 3 {
            let red = (value >> 8) & 15, green = (value >> 4) & 15, blue = value & 15
            return color(hex: red * 0x110000 + green * 0x1100 + blue * 0x11)
        }
        return nil
    }

    private static func color(hex: UInt32) -> NoteMathColor {
        NoteMathColor(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255,
                      blue: Double(hex & 255) / 255)
    }
}
