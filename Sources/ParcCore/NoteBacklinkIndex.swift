import Combine
import Foundation

package struct NoteBacklinkSnippet: Hashable, Sendable {
    package var text: String
    package var highlight: Range<Int>?
    package init(text: String, highlight: Range<Int>? = nil) {
        self.text = text
        self.highlight = highlight
    }

    package static let leadingContext = 40
    package static let maximumLength = 150

    package static func around(_ range: Range<Int>, in plain: String) -> NoteBacklinkSnippet {
        let string = plain as NSString
        let length = string.length
        guard length > 0 else { return NoteBacklinkSnippet(text: "", highlight: nil) }
        let lower = min(max(0, range.lowerBound), length)
        let upper = min(max(lower, range.upperBound), length)
        var start = max(0, lower - leadingContext)
        if start > 0 {
            var probe = start
            while probe < lower, !isSpace(string.character(at: probe)) { probe += 1 }
            start = probe < lower ? probe + 1 : string.rangeOfComposedCharacterSequence(at: start).location
        }
        var end = min(length, max(upper, start + maximumLength))
        if end < length {
            var probe = end
            while probe > upper, !isSpace(string.character(at: probe)) { probe -= 1 }
            if probe > upper { end = probe }
            let composed = string.rangeOfComposedCharacterSequence(at: end)
            if composed.location < end, composed.location >= upper { end = composed.location }
        }
        let before = collapsed(string.substring(with: NSRange(location: start, length: lower - start)))
        let middle = collapsed(string.substring(with: NSRange(location: lower, length: upper - lower)))
        let after = collapsed(string.substring(with: NSRange(location: upper, length: end - upper)))
        let head = (start > 0 ? "…" : "") + trimmed(before, leading: true)
        let tail = trimmed(after, leading: false) + (end < length ? "…" : "")
        let text = head + middle + tail
        let offset = (head as NSString).length
        let span = (middle as NSString).length
        return NoteBacklinkSnippet(text: text, highlight: span > 0 ? offset..<(offset + span) : nil)
    }

    package static func whole(_ text: String) -> NoteBacklinkSnippet {
        around(0..<(text as NSString).length, in: text)
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 32 || unit == 9 || unit == 10 || unit == 13 || unit == 0xA0 || unit == 0x2028 || unit == 0x2029 || unit == 0x3000
    }

    private static func collapsed(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var lastWasSpace = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(scalar)
                lastWasSpace = false
            }
        }
        return String(result)
    }

    private static func trimmed(_ text: String, leading: Bool) -> String {
        if leading { return String(text.drop(while: { $0 == " " })) }
        var value = text
        while value.last == " " { value.removeLast() }
        return value
    }
}

package struct NoteOutgoingLink: Hashable, Sendable {
    package enum Kind: Hashable, Sendable { case link, mention, pageLink }

    package var target: String
    package var kind: Kind
    package var snippet: NoteBacklinkSnippet
    package var anchor: String?
    package init(target: String, kind: Kind, snippet: NoteBacklinkSnippet, anchor: String? = nil) {
        self.target = target
        self.kind = kind
        self.snippet = snippet
        self.anchor = anchor
    }
}

package struct NoteBacklink: Hashable, Identifiable, Sendable {
    package var source: URL
    package var title: String
    package var icon: String?
    package var snippet: NoteBacklinkSnippet
    package var anchor: String?
    package var links: Int
    package init(source: URL, title: String, icon: String? = nil, snippet: NoteBacklinkSnippet, anchor: String? = nil, links: Int) {
        self.source = source
        self.title = title
        self.icon = icon
        self.snippet = snippet
        self.anchor = anchor
        self.links = links
    }

    package var id: URL { source }

    package var isEasel: Bool { source.scheme?.lowercased() == "parc" }

    package var destination: URL {
        guard let anchor, !anchor.isEmpty, var components = URLComponents(url: source, resolvingAgainstBaseURL: false) else { return source }
        components.fragment = anchor
        return components.url ?? source
    }
}

