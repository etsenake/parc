import Foundation

struct NoteHTMLStyleSheet {
    private var rules: [String: [String: String]] = [:]

    init(_ document: NoteHTMLNode) {
        for style in document.all(where: { $0.name == "style" }) { parse(style.textContent) }
    }

    func declarations(for node: NoteHTMLNode) -> [String: String] {
        var result: [String: String] = [:]
        if !rules.isEmpty {
            for name in node.classes {
                if let rule = rules["." + name] { result.merge(rule) { $1 } }
                if let rule = rules[node.name + "." + name] { result.merge(rule) { $1 } }
            }
        }
        if let inline = node["style"], !inline.isEmpty { result.merge(Self.declarations(inline)) { $1 } }
        return result
    }

    static func declarations(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for piece in split(text, on: ";") {
            guard let colon = piece.firstIndex(of: ":") else { continue }
            let key = piece[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = piece[piece.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let bang = value.range(of: "!important", options: .caseInsensitive) {
                value = value[..<bang.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            guard !key.isEmpty, !value.isEmpty else { continue }
            result[key] = value
        }
        return result
    }

    static func split(_ text: String, on separator: Character) -> [String] {
        var pieces: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if character == separator && depth == 0 {
                pieces.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        pieces.append(current)
        return pieces
    }

    private mutating func parse(_ source: String) {
        var text = source.replacingOccurrences(of: "<!--", with: " ").replacingOccurrences(of: "-->", with: " ")
        while let open = text.range(of: "/*") {
            let close = text.range(of: "*/", range: open.upperBound..<text.endIndex)?.upperBound ?? text.endIndex
            text.replaceSubrange(open.lowerBound..<close, with: " ")
        }
        var index = text.startIndex
        while index < text.endIndex {
            guard let brace = text[index...].firstIndex(where: { $0 == "{" || $0 == ";" }) else { return }
            let selector = text[index..<brace].trimmingCharacters(in: .whitespacesAndNewlines)
            if text[brace] == ";" {
                index = text.index(after: brace)
                continue
            }
            var depth = 0
            var cursor = brace
            var close = text.endIndex
            while cursor < text.endIndex {
                if text[cursor] == "{" { depth += 1 }
                if text[cursor] == "}" {
                    depth -= 1
                    if depth == 0 { close = cursor; break }
                }
                cursor = text.index(after: cursor)
            }
            if !selector.hasPrefix("@") {
                let body = String(text[text.index(after: brace)..<close])
                let parsed = Self.declarations(body)
                for item in selector.split(separator: ",") {
                    let name = item.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard Self.isClassSelector(name) else { continue }
                    let key = name.hasPrefix(".") ? name
                        : String(name.lowercased().prefix(while: { $0 != "." })) + String(name.drop(while: { $0 != "." }))
                    rules[key, default: [:]].merge(parsed) { $1 }
                }
            }
            index = close < text.endIndex ? text.index(after: close) : text.endIndex
        }
    }

    private static func isClassSelector(_ selector: String) -> Bool {
        let parts = selector.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty else { return false }
        let allowed: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return parts[0].allSatisfy { $0.isLetter || $0.isNumber } && parts[1].allSatisfy(allowed)
    }
}

struct NoteHTMLFont {
    var bold: Bool?
    var italic: Bool?
    var family: String?
    var size: Double?

    init(_ css: [String: String]) {
        if let shorthand = css["font"] { parseShorthand(shorthand) }
        if let weight = css["font-weight"] { bold = Self.weight(weight) ?? bold }
        if let style = css["font-style"]?.lowercased() {
            if style.hasPrefix("italic") || style.hasPrefix("oblique") { italic = true }
            else if style == "normal" { italic = false }
        }
        if let value = css["font-family"] { family = value }
        if let value = css["font-size"], let points = Self.points(value) { size = points }
    }

    static func weight(_ value: String) -> Bool? {
        let lowered = value.lowercased().trimmingCharacters(in: .whitespaces)
        if lowered == "bold" || lowered == "bolder" { return true }
        if lowered == "normal" || lowered == "lighter" { return false }
        if let number = Double(lowered) { return number >= 600 }
        return nil
    }

    static func points(_ value: String) -> Double? {
        let lowered = value.lowercased().trimmingCharacters(in: .whitespaces)
        for (unit, scale) in [("px", 0.75), ("pt", 1.0)] where lowered.hasSuffix(unit) {
            if let number = Double(lowered.dropLast(unit.count)) { return number * scale }
        }
        return nil
    }

    private mutating func parseShorthand(_ value: String) {
        let tokens = Self.tokens(value)
        for (index, token) in tokens.enumerated() {
            let lowered = token.lowercased()
            if let first = lowered.first, first.isNumber || first == "." , lowered.rangeOfCharacter(from: .letters) != nil || lowered.hasSuffix("%") {
                let sizeToken = lowered.split(separator: "/").first.map(String.init) ?? lowered
                size = Self.points(sizeToken)
                let rest = tokens[(index + 1)...].drop { $0.hasPrefix("/") }
                if !rest.isEmpty { family = rest.joined(separator: " ") }
                return
            }
            if lowered == "italic" || lowered == "oblique" { italic = true }
            if let weight = Self.weight(lowered) { bold = weight }
        }
    }

    private static func tokens(_ value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for character in value {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == " " {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    var isMonospace: Bool {
        guard let family else { return false }
        let primary = family.split(separator: ",").first.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")).lowercased()
        } ?? ""
        if ["monospace", "hack", "fixed", "terminal", "courier"].contains(primary) { return true }
        let markers = ["mono", "courier", "consolas", "menlo", "monaco", "inconsolata", "source code", "fira code",
                       "lucida console", "lucida sans typewriter", "andale", "jetbrains", "cascadia", "iosevka", "typewriter"]
        return markers.contains { primary.contains($0) }
    }
}

enum NoteHTMLColor {
    struct RGBA: Hashable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha = 1.0
    }

    static func parse(_ value: String) -> RGBA? {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.hasPrefix("#") { return hex(String(lowered.dropFirst())) }
        if lowered.hasPrefix("rgb") || lowered.hasPrefix("hsl") {
            guard let open = lowered.firstIndex(of: "("), let close = lowered.lastIndex(of: ")"), open < close else { return nil }
            let parts = lowered[lowered.index(after: open)..<close]
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
            guard parts.count >= 3 else { return nil }
            let alpha = parts.count > 3 ? component(parts[3], scale: 1) ?? 1 : 1
            if lowered.hasPrefix("rgb") {
                guard let red = component(parts[0], scale: 255), let green = component(parts[1], scale: 255),
                      let blue = component(parts[2], scale: 255) else { return nil }
                return RGBA(red: red, green: green, blue: blue, alpha: alpha)
            }
            guard let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
                  let saturation = component(parts[1], scale: 100), let lightness = component(parts[2], scale: 100) else { return nil }
            return hsl(hue, saturation, lightness, alpha)
        }
        if let code = named[lowered] { return hex(code) }
        return nil
    }

    static func firstColor(in value: String) -> RGBA? {
        if let direct = parse(value) { return direct }
        for token in NoteHTMLStyleSheet.split(value, on: " ") {
            if let color = parse(token) { return color }
        }
        return nil
    }

    private static func component(_ text: String, scale: Double) -> Double? {
        if text.hasSuffix("%"), let value = Double(text.dropLast()) { return min(max(value / 100, 0), 1) }
        guard let value = Double(text) else { return nil }
        return min(max(value / scale, 0), 1)
    }

    private static func hex(_ digits: String) -> RGBA? {
        var expanded = digits
        if digits.count == 3 || digits.count == 4 { expanded = digits.map { "\($0)\($0)" }.joined() }
        guard expanded.count == 6 || expanded.count == 8, let value = UInt64(expanded, radix: 16) else { return nil }
        let hasAlpha = expanded.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        return RGBA(red: Double(rgb >> 16 & 255) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255,
                    alpha: hasAlpha ? Double(value & 255) / 255 : 1)
    }

    private static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double, _ alpha: Double) -> RGBA {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double)
        switch Int(sector) {
        case 0: (red, green, blue) = (chroma, second, 0)
        case 1: (red, green, blue) = (second, chroma, 0)
        case 2: (red, green, blue) = (0, chroma, second)
        case 3: (red, green, blue) = (0, second, chroma)
        case 4: (red, green, blue) = (second, 0, chroma)
        default: (red, green, blue) = (chroma, 0, second)
        }
        let offset = lightness - chroma / 2
        return RGBA(red: red + offset, green: green + offset, blue: blue + offset, alpha: alpha)
    }

    static func lab(_ color: RGBA) -> (l: Double, a: Double, b: Double) {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let red = linear(color.red), green = linear(color.green), blue = linear(color.blue)
        let x = (0.4124 * red + 0.3576 * green + 0.1805 * blue) / 0.95047
        let y = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let z = (0.0193 * red + 0.1192 * green + 0.9505 * blue) / 1.08883
        func pivot(_ value: Double) -> Double {
            value > 0.008856 ? cbrt(value) : (7.787 * value) + 16.0 / 116.0
        }
        let fx = pivot(x), fy = pivot(y), fz = pivot(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    enum Reading: Equatable {
        case transparent
        case neutral
        case color(NoteColor)
    }

    static func read(_ value: String, background: Bool = false) -> Reading? {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered == "transparent" || lowered == "none" { return .transparent }
        guard let rgba = background ? firstColor(in: lowered) : parse(lowered) else { return nil }
        if rgba.alpha < 0.35 { return .transparent }
        guard let color = nearest(rgba) else { return .neutral }
        return .color(color)
    }

    static func nearest(_ color: RGBA) -> NoteColor? {
        let value = lab(color)
        let chroma = (value.a * value.a + value.b * value.b).squareRoot()
        if chroma < 14 { return nil }
        if value.l < 10 || (value.l < 22 && chroma < 24) { return nil }
        if value.l > 97 && chroma < 18 { return nil }
        var best: (NoteColor, Double)?
        for (name, samples) in references {
            for sample in samples {
                let distance = pow(value.l - sample.l, 2) * 0.5 + pow(value.a - sample.a, 2) + pow(value.b - sample.b, 2)
                if best == nil || distance < best!.1 { best = (name, distance) }
            }
        }
        return best?.0
    }

    private static let references: [(NoteColor, [(l: Double, a: Double, b: Double)])] = {
        let table: [(NoteColor, [String])] = [
            (.red, ["D44C47", "DF5452", "C4554D", "FF0000", "C00000", "CC0000", "E06666", "EA9999", "F4CCCC", "800000",
                    "DC143C", "B22222", "FF4136", "EB5757"]),
            (.orange, ["D9730D", "C77D48", "CC782F", "FF9900", "FFA500", "E69138", "F6B26B", "F9CB9C", "FCE5CD", "FF8C00",
                       "ED7D31", "FF6600", "F4B183"]),
            (.yellow, ["CB912F", "CA9849", "C29343", "FFFF00", "FFD966", "FFE599", "FFF2CC", "FFD700", "FBBC04", "F1C232",
                       "BF9000", "808000", "FFEB3B", "FBF3DB"]),
            (.green, ["448361", "529E72", "548164", "00FF00", "008000", "6AA84F", "93C47D", "B6D7A8", "D9EAD3", "38761D",
                      "00B050", "92D050", "34A853", "2E7D32", "4CAF50"]),
            (.blue, ["337EA9", "379AD3", "487CA5", "0000FF", "4285F4", "1155CC", "3C78D8", "6D9EEB", "A4C2F4", "C9DAF8",
                     "CFE2F3", "9FC5E8", "0B5394", "000080", "00FFFF", "008080", "4472C4", "0070C0", "00B0F0", "1E90FF"]),
            (.purple, ["9065B0", "9D68D3", "8A67AB", "9900FF", "674EA7", "8E7CC3", "B4A7D6", "D9D2E9", "800080", "7030A0",
                       "8A2BE2", "6A0DAD", "4B0082", "351C75"]),
            (.pink, ["C14C8A", "D15796", "B35488", "FF00FF", "C27BA0", "EAD1DC", "D5A6BD", "FFC0CB", "FF69B4", "E91E63",
                     "FF1493", "A64D79", "C0306A"]),
            (.brown, ["9F6B53", "BA856F", "976D57", "8B4513", "A0522D", "795548", "7B3F00", "964B00", "6F4E37", "A52A2A",
                      "D2B48C", "C19A6B"])
        ]
        return table.map { name, codes in (name, codes.compactMap { hex($0).map(lab) }) }
    }()

    private static let named: [String: String] = [
        "black": "000000", "white": "ffffff", "red": "ff0000", "green": "008000", "blue": "0000ff", "yellow": "ffff00",
        "orange": "ffa500", "purple": "800080", "pink": "ffc0cb", "brown": "a52a2a", "gray": "808080", "grey": "808080",
        "silver": "c0c0c0", "maroon": "800000", "olive": "808000", "lime": "00ff00", "aqua": "00ffff", "cyan": "00ffff",
        "teal": "008080", "navy": "000080", "fuchsia": "ff00ff", "magenta": "ff00ff", "gold": "ffd700",
        "darkred": "8b0000", "darkgreen": "006400", "darkblue": "00008b", "darkorange": "ff8c00", "darkviolet": "9400d3",
        "darkmagenta": "8b008b", "darkcyan": "008b8b", "darkgoldenrod": "b8860b", "darkyellow": "808000",
        "lightyellow": "ffffe0", "lightgreen": "90ee90", "lightblue": "add8e6", "lightpink": "ffb6c1", "lightgray": "d3d3d3",
        "lightgrey": "d3d3d3", "darkgray": "a9a9a9", "darkgrey": "a9a9a9", "dimgray": "696969", "violet": "ee82ee",
        "indigo": "4b0082", "crimson": "dc143c", "tomato": "ff6347", "coral": "ff7f50", "salmon": "fa8072",
        "chocolate": "d2691e", "sienna": "a0522d", "saddlebrown": "8b4513", "tan": "d2b48c", "khaki": "f0e68c",
        "turquoise": "40e0d0", "royalblue": "4169e1", "steelblue": "4682b4", "skyblue": "87ceeb", "dodgerblue": "1e90ff",
        "deepskyblue": "00bfff", "forestgreen": "228b22", "seagreen": "2e8b57", "limegreen": "32cd32", "orchid": "da70d6",
        "plum": "dda0dd", "hotpink": "ff69b4", "deeppink": "ff1493", "firebrick": "b22222", "goldenrod": "daa520",
        "orangered": "ff4500", "mediumpurple": "9370db", "rebeccapurple": "663399", "slateblue": "6a5acd",
        "slategray": "708090", "whitesmoke": "f5f5f5", "gainsboro": "dcdcdc", "lavender": "e6e6fa", "beige": "f5f5dc",
        "ivory": "fffff0", "snow": "fffafa", "linen": "faf0e6", "windowtext": "000000"
    ]

    static func style(token: String) -> NoteColorStyle? {
        var name = token.lowercased()
        var background = false
        for suffix in ["_background", "-background", "_bg", "-bg"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            background = true
        }
        if name == "teal" { name = "green" }
        guard let color = NoteColor(rawValue: name) else { return nil }
        return background ? .background(color) : .text(color)
    }

    static func token(_ style: NoteColorStyle) -> String {
        style.isBackground ? style.color.rawValue + "_background" : style.color.rawValue
    }
}
