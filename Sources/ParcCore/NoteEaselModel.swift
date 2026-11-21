import Foundation

enum NoteEaselAddress {
    static let scheme = "parc"
    static let host = "easel"

    static func address(_ id: UUID) -> String { scheme + "://" + host + "/" + id.uuidString.lowercased() }

    static func url(_ id: UUID) -> URL { URL(string: address(id))! }

    static func id(from input: String) -> UUID? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = URLComponents(string: trimmed), value.scheme?.lowercased() == scheme,
              value.host?.lowercased() == host, value.user == nil, value.password == nil, value.port == nil,
              value.query == nil, value.fragment == nil, value.path.hasPrefix("/") else { return nil }
        return UUID(uuidString: String(value.path.dropFirst()))
    }

    static func id(from url: URL) -> UUID? { id(from: url.absoluteString) }

    static func id(of block: NoteBlock) -> UUID? {
        guard block.kind == .easel, let source = block.props.source else { return nil }
        return id(from: source)
    }

    static func title(of block: NoteBlock) -> String {
        let stored = block.props.alt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultTitle : stored
    }

    static let defaultTitle = "Easel"

    static func block(id: UUID, title: String?) -> NoteBlock {
        var props = NoteBlockProps()
        props.source = address(id)
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        props.alt = trimmed.isEmpty ? nil : trimmed
        return NoteBlock(.easel, props: props)
    }
}

enum NoteEaselPageKey {
    static func key(block: UUID, item: UUID) -> UUID {
        var left = block.uuid, right = item.uuid, result = block.uuid
        withUnsafeMutableBytes(of: &result) { out in
            withUnsafeBytes(of: &left) { a in
                withUnsafeBytes(of: &right) { b in
                    for index in 0..<out.count { out[index] = a[index] ^ b[index] }
                }
            }
        }
        return UUID(uuid: result)
    }
}

struct NoteDocumentDrag: Equatable {
    static let pasteboardType = "org.parc.sidebar-document"

    var address: String
    var title: String

    init(address: String, title: String) {
        self.address = address
        self.title = title
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, !first.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        address = String(first)
        title = parts.count > 1 ? String(parts[1]) : ""
    }

    var encoded: String { address + "\n" + title.replacingOccurrences(of: "\n", with: " ") }

    var easelBlock: NoteBlock? { NoteEaselAddress.id(from: address).map { NoteEaselAddress.block(id: $0, title: title) } }
}

struct NoteEaselChoice: Equatable {
    enum Action: Equatable {
        case existing(UUID)
        case create(String)
    }

    var action: Action
    var title: String
    var subtitle: String
}

enum NoteEaselPicker {
    static let limit = 8
    static let untitled = "Untitled Easel"

    struct Candidate: Equatable {
        var id: UUID
        var title: String
        var itemCount: Int
    }

    static func newTitle(for query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitled : String(trimmed.prefix(200))
    }

    static func choices(_ easels: [Candidate], query: String) -> [NoteEaselChoice] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ranked: [Candidate]
        if needle.isEmpty {
            ranked = easels
        } else {
            let scored = easels.enumerated().compactMap { index, easel -> (Int, Int, Candidate)? in
                score(easel.title, needle).map { ($0, index, easel) }
            }
            ranked = scored.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map(\.2)
        }
        var result = ranked.prefix(limit).map { easel in
            NoteEaselChoice(action: .existing(easel.id), title: easel.title.isEmpty ? untitled : easel.title,
                            subtitle: easel.itemCount == 1 ? "1 object" : "\(easel.itemCount) objects")
        }
        let title = newTitle(for: needle)
        result.append(NoteEaselChoice(action: .create(title), title: needle.isEmpty ? "New Easel" : "New Easel “\(title)”",
                                      subtitle: "Start a fresh one right here"))
        return result
    }

    private static func score(_ title: String, _ needle: String) -> Int? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if title.compare(needle, options: options) == .orderedSame { return 0 }
        guard let range = title.range(of: needle, options: options) else { return nil }
        if range.lowerBound == title.startIndex { return 1 }
        let before = title[title.index(before: range.lowerBound)]
        return before.isWhitespace || before.isPunctuation ? 2 : 3
    }
}