package struct NoteBacklinkMove: Hashable, Sendable {
    package var fromKey: String
    package var from: URL
    package var to: URL
    package init(fromKey: String, from: URL, to: URL) {
        self.fromKey = fromKey
        self.from = from
        self.to = to
    }
}

package enum NoteBacklinkScanner {
    package static let readLimit = 2 * 1024 * 1024

    package struct Reference: Hashable {
        package var target: String
        package var kind: NoteOutgoingLink.Kind
        package var range: Range<Int>
        package init(target: String, kind: NoteOutgoingLink.Kind, range: Range<Int>) {
            self.target = target
            self.kind = kind
            self.range = range
        }
    }

    package static func mayLink(_ text: String) -> Bool {
        text.contains("](") || text.contains("[[") || text.contains("]:") || text.contains("href")
    }

    package static func outgoing(fileAt url: URL) -> [NoteOutgoingLink] {
        guard NoteFileKind(url: url) == .markdown,
              let text = NoteFileSummary.readHead(url, kind: .markdown, upTo: readLimit), mayLink(text) else { return [] }
        return outgoing(in: NoteMarkdown.parse(text), folder: url.deletingLastPathComponent())
    }

    package static func outgoing(in page: NotePage, folder: URL) -> [NoteOutgoingLink] {
        var keys: [String: String] = [:]
        var misses: Set<String> = []
        func key(_ target: String) -> String? {
            if let known = keys[target] { return known }
            if misses.contains(target) { return nil }
            guard let value = targetKey(target, from: folder) else {
                misses.insert(target)
                return nil
            }
            keys[target] = value
            return value
        }
        var slugs: [NoteBlockID: String] = [:]
        for entry in page.headingSlugs() { slugs[entry.id] = entry.slug }
        var section: String?
        var result: [NoteOutgoingLink] = []
        for block in page.allBlocks() {
            if let slug = slugs[block.id] { section = slug }
            let anchor = block.props.anchor ?? section
            if block.kind == .pageLink, let target = block.props.target, let resolved = key(target) {
                let label = block.text.plainText
                let shown = label.isEmpty ? NoteMDLinks.stem(target) : label
                result.append(NoteOutgoingLink(target: resolved, kind: .pageLink, snippet: .whole(shown), anchor: anchor))
            }
            for field in NotePageFinder.fields(of: block) {
                guard let text = block.text(in: field) else { continue }
                let flat = flatten(text)
                for reference in flat.references {
                    guard let resolved = key(reference.target) else { continue }
                    result.append(NoteOutgoingLink(target: resolved, kind: reference.kind,
                                                   snippet: .around(reference.range, in: flat.plain), anchor: anchor))
                }
            }
        }
        return result
    }

    package static func flatten(_ text: NoteText) -> (plain: String, references: [Reference]) {
        var plain = ""
        var position = 0
        var references: [Reference] = []
        var open: (target: String, start: Int)?
        func close() {
            if let current = open, position > current.start {
                references.append(Reference(target: current.target, kind: .link, range: current.start..<position))
            }
            open = nil
        }
        let source = text.string as NSString
        for run in text.runs() {
            if let atom = run.marks.atom {
                close()
                for _ in run.range {
                    var face = atom.fallbackText
                    if case .page(_, let title) = atom, title.isEmpty { face = "Untitled" }
                    let start = position
                    plain += face
                    position += (face as NSString).length
                    if case .page(let target, _) = atom {
                        references.append(Reference(target: target, kind: .mention, range: start..<position))
                    }
                }
                continue
            }
            if let link = run.marks.link {
                if open?.target != link {
                    close()
                    open = (link, position)
                }
            } else {
                close()
            }
            plain += source.substring(with: NSRange(location: run.range.lowerBound, length: run.range.count))
            position += run.range.count
        }
        close()
        return (plain, references)
    }

    package static func targetURL(_ raw: String, from folder: URL) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.hasPrefix("<"), value.hasSuffix(">") { value = String(value.dropFirst().dropLast()) }
        guard !value.isEmpty, !value.hasPrefix("#"), !value.hasPrefix("//") else { return nil }
        if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]) }
        guard !value.isEmpty else { return nil }
        var file: URL
        if let scheme = scheme(of: value) {
            guard scheme == "file", let url = URL(string: value) ?? URL(string: value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""),
                  url.isFileURL, !url.path.isEmpty else { return nil }
            file = URL(fileURLWithPath: url.path)
        } else {
            let decoded = value.removingPercentEncoding ?? value
            if decoded.hasPrefix("/") {
                file = URL(fileURLWithPath: decoded)
            } else if decoded == "~" || decoded.hasPrefix("~/") {
                file = URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath)
            } else {
                file = folder.appendingPathComponent(decoded)
            }
        }
        if NoteFileKind(url: file) == nil { file = URL(fileURLWithPath: file.path + ".md") }
        return file.standardizedFileURL
    }

    package static func targetKey(_ raw: String, from folder: URL) -> String? {
        targetURL(raw, from: folder).map { NoteFilePaths.key(for: $0) }
    }

    package static func scheme(of value: String) -> String? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let candidate = value[..<colon]
        guard candidate.count >= 2, let first = candidate.unicodeScalars.first, first.isASCII, CharacterSet.letters.contains(first),
              candidate.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+.-".unicodeScalars.contains($0)) })
        else { return nil }
        return candidate.lowercased()
    }
}

