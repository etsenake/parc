import AppKit

@MainActor
protocol EaselSelectionToolbarPresenting: AnyObject {
    func refresh(for canvas: EaselCanvasView)
    func detach()
    func settle()
    func owns(_ responder: NSResponder?) -> Bool
    func focusFromKeyboard() -> Bool
}

struct EaselToolbarButtonModel: Equatable {
    enum Face: Equatable {
        case symbol(String)
        case glyph(String)
        case text(String)
    }
    enum Mark: Equatable { case none, italic, underline, strikethrough }

    var control: EaselToolbarControl
    var face: Face
    var name: String
    var shortcut: String?
    var commandID: String?
    var isChecked = false
    var isEnabled = true
    var opensMenu = false
    var showsDisclosure = false
    var mark: Mark = .none
}

struct EaselToolbarMenuEntry: Equatable {
    var id: String
    var title: String
    var symbol: String?
    var shortcut: String?
    var isChecked = false
    var isEnabled = true
    var isDestructive = false
    var separatorBefore = false
}

struct EaselSelectionToolbarContent: Equatable {
    var groups: [[EaselToolbarButtonModel]]
    var anchor: NSRect
    var selection: Set<UUID>
}

extension EaselCanvasView {
    static var selectionToolbarFactory: (@MainActor () -> EaselSelectionToolbarPresenting)?

    func refreshSelectionToolbar() {
        guard window != nil else { return }
        selectionToolbar?.refresh(for: self)
    }

    var selectionToolbarSuppressed: Bool {
        let pressed = start != nil
        return motion.isInteracting || hidesPassiveAnnotations
            || (pressed && (drawing || dragDistance > 3 || resizing || marqueeRect != nil || selection != selectionBeforeGesture))
    }

    func selectionToolbarAcceptsFocus(of responder: NSResponder?) -> Bool {
        guard let responder, responder !== window else { return true }
        if responder === self || selectionToolbar?.owns(responder) == true { return true }
        guard let view = responder as? NSView else { return false }
        return view.isDescendant(of: self)
    }

    var selectionToolbarContent: EaselSelectionToolbarContent? {
        guard canPresentMotion, window != nil, !isHiddenOrHasHiddenAncestor, !selectionToolbarSuppressed,
              selectionToolbarAcceptsFocus(of: window?.firstResponder) else { return nil }
        let selected = session.document.items.filter { selection.contains($0.id) }.sorted { $0.zIndex < $1.zIndex }
        guard let first = selected.first else { return nil }
        let plan = EaselSelectionToolbarPlan.groups(for: selected.map { EaselToolbarSubject($0.kind) },
                                                    editingText: editor != nil, locked: selected.allSatisfy(\.isLocked))
        let groups = EaselSelectionToolbarPlan.available(plan) { selectionToolbarSupports($0, selected: selected) }
        guard !groups.isEmpty else { return nil }
        let anchor = selected.dropFirst().reduce(selectionToolbarFrame(first)) { $0.union(selectionToolbarFrame($1)) }
        return EaselSelectionToolbarContent(groups: groups.map { $0.map { selectionToolbarButton($0, selected: selected) } },
                                            anchor: anchor, selection: selection)
    }

    private func selectionToolbarFrame(_ item: EaselItem) -> NSRect {
        NSRect(x: item.frame.x, y: item.frame.y, width: max(1, item.frame.width), height: max(1, item.frame.height))
    }

    private var selectionToolbarStyles: [EaselTextStyle] {
        session.document.items.filter { selection.contains($0.id) && $0.kind == .text }.map(\.resolvedTextStyle)
    }

    private func selectionToolbarSupports(_ control: EaselToolbarControl, selected: [EaselItem]) -> Bool {
        let textOnly = selected.allSatisfy { $0.kind == .text }
        switch control {
        case .typeface, .textSize, .smaller, .larger, .textFill: return textOnly
        case .bold, .italic, .underline, .strikethrough, .paragraph, .link: return textOnly && editor != nil
        case .more: return true
        case .codeLanguage: return selected.allSatisfy { $0.kind == .code } && selected.contains { !$0.isLocked }
        default: return false
        }
    }

