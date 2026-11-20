import Foundation

@MainActor
final class LaggyReminderScheduler: NoteReminderScheduling {
    var pending: [String: NoteReminderRequest] = [:]

    func pendingRequests() async -> [NoteReminderRequest] {
        let snapshot = Array(pending.values)
        try? await Task.sleep(nanoseconds: 3_000_000)
        return snapshot
    }

    func removeRequests(_ identifiers: [String]) {
        for identifier in identifiers { pending[identifier] = nil }
    }

    func add(_ request: NoteReminderRequest) async {
        try? await Task.sleep(nanoseconds: 1_000_000)
        pending[request.identifier] = request
    }

    var ours: [NoteReminderRequest] { pending.values.sorted { $0.identifier < $1.identifier } }
}

@main
struct NoteSlashRemindersTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func page(_ words: String, _ mentions: [NoteDateMention]) -> NotePage {
        var text = NoteText(words)
        for mention in mentions { text = text + NoteText(" ") + NoteText.atom(.date(mention)) }
        return NotePage(blocks: [NoteBlock.paragraph(text)])
    }

    static func write(_ text: String, to url: URL) {
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    @MainActor
    static func main() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))!
        let parser = NoteDateParser(now: now, calendar: calendar, dayFirst: false, locale: Locale(identifier: "en_US"))
        let soon = NoteDateMention(year: 2026, month: 11, day: 21, hour: 15, minute: 30, remind: true)
        let later = NoteDateMention(year: 2026, month: 12, day: 3, remind: true)
        let earlier = now.addingTimeInterval(-60)

        let manager = FileManager.default
        let folder = NoteFilePaths.canonical(manager.temporaryDirectory.appendingPathComponent("parc-reminders-\(UUID().uuidString)", isDirectory: true))
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let suite = "parc.tests.reminders.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let scheduler = LaggyReminderScheduler()
        let legacy = NoteReminderRequest(identifier: NoteReminderBook.identifierPrefix + folder.path + "/Old.md|2026-11-21T15:30",
                                         noteID: folder.path + "/Old.md", title: "Old", body: "", fireDate: now.addingTimeInterval(3600),
                                         bookmark: nil, path: folder.path + "/Old.md")
        scheduler.pending[legacy.identifier] = legacy
        defaults.set([folder.path + "/Old.md"], forKey: NoteReminderBook.legacyKey)
        let book = NoteReminderBook(scheduler: scheduler, defaults: defaults)
        book.now = { now }
        expect(defaults.object(forKey: NoteReminderBook.legacyKey) == nil, "the old list of note paths is cleared out")

        let groceries = folder.appendingPathComponent("Groceries.md")
        write("Buy milk", to: groceries)
        let groceriesPage = page("Buy milk", [soon])
        expect(book.reconcile(page: groceriesPage, document: groceries, title: "Groceries", openedAt: earlier, parser: parser),
               "a note with a reminder schedules it")
        await book.drain()
        let first = scheduler.ours
        expect(first.count == 1, "one reminder, and the old path-keyed one is pruned as an orphan: \(first.map(\.identifier))")
        guard let scheduled = first.first else { return }
        let noteID = scheduled.noteID
        expect(!scheduled.identifier.contains(folder.path) && !scheduled.identifier.contains("Groceries"), "reminder identity never mentions the path")
        expect(noteID.hasPrefix("doc:"), "the file's document identifier names the note: \(noteID)")
        expect(scheduled.bookmark != nil && scheduled.path == groceries.path && scheduled.title == "Groceries", "the payload carries a bookmark")
        expect(book.records[noteID]?.path == groceries.path, "the tracked note is recorded by identity")
        expect(!book.reconcile(page: groceriesPage, document: groceries, title: "Groceries", openedAt: earlier, parser: parser),
               "nothing changed, nothing rescheduled")

        let shopping = folder.appendingPathComponent("Shopping.md")
        try? manager.moveItem(at: groceries, to: shopping)
        write("Buy oat milk", to: shopping)
        book.noteMoved(from: groceries, to: shopping)
        book.reconcile(page: groceriesPage, document: shopping, title: "Shopping", openedAt: earlier, parser: parser)
        await book.drain()
        let renamed = scheduler.ours
        expect(renamed.count == 1 && renamed.first?.noteID == noteID, "renaming and saving keeps the same reminder, no duplicate")
        expect(renamed.first?.title == "Shopping" && renamed.first?.path == shopping.path, "the reminder follows the new name")

        let errands = folder.appendingPathComponent("Errands", isDirectory: true).appendingPathComponent("Errands.md")
        try? manager.createDirectory(at: errands.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.moveItem(at: shopping, to: errands)
        write("Buy bread", to: errands)
        book.prune()
        await book.drain()
        let moved = scheduler.ours
        expect(moved.count == 1 && moved.first?.title == "Errands" && moved.first?.path == errands.path,
               "a move outside Parc is picked up when reminders are pruned: \(moved.map { $0.title })")
        expect(book.location(noteID: noteID, bookmark: scheduled.bookmark, path: groceries.path) == errands,
               "clicking an old reminder finds the note where it lives now")

        let relaunched = NoteReminderBook(scheduler: scheduler, defaults: defaults)
        relaunched.now = { now }
        expect(relaunched.records[noteID]?.path == errands.path, "the tracked notes survive a relaunch")
        relaunched.reconcile(page: groceriesPage, document: errands, title: "Errands", openedAt: now, parser: parser)
        await relaunched.drain()
        expect(scheduler.ours.count == 1 && scheduler.ours.first?.noteID == noteID, "reopening a moved note never duplicates its reminder")

        let taxes = folder.appendingPathComponent("Taxes.md")
        write("File taxes", to: taxes)
        let taxesPage = page("File taxes", [soon])
        relaunched.reconcile(page: taxesPage, document: taxes, title: "Taxes", openedAt: earlier, parser: parser)
        relaunched.reconcile(page: page("File taxes", [later]), document: taxes, title: "Taxes", openedAt: earlier, parser: parser)
        await relaunched.drain()
        let taxReminders = scheduler.ours.filter { $0.path == taxes.path }
        expect(taxReminders.count == 1 && taxReminders.first?.identifier.hasSuffix("2026-12-03T09:00") == true,
               "quick back-to-back edits run in order, leaving only the latest reminder: \(taxReminders.map(\.identifier))")

        relaunched.forget(document: taxes)
        await relaunched.drain()
        expect(!scheduler.ours.contains { $0.path == taxes.path }, "trashing a note clears its reminders")
        expect(!relaunched.reconcile(page: taxesPage, document: taxes, title: "Taxes", openedAt: earlier, parser: parser),
               "an editor's late sync can't bring a forgotten note's reminders back")
        await relaunched.drain()
        expect(!scheduler.ours.contains { $0.path == taxes.path }, "still nothing for the forgotten note")
        expect(relaunched.reconcile(page: taxesPage, document: taxes, title: "Taxes", openedAt: now.addingTimeInterval(60), parser: parser),
               "opening the note again later brings its reminders back")
        await relaunched.drain()
        expect(scheduler.ours.contains { $0.path == taxes.path }, "and they're scheduled")

        try? manager.removeItem(at: taxes)
        relaunched.forget(document: taxes)
        await relaunched.drain()
        expect(!scheduler.ours.contains { $0.noteID.hasPrefix("doc:") && $0.title == "Taxes" }, "forgetting after a delete still finds the note by its last path")

        let chores = folder.appendingPathComponent("Chores.md")
        write("Chores", to: chores)
        relaunched.reconcile(page: page("Chores", [later]), document: chores, title: "Chores", openedAt: earlier, parser: parser)
        await relaunched.drain()
        let trash = folder.appendingPathComponent(".Trash", isDirectory: true)
        try? manager.createDirectory(at: trash, withIntermediateDirectories: true)
        try? manager.moveItem(at: chores, to: trash.appendingPathComponent("Chores.md"))
        try? manager.removeItem(at: errands)
        relaunched.prune()
        await relaunched.drain()
        expect(scheduler.ours.isEmpty, "notes trashed or deleted outside Parc lose their reminders: \(scheduler.ours.map(\.title))")
        expect(relaunched.records.isEmpty && defaults.data(forKey: NoteReminderBook.recordsKey) == nil, "and drop off the tracked list")
        expect(relaunched.location(noteID: noteID, bookmark: scheduled.bookmark, path: groceries.path) == nil, "a reminder for a deleted note opens nothing")

        let walk = folder.appendingPathComponent("Walk.md")
        write("Walk", to: walk)
        relaunched.reconcile(page: page("Walk", [soon]), document: walk, title: "Walk", openedAt: earlier, parser: parser)
        await relaunched.drain()
        expect(relaunched.records.count == 1, "a fresh reminder is tracked")
        relaunched.reconcile(page: page("Walk", []), document: walk, title: "Walk", openedAt: earlier, parser: parser)
        await relaunched.drain()
        expect(scheduler.ours.isEmpty && relaunched.records.isEmpty, "removing the date removes the reminder and the tracking")
        relaunched.reconcile(page: page("Walk", [soon]), document: walk, title: "Walk", openedAt: earlier, parser: parser)
        await relaunched.drain()
        relaunched.now = { calendar.date(from: DateComponents(year: 2026, month: 11, day: 22))! }
        relaunched.prune()
        expect(relaunched.records.isEmpty, "notes whose reminders have all fired drop off the tracked list")

        print("NoteSlashRemindersTests passed")
    }
}