@MainActor
package final class NoteBacklinkIndex {
    private struct Source: Equatable {
        var url: URL
        var title: String
        var icon: String?
        var modifiedAt: Date
        var size: Int
        var identity: String?
        var node: NoteFileNode?
        var links: [NoteOutgoingLink]?
        var easel: EaselSourceInfo?
    }

    private struct EaselSourceInfo: Equatable {
        var store: ObjectIdentifier
        var id: UUID
        var file: URL
    }

    private struct EaselListing: Sendable {
        var path: String
        var id: UUID
        var modifiedAt: Date
        var size: Int
    }

    private struct Job {
        var path: String
        var url: URL
        var isEasel = false
        var modifiedAt: Date
        var size: Int
    }

    private struct Reading: Sendable {
        var path: String
        var modifiedAt: Date
        var size: Int
        var identity: String
        var node: NoteFileNode?
        var links: [NoteOutgoingLink]
        var title: String?
    }

    private struct Departure {
        var source: Source
        var at: Date
    }

    package static let shared = NoteBacklinkIndex()
    package static var worker = NoteFileWorker(label: "org.parc.notes.backlinks", qos: .utility)
    package static var clock: NoteFileClock = NoteFileSystemClock.shared
    package static var followDelay: TimeInterval = 1.5
    package static var departureWindow: TimeInterval = 10
    package static var easelDelay: TimeInterval = 1
    package static let chunkSize = 200

    package let changes = PassthroughSubject<Void, Never>()
    package private(set) var isActive = false
    private var libraries: [NoteLibrary] = []
    private var tracked: [ObjectIdentifier: AnyCancellable] = [:]
    private var creation: AnyCancellable?
    private var sources: [String: Source] = [:]
    private var departed: [String: Departure] = [:]
    private var incoming: [String: [NoteBacklink]] = [:]
    private var queue: [String] = []
    private var queued: Set<String> = []
    private var isReading = false
    private var refreshTimer: NoteFileTimer?
    private var moves: [(from: URL, to: URL)] = []
    private var aliases: [String: String] = [:]
    private var followTimer: NoteFileTimer?
    private var rewriting = 0
    private var easelStores: [ObjectIdentifier: EaselStore] = [:]
    private var easelObservers: [NSObjectProtocol] = []
    private var easelListing = false
    private var easelListingAgain = false
    private var easelTimer: NoteFileTimer?

    package var isSettled: Bool {
        !isReading && queue.isEmpty && refreshTimer == nil && followTimer == nil && rewriting == 0 && moves.isEmpty
            && easelTimer == nil && !easelListing
    }

    package func activate() {
        guard !isActive else { return }
        isActive = true
        creation = NoteLibrary.opened.sink { [weak self] library in self?.track(library) }
        for library in NoteLibrary.known { track(library) }
    }

    package func include(_ library: NoteLibrary) {
        activate()
        track(library)
    }

    package func include(_ store: EaselStore) {
        activate()
        let id = ObjectIdentifier(store)
        guard easelStores[id] == nil else { return }
        easelStores[id] = store
        if easelObservers.isEmpty {
            let names: [Notification.Name] = [.easelDocumentChanged, .easelDocumentRemoved]
            easelObservers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleEaselListing() }
                }
            }
        }
        scheduleEaselListing(after: 0)
    }

    package func backlinks(to note: URL) -> [NoteBacklink] {
        guard note.isFileURL else { return [] }
        activate()
        track(NoteLibrary.library(for: note))
        return incoming[NoteFilePaths.key(for: note)] ?? []
    }

    package func noteMoved(from old: URL, to new: URL) {
        guard old.isFileURL, new.isFileURL, old.path != new.path else { return }
        activate()
        track(NoteLibrary.library(for: new))
        let fromKey = NoteFilePaths.key(for: old)
        let path = sources[old.path] != nil ? old.path : sources.first(where: { $0.value.identity == fromKey })?.key
        if let path, let source = sources.removeValue(forKey: path) {
            queued.remove(path)
            queue.removeAll { $0 == path }
            place(source, from: old, at: new, title: new.deletingPathExtension().lastPathComponent, icon: source.icon,
                  modifiedAt: source.modifiedAt, size: source.size)
        }
        recordMove(from: old, to: new)
    }

    private func recordMove(from old: URL, to new: URL) {
        let fromKey = NoteFilePaths.key(for: old), toKey = NoteFilePaths.key(for: new)
        guard !moves.contains(where: { $0.from.path == old.path && $0.to.path == new.path }) else { return }
        if fromKey != toKey { aliases[fromKey] = toKey }
        rebuild()
        moves.append((old, new))
        followTimer?.cancel()
        followTimer = Self.clock.schedule(after: Self.followDelay) { [weak self] in
            self?.followTimer = nil
            self?.scheduleRefresh()
        }
    }

    private func place(_ source: Source, from old: URL, at new: URL, title: String, icon: String?, modifiedAt: Date, size: Int) {
        var moved = source
        let previous = sources[new.path]
        moved.url = new
        moved.title = title
        moved.icon = icon
        moved.identity = NoteFilePaths.key(for: new)
        moved.node = previous?.node ?? source.node
        let refolded = old.deletingLastPathComponent().path != new.deletingLastPathComponent().path
        let restamped = moved.modifiedAt != modifiedAt || moved.size != size
        moved.modifiedAt = modifiedAt
        moved.size = size
        sources[new.path] = moved
        if refolded || restamped { enqueue(new.path) }
    }

    private func track(_ library: NoteLibrary) {
        let id = ObjectIdentifier(library)
        guard tracked[id] == nil else { return }
        tracked[id] = library.listingChanges.sink { [weak self] in self?.scheduleRefresh() }
        libraries.append(library)
        scheduleRefresh()
    }

    private func scheduleEaselListing(after delay: TimeInterval? = nil) {
        guard !easelStores.isEmpty, easelTimer == nil else { return }
        easelTimer = Self.clock.schedule(after: delay ?? Self.easelDelay) { [weak self] in
            self?.easelTimer = nil
            self?.listEaselsNow()
        }
    }

    private func listEaselsNow() {
        if easelListing {
            easelListingAgain = true
            return
        }
        easelListing = true
        let directories = easelStores.map { (key: $0.key, directory: $0.value.documentsDirectory) }
        Self.worker.perform({
            directories.map { entry in (entry.key, Self.listEasels(in: entry.directory)) }
        }) { [weak self] listings in
            self?.finishEaselListing(listings)
        }
    }

    nonisolated private static func listEasels(in directory: URL) -> [EaselListing] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "json", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return EaselListing(path: url.path, id: id, modifiedAt: values.contentModificationDate ?? .distantPast,
                                size: values.fileSize ?? 0)
        }
    }

    private func finishEaselListing(_ listings: [(ObjectIdentifier, [EaselListing])]) {
        easelListing = false
        var present: Set<String> = []
        var changed = false
        for (storeKey, entries) in listings where easelStores[storeKey] != nil {
            for entry in entries {
                present.insert(entry.path)
                let file = URL(fileURLWithPath: entry.path)
                if var source = sources[entry.path] {
                    if source.modifiedAt != entry.modifiedAt || source.size != entry.size {
                        source.modifiedAt = entry.modifiedAt
                        source.size = entry.size
                        sources[entry.path] = source
                        enqueue(entry.path)
                    }
                } else {
                    sources[entry.path] = Source(url: URL(string: InternalPage.easel(entry.id).urlString) ?? file, title: "Untitled Easel",
                                                 icon: nil, modifiedAt: entry.modifiedAt, size: entry.size, identity: "easel:" + entry.id.uuidString,
                                                 node: nil, links: nil, easel: EaselSourceInfo(store: storeKey, id: entry.id, file: file))
                    enqueue(entry.path)
                }
            }
        }
        for (path, source) in sources where source.easel != nil && !present.contains(path) {
            sources[path] = nil
            queued.remove(path)
            changed = true
        }
        queue.removeAll { !queued.contains($0) }
        if changed { rebuild() }
        readNext()
        if easelListingAgain {
            easelListingAgain = false
            scheduleEaselListing()
        }
    }

    private func scheduleRefresh() {
        guard refreshTimer == nil else { return }
        refreshTimer = Self.clock.schedule(after: 0) { [weak self] in self?.refresh() }
    }

    private func refresh() {
        refreshTimer = nil
        var listed: [String: NoteLibrary.Entry] = [:]
        var complete = true
        for library in libraries {
            guard let entries = library.listedEntries() else {
                complete = false
                continue
            }
            for entry in entries { listed[entry.url.path] = entry }
        }
        var changed = false
        if complete {
            let now = Self.clock.now
            departed = departed.filter { now.timeIntervalSince($0.value.at) < Self.departureWindow }
            for path in Array(sources.keys) where listed[path] == nil && sources[path]?.easel == nil {
                guard let source = sources.removeValue(forKey: path) else { continue }
                if source.node != nil { departed[path] = Departure(source: source, at: now) }
                queued.remove(path)
                changed = true
            }
            queue.removeAll { !queued.contains($0) }
            if adoptMoves(listed) { changed = true }
        }
        for (path, entry) in listed {
            guard var source = sources[path] else {
                sources[path] = Source(url: entry.url, title: entry.title, icon: entry.icon, modifiedAt: entry.modifiedAt, size: entry.size,
                                       identity: nil, node: nil, links: nil)
                enqueue(path)
                continue
            }
            if source.modifiedAt != entry.modifiedAt || source.size != entry.size {
                source.modifiedAt = entry.modifiedAt
                source.size = entry.size
                enqueue(path)
            }
            if source.title != entry.title || source.icon != entry.icon || source.url != entry.url {
                source.title = entry.title
                source.icon = entry.icon
                source.url = entry.url
                changed = true
            }
            sources[path] = source
        }
        if changed { rebuild() }
        readNext(settling: complete)
    }

    private func adoptMoves(_ listed: [String: NoteLibrary.Entry]) -> Bool {
        guard !departed.isEmpty else { return false }
        var adopted = false
        for (path, entry) in listed where sources[path] == nil {
            guard let node = NoteFileNode(path: path),
                  let match = departed.first(where: { $0.value.source.node == node && $0.value.source.size == entry.size
                                                        && $0.value.source.modifiedAt == entry.modifiedAt }) else { continue }
            departed[match.key] = nil
            let old = match.value.source.url
            place(match.value.source, from: old, at: entry.url, title: entry.title, icon: entry.icon ?? match.value.source.icon,
                  modifiedAt: entry.modifiedAt, size: entry.size)
            recordMove(from: old, to: entry.url)
            adopted = true
        }
        return adopted
    }

    private func enqueue(_ path: String) {
        guard queued.insert(path).inserted else { return }
        queue.append(path)
    }

    private func readNext(settling: Bool = true) {
        guard !isReading else { return }
        var jobs: [Job] = []
        while jobs.count < Self.chunkSize, !queue.isEmpty {
            let path = queue.removeFirst()
            queued.remove(path)
            if let source = sources[path] {
                jobs.append(Job(path: path, url: source.easel?.file ?? source.url, isEasel: source.easel != nil,
                                modifiedAt: source.modifiedAt, size: source.size))
            }
        }
        guard !jobs.isEmpty else {
            if settling { settle() }
            return
        }
        isReading = true
        Self.worker.perform({
            jobs.map { job in
                if job.isEasel {
                    let read = EaselBacklinkScanner.read(fileAt: job.url)
                    return Reading(path: job.path, modifiedAt: job.modifiedAt, size: job.size, identity: "",
                                   node: nil, links: read?.links ?? [], title: read?.title)
                }
                return Reading(path: job.path, modifiedAt: job.modifiedAt, size: job.size, identity: NoteFilePaths.key(for: job.url),
                               node: NoteFileNode(path: job.path), links: NoteBacklinkScanner.outgoing(fileAt: job.url), title: nil)
            }
        }) { [weak self] readings in
            self?.finishReading(readings)
        }
    }

    private func finishReading(_ readings: [Reading]) {
        isReading = false
        var changed = false
        for reading in readings {
            guard var source = sources[reading.path], source.modifiedAt == reading.modifiedAt, source.size == reading.size else { continue }
            if source.easel != nil {
                if source.links != reading.links || (reading.title.map { $0 != source.title } ?? false) { changed = true }
                source.links = reading.links
                if let title = reading.title { source.title = title }
                sources[reading.path] = source
                continue
            }
            if source.links != reading.links || source.identity != reading.identity { changed = true }
            source.links = reading.links
            source.identity = reading.identity
            source.node = reading.node ?? source.node
            sources[reading.path] = source
        }
        if changed { rebuild() }
        if refreshTimer == nil { readNext() }
    }

    private func settle() {
        guard !moves.isEmpty, !isReading, queue.isEmpty, refreshTimer == nil, followTimer == nil else { return }
        guard libraries.allSatisfy({ $0.listedEntries() != nil }) else { return }
        let pending = moves
        moves = []
        follow(pending)
    }

    private func resolved(_ key: String) -> String {
        var current = key
        var steps = 0
        while let next = aliases[current], next != current, steps < 16 {
            current = next
            steps += 1
        }
        return current
    }

    private func rebuild() {
        var grouped: [String: [String: [NoteOutgoingLink]]] = [:]
        for (path, source) in sources {
            guard let links = source.links, !links.isEmpty else { continue }
            for link in links {
                let target = resolved(link.target)
                if let identity = source.identity, target == resolved(identity) { continue }
                grouped[target, default: [:]][path, default: []].append(link)
            }
        }
        var next: [String: [NoteBacklink]] = [:]
        for (target, bySource) in grouped {
            var list: [NoteBacklink] = []
            for (path, links) in bySource {
                guard let source = sources[path], let first = links.first else { continue }
                list.append(NoteBacklink(source: source.url, title: source.title, icon: source.icon, snippet: first.snippet,
                                         anchor: first.anchor, links: links.count))
            }
            next[target] = list.sorted(by: Self.ordered)
        }
        guard next != incoming else { return }
        incoming = next
        changes.send()
    }

    private static func ordered(_ first: NoteBacklink, _ second: NoteBacklink) -> Bool {
        let order = first.title.localizedStandardCompare(second.title)
        if order != .orderedSame { return order == .orderedAscending }
        return first.source.path < second.source.path
    }

    private func retarget(_ path: String, from fromKey: String, to toKey: String) {
        guard fromKey != toKey, var source = sources[path], let links = source.links, links.contains(where: { $0.target == fromKey }) else { return }
        source.links = links.map { link in
            var moved = link
            if moved.target == fromKey { moved.target = toKey }
            return moved
        }
        sources[path] = source
    }

    private func follow(_ pending: [(from: URL, to: URL)]) {
        var finals: [(key: String, from: URL, to: URL)] = []
        for move in pending {
            let fromKey = NoteFilePaths.key(for: move.from)
            for index in finals.indices where NoteFilePaths.key(for: finals[index].to) == fromKey { finals[index].to = move.to }
            if !finals.contains(where: { $0.key == fromKey }) { finals.append((fromKey, move.from, move.to)) }
        }
        for item in finals {
            let move = NoteBacklinkMove(fromKey: item.key, from: item.from, to: item.to)
            let toKey = NoteFilePaths.key(for: item.to)
            var handled: Set<String> = []
            for session in NoteFileSession.openSessions where session.kind == .markdown {
                guard NoteFileSession.session(for: session.url) === session else { continue }
                let identity = NoteFilePaths.key(for: session.url)
                handled.insert(identity)
                guard !session.page.isReadOnly else { continue }
                let folder = session.url.deletingLastPathComponent()
                let resolving = identity == toKey ? item.from.deletingLastPathComponent() : folder
                guard Self.rewrite(session.page, resolvingFrom: resolving, writingFrom: folder, move: move) else { continue }
                for (path, source) in sources where source.identity == identity { retarget(path, from: item.key, to: toKey) }
            }
            rewriteEasels(move, toKey: toKey)
            var closed: [(path: String, url: URL)] = []
            for (path, source) in sources where source.identity == toKey || source.links?.contains(where: { $0.target == item.key }) == true {
                guard let identity = source.identity, !handled.contains(identity), NoteFileSession.session(for: source.url) == nil,
                      NoteFilePaths.itemExists(source.url) else { continue }
                handled.insert(identity)
                closed.append((path, source.url))
            }
            guard !closed.isEmpty else {
                finishFollowing(move)
                continue
            }
            rewriting += 1
            let from = item.from
            NoteFileSession.worker.perform({
                closed.filter { entry in
                    let folder = entry.url.deletingLastPathComponent()
                    let resolving = NoteFilePaths.key(for: entry.url) == toKey ? from.deletingLastPathComponent() : folder
                    return NoteBacklinkRewriter.rewriteFile(at: entry.url, resolvingFrom: resolving, writingFrom: folder, move: move)
                }
            }) { [weak self] rewritten in
                guard let self else { return }
                self.rewriting -= 1
                for entry in rewritten { self.retarget(entry.path, from: move.fromKey, to: toKey) }
                NoteLibrary.filesRewritten(closed.map(\.url))
                self.finishFollowing(move)
            }
        }
    }

    private func rewriteEasels(_ move: NoteBacklinkMove, toKey: String) {
        for (path, source) in sources {
            guard let info = source.easel, let store = easelStores[info.store],
                  source.links?.contains(where: { $0.target == move.fromKey }) == true,
                  let session = try? store.load(info.id), !session.isClosed, !session.isDeleted,
                  let next = EaselBacklinkRewriter.rewrite(session.document, move: move) else { continue }
            do {
                if session.document.isLocked {
                    try session.updateLinks { EaselBacklinkRewriter.rewrite($0, move: move) }
                } else {
                    try session.perform("Update links") { $0 = next }
                }
            } catch {
                continue
            }
            retarget(path, from: move.fromKey, to: toKey)
        }
    }

    private func finishFollowing(_ move: NoteBacklinkMove) {
        if !moves.contains(where: { NoteFilePaths.key(for: $0.from) == move.fromKey }) { aliases[move.fromKey] = nil }
        rebuild()
        scheduleRefresh()
    }

    @discardableResult
    private static func rewrite(_ session: NotePageSession, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove) -> Bool {
        var changed = false
        for block in session.page.allBlocks() {
            var copy = block
            guard NoteBacklinkRewriter.rewrite(&copy, resolvingFrom: folder, writingFrom: newFolder, move: move) else { continue }
            session.updateBlockMetadata(block.id) { NoteBacklinkRewriter.rewrite(&$0, resolvingFrom: folder, writingFrom: newFolder, move: move) }
            changed = true
        }
        return changed
    }
}
