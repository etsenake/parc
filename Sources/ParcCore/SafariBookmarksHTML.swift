import Foundation

enum SafariBookmarksHTML {
    static let depthLimit = 128
    static let nodeLimit = 50_000

    static func parse(_ data: Data) throws -> [BrowserImportBookmark] {
        let bytes: [UInt8]
        if String(decoding: data, as: UTF8.self).utf8.elementsEqual(data) {
            bytes = Array(data)
        } else {
            bytes = Array((String(data: data, encoding: .isoLatin1) ?? "").utf8)
        }
        var reader = Reader(bytes: bytes)
        try reader.run()
        return build(reader.root.children, path: nil)
    }

    private static func build(_ nodes: [Node], path: String?) -> [BrowserImportBookmark] {
        nodes.enumerated().map { index, node in
            let position = path.map { "\($0).\(index)" } ?? "\(index)"
            return BrowserImportBookmark(id: "safari-export/" + position, title: node.title, url: node.url,
                                         children: build(node.children, path: position))
        }
    }

    private final class Node {
        let title: String
        let url: String?
        var children: [Node] = []

        init(title: String, url: String?) {
            self.title = title
            self.url = url
        }
    }

    private struct Tag {
        let name: String
        let closing: Bool
        let href: ArraySlice<UInt8>?
        let end: Int
    }

    private enum Capture {
        case folder
        case link(ArraySlice<UInt8>?)
    }

    private struct Reader {
        let bytes: [UInt8]
        let root = Node(title: "", url: nil)
        private var parents: [Node] = []
        private var lists: [Bool] = []
        private var pending: Node?
        private var capture: Capture?
        private var text: [UInt8] = []
        private var count = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
            parents = [root]
        }

        mutating func run() throws {
            var index = 0
            while index < bytes.count {
                if bytes[index] == UInt8(ascii: "<"), let tag = tag(at: index) {
                    index = tag.end
                    try handle(tag)
                    continue
                }
                let start = index
                index += 1
                while index < bytes.count, bytes[index] != UInt8(ascii: "<") { index += 1 }
                if capture != nil { text.append(contentsOf: bytes[start..<index]) }
            }
            try finishCapture()
        }

        private mutating func handle(_ tag: Tag) throws {
            let structural = ["dt", "dl", "h3", "a"].contains(tag.name)
            if let current = capture {
                switch (current, tag.name, tag.closing) {
                case (.folder, "h3", true), (.link, "a", true):
                    try finishCapture()
                    return
                default:
                    guard structural else { return }
                    try finishCapture()
                }
            }
            switch (tag.name, tag.closing) {
            case ("dt", false):
                pending = nil
            case ("h3", false):
                pending = nil
                capture = .folder
            case ("a", false):
                pending = nil
                capture = .link(tag.href)
            case ("dl", false):
                if let folder = pending {
                    parents.append(folder)
                    lists.append(true)
                } else {
                    lists.append(false)
                }
                pending = nil
            case ("dl", true):
                pending = nil
                if lists.popLast() == true { parents.removeLast() }
            default:
                break
            }
        }