    private func selectionToolbarButton(_ control: EaselToolbarControl, selected: [EaselItem]) -> EaselToolbarButtonModel {
        let styles = selectionToolbarStyles
        let composing = editor?.hasMarkedText() == true
        switch control {
        case .typeface:
            let family = EaselTextStyleState.family(of: styles, editor: editor)
            return .init(control: control, face: .text(family.map(Self.familyTitle) ?? "Mixed"), name: "Typeface",
                         isEnabled: !composing, opensMenu: true, showsDisclosure: true)
        case .textSize:
            let size = EaselTextStyleState.size(of: styles, editor: editor)
            return .init(control: control, face: .text(size.map(Self.sizeTitle) ?? "Mixed"), name: "Text size",
                         isEnabled: !composing, opensMenu: true, showsDisclosure: true)
        case .smaller, .larger:
            let delta = control == .larger ? 1 : -1
            let command: TextFormatCommand = control == .larger ? .bigger : .smaller
            return .init(control: control, face: .symbol(control == .larger ? "textformat.size.larger" : "textformat.size.smaller"),
                         name: command.commandTitle, commandID: command.bindingID,
                         isEnabled: EaselTextStyleState.canResize(by: delta, styles: styles, editor: editor))
        case .bold, .italic, .underline, .strikethrough:
            let emphasis = Self.emphasis(for: control)
            let command = Self.formatCommand(for: emphasis)
            return .init(control: control, face: .glyph(Self.glyph(for: emphasis)), name: command.title, commandID: command.bindingID,
                         isChecked: editor?.hasEmphasis(emphasis) == true, isEnabled: !composing, mark: Self.mark(for: emphasis))
        case .paragraph:
            let kind = editor?.paragraphKind()
            return .init(control: control, face: .text(kind?.rawValue ?? "Mixed"), name: "Paragraph style",
                         isEnabled: !composing && editor?.selectedRanges.count == 1, opensMenu: true, showsDisclosure: true)
        case .textFill:
            return .init(control: control, face: .symbol("highlighter"), name: "Text fill",
                         isChecked: EaselTextStyleState.fill(of: styles) == .on, isEnabled: !composing)
        case .link:
            let range = editor?.selectedRange() ?? NSRange(location: 0, length: 0)
            return .init(control: control, face: .symbol("link"), name: editor?.hasLink() == true ? "Edit link" : "Add a link",
                         commandID: TextFormatCommand.link.bindingID, isEnabled: !composing && range.length > 0)
        case .codeLanguage:
            let languages = selectedCodeLanguages
            let title = languages.count == 1 ? languages.first.map { EaselCodeBlock.displayName($0) } ?? "Mixed" : "Mixed"
            return .init(control: control, face: .text(title), name: "Language", opensMenu: true, showsDisclosure: true)
        default:
            return .init(control: control, face: .symbol("ellipsis"), name: "More", opensMenu: true)
        }
    }

    func selectionToolbarMenu(for control: EaselToolbarControl) -> [EaselToolbarMenuEntry] {
        let styles = selectionToolbarStyles
        switch control {
        case .typeface:
            let current = EaselTextStyleState.family(of: styles, editor: editor)
            return EaselTextStyle.Family.allCases.map {
                EaselToolbarMenuEntry(id: $0.rawValue, title: Self.familyTitle($0), isChecked: $0 == current)
            }
        case .textSize:
            let current = EaselTextStyleState.size(of: styles, editor: editor)
            return EaselTextStyle.Size.allCases.map {
                EaselToolbarMenuEntry(id: $0.rawValue, title: Self.sizeTitle($0), isChecked: $0 == current)
            }
        case .paragraph:
            let current = editor?.paragraphKind()
            return EaselParagraphEditing.Kind.allCases.map { kind in
                EaselToolbarMenuEntry(id: kind.rawValue, title: kind.rawValue, isChecked: kind == current,
                                      separatorBefore: kind == .bullets)
            }
        case .more:
            let ready = editor == nil || editor?.hasMarkedText() == false
            return [
                EaselToolbarMenuEntry(id: "front", title: "Bring to Front", symbol: "square.3.layers.3d.top.filled", isEnabled: ready),
                EaselToolbarMenuEntry(id: "duplicate", title: "Duplicate", symbol: "plus.square.on.square", isEnabled: ready),
                EaselToolbarMenuEntry(id: "delete", title: "Delete", symbol: "trash", shortcut: "⌫", isEnabled: ready,
                                      isDestructive: true, separatorBefore: true),
            ]
        case .codeLanguage:
            let current = selectedCodeLanguages
            return NoteCodeLanguage.all.map { EaselToolbarMenuEntry(id: $0.id, title: $0.name, isChecked: current == [$0.id]) }
        default:
            return []
        }
    }

