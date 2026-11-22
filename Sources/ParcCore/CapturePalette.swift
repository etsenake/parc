import Foundation

package struct CapturePaletteDocument: Equatable {
    package enum Target: Equatable { case easel(UUID), note(URL) }
    package enum Kind: String { case easel = "Easel", note = "Note" }

    package let target: Target
    package let title: String
    package let icon: String?
    package let modifiedAt: Date?
    package let profileID: UUID?
    package let id: String

    package init(target: Target, title: String, icon: String? = nil, modifiedAt: Date? = nil, profileID: UUID? = nil) {
        self.target = target; self.title = title; self.icon = icon; self.modifiedAt = modifiedAt; self.profileID = profileID
        switch target {
        case .easel(let id): self.id = "easel:" + id.uuidString
        case .note(let url): self.id = CaptureNoteTarget.note(url).id
        }
    }

    package init(_ easel: CaptureEaselDestination) {
        self.init(target: .easel(easel.id), title: easel.title, modifiedAt: easel.modifiedAt, profileID: easel.profileID)
    }

    package init(_ note: CaptureNoteDestination) {
        self.init(target: .note(note.url), title: note.title, icon: note.icon, modifiedAt: note.modifiedAt)
    }

    package var kind: Kind {
        if case .easel = target { return .easel }
        return .note
    }
}

package enum CapturePaletteSubmenu: Equatable { case easels, notes }

package enum CapturePaletteAction: Equatable {
    case library, copy, save, message, edit, crop, frame, removeFrame, retake
    case easels, notes, newEasel, newNote
    case document(CapturePaletteDocument)

    package var id: String {
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

    package var title: String {
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

    package var symbol: String {
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
        case .easels: return InternalPage.easelFallbackSymbol
        case .notes: return InternalPage.noteFallbackSymbol
        case .newEasel, .newNote: return "plus"
        case .document(let document): return document.kind == .easel ? InternalPage.easelFallbackSymbol : InternalPage.noteFallbackSymbol
        }
    }

    package var submenu: CapturePaletteSubmenu? {
        switch self {
        case .easels: return .easels
        case .notes: return .notes
        default: return nil
        }
    }

    package func title(librarySaved: Bool, framed: Bool) -> String {
        if self == .library && librarySaved { return "Saved to Library" }
        if self == .frame && framed { return "Edit Portrait Frame" }
        return title
    }
}

package struct CapturePaletteRow: Equatable {
    package var action: CapturePaletteAction
    package var title: String
    package var subtitle: String?
    package var section: String?
    package var separatorBefore = false
    package var isEnabled = true
    package var isChecked = false
    package init(action: CapturePaletteAction, title: String, subtitle: String? = nil, section: String? = nil, separatorBefore: Bool = false, isEnabled: Bool = true, isChecked: Bool = false) {
        self.action = action
        self.title = title
        self.subtitle = subtitle
        self.section = section
        self.separatorBefore = separatorBefore
        self.isEnabled = isEnabled
        self.isChecked = isChecked
    }

    package var id: String { action.id }
    package var hasSubmenu: Bool { action.submenu != nil }
}

package struct CapturePaletteContext: Equatable {
    package var easels: [CaptureEaselDestination] = []
    package var notes: [CaptureNoteDestination] = []
    package var framed = false
    package var librarySaved = false
    package var libraryAvailable = true
    package var easelsAvailable = true
    package var notesAvailable = false
    package var messageAvailable = true
    package var busy = false
    package init(easels: [CaptureEaselDestination] = [], notes: [CaptureNoteDestination] = [], framed: Bool = false, librarySaved: Bool = false, libraryAvailable: Bool = true, easelsAvailable: Bool = true, notesAvailable: Bool = false, messageAvailable: Bool = true, busy: Bool = false) {
        self.easels = easels
        self.notes = notes
        self.framed = framed
        self.librarySaved = librarySaved
        self.libraryAvailable = libraryAvailable
        self.easelsAvailable = easelsAvailable
        self.notesAvailable = notesAvailable
        self.messageAvailable = messageAvailable
        self.busy = busy
    }

    var offersEasels: Bool { libraryAvailable && easelsAvailable }
    var offersNotes: Bool { notesAvailable }
}

package enum CapturePaletteMenu {
    static let sendToTitle = "Send To"
    static let recentTitle = "Recent"

    package static func isEnabled(_ action: CapturePaletteAction, in context: CapturePaletteContext) -> Bool {
        !context.busy && (action != .message || context.messageAvailable)
    }

    package static func rows(_ context: CapturePaletteContext, query: String = "") -> [CapturePaletteRow] {
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

    package static func search(_ context: CapturePaletteContext, query: String) -> [CapturePaletteRow] {
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

    package static func submenu(_ submenu: CapturePaletteSubmenu, context: CapturePaletteContext, query: String = "") -> [CapturePaletteRow] {
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

    package static func documents(_ context: CapturePaletteContext) -> [CapturePaletteDocument] {
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

package enum CapturePaletteKey: Equatable { case up, down, left, right, enter, escape, tab }

package enum CapturePaletteFocus: Equatable { case main, submenu(CapturePaletteSubmenu), frame }

package enum CapturePaletteCommand: Equatable {
    case move(Int), activate, open(CapturePaletteSubmenu), closeSubmenu, back, cancel, consume, pass
}

package enum CapturePaletteKeys {
    package static func command(_ key: CapturePaletteKey, focus: CapturePaletteFocus, highlighted: CapturePaletteAction?,
                        caretAtStart: Bool = true, caretAtEnd: Bool = true, composing: Bool = false) -> CapturePaletteCommand {
        guard !composing else { return .pass }
        switch focus {
        case .main:
            switch key {
            case .up: return .move(-1)
            case .down: return .move(1)
            case .enter:
                if let submenu = highlighted?.submenu { return .open(submenu) }
                return highlighted == nil ? .move(1) : .activate
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

package struct CaptureFrameSettings: Equatable {
    package enum Background: Int, CaseIterable { case color, page, desktop }
    static let fractionTolerance = 0.001

    package var background: Background
    package var fraction: Double
    package var watermark: Bool
    package init(background: Background, fraction: Double, watermark: Bool) {
        self.background = background
        self.fraction = fraction
        self.watermark = watermark
    }

    func rendersLike(_ other: Self) -> Bool {
        background == other.background && watermark == other.watermark
            && (background != .color || abs(fraction - other.fraction) < Self.fractionTolerance)
    }
}

package enum CaptureFrameApply: Equatable {
    case pending, unchanged, unavailable

    package static func state(committed: CaptureFrameSettings?, draft: CaptureFrameSettings, renderable: Bool) -> Self {
        guard renderable else { return .unavailable }
        guard let committed else { return .pending }
        return draft.rendersLike(committed) ? .unchanged : .pending
    }

    package var isPrimary: Bool { self == .pending }
}
