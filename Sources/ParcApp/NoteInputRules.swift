import Foundation

struct NoteBlockShortcut: Hashable {
    var conversion: NoteBlockConversion
    var prefixLength: Int
    var checked = false
    var listStart: Int?
    var bulletMarker: String?
    var orderedDelimiter: String?
    var language: String?

    var adjustsProps: Bool {
        checked || listStart != nil || bulletMarker != nil || orderedDelimiter != nil || !(language ?? "").isEmpty
    }

    func adjust(_ props: inout NoteBlockProps) {
        switch conversion {
        case .todo: props.checked = checked
        case .bulletedList: props.bulletMarker = bulletMarker
        case .numberedList:
            props.listStart = listStart
            props.orderedDelimiter = orderedDelimiter
        case .code: props.language = language ?? ""
        default: break
        }
    }
}

struct NoteInlineConversion: Hashable {
    var text: NoteText
    var caret: Int
    var typingMarks: NoteMarks
    var name: String
}

enum NoteInputRule: Hashable {
    case block(NoteBlockShortcut)
    case inline(NoteInlineConversion)
}

enum NoteInputRules {
    static func afterTyping(_ inserted: String, text: NoteText, caret: Int, block: NoteBlock) -> NoteInputRule? {
        guard block.kind.hasRichText, let last = inserted.unicodeScalars.last, caret > 0, caret <= text.length else { return nil }
        let typed = Character(last)
        if let conversion = blockConversion(typed: typed, text: text, caret: caret, block: block) { return .block(conversion) }
        let marks = text.marks(at: caret - 1)
        if marks.code && typed != "`" { return nil }
        if let inline = inlineConversion(typed: typed, text: text, caret: caret) { return .inline(inline) }
        if typed == " ", let link = autolink(text: text, caret: caret) { return .inline(link) }
        return nil
    }

    static func onNewline(text: NoteText, caret: Int, block: NoteBlock) -> NoteInputRule? {
        guard block.kind.hasRichText, caret == text.length, let prefix = plainPrefix(text, caret),
              let language = fenceLanguage(prefix) else { return nil }
        return .block(NoteBlockShortcut(conversion: .code, prefixLength: caret, language: language))
    }

    private static func plainPrefix(_ text: NoteText, _ caret: Int) -> String? {
        let slice = text.slice(0..<caret)
        guard !slice.spans.contains(where: { $0.marks.atom != nil }) else { return nil }
        return slice.string
    }

    private static func fenceLanguage(_ prefix: String) -> String? {
        guard prefix.hasPrefix("```") else { return nil }
        let language = String(prefix.dropFirst(3))
        guard language.count <= 32, language.allSatisfy({ $0.isLetter || $0.isNumber || "+#-_.".contains($0) }) else { return nil }
        return language
    }

    private static func blockConversion(typed: Character, text: NoteText, caret: Int, block: NoteBlock) -> NoteBlockShortcut? {
        guard let prefix = plainPrefix(text, caret) else { return nil }
        if typed == "-", prefix == "---", text.length == 3, block.kind != .divider {
            return NoteBlockShortcut(conversion: .divider, prefixLength: 3)
        }
        if typed == "$", prefix == "$$", text.length == 2 {
            return NoteBlockShortcut(conversion: .equation, prefixLength: 2)
        }
        guard typed == " " else { return nil }
        let marker = String(prefix.dropLast())
        guard !marker.isEmpty, !marker.contains(" ") || marker == "[ ]" else { return nil }
        let conversion: NoteBlockShortcut
        if marker.allSatisfy({ $0 == "#" }), marker.count <= 6 {
            let toggle = block.isToggle
            if block.kind == .heading, block.props.level == marker.count, block.props.toggleable == toggle { return nil }
            conversion = NoteBlockShortcut(conversion: toggle ? .toggleHeading(marker.count) : .heading(marker.count), prefixLength: caret)
        } else if ["-", "*", "+"].contains(marker) {
            guard block.kind != .bulletedItem else { return nil }
            conversion = NoteBlockShortcut(conversion: .bulletedList, prefixLength: caret, bulletMarker: marker == "-" ? nil : marker)
        } else if let numbered = numberedMarker(marker) {
            guard block.kind != .numberedItem else { return nil }
            conversion = NoteBlockShortcut(conversion: .numberedList, prefixLength: caret, listStart: numbered.start,
                                           orderedDelimiter: numbered.delimiter)
        } else if marker == "[]" || marker == "[ ]" || marker == "[x]" || marker == "[X]" {
            let checked = marker.lowercased() == "[x]"
            if block.kind == .todo, block.props.checked == checked { return nil }
            conversion = NoteBlockShortcut(conversion: .todo, prefixLength: caret, checked: checked)
        } else if marker == ">" {
            guard !block.isToggle else { return nil }
            conversion = NoteBlockShortcut(conversion: .toggle, prefixLength: caret)
        } else if marker == "\"" || marker == "|" || marker == "“" {
            guard block.kind != .quote else { return nil }
            conversion = NoteBlockShortcut(conversion: .quote, prefixLength: caret)
        } else if let language = fenceLanguage(marker) {
            conversion = NoteBlockShortcut(conversion: .code, prefixLength: caret, language: language)
        } else {
            return nil
        }
        return conversion
    }