    @discardableResult
    func performSelectionToolbar(_ control: EaselToolbarControl, anchor: NSView? = nil) -> Bool {
        guard !session.isClosed, !session.isDeleted else { return false }
        switch control {
        case .smaller, .larger:
            guard EaselTextStyleState.canResize(by: control == .larger ? 1 : -1, styles: selectionToolbarStyles, editor: editor) else { return false }
            resizeText(by: control == .larger ? 1 : -1)
        case .bold, .italic, .underline, .strikethrough:
            guard editor?.hasMarkedText() == false else { return false }
            applyEmphasis(Self.emphasis(for: control))
        case .textFill:
            let styles = selectionToolbarStyles
            guard !styles.isEmpty else { return false }
            setTextFill(EaselTextStyleState.toggledFill(styles))
        case .link:
            guard let editor, editor.selectedRange().length > 0, !editor.hasMarkedText() else { return false }
            editLink(relativeTo: anchor ?? editor, rect: anchor == nil ? editor.revealedSelectionRect() : nil)
        default:
            return false
        }
        refreshTextControls()
        return true
    }

    @discardableResult
    func performSelectionToolbarMenu(_ control: EaselToolbarControl, entry id: String) -> Bool {
        guard !session.isClosed, !session.isDeleted else { return false }
        switch control {
        case .typeface:
            guard let family = EaselTextStyle.Family(rawValue: id) else { return false }
            changeTextStyle(preservingSize: true) { $0.family = family }
        case .textSize:
            guard let size = EaselTextStyle.Size(rawValue: id) else { return false }
            changeTextStyle { $0.size = size }
        case .paragraph:
            guard let kind = EaselParagraphEditing.Kind(rawValue: id), editor?.hasMarkedText() == false else { return false }
            applyParagraph(kind)
        case .more:
            switch id {
            case "front": return bringToFront(nil)
            case "duplicate": return duplicateObjects(nil)
            case "delete": deleteObjects(nil)
            default: return false
            }
        case .codeLanguage:
            guard let language = NoteCodeLanguage.all.first(where: { $0.id == id }) else { return false }
            return setCodeLanguage(EaselCodeBlock.stored(language))
        default:
            return false
        }
        refreshTextControls()
        return true
    }

    func selectionToolbarStructureChanged() {
        keyboardStructureChanged()
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func returnFocusFromSelectionToolbar() {
        if let editor { window?.makeFirstResponder(editor) } else { window?.makeFirstResponder(codeBlocks.editor ?? self) }
    }

    private static func emphasis(for control: EaselToolbarControl) -> EaselStyledTextView.Emphasis {
        switch control {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        default: return .strikethrough
        }
    }

    private static func formatCommand(for emphasis: EaselStyledTextView.Emphasis) -> TextFormatCommand {
        switch emphasis {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        }
    }

    private static func glyph(for emphasis: EaselStyledTextView.Emphasis) -> String {
        switch emphasis {
        case .bold: return "B"
        case .italic: return "i"
        case .underline: return "U"
        case .strikethrough: return "S"
        }
    }

    private static func mark(for emphasis: EaselStyledTextView.Emphasis) -> EaselToolbarButtonModel.Mark {
        switch emphasis {
        case .bold: return .none
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        }
    }

    static func familyTitle(_ family: EaselTextStyle.Family) -> String {
        switch family {
        case .mono: return "Mono"
        case .fancy: return "Fancy"
        case .hip: return "Hip"
        case .clean: return "Clean"
        }
    }

    static func sizeTitle(_ size: EaselTextStyle.Size) -> String {
        switch size {
        case .body: return "Body"
        case .h2: return "Heading 2"
        case .h1: return "Heading 1"
        case .h0: return "Title"
        case .ultra: return "Display"
        }
    }
}
