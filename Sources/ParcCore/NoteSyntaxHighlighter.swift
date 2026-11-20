import Foundation

enum NoteSyntaxKind: String, CaseIterable, Hashable, Sendable {
    case keyword, type, string, number, comment, function, property, operatorSymbol, punctuation, tag, attribute,
         variable, constant, regex, builtin, inserted, deleted, heading, emphasis, strong, link, meta, escape
}

struct NoteSyntaxToken: Hashable, Sendable {
    let range: Range<Int>
    let kind: NoteSyntaxKind
}

enum NoteSyntaxHighlighter {
    static func tokens(in code: String, language: String) -> [NoteSyntaxToken] {
        guard let language = NoteCodeLanguage.named(language) else { return [] }
        return tokens(in: code, language: language)
    }

    static func tokens(in code: String, language: NoteCodeLanguage) -> [NoteSyntaxToken] {
        guard !code.isEmpty, let lexer = NoteSyntaxLexer.lexer(for: language.id) else { return [] }
        var scanner = NoteSyntaxScanner(code)
        scanner.run(lexer)
        return scanner.tokens
    }
}

enum NoteSyntaxLexer: Sendable {
    case code(NoteSyntaxGrammar)
    case html, xml, css, scss, markdown, yaml, toml, diff, dockerfile, makefile, php

    static func lexer(for id: String) -> NoteSyntaxLexer? {
        switch id {
        case "html": return .html
        case "xml": return .xml
        case "css": return .css
        case "scss": return .scss
        case "markdown": return .markdown
        case "yaml": return .yaml
        case "toml": return .toml
        case "diff": return .diff
        case "dockerfile": return .dockerfile
        case "makefile": return .makefile
        case "php": return .php
        default: return NoteSyntaxGrammars.grammar(for: id).map { .code($0) }
        }
    }
}
