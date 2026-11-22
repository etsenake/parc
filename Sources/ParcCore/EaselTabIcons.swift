import Combine
import Foundation

@MainActor
package final class EaselTabIcons {
    private struct Entry {
        var icon: EaselPageIcon?
        var resolved: NoteTabIcon?
        var directory: URL
        var id: UUID
    }

    private struct Followed {
        weak var session: EaselSession?
        var key: String
        var subscription: AnyCancellable
    }

    package static let shared = EaselTabIcons()
    private static let sharedWorker = NoteFileWorker(label: "org.parc.easels.tab-icons", qos: .utility)
    package var worker = EaselTabIcons.sharedWorker

    package let changes = PassthroughSubject<Set<String>?, Never>()
    package var directory: (UUID) -> URL? = { _ in nil }
    package var store: (URL) -> EaselStore? = { _ in nil }
    package var notesFolder: (URL) -> URL? = { _ in nil }
    var readIcon: @Sendable (URL, UUID) -> EaselPageIcon? = { EaselStore.readIcon(directory: $0, id: $1) }

    private var known: [String: Entry] = [:]
    private var reading: Set<String> = []
    private var followed: [ObjectIdentifier: Followed] = [:]
    private var subscriptions: [AnyCancellable] = []

    package init() {
        subscriptions = [
            NoteEmojiLibrary.anyChange.sink { [weak self] _ in self?.resolveAgain() },
            NoteFolderPreferences.changes.sink { [weak self] _ in self?.resolveAgain() },
            NotificationCenter.default.publisher(for: .easelDocumentRemoved).sink { [weak self] note in
                guard let id = note.object as? UUID else { return }
                self?.forget(id)
            },
            NotificationCenter.default.publisher(for: .easelAssetsRemoved).sink { [weak self] note in
                guard let directory = note.object as? URL else { return }
                self?.resolveAgain(directory: directory)
            },
        ]
    }

    package nonisolated static func key(directory: URL, id: UUID) -> String {
        "easel:" + directory.standardizedFileURL.path + "|" + id.uuidString.lowercased()
    }

    package nonisolated static func touches(_ change: Set<String>?, key: String) -> Bool {
        change.map { $0.contains(key) } ?? true
    }

    package func key(profile: UUID, id: UUID) -> String? {
        directory(profile).map { Self.key(directory: $0, id: id) }
    }

    package func lookup(profile: UUID, id: UUID) -> NoteTabIcons.Lookup {
        guard let directory = directory(profile) else { return .known(nil) }
        return lookup(directory: directory, id: id)
    }

    package func lookup(directory: URL, id: UUID) -> NoteTabIcons.Lookup {
        let key = Self.key(directory: directory, id: id)
        if let session = store(directory)?.existingSession(id), !session.isClosed, !session.isDeleted { follow(session) }
        if let entry = known[key] { return .known(entry.resolved) }
        read(directory: directory, id: id, key: key)
        return known[key].map { .known($0.resolved) } ?? .pending
    }

    package func learn(_ summaries: [EaselSummary], directory: URL) {
        for summary in summaries {
            let key = Self.key(directory: directory, id: summary.id)
            if let live = store(directory)?.existingSession(summary.id), !live.isClosed, !live.isDeleted { follow(live); continue }
            guard known[key] == nil else { continue }
            known[key] = Entry(icon: summary.icon, resolved: resolve(summary.icon, directory: directory), directory: directory, id: summary.id)
        }
    }

    package func follow(_ session: EaselSession) {
        guard let directory = session.storeDirectory else { return }
        let identifier = ObjectIdentifier(session)
        if let entry = followed[identifier], entry.session === session { return }
        followed = followed.filter { $0.value.session != nil }
        let id = session.document.id
        let key = Self.key(directory: directory, id: id)
        remember(session.document.icon, directory: directory, id: id, key: key)
        let subscription = session.$document.map(\.icon).removeDuplicates().dropFirst().sink { [weak self] icon in
            self?.remember(icon, directory: directory, id: id, key: key)
        }
        followed[identifier] = Followed(session: session, key: key, subscription: subscription)
    }

    package func forget() {
        known.removeAll()
        reading.removeAll()
        followed.removeAll()
    }

    private func forget(_ id: UUID) {
        let suffix = "|" + id.uuidString.lowercased()
        let gone = known.keys.filter { $0.hasSuffix(suffix) }
        guard !gone.isEmpty else { return }
        for key in gone { known[key] = nil }
        followed = followed.filter { $0.value.session != nil && !$0.value.key.hasSuffix(suffix) }
        changes.send(Set(gone))
    }

    private func remember(_ icon: EaselPageIcon?, directory: URL, id: UUID, key: String) {
        let previous = known[key]
        let resolved = resolve(icon, directory: directory)
        known[key] = Entry(icon: icon, resolved: resolved, directory: directory, id: id)
        if previous.map({ $0.icon != icon || $0.resolved != resolved }) ?? false { changes.send([key]) }
    }

    private func read(directory: URL, id: UUID, key: String) {
        guard reading.insert(key).inserted else { return }
        let reader = readIcon
        worker.perform({ reader(directory, id) }) { [weak self] icon in
            guard let self else { return }
            self.reading.remove(key)
            guard self.known[key] == nil else { return }
            self.known[key] = Entry(icon: icon, resolved: self.resolve(icon, directory: directory), directory: directory, id: id)
            self.changes.send([key])
        }
    }

    private func resolve(_ icon: EaselPageIcon?, directory: URL) -> NoteTabIcon? {
        guard let icon else { return nil }
        switch icon.kind {
        case .emoji:
            return .emoji(icon.value)
        case .custom:
            return notesFolder(directory).flatMap { NoteEmojiLibrary.library(root: $0).imageURL(named: icon.value) }
                .map { .image(URL(fileURLWithPath: $0.path, isDirectory: false)) }
        case .image:
            return store(directory)?.assetFileURL(icon.value).map { .image(URL(fileURLWithPath: $0.path, isDirectory: false)) }
        }
    }

    private func resolveAgain(directory: URL? = nil) {
        var changed = Set<String>()
        let path = directory?.standardizedFileURL.path
        for (key, entry) in known where entry.icon != nil && (path == nil ? entry.icon?.kind != .emoji : entry.icon?.kind == .image) {
            if let path, entry.directory.standardizedFileURL.path != path { continue }
            let resolved = resolve(entry.icon, directory: entry.directory)
            guard resolved != entry.resolved else { continue }
            known[key]?.resolved = resolved
            changed.insert(key)
        }
        if !changed.isEmpty { changes.send(changed) }
    }
}

@MainActor
package final class EaselStoreAvailability {
    private var present: Set<String> = []
    private var subscriptions: [AnyCancellable] = []
    private let exists: (String) -> Bool

    package init(exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                 center: NotificationCenter = .default) {
        self.exists = exists
        subscriptions = [
            center.publisher(for: .easelDocumentRemoved).sink { [weak self] _ in self?.present.removeAll() },
        ]
    }

    package func contains(_ directory: URL) -> Bool {
        let path = directory.standardizedFileURL.path
        if present.contains(path) { return true }
        guard exists(path) else { return false }
        present.insert(path)
        return true
    }
}
