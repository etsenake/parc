import Combine
import Foundation

@MainActor
final class NoteLibrary {
    struct Entry: Hashable, Sendable {
        var url: URL
        var title: String
        var icon: String?
        var snippet: String
        var modifiedAt: Date
        var size: Int
        var foldedTitle: String

        var reference: NoteReference {
            NoteReference(url: url, title: title, icon: icon, modifiedAt: modifiedAt, snippet: snippet)
        }
    }

    struct IndexedContent: Hashable, Sendable {
        var modifiedAt: Date
        var size: Int
        var folded: String
    }

    private static var libraries: [String: NoteLibrary] = [:]
    private static var shallowLibraries: [String: NoteLibrary] = [:]
    static var worker: NoteFileWorker = .index
    static var clock: NoteFileClock = NoteFileSystemClock.shared
    static var refreshDelay: TimeInterval = 0.2
    nonisolated static let maximumDepth = 12
    nonisolated static let maximumNotes = 20_000
    nonisolated static let indexedBytes = 2 * 1024 * 1024
    nonisolated private static let skippedFolders: Set<String> = ["attachments", "node_modules"]
    nonisolated private static let bundleExtensions: Set<String> = [
        "textbundle", "textpack", "app", "bundle", "framework", "plugin", "photoslibrary", "xcodeproj", "xcworkspace", "playground"]

    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Parc Notes", isDirectory: true)
    }

    static func shared(folder: URL) -> NoteLibrary {
        let canonical = NoteFilePaths.canonical(folder)
        let key = NoteFilePaths.identityKey(ofCanonicalPath: canonical.path)
        if let existing = libraries[key] { return existing }
        let library = NoteLibrary(folder: canonical, recursive: true)
        libraries[key] = library
        return library
    }

    static func library(for note: URL) -> NoteLibrary {
        let containing = libraries.values.filter { $0.contains(note) }
        if let deepest = containing.max(by: { $0.folder.path.count < $1.folder.path.count }) { return deepest }
        let parent = NoteFilePaths.canonical(note.deletingLastPathComponent())
        let key = NoteFilePaths.identityKey(ofCanonicalPath: parent.path)
        if let existing = libraries[key] ?? shallowLibraries[key] { return existing }
        let library = NoteLibrary(folder: parent, recursive: false)
        shallowLibraries[key] = library
        return library
    }

    static func trash(_ url: URL) throws {
        let session = NoteFileSession.session(for: url)
        try? session?.flush()
        try NoteFileIO.trash(NoteFilePaths.canonical(url), presenter: session?.presenter)
        session?.noteWasTrashed()
        invalidateLibraries(containing: url)
    }

    static func rename(_ url: URL, to title: String) throws -> URL {
        if let session = NoteFileSession.session(for: url) {
            let renamed = try session.rename(to: title)
            invalidateLibraries(containing: renamed)
            return renamed
        }
        let source = NoteFilePaths.canonical(url)
        guard NoteFilePaths.itemExists(source) else { throw NoteFileError.missing }
        guard let target = try NoteFileNaming.renameTarget(for: source, to: title) else { return source }
        try NoteFileIO.move(source, to: target, presenter: nil)
        let renamed = NoteFilePaths.canonical(target.deletingLastPathComponent()).appendingPathComponent(target.lastPathComponent)
        invalidateLibraries(containing: renamed)
        return renamed
    }

    private static func invalidateLibraries(containing url: URL) {
        for library in Array(libraries.values) + Array(shallowLibraries.values) where library.contains(url) {
            library.folderChanged(paths: [url.path], broad: false)
        }
    }

    let folder: URL
    let isRecursive: Bool
    let changes = PassthroughSubject<Void, Never>()

    private var entries: [String: Entry] = [:]
    private var listingIsCurrent = false
    private var contents: [String: IndexedContent] = [:]
    private var contentIsCurrent = false
    private var isIndexing = false
    private var indexAgain = false
    private var watcher: NoteFileFolderWatcher?
    private var refreshTimer: NoteFileTimer?

    private init(folder: URL, recursive: Bool) {
        self.folder = folder
        isRecursive = recursive
        startWatchingIfNeeded()
    }

    func contains(_ url: URL) -> Bool {
        guard url.isFileURL, NoteFilePaths.contains(folder: folder, item: url) else { return false }
        guard !isRecursive else { return true }
        let parent = NoteFilePaths.canonical(url).deletingLastPathComponent().path
        return NoteFilePaths.identityKey(ofCanonicalPath: parent) == NoteFilePaths.identityKey(ofCanonicalPath: folder.path)
    }

    func createNote(title: String? = nil) throws -> URL {
        try Self.createNote(in: folder, title: title)
    }

    static func createNote(in folder: URL, title: String?) throws -> URL {
        let directory = NoteFilePaths.canonical(folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var base = NoteFileNaming.sanitizedTitle(title ?? "")
        if base.isEmpty { base = NoteFileNaming.untitled }
        for candidate in NoteFileNaming.candidates(in: directory, base: base, pathExtension: "md").prefix(10_000) {
            if NoteFilePaths.itemExists(candidate) { continue }
            do {
                try Data().write(to: candidate, options: .withoutOverwriting)
            } catch CocoaError.fileWriteFileExists {
                continue
            }
            invalidateLibraries(containing: candidate)
            return candidate
        }
        throw NoteFileError.nameTaken(base)
    }

    func notes() throws -> [NoteReference] {
        try ensureListing()
        return Self.newestFirst(Array(entries.values)).map(\.reference)
    }

    func search(_ query: String, limit: Int) -> [NoteReference] {
        guard limit > 0 else { return [] }
        do { try ensureListing() } catch { return [] }
        if !contentIsCurrent { indexContents() }
        return Self.rank(query, entries: Array(entries.values), contents: contents, limit: limit).map(\.reference)
    }

    func snippet(for url: URL) -> String? {
        let file = NoteFilePaths.canonical(url)
        if let entry = entries[file.path] { return entry.snippet }
        guard let kind = NoteFileKind(url: file), NoteFilePaths.isOpenableFile(file) else { return nil }
        return NoteFileSummary.read(file, kind: kind).snippet
    }

    func refresh() {
        folderChanged(paths: [], broad: true)
    }

    private func ensureListing() throws {
        if listingIsCurrent && watcher != nil { return }
        guard NoteFilePaths.isDirectory(folder) else {
            watcher = nil
            entries = [:]
            listingIsCurrent = false
            return
        }
        guard FileManager.default.isReadableFile(atPath: folder.path) else {
            throw NoteFileError.unreadable("Parc doesn’t have permission to look inside “\(folder.lastPathComponent)”.")
        }
        entries = Self.scan(folder: folder, recursive: isRecursive, previous: entries)
        startWatchingIfNeeded()
        listingIsCurrent = watcher != nil
    }

    private func indexContents() {
        guard !isIndexing else {
            indexAgain = true
            return
        }
        isIndexing = true
        let snapshot = Array(entries.values), previous = contents
        Self.worker.perform({ Self.index(snapshot, previous: previous) }) { [weak self] indexed in
            self?.finishIndexing(indexed)
        }
    }

    private func finishIndexing(_ indexed: [String: IndexedContent]) {
        isIndexing = false
        let changed = indexed != contents
        contents = indexed
        if indexAgain {
            indexAgain = false
            contentIsCurrent = false
            try? ensureListing()
            indexContents()
        } else {
            contentIsCurrent = listingIsCurrent
        }
        if changed { changes.send() }
    }

    private func folderChanged(paths: Set<String>, broad: Bool) {
        guard broad || paths.contains(where: isRelevant) else { return }
        listingIsCurrent = false
        contentIsCurrent = false
        if isIndexing { indexAgain = true }
        startWatchingIfNeeded()
        changes.send()
        refreshTimer?.cancel()
        refreshTimer = Self.clock.schedule(after: Self.refreshDelay) { [weak self] in
            guard let self else { return }
            self.refreshTimer = nil
            try? self.ensureListing()
            self.indexContents()
        }
    }

    private func isRelevant(_ path: String) -> Bool {
        let folderPath = folder.path
        if path == folderPath || path == folderPath + "/" { return true }
        guard path.hasPrefix(folderPath + "/") else { return false }
        let relative = path.dropFirst(folderPath.count + 1).split(separator: "/").map(String.init)
        guard let name = relative.last else { return false }
        if !isRecursive && relative.count > 1 { return false }
        if relative.dropLast().contains(where: { $0.hasPrefix(".") || Self.skippedFolders.contains($0.lowercased()) }) { return false }
        if name.hasPrefix(".") { return false }
        let pathExtension = (name as NSString).pathExtension
        return pathExtension.isEmpty || NoteFileKind(pathExtension: pathExtension) != nil
    }

    private func startWatchingIfNeeded() {
        guard watcher == nil, NoteFilePaths.isDirectory(folder) else { return }
        watcher = NoteFileFolderWatcher(folder: folder) { [weak self] paths, broad in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.folderChanged(paths: paths, broad: broad) }
            }
        }
    }

    nonisolated static func scan(folder: URL, recursive: Bool, previous: [String: Entry]) -> [String: Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: options,
                                                              errorHandler: { _, _ in true }) else { return [:] }
        var result: [String: Entry] = [:]
        while let next = enumerator.nextObject() as? URL {
            guard let values = try? next.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if values.isPackage == true || bundleExtensions.contains(next.pathExtension.lowercased())
                    || skippedFolders.contains(next.lastPathComponent.lowercased()) || enumerator.level >= maximumDepth {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, let kind = NoteFileKind(pathExtension: next.pathExtension) else { continue }
            let url = URL(fileURLWithPath: next.path)
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let size = values.fileSize ?? 0
            if let known = previous[url.path], known.modifiedAt == modifiedAt, known.size == size {
                result[url.path] = known
            } else {
                let title = url.deletingPathExtension().lastPathComponent
                let summary = NoteFileSummary.read(url, kind: kind)
                result[url.path] = Entry(url: url, title: title, icon: summary.icon, snippet: summary.snippet,
                                         modifiedAt: modifiedAt, size: size, foldedTitle: fold(title))
            }
            if result.count >= maximumNotes { break }
        }
        return result
    }

    nonisolated static func index(_ entries: [Entry], previous: [String: IndexedContent]) -> [String: IndexedContent] {
        var result: [String: IndexedContent] = [:]
        for entry in entries {
            let key = entry.url.path
            if let known = previous[key], known.modifiedAt == entry.modifiedAt, known.size == entry.size {
                result[key] = known
                continue
            }
            guard let kind = NoteFileKind(url: entry.url),
                  let text = NoteFileSummary.readHead(entry.url, kind: kind, upTo: indexedBytes) else { continue }
            result[key] = IndexedContent(modifiedAt: entry.modifiedAt, size: entry.size, folded: fold(text))
        }
        return result
    }

    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    nonisolated static func newestFirst(_ entries: [Entry]) -> [Entry] {
        entries.sorted { isNewer($0, than: $1) }
    }

    nonisolated static func isNewer(_ first: Entry, than second: Entry) -> Bool {
        if first.modifiedAt != second.modifiedAt { return first.modifiedAt > second.modifiedAt }
        let order = first.title.localizedStandardCompare(second.title)
        if order != .orderedSame { return order == .orderedAscending }
        return first.url.path < second.url.path
    }

    nonisolated static func rank(_ query: String, entries: [Entry], contents: [String: IndexedContent], limit: Int) -> [Entry] {
        let tokens = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return Array(newestFirst(entries).prefix(limit)) }
        let phrase = tokens.joined(separator: " ")
        var scored: [(Entry, Int)] = []
        for entry in entries {
            let title = entry.foldedTitle
            var score = 0
            if title == phrase { score = 1000 }
            else if title.hasPrefix(phrase) { score = 800 }
            else if startsWord(phrase, in: title) { score = 600 }
            else if title.contains(phrase) { score = 400 }
            else if tokens.allSatisfy({ title.contains($0) }) { score = 300 }
            else if let body = contents[entry.url.path]?.folded {
                if body.contains(phrase) { score = 200 }
                else if tokens.allSatisfy({ title.contains($0) || body.contains($0) }) {
                    score = tokens.contains(where: { title.contains($0) }) ? 150 : 100
                }
            }
            if score > 0 { scored.append((entry, score)) }
        }
        scored.sort { first, second in first.1 != second.1 ? first.1 > second.1 : isNewer(first.0, than: second.0) }
        return scored.prefix(limit).map(\.0)
    }

    nonisolated private static func startsWord(_ phrase: String, in title: String) -> Bool {
        var searchStart = title.startIndex
        while let range = title.range(of: phrase, range: searchStart..<title.endIndex) {
            if range.lowerBound == title.startIndex { return true }
            let before = title[title.index(before: range.lowerBound)]
            if !(before.isLetter || before.isNumber) { return true }
            searchStart = title.index(after: range.lowerBound)
        }
        return false
    }
}
