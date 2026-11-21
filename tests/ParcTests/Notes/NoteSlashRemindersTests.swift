import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteSlashRemindersTests {
    final class Scheduler: NoteReminderScheduling {
        var pending: [String: NoteReminderRequest] = [:]

        func pendingRequests() async -> [NoteReminderRequest] {
            let snapshot = Array(pending.values)
            await Task.yield()
            return snapshot
        }

        func removeRequests(_ identifiers: [String]) {
            for identifier in identifiers { pending[identifier] = nil }
        }

        func add(_ request: NoteReminderRequest) async {
            await Task.yield()
            pending[request.identifier] = request
        }

        var ours: [NoteReminderRequest] { pending.values.sorted { $0.identifier < $1.identifier } }
    }

    struct Clock {
        let calendar: Calendar
        let now: Date
        let parser: NoteDateParser
        let soon = NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)
        let later = NoteDateMention(year: 2026, month: 12, day: 3, remind: true)

        init() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            self.calendar = calendar
            now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))!
            parser = NoteDateParser(now: now, calendar: calendar, dayFirst: false, locale: Locale(identifier: "en_US"))
        }

        var earlier: Date { now.addingTimeInterval(-60) }
    }

    @MainActor final class Setup {
        let clock = Clock()
        let folder: URL
        let suite = "parc.tests.reminders.\(UUID().uuidString)"
        let defaults: UserDefaults
        let scheduler = Scheduler()
        let book: NoteReminderBook

        init(withLegacy: Bool = false) {
            folder = NoteFilePaths.canonical(FileManager.default.temporaryDirectory.appendingPathComponent("parc-reminders-\(UUID().uuidString)", isDirectory: true))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defaults = UserDefaults(suiteName: suite)!
            if withLegacy {
                let legacy = NoteReminderRequest(identifier: NoteReminderBook.identifierPrefix + folder.path + "/Old.md|2026-11-21T15:30",
                                                 noteID: folder.path + "/Old.md", title: "Old", body: "", fireDate: clock.now.addingTimeInterval(3600),
                                                 bookmark: nil, path: folder.path + "/Old.md")
                scheduler.pending[legacy.identifier] = legacy
                defaults.set([folder.path + "/Old.md"], forKey: NoteReminderBook.legacyKey)
            }
            book = NoteReminderBook(scheduler: scheduler, defaults: defaults)
            let now = clock.now
            book.now = { now }
        }

        deinit {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }

        func page(_ words: String, _ mentions: [NoteDateMention]) -> NotePage {
            var text = NoteText(words)
            for mention in mentions { text = text + NoteText(" ") + NoteText.atom(.date(mention)) }
            return NotePage(blocks: [NoteBlock.paragraph(text)])
        }

        func write(_ text: String, to url: URL) { try? Data(text.utf8).write(to: url, options: .atomic) }

        @discardableResult
        func reconcile(using book: NoteReminderBook? = nil, _ words: String, _ mentions: [NoteDateMention], at document: URL, title: String,
                       openedAt: Date? = nil) -> Bool {
            (book ?? self.book).reconcile(page: page(words, mentions), document: document, title: title, openedAt: openedAt ?? clock.earlier, parser: clock.parser)
        }
    }

    func scheduledGroceries(_ setup: Setup) async -> (URL, NoteReminderRequest?) {
        let groceries = setup.folder.appendingPathComponent("Groceries.md")
        setup.write("Buy milk", to: groceries)
        setup.reconcile("Buy milk", [setup.clock.soon], at: groceries, title: "Groceries")
        await setup.book.drain()
        return (groceries, setup.scheduler.ours.first)
    }

    @Test func theOldListOfNotePathsIsClearedOut() {
        let setup = Setup(withLegacy: true)
        #expect(setup.defaults.object(forKey: NoteReminderBook.legacyKey) == nil)
    }

    @Test func aNoteWithAReminderSchedulesIt() {
        let setup = Setup()
        let groceries = setup.folder.appendingPathComponent("Groceries.md")
        setup.write("Buy milk", to: groceries)
        #expect(setup.reconcile("Buy milk", [setup.clock.soon], at: groceries, title: "Groceries"))
    }

    @Test func theOldPathKeyedReminderIsPrunedAsAnOrphan() async {
        let setup = Setup(withLegacy: true)
        _ = await scheduledGroceries(setup)
        #expect(setup.scheduler.ours.count == 1)
    }

    @Test func reminderIdentityNeverMentionsThePath() async throws {
        let setup = Setup()
        let (_, scheduled) = await scheduledGroceries(setup)
        let request = try #require(scheduled)
        #expect(!request.identifier.contains(setup.folder.path))
        #expect(!request.identifier.contains("Groceries"))
    }

    @Test func theFilesDocumentIdentifierNamesTheNote() async throws {
        let setup = Setup()
        let (_, scheduled) = await scheduledGroceries(setup)
        #expect(try #require(scheduled).noteID.hasPrefix("doc:"))
    }

    @Test func thePayloadCarriesABookmark() async throws {
        let setup = Setup()
        let (groceries, scheduled) = await scheduledGroceries(setup)
        let request = try #require(scheduled)
        #expect(request.bookmark != nil)
        #expect(request.path == groceries.path)
        #expect(request.title == "Groceries")
    }

    @Test func theTrackedNoteIsRecordedByIdentity() async throws {
        let setup = Setup()
        let (groceries, scheduled) = await scheduledGroceries(setup)
        #expect(setup.book.records[try #require(scheduled).noteID]?.path == groceries.path)
    }

    @Test func nothingChangedNothingRescheduled() async {
        let setup = Setup()
        let (groceries, _) = await scheduledGroceries(setup)
        #expect(!setup.reconcile("Buy milk", [setup.clock.soon], at: groceries, title: "Groceries"))
    }

    func renamed(_ setup: Setup) async throws -> (noteID: String, shopping: URL, bookmark: Data?) {
        let (groceries, scheduled) = await scheduledGroceries(setup)
        let request = try #require(scheduled)
        let shopping = setup.folder.appendingPathComponent("Shopping.md")
        try FileManager.default.moveItem(at: groceries, to: shopping)
        setup.write("Buy oat milk", to: shopping)
        setup.book.noteMoved(from: groceries, to: shopping)
        setup.reconcile("Buy milk", [setup.clock.soon], at: shopping, title: "Shopping")
        await setup.book.drain()
        return (request.noteID, shopping, request.bookmark)
    }

    @Test func renamingAndSavingKeepsTheSameReminderWithNoDuplicate() async throws {
        let setup = Setup()
        let result = try await renamed(setup)
        #expect(setup.scheduler.ours.count == 1)
        #expect(setup.scheduler.ours.first?.noteID == result.noteID)
    }

    @Test func theReminderFollowsTheNewName() async throws {
        let setup = Setup()
        let result = try await renamed(setup)
        #expect(setup.scheduler.ours.first?.title == "Shopping")
        #expect(setup.scheduler.ours.first?.path == result.shopping.path)
    }

    func movedOutsideParc(_ setup: Setup) async throws -> (noteID: String, errands: URL, bookmark: Data?, original: URL) {
        let (groceries, scheduled) = await scheduledGroceries(setup)
        let request = try #require(scheduled)
        let errands = setup.folder.appendingPathComponent("Errands", isDirectory: true).appendingPathComponent("Errands.md")
        try FileManager.default.createDirectory(at: errands.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: groceries, to: errands)
        setup.write("Buy bread", to: errands)
        setup.book.prune()
        await setup.book.drain()
        return (request.noteID, errands, request.bookmark, groceries)
    }

    @Test func aMoveOutsideParcIsPickedUpWhenRemindersArePruned() async throws {
        let setup = Setup()
        let result = try await movedOutsideParc(setup)
        #expect(setup.scheduler.ours.count == 1)
        #expect(setup.scheduler.ours.first?.title == "Errands")
        #expect(setup.scheduler.ours.first?.path == result.errands.path)
    }

    @Test func clickingAnOldReminderFindsTheNoteWhereItLivesNow() async throws {
        let setup = Setup()
        let result = try await movedOutsideParc(setup)
        #expect(setup.book.location(noteID: result.noteID, bookmark: result.bookmark, path: result.original.path) == result.errands)
    }

    @Test func trackedNotesSurviveARelaunch() async throws {
        let setup = Setup()
        let result = try await movedOutsideParc(setup)
        let relaunched = NoteReminderBook(scheduler: setup.scheduler, defaults: setup.defaults)
        #expect(relaunched.records[result.noteID]?.path == result.errands.path)
    }

    @Test func reopeningAMovedNoteNeverDuplicatesItsReminder() async throws {
        let setup = Setup()
        let result = try await movedOutsideParc(setup)
        let relaunched = NoteReminderBook(scheduler: setup.scheduler, defaults: setup.defaults)
        let now = setup.clock.now
        relaunched.now = { now }
        setup.reconcile(using: relaunched, "Buy milk", [setup.clock.soon], at: result.errands, title: "Errands", openedAt: now)
        await relaunched.drain()
        #expect(setup.scheduler.ours.count == 1)
        #expect(setup.scheduler.ours.first?.noteID == result.noteID)
    }

    func taxesSetup() -> (Setup, URL) {
        let setup = Setup()
        let taxes = setup.folder.appendingPathComponent("Taxes.md")
        setup.write("File taxes", to: taxes)
        return (setup, taxes)
    }

    @Test func quickBackToBackEditsRunInOrderLeavingOnlyTheLatestReminder() async {
        let (setup, taxes) = taxesSetup()
        setup.reconcile("File taxes", [setup.clock.soon], at: taxes, title: "Taxes")
        setup.reconcile("File taxes", [setup.clock.later], at: taxes, title: "Taxes")
        await setup.book.drain()
        let reminders = setup.scheduler.ours.filter { $0.path == taxes.path }
        #expect(reminders.count == 1)
        #expect(reminders.first?.identifier.hasSuffix("2026-12-03T09:00") == true)
    }

    func forgottenTaxes() async -> (Setup, URL) {
        let (setup, taxes) = taxesSetup()
        setup.reconcile("File taxes", [setup.clock.soon], at: taxes, title: "Taxes")
        await setup.book.drain()
        setup.book.forget(document: taxes)
        await setup.book.drain()
        return (setup, taxes)
    }

    @Test func trashingANoteClearsItsReminders() async {
        let (setup, taxes) = await forgottenTaxes()
        #expect(!setup.scheduler.ours.contains { $0.path == taxes.path })
    }

    @Test func anEditorsLateSyncCannotBringAForgottenNotesRemindersBack() async {
        let (setup, taxes) = await forgottenTaxes()
        #expect(!setup.reconcile("File taxes", [setup.clock.soon], at: taxes, title: "Taxes"))
        await setup.book.drain()
        #expect(!setup.scheduler.ours.contains { $0.path == taxes.path })
    }

    @Test func openingTheNoteAgainLaterBringsItsRemindersBack() async {
        let (setup, taxes) = await forgottenTaxes()
        #expect(setup.reconcile("File taxes", [setup.clock.soon], at: taxes, title: "Taxes", openedAt: setup.clock.now.addingTimeInterval(60)))
        await setup.book.drain()
        #expect(setup.scheduler.ours.contains { $0.path == taxes.path })
    }

    @Test func forgettingAfterADeleteStillFindsTheNoteByItsLastPath() async throws {
        let (setup, taxes) = taxesSetup()
        setup.reconcile("File taxes", [setup.clock.soon], at: taxes, title: "Taxes")
        await setup.book.drain()
        try FileManager.default.removeItem(at: taxes)
        setup.book.forget(document: taxes)
        await setup.book.drain()
        #expect(!setup.scheduler.ours.contains { $0.noteID.hasPrefix("doc:") && $0.title == "Taxes" })
    }

    func trashedOutsideParc() async throws -> Setup {
        let setup = Setup()
        let chores = setup.folder.appendingPathComponent("Chores.md")
        setup.write("Chores", to: chores)
        setup.reconcile("Chores", [setup.clock.later], at: chores, title: "Chores")
        await setup.book.drain()
        let trash = setup.folder.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: chores, to: trash.appendingPathComponent("Chores.md"))
        setup.book.prune()
        await setup.book.drain()
        return setup
    }

    @Test func notesTrashedOutsideParcLoseTheirReminders() async throws {
        #expect(try await trashedOutsideParc().scheduler.ours.isEmpty)
    }

    @Test func trashedNotesDropOffTheTrackedList() async throws {
        let setup = try await trashedOutsideParc()
        #expect(setup.book.records.isEmpty)
        #expect(setup.defaults.data(forKey: NoteReminderBook.recordsKey) == nil)
    }

    @Test func aReminderForADeletedNoteOpensNothing() async throws {
        let setup = Setup()
        let (groceries, scheduled) = await scheduledGroceries(setup)
        let request = try #require(scheduled)
        try FileManager.default.removeItem(at: groceries)
        setup.book.prune()
        await setup.book.drain()
        #expect(setup.book.location(noteID: request.noteID, bookmark: request.bookmark, path: groceries.path) == nil)
    }

    func walk(_ setup: Setup) -> URL {
        let walk = setup.folder.appendingPathComponent("Walk.md")
        setup.write("Walk", to: walk)
        return walk
    }

    @Test func aFreshReminderIsTracked() async {
        let setup = Setup()
        setup.reconcile("Walk", [setup.clock.soon], at: walk(setup), title: "Walk")
        await setup.book.drain()
        #expect(setup.book.records.count == 1)
    }

    @Test func removingTheDateRemovesTheReminderAndTheTracking() async {
        let setup = Setup()
        let walk = walk(setup)
        setup.reconcile("Walk", [setup.clock.soon], at: walk, title: "Walk")
        await setup.book.drain()
        setup.reconcile("Walk", [], at: walk, title: "Walk")
        await setup.book.drain()
        #expect(setup.scheduler.ours.isEmpty)
        #expect(setup.book.records.isEmpty)
    }

    @Test func notesWhoseRemindersHaveAllFiredDropOffTheTrackedList() async {
        let setup = Setup()
        setup.reconcile("Walk", [setup.clock.soon], at: walk(setup), title: "Walk")
        await setup.book.drain()
        let after = setup.clock.calendar.date(from: DateComponents(year: 2026, month: 11, day: 22))!
        setup.book.now = { after }
        setup.book.prune()
        #expect(setup.book.records.isEmpty)
    }
}
