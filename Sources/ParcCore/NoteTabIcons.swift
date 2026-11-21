import Combine
import Foundation

package enum NoteTabIcon: Hashable, Sendable {
    case emoji(String)
    case image(URL)

    package init?(_ raw: String?, resolve: (String) -> URL?) {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let emoji = Self.emoji(value) {
            self = .emoji(emoji)
            return
        }
        if NoteCustomEmojiName.isReference(value) {
            guard let resolved = resolve(value), resolved.isFileURL else { return nil }
            self = .image(URL(fileURLWithPath: resolved.path, isDirectory: false))
            return
        }
        guard NotePageExport.isImageSource(value), let resolved = resolve(value), resolved.isFileURL else { return nil }
        self = .image(URL(fileURLWithPath: resolved.path, isDirectory: false))
    }

    package static func emoji(_ value: String) -> String? {
        guard value.count == 1, let first = value.unicodeScalars.first, first.properties.isEmoji,
              first.properties.isEmojiPresentation || value.unicodeScalars.count > 1 else { return nil }
        return value
    }
}

@MainActor
package final class NoteTabIcons {
    package enum Lookup: Equatable {
        case known(NoteTabIcon?)
        case pending
    }

    private struct Followed {
        weak var session: NoteFileSession?
        var raw: String?
        var url: URL
        var icon: NoteTabIcon?
        var subscriptions: [AnyCancellable]
    }

    package static let shared = NoteTabIcons(files: .shared, worker: NoteFileWorker(label: "org.parc.notes.tab-icons", qos: .utility),
                                              clock: NoteFileSystemClock.shared)
    package nonisolated static let rememberedNotes = 4_096

    package let files: NoteFiles
    package let worker: NoteFileWorker
    package let clock: NoteFileClock
    package let changes = PassthroughSubject<Set<String>?, Never>()
    package var readIcon: @Sendable (URL) -> String? = { NoteTabIcons.frontMatterIcon($0) }
    package lazy var folderChanges: @MainActor (URL) -> AnyPublisher<Void, Never>? = { [unowned files] note in
        files.library(for: note).changes.eraseToAnyPublisher()
    }

    private var known: [String: NoteTabIcon?] = [:]
    private var reading: [String: Bool] = [:]
    private var generations: [String: Int] = [:]
    private var followed: [ObjectIdentifier: Followed] = [:]
    private var watchedFolders: Set<String> = []
    private var folderSubscriptions: [AnyCancellable] = []
    private var unannounced: Set<String>? = []
    private var announcement: NoteFileTimer?
    private var emojiSubscription: AnyCancellable?

    package init(files: NoteFiles, worker: NoteFileWorker, clock: NoteFileClock) {
        self.files = files
        self.worker = worker
        self.clock = clock
        emojiSubscription = files.emojiChanges.sink { [weak self] _ in self?.emojiLibraryChanged() }
    }

    private func emojiLibraryChanged() {
        known.removeAll()
        for id in Array(followed.keys) {
            guard var entry = followed[id], let session = entry.session else { continue }
            entry.icon = NoteTabIcon(entry.raw, resolve: session.environment.resolve)
            followed[id] = entry
            rememberLive(entry.icon, for: session.url)
        }
        announce(nil)
    }

    package nonisolated static func key(_ note: URL) -> String { note.standardizedFileURL.path }

    package nonisolated static func touches(_ change: Set<String>?, note: URL) -> Bool {
        change.map { $0.contains(key(note)) } ?? true
    }

    package nonisolated static func frontMatterIcon(_ note: URL) -> String? {
        guard NoteFileKind(url: note) == .markdown,
              let head = NoteFileSummary.readHead(note, kind: .markdown, upTo: NoteFileSummary.headSize) else { return nil }
        return NoteFileSummary.frontMatter(head.components(separatedBy: "\n")).icon
    }

    package func lookup(_ note: URL) -> Lookup {
        guard NoteFileKind(url: note) == .markdown else { return .known(nil) }
        if let session = files.session(for: note) { return .known(follow(session)) }
        let key = Self.key(note)
        if let icon = known[key] { return .known(icon) }
        read(note, key: key, again: false)
        return known[key].map(Lookup.known) ?? .pending
    }

    @discardableResult
    package func follow(_ session: NoteFileSession) -> NoteTabIcon? {
        let id = ObjectIdentifier(session)
        if let entry = followed[id], entry.session === session {
            refresh(id)
            return followed[id]?.icon
        }
        followed = followed.filter { $0.value.session != nil }
        let raw = Self.raw(of: session)
        let icon = NoteTabIcon(raw, resolve: session.environment.resolve)
        let subscriptions = [
            session.page.changes.sink { [weak self] change in
                guard change.kind != .selection else { return }
                self?.refresh(id)
            },
            session.urlChanges.sink { [weak self] _ in self?.refresh(id) },
        ]
        followed[id] = Followed(session: session, raw: raw, url: session.url, icon: icon, subscriptions: subscriptions)
        rememberLive(icon, for: session.url)
        return icon
    }

    package func forget() {
        known.removeAll()
        reading.removeAll()
        generations.removeAll()
        followed.removeAll()
        watchedFolders.removeAll()
        folderSubscriptions.removeAll()
        announcement?.cancel()
        announcement = nil
        unannounced = []
    }

    private static func raw(of session: NoteFileSession) -> String? {
        session.kind == .markdown ? session.page.page.settings.icon : nil
    }

    private func refresh(_ id: ObjectIdentifier) {
        guard var entry = followed[id] else { return }
        guard let session = entry.session else {
            followed[id] = nil
            return
        }
        let raw = Self.raw(of: session)
        guard raw != entry.raw || session.url != entry.url else { return }
        let previous = entry.icon
        if session.url != entry.url { known[Self.key(entry.url)] = nil }
        entry.raw = raw
        entry.url = session.url
        entry.icon = NoteTabIcon(raw, resolve: session.environment.resolve)
        followed[id] = entry
        rememberLive(entry.icon, for: session.url)
        if entry.icon != previous { announce(nil) }
    }

    private func rememberLive(_ icon: NoteTabIcon?, for note: URL) {
        let key = Self.key(note)
        generations[key, default: 0] += 1
        remember(icon, for: key)
        watchFolder(of: note)
    }

    private func remember(_ icon: NoteTabIcon?, for key: String) {
        if known.count >= Self.rememberedNotes, known[key] == nil {
            known.removeAll()
            generations = generations.filter { reading[$0.key] != nil }
        }
        known[key] = .some(icon)
    }

    private func read(_ note: URL, key: String, again: Bool) {
        if let queued = reading[key] {
            if again && !queued { reading[key] = true }
            return
        }
        reading[key] = false
        watchFolder(of: note)
        let reader = readIcon, generation = generations[key, default: 0]
        worker.perform({ reader(note) }) { [weak self] raw in
            self?.finishRead(note, key: key, raw: raw, generation: generation)
        }
    }

    private func finishRead(_ note: URL, key: String, raw: String?, generation: Int) {
        guard let again = reading.removeValue(forKey: key) else { return }
        guard generations[key, default: 0] == generation, files.session(for: note) == nil else {
            announce([key])
            if again, files.session(for: note) == nil { read(note, key: key, again: false) }
            return
        }
        let icon = NoteTabIcon(raw, resolve: NoteFileEnvironment(documentURL: note, isPlainText: false, files: files).resolve)
        let previous = known[key]
        remember(icon, for: key)
        if previous.map({ $0 != icon }) ?? true { announce([key]) }
        if again { read(note, key: key, again: false) }
    }

    private func watchFolder(of note: URL) {
        let folder = (Self.key(note) as NSString).deletingLastPathComponent
        guard watchedFolders.insert(folder).inserted, let publisher = folderChanges(note) else { return }
        folderSubscriptions.append(publisher.sink { [weak self] in self?.folderChanged(folder) })
    }

    private func folderChanged(_ folder: String) {
        let keys = Set(known.keys).union(reading.keys).filter { ($0 as NSString).deletingLastPathComponent == folder }
        for key in keys.sorted() {
            let note = URL(fileURLWithPath: key, isDirectory: false)
            if files.session(for: note) != nil { continue }
            read(note, key: key, again: true)
        }
    }

    private func announce(_ keys: Set<String>?) {
        if let keys, let pending = unannounced { unannounced = pending.union(keys) } else { unannounced = nil }
        guard announcement == nil else { return }
        announcement = clock.schedule(after: 0) { [weak self] in
            guard let self else { return }
            let change = self.unannounced
            self.announcement = nil
            self.unannounced = []
            self.changes.send(change)
        }
    }
}
