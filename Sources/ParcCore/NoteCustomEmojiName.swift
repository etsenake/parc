import Foundation

package enum NoteCustomEmojiName {
    package static let maximumLength = 48

    package static func isNameByte(_ byte: UInt8) -> Bool {
        (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 95 || byte == 45 || byte == 43
    }

    package static func isValid(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard !bytes.isEmpty, bytes.count <= maximumLength, bytes.allSatisfy(isNameByte) else { return false }
        return bytes.contains { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }
    }

    package static func normalized(_ proposed: String) -> String? {
        let folded = proposed.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
            .lowercased()
        var result = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, isNameByte(UInt8(scalar.value)) {
                if pendingDash, !result.isEmpty { result.append("-") }
                pendingDash = false
                result.unicodeScalars.append(scalar)
            } else if scalar == ":" {
                continue
            } else {
                pendingDash = true
            }
        }
        while let last = result.last, last == "-" || last == "_" { result.removeLast() }
        while let first = result.first, first == "-" || first == "_" { result.removeFirst() }
        if result.utf8.count > maximumLength {
            result = String(result.prefix(maximumLength))
            while let last = result.last, last == "-" || last == "_" { result.removeLast() }
        }
        return isValid(result) ? result : nil
    }

    package static func reference(_ name: String) -> String { ":" + name + ":" }

    package static func name(inReference value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, trimmed.hasPrefix(":"), trimmed.hasSuffix(":") else { return nil }
        let name = String(trimmed.dropFirst().dropLast())
        return isValid(name) ? name : nil
    }

    package static func isReference(_ value: String) -> Bool { name(inReference: value) != nil }

    package static func names(in page: NotePage) -> Set<String> {
        var found = Set<String>()
        func scan(_ text: NoteText) {
            for span in text.spans {
                if case .customEmoji(let name)? = span.marks.atom { found.insert(name) }
            }
        }
        for block in page.allBlocks() {
            scan(block.text)
            scan(block.props.caption)
            if let table = block.props.table {
                for row in table.rows { for cell in row { scan(cell) } }
            }
        }
        return found
    }
}
