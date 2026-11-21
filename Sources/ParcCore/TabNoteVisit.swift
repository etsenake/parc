import Foundation

struct TabNoteVisit: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var url: String
        var title: String
    }

    var page: Entry
    var note: Entry
    var showsNote: Bool

    var shown: Entry { showsNote ? note : page }
    var noteFile: URL? { InternalPage.noteFile(note.url) }
    var document: InternalPage? { InternalPage(urlString: note.url) }

    static func entry(_ document: InternalPage, title: String) -> Entry? {
        switch document {
        case .note(let url):
            guard let file = InternalPage.noteFile(url) else { return nil }
            return Entry(url: InternalPage.note(file).urlString, title: InternalPage.noteTitle(title, file: file))
        case .easel:
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return Entry(url: document.urlString, title: name.isEmpty ? document.untitledTitle : name)
        }
    }
}

extension BrowserTab {
    var showsNoteOverPage: Bool { noteVisit?.showsNote == true }
    var hasNoteAhead: Bool { noteVisit.map { !$0.showsNote } ?? false }

    @discardableResult
    mutating func openNoteVisit(url noteURL: URL, title noteTitle: String) -> Bool {
        openDocumentVisit(.note(noteURL), title: noteTitle)
    }

    @discardableResult
    mutating func openDocumentVisit(_ document: InternalPage, title documentTitle: String) -> Bool {
        guard archivedAt == nil, let entry = TabNoteVisit.entry(document, title: documentTitle) else { return false }
        if var visit = noteVisit, visit.showsNote, InternalPage.isInternal(url) {
            visit.note = entry
            noteVisit = visit
        } else {
            guard !InternalPage.isInternal(url), !BrowserState.isBlankPage(url) else { return false }
            noteVisit = TabNoteVisit(page: .init(url: url, title: title), note: entry, showsNote: true)
        }
        show(entry)
        return true
    }

    @discardableResult
    mutating func stepBackFromNote() -> Bool {
        guard var visit = noteVisit, visit.showsNote, archivedAt == nil else { return false }
        visit.note = .init(url: url, title: title)
        visit.showsNote = false
        noteVisit = visit
        show(visit.page)
        return true
    }

    @discardableResult
    mutating func stepForwardToNote() -> Bool {
        guard var visit = noteVisit, !visit.showsNote, archivedAt == nil, !InternalPage.isInternal(url) else { return false }
        visit.page = .init(url: url, title: title)
        visit.showsNote = true
        noteVisit = visit
        show(visit.note)
        return true
    }

    @discardableResult
    mutating func followPageUnderNote(url pageURL: String?, title pageTitle: String?) -> Bool {
        guard var visit = noteVisit, visit.showsNote else { return false }
        let before = visit
        if let pageURL, !pageURL.isEmpty { visit.page.url = BrowserInternalURL.publicString(pageURL) }
        if let pageTitle, !pageTitle.isEmpty { visit.page.title = pageTitle }
        guard visit != before else { return false }
        noteVisit = visit
        return true
    }

    @discardableResult
    mutating func followNoteRename(from matches: (String) -> Bool, to destination: String, title noteTitle: String) -> Bool {
        guard var visit = noteVisit, matches(visit.note.url) else { return false }
        let before = visit
        visit.note = .init(url: destination, title: noteTitle)
        guard visit != before else { return false }
        noteVisit = visit
        return true
    }

    @discardableResult
    mutating func forgetNote(matching matches: (String) -> Bool) -> Bool {
        guard let visit = noteVisit, matches(visit.note.url) else { return false }
        noteVisit = nil
        if visit.showsNote { show(visit.page) }
        return true
    }

    private mutating func show(_ entry: TabNoteVisit.Entry) {
        url = entry.url
        title = entry.title
        if kind == .today {
            savedURL = entry.url
            savedTitle = entry.title
        }
    }
}
