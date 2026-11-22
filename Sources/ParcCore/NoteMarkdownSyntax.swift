import Foundation

enum NoteMDByte {
    static let tab: UInt8 = 9
    static let newline: UInt8 = 10
    static let carriageReturn: UInt8 = 13
    static let space: UInt8 = 32

    static func isSpaceOrTab(_ byte: UInt8) -> Bool { byte == space || byte == tab }
    static func isWhitespace(_ byte: UInt8) -> Bool { byte == space || byte == tab || byte == newline || byte == carriageReturn || byte == 12 || byte == 11 }
    static func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
    static func isLetter(_ byte: UInt8) -> Bool { (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) }
    static func isAlphanumeric(_ byte: UInt8) -> Bool { isLetter(byte) || isDigit(byte) }
    static func isHexDigit(_ byte: UInt8) -> Bool { isDigit(byte) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102) }
    static func isPunctuation(_ byte: UInt8) -> Bool {
        (byte >= 33 && byte <= 47) || (byte >= 58 && byte <= 64) || (byte >= 91 && byte <= 96) || (byte >= 123 && byte <= 126)
    }
    static func lowered(_ byte: UInt8) -> UInt8 { byte >= 65 && byte <= 90 ? byte + 32 : byte }

    static func string(_ bytes: ArraySlice<UInt8>) -> String { String(decoding: bytes, as: UTF8.self) }
    static func string(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

    static func scalar(endingBefore index: Int, in bytes: [UInt8], lowerBound: Int = 0) -> Unicode.Scalar? {
        guard index > lowerBound else { return nil }
        var start = index - 1
        while start > lowerBound, bytes[start] & 0xC0 == 0x80 { start -= 1 }
        return String(decoding: bytes[start..<index], as: UTF8.self).unicodeScalars.first
    }

    static func scalar(startingAt index: Int, in bytes: [UInt8], upperBound: Int) -> Unicode.Scalar? {
        guard index < upperBound else { return nil }
        var end = index + 1
        while end < upperBound, bytes[end] & 0xC0 == 0x80 { end += 1 }
        return String(decoding: bytes[index..<end], as: UTF8.self).unicodeScalars.first
    }

    static func isUnicodeWhitespace(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return true }
        switch scalar.value {
        case 9, 10, 12, 13, 32: return true
        default: return scalar.properties.generalCategory == .spaceSeparator
        }
    }

    static func isUnicodePunctuation(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        if scalar.isASCII { return isPunctuation(UInt8(scalar.value)) }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
             .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }
}

enum NoteMDText {
    static func unescape(_ bytes: ArraySlice<UInt8>) -> String {
        guard bytes.contains(92) || bytes.contains(38) else { return NoteMDByte.string(bytes) }
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == 92, index + 1 < bytes.endIndex, NoteMDByte.isPunctuation(bytes[index + 1]) {
                output.append(bytes[index + 1])
                index += 2
            } else if byte == 38, let (decoded, length) = NoteMDEntities.decode(bytes, at: index) {
                output.append(contentsOf: Array(decoded.utf8))
                index += length
            } else {
                output.append(byte)
                index += 1
            }
        }
        return NoteMDByte.string(output)
    }

    static func normalizeLabel(_ label: String) -> String {
        let collapsed = label.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " ")
        return collapsed.folding(options: [.caseInsensitive], locale: nil).uppercased()
    }

    static func trimmed(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var lower = bytes.startIndex, upper = bytes.endIndex
        while lower < upper, NoteMDByte.isWhitespace(bytes[lower]) { lower += 1 }
        while upper > lower, NoteMDByte.isWhitespace(bytes[upper - 1]) { upper -= 1 }
        return bytes[lower..<upper]
    }
}

struct NoteMDLinkReference: Hashable {
    var destination: String
    var title: String?
}

enum NoteMDScan {
    static func linkLabel(_ bytes: [UInt8], from start: Int, upTo end: Int) -> Int? {
        guard start < end, bytes[start] == 91 else { return nil }
        var index = start + 1
        var count = 0
        var nonBlank = false
        while index < end {
            let byte = bytes[index]
            if byte == 93 { return nonBlank && count <= 999 ? index + 1 : nil }
            if byte == 91 { return nil }
            if byte == 92, index + 1 < end, NoteMDByte.isPunctuation(bytes[index + 1]) {
                index += 2; count += 2; nonBlank = true
                continue
            }
            if !NoteMDByte.isWhitespace(byte) { nonBlank = true }
            index += 1
            count += 1
            if count > 999 { return nil }
        }
        return nil
    }

