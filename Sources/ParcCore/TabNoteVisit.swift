import Foundation

struct TabNoteVisit: Equatable {
    struct Entry: Codable, Equatable {
        var url: String
        var title: String
    }

    struct PageEntry: Codable, Equatable {
        var id: String
        var url: String
        var title: String
    }

    enum Step: Equatable {
        case page(PageEntry)
        case document(Entry)

        var url: String {
            switch self {
            case .page(let entry): entry.url
            case .document(let entry): entry.url
            }
        }
        var title: String {
            switch self {
            case .page(let entry): entry.title
            case .document(let entry): entry.title
            }
        }
        var page: PageEntry? { if case .page(let entry) = self { entry } else { nil } }
        var document: Entry? { if case .document(let entry) = self { entry } else { nil } }
    }

    struct PageHistory: Equatable {
        var entries: [PageEntry]
        var current: Int
        var navigating: Bool

        init(entries: [PageEntry], current: Int, navigating: Bool = false) {
            self.entries = entries; self.current = current; self.navigating = navigating
        }

        var isValid: Bool {
            entries.indices.contains(current) && !entries.contains { $0.id.isEmpty }
                && Set(entries.map(\.id)).count == entries.count
        }
    }

    static let limit = 50

    private(set) var steps: [Step]
    private(set) var position: Int
    private(set) var leaving = false
    private(set) var pageID: String?

    private init?(steps: [Step], position: Int, leaving: Bool) {
        guard steps.first?.page != nil, steps.indices.contains(position),
              steps.contains(where: { $0.document != nil }) else { return nil }
        self.steps = steps
        self.position = position
        self.leaving = leaving
        trimDocuments()
    }

    init(page: Entry, documents: [Entry], position: Int?) {
        let kept = Array(documents.suffix(Self.limit))
        let dropped = documents.count - kept.count
        let shown = position.map { min(max($0 - dropped, 0), max(kept.count - 1, 0)) + 1 } ?? 0
        self.steps = [.page(PageEntry(id: "", url: page.url, title: page.title))] + kept.map(Step.document)
        self.position = shown
    }

    init(page: Entry, note: Entry, showsNote: Bool) {
        self.init(page: page, documents: [note], position: showsNote ? 0 : nil)
    }

    private init(page: Entry, history: PageHistory?) {
        if let history, history.isValid {
            steps = history.entries.map(Step.page)
            position = history.current
            pageID = history.entries[history.current].id
        } else {
            steps = [.page(PageEntry(id: "", url: page.url, title: page.title))]
            position = 0
        }
    }

    var showsNote: Bool { !leaving && steps[position].document != nil }
    var current: Entry? { showsNote ? steps[position].document : nil }
    var shownStep: Step { steps[leaving ? anchorIndex(position) : position] }
    var shownPage: PageEntry? { leaving ? nil : steps[position].page }
    var pageUnderShown: PageEntry { steps[anchorIndex(position)].page ?? PageEntry(id: "", url: "", title: "") }
    var page: Entry { Entry(url: pageUnderShown.url, title: pageUnderShown.title) }
    var documents: [Entry] { steps.compactMap(\.document) }
    var pageEntryIDs: [String] { steps.compactMap { $0.page?.id }.filter { !$0.isEmpty } }
    var tracksPageHistory: Bool { !steps.contains { $0.page?.id.isEmpty == true } }
    var behind: [Step] { Array((leaving ? steps[...position] : steps[..<position]).reversed()) }
    var ahead: [Step] { leaving ? [] : Array(steps[(position + 1)...]) }
    var note: Entry { current ?? documents[0] }
    var noteFile: URL? { InternalPage.noteFile(note.url) }
    var document: InternalPage? { InternalPage(urlString: note.url) }

    static func noteFile(_ entry: Entry) -> URL? { InternalPage.noteFile(entry.url) }
    static func document(_ entry: Entry) -> InternalPage? { InternalPage(urlString: entry.url) }

    func hasDocument(towardBack back: Bool) -> Bool {
        showsNote || (back ? behind : ahead).contains { $0.document != nil }
    }

    func step(_ offset: Int) -> Step? {
        targetIndex(offset).map { steps[$0] }
    }

    func anchor(afterMovingBy offset: Int) -> PageEntry? {
        targetIndex(offset).flatMap { steps[anchorIndex($0)].page }
    }

    private func targetIndex(_ offset: Int) -> Int? {
        guard offset != 0 else { return nil }
        let target = leaving ? (offset < 0 ? position + offset + 1 : steps.count) : position + offset
        return steps.indices.contains(target) ? target : nil
    }

    private func anchorIndex(_ index: Int) -> Int {
        steps[...index].lastIndex { $0.page != nil } ?? 0
    }

    mutating func syncShown(url: String, title: String) {
        guard !leaving else { return }
        switch steps[position] {
        case .document: steps[position] = .document(Entry(url: url, title: title))
        case .page(let entry): steps[position] = .page(PageEntry(id: entry.id, url: url, title: title))
        }
    }

