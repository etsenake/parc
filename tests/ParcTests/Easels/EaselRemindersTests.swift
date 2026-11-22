import Foundation
import ParcTestSupport
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct EaselRemindersTests {
    final class Scheduler: NoteReminderScheduling {
        var pending: [String: NoteReminderRequest] = [:]
        func pendingRequests() async -> [NoteReminderRequest] { Array(pending.values) }
        func removeRequests(_ identifiers: [String]) { for identifier in identifiers { pending[identifier] = nil } }
        func add(_ request: NoteReminderRequest) async { pending[request.identifier] = request }
    }

    @MainActor final class Setup {
        let now: Date
        let parser: NoteDateParser
        let root: URL
        let profileA = UUID(), profileB = UUID()
        let documentsA: URL
        let documentsB: URL
        let defaults: UserDefaults
        let scheduler = Scheduler()
        let book: NoteReminderBook
        let document: EaselDocument
        let file: URL

        init() throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))!
            parser = NoteDateParser(now: now, calendar: calendar, dayFirst: false, locale: Locale(identifier: "en_US"))
            root = NoteFilePaths.canonical(FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-reminders-\(UUID().uuidString)", isDirectory: true))
            documentsA = root.appendingPathComponent("Profiles/\(profileA.uuidString)/Easels/documents", isDirectory: true)
            documentsB = root.appendingPathComponent("Profiles/\(profileB.uuidString)/Easels/documents", isDirectory: true)
            try FileManager.default.createDirectory(at: documentsA, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: documentsB, withIntermediateDirectories: true)
            defaults = TestDefaults("parc.tests.easel-reminders.")!
            book = NoteReminderBook(scheduler: scheduler, defaults: defaults)
            let now = now
            book.now = { now }
            document = Self.easel("Launch", reminder: NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true))
            file = documentsA.appendingPathComponent(document.id.uuidString.lowercased() + ".json")
            try save()
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        static func easel(_ title: String, reminder: NoteDateMention) -> EaselDocument {
            let font = EaselRichText.Font(name: "Helvetica", size: 15)
            let rich = EaselRichText(runs: [
                .init(location: 0, length: 5, attributes: .init(font: font, ink: "#000000FF")),
                .init(location: 5, length: 1, attributes: .init(font: font, ink: "#000000FF", inline: .date(reminder))),
            ])
            let item = EaselItem(kind: .sticky, frame: EaselRect(x: 0, y: 0, width: 100, height: 100), text: "Ship \u{FFFC}", richText: rich)
            return EaselDocument(id: UUID(), title: title, createdAt: Date(), modifiedAt: Date(), items: [item])
        }

        func save() throws {
            try JSONEncoder().encode(document).write(to: file)
        }

        @discardableResult
        func reconcile(_ document: EaselDocument? = nil, at file: URL? = nil, openedAfter seconds: TimeInterval) -> Bool {
            let document = document ?? self.document
            return book.reconcile(page: document.reminderPage, document: file ?? self.file, title: document.title,
                                  openedAt: now.addingTimeInterval(seconds), parser: parser)
        }

        func delete() async {
            try? FileManager.default.removeItem(at: file)
            let now = now
            book.now = { now.addingTimeInterval(10) }
            book.forget(document: file)
            await book.drain()
        }

        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    }

    @Test func theEaselFileNamesItsProfile() throws {
        let setup = try Setup()
        #expect(EaselReminderOwner(file: setup.file)?.profile == setup.profileA)
    }

    @Test func anEaselWithAReminderSchedulesItNamedAfterTheEasel() async throws {
        let setup = try Setup()
        #expect(setup.reconcile(openedAfter: -60))
        await setup.book.drain()
        #expect(setup.scheduler.pending.values.map(\.title) == ["Launch"])
    }

    @Test func deletingAnEaselClearsItsReminders() async throws {
        let setup = try Setup()
        setup.reconcile(openedAfter: -60)
        await setup.book.drain()
        await setup.delete()
        #expect(setup.scheduler.pending.isEmpty)
    }

    @Test func anOldWatchStaysBuriedAfterTheDelete() async throws {
        let setup = try Setup()
        setup.reconcile(openedAfter: -60)
        await setup.book.drain()
        await setup.delete()
        try setup.save()
        #expect(!setup.reconcile(openedAfter: -60))
    }

    @Test func aRestoredEaselsNewWatchLiftsTheTombstoneAndRingsAgain() async throws {
        let setup = try Setup()
        setup.reconcile(openedAfter: -60)
        await setup.book.drain()
        await setup.delete()
        try setup.save()
        #expect(setup.reconcile(openedAfter: 20))
        await setup.book.drain()
        #expect(setup.scheduler.pending.count == 1)
    }

    @Test func aMovedEaselIsFoundInItsNewProfile() throws {
        let setup = try Setup()
        let moved = setup.documentsB.appendingPathComponent(setup.file.lastPathComponent)
        try FileManager.default.moveItem(at: setup.file, to: moved)
        #expect(EaselReminderOwner.destination(of: setup.document.id, in: [setup.documentsA, setup.documentsB], exists: setup.exists) == moved)
    }

    @Test func aDeletedEaselIsFoundNowhere() throws {
        let setup = try Setup()
        #expect(EaselReminderOwner.destination(of: UUID(), in: [setup.documentsA, setup.documentsB], exists: setup.exists) == nil)
    }

    @Test func remindersFollowTheEaselToItsNewProfileAndName() async throws {
        let setup = try Setup()
        setup.reconcile(openedAfter: -60)
        await setup.book.drain()
        let moved = setup.documentsB.appendingPathComponent(setup.file.lastPathComponent)
        try FileManager.default.moveItem(at: setup.file, to: moved)
        var renamed = setup.document
        renamed.title = "Launch day"
        #expect(setup.reconcile(renamed, at: moved, openedAfter: 30))
        await setup.book.drain()
        #expect(setup.scheduler.pending.count == 1)
        #expect(setup.scheduler.pending.values.first?.path == moved.path)
        #expect(setup.scheduler.pending.values.first?.title == "Launch day")
    }
}