    static func linkDestination(_ bytes: [UInt8], from start: Int, upTo end: Int) -> (String, Int)? {
        guard start < end else { return nil }
        if bytes[start] == 60 {
            var index = start + 1
            while index < end {
                let byte = bytes[index]
                if byte == 62 { return (NoteMDText.unescape(bytes[(start + 1)..<index]), index + 1) }
                if byte == 60 || byte == NoteMDByte.newline || byte == NoteMDByte.carriageReturn { return nil }
                if byte == 92, index + 1 < end, NoteMDByte.isPunctuation(bytes[index + 1]) { index += 2; continue }
                index += 1
            }
            return nil
        }
        var index = start
        var depth = 0
        while index < end {
            let byte = bytes[index]
            if byte == 92, index + 1 < end, NoteMDByte.isPunctuation(bytes[index + 1]) { index += 2; continue }
            if byte == 40 {
                depth += 1
                if depth > 32 { return nil }
            } else if byte == 41 {
                if depth == 0 { break }
                depth -= 1
            } else if byte <= 32 || byte == 127 {
                break
            }
            index += 1
        }
        guard depth == 0 else { return nil }
        return (NoteMDText.unescape(bytes[start..<index]), index)
    }

    static func linkTitle(_ bytes: [UInt8], from start: Int, upTo end: Int) -> (String, Int)? {
        guard start < end else { return nil }
        let open = bytes[start]
        let close: UInt8
        switch open {
        case 34: close = 34
        case 39: close = 39
        case 40: close = 41
        default: return nil
        }
        var index = start + 1
        while index < end {
            let byte = bytes[index]
            if byte == 92, index + 1 < end, NoteMDByte.isPunctuation(bytes[index + 1]) { index += 2; continue }
            if byte == close { return (NoteMDText.unescape(bytes[(start + 1)..<index]), index + 1) }
            if open == 40, byte == 40 { return nil }
            if byte == NoteMDByte.newline, index + 1 < end {
                var probe = index + 1
                while probe < end, NoteMDByte.isSpaceOrTab(bytes[probe]) { probe += 1 }
                if probe < end, bytes[probe] == NoteMDByte.newline { return nil }
            }
            index += 1
        }
        return nil
    }

    static func skipSpacesAndOneNewline(_ bytes: [UInt8], from start: Int, upTo end: Int) -> Int {
        var index = start
        var newlines = 0
        while index < end {
            let byte = bytes[index]
            if NoteMDByte.isSpaceOrTab(byte) { index += 1; continue }
            if byte == NoteMDByte.newline, newlines == 0 { newlines += 1; index += 1; continue }
            break
        }
        return index
    }

    static func reference(_ bytes: [UInt8], from start: Int, upTo end: Int) -> (label: String, reference: NoteMDLinkReference, end: Int)? {
        guard let labelEnd = linkLabel(bytes, from: start, upTo: end), labelEnd < end, bytes[labelEnd] == 58 else { return nil }
        let label = NoteMDByte.string(bytes[(start + 1)..<(labelEnd - 1)])
        if label.hasPrefix("^") { return nil }
        var index = skipSpacesAndOneNewline(bytes, from: labelEnd + 1, upTo: end)
        guard let (destination, destinationEnd) = linkDestination(bytes, from: index, upTo: end) else { return nil }
        if destinationEnd == index, index >= end || bytes[index] != 60 { return nil }
        index = destinationEnd
        let beforeTitle = index
        let titleStart = skipSpacesAndOneNewline(bytes, from: index, upTo: end)
        var title: String?
        if titleStart > beforeTitle, let (value, titleEnd) = linkTitle(bytes, from: titleStart, upTo: end) {
            title = value
            index = titleEnd
        }
        func atLineEnd(_ position: Int) -> Int? {
            var probe = position
            while probe < end, NoteMDByte.isSpaceOrTab(bytes[probe]) { probe += 1 }
            if probe == end { return probe }
            if bytes[probe] == NoteMDByte.newline { return probe + 1 }
            return nil
        }
        var finish = atLineEnd(index)
        if finish == nil, title != nil {
            title = nil
            finish = atLineEnd(beforeTitle)
        }
        guard let finalEnd = finish else { return nil }
        let normalized = NoteMDText.normalizeLabel(label)
        guard !normalized.isEmpty else { return nil }
        return (normalized, NoteMDLinkReference(destination: destination, title: title), finalEnd)
    }
}

package struct NoteMDTag {
    var name: String
    var closing: Bool
    var selfClosing: Bool
    var attributes: [(String, String?)]

    func attribute(_ name: String) -> String?? {
        for (key, value) in attributes where key == name { return .some(value) }
        return nil
    }
}