    @discardableResult
    mutating func followPage(url: String?, title: String?) -> Bool {
        let index = pageID.flatMap { id in steps.firstIndex { $0.page?.id == id } } ?? anchorIndex(position)
        guard case .page(var entry) = steps[index] else { return false }
        let before = entry
        if let url, !url.isEmpty { entry.url = url }
        if let title, !title.isEmpty { entry.title = title }
        guard entry != before else { return false }
        steps[index] = .page(entry)
        return true
    }

    mutating func move(by offset: Int) -> Bool {
        guard let target = targetIndex(offset) else { return false }
        position = target
        leaving = false
        if let id = steps[anchorIndex(target)].page?.id, !id.isEmpty { pageID = id }
        return true
    }

    mutating func push(_ entry: Entry) {
        var kept = Array(steps[...position])
        if kept.last?.document?.url == entry.url { kept[kept.count - 1] = .document(entry) } else { kept.append(.document(entry)) }
        steps = kept
        position = kept.count - 1
        leaving = false
        trimDocuments()
    }

    mutating func leave() -> Bool {
        guard showsNote else { return false }
        steps = Array(steps[...position])
        leaving = true
        return true
    }

    @discardableResult
    mutating func sync(_ history: PageHistory) -> Bool {
        guard history.isValid else { return false }
        let before = self
        let currentID = history.entries[history.current].id
        let resolved = steps.map { step -> Step in
            guard case .page(var entry) = step, entry.id.isEmpty else { return step }
            entry.id = currentID
            return .page(entry)
        }
        let knownIDs = Set(resolved.compactMap { $0.page?.id })
        let liveIDs = Set(history.entries.map(\.id))
        var runs: [String: [(Int, Entry)]] = [:]
        var anchor: String?
        for (index, step) in resolved.enumerated() {
            switch step {
            case .page(let entry): anchor = entry.id
            case .document(let entry): if let anchor { runs[anchor, default: []].append((index, entry)) }
            }
        }
        let shownAnchor = resolved[anchorIndex(position)].page?.id ?? currentID
        if !leaving, case .page(let shown) = resolved[position],
           let index = history.entries.firstIndex(where: { $0.id == shown.id }), history.current > index,
           history.entries.indices.contains(index + 1), !knownIDs.contains(history.entries[index + 1].id) {
            runs[shown.id] = nil
        }
        if leaving || resolved[position].document != nil, !liveIDs.contains(shownAnchor),
           let run = runs.removeValue(forKey: shownAnchor) {
            runs[currentID, default: []] += run
        }
        var rebuilt: [Step] = [], moved: [Int: Int] = [:]
        for entry in history.entries {
            rebuilt.append(.page(entry))
            for (old, document) in runs[entry.id] ?? [] {
                moved[old] = rebuilt.count
                rebuilt.append(.document(document))
            }
        }
        let currentStep = rebuilt.firstIndex { $0.page?.id == currentID } ?? 0
        var nextPosition = currentStep, nextLeaving = false
        if leaving {
            if knownIDs.contains(currentID), history.navigating, let left = moved[position] {
                nextPosition = left
                nextLeaving = true
            }
        } else if resolved[position].document != nil, let shown = moved[position] {
            nextPosition = shown
        }
        steps = rebuilt
        position = nextPosition
        leaving = nextLeaving
        pageID = currentID
        trimDocuments()
        return self != before
    }

    mutating func rename(matching matches: (String) -> Bool, to destination: String, title: String) -> Bool {
        let renamed = steps.map { step -> Step in
            guard let document = step.document, matches(document.url) else { return step }
            return .document(Entry(url: destination, title: title))
        }
        guard renamed != steps else { return false }
        steps = renamed
        collapse()
        return true
    }

    func removing(matching matches: (String) -> Bool) -> TabNoteVisit? {
        var next = self
        let removed = steps.indices.filter { steps[$0].document.map { matches($0.url) } ?? false }
        guard !removed.isEmpty else { return self }
        let shown = steps[...position].indices.last { !removed.contains($0) } ?? 0
        next.steps = steps.indices.filter { !removed.contains($0) }.map { steps[$0] }
        next.position = shown - removed.filter { $0 < shown }.count
        next.collapse()
        return next.steps.contains { $0.document != nil } ? next : nil
    }

    private mutating func collapse() {
        var kept: [Step] = [], shown = 0
        for (index, step) in steps.enumerated() {
            if let document = step.document, kept.last?.document?.url == document.url {
                if index == position { shown = kept.count - 1 }
                continue
            }
            if index == position { shown = kept.count }
            kept.append(step)
        }
        steps = kept
        position = shown
    }

