import Foundation

struct NoteSyntaxFeatures: OptionSet, Sendable {
    let rawValue: UInt64

    static let regexLiterals = NoteSyntaxFeatures(rawValue: 1 << 0)
    static let jsx = NoteSyntaxFeatures(rawValue: 1 << 1)
    static let taggedTemplates = NoteSyntaxFeatures(rawValue: 1 << 2)
    static let privateNames = NoteSyntaxFeatures(rawValue: 1 << 3)
    static let swiftLiterals = NoteSyntaxFeatures(rawValue: 1 << 4)
    static let rustLiterals = NoteSyntaxFeatures(rawValue: 1 << 5)
    static let preprocessor = NoteSyntaxFeatures(rawValue: 1 << 6)
    static let csharpLiterals = NoteSyntaxFeatures(rawValue: 1 << 7)
    static let objcLiterals = NoteSyntaxFeatures(rawValue: 1 << 8)
    static let rubyLiterals = NoteSyntaxFeatures(rawValue: 1 << 9)
    static let symbols = NoteSyntaxFeatures(rawValue: 1 << 10)
    static let elixirSigils = NoteSyntaxFeatures(rawValue: 1 << 11)
    static let phpLiterals = NoteSyntaxFeatures(rawValue: 1 << 12)
    static let shell = NoteSyntaxFeatures(rawValue: 1 << 13)
    static let luaLongBrackets = NoteSyntaxFeatures(rawValue: 1 << 14)
    static let zigLiterals = NoteSyntaxFeatures(rawValue: 1 << 15)
    static let powershell = NoteSyntaxFeatures(rawValue: 1 << 16)
    static let sqlLiterals = NoteSyntaxFeatures(rawValue: 1 << 17)
    static let keysBeforeColon = NoteSyntaxFeatures(rawValue: 1 << 18)
    static let capsConstants = NoteSyntaxFeatures(rawValue: 1 << 19)
    static let capitalizedTypes = NoteSyntaxFeatures(rawValue: 1 << 20)
    static let callsAreFunctions = NoteSyntaxFeatures(rawValue: 1 << 21)
    static let arrowMembers = NoteSyntaxFeatures(rawValue: 1 << 22)
    static let memberProperties = NoteSyntaxFeatures(rawValue: 1 << 23)
    static let backtickIdentifiers = NoteSyntaxFeatures(rawValue: 1 << 24)
    static let decoratorsAtLineStart = NoteSyntaxFeatures(rawValue: 1 << 25)
    static let percentOperators = NoteSyntaxFeatures(rawValue: 1 << 26)
    static let haskellDashes = NoteSyntaxFeatures(rawValue: 1 << 27)
    static let lineStartFunctions = NoteSyntaxFeatures(rawValue: 1 << 28)
    static let signedNumbers = NoteSyntaxFeatures(rawValue: 1 << 29)
    static let graphqlLiterals = NoteSyntaxFeatures(rawValue: 1 << 30)
}

enum NoteSyntaxInterpolation: Sendable {
    case backslashParen, dollarBrace, dollarName, hashBrace, brace, php, shell, powershell
}

enum NoteSyntaxStringPrefixes: Sendable {
    case none, python, rust, cpp, scala, dart, r, sql
}

struct NoteSyntaxStringRule: Sendable {
    var open: [UInt16]
    var close: [UInt16]
    var escape: UInt16 = NoteSyntaxChar.backslash
    var escapes = true
    var rawEscapes = false
    var escapeHashes = 0
    var doubledClose = false
    var multiline = false
    var interpolation: NoteSyntaxInterpolation?
    var kind: NoteSyntaxKind = .string

    init(_ open: String, _ close: String? = nil, multiline: Bool = false, escapes: Bool = true, rawEscapes: Bool = false,
         doubledClose: Bool = false, interpolation: NoteSyntaxInterpolation? = nil, kind: NoteSyntaxKind = .string,
         escape: UInt16 = NoteSyntaxChar.backslash) {
        self.open = Array(open.utf16)
        self.close = Array((close ?? open).utf16)
        self.multiline = multiline
        self.escapes = escapes
        self.rawEscapes = rawEscapes
        self.doubledClose = doubledClose
        self.interpolation = interpolation
        self.kind = kind
        self.escape = escape
    }