enum NoteMDHTML {
    static let blockTagNames: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col", "colgroup",
        "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame",
        "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link",
        "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "search", "section",
        "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul",
    ]

    static func tagName(_ bytes: [UInt8], from start: Int, upTo end: Int) -> Int {
        var index = start
        guard index < end, NoteMDByte.isLetter(bytes[index]) else { return start }
        index += 1
        while index < end, NoteMDByte.isAlphanumeric(bytes[index]) || bytes[index] == 45 { index += 1 }
        return index
    }

    static func tag(_ bytes: [UInt8], from start: Int, upTo end: Int) -> (NoteMDTag, Int)? {
        guard start + 1 < end, bytes[start] == 60 else { return nil }
        var index = start + 1
        if index < end, bytes[index] == 47 {
            let nameEnd = tagName(bytes, from: index + 1, upTo: end)
            guard nameEnd > index + 1 else { return nil }
            let name = NoteMDByte.string(bytes[(index + 1)..<nameEnd]).lowercased()
            index = nameEnd
            while index < end, NoteMDByte.isWhitespace(bytes[index]) { index += 1 }
            guard index < end, bytes[index] == 62 else { return nil }
            return (NoteMDTag(name: name, closing: true, selfClosing: false, attributes: []), index + 1)
        }
        let nameEnd = tagName(bytes, from: index, upTo: end)
        guard nameEnd > index else { return nil }
        let name = NoteMDByte.string(bytes[index..<nameEnd]).lowercased()
        index = nameEnd
        var attributes: [(String, String?)] = []
        while true {
            var probe = index
            while probe < end, NoteMDByte.isWhitespace(bytes[probe]) { probe += 1 }
            guard probe < end else { return nil }
            if bytes[probe] == 62 { return (NoteMDTag(name: name, closing: false, selfClosing: false, attributes: attributes), probe + 1) }
            if bytes[probe] == 47 {
                guard probe + 1 < end, bytes[probe + 1] == 62 else { return nil }
                return (NoteMDTag(name: name, closing: false, selfClosing: true, attributes: attributes), probe + 2)
            }
            guard probe > index else { return nil }
            let attributeStart = probe
            let first = bytes[probe]
            guard NoteMDByte.isLetter(first) || first == 95 || first == 58 else { return nil }
            probe += 1
            while probe < end {
                let byte = bytes[probe]
                if NoteMDByte.isAlphanumeric(byte) || byte == 95 || byte == 46 || byte == 58 || byte == 45 { probe += 1 } else { break }
            }
            let attributeName = NoteMDByte.string(bytes[attributeStart..<probe]).lowercased()
            var valueProbe = probe
            while valueProbe < end, NoteMDByte.isWhitespace(bytes[valueProbe]) { valueProbe += 1 }
            if valueProbe < end, bytes[valueProbe] == 61 {
                valueProbe += 1
                while valueProbe < end, NoteMDByte.isWhitespace(bytes[valueProbe]) { valueProbe += 1 }
                guard valueProbe < end else { return nil }
                let quote = bytes[valueProbe]
                if quote == 34 || quote == 39 {
                    var valueEnd = valueProbe + 1
                    while valueEnd < end, bytes[valueEnd] != quote { valueEnd += 1 }
                    guard valueEnd < end else { return nil }
                    attributes.append((attributeName, NoteMDText.unescapeEntities(bytes[(valueProbe + 1)..<valueEnd])))
                    index = valueEnd + 1
                } else {
                    var valueEnd = valueProbe
                    while valueEnd < end {
                        let byte = bytes[valueEnd]
                        if NoteMDByte.isWhitespace(byte) || byte == 34 || byte == 39 || byte == 61 || byte == 60 || byte == 62 || byte == 96 { break }
                        valueEnd += 1
                    }
                    guard valueEnd > valueProbe else { return nil }
                    attributes.append((attributeName, NoteMDText.unescapeEntities(bytes[valueProbe..<valueEnd])))
                    index = valueEnd
                }
            } else {
                attributes.append((attributeName, nil))
                index = probe
            }
        }
    }

    static func inlineHTML(_ bytes: [UInt8], from start: Int, upTo end: Int) -> Int? {
        guard start + 1 < end, bytes[start] == 60 else { return nil }
        let next = bytes[start + 1]
        if next == 33 {
            if start + 3 < end, bytes[start + 2] == 45, bytes[start + 3] == 45 {
                var index = start + 4
                if index < end, bytes[index] == 62 { return index + 1 }
                if index + 1 < end, bytes[index] == 45, bytes[index + 1] == 62 { return index + 2 }
                while index + 2 < end {
                    if bytes[index] == 45, bytes[index + 1] == 45, bytes[index + 2] == 62 { return index + 3 }
                    index += 1
                }
                return nil
            }
            if matches(bytes, at: start + 2, upTo: end, ascii: "[CDATA[") {
                var index = start + 9
                while index + 2 < end {
                    if bytes[index] == 93, bytes[index + 1] == 93, bytes[index + 2] == 62 { return index + 3 }
                    index += 1
                }
                return nil
            }
            if start + 2 < end, NoteMDByte.isLetter(bytes[start + 2]) {
                var index = start + 3
                while index < end, bytes[index] != 62 { index += 1 }
                return index < end ? index + 1 : nil
            }
            return nil
        }
        if next == 63 {
            var index = start + 2
            while index + 1 < end {
                if bytes[index] == 63, bytes[index + 1] == 62 { return index + 2 }
                index += 1
            }
            return nil
        }
        return tag(bytes, from: start, upTo: end)?.1
    }

    static func matches(_ bytes: [UInt8], at start: Int, upTo end: Int, ascii: String, caseInsensitive: Bool = false) -> Bool {
        var index = start
        for byte in ascii.utf8 {
            guard index < end else { return false }
            let actual = caseInsensitive ? NoteMDByte.lowered(bytes[index]) : bytes[index]
            if actual != (caseInsensitive ? NoteMDByte.lowered(byte) : byte) { return false }
            index += 1
        }
        return true
    }

    static func blockStart(_ bytes: [UInt8], from start: Int, upTo end: Int, interruptsParagraph: Bool) -> Int? {
        guard start < end, bytes[start] == 60 else { return nil }
        for name in ["pre", "script", "style", "textarea"] where matches(bytes, at: start + 1, upTo: end, ascii: name, caseInsensitive: true) {
            let after = start + 1 + name.utf8.count
            if after >= end || NoteMDByte.isWhitespace(bytes[after]) || bytes[after] == 62 { return 1 }
        }
        if matches(bytes, at: start, upTo: end, ascii: "<!--") { return 2 }
        if matches(bytes, at: start, upTo: end, ascii: "<?") { return 3 }
        if start + 2 < end, bytes[start + 1] == 33, NoteMDByte.isLetter(bytes[start + 2]) { return 4 }
        if matches(bytes, at: start, upTo: end, ascii: "<![CDATA[") { return 5 }
        var nameStart = start + 1
        if nameStart < end, bytes[nameStart] == 47 { nameStart += 1 }
        let nameEnd = tagName(bytes, from: nameStart, upTo: end)
        if nameEnd > nameStart {
            let name = NoteMDByte.string(bytes[nameStart..<nameEnd]).lowercased()
            if blockTagNames.contains(name) {
                if nameEnd >= end || NoteMDByte.isWhitespace(bytes[nameEnd]) || bytes[nameEnd] == 62
                    || (bytes[nameEnd] == 47 && nameEnd + 1 < end && bytes[nameEnd + 1] == 62) { return 6 }
            }
        }
        guard !interruptsParagraph else { return nil }
        guard let (tag, tagEnd) = tag(bytes, from: start, upTo: end), !["script", "style", "pre"].contains(tag.name) else { return nil }
        var index = tagEnd
        while index < end, NoteMDByte.isSpaceOrTab(bytes[index]) { index += 1 }
        return index >= end ? 7 : nil
    }

    static func blockEnds(_ type: Int, _ bytes: [UInt8], from start: Int, upTo end: Int) -> Bool {
        func contains(_ needle: String, caseInsensitive: Bool = false) -> Bool {
            let pattern = Array(needle.utf8)
            guard end - start >= pattern.count else { return false }
            var index = start
            while index + pattern.count <= end {
                if matches(bytes, at: index, upTo: end, ascii: needle, caseInsensitive: caseInsensitive) { return true }
                index += 1
            }
            return false
        }
        switch type {
        case 1: return contains("</pre>", caseInsensitive: true) || contains("</script>", caseInsensitive: true)
            || contains("</style>", caseInsensitive: true) || contains("</textarea>", caseInsensitive: true)
        case 2: return contains("-->")
        case 3: return contains("?>")
        case 4: return contains(">")
        case 5: return contains("]]>")
        default: return false
        }
    }
}

extension NoteMDText {
    static func unescapeEntities(_ bytes: ArraySlice<UInt8>) -> String {
        guard bytes.contains(38) else { return NoteMDByte.string(bytes) }
        var output: [UInt8] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if bytes[index] == 38, let (decoded, length) = NoteMDEntities.decode(bytes, at: index) {
                output.append(contentsOf: Array(decoded.utf8))
                index += length
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return NoteMDByte.string(output)
    }

    static func escapeAttribute(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "\"": result += "&quot;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\n": result += "&#10;"
            default: result.append(character)
            }
        }
        return result
    }
}