    private static func numberedMarker(_ marker: String) -> (start: Int?, delimiter: String?)? {
        if marker == "a." || marker == "i." { return (nil, nil) }
        guard let delimiter = marker.last, delimiter == "." || delimiter == ")" else { return nil }
        let digits = marker.dropLast()
        guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(digits) else {
            return nil
        }
        return (value == 1 ? nil : value, delimiter == ")" ? ")" : nil)
    }

    private struct Delimiter {
        var token: String
        var name: String
        var boundary: Bool
        var apply: (inout NoteMarks) -> Void
        var clear: (inout NoteMarks) -> Void
        var isEquation = false
    }

    private static let delimiters: [Delimiter] = [
        Delimiter(token: "**", name: "Bold", boundary: false, apply: { $0.bold = true }, clear: { $0.bold = false }),
        Delimiter(token: "__", name: "Bold", boundary: true, apply: { $0.bold = true }, clear: { $0.bold = false }),
        Delimiter(token: "~~", name: "Strikethrough", boundary: false, apply: { $0.strikethrough = true }, clear: { $0.strikethrough = false }),
        Delimiter(token: "==", name: "Highlight", boundary: false, apply: { $0.color = .background(.yellow) },
                  clear: { $0.color = nil }),
        Delimiter(token: "$$", name: "Equation", boundary: false, apply: { _ in }, clear: { _ in }, isEquation: true),
        Delimiter(token: "`", name: "Inline Code", boundary: false, apply: { $0.code = true }, clear: { $0.code = false }),
        Delimiter(token: "*", name: "Italic", boundary: true, apply: { $0.italic = true }, clear: { $0.italic = false }),
        Delimiter(token: "_", name: "Italic", boundary: true, apply: { $0.italic = true }, clear: { $0.italic = false }),
        Delimiter(token: "~", name: "Strikethrough", boundary: true, apply: { $0.strikethrough = true }, clear: { $0.strikethrough = false }),
        Delimiter(token: "$", name: "Equation", boundary: true, apply: { _ in }, clear: { _ in }, isEquation: true),
    ]

