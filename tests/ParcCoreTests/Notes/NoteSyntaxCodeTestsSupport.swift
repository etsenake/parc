import Foundation
import Testing
@testable import ParcCore

enum NoteSyntaxCodeTestsSupport {
    struct TokenCase: Sendable, CustomTestStringConvertible {
        let fragment: String
        let kind: NoteSyntaxKind?
        let occurrence: Int

        init(_ fragment: String, _ kind: NoteSyntaxKind?, _ occurrence: Int = 1) {
            self.fragment = fragment
            self.kind = kind
            self.occurrence = occurrence
        }

        var testDescription: String {
            "\(fragment.debugDescription) #\(occurrence) is \(kind?.rawValue ?? "unhighlighted")"
        }
    }

    struct SyntaxProbe {
        let language: String
        let code: String
        let tokens: [NoteSyntaxToken]

        init(_ language: String, _ code: String) {
            self.language = language
            self.code = code
            tokens = NoteSyntaxHighlighter.tokens(in: code, language: language)
        }

        func range(of fragment: String, occurrence: Int) -> Range<Int>? {
            let text = code as NSString
            var searchStart = 0
            var found = NSRange(location: NSNotFound, length: 0)
            for _ in 0..<occurrence {
                found = text.range(of: fragment, options: [], range: NSRange(location: searchStart, length: text.length - searchStart))
                if found.location == NSNotFound { return nil }
                searchStart = found.location + max(1, found.length)
            }
            return found.location..<(found.location + found.length)
        }

        func kind(_ fragment: String, _ occurrence: Int = 1) -> NoteSyntaxKind? {
            guard let target = range(of: fragment, occurrence: occurrence) else { return nil }
            return tokens.first { $0.range.lowerBound <= target.lowerBound && $0.range.upperBound >= target.upperBound }?.kind
        }

        func expect(_ token: TokenCase) {
            let (fragment, kind, occurrence) = (token.fragment, token.kind, token.occurrence)
            let actual = self.kind(fragment, occurrence)
            if actual != kind {
                let dump = tokens.map { token -> String in
                    let piece = (code as NSString).substring(with: NSRange(location: token.range.lowerBound, length: token.range.count))
                    return "\(token.kind.rawValue)=\(piece.debugDescription)"
                }.joined(separator: " ")
                Issue.record("[\(language)] \(fragment.debugDescription)#\(occurrence) expected \(kind?.rawValue ?? "none"), got \(actual?.rawValue ?? "none")\n\(dump)")
            }
        }

        func expectWellFormed() {
            let length = (code as NSString).length
            var previous = 0
            for token in tokens {
                if token.range.lowerBound < previous || token.range.isEmpty || token.range.upperBound > length {
                    Issue.record("[\(language)] malformed token \(token) after \(previous)")
                }
                previous = token.range.upperBound
            }
        }
    }
}
