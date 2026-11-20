import Combine
import Foundation

struct NoteBacklinkSnippet: Hashable, Sendable {
    var text: String
    var highlight: Range<Int>?

    static let leadingContext = 40
    static let maximumLength = 150

    static func around(_ range: Range<Int>, in plain: String) -> NoteBacklinkSnippet {
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

    static func whole(_ text: String) -> NoteBacklinkSnippet {
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

struct NoteOutgoingLink: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case link, mention, pageLink }

    var target: String
    var kind: Kind
    var snippet: NoteBacklinkSnippet
    var anchor: String?
}

struct NoteBacklink: Hashable, Identifiable, Sendable {
    var source: URL
    var title: String
    var icon: String?
    var snippet: NoteBacklinkSnippet
    var anchor: String?
    var links: Int

    var id: URL { source }

    var destination: URL {
        guard let anchor, !anchor.isEmpty, var components = URLComponents(url: source, resolvingAgainstBaseURL: false) else { return source }
        components.fragment = anchor
        return components.url ?? source
    }
}

struct NoteBacklinkMove: Hashable, Sendable {
    var fromKey: String
    var from: URL
    var to: URL
}

enum NoteBacklinkScanner {
    static let readLimit = 2 * 1024 * 1024

    struct Reference: Hashable {
        var target: String
        var kind: NoteOutgoingLink.Kind
        var range: Range<Int>
    }

    static func mayLink(_ text: String) -> Bool {
        text.contains("](") || text.contains("[[") || text.contains("]:") || text.contains("href")
    }

    static func outgoing(fileAt url: URL) -> [NoteOutgoingLink] {
        guard NoteFileKind(url: url) == .markdown,
              let text = NoteFileSummary.readHead(url, kind: .markdown, upTo: readLimit), mayLink(text) else { return [] }
        return outgoing(in: NoteMarkdown.parse(text), folder: url.deletingLastPathComponent())
    }

