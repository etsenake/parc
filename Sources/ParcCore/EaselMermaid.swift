import Foundation

enum EaselMermaidDirection: String, Equatable, CaseIterable {
    case down, up, right, left

    init?(keyword: String) {
        switch keyword.trimmingCharacters(in: .whitespaces).uppercased() {
        case "TB", "TD", "V": self = .down
        case "BT", "^": self = .up
        case "LR", ">": self = .right
        case "RL", "<": self = .left
        default: return nil
        }
    }

    var isVertical: Bool { self == .down || self == .up }
}

enum EaselMermaidShape: String, Equatable, CaseIterable {
    case rectangle, rounded, stadium, subroutine, cylinder, circle, doubleCircle, asymmetric, diamond, hexagon
    case leanRight, leanLeft, trapezoid, invertedTrapezoid, ellipse, document, documents, card, horizontalCylinder
    case manualInput, internalStorage, triangle, flippedTriangle, crossedCircle, text, entity

    init(mermaidName raw: String) {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "rounded", "event", "delay", "half-rounded-rectangle": self = .rounded
        case "stadium", "pill", "terminal": self = .stadium
        case "fr-rect", "subproc", "subprocess", "subroutine", "framed-rectangle", "lin-rect", "lined-rectangle",
             "lin-proc", "lined-process", "shaded-process": self = .subroutine
        case "cyl", "db", "database", "cylinder", "lin-cyl", "disk", "lined-cylinder": self = .cylinder
        case "circle", "circ", "sm-circ", "start", "small-circle", "f-circ", "junction", "filled-circle": self = .circle
        case "dbl-circ", "double-circle", "fr-circ", "stop", "framed-circle": self = .doubleCircle
        case "odd", "flag", "paper-tape": self = .asymmetric
        case "diam", "decision", "diamond", "question": self = .diamond
        case "hex", "hexagon", "prepare": self = .hexagon
        case "lean-r", "lean-right", "in-out": self = .leanRight
        case "lean-l", "lean-left", "out-in": self = .leanLeft
        case "trap-b", "trapezoid-bottom", "priority", "trapezoid": self = .trapezoid
        case "trap-t", "trapezoid-top", "manual", "inv-trapezoid": self = .invertedTrapezoid
        case "doc", "document", "lin-doc", "lined-document", "tag-doc", "tagged-document": self = .document
        case "docs", "documents", "st-doc", "stacked-document", "processes", "procs", "stacked-rectangle", "st-rect":
            self = .documents
        case "notch-rect", "card", "notched-rectangle": self = .card
        case "h-cyl", "das", "horizontal-cylinder", "bow-rect", "stored-data", "bow-tie-rectangle": self = .horizontalCylinder
        case "sl-rect", "manual-input", "sloped-rectangle": self = .manualInput
        case "win-pane", "internal-storage", "window-pane": self = .internalStorage
        case "tri", "extract", "triangle": self = .triangle
        case "flip-tri", "manual-file", "flipped-triangle": self = .flippedTriangle
        case "cross-circ", "summary", "crossed-circle": self = .crossedCircle
        case "text": self = .text
        default: self = .rectangle
        }
    }
}

enum EaselMermaidHead: String, Equatable, CaseIterable {
    case none, arrow, circle, cross, zeroOrOne, exactlyOne, zeroOrMore, oneOrMore
}

enum EaselMermaidLine: String, Equatable, CaseIterable {
    case solid, dotted, thick, invisible
}

struct EaselMermaidStyle: Equatable {
    var fill: String?
    var stroke: String?
    var strokeWidth: Double?
    var dashed: Bool?

    func merged(with other: EaselMermaidStyle) -> EaselMermaidStyle {
        EaselMermaidStyle(fill: other.fill ?? fill, stroke: other.stroke ?? stroke,
                          strokeWidth: other.strokeWidth ?? strokeWidth, dashed: other.dashed ?? dashed)
    }
}

struct EaselMermaidAttribute: Equatable {
    var type: String
    var name: String
    var keys: [String] = []
    var comment = ""

    var line: String {
        var value = type + " " + name
        if !keys.isEmpty { value += " " + keys.joined(separator: ", ") }
        if !comment.isEmpty { value += " · " + comment }
        return value
    }
}

struct EaselMermaidNode: Equatable {
    var id: String
    var label: String
    var shape: EaselMermaidShape = .rectangle
    var group: String?
    var style = EaselMermaidStyle()
    var attributes: [EaselMermaidAttribute] = []
}

struct EaselMermaidEdge: Equatable {
    var from: String
    var to: String
    var label = ""
    var line: EaselMermaidLine = .solid
    var startHead: EaselMermaidHead = .none
    var endHead: EaselMermaidHead = .arrow
    var length = 1
    var style = EaselMermaidStyle()
}

struct EaselMermaidGroup: Equatable {
    var id: String
    var title: String
    var parent: String?
    var direction: EaselMermaidDirection?
    var style = EaselMermaidStyle()
}

struct EaselMermaidDiagram: Equatable {
    enum Kind: String, Equatable { case flowchart, entityRelationship }

    var kind: Kind
    var direction: EaselMermaidDirection = .down
    var nodes: [EaselMermaidNode] = []
    var edges: [EaselMermaidEdge] = []
    var groups: [EaselMermaidGroup] = []

    func node(_ id: String) -> EaselMermaidNode? { nodes.first { $0.id == id } }
    func group(_ id: String) -> EaselMermaidGroup? { groups.first { $0.id == id } }

    var summary: String {
        func count(_ value: Int, _ one: String, _ many: String) -> String { "\(value) \(value == 1 ? one : many)" }
        let arrows = edges.filter { $0.line != .invisible }.count
        var parts = [count(nodes.count, kind == .entityRelationship ? "entity" : "shape",
                           kind == .entityRelationship ? "entities" : "shapes")]
        if arrows > 0 { parts.append(count(arrows, kind == .entityRelationship ? "relationship" : "arrow",
                                           kind == .entityRelationship ? "relationships" : "arrows")) }
        if !groups.isEmpty { parts.append(count(groups.count, "section", "sections")) }
        return (kind == .entityRelationship ? "ER diagram" : "Flowchart") + " · " + parts.joined(separator: ", ")
    }
}

enum EaselMermaidRefusal: Error, Equatable {
    case notMermaid
    case unsupported(String)
    case empty
    case syntax(line: Int, detail: String)
    case tooLarge

    var message: String {
        switch self {
        case .notMermaid: return "Start with flowchart, graph or erDiagram and Parc draws the rest."
        case .unsupported(let name): return "\(name) can't become Easel objects. Flowcharts and ER diagrams can."
        case .empty: return "There's nothing to draw yet. Add a shape or two."
        case .syntax(let line, let detail): return line > 0 ? "Line \(line): \(detail)." : detail.prefix(1).uppercased() + detail.dropFirst() + "."
        case .tooLarge:
            return "That's a big one. Easels draw diagrams of up to \(EaselMermaid.maximumNodes) shapes and \(EaselMermaid.maximumEdges.formatted()) arrows."
        }
    }
}

