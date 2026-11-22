import Foundation

package struct NoteCodeLanguage: Hashable, Sendable {
    package let id: String
    package let name: String
    package let aliases: [String]

    init(id: String, name: String, aliases: [String]) {
        self.id = id
        self.name = name
        self.aliases = aliases
    }

    package static let plainText = NoteCodeLanguage(id: "plaintext", name: "Plain Text", aliases: ["text", "txt", "plain", "none"])

    package static let all: [NoteCodeLanguage] = [
        plainText,
        NoteCodeLanguage(id: "bash", name: "Bash", aliases: ["sh", "shell", "zsh", "ksh", "shellscript", "shell-script", "console"]),
        NoteCodeLanguage(id: "c", name: "C", aliases: ["h"]),
        NoteCodeLanguage(id: "csharp", name: "C#", aliases: ["cs", "c#", "dotnet"]),
        NoteCodeLanguage(id: "cpp", name: "C++", aliases: ["c++", "cc", "cxx", "hpp", "hh", "hxx", "h++"]),
        NoteCodeLanguage(id: "css", name: "CSS", aliases: []),
        NoteCodeLanguage(id: "dart", name: "Dart", aliases: ["flutter"]),
        NoteCodeLanguage(id: "diff", name: "Diff", aliases: ["patch", "udiff"]),
        NoteCodeLanguage(id: "dockerfile", name: "Dockerfile", aliases: ["docker", "containerfile"]),
        NoteCodeLanguage(id: "elixir", name: "Elixir", aliases: ["ex", "exs"]),
        NoteCodeLanguage(id: "go", name: "Go", aliases: ["golang"]),
        NoteCodeLanguage(id: "graphql", name: "GraphQL", aliases: ["gql"]),
        NoteCodeLanguage(id: "haskell", name: "Haskell", aliases: ["hs"]),
        NoteCodeLanguage(id: "html", name: "HTML", aliases: ["htm", "xhtml", "vue", "svelte"]),
        NoteCodeLanguage(id: "java", name: "Java", aliases: []),
        NoteCodeLanguage(id: "javascript", name: "JavaScript", aliases: ["js", "mjs", "cjs", "node", "ecmascript"]),
        NoteCodeLanguage(id: "json", name: "JSON", aliases: ["jsonc", "json5", "geojson", "webmanifest"]),
        NoteCodeLanguage(id: "jsx", name: "JSX", aliases: ["react"]),
        NoteCodeLanguage(id: "kotlin", name: "Kotlin", aliases: ["kt", "kts"]),
        NoteCodeLanguage(id: "lua", name: "Lua", aliases: ["luau"]),
        NoteCodeLanguage(id: "makefile", name: "Makefile", aliases: ["make", "mk", "mak", "gnumake"]),
        NoteCodeLanguage(id: "markdown", name: "Markdown", aliases: ["md", "mdown", "mkd", "gfm"]),
        NoteCodeLanguage(id: "mermaid", name: "Mermaid", aliases: ["mmd", "mermaidjs"]),
        NoteCodeLanguage(id: "objectivec", name: "Objective-C", aliases: ["objc", "obj-c", "objective-c", "objectivec", "m", "mm"]),
        NoteCodeLanguage(id: "php", name: "PHP", aliases: ["php8", "phtml"]),
        NoteCodeLanguage(id: "powershell", name: "PowerShell", aliases: ["ps1", "psm1", "pwsh", "posh", "ps"]),
        NoteCodeLanguage(id: "python", name: "Python", aliases: ["py", "py3", "python3", "gyp", "pyi"]),
        NoteCodeLanguage(id: "r", name: "R", aliases: ["rlang", "rscript"]),
        NoteCodeLanguage(id: "ruby", name: "Ruby", aliases: ["rb", "gemfile", "rake", "podfile"]),
        NoteCodeLanguage(id: "rust", name: "Rust", aliases: ["rs"]),
        NoteCodeLanguage(id: "scala", name: "Scala", aliases: ["sc", "sbt"]),
        NoteCodeLanguage(id: "scss", name: "SCSS", aliases: ["sass"]),
        NoteCodeLanguage(id: "sql", name: "SQL", aliases: ["mysql", "postgresql", "postgres", "psql", "sqlite", "plsql", "tsql", "pgsql"]),
        NoteCodeLanguage(id: "swift", name: "Swift", aliases: []),
        NoteCodeLanguage(id: "toml", name: "TOML", aliases: []),
        NoteCodeLanguage(id: "tsx", name: "TSX", aliases: []),
        NoteCodeLanguage(id: "typescript", name: "TypeScript", aliases: ["ts", "mts", "cts"]),
        NoteCodeLanguage(id: "xml", name: "XML", aliases: ["svg", "plist", "xsd", "xsl", "xslt", "rss", "atom", "xaml", "csproj"]),
        NoteCodeLanguage(id: "yaml", name: "YAML", aliases: ["yml"]),
        NoteCodeLanguage(id: "zig", name: "Zig", aliases: []),
    ]

    private static let index: [String: NoteCodeLanguage] = {
        var table: [String: NoteCodeLanguage] = [:]
        for language in all {
            for key in [language.id, language.name] + language.aliases where table[key.lowercased()] == nil {
                table[key.lowercased()] = language
            }
        }
        return table
    }()

    package static func named(_ text: String) -> NoteCodeLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let language = index[trimmed] { return language }
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "{},"))
        guard let first = trimmed.components(separatedBy: separators).first(where: { !$0.isEmpty }) else { return nil }
        var word = Substring(first)
        if word.hasPrefix(".") { word = word.dropFirst() }
        if word.hasPrefix("language-") { word = word.dropFirst("language-".count) }
        return index[String(word)]
    }
}
