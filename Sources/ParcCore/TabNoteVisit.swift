import Foundation

struct TabNoteVisit: Equatable {
    struct Entry: Codable, Equatable {
        var url: String
        var title: String
    }

    static let limit = 50

    var page: Entry
    private(set) var documents: [Entry]
    private(set) var position: Int?

    init(page: Entry, documents: [Entry], position: Int?) {
        let kept = Array(documents.suffix(Self.limit))
        let dropped = documents.count - kept.count
        self.page = page
        self.documents = kept
        self.position = position.map { min(max($0 - dropped, 0), max(kept.count - 1, 0)) }
    }

    init(page: Entry, note: Entry, showsNote: Bool) {
        self.init(page: page, documents: [note], position: showsNote ? 0 : nil)
    }

    var showsNote: Bool { position != nil }
    var current: Entry? { position.map { documents[$0] } }
    var shown: Entry { current ?? page }
    var behind: [Entry] { position.map { Array(documents[..<$0].reversed()) + [page] } ?? [] }
    var ahead: [Entry] { Array(documents[((position ?? -1) + 1)...]) }
    var note: Entry { current ?? documents[0] }
    var noteFile: URL? { InternalPage.noteFile(note.url) }
    var document: InternalPage? { InternalPage(urlString: note.url) }

    static func noteFile(_ entry: Entry) -> URL? { InternalPage.noteFile(entry.url) }
    static func document(_ entry: Entry) -> InternalPage? { InternalPage(urlString: entry.url) }

    func step(_ offset: Int) -> Entry? {
        let target = (position ?? -1) + offset
        guard offset != 0, (-1..<documents.count).contains(target) else { return nil }
        return target < 0 ? page : documents[target]
    }

    mutating func syncShown(url: String, title: String) {
        if let position { documents[position] = .init(url: url, title: title) } else { page = .init(url: url, title: title) }
    }

    mutating func move(by offset: Int) -> Bool {
        guard step(offset) != nil else { return false }
        let target = (position ?? -1) + offset
        position = target < 0 ? nil : target
        return true
    }

    mutating func push(_ entry: Entry) {
        let base = position ?? -1
        var kept = Array(documents[...base])
        if kept.last?.url == entry.url { kept[kept.count - 1] = entry } else { kept.append(entry) }
        self = TabNoteVisit(page: page, documents: kept, position: kept.count - 1)
    }

    mutating func rename(matching matches: (String) -> Bool, to destination: String, title: String) -> Bool {
        let renamed = documents.map { matches($0.url) ? Entry(url: destination, title: title) : $0 }
        guard renamed != documents else { return false }
        self = Self.collapsed(page: page, documents: renamed.enumerated().map { ($0.offset, $0.element) },
                              shown: position) ?? self
        return true
    }

    func removing(matching matches: (String) -> Bool) -> TabNoteVisit? {
        let kept = documents.enumerated().filter { !matches($0.element.url) }.map { ($0.offset, $0.element) }
        let shown = position.flatMap { position in kept.last { $0.0 <= position }?.0 }
        return Self.collapsed(page: page, documents: kept, shown: shown)
    }

    private static func collapsed(page: Entry, documents: [(Int, Entry)], shown: Int?) -> TabNoteVisit? {
        var entries: [Entry] = [], position: Int?
        for (index, entry) in documents {
            if entries.last?.url != entry.url { entries.append(entry) }
            if index == shown { position = entries.count - 1 }
        }
        guard !entries.isEmpty else { return nil }
        return TabNoteVisit(page: page, documents: entries, position: position)
    }

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

extension TabNoteVisit: Codable {
    private enum CodingKeys: String, CodingKey { case page, note, showsNote, documents, position }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let page = try values.decode(Entry.self, forKey: .page)
        if let documents = try? values.decodeIfPresent([Entry].self, forKey: .documents), !documents.isEmpty {
            let position = try? values.decodeIfPresent(Int.self, forKey: .position)
            guard position.map({ documents.indices.contains($0) }) ?? true else {
                throw DecodingError.dataCorruptedError(forKey: .position, in: values, debugDescription: "Step outside the visit")
            }
            self.init(page: page, documents: documents, position: position)
        } else {
            self.init(page: page, note: try values.decode(Entry.self, forKey: .note),
                      showsNote: try values.decode(Bool.self, forKey: .showsNote))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(page, forKey: .page)
        try values.encode(note, forKey: .note)
        try values.encode(showsNote, forKey: .showsNote)
        try values.encode(documents, forKey: .documents)
        try values.encodeIfPresent(position, forKey: .position)
    }
}

extension BrowserTab {
    var showsNoteOverPage: Bool { noteVisit?.showsNote == true }
    var hasNoteAhead: Bool { noteVisit.map { !$0.ahead.isEmpty } ?? false }

    @discardableResult
    mutating func openNoteVisit(url noteURL: URL, title noteTitle: String) -> Bool {
        openDocumentVisit(.note(noteURL), title: noteTitle)
    }

    @discardableResult
    mutating func openDocumentVisit(_ document: InternalPage, title documentTitle: String) -> Bool {
        guard archivedAt == nil, let entry = TabNoteVisit.entry(document, title: documentTitle) else { return false }
        if var visit = noteVisit, visit.showsNote, InternalPage.isInternal(url) {
            visit.syncShown(url: url, title: title)
            visit.push(entry)
            noteVisit = visit
        } else {
            guard !InternalPage.isInternal(url), !BrowserState.isBlankPage(url) else { return false }
            noteVisit = TabNoteVisit(page: .init(url: url, title: title), note: entry, showsNote: true)
        }
        show(entry)
        return true
    }

    @discardableResult
    mutating func stepBackFromNote() -> Bool { stepNoteVisit(by: -1) }

    @discardableResult
    mutating func stepForwardToNote() -> Bool { stepNoteVisit(by: 1) }

    @discardableResult
    mutating func stepNoteVisit(by offset: Int) -> Bool {
        guard var visit = noteVisit, archivedAt == nil, visit.step(offset) != nil,
              visit.showsNote == InternalPage.isInternal(url) else { return false }
        visit.syncShown(url: url, title: title)
        guard visit.move(by: offset) else { return false }
        noteVisit = visit
        show(visit.shown)
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
        guard var visit = noteVisit, visit.rename(matching: matches, to: destination, title: noteTitle) else { return false }
        noteVisit = visit
        return true
    }

    @discardableResult
    mutating func forgetNote(matching matches: (String) -> Bool) -> Bool {
        guard let visit = noteVisit, visit.documents.contains(where: { matches($0.url) }) else { return false }
        let remaining = visit.removing(matching: matches)
        noteVisit = remaining
        if visit.showsNote, (remaining?.shown ?? visit.page) != visit.current { show(remaining?.shown ?? visit.page) }
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
