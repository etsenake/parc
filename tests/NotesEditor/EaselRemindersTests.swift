import Foundation

@MainActor
final class EaselReminderScheduler: NoteReminderScheduling {
    var pending: [String: NoteReminderRequest] = [:]
    func pendingRequests() async -> [NoteReminderRequest] { Array(pending.values) }
    func removeRequests(_ identifiers: [String]) { for identifier in identifiers { pending[identifier] = nil } }
    func add(_ request: NoteReminderRequest) async { pending[request.identifier] = request }
}

@main
struct EaselRemindersTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func easel(_ title: String, reminder: NoteDateMention) -> EaselDocument {
        let text = "Ship \u{FFFC}"
        let font = EaselRichText.Font(name: "Helvetica", size: 15)
        let rich = EaselRichText(runs: [
            .init(location: 0, length: 5, attributes: .init(font: font, ink: "#000000FF")),
            .init(location: 5, length: 1, attributes: .init(font: font, ink: "#000000FF", inline: .date(reminder))),
        ])
        let item = EaselItem(kind: .sticky, frame: EaselRect(x: 0, y: 0, width: 100, height: 100), text: text, richText: rich)
        return EaselDocument(id: UUID(), title: title, createdAt: Date(), modifiedAt: Date(), items: [item])
    }

    @MainActor
    static func main() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))!
        let parser = NoteDateParser(now: now, calendar: calendar, dayFirst: false, locale: Locale(identifier: "en_US"))
        let soon = NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)
        let manager = FileManager.default
        let root = NoteFilePaths.canonical(manager.temporaryDirectory.appendingPathComponent("parc-easel-reminders-\(UUID().uuidString)", isDirectory: true))
        let profileA = UUID(), profileB = UUID()
        let documentsA = root.appendingPathComponent("Profiles/\(profileA.uuidString)/Easels/documents", isDirectory: true)
        let documentsB = root.appendingPathComponent("Profiles/\(profileB.uuidString)/Easels/documents", isDirectory: true)
        try? manager.createDirectory(at: documentsA, withIntermediateDirectories: true)
        try? manager.createDirectory(at: documentsB, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let suite = "parc.tests.easel-reminders.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let scheduler = EaselReminderScheduler()
        let book = NoteReminderBook(scheduler: scheduler, defaults: defaults)
        book.now = { now }

        let document = easel("Launch", reminder: soon)
        let name = document.id.uuidString.lowercased() + ".json"
        let file = documentsA.appendingPathComponent(name)
        try? JSONEncoder().encode(document).write(to: file)
        expect(EaselReminderOwner(file: file)?.profile == profileA, "the Easel file names its Profile")
        let opened = now.addingTimeInterval(-60)
        expect(book.reconcile(page: document.reminderPage, document: file, title: document.title, openedAt: opened, parser: parser),
               "an Easel with a reminder schedules it")
        await book.drain()
        expect(scheduler.pending.values.map(\.title) == ["Launch"], "the notification is named after the Easel")

        try? manager.removeItem(at: file)
        book.now = { now.addingTimeInterval(10) }
        book.forget(document: file)
        await book.drain()
        expect(scheduler.pending.isEmpty, "deleting an Easel clears its reminders")
        try? JSONEncoder().encode(document).write(to: file)
        expect(!book.reconcile(page: document.reminderPage, document: file, title: document.title, openedAt: opened, parser: parser),
               "an old watch stays buried after the delete")
        expect(book.reconcile(page: document.reminderPage, document: file, title: document.title, openedAt: now.addingTimeInterval(20), parser: parser),
               "a restored Easel's new watch lifts the tombstone")
        await book.drain()
        expect(scheduler.pending.count == 1, "the restored Easel rings again")

        let moved = documentsB.appendingPathComponent(name)
        try? manager.moveItem(at: file, to: moved)
        expect(EaselReminderOwner.destination(of: document.id, in: [documentsA, documentsB], exists: { manager.fileExists(atPath: $0.path) }) == moved,
               "a moved Easel is found in its new Profile")
        expect(EaselReminderOwner.destination(of: UUID(), in: [documentsA, documentsB], exists: { manager.fileExists(atPath: $0.path) }) == nil,
               "a deleted Easel is found nowhere")
        var renamed = document
        renamed.title = "Launch day"
        expect(book.reconcile(page: renamed.reminderPage, document: moved, title: renamed.title, openedAt: now.addingTimeInterval(30), parser: parser),
               "the moved Easel re-registers")
        await book.drain()
        expect(scheduler.pending.count == 1 && scheduler.pending.values.first?.path == moved.path
               && scheduler.pending.values.first?.title == "Launch day", "reminders follow the Easel to its new Profile and name")
        print("EaselRemindersTests passed")
    }
}
