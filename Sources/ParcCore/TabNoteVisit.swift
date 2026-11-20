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
}

extension BrowserTab {
    var showsNoteOverPage: Bool { noteVisit?.showsNote == true }
    var hasNoteAhead: Bool { noteVisit.map { !$0.showsNote } ?? false }

    @discardableResult
    mutating func openNoteVisit(url noteURL: URL, title noteTitle: String) -> Bool {
        guard archivedAt == nil, !InternalPage.isInternal(url), !BrowserState.isBlankPage(url),
              let file = InternalPage.noteFile(noteURL) else { return false }
        let note = TabNoteVisit.Entry(url: InternalPage.note(file).urlString,
                                      title: InternalPage.noteTitle(noteTitle, file: file))
        noteVisit = TabNoteVisit(page: .init(url: url, title: title), note: note, showsNote: true)
        show(note)
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
