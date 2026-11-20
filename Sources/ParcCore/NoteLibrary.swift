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
        var summarized = true

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
    nonisolated static let quickListBudget = 1_000
    nonisolated static let indexedBytes = 2 * 1024 * 1024
    nonisolated private static let skippedFolders: Set<String> = ["attachments", "node_modules"]
    nonisolated private static let bundleExtensions: Set<String> = [
        "textbundle", "textpack", "app", "bundle", "framework", "plugin", "photoslibrary", "xcodeproj", "xcworkspace", "playground"]

    static let opened = PassthroughSubject<NoteLibrary, Never>()

    static var known: [NoteLibrary] { Array(libraries.values) + Array(shallowLibraries.values) }

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
        opened.send(library)
        return library
    }

    static func browsing(_ folder: URL) -> NoteLibrary {
        let canonical = NoteFilePaths.canonical(folder)
        let key = NoteFilePaths.identityKey(ofCanonicalPath: canonical.path)
        if let existing = libraries[key] ?? shallowLibraries[key] { return existing }
        let library = NoteLibrary(folder: canonical, recursive: false)
        shallowLibraries[key] = library
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
        opened.send(library)
        return library
    }

    static func trash(_ url: URL) throws {
        let session = NoteFileSession.session(for: url)
        try? session?.flush()
        let file = NoteFilePaths.canonical(url)
        try NoteFileIO.trash(file, presenter: session?.presenter)
        session?.noteWasTrashed()
        invalidateLibraries(containing: [file])
    }

    static func rename(_ url: URL, to title: String) throws -> URL {
        if let session = NoteFileSession.session(for: url) {
            let original = session.url
            let renamed = try session.rename(to: title)
            invalidateLibraries(containing: [original, renamed])
            return renamed
        }
        let source = NoteFilePaths.canonical(url)
        guard NoteFilePaths.itemExists(source) else { throw NoteFileError.missing }
        guard let target = try NoteFileNaming.renameTarget(for: source, to: title) else { return source }
        try NoteFileIO.move(source, to: target, presenter: nil)
        let renamed = NoteFilePaths.canonical(target.deletingLastPathComponent()).appendingPathComponent(target.lastPathComponent)
        invalidateLibraries(containing: [source, renamed])
        noteDidMove(from: source, to: renamed)
        return renamed
    }

    static func noteDidMove(from source: URL, to destination: URL) {
        NoteBacklinkIndex.shared.noteMoved(from: source, to: destination)
    }

    static func filesRewritten(_ urls: [URL]) {
        invalidateLibraries(containing: urls.map(NoteFilePaths.canonical))
    }

    private static func invalidateLibraries(containing urls: [URL]) {
        for library in Array(libraries.values) + Array(shallowLibraries.values) {
            let inside = urls.filter(library.contains)
            if !inside.isEmpty { library.filesChanged(inside) }
        }
    }

    let folder: URL
    let isRecursive: Bool
    let changes = PassthroughSubject<Void, Never>()
    let listingChanges = PassthroughSubject<Void, Never>()

    private var entries: [String: Entry] = [:]
    private var hasListing = false
    private var listingIsCurrent = false
    private var listingGeneration = 0
    private var isScanning = false
    private var scanAgain = false
    private var touchedWhileScanning: Set<String> = []
    private var contents: [String: IndexedContent] = [:]
    private var contentIsCurrent = false
    private var wantsContents = false
    private var isIndexing = false
    private var indexAgain = false
    private var watcher: NoteFileFolderWatcher?
    private var refreshTimer: NoteFileTimer?

    private init(folder: URL, recursive: Bool) {
        self.folder = folder
        isRecursive = recursive
        startWatchingIfNeeded()
        if watcher != nil, FileManager.default.isReadableFile(atPath: folder.path) { scan() }
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
            invalidateLibraries(containing: [candidate])
            return candidate
        }
        throw NoteFileError.nameTaken(base)
    }

    func notes() throws -> [NoteReference] {
        try refreshListing()
        return Self.newestFirst(Array(entries.values)).map(\.reference)
    }

    func search(_ query: String, limit: Int) -> [NoteReference] {
        guard limit > 0 else { return [] }
        do { try refreshListing() } catch { return [] }
        wantsContents = true
        if !contentIsCurrent { indexContents() }
        return Self.rank(query, entries: Array(entries.values), contents: contents, limit: limit).map(\.reference)
    }

    func notes(withSyncedOriginal anchor: String) -> [URL] {
        syncedNotes(matching: ["synced id=\"" + anchor + "\""])
    }

    func notes(mentioningSynced anchor: String) -> [URL] {
        syncedNotes(matching: ["synced id=\"" + anchor + "\"", "#" + anchor + "\""])
    }

    private func syncedNotes(matching needles: [String]) -> [URL] {
        guard !needles.isEmpty else { return [] }
        do { try refreshListing() } catch { return [] }
        wantsContents = true
        if !contentIsCurrent { indexContents() }
        let folded = needles.map(Self.fold)
        let marker = Self.fold("parc synced")
        return entries.values.compactMap { entry -> URL? in
            guard let body = contents[entry.url.path]?.folded, body.contains(marker), folded.contains(where: { body.contains($0) }) else { return nil }
            return entry.url
        }.sorted { $0.path < $1.path }
    }

    func snippet(for url: URL) -> String? {
        let file = NoteFilePaths.canonical(url)
        if let entry = entries[file.path], entry.summarized { return entry.snippet }
        guard let kind = NoteFileKind(url: file), NoteFilePaths.isOpenableFile(file) else { return nil }
        return NoteFileSummary.read(file, kind: kind).snippet
    }

    func refresh() {
        folderChanged(events: [], broad: true)
    }

    func listedEntries() -> [Entry]? {
        if !(listingIsCurrent && watcher != nil) {
            guard NoteFilePaths.isDirectory(folder) else { return hasListing ? Array(entries.values) : [] }
            startWatchingIfNeeded()
            if !isScanning && refreshTimer == nil { scan() }
        }
        return hasListing ? Array(entries.values) : nil
    }

    private func refreshListing() throws {
        if listingIsCurrent && watcher != nil { return }
        guard NoteFilePaths.isDirectory(folder) else {
            forgetListing()
            return
        }
        guard FileManager.default.isReadableFile(atPath: folder.path) else {
            throw NoteFileError.unreadable("Parc doesn’t have permission to look inside “\(folder.lastPathComponent)”.")
        }
        startWatchingIfNeeded()
        if !hasListing {
            entries = Self.list(folder: folder, recursive: false, previous: entries, budget: Self.quickListBudget)
            hasListing = true
        }
        if !isScanning { scan() }
    }

    private func forgetListing() {
        watcher = nil
        listingGeneration += 1
        entries = [:]
        hasListing = false
        listingIsCurrent = false
        contentIsCurrent = false
    }

    private func scan() {
        isScanning = true
        scanAgain = false
        touchedWhileScanning = []
        let folder = folder, recursive = isRecursive, previous = entries, generation = listingGeneration
        Self.worker.perform({ Self.scan(folder: folder, recursive: recursive, previous: previous) }) { [weak self] scanned in
            self?.finishScan(scanned, generation: generation)
        }
    }

    private func finishScan(_ scanned: [String: Entry], generation: Int) {
        isScanning = false
        guard generation == listingGeneration else { return }
        var next = scanned
        for path in touchedWhileScanning {
            if let current = entries[path], let fresh = scanned[path], fresh.modifiedAt == current.modifiedAt, fresh.size == current.size {
                continue
            }
            next[path] = entries[path]
        }
        touchedWhileScanning = []
        let changed = next != entries, wasListed = hasListing
        entries = next
        hasListing = true
        if changed { contentIsCurrent = false }
        if scanAgain { scan() } else { listingIsCurrent = watcher != nil }
        if wantsContents && !contentIsCurrent { indexContents() }
        if changed || !wasListed { listingChanges.send() }
        if changed && wasListed { changes.send() }
    }

    private func filesChanged(_ urls: [URL]) {
        let files = urls.map(NoteFilePaths.canonical).filter { isRelevant(NoteFolderEvent(path: $0.path)) }
        var announce = !hasListing
        if hasListing {
            var next = entries
            var departed: [Entry] = []
            var arrived: [Entry] = []
            for file in files {
                if isScanning { touchedWhileScanning.insert(file.path) }
                if let entry = Self.entry(at: file, previous: entries[file.path]) {
                    arrived.append(entry)
                } else if let gone = next.removeValue(forKey: file.path) {
                    departed.append(gone)
                }
            }
            for entry in arrived {
                next[entry.url.path] = Self.carryingSummary(into: entry, from: departed)
            }
            if next != entries {
                entries = next
                announce = true
            }
        }
        folderChanged(events: files.map { NoteFolderEvent(path: $0.path) }, broad: false)
        if announce {
            listingChanges.send()
            changes.send()
        }
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
            indexContents()
        } else {
            contentIsCurrent = listingIsCurrent && !isScanning
        }
        if changed { changes.send() }
    }

    private func folderChanged(events: [NoteFolderEvent], broad: Bool) {
        guard broad || events.contains(where: isRelevant) else { return }
        listingIsCurrent = false
        contentIsCurrent = false
        if isScanning { scanAgain = true }
        if isIndexing { indexAgain = true }
        startWatchingIfNeeded()
        refreshTimer?.cancel()
        refreshTimer = Self.clock.schedule(after: Self.refreshDelay) { [weak self] in
            guard let self else { return }
            self.refreshTimer = nil
            let hadEntries = !self.entries.isEmpty
            try? self.refreshListing()
            if hadEntries && !self.hasListing {
                self.listingChanges.send()
                self.changes.send()
            }
        }
    }

    private func isRelevant(_ event: NoteFolderEvent) -> Bool {
        let path = event.path, folderPath = folder.path
        if path == folderPath || path == folderPath + "/" { return true }
        guard path.hasPrefix(folderPath + "/") else { return false }
        let relative = path.dropFirst(folderPath.count + 1).split(separator: "/").map(String.init)
        guard let name = relative.last else { return false }
        if !isRecursive && relative.count > 1 { return false }
        if relative.dropLast().contains(where: { $0.hasPrefix(".") || Self.skippedFolders.contains($0.lowercased()) }) { return false }
        if name.hasPrefix(".") { return false }
        guard event.isFile else { return true }
        return NoteFileKind(pathExtension: (name as NSString).pathExtension) != nil
    }

    private func startWatchingIfNeeded() {
        guard watcher == nil, NoteFilePaths.isDirectory(folder) else { return }
        watcher = NoteFileFolderWatcher(folder: folder) { [weak self] events, broad in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.folderChanged(events: events, broad: broad) }
            }
        }
    }

    nonisolated static func scan(folder: URL, recursive: Bool, previous: [String: Entry]) -> [String: Entry] {
        summarize(list(folder: folder, recursive: recursive, previous: previous))
    }

    nonisolated static func summarize(_ entries: [String: Entry]) -> [String: Entry] {
        var result = entries
        for (key, entry) in entries where !entry.summarized {
            guard let kind = NoteFileKind(url: entry.url) else { continue }
            let summary = NoteFileSummary.read(entry.url, kind: kind)
            result[key]?.icon = summary.icon
            result[key]?.snippet = summary.snippet
            result[key]?.summarized = true
        }
        return result
    }

    nonisolated static func entry(at url: URL, previous: Entry?) -> Entry? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard NoteFileKind(url: url) != nil, let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
        let modifiedAt = values.contentModificationDate ?? .distantPast
        let size = values.fileSize ?? 0
        if let previous, previous.modifiedAt == modifiedAt, previous.size == size { return previous }
        return unsummarized(url, modifiedAt: modifiedAt, size: size, previous: previous)
    }

    nonisolated static func carryingSummary(into entry: Entry, from departed: [Entry]) -> Entry {
        guard !entry.summarized, entry.snippet.isEmpty, entry.icon == nil,
              let twin = departed.first(where: { $0.modifiedAt == entry.modifiedAt && $0.size == entry.size }) else { return entry }
        var carried = entry
        carried.icon = twin.icon
        carried.snippet = twin.snippet
        carried.summarized = twin.summarized
        return carried
    }

    nonisolated private static func unsummarized(_ url: URL, modifiedAt: Date, size: Int, previous: Entry?) -> Entry {
        let title = url.deletingPathExtension().lastPathComponent
        return Entry(url: url, title: title, icon: previous?.icon, snippet: previous?.snippet ?? "", modifiedAt: modifiedAt, size: size,
                     foldedTitle: fold(title), summarized: false)
    }

    nonisolated static func list(folder: URL, recursive: Bool, previous: [String: Entry], budget: Int = .max) -> [String: Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: options,
                                                              errorHandler: { _, _ in true }) else { return [:] }
        var result: [String: Entry] = [:]
        var visited = 0
        while visited < budget, let next = enumerator.nextObject() as? URL {
            visited += 1
            guard let values = try? next.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if values.isPackage == true || bundleExtensions.contains(next.pathExtension.lowercased())
                    || skippedFolders.contains(next.lastPathComponent.lowercased()) || enumerator.level >= maximumDepth {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, NoteFileKind(pathExtension: next.pathExtension) != nil else { continue }
            let url = URL(fileURLWithPath: next.path)
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let size = values.fileSize ?? 0
            if let known = previous[url.path], known.modifiedAt == modifiedAt, known.size == size {
                result[url.path] = known
            } else {
                result[url.path] = unsummarized(url, modifiedAt: modifiedAt, size: size, previous: previous[url.path])
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