    init(units open: [UInt16], close: [UInt16], multiline: Bool, escapes: Bool, interpolation: NoteSyntaxInterpolation?) {
        self.open = open
        self.close = close
        self.multiline = multiline
        self.escapes = escapes
        self.interpolation = interpolation
    }
}

struct NoteSyntaxBlockComment: Sendable {
    let open: [UInt16]
    let close: [UInt16]
    let nests: Bool
    let kind: NoteSyntaxKind

    init(_ open: String, _ close: String, nests: Bool = false, kind: NoteSyntaxKind = .comment) {
        self.open = Array(open.utf16)
        self.close = Array(close.utf16)
        self.nests = nests
        self.kind = kind
    }
}

final class NoteSyntaxGrammar: Sendable {
    let words: NoteSyntaxWords
    let lineComments: [[UInt16]]
    let blockComments: [NoteSyntaxBlockComment]
    let strings: [NoteSyntaxStringRule]
    let prefixes: NoteSyntaxStringPrefixes
    let features: NoteSyntaxFeatures
    let wordExtras: [UInt16]
    let wordStartExtras: [UInt16]
    let wordSuffixes: [UInt16]
    let operators: [UInt16]
    let punctuation: [UInt16]
    let dollarKind: NoteSyntaxKind?
    let atKind: NoteSyntaxKind?
    let digitSeparators: [UInt16]

    init(keywords: String = "", types: String = "", constants: String = "", builtins: String = "",
         operands: String = "", variables: String = "", functionDeclarators: String = "", typeDeclarators: String = "",
         commandStarters: String = "", caseInsensitive: Bool = false,
         lineComments: [String] = [], blockComments: [NoteSyntaxBlockComment] = [],
         strings: [NoteSyntaxStringRule] = [], prefixes: NoteSyntaxStringPrefixes = .none,
         features: NoteSyntaxFeatures = [.callsAreFunctions, .memberProperties],
         wordExtras: String = "", wordStartExtras: String = "", wordSuffixes: String = "",
         operators: String = "+-*/%=&|^!<>~?:", punctuation: String = "(){}[];,.",
         dollarKind: NoteSyntaxKind? = nil, atKind: NoteSyntaxKind? = nil, digitSeparators: String = "_") {
        var table = NoteSyntaxWords(caseInsensitive: caseInsensitive)
        table.add(builtins, .builtin)
        table.add(types, .type)
        table.add(constants, .constant)
        table.add(variables, .variable, role: .operand)
        table.add(keywords, .keyword)
        table.add(operands, .keyword, role: .operand)
        table.add(functionDeclarators, .keyword, role: .declaresFunction)
        table.add(typeDeclarators, .keyword, role: .declaresType)
        table.add(commandStarters, .keyword, role: .startsCommand)
        words = table
        self.lineComments = lineComments.map { Array($0.utf16) }
        self.blockComments = blockComments
        self.strings = strings
        self.prefixes = prefixes
        self.features = features
        self.wordExtras = Array(wordExtras.utf16)
        self.wordStartExtras = Array(wordStartExtras.utf16)
        self.wordSuffixes = Array(wordSuffixes.utf16)
        self.operators = Array(operators.utf16)
        self.punctuation = Array(punctuation.utf16)
        self.dollarKind = dollarKind
        self.atKind = atKind
        self.digitSeparators = Array(digitSeparators.utf16)
    }

    @inline(__always) func isWordStart(_ c: UInt16) -> Bool {
        NoteSyntaxChar.isWordStart(c) || (!wordStartExtras.isEmpty && wordStartExtras.contains(c))
    }

    @inline(__always) func isWord(_ c: UInt16) -> Bool {
        NoteSyntaxChar.isWord(c) || (!wordExtras.isEmpty && wordExtras.contains(c))
    }
}
