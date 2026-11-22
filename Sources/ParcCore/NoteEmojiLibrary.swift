import Combine
import Foundation

package struct NoteCustomEmoji: Hashable, Sendable {
    package var name: String
    var file: String
    var aliases: [String] = []

    package var reference: String { NoteCustomEmojiName.reference(name) }

    init(name: String, file: String, aliases: [String] = []) {
        self.name = name
        self.file = file
        self.aliases = aliases
    }
}

package enum NoteEmojiLibraryError: Error, LocalizedError, Equatable {
    case invalidName
    case nameTaken(String)
    case missing
    case unreadableImage
    case unwritable(String)

    package var errorDescription: String? {
        switch self {
        case .invalidName: return "Emoji names need at least one letter or number."
        case .nameTaken(let name): return "There’s already an emoji called :\(name): here."
        case .missing: return "That emoji isn’t in this folder anymore."
        case .unreadableImage: return "That file doesn’t look like an image Parc can use."
        case .unwritable(let detail): return "Parc couldn’t save that emoji. \(detail)"
        }
    }
}

@MainActor
package final class NoteEmojiLibrary {
    private struct Manifest: Codable {
        struct Entry: Codable {
            var name: String
            var file: String
            var aliases: [String]?

            init(name: String, file: String, aliases: [String]? = nil) {
                self.name = name
                self.file = file
                self.aliases = aliases
            }
        }
        var version = 1
        var emoji: [Entry] = []
    }

    private struct Stamp: Equatable {
        var manifest: Date?
        var folder: Date?

        init(manifest: Date? = nil, folder: Date? = nil) {
            self.manifest = manifest
            self.folder = folder
        }
    }

    nonisolated static let folderName = ".parc"
    nonisolated static let emojiFolderName = "emoji"
    nonisolated static let manifestName = "emoji.json"
    nonisolated static let imageExtensions: Set<String> = ["png", "gif", "jpg", "jpeg", "webp", "heic", "tif", "tiff"]

    static var anyChange: PassthroughSubject<NoteEmojiLibrary, Never> { NoteFiles.shared.emojiChanges }

    nonisolated static func directory(in root: URL) -> URL {
        root.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(emojiFolderName, isDirectory: true)
    }

    package static func library(for note: URL) -> NoteEmojiLibrary { NoteFiles.shared.emojiLibrary(for: note) }

    package static func library(root: URL) -> NoteEmojiLibrary { NoteFiles.shared.emojiLibrary(root: root) }

    nonisolated static func root(for note: URL, notesFolders: [URL]) -> URL {
        let start = NoteFilePaths.canonical(note.deletingLastPathComponent())
        let boundary = notesFolders.map { NoteFilePaths.canonical($0) }
            .filter { start.path == $0.path || start.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }
            .max { $0.path.count < $1.path.count }
        let home = NoteFilePaths.canonical(FileManager.default.homeDirectoryForCurrentUser).path
        var current = start
        while true {
            if FileManager.default.fileExists(atPath: directory(in: current).path) { return current }
            if let boundary, current.path == boundary.path { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || current.path == home || (boundary == nil && parent.path == home) { break }
            current = parent
        }
        return boundary ?? start
    }

    let root: URL
    package let changes = PassthroughSubject<Void, Never>()
    private let announcements: PassthroughSubject<NoteEmojiLibrary, Never>
    package private(set) var emoji: [NoteCustomEmoji] = []
    package private(set) var revision = 0
    private var byName: [String: Int] = [:]
    private var byAlias: [String: Int] = [:]
    private var stamp = Stamp()

    convenience init(root: URL) {
        self.init(root: root, announcing: NoteFiles.shared.emojiChanges)
    }

    init(root: URL, announcing announcements: PassthroughSubject<NoteEmojiLibrary, Never>) {
        self.root = root
        self.announcements = announcements
        reload()
    }

    var directory: URL { Self.directory(in: root) }
    var manifestURL: URL { directory.appendingPathComponent(Self.manifestName) }
    package var isEmpty: Bool { emoji.isEmpty }

    var names: Set<String> { Set(byName.keys).union(byAlias.keys) }

    package func emoji(named name: String) -> NoteCustomEmoji? {
        if let index = byName[name] ?? byAlias[name] { return emoji[index] }
        return nil
    }

    package func emoji(forReference value: String) -> NoteCustomEmoji? {
        NoteCustomEmojiName.name(inReference: value).flatMap(emoji(named:))
    }

    package func imageURL(named name: String) -> URL? {
        emoji(named: name).map { directory.appendingPathComponent($0.file, isDirectory: false) }
    }

    package func imageURL(for entry: NoteCustomEmoji) -> URL {
        directory.appendingPathComponent(entry.file, isDirectory: false)
    }

    package func search(_ query: String, limit: Int = .max) -> [NoteCustomEmoji] {
        let folded = NoteEmojiCatalog.fold(query).trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines))
            .replacingOccurrences(of: " ", with: "-")
        guard limit > 0 else { return [] }
        guard !folded.isEmpty else { return Array(emoji.prefix(limit)) }
        var ranked: [(rank: Int, entry: NoteCustomEmoji)] = []
        for entry in emoji {
            let words = entry.name.split { $0 == "-" || $0 == "_" || $0 == "+" }.map(String.init)
            let rank: Int?
            if entry.name == folded { rank = 0 }
            else if entry.name.hasPrefix(folded) { rank = 1 }
            else if words.contains(where: { $0.hasPrefix(folded) }) { rank = 2 }
            else if entry.aliases.contains(where: { $0.hasPrefix(folded) }) { rank = 3 }
            else if entry.name.contains(folded) { rank = 4 }
            else { rank = nil }
            if let rank { ranked.append((rank, entry)) }
        }
        ranked.sort { ($0.rank, $0.entry.name) < ($1.rank, $1.entry.name) }
        return ranked.prefix(limit).map(\.entry)
    }

    package func uniqueName(for proposed: String) -> String? {
        guard let base = NoteCustomEmojiName.normalized(proposed) else { return nil }
        guard byName[base] != nil else { return base }
        var number = 2
        while true {
            let suffix = "-\(number)"
            let trimmed = String(base.prefix(NoteCustomEmojiName.maximumLength - suffix.count))
            let candidate = trimmed + suffix
            if byName[candidate] == nil { return candidate }
            number += 1
        }
    }

    @discardableResult
    package func add(png data: Data, name proposed: String) throws -> NoteCustomEmoji {
        refreshIfNeeded()
        guard let name = NoteCustomEmojiName.normalized(proposed) else { throw NoteEmojiLibraryError.invalidName }
        guard byName[name] == nil else { throw NoteEmojiLibraryError.nameTaken(name) }
        guard !data.isEmpty else { throw NoteEmojiLibraryError.unreadableImage }
        let file = freeFileName(for: name, extension: "png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        } catch {
            throw NoteEmojiLibraryError.unwritable(error.localizedDescription)
        }
        var next = emoji.map { entry -> NoteCustomEmoji in
            var value = entry
            value.aliases.removeAll { $0 == name }
            return value
        }
        let entry = NoteCustomEmoji(name: name, file: file)
        next.append(entry)
        do { try commit(next) } catch {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            throw error
        }
        return entry
    }

    @discardableResult
    package func rename(_ name: String, to proposed: String) throws -> NoteCustomEmoji {
        refreshIfNeeded()
        guard let index = byName[name] else { throw NoteEmojiLibraryError.missing }
        guard let target = NoteCustomEmojiName.normalized(proposed) else { throw NoteEmojiLibraryError.invalidName }
        guard target != name else { return emoji[index] }
        guard byName[target] == nil else { throw NoteEmojiLibraryError.nameTaken(target) }
        var entry = emoji[index]
        let source = directory.appendingPathComponent(entry.file)
        let pathExtension = (entry.file as NSString).pathExtension.lowercased()
        let file = freeFileName(for: target, extension: pathExtension.isEmpty ? "png" : pathExtension)
        var moved = false
        if FileManager.default.fileExists(atPath: source.path) {
            do {
                try FileManager.default.moveItem(at: source, to: directory.appendingPathComponent(file))
                moved = true
            } catch {
                throw NoteEmojiLibraryError.unwritable(error.localizedDescription)
            }
        }
        if moved { entry.file = file }
        entry.aliases = (entry.aliases + [name]).filter { $0 != target }
        entry.name = target
        var next = emoji.map { other -> NoteCustomEmoji in
            var value = other
            value.aliases.removeAll { $0 == target }
            return value
        }
        next[index] = entry
        do { try commit(next) } catch {
            if moved { try? FileManager.default.moveItem(at: directory.appendingPathComponent(file), to: source) }
            throw error
        }
        return entry
    }

    package func remove(_ name: String, trash: (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }) throws {
        refreshIfNeeded()
        guard let index = byName[name] else { throw NoteEmojiLibraryError.missing }
        let entry = emoji[index]
        var next = emoji
        next.remove(at: index)
        try commit(next)
        let image = directory.appendingPathComponent(entry.file)
        guard FileManager.default.fileExists(atPath: image.path) else { return }
        do { try trash(image) } catch {
            try? FileManager.default.removeItem(at: image)
        }
        refreshStamp()
    }

    package func refreshIfNeeded() {
        guard currentStamp() != stamp else { return }
        let before = emoji
        reload()
        if emoji != before { announce() }
    }

    private func reload() {
        stamp = currentStamp()
        var entries: [NoteCustomEmoji] = []
        var seen = Set<String>()
        var files = Set<String>()
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let present = Set(listing)
        if let data = try? Data(contentsOf: manifestURL), let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
            for item in manifest.emoji where NoteCustomEmojiName.isValid(item.name) && !seen.contains(item.name) {
                guard present.contains(item.file), !item.file.contains("/") else { continue }
                seen.insert(item.name)
                files.insert(item.file)
                entries.append(NoteCustomEmoji(name: item.name, file: item.file, aliases: (item.aliases ?? []).filter(NoteCustomEmojiName.isValid)))
            }
        }
        for file in listing.sorted() where !files.contains(file) && !file.hasPrefix(".") {
            let stem = (file as NSString).deletingPathExtension
            guard Self.imageExtensions.contains((file as NSString).pathExtension.lowercased()),
                  NoteCustomEmojiName.isValid(stem), !seen.contains(stem) else { continue }
            seen.insert(stem)
            entries.append(NoteCustomEmoji(name: stem, file: file))
        }
        apply(entries)
    }

    private func apply(_ entries: [NoteCustomEmoji]) {
        var taken = Set(entries.map(\.name))
        var cleaned: [NoteCustomEmoji] = []
        for var entry in entries {
            entry.aliases = entry.aliases.filter { taken.insert($0).inserted }
            cleaned.append(entry)
        }
        emoji = cleaned.sorted { $0.name < $1.name }
        byName = [:]
        byAlias = [:]
        for (index, entry) in emoji.enumerated() {
            byName[entry.name] = index
            for alias in entry.aliases { byAlias[alias] = index }
        }
    }

    private func commit(_ entries: [NoteCustomEmoji]) throws {
        let manifest = Manifest(emoji: entries.sorted { $0.name < $1.name }.map {
            Manifest.Entry(name: $0.name, file: $0.file, aliases: $0.aliases.isEmpty ? nil : $0.aliases)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        } catch {
            throw NoteEmojiLibraryError.unwritable(error.localizedDescription)
        }
        apply(entries)
        refreshStamp()
        announce()
    }

    private func announce() {
        revision += 1
        changes.send()
        announcements.send(self)
    }

    private func refreshStamp() { stamp = currentStamp() }

    private func currentStamp() -> Stamp {
        func modified(_ url: URL) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        return Stamp(manifest: modified(manifestURL), folder: modified(directory))
    }

    private func freeFileName(for name: String, extension pathExtension: String) -> String {
        var candidate = name + "." + pathExtension
        var number = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = name + "-\(number)." + pathExtension
            number += 1
        }
        return candidate
    }
}