extension EaselMermaidRefusal: LocalizedError {
    var errorDescription: String? { message }
}

enum EaselMermaid {
    static let maximumNodes = 500
    static let maximumEdges = 1000
    static let maximumGroups = 200
    static let maximumAttributes = 100
    static let maximumLength = 6
    static let maximumSourceBytes = 400_000

    static func canParse(_ text: String) -> Bool {
        if case .success = parse(text) { return true }
        return false
    }

    static func parse(_ text: String) -> Result<EaselMermaidDiagram, EaselMermaidRefusal> {
        let probe = text.utf8.count > maximumSourceBytes ? String(text.prefix(4096)) : text
        guard let lines = EaselMermaidSource.lines(probe),
              let header = lines.firstIndex(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return .failure(.notMermaid)
        }
        let keyword = EaselMermaidSource.firstWord(lines[header].text.trimmingCharacters(in: .whitespaces))
        let kind: EaselMermaidDiagram.Kind
        switch keyword {
        case "flowchart", "graph", "flowchart-elk": kind = .flowchart
        case "erDiagram": kind = .entityRelationship
        default: return .failure(unsupportedName(keyword).map(EaselMermaidRefusal.unsupported) ?? .notMermaid)
        }
        guard probe.utf8.count == text.utf8.count else { return .failure(.tooLarge) }
        do {
            switch kind {
            case .flowchart:
                var parser = EaselMermaidFlowchartParser()
                return .success(try parser.parse(lines))
            case .entityRelationship:
                var parser = EaselMermaidEntityParser()
                return .success(try parser.parse(lines, header: header))
            }
        } catch let refusal as EaselMermaidRefusal {
            return .failure(refusal)
        } catch {
            return .failure(.notMermaid)
        }
    }

    static func unsupportedName(_ keyword: String) -> String? {
        switch keyword {
        case "sequenceDiagram": return "Sequence diagrams"
        case "classDiagram", "classDiagram-v2": return "Class diagrams"
        case "stateDiagram", "stateDiagram-v2": return "State diagrams"
        case "gantt": return "Gantt charts"
        case "pie": return "Pie charts"
        case "journey": return "User journeys"
        case "gitGraph": return "Git graphs"
        case "mindmap": return "Mind maps"
        case "timeline": return "Timelines"
        case "quadrantChart": return "Quadrant charts"
        case "requirementDiagram": return "Requirement diagrams"
        case "C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment": return "C4 diagrams"
        case "sankey", "sankey-beta": return "Sankey diagrams"
        case "xychart", "xychart-beta": return "XY charts"
        case "block", "block-beta": return "Block diagrams"
        case "packet", "packet-beta": return "Packet diagrams"
        case "kanban": return "Kanban boards"
        case "architecture", "architecture-beta": return "Architecture diagrams"
        case "radar", "radar-beta": return "Radar charts"
        case "treemap", "treemap-beta": return "Treemaps"
        case "zenuml": return "ZenUML diagrams"
        default: return nil
        }
    }
}

enum EaselMermaidSource {
    struct Line: Equatable {
        var number: Int
        var text: String
    }

    static func lines(_ text: String) -> [Line]? {
        let normalized = text.unicodeScalars.contains("\r")
            ? text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") : text
        var lines = normalized.components(separatedBy: "\n").enumerated().map { Line(number: $0.offset + 1, text: $0.element) }
        let blank: (Line) -> Bool = { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        if let first = lines.firstIndex(where: { !blank($0) }), let fence = fence(lines[first].text) {
            guard fence.info.isEmpty || fence.info == "mermaid" else { return nil }
            lines[first].text = ""
            if let last = lines.lastIndex(where: { !blank($0) }), last > first {
                let closing = lines[last].text.trimmingCharacters(in: .whitespaces)
                if closing.count >= fence.count, closing.allSatisfy({ $0 == fence.marker }) { lines[last].text = "" }
            }
        }
        if let first = lines.firstIndex(where: { !blank($0) }), lines[first].text.trimmingCharacters(in: .whitespaces) == "---" {
            guard let close = lines[(first + 1)...].firstIndex(where: { $0.text.trimmingCharacters(in: .whitespaces) == "---" }) else { return nil }
            for index in first...close { lines[index].text = "" }
        }
        var directive = false
        for index in lines.indices {
            let trimmed = lines[index].text.trimmingCharacters(in: .whitespaces)
            if directive {
                if trimmed.contains("}%%") { directive = false }
                lines[index].text = ""
            } else if trimmed.hasPrefix("%%{") {
                directive = !trimmed.contains("}%%")
                lines[index].text = ""
            } else if trimmed.hasPrefix("%%") {
                lines[index].text = ""
            }
        }
        return lines
    }

    private static func fence(_ line: String) -> (marker: Character, count: Int, info: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix { $0 == marker }.count
        guard count >= 3 else { return nil }
        let info = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
        return (marker, count, String(info.prefix { !$0.isWhitespace && $0 != "{" }).lowercased())
    }

    static func firstWord(_ text: String) -> String {
        String(text.prefix { !$0.isWhitespace && $0 != ";" && $0 != ":" })
    }

    static func statements(_ lines: [Line]) -> [Line] {
        var result: [Line] = []
        var buffer = "", start = 0, depth = 0, quoted = false
        func flush() {
            if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(Line(number: start, text: buffer)) }
            buffer = ""
        }
        func append(_ character: Character, line: Int) {
            if buffer.isEmpty {
                if character.isWhitespace { return }
                start = line
            }
            buffer.append(character)
        }
        for line in lines {
            if !quoted { depth = 0 }
            let characters = Array(line.text)
            var index = 0
            while index < characters.count {
                let character = characters[index]
                if quoted {
                    append(character, line: line.number)
                    if character == "\"" { quoted = false }
                } else if character == "%", depth == 0, index + 1 < characters.count, characters[index + 1] == "%" {
                    break
                } else {
                    switch character {
                    case "\"": quoted = true; append(character, line: line.number)
                    case "[", "(", "{": depth += 1; append(character, line: line.number)
                    case "]", ")", "}": depth = max(0, depth - 1); append(character, line: line.number)
                    case ";" where depth == 0: flush()
                    default: append(character, line: line.number)
                    }
                }
                index += 1
            }
            if quoted { buffer.append("\n") } else { flush() }
        }
        flush()
        return result
    }

    static func strippingComment(_ text: String) -> String {
        var quoted = false, previous: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" { quoted.toggle() }
            if !quoted, character == "%", previous == "%" { return String(text[..<text.index(before: index)]) }
            previous = character
            index = text.index(after: index)
        }
        return text
    }
}

struct EaselMermaidScanner {
    let characters: [Character]
    var index = 0

    init(_ text: String) { characters = Array(text) }

    var atEnd: Bool { index >= characters.count }
    var rest: String { index < characters.count ? String(characters[index...]) : "" }

    func peek(_ offset: Int = 0) -> Character? {
        let position = index + offset
        return position >= 0 && position < characters.count ? characters[position] : nil
    }

