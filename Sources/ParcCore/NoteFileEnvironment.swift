import Foundation

@MainActor
final class NoteFileEnvironment: NoteEnvironment {
    private static let webSchemes: Set<String> = ["http", "https"]
    private static let knownSchemes: Set<String> = ["http", "https", "file", "mailto", "data", "tel", "ftp", "parc", "about", "blob"]

    private(set) var documentURL: URL?
    let isPlainText: Bool
    var now: () -> Date = Date.init

    init(documentURL: URL, isPlainText: Bool) {
        self.documentURL = documentURL
        self.isPlainText = isPlainText
    }

    func move(to url: URL) { documentURL = url }

    var folder: URL? { documentURL?.deletingLastPathComponent() }

    func resolve(_ source: String) -> URL? {
        var value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.hasPrefix("<"), value.hasSuffix(">") { value = String(value.dropFirst().dropLast()) }
        guard !value.isEmpty else { return nil }
        if let scheme = Self.scheme(of: value) {
            let remainder = value.dropFirst(scheme.count + 1)
            if Self.webSchemes.contains(scheme) { return Self.webURL(value) }
            if scheme == "file" { return Self.fileURL(value) }
            if Self.knownSchemes.contains(scheme) || remainder.hasPrefix("//") { return Self.webURL(value) }
            if let local = localURL(value), NoteFilePaths.itemExists(local) { return local }
            return Self.webURL(value)
        }
        if value.hasPrefix("//") { return Self.webURL("https:" + value) }
        if value.hasPrefix("#") {
            guard let documentURL else { return nil }
            return Self.attaching(fragment: String(value.dropFirst()), to: documentURL)
        }
        return localURL(value)
    }

    func importAsset(from url: URL) throws -> String {
        guard url.isFileURL else { return url.absoluteString }
        guard let documentURL else { throw NoteFileError.missing }
        return try NoteAttachments.importFile(url, into: documentURL)
    }

    func importAsset(data: Data, fileExtension: String, suggestedName: String?) throws -> String {
        guard let documentURL else { throw NoteFileError.missing }
        return try NoteAttachments.importData(data, fileExtension: fileExtension, suggestedName: suggestedName,
                                              into: documentURL, date: now())
    }

    func searchNotes(_ query: String, limit: Int) -> [NoteReference] {
        guard let documentURL, limit > 0 else { return [] }
        let own = NoteFilePaths.key(for: documentURL)
        let found = NoteLibrary.library(for: documentURL).search(query, limit: limit + 1)
        return Array(found.filter { NoteFilePaths.key(for: $0.url) != own }.prefix(limit))
    }

    func linkTarget(for note: URL) -> String {
        guard note.isFileURL, let folder else { return note.absoluteString }
        let file = URL(fileURLWithPath: note.path)
        guard let relative = NoteFilePaths.relativePath(from: folder, to: file) else { return file.absoluteString }
        guard let fragment = note.fragment, !fragment.isEmpty else { return relative }
        return relative + "#" + NoteFilePaths.encodedSegment(fragment)
    }

    func resolveNoteLink(_ target: String) -> URL? {
        guard let resolved = resolve(target), resolved.isFileURL else { return nil }
        let file = NoteFilePaths.canonical(URL(fileURLWithPath: resolved.path))
        if NoteFileKind(url: file) != nil { return file }
        let markdown = URL(fileURLWithPath: file.path + ".md")
        return NoteFilePaths.itemExists(markdown) ? markdown : nil
    }

    private func localURL(_ value: String) -> URL? {
        let (path, fragment) = Self.splitFragment(value)
        let decoded = path.removingPercentEncoding ?? path
        let file: URL
        if decoded.hasPrefix("/") {
            file = NoteFilePaths.canonical(URL(fileURLWithPath: decoded))
        } else if decoded == "~" || decoded.hasPrefix("~/") {
            file = NoteFilePaths.canonical(URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath))
        } else {
            guard let folder else { return nil }
            file = decoded.isEmpty ? (documentURL ?? folder) : NoteFilePaths.canonical(folder.appendingPathComponent(decoded))
        }
        guard let fragment, !fragment.isEmpty else { return file }
        return Self.attaching(fragment: fragment, to: file)
    }

    private static func splitFragment(_ value: String) -> (String, String?) {
        guard let hash = value.firstIndex(of: "#") else { return (value, nil) }
        let fragment = String(value[value.index(after: hash)...])
        return (String(value[..<hash]), fragment.removingPercentEncoding ?? fragment)
    }

    private static func attaching(fragment: String, to url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.fragment = fragment
        return components.url ?? url
    }

    private static func scheme(of value: String) -> String? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let candidate = value[..<colon]
        guard candidate.count >= 2, let first = candidate.unicodeScalars.first, first.isASCII,
              CharacterSet.letters.contains(first),
              candidate.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+.-".unicodeScalars.contains($0)) })
        else { return nil }
        return candidate.lowercased()
    }

    private static func webURL(_ value: String) -> URL? {
        if let url = URL(string: value) { return url }
        let allowed = CharacterSet.urlQueryAllowed.union(.urlPathAllowed).union(CharacterSet(charactersIn: "#%"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed).flatMap(URL.init(string:))
    }

    private static func fileURL(_ value: String) -> URL? {
        if let url = URL(string: value), url.isFileURL { return NoteFilePaths.canonical(url) }
        let path = String(value.dropFirst("file://".count))
        return NoteFilePaths.canonical(URL(fileURLWithPath: path.removingPercentEncoding ?? path))
    }
}
