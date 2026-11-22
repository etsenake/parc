import Foundation

enum NoteFileLineEnding: String, Hashable, Sendable {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"
}

struct NoteFileFormat: Hashable, Sendable {
    var encoding: String.Encoding
    var byteOrderMark: Bool
    var lineEnding: NoteFileLineEnding
    var endsWithNewline: Bool

    static let standard = NoteFileFormat(encoding: .utf8, byteOrderMark: false, lineEnding: .lf, endsWithNewline: true)

    static func empty(for kind: NoteFileKind) -> NoteFileFormat {
        var format = standard
        format.endsWithNewline = kind == .markdown
        return format
    }
}

package struct NoteFileContents: Hashable, Sendable {
    var text: String
    var format: NoteFileFormat
}

package enum NoteFileText {
    static let maximumSize = 20 * 1024 * 1024

    private static let utf8Mark: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LittleMark: [UInt8] = [0xFF, 0xFE]
    private static let utf16BigMark: [UInt8] = [0xFE, 0xFF]
    private static let utf32LittleMark: [UInt8] = [0xFF, 0xFE, 0x00, 0x00]
    private static let utf32BigMark: [UInt8] = [0x00, 0x00, 0xFE, 0xFF]

    static func decode(_ data: Data, kind: NoteFileKind) -> NoteFileContents? {
        guard !data.isEmpty else { return NoteFileContents(text: "", format: .empty(for: kind)) }
        guard let (text, encoding, marked) = decodeText(data) else { return nil }
        let format = NoteFileFormat(encoding: encoding, byteOrderMark: marked,
                                    lineEnding: lineEnding(of: text) ?? .lf, endsWithNewline: endsWithNewline(text))
        return NoteFileContents(text: text, format: format)
    }

    static func encode(_ text: String, format: NoteFileFormat) -> (data: Data, format: NoteFileFormat) {
        var format = format
        var body: Data
        if format.encoding == .utf8 {
            body = Data(text.utf8)
        } else if let encoded = text.data(using: format.encoding, allowLossyConversion: false) {
            body = encoded
        } else {
            format.encoding = .utf8
            format.byteOrderMark = false
            body = Data(text.utf8)
        }
        if format.byteOrderMark, let mark = byteOrderMark(for: format.encoding) { body.insert(contentsOf: mark, at: 0) }
        return (body, format)
    }

    package static func editableText(_ contents: NoteFileContents, kind: NoteFileKind) -> String {
        let normalized = normalizedLineEndings(contents.text)
        if kind == .plainText, contents.format.endsWithNewline, normalized.utf8.last == 10 {
            return String(normalized.dropLast())
        }
        return normalized
    }

    static func fileText(_ body: String, format: NoteFileFormat, kind: NoteFileKind) -> String {
        var text = normalizedLineEndings(body)
        switch kind {
        case .markdown:
            while text.utf8.last == 10 { text.removeLast() }
            if text.isEmpty { return "" }
            if format.endsWithNewline { text.append("\n") }
        case .plainText:
            if format.endsWithNewline { text.append("\n") }
        }
        if format.lineEnding != .lf { text = text.replacingOccurrences(of: "\n", with: format.lineEnding.rawValue) }
        return text
    }

    static func normalizedLineEndings(_ text: String) -> String {
        guard text.utf8.contains(13) else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func lineEnding(of text: String) -> NoteFileLineEnding? {
        var feeds = 0, pairs = 0, returns = 0
        var previousWasReturn = false
        for byte in text.utf8 {
            switch byte {
            case 10:
                if previousWasReturn { pairs += 1; returns -= 1 } else { feeds += 1 }
                previousWasReturn = false
            case 13:
                returns += 1
                previousWasReturn = true
            default:
                previousWasReturn = false
            }
        }
        if feeds == 0 && pairs == 0 && returns == 0 { return nil }
        if pairs > feeds && pairs >= returns { return .crlf }
        if returns > feeds && returns > pairs { return .cr }
        return .lf
    }

    static func endsWithNewline(_ text: String) -> Bool {
        guard let last = text.utf8.last else { return false }
        return last == 10 || last == 13
    }

    private static func byteOrderMark(for encoding: String.Encoding) -> [UInt8]? {
        switch encoding {
        case .utf8: return utf8Mark
        case .utf16LittleEndian: return utf16LittleMark
        case .utf16BigEndian: return utf16BigMark
        case .utf32LittleEndian: return utf32LittleMark
        case .utf32BigEndian: return utf32BigMark
        default: return nil
        }
    }

    private static func decodeText(_ data: Data) -> (String, String.Encoding, Bool)? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: utf8Mark) {
            return (String(decoding: data.dropFirst(utf8Mark.count), as: UTF8.self), .utf8, true)
        }
        for (mark, encoding) in [(utf32LittleMark, String.Encoding.utf32LittleEndian), (utf32BigMark, .utf32BigEndian),
                                 (utf16LittleMark, .utf16LittleEndian), (utf16BigMark, .utf16BigEndian)]
        where bytes.starts(with: mark) {
            guard let text = String(data: data.dropFirst(mark.count), encoding: encoding) else { return nil }
            return (text, encoding, true)
        }
        if data.contains(0) {
            guard let encoding = unmarkedUTF16(data), let text = String(data: data, encoding: encoding) else { return nil }
            return (text, encoding, false)
        }
        let utf8 = String(decoding: data, as: UTF8.self)
        if utf8.utf8.elementsEqual(data) { return (utf8, .utf8, false) }
        if let text = String(data: data, encoding: .windowsCP1252) { return (text, .windowsCP1252, false) }
        guard let text = String(data: data, encoding: .isoLatin1) else { return nil }
        return (text, .isoLatin1, false)
    }

    private static func unmarkedUTF16(_ data: Data) -> String.Encoding? {
        let sample = [UInt8](data.prefix(4096))
        guard sample.count >= 2, data.count % 2 == 0 else { return nil }
        var evenZeros = 0, oddZeros = 0
        for (index, byte) in sample.enumerated() where byte == 0 {
            if index % 2 == 0 { evenZeros += 1 } else { oddZeros += 1 }
        }
        let pairs = sample.count / 2
        if evenZeros == 0 && oddZeros * 5 >= pairs * 2 { return .utf16LittleEndian }
        if oddZeros == 0 && evenZeros * 5 >= pairs * 2 { return .utf16BigEndian }
        return nil
    }
}
