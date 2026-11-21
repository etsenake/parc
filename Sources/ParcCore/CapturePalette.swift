import Foundation

struct CapturePaletteDocument: Equatable {
    enum Target: Equatable { case easel(UUID), note(URL) }
    enum Kind: String { case easel = "Easel", note = "Note" }

    let target: Target
    let title: String
    let icon: String?
    let modifiedAt: Date?
    let id: String

    init(target: Target, title: String, icon: String? = nil, modifiedAt: Date? = nil) {
        self.target = target; self.title = title; self.icon = icon; self.modifiedAt = modifiedAt
        switch target {
        case .easel(let id): self.id = "easel:" + id.uuidString
        case .note(let url): self.id = CaptureNoteTarget.note(url).id
        }
    }

    init(_ easel: CaptureEaselDestination) {
        self.init(target: .easel(easel.id), title: easel.title, modifiedAt: easel.modifiedAt)
    }

    init(_ note: CaptureNoteDestination) {
        self.init(target: .note(note.url), title: note.title, icon: note.icon, modifiedAt: note.modifiedAt)
    }

    var kind: Kind {
        if case .easel = target { return .easel }
        return .note
    }
}

enum CapturePaletteSubmenu: Equatable { case easels, notes }

enum CapturePaletteAction: Equatable {
    case library, copy, save, message, edit, crop, frame, removeFrame, retake
    case easels, notes, newEasel, newNote
    case document(CapturePaletteDocument)

    var id: String {
        switch self {
        case .library: return "library"
        case .copy: return "copy"
        case .save: return "save"
        case .message: return "message"
        case .edit: return "edit"
        case .crop: return "crop"
        case .frame: return "frame"
        case .removeFrame: return "removeFrame"
        case .retake: return "retake"
        case .easels: return "easels"
        case .notes: return "notes"
        case .newEasel: return "newEasel"
        case .newNote: return CaptureNoteTarget.newNote.id
        case .document(let document): return document.id
        }
    }

    var title: String {
        switch self {
        case .library: return "Save to Library"
        case .copy: return "Copy"
        case .save: return "Save…"
        case .message: return "Send via iMessage…"
        case .edit: return "Edit"
        case .crop: return "Crop"
        case .frame: return "Frame in Portrait Mode"
        case .removeFrame: return "Remove Frame"
        case .retake: return "Retake"
        case .easels: return "Easel"
        case .notes: return "Note"
        case .newEasel: return "New Easel"
        case .newNote: return CaptureNoteTarget.newNoteTitle
        case .document(let document): return document.title
        }
    }

    var symbol: String {
        switch self {
        case .library: return "tray.and.arrow.down"
        case .copy: return "doc.on.doc"
        case .save: return "square.and.arrow.down"
        case .message: return "message"
        case .edit: return "pencil"
        case .crop: return "crop"
        case .frame: return "photo.artframe"
        case .removeFrame: return "photo"
        case .retake: return "camera"
        case .easels: return "scribble"
        case .notes: return CaptureNoteTarget.noteSymbol
        case .newEasel, .newNote: return "plus"
        case .document(let document): return document.kind == .easel ? "scribble" : CaptureNoteTarget.noteSymbol
        }
    }

    var submenu: CapturePaletteSubmenu? {
        switch self {
        case .easels: return .easels
        case .notes: return .notes
        default: return nil
        }
    }

    func title(librarySaved: Bool, framed: Bool) -> String {
        if self == .library && librarySaved { return "Saved to Library" }
        if self == .frame && framed { return "Edit Portrait Frame" }
        return title
    }
}

struct CapturePaletteRow: Equatable {
    var action: CapturePaletteAction
    var title: String
    var subtitle: String?
    var section: String?
    var separatorBefore = false
    var isEnabled = true
    var isChecked = false

    var id: String { action.id }
    var hasSubmenu: Bool { action.submenu != nil }
}

struct CapturePaletteContext: Equatable {
    var easels: [CaptureEaselDestination] = []
    var notes: [CaptureNoteDestination] = []
    var framed = false
    var librarySaved = false
    var libraryAvailable = true
    var easelsAvailable = true
    var notesAvailable = false
    var messageAvailable = true
    var busy = false

    var offersEasels: Bool { libraryAvailable && easelsAvailable }
    var offersNotes: Bool { notesAvailable }
}

enum CapturePaletteMenu {
    static let sendToTitle = "Send To"
    static let recentTitle = "Recent"

    static func isEnabled(_ action: CapturePaletteAction, in context: CapturePaletteContext) -> Bool {
        !context.busy && (action != .message || context.messageAvailable)
    }

    static func rows(_ context: CapturePaletteContext, query: String = "") -> [CapturePaletteRow] {
        guard query.isEmpty else { return search(context, query: query) }
        var rows = quickActions(context).map { row($0, context) }
        for (index, action) in editActions(context).enumerated() {
            var item = row(action, context)
            item.separatorBefore = index == 0
            rows.append(item)
        }
        let sendTo: [CapturePaletteAction] = (context.offersEasels ? [.easels] : []) + (context.offersNotes ? [.notes] : [])
        for action in sendTo {
            var item = row(action, context)
            item.section = sendToTitle
            rows.append(item)
        }
        return rows
    }