extension NoteCustomEmojiName {
    static func upgrading(_ text: NoteText, names: Set<String>) -> NoteText {
        guard !names.isEmpty, text.string.contains(":") else { return text }
        var result = NoteText()
        var changed = false
        let string = text.string as NSString
        for run in text.runs() {
            let piece = string.substring(with: NSRange(location: run.range.lowerBound, length: run.range.count))
            guard run.marks.atom == nil, !run.marks.code, piece.contains(":") else {
                result.append(NoteText(piece, marks: run.marks))
                continue
            }
            let bytes = Array(piece.utf8)
            var start = 0
            var index = 0
            while index < bytes.count {
                if bytes[index] == 58, let close = NoteMDInlineParser.customEmojiEnd(bytes, at: index, upTo: bytes.count, names: names) {
                    if index > start { result.append(NoteText(String(decoding: bytes[start..<index], as: UTF8.self), marks: run.marks)) }
                    var marks = run.marks
                    marks.atom = .customEmoji(String(decoding: bytes[(index + 1)..<(close - 1)], as: UTF8.self))
                    result.append(NoteText(NoteAtom.character, marks: marks))
                    index = close
                    start = close
                    changed = true
                } else {
                    index += 1
                }
            }
            if start < bytes.count { result.append(NoteText(String(decoding: bytes[start...], as: UTF8.self), marks: run.marks)) }
        }
        return changed ? result : text
    }

