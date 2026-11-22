import AppKit
import ParcCore

@MainActor
enum NoteMentionMenu {
    enum Scope: Hashable {
        case everything, notes, dates, noteBlock

        var showsNotes: Bool { self != .dates }
        var showsDates: Bool { self == .everything || self == .dates }
    }

    enum Choice {
        case note(NoteReference)
        case createNote(String)
        case date(NoteDateMention)
    }

    struct Contents {
        var items: [NoteMenuList.Item] = []
        var choices: [String: Choice] = [:]
        var hasResults: Bool { !items.isEmpty }
    }

    static let notesSection = "Notes"
    static let datesSection = "Dates"
    static let remindSection = "Remind me"
    static let noteLimit = 6

    static func contents(for rawQuery: String, scope: Scope, environment: NoteEnvironment, parser: NoteDateParser) -> Contents {
        var result = Contents()
        var notesFound = false
        var creating: NoteMenuList.Item?
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        let reminder = NoteDateParser.reminderQuery(query)
        let folder = environment.documentURL?.deletingLastPathComponent()
        if scope.showsNotes && !reminder.remind {
            let current = environment.documentURL?.standardizedFileURL
            let notes = environment.searchNotes(query, limit: noteLimit + 1).filter { $0.url.standardizedFileURL != current }.prefix(noteLimit)
            for (index, note) in notes.enumerated() {
                let id = "note.\(index)"
                var item = NoteMenuList.Item(id: id, title: note.title.isEmpty ? "Untitled" : note.title,
                                             subtitle: folderName(of: note.url, relativeTo: folder),
                                             icon: NoteIcon.note(note.icon, at: note.url), section: notesSection)
                item.accessibilityLabel = "Note, " + item.title
                result.items.append(item)
                result.choices[id] = .note(note)
                notesFound = true
            }
            if !query.isEmpty, folder != nil,
               !notes.contains(where: { $0.title.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                var item = NoteMenuList.Item(id: "note.create", title: "New note “\(query)”", subtitle: scope == .noteBlock ? nil : "in this folder",
                                             icon: .symbol("plus"), section: notesSection)
                item.accessibilityLabel = "Create a new note called \(query)"
                result.choices[item.id] = .createNote(query)
                if notesFound { result.items.append(item) } else { creating = item }
            }
        }
        if scope.showsDates {
            if !reminder.remind {
                for (index, suggestion) in parser.suggestions(for: query).enumerated() {
                    let id = "date.\(index)"
                    var item = NoteMenuList.Item(id: id, title: suggestion.title, subtitle: subtitle(for: suggestion.mention, parser: parser),
                                                 icon: .symbol("calendar"), section: datesSection)
                    item.accessibilityLabel = "Date, " + NoteDateFormatting.longLabel(suggestion.mention, calendar: parser.calendar, locale: parser.locale)
                    result.items.append(item)
                    result.choices[id] = .date(suggestion.mention)
                }
            }
            let reminders = parser.suggestions(for: reminder.remind ? reminder.query : query, remind: true, limit: reminder.remind ? 4 : (query.isEmpty ? 1 : 2))
            for (index, suggestion) in reminders.enumerated() {
                let id = "remind.\(index)"
                var item = NoteMenuList.Item(id: id, title: suggestion.title, subtitle: subtitle(for: suggestion.mention, parser: parser), icon: .symbol("bell"), section: remindSection)
                item.accessibilityLabel = "Remind me " + NoteDateFormatting.longLabel(suggestion.mention, calendar: parser.calendar, locale: parser.locale)
                result.items.append(item)
                result.choices[id] = .date(suggestion.mention)
            }
            if reminders.isEmpty, reminder.remind, let passed = parser.passedReminder(for: reminder.query) {
                var item = NoteMenuList.Item(id: "remind.passed", title: passed.title, subtitle: "Already passed", icon: .symbol("bell"), section: remindSection)
                item.isEnabled = false
                item.accessibilityLabel = NoteDateFormatting.longLabel(passed.mention, calendar: parser.calendar, locale: parser.locale) + " has already passed"
                result.items.append(item)
            }
        }
        if let creating { result.items.append(creating) }
        return result
    }

    static func isStillTyping(_ query: String, scope: Scope, parser: NoteDateParser) -> Bool {
        guard scope.showsDates else { return false }
        let reminder = NoteDateParser.reminderQuery(query)
        return parser.isPlausiblePrefix(reminder.remind ? reminder.query : query)
    }

    static func noResultsTitle(for scope: Scope) -> String {
        switch scope {
        case .dates: return "That doesn’t look like a date yet."
        case .notes, .noteBlock: return "No notes by that name. Keep typing?"
        case .everything: return "Nothing yet. Try a note’s name or a date."
        }
    }

    static func folderName(of url: URL, relativeTo folder: URL?) -> String? {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        if let folder, parent == folder.standardizedFileURL { return nil }
        let name = parent.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    static func subtitle(for mention: NoteDateMention, parser: NoteDateParser) -> String? {
        NoteDateText.suggestionDateHint(mention, now: parser.now, calendar: parser.calendar, locale: parser.locale)
    }
}