    static func search(_ context: CapturePaletteContext, query: String) -> [CapturePaletteRow] {
        let needle = query.lowercased()
        func matches(_ title: String) -> Bool { title.lowercased().contains(needle) }
        var actions = quickActions(context) + editActions(context)
        if context.offersEasels { actions.append(.newEasel) }
        if context.offersNotes { actions.append(.newNote) }
        var rows = actions.filter { matches($0.title(librarySaved: context.librarySaved, framed: context.framed)) }
            .map { row($0, context) }
        for document in documents(context) where matches(document.title) {
            var item = row(.document(document), context)
            item.subtitle = document.kind.rawValue
            rows.append(item)
        }
        return rows
    }

    static func submenu(_ submenu: CapturePaletteSubmenu, context: CapturePaletteContext, query: String = "") -> [CapturePaletteRow] {
        let offered = submenu == .easels ? context.offersEasels : context.offersNotes
        guard offered else { return [] }
        let create: CapturePaletteAction = submenu == .easels ? .newEasel : .newNote
        let documents = documents(context).filter { ($0.kind == .easel) == (submenu == .easels) }
        guard query.isEmpty else {
            let needle = query.lowercased()
            return ([create] + documents.map { .document($0) }).filter { $0.title.lowercased().contains(needle) }
                .map { row($0, context) }
        }
        return [row(create, context)] + documents.map { document in
            var item = row(.document(document), context)
            item.section = recentTitle
            return item
        }
    }

    static func documents(_ context: CapturePaletteContext) -> [CapturePaletteDocument] {
        (context.offersEasels ? CaptureEaselDestination.ranked(context.easels).map(CapturePaletteDocument.init) : [])
            + (context.offersNotes ? CaptureNoteDestination.ranked(context.notes).map(CapturePaletteDocument.init) : [])
    }

    static func retainedHighlight(_ previousID: String?, in rows: [CapturePaletteRow]) -> String? {
        guard let previousID, let row = rows.first(where: { $0.id == previousID }), row.isEnabled else { return nil }
        return row.id
    }

    static func firstAvailable(in rows: [CapturePaletteRow]) -> String? {
        rows.first(where: \.isEnabled)?.id
    }

    private static func quickActions(_ context: CapturePaletteContext) -> [CapturePaletteAction] {
        (context.libraryAvailable ? [.library] : []) + [.copy, .save, .message]
    }

    private static func editActions(_ context: CapturePaletteContext) -> [CapturePaletteAction] {
        [.edit, .crop, .frame] + (context.framed ? [.removeFrame] : []) + [.retake]
    }

    private static func row(_ action: CapturePaletteAction, _ context: CapturePaletteContext) -> CapturePaletteRow {
        CapturePaletteRow(action: action, title: action.title(librarySaved: context.librarySaved, framed: context.framed),
                          isEnabled: isEnabled(action, in: context),
                          isChecked: action == .library && context.librarySaved)
    }
}

enum CapturePaletteKey: Equatable { case up, down, left, right, enter, escape, tab }

enum CapturePaletteFocus: Equatable { case main, submenu(CapturePaletteSubmenu), frame }

enum CapturePaletteCommand: Equatable {
    case move(Int), activate, open(CapturePaletteSubmenu), closeSubmenu, back, cancel, consume, pass
}

enum CapturePaletteKeys {
    static func command(_ key: CapturePaletteKey, focus: CapturePaletteFocus, highlighted: CapturePaletteAction?,
                        caretAtStart: Bool = true, caretAtEnd: Bool = true, composing: Bool = false) -> CapturePaletteCommand {
        guard !composing else { return .pass }
        switch focus {
        case .main:
            switch key {
            case .up: return .move(-1)
            case .down: return .move(1)
            case .enter:
                if let submenu = highlighted?.submenu { return .open(submenu) }
                return highlighted == nil ? .consume : .activate
            case .right:
                guard caretAtEnd, let submenu = highlighted?.submenu else { return .pass }
                return .open(submenu)
            case .left: return .pass
            case .escape: return .cancel
            case .tab: return .consume
            }
        case .submenu:
            switch key {
            case .up: return .move(-1)
            case .down: return .move(1)
            case .enter: return highlighted == nil ? .consume : .activate
            case .left: return caretAtStart ? .closeSubmenu : .pass
            case .right: return .pass
            case .escape: return .closeSubmenu
            case .tab: return .consume
            }
        case .frame:
            switch key {
            case .escape, .left: return .back
            case .enter: return .activate
            case .up, .down, .right, .tab: return .pass
            }
        }
    }
}

struct CaptureFrameSettings: Equatable {
    enum Background: Int, CaseIterable { case color, page, desktop }
    static let fractionTolerance = 0.001

    var background: Background
    var fraction: Double
    var watermark: Bool

    func rendersLike(_ other: Self) -> Bool {
        background == other.background && watermark == other.watermark
            && (background != .color || abs(fraction - other.fraction) < Self.fractionTolerance)
    }
}

enum CaptureFrameApply: Equatable {
    case pending, unchanged, unavailable

    static func state(committed: CaptureFrameSettings?, draft: CaptureFrameSettings, renderable: Bool) -> Self {
        guard renderable else { return .unavailable }
        guard let committed else { return .pending }
        return draft.rendersLike(committed) ? .unchanged : .pending
    }

    var isPrimary: Bool { self == .pending }
}
