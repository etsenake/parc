import Foundation

enum NoteMDFrontMatter {
    private enum Scalar {
        case text(String)
        case number(Double)
        case checkbox(Bool)
        case date(String)
    }

    private enum Value {
        case scalar(Scalar)
        case list([String])
        case complex
    }

    static func split(_ bytes: [UInt8]) -> (yaml: String, body: ArraySlice<UInt8>)? {
        func line(at start: Int) -> (Range<Int>, Int) {
            var end = start
            while end < bytes.count, bytes[end] != NoteMDByte.newline { end += 1 }
            var contentEnd = end
            while contentEnd > start, bytes[contentEnd - 1] == NoteMDByte.space || bytes[contentEnd - 1] == NoteMDByte.tab || bytes[contentEnd - 1] == NoteMDByte.carriageReturn { contentEnd -= 1 }
            return (start..<contentEnd, end < bytes.count ? end + 1 : end)
        }
        let (first, afterFirst) = line(at: 0)
        guard Array(bytes[first]) == Array("---".utf8), afterFirst > first.upperBound else { return nil }
        var start = afterFirst
        while start < bytes.count {
            let (range, next) = line(at: start)
            let content = Array(bytes[range])
            if content == Array("---".utf8) || content == Array("...".utf8) {
                let yaml = NoteMDByte.string(bytes[afterFirst..<start])
                return (yaml, bytes[next...])
            }
            if next == start { break }
            start = next
        }
        return nil
    }