        private mutating func finishCapture() throws {
            guard let current = capture else { return }
            capture = nil
            let title = SafariBookmarksHTML.decode(text[...]).trimmingCharacters(in: .whitespacesAndNewlines)
            text.removeAll(keepingCapacity: true)
            switch current {
            case .folder:
                let folder = try add(Node(title: title, url: nil))
                pending = folder
            case .link(let href):
                guard let href else { return }
                let address = SafariBookmarksHTML.decode(href).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: address), let scheme = url.scheme, !scheme.isEmpty,
                      scheme.lowercased() != "arc" else { return }
                try add(Node(title: title, url: address))
            }
        }

        @discardableResult
        private mutating func add(_ node: Node) throws -> Node {
            guard parents.count <= SafariBookmarksHTML.depthLimit, count < SafariBookmarksHTML.nodeLimit else {
                throw CocoaError(.fileReadTooLarge)
            }
            count += 1
            parents[parents.count - 1].children.append(node)
            return node
        }

        private func isSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
        }

        private func isLetter(_ byte: UInt8) -> Bool {
            (byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "z")
        }

        private func lowered(_ slice: ArraySlice<UInt8>) -> String {
            String(decoding: slice.map { isLetter($0) ? $0 | 0x20 : $0 }, as: UTF8.self)
        }

        private func position(of needle: [UInt8], from start: Int) -> Int? {
            guard needle.count <= bytes.count else { return nil }
            var index = start
            while index + needle.count <= bytes.count {
                if bytes[index..<(index + needle.count)].elementsEqual(needle) { return index }
                index += 1
            }
            return nil
        }

        private func tag(at start: Int) -> Tag? {
            var index = start + 1
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: "!") || bytes[index] == UInt8(ascii: "?") {
                if bytes[index...].starts(with: Array("!--".utf8)) {
                    let close = position(of: Array("-->".utf8), from: index + 3).map { $0 + 3 } ?? bytes.count
                    return Tag(name: "!", closing: false, href: nil, end: close)
                }
                let close = bytes[index...].firstIndex(of: UInt8(ascii: ">")).map { $0 + 1 } ?? bytes.count
                return Tag(name: "!", closing: false, href: nil, end: close)
            }
            let closing = bytes[index] == UInt8(ascii: "/")
            if closing { index += 1 }
            guard index < bytes.count, isLetter(bytes[index]) else { return nil }
            let nameStart = index
            while index < bytes.count, isLetter(bytes[index]) || (bytes[index] >= 0x30 && bytes[index] <= 0x39) { index += 1 }
            let name = lowered(bytes[nameStart..<index])
            var href: ArraySlice<UInt8>?
            while index < bytes.count {
                while index < bytes.count, isSpace(bytes[index]) { index += 1 }
                guard index < bytes.count else { break }
                if bytes[index] == UInt8(ascii: ">") { return Tag(name: name, closing: closing, href: href, end: index + 1) }
                let attributeStart = index
                while index < bytes.count, !isSpace(bytes[index]), bytes[index] != UInt8(ascii: "="),
                      bytes[index] != UInt8(ascii: ">"), bytes[index] != UInt8(ascii: "/") || index == attributeStart { index += 1 }
                let attribute = lowered(bytes[attributeStart..<index])
                while index < bytes.count, isSpace(bytes[index]) { index += 1 }
                guard index < bytes.count, bytes[index] == UInt8(ascii: "=") else { continue }
                index += 1
                while index < bytes.count, isSpace(bytes[index]) { index += 1 }
                let value: ArraySlice<UInt8>
                if index < bytes.count, bytes[index] == UInt8(ascii: "\"") || bytes[index] == UInt8(ascii: "'") {
                    let quote = bytes[index]
                    index += 1
                    let valueStart = index
                    while index < bytes.count, bytes[index] != quote { index += 1 }
                    value = bytes[valueStart..<index]
                    if index < bytes.count { index += 1 }
                } else {
                    let valueStart = index
                    while index < bytes.count, !isSpace(bytes[index]), bytes[index] != UInt8(ascii: ">") { index += 1 }
                    value = bytes[valueStart..<index]
                }
                if attribute == "href", href == nil { href = value }
            }
            return Tag(name: name, closing: closing, href: href, end: bytes.count)
        }
    }

    private static func decode(_ bytes: ArraySlice<UInt8>) -> String {
        let text = String(decoding: bytes, as: UTF8.self)
        guard text.contains("&") else { return text }
        var result = ""
        var rest = text[...]
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let candidate = rest[rest.index(after: ampersand)...]
            if let semicolon = candidate.prefix(16).firstIndex(of: ";"),
               let character = entity(candidate[..<semicolon]) {
                result += character
                rest = candidate[candidate.index(after: semicolon)...]
            } else {
                result += "&"
                rest = candidate
            }
        }
        result += rest
        return result
    }

    private static func entity(_ name: Substring) -> String? {
        switch name.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{00A0}"
        default: break
        }
        guard name.first == "#" else { return nil }
        let digits = name.dropFirst()
        let value: UInt32?
        if digits.first == "x" || digits.first == "X" {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits, radix: 10)
        }
        guard let value, value != 0, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }
}