    private static func inlineConversion(typed: Character, text: NoteText, caret: Int) -> NoteInlineConversion? {
        let units = Array(text.string.utf16)
        for delimiter in delimiters {
            let token = Array(delimiter.token.utf16)
            let length = token.count
            guard typed == Character(delimiter.token.unicodeScalars.last!), caret >= length * 2 + 1,
                  Array(units[(caret - length)..<caret]) == token else { continue }
            let tokenUnit = token[0]
            let closeStart = caret - length
            if length == 1, closeStart > 0, units[closeStart - 1] == tokenUnit { continue }
            var open = closeStart - 1 - length
            while open >= 0 {
                defer { open -= 1 }
                guard Array(units[open..<(open + length)]) == token else { continue }
                if open > 0, units[open - 1] == tokenUnit { continue }
                let contentStart = open + length
                guard contentStart < closeStart else { continue }
                let content = Array(units[contentStart..<closeStart])
                if content.contains(10) || content.contains(13) { break }
                guard !isSpace(content.first!), !isSpace(content.last!) else { continue }
                if content.first == tokenUnit || content.last == tokenUnit { continue }
                if delimiter.boundary, open > 0, isWordUnit(units[open - 1]) { continue }
                let contentRange = contentStart..<closeStart
                let segment = text.slice(contentRange)
                if segment.spans.contains(where: { $0.marks.code }) && !delimiter.isEquation { continue }
                if (delimiter.isEquation || delimiter.token == "`") && segment.spans.contains(where: { $0.marks.atom != nil }) { continue }
                var result = text
                result.delete(closeStart..<caret)
                result.delete(open..<contentStart)
                let range = open..<(open + content.count)
                if delimiter.isEquation {
                    let marks = text.marks(at: open).withoutAtom
                    result.replace(range, with: NoteText.atom(.equation(segment.string), marks: marks))
                    let end = open + 1
                    return NoteInlineConversion(text: result, caret: end, typingMarks: marks, name: delimiter.name)
                }
                result.updateMarks(in: range, delimiter.apply)
                var typing = result.typingMarks(at: range.upperBound)
                delimiter.clear(&typing)
                return NoteInlineConversion(text: result, caret: range.upperBound, typingMarks: typing, name: delimiter.name)
            }
        }
        return nil
    }

    private static func autolink(text: NoteText, caret: Int) -> NoteInlineConversion? {
        let units = Array(text.string.utf16)
        let end = caret - 1
        var start = end
        while start > 0, !isSpace(units[start - 1]) { start -= 1 }
        guard start < end else { return nil }
        var wordEnd = end
        let word = String(utf16CodeUnits: Array(units[start..<end]), count: end - start)
        var trimmed = Substring(word)
        while let last = trimmed.last, ".,;:!?'\"".contains(last) || (last == ")" && !trimmed.contains("(")) {
            trimmed.removeLast()
            wordEnd -= String(last).utf16.count
        }
        let candidate = String(trimmed)
        let lower = candidate.lowercased()
        let url: String
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            guard candidate.count > (lower.hasPrefix("https://") ? 8 : 7) else { return nil }
            url = candidate
        } else if lower.hasPrefix("www.") {
            url = "https://" + candidate
        } else {
            return nil
        }
        guard let parsed = URL(string: url), let host = parsed.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            return nil
        }
        let range = start..<wordEnd
        guard !text.runs(in: range).contains(where: { $0.marks.link != nil || $0.marks.code || $0.marks.atom != nil }) else { return nil }
        var result = text
        result.updateMarks(in: range) { $0.link = url }
        return NoteInlineConversion(text: result, caret: caret, typingMarks: result.typingMarks(at: caret), name: "Link")
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 32 || unit == 9 || unit == 10 || unit == 13 || unit == 0xA0 || unit == 0x2028 || unit == 0x3000
    }

    private static func isWordUnit(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return true }
        return scalar.properties.isAlphabetic || (unit >= 48 && unit <= 57)
    }
}

extension NotePageSession {
    func applyInlineConversion(_ conversion: NoteInlineConversion, to id: NoteBlockID, field: NoteTextField = .body,
                               origin: AnyObject? = nil) {
        edit(conversion.name, kind: .text, affected: [id], origin: origin,
             selection: .caret(NotePosition(id, conversion.caret, field: field))) { page in
            page.update(id) { $0.setText(conversion.text, in: field) }
        }
    }

    @discardableResult
    func applyBlockShortcut(_ shortcut: NoteBlockShortcut, to id: NoteBlockID) -> NotePosition? {
        let applied = group("Turn Into") { () -> Bool in
            guard applyBlockShortcut(id, prefixLength: shortcut.prefixLength, conversion: shortcut.conversion) else { return false }
            if shortcut.adjustsProps, page.block(id) != nil { updateBlock(id, name: "Turn Into") { shortcut.adjust(&$0.props) } }
            return true
        }
        guard applied else { return nil }
        if case .text(_, let head) = selection { return head }
        return NotePosition(id, 0)
    }
}