    static func outgoing(in page: NotePage, folder: URL) -> [NoteOutgoingLink] {
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

    static func flatten(_ text: NoteText) -> (plain: String, references: [Reference]) {
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

    static func targetURL(_ raw: String, from folder: URL) -> URL? {
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

    static func targetKey(_ raw: String, from folder: URL) -> String? {
        targetURL(raw, from: folder).map { NoteFilePaths.key(for: $0) }
    }

    static func scheme(of value: String) -> String? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let candidate = value[..<colon]
        guard candidate.count >= 2, let first = candidate.unicodeScalars.first, first.isASCII, CharacterSet.letters.contains(first),
              candidate.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+.-".unicodeScalars.contains($0)) })
        else { return nil }
        return candidate.lowercased()
    }
}

@MainActor
final class NoteBacklinkIndex {
    private struct Source: Equatable {
        var url: URL
        var title: String
        var icon: String?
        var modifiedAt: Date
        var size: Int
        var identity: String?
        var links: [NoteOutgoingLink]?
    }

    private struct Job {
        var path: String
        var url: URL
        var modifiedAt: Date
        var size: Int
    }

    private struct Reading: Sendable {
        var path: String
        var modifiedAt: Date
        var size: Int
        var identity: String
        var links: [NoteOutgoingLink]
    }

    static let shared = NoteBacklinkIndex()
    static var worker = NoteFileWorker(label: "org.parc.notes.backlinks", qos: .utility)
    static var clock: NoteFileClock = NoteFileSystemClock.shared
    static var followDelay: TimeInterval = 1.5
    static var aliasGrace: TimeInterval = 3
    static let chunkSize = 200

    let changes = PassthroughSubject<Void, Never>()
    private(set) var isActive = false
    private var libraries: [NoteLibrary] = []
    private var tracked: [ObjectIdentifier: AnyCancellable] = [:]
    private var creation: AnyCancellable?
    private var sources: [String: Source] = [:]
    private var incoming: [String: [NoteBacklink]] = [:]
    private var queue: [String] = []
    private var queued: Set<String> = []
    private var isReading = false
    private var refreshTimer: NoteFileTimer?
    private var moves: [(from: URL, to: URL)] = []
    private var aliases: [String: String] = [:]
    private var expiring: Set<String> = []
    private var followTimer: NoteFileTimer?
    private var expiryTimer: NoteFileTimer?
    private var rewriting = 0

    var isSettled: Bool {
        !isReading && queue.isEmpty && refreshTimer == nil && followTimer == nil && rewriting == 0 && moves.isEmpty
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        creation = NoteLibrary.opened.sink { [weak self] library in self?.track(library) }
        for library in NoteLibrary.known { track(library) }
    }

    func include(_ library: NoteLibrary) {
        activate()
        track(library)
    }

    func backlinks(to note: URL) -> [NoteBacklink] {
        guard note.isFileURL else { return [] }
        activate()
        track(NoteLibrary.library(for: note))
        return incoming[NoteFilePaths.key(for: note)] ?? []
    }

    func noteMoved(from old: URL, to new: URL) {
        guard old.isFileURL, new.isFileURL, old.path != new.path else { return }
        activate()
        track(NoteLibrary.library(for: new))
        let fromKey = NoteFilePaths.key(for: old), toKey = NoteFilePaths.key(for: new)
        if fromKey != toKey {
            aliases[fromKey] = toKey
            rebuild()
        }
        moves.append((old, new))
        followTimer?.cancel()
        followTimer = Self.clock.schedule(after: Self.followDelay) { [weak self] in
            self?.followTimer = nil
            self?.scheduleRefresh()
        }
    }

    private func track(_ library: NoteLibrary) {
        let id = ObjectIdentifier(library)
        guard tracked[id] == nil else { return }
        tracked[id] = library.listingChanges.sink { [weak self] in self?.scheduleRefresh() }
        libraries.append(library)
        scheduleRefresh()
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
        for (path, entry) in listed {
            guard var source = sources[path] else {
                let isMarkdown = NoteFileKind(url: entry.url) == .markdown
                sources[path] = Source(url: entry.url, title: entry.title, icon: entry.icon, modifiedAt: entry.modifiedAt, size: entry.size,
                                       identity: nil, links: isMarkdown ? nil : [])
                if isMarkdown { enqueue(path) }
                continue
            }
            if source.modifiedAt != entry.modifiedAt || source.size != entry.size {
                source.modifiedAt = entry.modifiedAt
                source.size = entry.size
                if NoteFileKind(url: entry.url) == .markdown { enqueue(path) }
            }
            if source.title != entry.title || source.icon != entry.icon || source.url != entry.url {
                source.title = entry.title
                source.icon = entry.icon
                source.url = entry.url
                changed = true
            }
            sources[path] = source
        }
        if complete {
            for path in Array(sources.keys) where listed[path] == nil {
                sources[path] = nil
                queued.remove(path)
                changed = true
            }
            queue.removeAll { !queued.contains($0) }
        }
        if changed { rebuild() }
        readNext(settling: complete)
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
            if let source = sources[path] { jobs.append(Job(path: path, url: source.url, modifiedAt: source.modifiedAt, size: source.size)) }
        }
        guard !jobs.isEmpty else {
            if settling { settle() }
            return
        }
        isReading = true
        Self.worker.perform({
            jobs.map { job in
                Reading(path: job.path, modifiedAt: job.modifiedAt, size: job.size, identity: NoteFilePaths.key(for: job.url),
                        links: NoteBacklinkScanner.outgoing(fileAt: job.url))
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
            if source.links != reading.links || source.identity != reading.identity { changed = true }
            source.links = reading.links
            source.identity = reading.identity
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

    private func scheduleExpiry() {
        expiryTimer?.cancel()
        expiryTimer = Self.clock.schedule(after: Self.aliasGrace) { [weak self] in
            guard let self else { return }
            self.expiryTimer = nil
            guard self.isSettled else {
                self.scheduleExpiry()
                return
            }
            for key in self.expiring { self.aliases[key] = nil }
            self.expiring = []
            self.rebuild()
        }
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
                Self.rewrite(session.page, resolvingFrom: resolving, writingFrom: folder, move: move)
            }
            var closed: [URL] = []
            for source in sources.values where source.links?.contains(where: { $0.target == item.key }) == true {
                guard let identity = source.identity, !handled.contains(identity), NoteFileSession.session(for: source.url) == nil,
                      NoteFilePaths.itemExists(source.url) else { continue }
                handled.insert(identity)
                closed.append(source.url)
            }
            guard !closed.isEmpty else {
                finishFollowing(move)
                continue
            }
            rewriting += 1
            NoteFileSession.worker.perform({
                for url in closed {
                    let folder = url.deletingLastPathComponent()
                    let resolving = NoteFilePaths.key(for: url) == toKey ? item.from.deletingLastPathComponent() : folder
                    _ = NoteBacklinkRewriter.rewriteFile(at: url, resolvingFrom: resolving, writingFrom: folder, move: move)
                }
            }) { [weak self] _ in
                guard let self else { return }
                self.rewriting -= 1
                NoteLibrary.filesRewritten(closed)
                self.finishFollowing(move)
            }
        }
    }

    private func finishFollowing(_ move: NoteBacklinkMove) {
        if aliases[move.fromKey] != nil { expiring.insert(move.fromKey) }
        scheduleRefresh()
        scheduleExpiry()
    }

    private static func rewrite(_ session: NotePageSession, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove) {
        for block in session.page.allBlocks() {
            var copy = block
            guard NoteBacklinkRewriter.rewrite(&copy, resolvingFrom: folder, writingFrom: newFolder, move: move) else { continue }
            session.updateBlockMetadata(block.id) { NoteBacklinkRewriter.rewrite(&$0, resolvingFrom: folder, writingFrom: newFolder, move: move) }
        }
    }
}