    static func read(_ yaml: String) -> NotePageSettings {
        var settings = NotePageSettings()
        var coverPosition: Double?
        var coverCredit: (name: String?, link: String?) = (nil, nil)
        var lines = yaml.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
            var end = index + 1
            while end < lines.count {
                let next = lines[end]
                if next.first == " " || next.first == "\t" || next.hasPrefix("- ") || next == "-" { end += 1; continue }
                if next.trimmingCharacters(in: .whitespaces).isEmpty,
                   let following = lines[(end + 1)...].first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
                   following.first == " " || following.first == "\t" || following.hasPrefix("- ") {
                    end += 1
                    continue
                }
                break
            }
            let entry = Array(lines[index..<end])
            index = end
            guard let (key, rest) = splitKey(line), !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("#"), !line.hasPrefix("- ") else {
                settings.preservedFrontMatter.append(entry.joined(separator: "\n"))
                continue
            }
            let value = classify(rest, continuation: Array(entry.dropFirst()))
            if apply(key: key, value: value, to: &settings, coverPosition: &coverPosition, coverCredit: &coverCredit) { continue }
            switch value {
            case .scalar(let scalar): settings.properties.append(NotePageProperty(key: key, value: propertyValue(scalar)))
            case .list(let items): settings.properties.append(NotePageProperty(key: key, value: .list(items)))
            case .complex: settings.preservedFrontMatter.append(entry.joined(separator: "\n"))
            }
        }
        if let coverPosition {
            if settings.cover != nil { settings.cover?.position = coverPosition } else {
                settings.properties.append(NotePageProperty(key: "cover-position", value: .number(coverPosition)))
            }
        }
        if settings.cover != nil, let credit = NoteMediaCredit(name: coverCredit.name, link: coverCredit.link),
           credit.name == coverCredit.name, credit.link == coverCredit.link {
            settings.cover?.credit = credit
        } else {
            if let name = coverCredit.name { settings.properties.append(NotePageProperty(key: "cover-credit", value: .text(name))) }
            if let link = coverCredit.link { settings.properties.append(NotePageProperty(key: "cover-credit-url", value: .text(link))) }
        }
        return settings
    }

    private static func propertyValue(_ scalar: Scalar) -> NotePropertyValue {
        switch scalar {
        case .text(let value): return .text(value)
        case .number(let value): return .number(value)
        case .checkbox(let value): return .checkbox(value)
        case .date(let value): return .date(value)
        }
    }

    private static func apply(key: String, value: Value, to settings: inout NotePageSettings, coverPosition: inout Double?,
                              coverCredit: inout (name: String?, link: String?)) -> Bool {
        guard case .scalar(let scalar) = value else { return false }
        switch (key, scalar) {
        case ("icon", .text(let text)) where !text.isEmpty && settings.icon == nil:
            settings.icon = text
        case ("cover", .text(let text)) where !text.isEmpty && settings.cover == nil:
            settings.cover = NoteCover(source: text)
        case ("cover-position", .number(let number)) where coverPosition == nil:
            coverPosition = number
        case ("cover-credit", .text(let text)) where coverCredit.name == nil:
            coverCredit.name = text
        case ("cover-credit-url", .text(let text)) where coverCredit.link == nil:
            coverCredit.link = text
        case ("font", .text(let text)):
            guard let font = NotePageFont(rawValue: text), font != .standard, settings.font == .standard else { return false }
            settings.font = font
        case ("small-text", .checkbox(true)) where !settings.smallText:
            settings.smallText = true
        case ("full-width", .checkbox(true)) where !settings.fullWidth:
            settings.fullWidth = true
        case ("locked", .checkbox(true)) where !settings.locked:
            settings.locked = true
        case ("backlinks", .text(let text)):
            guard let display = NoteBacklinksDisplay(rawValue: text), settings.backlinks == nil else { return false }
            settings.backlinks = display
        default:
            return false
        }
        return true
    }

    private static func splitKey(_ line: String) -> (String, String)? {
        let scalars = Array(line.unicodeScalars)
        guard let first = scalars.first else { return nil }
        if first == "\"" || first == "'" {
            var index = 1
            var key = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                if scalar == first {
                    if first == "'", index + 1 < scalars.count, scalars[index + 1] == "'" { key.append("'"); index += 2; continue }
                    break
                }
                if first == "\"", scalar == "\\" { return nil }
                key.append(scalar)
                index += 1
            }
            guard index + 1 < scalars.count, scalars[index + 1] == ":" else { return nil }
            let rest = String(String.UnicodeScalarView(scalars[(index + 2)...]))
            guard rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("\t") else { return nil }
            return (String(key), rest.trimmingCharacters(in: .whitespaces))
        }
        if "-?:,[]{}#&*!|>%@`".unicodeScalars.contains(first) { return nil }
        var index = 0
        while index < scalars.count {
            if scalars[index] == ":", index + 1 == scalars.count || scalars[index + 1] == " " || scalars[index + 1] == "\t" {
                let key = String(String.UnicodeScalarView(scalars[..<index]))
                guard !key.isEmpty, key == key.trimmingCharacters(in: .whitespaces), !key.contains(" #") else { return nil }
                let rest = String(String.UnicodeScalarView(scalars[(index + 1)...])).trimmingCharacters(in: .whitespaces)
                return (key, rest)
            }
            index += 1
        }
        return nil
    }

    private static func classify(_ rest: String, continuation: [String]) -> Value {
        let content = continuation.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !content.isEmpty {
            guard rest.isEmpty else { return .complex }
            var items: [String] = []
            for line in content {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("- ") || trimmed == "-" else { return .complex }
                let item = trimmed == "-" ? "" : String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard let text = listItem(item, inFlow: false) else { return .complex }
                items.append(text)
            }
            return .list(items)
        }
        if rest.isEmpty { return .scalar(.text("")) }
        if rest.hasPrefix("[") {
            guard rest.hasSuffix("]") else { return .complex }
            let inner = rest.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return .list([]) }
            guard let parts = flowItems(inner) else { return .complex }
            var items: [String] = []
            for part in parts {
                guard let text = listItem(part, inFlow: true) else { return .complex }
                items.append(text)
            }
            return .list(items)
        }
        guard let value = scalar(rest, inFlow: false) else { return .complex }
        return .scalar(value)
    }

    private static func listItem(_ raw: String, inFlow: Bool) -> String? {
        switch scalar(raw, inFlow: inFlow) {
        case .text(let value): return value
        case .date, .checkbox, .number: return raw
        case nil: return nil
        }
    }

    private static func flowItems(_ inner: String) -> [String]? {
        var items: [String] = []
        var current = ""
        var quote: Character?
        var previous: Character?
        for character in inner {
            if let open = quote {
                current.append(character)
                if character == open, !(open == "\"" && previous == "\\") { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "," {
                items.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else if "[]{}".contains(character) {
                return nil
            } else {
                current.append(character)
            }
            previous = character
        }
        guard quote == nil else { return nil }
        items.append(current.trimmingCharacters(in: .whitespaces))
        return items.contains(where: \.isEmpty) ? nil : items
    }

    private static func scalar(_ raw: String, inFlow: Bool) -> Scalar? {
        guard let first = raw.first else { return .text("") }
        if first == "\"" {
            var result = ""
            var iterator = raw.dropFirst().makeIterator()
            var closed = false
            var trailing = ""
            while let character = iterator.next() {
                if closed { trailing.append(character); continue }
                if character == "\"" { closed = true; continue }
                if character == "\\" {
                    guard let escaped = iterator.next() else { return nil }
                    switch escaped {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    case "/": result.append("/")
                    case "0": result.append("\0")
                    case "u":
                        var hex = ""
                        for _ in 0..<4 { if let digit = iterator.next() { hex.append(digit) } }
                        guard let code = UInt32(hex, radix: 16), let unicode = Unicode.Scalar(code) else { return nil }
                        result.unicodeScalars.append(unicode)
                    default: return nil
                    }
                    continue
                }
                result.append(character)
            }
            guard closed, trailing.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return .text(result)
        }
        if first == "'" {
            var result = ""
            let characters = Array(raw.dropFirst())
            var index = 0
            var closed = false
            while index < characters.count {
                let character = characters[index]
                if character == "'" {
                    if index + 1 < characters.count, characters[index + 1] == "'" { result.append("'"); index += 2; continue }
                    closed = true
                    index += 1
                    break
                }
                result.append(character)
                index += 1
            }
            guard closed, String(characters[index...]).trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return .text(result)
        }
        if "{&*!|>%@`#,[]}".contains(first) || raw.hasPrefix("- ") || raw.hasPrefix("? ") || raw.hasPrefix(": ") || raw == "-" { return nil }
        if raw.contains(" #") || raw.contains("\t#") || raw.hasSuffix(":") || raw.contains(": ") { return nil }
        if inFlow, raw.contains(where: { ",[]{}".contains($0) }) { return nil }
        switch raw {
        case "true", "True", "TRUE": return .checkbox(true)
        case "false", "False", "FALSE": return .checkbox(false)
        case "null", "Null", "NULL", "~": return nil
        default: break
        }
        if isNumber(raw) {
            guard let value = Double(raw), abs(value) < 1e15 else { return nil }
            return .number(value)
        }
        if looksNumeric(raw) { return nil }
        if isDate(raw) { return .date(raw) }
        return .text(raw)
    }

    private static func isNumber(_ value: String) -> Bool {
        guard value.range(of: "^[-+]?(\\.[0-9]+|[0-9]+(\\.[0-9]*)?)([eE][-+]?[0-9]+)?$", options: .regularExpression) != nil else { return false }
        let digits = value.drop(while: { $0 == "-" || $0 == "+" })
        if digits.count > 1, digits.first == "0", digits.dropFirst().first?.isNumber == true { return false }
        return true
    }

    private static func looksNumeric(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if [".inf", "-.inf", "+.inf", ".nan"].contains(lowered) { return true }
        if lowered.range(of: "^[-+]?0[xo][0-9a-f]+$", options: .regularExpression) != nil { return true }
        return lowered.range(of: "^[-+]?0[0-9]+(\\.[0-9]*)?$", options: .regularExpression) != nil
    }

    private static func isDate(_ value: String) -> Bool {
        value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?)?$", options: .regularExpression) != nil
    }

    static func write(_ settings: NotePageSettings) -> String? {
        var lines: [String] = []
        if let icon = settings.icon { lines.append("icon: " + scalarText(icon)) }
        if let cover = settings.cover {
            lines.append("cover: " + scalarText(cover.source))
            if cover.position != 0.5 { lines.append("cover-position: " + numberText(cover.position)) }
            if let credit = cover.credit, !credit.name.isEmpty {
                lines.append("cover-credit: " + scalarText(credit.name))
                if let link = credit.link { lines.append("cover-credit-url: " + scalarText(link)) }
            }
        }
        if settings.font != .standard { lines.append("font: " + settings.font.rawValue) }
        if settings.smallText { lines.append("small-text: true") }
        if settings.fullWidth { lines.append("full-width: true") }
        if settings.locked { lines.append("locked: true") }
        if let backlinks = settings.backlinks { lines.append("backlinks: " + backlinks.rawValue) }
        for property in settings.properties {
            let key = keyText(property.key)
            switch property.value {
            case .text(let value): lines.append(value.isEmpty ? key + ":" : key + ": " + scalarText(value))
            case .number(let value): lines.append(key + ": " + numberText(value))
            case .checkbox(let value): lines.append(key + ": " + (value ? "true" : "false"))
            case .date(let value): lines.append(key + ": " + (isDate(value) ? value : quoted(value)))
            case .list(let items):
                if items.isEmpty { lines.append(key + ": []") } else {
                    lines.append(key + ":")
                    for item in items { lines.append("  - " + scalarText(item, inList: true)) }
                }
            }
        }
        lines.append(contentsOf: settings.preservedFrontMatter)
        guard !lines.isEmpty else { return nil }
        return "---\n" + lines.joined(separator: "\n") + "\n---\n"
    }

    private static func keyText(_ key: String) -> String {
        if key.range(of: "^[A-Za-z0-9_][A-Za-z0-9 _.-]*$", options: .regularExpression) != nil, !key.hasSuffix(" "), !key.contains(" #") { return key }
        return quoted(key)
    }

    private static func numberText(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }

    private static func scalarText(_ value: String, inList: Bool = false) -> String {
        guard !value.isEmpty else { return "\"\"" }
        let safe = value == value.trimmingCharacters(in: .whitespaces)
            && !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0 == "\u{2028}" || $0 == "\u{2029}" })
        if safe {
            if inList {
                if listItem(value, inFlow: false) == value { return value }
            } else if case .text(let read)? = scalar(value, inFlow: false), read == value {
                return value
            }
        }
        return quoted(value)
    }

    private static func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            default:
                if scalar.value < 32 || scalar.value == 127 { result += String(format: "\\u%04X", scalar.value) } else { result.unicodeScalars.append(scalar) }
            }
        }
        return result + "\""
    }
}