    mutating func advance(_ count: Int = 1) { index = min(characters.count, index + max(0, count)) }

    @discardableResult
    mutating func skipSpaces() -> Bool {
        let start = index
        while let character = peek(), character.isWhitespace { index += 1 }
        return index > start
    }

    func matches(_ text: String, at offset: Int = 0) -> Bool {
        var position = index + offset
        for character in text {
            guard position < characters.count, characters[position] == character else { return false }
            position += 1
        }
        return true
    }

    func run(of character: Character, from offset: Int = 0) -> Int {
        var count = 0
        while peek(offset + count) == character { count += 1 }
        return count
    }

    mutating func take(_ character: Character) -> Int {
        let count = run(of: character)
        advance(count)
        return count
    }

    static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    mutating func readIdentifier() -> String? {
        var result = ""
        while let character = peek() {
            if Self.isNameCharacter(character) {
                result.append(character); advance()
            } else if (character == "-" || character == "."), !result.isEmpty, let next = peek(1), Self.isNameCharacter(next) {
                result.append(character); advance()
            } else {
                break
            }
        }
        return result.isEmpty ? nil : result
    }

    mutating func readQuoted() -> String? {
        guard peek() == "\"" else { return nil }
        let start = index
        advance()
        var value = ""
        while let character = peek(), character != "\"" { value.append(character); advance() }
        guard peek() == "\"" else { index = start; return nil }
        advance()
        return value
    }

    mutating func readLabel(closers: [String]) -> (text: String, closer: String)? {
        let family = closers.first?.last ?? "]"
        let open: Character = family == ")" ? "(" : family == "}" ? "{" : "["
        let start = index
        skipSpaces()
        var collected = ""
        if let quoted = readQuoted() {
            let afterQuote = index
            skipSpaces()
            if let closer = closers.first(where: { matches($0) }) {
                advance(closer.count)
                return ("\"" + quoted + "\"", closer)
            }
            index = afterQuote
            collected = quoted
        }
        var depth = 0
        while !atEnd {
            if depth == 0, let closer = closers.first(where: { matches($0) }) {
                advance(closer.count)
                return (collected, closer)
            }
            let character = characters[index]
            if character == open { depth += 1 } else if character == family { if depth == 0 { break }; depth -= 1 }
            collected.append(character)
            advance()
        }
        index = start
        return nil
    }

    mutating func readUntil(_ terminator: Character) -> String? {
        let start = index
        var value = "", quoted = false
        while let character = peek() {
            if character == "\"" { quoted.toggle() }
            if character == terminator, !quoted { advance(); return value }
            value.append(character); advance()
        }
        index = start
        return nil
    }
}

enum EaselMermaidText {
    private static let entityNames: [String: String] = [
        "quot": "\"", "amp": "&", "lt": "<", "gt": ">", "nbsp": " ", "apos": "'", "hellip": "…",
        "mdash": "—", "ndash": "–", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔",
    ]

