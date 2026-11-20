import Foundation

struct NoteFileSummary: Hashable, Sendable {
    var icon: String?
    var snippet: String

    static let headSize = 16 * 1024
    static let snippetLength = 160

    static func read(_ url: URL, kind: NoteFileKind) -> NoteFileSummary {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return NoteFileSummary(icon: nil, snippet: "") }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: headSize)) ?? Data()
        return make(fromHead: decodedHead(data, kind: kind), kind: kind)
    }

    static func decodedHead(_ data: Data, kind: NoteFileKind) -> String {
        if let contents = NoteFileText.decode(data, kind: kind) { return NoteFileText.normalizedLineEndings(contents.text) }
        var trimmed = data
        for _ in 0..<3 where !trimmed.isEmpty {
            trimmed.removeLast()
            if let contents = NoteFileText.decode(trimmed, kind: kind) { return NoteFileText.normalizedLineEndings(contents.text) }
        }
        return ""
    }

    static func make(fromHead head: String, kind: NoteFileKind) -> NoteFileSummary {
        let lines = head.components(separatedBy: "\n")
        guard kind == .markdown else {
            return NoteFileSummary(icon: nil, snippet: clipped(lines.map(collapsed).filter { !$0.isEmpty }))
        }
        let (icon, bodyStart) = frontMatter(lines)
        var pieces: [String] = []
        var inFence: String?
        var length = 0
        for line in lines[bodyStart...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = inFence {
                if trimmed.hasPrefix(fence) { inFence = nil; continue }
                let text = collapsed(trimmed)
                if !text.isEmpty { pieces.append(text); length += text.count + 1 }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = String(trimmed.prefix(3))
            } else if trimmed.hasPrefix("$$") {
                continue
            } else {
                let text = plainLine(trimmed)
                if !text.isEmpty { pieces.append(text); length += text.count + 1 }
            }
            if length > snippetLength { break }
        }
        return NoteFileSummary(icon: icon, snippet: clipped(pieces))
    }

    static func frontMatter(_ lines: [String]) -> (icon: String?, bodyStart: Int) {
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, 0) }
        var icon: String?
        for index in 1..<lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." { return (icon, index + 1) }
            guard icon == nil, line.hasPrefix("icon:") else { continue }
            let value = unquoted(String(line.dropFirst("icon:".count)).trimmingCharacters(in: .whitespaces))
            if !value.isEmpty { icon = value }
        }
        return (nil, 0)
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else {
            if let hash = value.range(of: " #") { return String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
            return value
        }
        let inner = String(value.dropFirst().dropLast())
        return first == "'" ? inner.replacingOccurrences(of: "''", with: "'") : inner.replacingOccurrences(of: "\\\"", with: "\"")
    }

    static func plainLine(_ line: String) -> String {
        var text = line
        if text.allSatisfy({ "-*_=|:+ ".contains($0) }) || text.hasPrefix(":::") { return "" }
        if text.hasPrefix("|") { text = text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ") }
        var previous = ""
        while previous != text {
            previous = text
            for pattern in [#"^>\s?"#, #"^#{1,6}(\s+|$)"#, #"^[-*+]\s+"#, #"^\d{1,9}[.)]\s+"#, #"^\[[ xX]\]\s+"#] {
                guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
                text.removeSubrange(range)
                text = text.trimmingCharacters(in: .whitespaces)
            }
        }
        text = replacing(text, #"^\[![A-Za-z]+\][+-]?\s*"#, with: "")
        text = replacing(text, #"!\[[^\]]*\]\([^)]*\)"#, with: "")
        text = replacing(text, #"\[([^\]]*)\]\([^)]*\)"#, with: "$1")
        text = replacing(text, #"\[\[([^\]|]*)(\|([^\]]*))?\]\]"#, with: "$1")
        text = replacing(text, #"</?[A-Za-z][^>]*>"#, with: "")
        text = replacing(text, #"(\*\*|~~|==|\*|`)"#, with: "")
        text = replacing(text, #"(?<![\p{L}\p{N}])_+|_+(?![\p{L}\p{N}])"#, with: "")
        text = replacing(text, #"\\([\\`*_{}\[\]()#+\-.!|~<>=$])"#, with: "$1")
        return collapsed(text)
    }

    private static func replacing(_ text: String, _ pattern: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func clipped(_ pieces: [String]) -> String {
        let joined = pieces.joined(separator: " ")
        guard joined.count > snippetLength else { return joined }
        var cut = String(joined.prefix(snippetLength))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > snippetLength / 2 {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }
}
