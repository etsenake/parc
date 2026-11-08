import Foundation

///
///
///
///
///
/// may be incomplete; the database is copied to a private folder and read.
enum ArcNotesCache {
    struct Format: Equatable {
        enum Kind: Equatable {
            case bold, italic, underline, strikethrough, heading(Int), bulleted(level: Int), numbered(level: Int)
            ///
            case link(String?)
            case image
        }
        let location: Int
        let length: Int
        let kind: Kind
    }
    struct Note: Equatable {
        let id: String
        let title: String
        let text: String
        let formats: [Format]
        let modifiedAt: Date
    }
    struct Contents: Equatable {
        let notes: [Note]
        ///
        let othersSkipped: Int
    }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/firestore/Arc/bcny-arc-server/main", isDirectory: true)
    }
    static var authStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Arc/StorableAuthState.json")
    }
    static let maximumCacheBytes: Int64 = 2 * 1024 * 1024 * 1024

    static func read(cache: URL, authState: URL) throws -> Contents {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("ParcArcNotesCache-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        var total: Int64 = 0
        for file in try files.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        where ["ldb", "sst", "log"].contains(file.pathExtension) {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            total += Int64(values.fileSize ?? 0)
            guard total <= maximumCacheBytes else { throw ArcNotesExport.Failure.tooLarge }
            //
            try? files.copyItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
        }
        let owner = (try? Data(contentsOf: authState)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { (($0["session"] as? [String: Any])?["user"] as? [String: Any])?["id"] as? String }
        var notes: [Note] = [], others = 0
        for document in try FirestoreCache.documents(in: directory, collection: "documents") {
            if let owner, let creator = document.fields["creatorID"]?.string, creator != owner { others += 1; continue }
            if let note = note(document) { notes.append(note) }
        }
        return Contents(notes: notes.sorted { $0.modifiedAt == $1.modifiedAt ? $0.id < $1.id : $0.modifiedAt < $1.modifiedAt },
                        othersSkipped: others)
    }

    static func note(_ document: FirestoreCache.Document) -> Note? {
        let fields = document.fields
        guard let scratchpad = fields["data"]?["scratchpad"], case .map(let blocks)? = scratchpad["blocks"] else { return nil }
        var text = "", formats: [Format] = []
        var modified = [fields["title"]?["lastUpdatedAt"]?.date, fields["createdAt"]?.date, document.updated].compactMap { $0 }
        //
        let roots = (scratchpad["rootBlocks"]?.array ?? []).compactMap(\.string)
        for id in roots.isEmpty ? blocks.keys.sorted() : roots {
            guard let block = blocks[id], let blockText = block["text"]?.string else { continue }
            if let date = block["lastUpdatedAt"]?.date { modified.append(date) }
            if !text.isEmpty { text += "\n" }
            let offset = (text as NSString).length
            text += blockText
            let limit = (blockText as NSString).length
            for property in block["properties"]?.array ?? [] {
                guard let rich = property["richText"], let range = rich["range"]?.array, range.count == 2,
                      let location = range[0].integer, let length = range[1].integer,
                      location >= 0, length >= 0, location <= Int64(limit), length <= Int64(limit) - location,
                      case .map(let value)? = rich["value"], value.count == 1, let (name, payload) = value.first,
                      let kind = kind(name, payload) else { continue }
                formats.append(Format(location: offset + Int(location), length: Int(length), kind: kind))
            }
        }
        let title = fields["title"]?["value"]?.string ?? fields["title"]?.string ?? ""
        return Note(id: fields["id"]?.string ?? document.path, title: title, text: text, formats: formats,
                    modifiedAt: modified.max() ?? Date(timeIntervalSince1970: 0))
    }

    private static func kind(_ name: String, _ payload: FirestoreCache.Value) -> Format.Kind? {
        let level = max(1, min(7, Int(payload["level"]?.integer ?? 1)))
        switch name {
        case "bold": return .bold
        case "italic": return .italic
        case "underline": return .underline
        case "strikethrough": return .strikethrough
        case "h1": return .heading(1)
        case "h2": return .heading(2)
        case "h3": return .heading(3)
        case "unorderedList": return .bulleted(level: level)
        case "orderedList": return .numbered(level: level)
        case "hyperlink": return .link(nil)
        case "formattedHyperlink": return .link(payload["url"]?.string)
        case "image": return .image
        default: return nil
        }
    }
}