    private static func expression(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let lineBreak = expression("<br\\s*/?>")
    private static let tag = expression("</?[A-Za-z][A-Za-z0-9]*(\\s[^<>]*)?/?>")
    private static let icon = expression("\\bfa[bsrld]?:fa-[a-z0-9-]+\\s*")
    private static let entity = expression("(?:#|&#?)(x[0-9a-f]{1,6}|[0-9]{1,7}|[a-z]{2,8});")
    private static let markdown: [NSRegularExpression] = [
        "\\*\\*(.+?)\\*\\*", "__(.+?)__", "~~(.+?)~~",
        "(?<![A-Za-z0-9*])\\*(?!\\s)(.+?)(?<!\\s)\\*(?![A-Za-z0-9*])",
        "(?<![A-Za-z0-9_])_(?!\\s)(.+?)(?<!\\s)_(?![A-Za-z0-9_])",
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static let maximumLength = 2000

    static func clean(_ raw: String) -> String {
        var text = String(raw.prefix(maximumLength * 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var isMarkdown = false
        if text.count >= 2, text.hasPrefix("`"), text.hasSuffix("`") {
            text = String(text.dropFirst().dropLast())
            isMarkdown = true
        }
        text = replacing(lineBreak, in: text, with: "\n")
        text = replacing(tag, in: text, with: "")
        text = replacing(icon, in: text, with: "")
        text = decodingEntities(text)
        if isMarkdown {
            for pattern in markdown { text = replacing(pattern, in: text, with: "$1") }
        }
        var lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let joined = lines.joined(separator: "\n")
        return joined.count > maximumLength ? String(joined.prefix(maximumLength)) : joined
    }

    private static func replacing(_ expression: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let expression, !text.isEmpty else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func decodingEntities(_ text: String) -> String {
        guard let entity, text.contains(";") else { return text }
        let source = text as NSString
        var result = "", cursor = 0
        for match in entity.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let name = source.substring(with: match.range(at: 1)).lowercased()
            let scalar: Unicode.Scalar?
            if name.hasPrefix("x"), let value = UInt32(name.dropFirst(), radix: 16) { scalar = Unicode.Scalar(value) }
            else if let value = UInt32(name) { scalar = Unicode.Scalar(value) }
            else { scalar = nil }
            if let scalar, scalar.value >= 32 { result.unicodeScalars.append(scalar) }
            else if let named = entityNames[name] { result += named }
            else { result += source.substring(with: match.range) }
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    static func properties(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        var parts: [String] = [], current = "", quoted = false
        for character in body {
            if character == "\"" { quoted.toggle() }
            if character == ",", !quoted { parts.append(current); current = "" } else { current.append(character) }
        }
        parts.append(current)
        for part in parts {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let key = part[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }
}

enum EaselMermaidColor {
    private static let named: [String: UInt32] = [
        "black": 0x000000, "white": 0xFFFFFF, "gray": 0x808080, "grey": 0x808080, "silver": 0xC0C0C0,
        "lightgray": 0xD3D3D3, "lightgrey": 0xD3D3D3, "darkgray": 0xA9A9A9, "darkgrey": 0xA9A9A9, "whitesmoke": 0xF5F5F5,
        "red": 0xFF0000, "darkred": 0x8B0000, "crimson": 0xDC143C, "maroon": 0x800000, "tomato": 0xFF6347,
        "salmon": 0xFA8072, "coral": 0xFF7F50, "orange": 0xFFA500, "darkorange": 0xFF8C00, "gold": 0xFFD700,
        "yellow": 0xFFFF00, "khaki": 0xF0E68C, "olive": 0x808000, "lime": 0x00FF00, "green": 0x008000,
        "darkgreen": 0x006400, "lightgreen": 0x90EE90, "teal": 0x008080, "turquoise": 0x40E0D0, "cyan": 0x00FFFF,
        "aqua": 0x00FFFF, "blue": 0x0000FF, "navy": 0x000080, "darkblue": 0x00008B, "lightblue": 0xADD8E6,
        "skyblue": 0x87CEEB, "steelblue": 0x4682B4, "indigo": 0x4B0082, "purple": 0x800080, "violet": 0xEE82EE,
        "orchid": 0xDA70D6, "lavender": 0xE6E6FA, "magenta": 0xFF00FF, "fuchsia": 0xFF00FF, "pink": 0xFFC0CB,
        "hotpink": 0xFF69B4, "brown": 0xA52A2A, "chocolate": 0xD2691E, "tan": 0xD2B48C, "beige": 0xF5F5DC,
        "ivory": 0xFFFFF0,
    ]

    static func rgb(_ raw: String) -> (red: Double, green: Double, blue: Double)? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") {
            var digits = String(value.dropFirst())
            guard digits.allSatisfy(\.isHexDigit) else { return nil }
            if digits.count == 3 || digits.count == 4 { digits = String(digits.prefix(3).flatMap { [$0, $0] }) }
            guard digits.count == 6 || digits.count == 8, let number = UInt32(digits.prefix(6), radix: 16) else { return nil }
            return components(number)
        }
        if value.hasPrefix("rgb"), let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"), open < close {
            let numbers = value[value.index(after: open)..<close].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")) }
            guard numbers.count >= 3 else { return nil }
            return (min(1, max(0, numbers[0] / 255)), min(1, max(0, numbers[1] / 255)), min(1, max(0, numbers[2] / 255)))
        }
        return named[value].map(components)
    }

    private static func components(_ number: UInt32) -> (red: Double, green: Double, blue: Double) {
        (Double(number >> 16 & 0xFF) / 255, Double(number >> 8 & 0xFF) / 255, Double(number & 0xFF) / 255)
    }

    static func palette(_ raw: String, role: EaselColorRole) -> String? {
        guard let color = rgb(raw) else { return nil }
        let high = max(color.red, color.green, color.blue), low = min(color.red, color.green, color.blue)
        let lightness = (high + low) / 2, chroma = high - low
        let saturation = chroma == 0 ? 0 : chroma / (1 - abs(2 * lightness - 1))
        if saturation < 0.15 || chroma < 0.08 {
            switch role {
            case .ink: return lightness > 0.62 ? EaselPalette.hex(.note(.gray), role: .ink) : EaselPalette.automaticInk
            case .fill, .sticky: return lightness > 0.86 ? EaselPalette.neutralLight : EaselPalette.hex(.note(.gray), role: role)
            case .highlight: return EaselPalette.hex(.note(.gray), role: .highlight)
            }
        }
        var hue: Double
        if high == color.red { hue = (color.green - color.blue) / chroma }
        else if high == color.green { hue = (color.blue - color.red) / chroma + 2 }
        else { hue = (color.red - color.green) / chroma + 4 }
        hue = (hue * 60).truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        if (hue >= 8 && hue <= 48 && lightness < 0.4) || (hue >= 18 && hue <= 48 && saturation < 0.45 && lightness < 0.8) {
            return EaselPalette.hex(.note(.brown), role: role)
        }
        let anchors: [(NoteColor, Double)] = [(.red, 0), (.orange, 30), (.yellow, 55), (.green, 135), (.blue, 212),
                                              (.purple, 272), (.pink, 322), (.red, 360)]
        let nearest = anchors.min { abs($0.1 - hue) < abs($1.1 - hue) }?.0 ?? .blue
        return EaselPalette.hex(.note(nearest), role: role)
    }

    static func style(_ declarations: String, strokeRole: EaselColorRole = .ink) -> EaselMermaidStyle {
        var style = EaselMermaidStyle()
        var parts: [String] = [], current = "", depth = 0
        for character in declarations {
            if character == "(" { depth += 1 } else if character == ")" { depth = max(0, depth - 1) }
            if character == ",", depth == 0 { parts.append(current); current = "" } else { current.append(character) }
        }
        parts.append(current)
        for part in parts {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let key = part[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
            switch key {
            case "fill", "background", "background-color": style.fill = palette(value, role: .fill) ?? style.fill
            case "stroke", "border-color": style.stroke = palette(value, role: strokeRole) ?? style.stroke
            case "stroke-width", "border-width":
                if let width = Double(value.lowercased().replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces)),
                   width.isFinite {
                    style.strokeWidth = min(EaselPaintRules.maximumWidth, max(0, width))
                }
            case "stroke-dasharray":
                let trimmed = value.lowercased()
                style.dashed = !(trimmed.isEmpty || trimmed == "0" || trimmed == "none")
            default: break
            }
        }
        return style
    }
}

private func syntax(_ line: Int, _ detail: String) -> EaselMermaidRefusal { .syntax(line: line, detail: detail) }

private struct EaselMermaidLink {
    var line: EaselMermaidLine
    var length: Int
    var end: EaselMermaidHead
    var start: EaselMermaidHead = .none
    var label = ""
}

struct EaselMermaidFlowchartParser {
    private var diagram = EaselMermaidDiagram(kind: .flowchart)
    private var nodeIndex: [String: Int] = [:]
    private var explicitNodes: Set<String> = []
    private var groupIndex: [String: Int] = [:]
    private var stack: [(id: String, members: [String])] = []
    private var classes: [String: EaselMermaidStyle] = [:]
    private var nodeClasses: [String: [String]] = [:]
    private var styles: [String: EaselMermaidStyle] = [:]
    private var linkStyles: [(indices: [Int]?, style: EaselMermaidStyle)] = []
    private var directionGiven = false
    private var skippingBlock = false
    private var counter = 0

    private static let openers: [(open: String, closers: [String], shapes: [EaselMermaidShape])] = [
        ("(((", [")))"], [.doubleCircle]),
        ("((", ["))"], [.circle]),
        ("(-", ["-)"], [.ellipse]),
        ("([", ["])"], [.stadium]),
        ("(", [")"], [.rounded]),
        ("[[", ["]]"], [.subroutine]),
        ("[(", [")]"], [.cylinder]),
        ("[/", ["/]", "\\]"], [.leanRight, .trapezoid]),
        ("[\\", ["\\]", "/]"], [.leanLeft, .invertedTrapezoid]),
        ("[", ["]"], [.rectangle]),
        ("{{", ["}}"], [.hexagon]),
        ("{", ["}"], [.diamond]),
        (">", ["]"], [.asymmetric]),
    ]

    mutating func parse(_ lines: [EaselMermaidSource.Line]) throws -> EaselMermaidDiagram {
        let statements = EaselMermaidSource.statements(lines)
        guard let header = statements.first else { throw EaselMermaidRefusal.notMermaid }
        let words = header.text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count > 1 {
            guard let direction = EaselMermaidDirection(keyword: words[1]) else {
                throw syntax(header.number, "the direction should be TB, TD, BT, LR or RL")
            }
            diagram.direction = direction
            directionGiven = true
            if words.count > 2 {
                try read(EaselMermaidSource.Line(number: header.number, text: words.dropFirst(2).joined(separator: " ")))
            }
        }
        for statement in statements.dropFirst() { try read(statement) }
        return try finish()
    }

    private mutating func read(_ statement: EaselMermaidSource.Line) throws {
        let text = statement.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if skippingBlock {
            if text.contains("}") { skippingBlock = false }
            return
        }
        let word = EaselMermaidSource.firstWord(text)
        let rest = String(text.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        switch word {
        case "subgraph": try beginGroup(rest)
        case "end" where rest.isEmpty: try endGroup(line: statement.number)
        case "direction" where !rest.isEmpty:
            guard let direction = EaselMermaidDirection(keyword: rest) else {
                throw syntax(statement.number, "the direction should be TB, TD, BT, LR or RL")
            }
            if let top = stack.last, let index = groupIndex[top.id] { diagram.groups[index].direction = direction }
            else if !directionGiven { diagram.direction = direction; directionGiven = true }
        case "classDef" where !rest.isEmpty: defineClass(rest)
        case "class" where !rest.isEmpty: assignClass(rest)
        case "style" where !rest.isEmpty: assignStyle(rest)
        case "linkStyle" where !rest.isEmpty: assignLinkStyle(rest)
        case "click", "call", "href": return
        case "accTitle", "accDescr", "title":
            if text.contains("{") && !text.contains("}") { skippingBlock = true }
        default:
            if isEdgeProperty(text) { return }
            try chain(text, line: statement.number)
        }
    }

    private func isEdgeProperty(_ text: String) -> Bool {
        var scanner = EaselMermaidScanner(text)
        guard scanner.readIdentifier() != nil, scanner.matches("@{") else { return false }
        let keys = EaselMermaidText.properties(String(scanner.rest.dropFirst(2).dropLast()))
        return keys["shape"] == nil && keys["label"] == nil && (keys["animate"] != nil || keys["animation"] != nil || keys["curve"] != nil)
    }

    private mutating func chain(_ text: String, line: Int) throws {
        var scanner = EaselMermaidScanner(text)
        var previous = try nodeGroup(&scanner, line: line)
        while true {
            let spaced = scanner.skipSpaces()
            if scanner.atEnd { return }
            skipEdgeID(&scanner)
            guard let link = try link(&scanner, spaced: spaced, line: line) else {
                throw syntax(line, "Parc expected an arrow like --> after \(previous.last ?? "a node")")
            }
            scanner.skipSpaces()
            guard !scanner.atEnd else { throw syntax(line, "this arrow needs something on the other end") }
            let next = try nodeGroup(&scanner, line: line)
            guard diagram.edges.count + previous.count * next.count <= EaselMermaid.maximumEdges else { throw EaselMermaidRefusal.tooLarge }
            for from in previous {
                for to in next {
                    diagram.edges.append(EaselMermaidEdge(from: from, to: to, label: link.label, line: link.line, startHead: link.start,
                                                          endHead: link.end, length: min(EaselMermaid.maximumLength, max(1, link.length))))
                }
            }
            previous = next
        }
    }

    private func skipEdgeID(_ scanner: inout EaselMermaidScanner) {
        let start = scanner.index
        if scanner.readIdentifier() != nil, scanner.peek() == "@", let next = scanner.peek(1), "-=.~<ox".contains(next) {
            scanner.advance()
        } else {
            scanner.index = start
        }
    }

    private mutating func nodeGroup(_ scanner: inout EaselMermaidScanner, line: Int) throws -> [String] {
        var ids = [try node(&scanner, line: line)]
        while true {
            let save = scanner.index
            scanner.skipSpaces()
            guard scanner.peek() == "&" else { scanner.index = save; return ids }
            scanner.advance()
            scanner.skipSpaces()
            guard ids.count < EaselMermaid.maximumNodes else { throw EaselMermaidRefusal.tooLarge }
            ids.append(try node(&scanner, line: line))
        }
    }

    private mutating func node(_ scanner: inout EaselMermaidScanner, line: Int) throws -> String {
        guard let id = scanner.readIdentifier() else {
            let found = scanner.peek().map { "“\($0)”" } ?? "the end of the line"
            throw syntax(line, "Parc expected a node name but found \(found)")
        }
        var label: String?, shape: EaselMermaidShape?
        if scanner.matches("@{") {
            scanner.advance(2)
            guard let body = scanner.readUntil("}") else { throw syntax(line, "\(id)@{ … } is missing its closing brace") }
            let properties = EaselMermaidText.properties(body)
            shape = properties["shape"].map(EaselMermaidShape.init(mermaidName:))
            label = properties["label"].map(EaselMermaidText.clean)
        } else {
            var tried = false
            for opener in Self.openers where scanner.matches(opener.open) {
                tried = true
                let save = scanner.index
                scanner.advance(opener.open.count)
                if let found = scanner.readLabel(closers: opener.closers),
                   let position = opener.closers.firstIndex(of: found.closer) {
                    label = EaselMermaidText.clean(found.text)
                    shape = opener.shapes[position]
                    break
                }
                scanner.index = save
            }
            if tried && shape == nil { throw syntax(line, "the label for \(id) is missing its closing bracket") }
        }
        if scanner.matches(":::") {
            scanner.advance(3)
            guard let name = scanner.readIdentifier() else { throw syntax(line, "::: needs a class name after it") }
            nodeClasses[id, default: []].append(name)
        }
        try touch(id, label: label, shape: shape)
        return id
    }

    private mutating func link(_ scanner: inout EaselMermaidScanner, spaced: Bool, line: Int) throws -> EaselMermaidLink? {
        let begin = scanner.index
        var start: Character?
        if scanner.peek() == "<" {
            start = "<"; scanner.advance()
        } else if spaced, let character = scanner.peek(), character == "o" || character == "x",
                  let next = scanner.peek(1), "-=.".contains(next) {
            start = character; scanner.advance()
        }
        guard let first = scanner.peek() else { scanner.index = begin; return nil }
        var result: EaselMermaidLink
        switch first {
        case "-", ".":
            let dashes = scanner.run(of: "-")
            if dashes <= 1, scanner.peek(dashes) == "." {
                scanner.advance(dashes)
                let dots = scanner.take(".")
                if scanner.peek() == "-" {
                    scanner.advance()
                    result = EaselMermaidLink(line: .dotted, length: dots, end: takeHead(&scanner) ?? .none)
                } else if dashes == 1 && dots == 1 {
                    result = try labelled(&scanner, kind: .dotted, line: line)
                } else {
                    scanner.index = begin; return nil
                }
            } else if dashes >= 2 {
                scanner.advance(dashes)
                if let head = takeHead(&scanner) { result = EaselMermaidLink(line: .solid, length: dashes - 1, end: head) }
                else if dashes >= 3 { result = EaselMermaidLink(line: .solid, length: dashes - 2, end: .none) }
                else { result = try labelled(&scanner, kind: .solid, line: line) }
            } else if dashes == 1, scanner.peek(1) == ">" {
                scanner.advance(2)
                result = EaselMermaidLink(line: .solid, length: 1, end: .arrow)
            } else {
                scanner.index = begin; return nil
            }
        case "=":
            let bars = scanner.run(of: "=")
            guard bars >= 2 else { scanner.index = begin; return nil }
            scanner.advance(bars)
            if let head = takeHead(&scanner) { result = EaselMermaidLink(line: .thick, length: bars - 1, end: head) }
            else if bars >= 3 { result = EaselMermaidLink(line: .thick, length: bars - 2, end: .none) }
            else { result = try labelled(&scanner, kind: .thick, line: line) }
        case "~":
            let tildes = scanner.run(of: "~")
            guard tildes >= 3 else { scanner.index = begin; return nil }
            scanner.advance(tildes)
            result = EaselMermaidLink(line: .invisible, length: tildes - 2, end: .none)
        default:
            scanner.index = begin; return nil
        }
        switch start {
        case "<"?: result.start = .arrow
        case "o"?: result.start = .circle
        case "x"?: result.start = .cross
        default: break
        }
        let save = scanner.index
        scanner.skipSpaces()
        if scanner.peek() == "|" {
            scanner.advance()
            guard let label = scanner.readUntil("|") else { throw syntax(line, "an arrow label is missing its closing |") }
            result.label = EaselMermaidText.clean(label)
        } else {
            scanner.index = save
        }
        return result
    }

    private func takeHead(_ scanner: inout EaselMermaidScanner) -> EaselMermaidHead? {
        let head: EaselMermaidHead
        switch scanner.peek() {
        case ">"?: head = .arrow
        case "o"?: head = .circle
        case "x"?: head = .cross
        default: return nil
        }
        scanner.advance()
        return head
    }

    private func labelled(_ scanner: inout EaselMermaidScanner, kind: EaselMermaidLine, line: Int) throws -> EaselMermaidLink {
        let characters = scanner.characters, begin = scanner.index
        var position = begin, found: Int?
        while position < characters.count {
            let character = characters[position]
            if character == "\"" {
                position += 1
                while position < characters.count, characters[position] != "\"" { position += 1 }
                position += 1
                continue
            }
            let next = position + 1 < characters.count ? characters[position + 1] : nil
            switch kind {
            case .solid: if character == "-" && next == "-" { found = position }
            case .thick: if character == "=" && next == "=" { found = position }
            case .dotted:
                if character == "." {
                    var after = position
                    while after < characters.count, characters[after] == "." { after += 1 }
                    if after < characters.count, characters[after] == "-" { found = position }
                }
            case .invisible: break
            }
            if found != nil { break }
            position += 1
        }
        guard let end = found else { throw syntax(line, "an arrow label needs the rest of its arrow, like -- yes -->") }
        let label = EaselMermaidText.clean(String(characters[begin..<end]))
        scanner.index = end
        switch kind {
        case .dotted:
            let dots = scanner.take(".")
            scanner.advance()
            return EaselMermaidLink(line: .dotted, length: dots, end: takeHead(&scanner) ?? .none, label: label)
        default:
            let marks = scanner.take(kind == .thick ? "=" : "-")
            let head = takeHead(&scanner)
            return EaselMermaidLink(line: kind, length: head == nil ? max(1, marks - 2) : marks - 1, end: head ?? .none, label: label)
        }
    }

    private mutating func touch(_ id: String, label: String?, shape: EaselMermaidShape?) throws {
        if label == nil, shape == nil, nodeIndex[id] == nil, groupIndex[id] != nil { return }
        if let index = nodeIndex[id] {
            if let label { diagram.nodes[index].label = label }
            if let shape { diagram.nodes[index].shape = shape }
        } else {
            guard diagram.nodes.count < EaselMermaid.maximumNodes + EaselMermaid.maximumGroups else { throw EaselMermaidRefusal.tooLarge }
            nodeIndex[id] = diagram.nodes.count
            diagram.nodes.append(EaselMermaidNode(id: id, label: label ?? id, shape: shape ?? .rectangle))
        }
        if label != nil || shape != nil { explicitNodes.insert(id) }
        if !stack.isEmpty { stack[stack.count - 1].members.append(id) }
    }

    private mutating func beginGroup(_ rest: String) throws {
        guard diagram.groups.count < EaselMermaid.maximumGroups else { throw EaselMermaidRefusal.tooLarge }
        counter += 1
        var id: String?, title: String
        if let open = rest.firstIndex(of: "["), rest.hasSuffix("]") {
            id = rest[..<open].trimmingCharacters(in: .whitespaces)
            title = EaselMermaidText.clean(String(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)]))
        } else {
            title = EaselMermaidText.clean(rest)
            id = rest.contains(where: \.isWhitespace) || rest.hasPrefix("\"") ? nil : rest
        }
        let base = (id?.isEmpty ?? true) ? "subGraph\(counter)" : id ?? ""
        var groupID = base, suffix = 1
        while groupIndex[groupID] != nil || explicitNodes.contains(groupID) { suffix += 1; groupID = base + "_\(suffix)" }
        groupIndex[groupID] = diagram.groups.count
        diagram.groups.append(EaselMermaidGroup(id: groupID, title: title, parent: stack.last?.id))
        stack.append((groupID, []))
    }

    private mutating func endGroup(line: Int) throws {
        guard let top = stack.popLast() else { throw syntax(line, "there's an end without a subgraph to close") }
        for member in top.members {
            if let index = nodeIndex[member], diagram.nodes[index].group == nil { diagram.nodes[index].group = top.id }
        }
    }

    private mutating func defineClass(_ rest: String) {
        let names = String(rest.prefix { !$0.isWhitespace })
        let declarations = String(rest.dropFirst(names.count))
        let style = EaselMermaidColor.style(declarations)
        for name in names.split(separator: ",") {
            let key = name.trimmingCharacters(in: .whitespaces)
            classes[key] = (classes[key] ?? EaselMermaidStyle()).merged(with: style)
        }
    }

    private mutating func assignClass(_ rest: String) {
        let words = rest.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2, let name = words.last else { return }
        for id in words.dropLast().joined().split(separator: ",") {
            nodeClasses[id.trimmingCharacters(in: .whitespaces), default: []].append(name)
        }
    }

    private mutating func assignStyle(_ rest: String) {
        let id = String(rest.prefix { !$0.isWhitespace })
        let style = EaselMermaidColor.style(String(rest.dropFirst(id.count)))
        styles[id] = (styles[id] ?? EaselMermaidStyle()).merged(with: style)
    }

    private mutating func assignLinkStyle(_ rest: String) {
        let target = String(rest.prefix { !$0.isWhitespace })
        let style = EaselMermaidColor.style(String(rest.dropFirst(target.count)))
        if target == "default" {
            linkStyles.append((nil, style))
        } else {
            linkStyles.append((target.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }, style))
        }
    }

    private mutating func finish() throws -> EaselMermaidDiagram {
        while !stack.isEmpty { try endGroup(line: 0) }
        let groupIDs = Set(diagram.groups.map(\.id))
        diagram.nodes.removeAll { groupIDs.contains($0.id) && !explicitNodes.contains($0.id) }
        guard diagram.nodes.count <= EaselMermaid.maximumNodes, diagram.edges.count <= EaselMermaid.maximumEdges,
              diagram.groups.count <= EaselMermaid.maximumGroups else { throw EaselMermaidRefusal.tooLarge }
        let fallback = classes["default"] ?? EaselMermaidStyle()
        for index in diagram.nodes.indices {
            let id = diagram.nodes[index].id
            var style = fallback
            for name in nodeClasses[id] ?? [] { if let found = classes[name] { style = style.merged(with: found) } }
            if let found = styles[id] { style = style.merged(with: found) }
            diagram.nodes[index].style = style
        }
        for index in diagram.groups.indices {
            let id = diagram.groups[index].id
            var style = EaselMermaidStyle()
            for name in nodeClasses[id] ?? [] { if let found = classes[name] { style = style.merged(with: found) } }
            if let found = styles[id] { style = style.merged(with: found) }
            diagram.groups[index].style = style
        }
        var shared = EaselMermaidStyle(), picked: [Int: EaselMermaidStyle] = [:]
        for entry in linkStyles {
            guard let indices = entry.indices else { shared = shared.merged(with: entry.style); continue }
            for index in indices where diagram.edges.indices.contains(index) {
                picked[index] = (picked[index] ?? EaselMermaidStyle()).merged(with: entry.style)
            }
        }
        for index in diagram.edges.indices {
            diagram.edges[index].style = shared.merged(with: picked[index] ?? EaselMermaidStyle())
        }
        guard !diagram.nodes.isEmpty || !diagram.groups.isEmpty else { throw EaselMermaidRefusal.empty }
        return diagram
    }
}

struct EaselMermaidEntityParser {
    private var diagram = EaselMermaidDiagram(kind: .entityRelationship)
    private var nodeIndex: [String: Int] = [:]
    private var classes: [String: EaselMermaidStyle] = [:]
    private var nodeClasses: [String: [String]] = [:]
    private var styles: [String: EaselMermaidStyle] = [:]

    private static let cardinalities: [(String, EaselMermaidHead)] = [
        ("zero or one", .zeroOrOne), ("one or zero", .zeroOrOne), ("zero or more", .zeroOrMore),
        ("zero or many", .zeroOrMore), ("one or more", .oneOrMore), ("one or many", .oneOrMore),
        ("only one", .exactlyOne), ("many(0)", .zeroOrMore), ("many(1)", .oneOrMore), ("0+", .zeroOrMore),
        ("1+", .oneOrMore), ("1", .exactlyOne),
    ]
    private static let leftSymbols: [String: EaselMermaidHead] = ["|o": .zeroOrOne, "||": .exactlyOne, "}o": .zeroOrMore, "}|": .oneOrMore]
    private static let rightSymbols: [String: EaselMermaidHead] = ["o|": .zeroOrOne, "||": .exactlyOne, "o{": .zeroOrMore, "|{": .oneOrMore]

    mutating func parse(_ lines: [EaselMermaidSource.Line], header: Int) throws -> EaselMermaidDiagram {
        var index = header + 1
        let trailing = lines[header].text.trimmingCharacters(in: .whitespaces).dropFirst("erDiagram".count)
            .trimmingCharacters(in: .whitespaces)
        var pending: [EaselMermaidSource.Line] = trailing.isEmpty ? [] : [EaselMermaidSource.Line(number: lines[header].number, text: trailing)]
        func next() -> EaselMermaidSource.Line? {
            if !pending.isEmpty { return pending.removeFirst() }
            guard index < lines.count else { return nil }
            defer { index += 1 }
            return lines[index]
        }
        var skipping = false
        while let line = next() {
            let text = EaselMermaidSource.strippingComment(line.text).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if skipping {
                if text.contains("}") { skipping = false }
                continue
            }
            let word = EaselMermaidSource.firstWord(text)
            let rest = String(text.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            switch word {
            case "direction" where !rest.isEmpty:
                guard let direction = EaselMermaidDirection(keyword: rest) else {
                    throw syntax(line.number, "the direction should be TB, TD, BT, LR or RL")
                }
                diagram.direction = direction
                continue
            case "title", "accTitle", "accDescr":
                if text.contains("{") && !text.contains("}") { skipping = true }
                continue
            case "classDef" where !rest.isEmpty:
                let names = String(rest.prefix { !$0.isWhitespace })
                let style = EaselMermaidColor.style(String(rest.dropFirst(names.count)))
                for name in names.split(separator: ",") { classes[name.trimmingCharacters(in: .whitespaces)] = style }
                continue
            case "class" where !rest.isEmpty:
                let words = rest.split(whereSeparator: \.isWhitespace).map(String.init)
                if words.count >= 2, let name = words.last {
                    for id in words.dropLast().joined().split(separator: ",") { nodeClasses[String(id), default: []].append(name) }
                }
                continue
            case "style" where !rest.isEmpty:
                let id = String(rest.prefix { !$0.isWhitespace })
                styles[id] = EaselMermaidColor.style(String(rest.dropFirst(id.count)))
                continue
            default: break
            }
            if try relationship(text, line: line.number) { continue }
            var scanner = EaselMermaidScanner(text)
            guard let entity = entityReference(&scanner) else {
                throw syntax(line.number, "Parc couldn't read this as an entity or a relationship")
            }
            readClass(&scanner, for: entity.name)
            scanner.skipSpaces()
            if scanner.atEnd {
                try touch(entity.name, alias: entity.alias)
                continue
            }
            guard scanner.peek() == "{" else { throw syntax(line.number, "Parc couldn't read this as an entity or a relationship") }
            scanner.advance()
            var body = scanner.rest, closed = false
            if let close = body.firstIndex(of: "}") {
                pending.insert(contentsOf: [EaselMermaidSource.Line(number: line.number, text: String(body[body.index(after: close)...]))], at: 0)
                body = String(body[..<close]); closed = true
            }
            while !closed, let more = next() {
                let content = EaselMermaidSource.strippingComment(more.text)
                if let close = content.firstIndex(of: "}") {
                    body += "\n" + content[..<close]
                    pending.insert(EaselMermaidSource.Line(number: more.number, text: String(content[content.index(after: close)...])), at: 0)
                    closed = true
                } else {
                    body += "\n" + content
                }
            }
            guard closed else { throw syntax(line.number, "the { after \(entity.name) needs a closing }") }
            try touch(entity.name, alias: entity.alias, attributes: try attributes(body, line: line.number))
        }
        return try finish()
    }

    private func entityReference(_ scanner: inout EaselMermaidScanner) -> (name: String, alias: String?)? {
        let name: String
        if let quoted = scanner.readQuoted() {
            name = quoted.trimmingCharacters(in: .whitespaces)
        } else {
            var value = ""
            while let character = scanner.peek(), EaselMermaidScanner.isNameCharacter(character) || character == "-" || character == "." {
                if character == "-", value.isEmpty { break }
                if character == "-", let next = scanner.peek(1), next == "-" || next == "." { break }
                value.append(character); scanner.advance()
            }
            name = value
        }
        guard !name.isEmpty else { return nil }
        var alias: String?
        if scanner.peek() == "[" {
            let start = scanner.index
            scanner.advance()
            if let found = scanner.readLabel(closers: ["]"]) { alias = EaselMermaidText.clean(found.text) } else { scanner.index = start }
        }
        return (name, alias)
    }

    private mutating func readClass(_ scanner: inout EaselMermaidScanner, for name: String) {
        guard scanner.matches(":::") else { return }
        scanner.advance(3)
        if let className = scanner.readIdentifier() { nodeClasses[name, default: []].append(className) }
    }

    private mutating func relationship(_ text: String, line: Int) throws -> Bool {
        var scanner = EaselMermaidScanner(text)
        guard let first = entityReference(&scanner) else { return false }
        readClass(&scanner, for: first.name)
        scanner.skipSpaces()
        guard let spec = relationshipSpec(&scanner) else { return false }
        scanner.skipSpaces()
        guard let second = entityReference(&scanner) else { throw syntax(line, "this relationship needs a second entity") }
        readClass(&scanner, for: second.name)
        scanner.skipSpaces()
        var label = ""
        if scanner.peek() == ":" {
            scanner.advance()
            label = EaselMermaidText.clean(scanner.rest)
        } else if !scanner.atEnd {
            throw syntax(line, "a relationship's label goes after a colon")
        }
        try touch(first.name, alias: first.alias)
        try touch(second.name, alias: second.alias)
        guard diagram.edges.count < EaselMermaid.maximumEdges else { throw EaselMermaidRefusal.tooLarge }
        diagram.edges.append(EaselMermaidEdge(from: first.name, to: second.name, label: label,
                                              line: spec.identifying ? .solid : .dotted,
                                              startHead: spec.left, endHead: spec.right))
        return true
    }

    private func relationshipSpec(_ scanner: inout EaselMermaidScanner) -> (left: EaselMermaidHead, identifying: Bool, right: EaselMermaidHead)? {
        let start = scanner.index
        if scanner.index + 6 <= scanner.characters.count {
            let symbol = String(scanner.characters[scanner.index..<scanner.index + 6])
            let left = String(symbol.prefix(2)), middle = String(symbol.dropFirst(2).prefix(2)), right = String(symbol.suffix(2))
            if let leftHead = Self.leftSymbols[left], let rightHead = Self.rightSymbols[right], ["--", "..", ".-", "-."].contains(middle) {
                scanner.advance(6)
                return (leftHead, middle == "--", rightHead)
            }
        }
        guard let left = phrase(&scanner) else { scanner.index = start; return nil }
        scanner.skipSpaces()
        let identifying: Bool
        if matchesWord(&scanner, "optionally to") { identifying = false }
        else if matchesWord(&scanner, "to") { identifying = true }
        else { scanner.index = start; return nil }
        scanner.skipSpaces()
        guard let right = phrase(&scanner) else { scanner.index = start; return nil }
        return (left, identifying, right)
    }

    private func phrase(_ scanner: inout EaselMermaidScanner) -> EaselMermaidHead? {
        for (words, head) in Self.cardinalities where matchesWord(&scanner, words) { return head }
        return nil
    }

    private func matchesWord(_ scanner: inout EaselMermaidScanner, _ words: String) -> Bool {
        let lowered = Array(words)
        guard scanner.index + lowered.count <= scanner.characters.count else { return false }
        for (offset, character) in lowered.enumerated() where scanner.characters[scanner.index + offset].lowercased() != String(character) {
            return false
        }
        if let after = scanner.peek(lowered.count), !after.isWhitespace { return false }
        scanner.advance(lowered.count)
        return true
    }

    private func attributes(_ body: String, line: Int) throws -> [EaselMermaidAttribute] {
        enum Token { case word(String), comment(String), comma }
        var tokens: [Token] = []
        var scanner = EaselMermaidScanner(body)
        while true {
            scanner.skipSpaces()
            guard let character = scanner.peek() else { break }
            if character == "\"" {
                guard let comment = scanner.readQuoted() else { throw syntax(line, "an attribute comment is missing its closing quote") }
                tokens.append(.comment(comment))
            } else if character == "," {
                scanner.advance(); tokens.append(.comma)
            } else {
                var word = ""
                while let next = scanner.peek(), !next.isWhitespace, next != "\"", next != "," { word.append(next); scanner.advance() }
                tokens.append(.word(word))
            }
        }
        var result: [EaselMermaidAttribute] = []
        var position = 0
        while position < tokens.count {
            guard case .word(let type) = tokens[position] else { throw syntax(line, "an attribute starts with its type, like “string name”") }
            guard position + 1 < tokens.count, case .word(let name) = tokens[position + 1] else {
                throw syntax(line, "the \(type) attribute needs a name")
            }
            position += 2
            var keys: [String] = []
            while position < tokens.count {
                if case .word(let key) = tokens[position], ["PK", "FK", "UK"].contains(key.uppercased()) {
                    keys.append(key.uppercased()); position += 1
                } else if case .comma = tokens[position], !keys.isEmpty {
                    position += 1
                } else {
                    break
                }
            }
            var comment = ""
            if position < tokens.count, case .comment(let text) = tokens[position] { comment = EaselMermaidText.clean(text); position += 1 }
            result.append(EaselMermaidAttribute(type: type, name: name, keys: keys, comment: comment))
            guard result.count <= EaselMermaid.maximumAttributes else { throw EaselMermaidRefusal.tooLarge }
        }
        return result
    }

    private mutating func touch(_ name: String, alias: String?, attributes: [EaselMermaidAttribute]? = nil) throws {
        if let index = nodeIndex[name] {
            if let alias { diagram.nodes[index].label = alias }
            if let attributes {
                guard diagram.nodes[index].attributes.count + attributes.count <= EaselMermaid.maximumAttributes else {
                    throw EaselMermaidRefusal.tooLarge
                }
                diagram.nodes[index].attributes += attributes
            }
        } else {
            guard diagram.nodes.count < EaselMermaid.maximumNodes else { throw EaselMermaidRefusal.tooLarge }
            nodeIndex[name] = diagram.nodes.count
            diagram.nodes.append(EaselMermaidNode(id: name, label: alias ?? name, shape: .entity, attributes: attributes ?? []))
        }
    }

    private mutating func finish() throws -> EaselMermaidDiagram {
        for index in diagram.nodes.indices {
            let id = diagram.nodes[index].id
            var style = classes["default"] ?? EaselMermaidStyle()
            for name in nodeClasses[id] ?? [] { if let found = classes[name] { style = style.merged(with: found) } }
            if let found = styles[id] { style = style.merged(with: found) }
            diagram.nodes[index].style = style
        }
        guard !diagram.nodes.isEmpty else { throw EaselMermaidRefusal.empty }
        guard diagram.nodes.count <= EaselMermaid.maximumNodes, diagram.edges.count <= EaselMermaid.maximumEdges,
              diagram.nodes.allSatisfy({ $0.attributes.count <= EaselMermaid.maximumAttributes }) else {
            throw EaselMermaidRefusal.tooLarge
        }
        return diagram
    }
}