    static func upgrading(_ page: NotePage, names: Set<String>) -> NotePage {
        guard !names.isEmpty else { return page }
        func map(_ blocks: [NoteBlock]) -> [NoteBlock] {
            blocks.map { block in
                var value = block
                let text = upgrading(block.text, names: names)
                if text != block.text { value.text = text }
                let caption = upgrading(block.props.caption, names: names)
                if caption != block.props.caption { value.props.caption = caption }
                if var table = block.props.table {
                    let rows = table.rows.map { $0.map { upgrading($0, names: names) } }
                    if rows != table.rows {
                        table.rows = rows
                        value.props.table = table
                    }
                }
                if !block.children.isEmpty {
                    let children = map(block.children)
                    if children != block.children { value.children = children }
                }
                return value
            }
        }
        let blocks = map(page.blocks)
        guard blocks != page.blocks else { return page }
        var next = page
        next.blocks = blocks
        return next
    }
}

extension NoteFiles {
    func emojiLibrary(for note: URL) -> NoteEmojiLibrary {
        emojiLibrary(root: NoteEmojiLibrary.root(for: note, notesFolders: notesFolders))
    }

    package func emojiLibrary(root: URL) -> NoteEmojiLibrary {
        let canonical = NoteFilePaths.canonical(root)
        let key = NoteFilePaths.identityKey(ofCanonicalPath: canonical.path)
        if let existing = emojiLibraries[key] {
            existing.refreshIfNeeded()
            return existing
        }
        let library = NoteEmojiLibrary(root: canonical, announcing: emojiChanges)
        emojiLibraries[key] = library
        return library
    }
}
