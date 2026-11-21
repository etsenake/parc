import Foundation

package struct NoteSyntaxFeatures: OptionSet, Sendable {
    package let rawValue: UInt64

    package init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    package static let regexLiterals = NoteSyntaxFeatures(rawValue: 1 << 0)
    package static let jsx = NoteSyntaxFeatures(rawValue: 1 << 1)
    package static let taggedTemplates = NoteSyntaxFeatures(rawValue: 1 << 2)
    package static let privateNames = NoteSyntaxFeatures(rawValue: 1 << 3)
    package static let swiftLiterals = NoteSyntaxFeatures(rawValue: 1 << 4)
    package static let rustLiterals = NoteSyntaxFeatures(rawValue: 1 << 5)
    package static let preprocessor = NoteSyntaxFeatures(rawValue: 1 << 6)
    package static let csharpLiterals = NoteSyntaxFeatures(rawValue: 1 << 7)
    package static let objcLiterals = NoteSyntaxFeatures(rawValue: 1 << 8)
    package static let rubyLiterals = NoteSyntaxFeatures(rawValue: 1 << 9)
    package static let symbols = NoteSyntaxFeatures(rawValue: 1 << 10)
    package static let elixirSigils = NoteSyntaxFeatures(rawValue: 1 << 11)
    package static let phpLiterals = NoteSyntaxFeatures(rawValue: 1 << 12)
    package static let shell = NoteSyntaxFeatures(rawValue: 1 << 13)
    package static let luaLongBrackets = NoteSyntaxFeatures(rawValue: 1 << 14)
    package static let zigLiterals = NoteSyntaxFeatures(rawValue: 1 << 15)
    package static let powershell = NoteSyntaxFeatures(rawValue: 1 << 16)
    package static let sqlLiterals = NoteSyntaxFeatures(rawValue: 1 << 17)
    package static let keysBeforeColon = NoteSyntaxFeatures(rawValue: 1 << 18)
    package static let capsConstants = NoteSyntaxFeatures(rawValue: 1 << 19)
    package static let capitalizedTypes = NoteSyntaxFeatures(rawValue: 1 << 20)
    package static let callsAreFunctions = NoteSyntaxFeatures(rawValue: 1 << 21)
    package static let arrowMembers = NoteSyntaxFeatures(rawValue: 1 << 22)
    package static let memberProperties = NoteSyntaxFeatures(rawValue: 1 << 23)
    package static let backtickIdentifiers = NoteSyntaxFeatures(rawValue: 1 << 24)
    package static let decoratorsAtLineStart = NoteSyntaxFeatures(rawValue: 1 << 25)
    package static let percentOperators = NoteSyntaxFeatures(rawValue: 1 << 26)
    package static let haskellDashes = NoteSyntaxFeatures(rawValue: 1 << 27)
    package static let lineStartFunctions = NoteSyntaxFeatures(rawValue: 1 << 28)
    package static let signedNumbers = NoteSyntaxFeatures(rawValue: 1 << 29)
    package static let graphqlLiterals = NoteSyntaxFeatures(rawValue: 1 << 30)
}

package enum NoteSyntaxInterpolation: Sendable {
    case backslashParen, dollarBrace, dollarName, hashBrace, brace, php, shell, powershell
}

package enum NoteSyntaxStringPrefixes: Sendable {
    case none, python, rust, cpp, scala, dart, r, sql
}

package struct NoteSyntaxStringRule: Sendable {
    package var open: [UInt16]
    package var close: [UInt16]
    package var escape: UInt16 = NoteSyntaxChar.backslash
    package var escapes = true
    package var rawEscapes = false
    package var escapeHashes = 0
    package var doubledClose = false
    package var multiline = false
    package var interpolation: NoteSyntaxInterpolation?
    package var kind: NoteSyntaxKind = .string

    package init(_ open: String, _ close: String? = nil, multiline: Bool = false, escapes: Bool = true, rawEscapes: Bool = false,
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

    package init(units open: [UInt16], close: [UInt16], multiline: Bool, escapes: Bool, interpolation: NoteSyntaxInterpolation?) {
        self.open = open
        self.close = close
        self.multiline = multiline
        self.escapes = escapes
        self.interpolation = interpolation
    }
}

package struct NoteSyntaxBlockComment: Sendable {
    package let open: [UInt16]
    package let close: [UInt16]
    package let nests: Bool
    package let kind: NoteSyntaxKind

    package init(_ open: String, _ close: String, nests: Bool = false, kind: NoteSyntaxKind = .comment) {
        self.open = Array(open.utf16)
        self.close = Array(close.utf16)
        self.nests = nests
        self.kind = kind
    }
}

package final class NoteSyntaxGrammar: Sendable {
    package let words: NoteSyntaxWords
    package let lineComments: [[UInt16]]
    package let blockComments: [NoteSyntaxBlockComment]
    package let strings: [NoteSyntaxStringRule]
    package let prefixes: NoteSyntaxStringPrefixes
    package let features: NoteSyntaxFeatures
    package let wordExtras: [UInt16]
    package let wordStartExtras: [UInt16]
    package let wordSuffixes: [UInt16]
    package let operators: [UInt16]
    package let punctuation: [UInt16]
    package let dollarKind: NoteSyntaxKind?
    package let atKind: NoteSyntaxKind?
    package let digitSeparators: [UInt16]

    package init(keywords: String = "", types: String = "", constants: String = "", builtins: String = "",
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

    @inline(__always) package func isWordStart(_ c: UInt16) -> Bool {
        NoteSyntaxChar.isWordStart(c) || (!wordStartExtras.isEmpty && wordStartExtras.contains(c))
    }

    @inline(__always) package func isWord(_ c: UInt16) -> Bool {
        NoteSyntaxChar.isWord(c) || (!wordExtras.isEmpty && wordExtras.contains(c))
    }
}
