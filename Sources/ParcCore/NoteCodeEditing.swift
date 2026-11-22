import Foundation

package struct NoteCodeEdit: Hashable {
    package var range: Range<Int>
    package var replacement: String
    package var selection: Range<Int>

    init(range: Range<Int>, replacement: String, selection: Range<Int>) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: replacement)
    }
}

package enum NoteCodeIndent: Hashable {
    case spaces(Int)
    case tab(Int)

    var unit: String {
        switch self {
        case .spaces(let width): return String(repeating: " ", count: width)
        case .tab: return "\t"
        }
    }

    package var width: Int {
        switch self { case .spaces(let width), .tab(let width): return max(1, width) }
    }
}

package enum NoteCodeEditing {
    private static let fourSpaceLanguages: Set<String> = [
        "python", "py", "python3", "swift", "kotlin", "kt", "java", "c", "h", "cpp", "c++", "cc", "cxx", "hpp",
        "objective-c", "objectivec", "objc", "objective-c++", "csharp", "c#", "cs", "rust", "rs", "go", "golang",
        "php", "scala", "dart", "julia", "jl", "powershell", "ps1", "pwsh", "visual basic", "vb", "vb.net", "vbnet",
        "fortran", "perl", "pl", "groovy", "f#", "fsharp", "erlang", "zig", "nim", "pascal", "delphi", "cobol",
        "assembly", "asm", "x86asm", "nasm", "matlab", "solidity", "gdscript", "verilog", "vhdl", "glsl", "hlsl",
        "cuda", "d", "ada", "prolog", "sql", "plsql", "tsql", "mysql", "postgresql", "kusto", "applescript",
    ]
    private static let tabLanguages: Set<String> = ["makefile", "make", "mk", "mak"]
    private static let markupLanguages: Set<String> = [
        "html", "xml", "svg", "xhtml", "vue", "svelte", "jsx", "tsx", "astro", "php", "plist", "markup", "erb", "handlebars",
    ]
    private static let wordOpenerLanguages: Set<String> = [
        "ruby", "rb", "elixir", "ex", "exs", "crystal", "lua", "bash", "sh", "shell", "zsh", "fish", "julia", "jl",
    ]
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr",
    ]
    private static let pairs: [unichar: unichar] = [123: 125, 91: 93, 40: 41]

    package static func normalizedLanguage(_ language: String) -> String {
        language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    package static func indentWidth(forLanguage language: String) -> Int {
        fourSpaceLanguages.contains(normalizedLanguage(language)) ? 4 : 2
    }

    package static func indent(forLanguage language: String, text: String = "") -> NoteCodeIndent {
        let name = normalizedLanguage(language)
        let width = indentWidth(forLanguage: name)
        if tabLanguages.contains(name) { return .tab(4) }
        var tabbed = 0, spaced = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(400) {
            if line.hasPrefix("\t") { tabbed += 1 } else if line.hasPrefix("  ") { spaced += 1 }
        }
        return tabbed > spaced ? .tab(width) : .spaces(width)
    }

    package static func newline(in text: String, selection: Range<Int>, indent: NoteCodeIndent, language: String = "") -> NoteCodeEdit {
        let characters = text as NSString
        let range = clamp(selection, characters.length)
        let lineStart = lineStart(of: range.lowerBound, in: characters)
        let lineEnd = lineEnd(of: range.upperBound, in: characters)
        let before = characters.substring(with: NSRange(location: lineStart, length: range.lowerBound - lineStart))
        let after = characters.substring(with: NSRange(location: range.upperBound, length: lineEnd - range.upperBound))
        let leading = leadingWhitespace(before)
        let trimmedBefore = trimmingTrailingWhitespace(before)
        let afterSkip = (leadingWhitespace(after) as NSString).length
        let rest = (after as NSString).substring(from: afterSkip)
        let name = normalizedLanguage(language)
        var start = range.lowerBound
        if trimmedBefore.isEmpty { start = lineStart }
        let opens = opensBlock(trimmedBefore, language: name)
        var level = leading
        if opens {
            level += indent.unit
        } else if name == "python" || name == "py" || name == "python3", dedentsAfter(trimmedBefore) {
            level = dedented(leading, indent: indent)
        }
        var replacement = "\n" + level
        let caret = start + (replacement as NSString).length
        if opens, closes(trimmedBefore, rest, language: name) {
            replacement += "\n" + leading
        }
        return NoteCodeEdit(range: start..<(range.upperBound + afterSkip), replacement: replacement, selection: caret..<caret)
    }

    package static func tab(in text: String, selection: Range<Int>, indent: NoteCodeIndent) -> NoteCodeEdit {
        let characters = text as NSString
        let range = clamp(selection, characters.length)
        let selected = characters.substring(with: NSRange(location: range.lowerBound, length: range.count))
        let start = lineStart(of: range.lowerBound, in: characters)
        let coversLine = !range.isEmpty && range.lowerBound == start && range.upperBound == lineEnd(of: range.lowerBound, in: characters)
        if selected.contains("\n") || coversLine { return indentLines(in: text, selection: range, indent: indent) }
        let insertion: String
        switch indent {
        case .tab: insertion = "\t"
        case .spaces(let width):
            let column = self.column(of: range.lowerBound, in: characters, tabWidth: indent.width)
            insertion = String(repeating: " ", count: width - column % width)
        }
        let caret = range.lowerBound + (insertion as NSString).length
        return NoteCodeEdit(range: range, replacement: insertion, selection: caret..<caret)
    }

    static func indentLines(in text: String, selection: Range<Int>, indent: NoteCodeIndent) -> NoteCodeEdit {
        let characters = text as NSString
        let range = clamp(selection, characters.length)
        let lines = touchedLines(range, in: characters)
        let unit = indent.unit
        let unitLength = (unit as NSString).length
        var replacement = ""
        var inserted: [Int] = []
        for (index, line) in lines.enumerated() {
            let content = characters.substring(with: NSRange(location: line.lowerBound, length: line.count))
            if index > 0 { replacement += "\n" }
            if content.isEmpty && lines.count > 1 { continue }
            replacement += unit + content
            inserted.append(line.lowerBound)
        }
        func shifted(_ offset: Int) -> Int {
            offset + inserted.filter { range.isEmpty ? $0 <= offset : $0 < offset }.count * unitLength
        }
        let span = lines.first!.lowerBound..<lines.last!.upperBound
        let lower = shifted(range.lowerBound)
        return NoteCodeEdit(range: span, replacement: replacement, selection: lower..<max(lower, shifted(range.upperBound)))
    }

    package static func dedentLines(in text: String, selection: Range<Int>, indent: NoteCodeIndent) -> NoteCodeEdit? {
        let characters = text as NSString
        let range = clamp(selection, characters.length)
        let lines = touchedLines(range, in: characters)
        var replacement = ""
        var removals: [Range<Int>] = []
        for (index, line) in lines.enumerated() {
            let content = characters.substring(with: NSRange(location: line.lowerBound, length: line.count)) as NSString
            var removed = 0
            if content.length > 0, content.character(at: 0) == 9 {
                removed = 1
            } else {
                while removed < indent.width, removed < content.length, content.character(at: removed) == 32 { removed += 1 }
            }
            if index > 0 { replacement += "\n" }
            replacement += content.substring(from: removed)
            if removed > 0 { removals.append(line.lowerBound..<(line.lowerBound + removed)) }
        }
        guard !removals.isEmpty else { return nil }
        func shifted(_ offset: Int) -> Int {
            offset - removals.reduce(0) { $0 + min($1.count, max(0, offset - $1.lowerBound)) }
        }
        let span = lines.first!.lowerBound..<lines.last!.upperBound
        let lower = shifted(range.lowerBound)
        return NoteCodeEdit(range: span, replacement: replacement, selection: lower..<max(lower, shifted(range.upperBound)))
    }

    package static func closingBracket(_ character: String, in text: String, selection: Range<Int>, indent: NoteCodeIndent) -> NoteCodeEdit? {
        guard ["}", "]", ")"].contains(character) else { return nil }
        let characters = text as NSString
        let range = clamp(selection, characters.length)
        guard range.isEmpty else { return nil }
        let start = lineStart(of: range.lowerBound, in: characters)
        let before = characters.substring(with: NSRange(location: start, length: range.lowerBound - start))
        guard !before.isEmpty, leadingWhitespace(before) == before else { return nil }
        let level = dedented(before, indent: indent)
        guard level != before else { return nil }
        let replacement = level + character
        let caret = start + (replacement as NSString).length
        return NoteCodeEdit(range: start..<range.lowerBound, replacement: replacement, selection: caret..<caret)
    }

    package static func deleteBackward(in text: String, selection: Range<Int>, indent: NoteCodeIndent) -> NoteCodeEdit? {
        guard case .spaces(let width) = indent else { return nil }
        let characters = text as NSString
        let range = clamp(selection, characters.length)
        guard range.isEmpty, range.lowerBound > 0 else { return nil }
        let start = lineStart(of: range.lowerBound, in: characters)
        let before = characters.substring(with: NSRange(location: start, length: range.lowerBound - start))
        guard !before.isEmpty, before.allSatisfy({ $0 == " " }) else { return nil }
        let column = before.count
        let count = min(column, column % width == 0 ? width : column % width)
        guard count > 1 else { return nil }
        let lower = range.lowerBound - count
        return NoteCodeEdit(range: lower..<range.lowerBound, replacement: "", selection: lower..<lower)
    }

    package static func exitsOnReturn(_ text: String, selection: Range<Int>) -> Bool {
        let characters = text as NSString
        guard selection.isEmpty, selection.lowerBound == characters.length else { return false }
        let start = lineStart(of: characters.length, in: characters)
        guard start > 0 else { return false }
        let last = characters.substring(from: start)
        guard leadingWhitespace(last) == last else { return false }
        if last.isEmpty { return true }
        let previousStart = lineStart(of: start - 1, in: characters)
        let previous = characters.substring(with: NSRange(location: previousStart, length: start - 1 - previousStart))
        return leadingWhitespace(previous) == previous
    }

    package static func trimmedForExit(_ text: String) -> String {
        let characters = text as NSString
        var end = characters.length
        while end > 0, isWhitespaceOrNewline(characters.character(at: end - 1)) { end -= 1 }
        guard end > 0 else { return "" }
        return characters.substring(to: lineEnd(of: end, in: characters))
    }

    static func lineRange(at offset: Int, in text: String) -> Range<Int> {
        let characters = text as NSString
        let clamped = min(max(0, offset), characters.length)
        return lineStart(of: clamped, in: characters)..<lineEnd(of: clamped, in: characters)
    }

    private static func opensBlock(_ trimmed: String, language: String) -> Bool {
        let characters = trimmed as NSString
        guard characters.length > 0 else { return false }
        let last = characters.character(at: characters.length - 1)
        if pairs[last] != nil { return true }
        if last == 58 {
            return characters.length < 2 || characters.character(at: characters.length - 2) != 58
        }
        if last == 62, markupLanguages.contains(language) { return opensTag(trimmed) }
        if wordOpenerLanguages.contains(language) {
            let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let word = words.last, ["do", "then", "else", "begin"].contains(String(word)) || word.hasSuffix("|") && words.contains("do") {
                return true
            }
        }
        return false
    }

    private static func opensTag(_ trimmed: String) -> Bool {
        guard let open = trimmed.range(of: "<", options: .backwards) else { return false }
        let tag = trimmed[open.lowerBound...]
        if tag.hasPrefix("</") || tag.hasPrefix("<!") || tag.hasPrefix("<?") || tag.hasSuffix("/>") { return false }
        let name = tag.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == ":" }.lowercased()
        return !name.isEmpty && !voidElements.contains(name)
    }

    private static func closes(_ trimmedBefore: String, _ rest: String, language: String) -> Bool {
        let before = trimmedBefore as NSString, after = rest as NSString
        guard before.length > 0, after.length > 0 else { return false }
        let last = before.character(at: before.length - 1)
        if let closer = pairs[last] { return after.character(at: 0) == closer }
        if last == 62, markupLanguages.contains(language) { return rest.hasPrefix("</") }
        return false
    }

    private static func dedentsAfter(_ trimmed: String) -> Bool {
        let statement = trimmed.trimmingCharacters(in: .whitespaces)
        let word = statement.prefix { $0.isLetter }
        return ["return", "pass", "break", "continue", "raise"].contains(String(word))
            && (statement.count == word.count || statement.dropFirst(word.count).first == " ")
    }

    private static func dedented(_ whitespace: String, indent: NoteCodeIndent) -> String {
        let characters = whitespace as NSString
        guard characters.length > 0 else { return whitespace }
        if characters.character(at: characters.length - 1) == 9 { return characters.substring(to: characters.length - 1) }
        var trailing = 0
        while trailing < characters.length, characters.character(at: characters.length - 1 - trailing) == 32 { trailing += 1 }
        let width = indent.width
        let column = whitespace.reduce(0) { $1 == "\t" ? ($0 / width + 1) * width : $0 + 1 }
        let remove = min(trailing, column % width == 0 ? width : column % width)
        return characters.substring(to: characters.length - remove)
    }

    private static func touchedLines(_ range: Range<Int>, in characters: NSString) -> [Range<Int>] {
        var anchor = range.upperBound
        if !range.isEmpty, characters.character(at: range.upperBound - 1) == 10 { anchor = range.upperBound - 1 }
        let last = lineStart(of: anchor, in: characters)
        var lines: [Range<Int>] = []
        var start = lineStart(of: range.lowerBound, in: characters)
        while true {
            let end = lineEnd(of: start, in: characters)
            lines.append(start..<end)
            if start >= last || end >= characters.length { break }
            start = end + 1
        }
        return lines
    }

    private static func column(of offset: Int, in characters: NSString, tabWidth: Int) -> Int {
        var column = 0
        var index = lineStart(of: offset, in: characters)
        while index < offset {
            column = characters.character(at: index) == 9 ? (column / tabWidth + 1) * tabWidth : column + 1
            index += 1
        }
        return column
    }

    private static func lineStart(of offset: Int, in characters: NSString) -> Int {
        var index = min(max(0, offset), characters.length)
        while index > 0, characters.character(at: index - 1) != 10 { index -= 1 }
        return index
    }

    private static func lineEnd(of offset: Int, in characters: NSString) -> Int {
        var index = min(max(0, offset), characters.length)
        while index < characters.length, characters.character(at: index) != 10 { index += 1 }
        return index
    }

    private static func leadingWhitespace(_ value: String) -> String {
        String(value.prefix { $0 == " " || $0 == "\t" })
    }

    private static func trimmingTrailingWhitespace(_ value: String) -> String {
        var result = Substring(value)
        while let last = result.last, last == " " || last == "\t" { result = result.dropLast() }
        return String(result)
    }

    private static func isWhitespaceOrNewline(_ character: unichar) -> Bool {
        character == 32 || character == 9 || character == 10 || character == 13
    }

    private static func clamp(_ range: Range<Int>, _ length: Int) -> Range<Int> {
        let lower = min(max(0, range.lowerBound), length)
        return lower..<min(max(lower, range.upperBound), length)
    }
}