    private mutating func trimDocuments() {
        var excess = documents.count - Self.limit
        guard excess > 0 else { return }
        var kept: [Step] = [], shown = position
        for (index, step) in steps.enumerated() {
            if excess > 0, step.document != nil, index != position {
                excess -= 1
                if index < position { shown -= 1 }
                continue
            }
            kept.append(step)
        }
        steps = kept
        position = shown
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

    static func page(_ url: String, title: String, history: PageHistory?) -> TabNoteVisit {
        TabNoteVisit(page: Entry(url: url, title: title), history: history)
    }
}

extension TabNoteVisit: Codable {
    private enum CodingKeys: String, CodingKey { case page, note, showsNote, documents, position, steps, shown, leaving, pageEntry }
    private struct SavedStep: Codable {
        var id: String?
        var url: String
        var title: String
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let saved = try values.decodeIfPresent([SavedStep].self, forKey: .steps) {
            let steps = saved.map { step -> Step in
                step.id.map { .page(PageEntry(id: $0, url: step.url, title: step.title)) }
                    ?? .document(Entry(url: step.url, title: step.title))
            }
            guard var visit = TabNoteVisit(steps: steps, position: try values.decode(Int.self, forKey: .shown),
                                           leaving: try values.decodeIfPresent(Bool.self, forKey: .leaving) ?? false) else {
                throw DecodingError.dataCorruptedError(forKey: .steps, in: values, debugDescription: "Unreadable visit")
            }
            visit.pageID = try values.decodeIfPresent(String.self, forKey: .pageEntry)
            self = visit
            return
        }
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
        let shownDocument = showsNote ? steps[..<position].filter { $0.document != nil }.count : nil
        try values.encode(page, forKey: .page)
        try values.encode(note, forKey: .note)
        try values.encode(showsNote, forKey: .showsNote)
        try values.encode(documents, forKey: .documents)
        try values.encodeIfPresent(shownDocument, forKey: .position)
        try values.encode(steps.map { step in
            SavedStep(id: step.page.map(\.id), url: step.url, title: step.title)
        }, forKey: .steps)
        try values.encode(position, forKey: .shown)
        if leaving { try values.encode(true, forKey: .leaving) }
        try values.encodeIfPresent(pageID, forKey: .pageEntry)
    }
}

extension BrowserTab {
    var showsNoteOverPage: Bool { noteVisit?.showsNote == true }
    var hasVisitStepAhead: Bool { noteVisit.map { !$0.ahead.isEmpty } ?? false }
    var hasVisitStepBehind: Bool { noteVisit.map { !$0.behind.isEmpty } ?? false }

    @discardableResult
    mutating func openNoteVisit(url noteURL: URL, title noteTitle: String) -> Bool {
        openDocumentVisit(.note(noteURL), title: noteTitle)
    }

    @discardableResult
    mutating func openDocumentVisit(_ document: InternalPage, title documentTitle: String,
                                    history: TabNoteVisit.PageHistory? = nil) -> Bool {
        guard archivedAt == nil, let entry = TabNoteVisit.entry(document, title: documentTitle) else { return false }
        if var visit = noteVisit, visit.showsNote == InternalPage.isInternal(url) {
            visit.syncShown(url: url, title: title)
            if let history { visit.sync(history) }
            visit.push(entry)
            noteVisit = visit
        } else {
            guard !InternalPage.isInternal(url), !BrowserState.isBlankPage(url) else { return false }
            var visit = TabNoteVisit.page(url, title: title, history: history)
            visit.push(entry)
            noteVisit = visit
        }
        show(entry.url, title: entry.title)
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
        show(visit.shownStep.url, title: visit.shownStep.title)
        return true
    }

    @discardableResult
    mutating func followPageUnderNote(url pageURL: String?, title pageTitle: String?) -> Bool {
        guard var visit = noteVisit, visit.showsNote || visit.leaving else { return false }
        guard visit.followPage(url: pageURL.map(BrowserInternalURL.publicString), title: pageTitle) else { return false }
        noteVisit = visit
        return true
    }

    @discardableResult
    mutating func syncPageHistory(_ history: TabNoteVisit.PageHistory) -> Bool {
        guard var visit = noteVisit, archivedAt == nil, visit.sync(history) else { return false }
        noteVisit = visit.documents.isEmpty ? nil : visit
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
        if visit.showsNote {
            let shown = remaining?.shownStep ?? .page(visit.pageUnderShown)
            if shown.document != visit.current { show(shown.url, title: shown.title) }
        }
        return true
    }

    mutating func leaveNoteVisit(for destination: String) -> Bool {
        guard var visit = noteVisit, visit.tracksPageHistory, visit.showsNote, InternalPage.isInternal(url),
              !InternalPage.isInternal(destination), visit.leave() else { return false }
        noteVisit = visit
        return true
    }

    private mutating func show(_ shownURL: String, title shownTitle: String) {
        url = shownURL
        title = shownTitle
        if kind == .today {
            savedURL = shownURL
            savedTitle = shownTitle
        }
    }
}
