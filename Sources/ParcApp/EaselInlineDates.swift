import AppKit
import Combine

@MainActor
final class EaselInlineDates {
    static let shared = EaselInlineDates()

    private final class Watch {
        weak var session: EaselSession?
        let file: URL
        let openedAt = Date()
        var subscription: AnyCancellable?
        var task: Task<Void, Never>?
        init(session: EaselSession, file: URL) { self.session = session; self.file = file }
    }

    private var watches: [UUID: Watch] = [:]
    private var refresher: NoteDateRefresher?
    private var directories: [URL] = []

    func attach(to store: EaselStore) {
        let created = store.onSessionCreated, removed = store.onDocumentRemoved
        let documents = store.documentsDirectory
        if !directories.contains(documents) { directories.append(documents) }
        store.onSessionCreated = { [weak self] session in
            created?(session)
            self?.follow(session, file: documents.appendingPathComponent(session.document.id.uuidString.lowercased() + ".json"))
        }
        store.onDocumentRemoved = { [weak self] id in
            removed?(id)
            self?.forget(id, file: documents.appendingPathComponent(id.uuidString.lowercased() + ".json"))
        }
    }

    private func follow(_ session: EaselSession, file: URL) {
        let id = session.document.id
        watches[id]?.task?.cancel()
        let watch = Watch(session: session, file: file)
        watch.subscription = session.$document.dropFirst().sink { [weak self, weak watch] _ in
            guard let self, let watch else { return }
            watch.task?.cancel()
            watch.task = Task { @MainActor [weak self, weak watch] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled, let self, let watch else { return }
                self.sync(watch)
            }
        }
        watches[id] = watch
        sync(watch)
    }

    private func forget(_ id: UUID, file: URL) {
        watches.removeValue(forKey: id)?.task?.cancel()
        defer { refresher?.reschedule() }
        if let moved = EaselReminderOwner.destination(of: id, in: directories.filter { $0 != file.deletingLastPathComponent() },
                                                      exists: { FileManager.default.fileExists(atPath: $0.path) }) {
            guard let data = try? Data(contentsOf: moved, options: .mappedIfSafe), data.count <= EaselStore.maximumDocumentBytes,
                  let document = try? JSONDecoder().decode(EaselDocument.self, from: data) else { return }
            NoteReminderCenter.shared.reconcile(page: document.reminderPage, document: moved,
                                                title: document.title.isEmpty ? "Untitled Easel" : document.title, openedAt: Date())
            return
        }
        NoteReminderCenter.shared.forget(document: file)
    }

    private func sync(_ watch: Watch) {
        guard let session = watch.session, !session.isDeleted, !session.isClosed else { return }
        let document = session.document
        if FileManager.default.fileExists(atPath: watch.file.path) {
            NoteReminderCenter.shared.reconcile(page: document.reminderPage, document: watch.file,
                                                title: document.title.isEmpty ? "Untitled Easel" : document.title, openedAt: watch.openedAt)
        }
        if refresher == nil, !document.dateMentions.isEmpty {
            refresher = NoteDateRefresher(mentions: { [weak self] in self?.mentions() }, refresh: { [weak self] in
                guard self != nil else { return false }
                EaselInlineText.refreshDates()
                NotificationCenter.default.post(name: EaselInlineText.datesChanged, object: nil)
                return true
            })
        } else {
            refresher?.reschedule()
        }
    }

    private func mentions() -> [NoteDateMention] {
        watches = watches.filter { $0.value.session != nil }
        return watches.values.flatMap { $0.session?.document.dateMentions ?? [] }
    }

    static func open(_ owner: EaselReminderOwner, in windows: [BrowserWindowController], front: BrowserWindowController?) {
        let usable = windows.filter { !$0.isPopupWindow && !$0.isPrivateBrowsing }
        guard let target = usable.first(where: { $0.activeProfileID == owner.profile }) ?? front ?? usable.first else { return }
        let title = NoteReminderCenter.shared.book.records.values.first { $0.path == owner.file.path }?.title ?? ""
        target.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        target.openEasel(id: owner.id, title: title)
    }
}
