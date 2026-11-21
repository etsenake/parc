import AppKit
import ParcCore

enum EaselLastTextTint: Equatable {
    case ink(EaselColorChoice)
    case highlight(NoteColor)
}

extension EaselCanvasView {
    private var highlightReady: Bool { editor?.hasMarkedText() == false && !session.isClosed && !session.isDeleted }

    func selectionToolbarTextSupports(_ control: EaselToolbarControl, selected: [EaselItem]) -> Bool? {
        switch control {
        case .highlight: return editor != nil && selected.count == 1 && adaptsInk && !editingLabel
        case .code, .mention, .equation: return editor != nil && selected.count == 1 && !editingLabel
        default: return nil
        }
    }

    func selectionToolbarTextButton(_ control: EaselToolbarControl) -> EaselToolbarButtonModel? {
        let ready = highlightReady
        switch control {
        case .highlight:
            let state = editor?.highlightState() ?? .none
            var value = "None"
            var tint: NSColor?
            switch state {
            case .none: break
            case .mixed: value = "Mixed"
            case .color(let color): value = NoteTheme.displayName(color); tint = NoteTheme.swatch(color)
            }
            return .init(control: control, face: .glyph("A"), name: "Highlight", shortcut: NoteFormatShortcut.lastColor.display,
                         isEnabled: ready, opens: .highlightPicker, showsDisclosure: true, tint: tint, value: value)
        case .code:
            return .init(control: control, face: .symbol("chevron.left.forwardslash.chevron.right"), name: "Code",
                         shortcut: NoteFormatShortcut.code.display, isChecked: editor?.hasInlineCode() == true, isEnabled: ready)
        case .mention:
            return .init(control: control, face: .glyph("@"), name: "Mention a note or date", isEnabled: ready)
        case .equation:
            return .init(control: control, face: .symbol("x.squareroot"), name: "Inline equation", shortcut: NoteFormatShortcut.equation.display,
                         isEnabled: ready)
        default:
            return nil
        }
    }

    func performSelectionToolbarText(_ control: EaselToolbarControl) -> Bool? {
        switch control {
        case .code:
            guard highlightReady, let editor, editor.selectedRanges.count == 1 else { return false }
            editor.toggleInlineCode()
            return true
        case .mention:
            guard highlightReady, let editor, editor.selectedRanges.count == 1 else { return false }
            editor.beginMention()
            return true
        case .equation:
            guard highlightReady, let editor, editor.selectedRanges.count == 1 else { return false }
            editor.insertInlineEquation()
            return true
        default:
            return nil
        }
    }

    var highlightMenuState: EaselStyledTextView.HighlightState? {
        highlightReady ? editor?.highlightState() : nil
    }

    @discardableResult
    func applyHighlight(_ color: NoteColor?) -> Bool {
        guard highlightReady, let editor, editor.selectedRanges.count == 1 else { return false }
        editor.applyHighlight(color)
        if let color {
            Self.highlightRecorder?(color)
            lastTextTint = .highlight(color)
        }
        refreshTextControls()
        return true
    }

    @discardableResult
    func repeatLastTextTint() -> Bool {
        guard highlightReady, let editor, editor.selectedRanges.count == 1 else { return false }
        switch lastTextTint {
        case .highlight(let color)?:
            return applyHighlight(color)
        case .ink(let choice)?:
            editor.applyTextColor(EaselInk.color(choice.hex(role: .ink), adaptive: adaptsInk))
            refreshTextControls()
            return true
        case nil:
            guard let color = Self.highlightRecall?() else { return false }
            return applyHighlight(color)
        }
    }
}
