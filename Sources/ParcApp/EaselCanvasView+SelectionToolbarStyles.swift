import AppKit

extension EaselCanvasView {
    private var styleToolbarReady: Bool { editor?.hasMarkedText() != true && !session.isClosed && !session.isDeleted }

    private static let alignments: [(EaselTextStyle.Alignment, NSTextAlignment, String, String, String)] = [
        (.left, .left, "Align Left", "text.alignleft", "⌥⌘L"),
        (.center, .center, "Align Center", "text.aligncenter", "⌥⌘T"),
        (.right, .right, "Align Right", "text.alignright", "⌥⌘R"),
    ]

    private func selectionIsTables(_ selected: [EaselItem]) -> Bool {
        !selected.isEmpty && selected.allSatisfy { $0.kind == .table }
    }

    private var editingTableText: Bool { isEditingTableCell && editor != nil }

    func selectionToolbarTableSupports(_ control: EaselToolbarControl, selected: [EaselItem]) -> Bool? {
        guard selectionIsTables(selected) else { return nil }
        let unlocked = selected.contains { !$0.isLocked }
        if editingTableText {
            switch control {
            case .typeface, .textSize, .bold, .italic, .underline, .strikethrough, .paragraph, .link: return true
            case .alignment: return unlocked
            default: return nil
            }
        }
        guard selected.count == 1 else { return nil }
        switch control {
        case .typeface, .textSize, .bold, .strikethrough, .alignment, .color, .cellFill: return unlocked
        case .mergeCells: return unlocked && tableCellSelection != nil
        default: return nil
        }
    }

    func selectionToolbarTableButton(_ control: EaselToolbarControl, selected: [EaselItem]) -> EaselToolbarButtonModel? {
        guard selectionIsTables(selected), !editingTableText || control == .alignment else { return nil }
        let ready = styleToolbarReady
        let style = selected.first?.resolvedTextStyle ?? EaselTextStyle()
        switch control {
        case .typeface:
            return .init(control: control, face: .text(Self.familyTitle(style.family)), name: "Typeface", isEnabled: ready,
                         opens: .menu, showsDisclosure: true)
        case .textSize:
            return .init(control: control, face: .text(Self.sizeTitle(style.size)), name: "Text size", isEnabled: ready,
                         opens: .menu, showsDisclosure: true)
        case .bold:
            return .init(control: control, face: .glyph("B"), name: TextFormatCommand.bold.title, commandID: TextFormatCommand.bold.bindingID,
                         isChecked: tableCellsHaveEmphasis(.bold), isEnabled: ready)
        case .strikethrough:
            return .init(control: control, face: .glyph("S"), name: TextFormatCommand.strikethrough.title,
                         commandID: TextFormatCommand.strikethrough.bindingID, isChecked: tableCellsHaveEmphasis(.strikethrough),
                         isEnabled: ready, mark: .strikethrough)
        case .alignment:
            return .init(control: control, face: .symbol("text.alignleft"), name: "Alignment", isEnabled: ready, opens: .menu,
                         showsDisclosure: true)
        case .color:
            return .init(control: control, face: .glyph("A"), name: "Text color", isEnabled: ready, opens: .menu, showsDisclosure: true)
        case .cellFill:
            let fill = tableSelectionFill
            let tint = fill.flatMap { $0 }.map { EaselInk.color($0, adaptive: adaptsInk, role: .fill) }
            return .init(control: control, face: .symbol(tint == nil ? "square.dashed" : "square.fill"), name: "Cell color",
                         isEnabled: ready, opens: .menu, showsDisclosure: true, tint: tint)
        case .mergeCells:
            let cells = tableCellSelection
            let unmerges = cells.map { $0.table.hasMerges(in: $0.range) && !$0.table.canMerge($0.range) } ?? false
            let merges = cells.map { $0.table.canMerge($0.range) } ?? false
            return .init(control: control, face: .symbol(unmerges ? "arrow.left.and.line.vertical.and.arrow.right"
                                                                  : "arrow.right.and.line.vertical.and.arrow.left"),
                         name: unmerges ? "Unmerge cells" : "Merge cells", isEnabled: ready && (merges || unmerges))
        default:
            return nil
        }
    }

    func selectionToolbarTableMenu(_ control: EaselToolbarControl) -> [EaselToolbarMenuEntry]? {
        guard let item = selectedTable, !editingTableText || control == .alignment else { return nil }
        let style = item.resolvedTextStyle
        switch control {
        case .typeface:
            return EaselTextStyle.Family.allCases.map {
                EaselToolbarMenuEntry(id: $0.rawValue, title: Self.familyTitle($0), isChecked: $0 == style.family)
            }
        case .textSize:
            return EaselTextStyle.Size.allCases.map {
                EaselToolbarMenuEntry(id: $0.rawValue, title: Self.sizeTitle($0), isChecked: $0 == style.size)
            }
        case .alignment:
            return Self.alignments.map { EaselToolbarMenuEntry(id: $0.0.rawValue, title: $0.2, symbol: $0.3) }
        case .color:
            let dark = NoteTheme.isDark(effectiveAppearance)
            return EaselPalette.colors(for: .ink).compactMap { color in
                guard let hex = EaselPalette.hex(color, role: .ink) else { return nil }
                return EaselToolbarMenuEntry(id: hex, title: color.title(dark: dark), symbol: "circle.fill",
                                             tint: EaselInk.color(hex, adaptive: adaptsInk, role: .ink))
            }
        case .cellFill:
            let dark = NoteTheme.isDark(effectiveAppearance)
            let current = tableSelectionFill
            let none = EaselToolbarMenuEntry(id: "none", title: "No color", symbol: "circle.slash", isChecked: current == .some(nil))
            return [none] + EaselPalette.colors(for: .fill).compactMap { color in
                guard let hex = EaselPalette.hex(color, role: .fill) else { return nil }
                return EaselToolbarMenuEntry(id: hex, title: color.title(dark: dark), symbol: "circle.fill",
                                             isChecked: current == .some(hex), separatorBefore: color == .neutral,
                                             tint: EaselInk.color(hex, adaptive: adaptsInk, role: .fill))
            }
        default:
            return nil
        }
    }

    func performSelectionToolbarTable(_ control: EaselToolbarControl) -> Bool? {
        guard let item = selectedTable, !editingTableText else { return nil }
        guard styleToolbarReady, !item.isLocked else { return false }
        switch control {
        case .bold: return toggleTableCellsEmphasis(.bold)
        case .strikethrough: return toggleTableCellsEmphasis(.strikethrough)
        case .mergeCells:
            guard let cells = tableCellSelection else { return false }
            if cells.table.canMerge(cells.range) { mergeTableCells(); return true }
            if cells.table.hasMerges(in: cells.range) { unmergeTableCells(); return true }
            return false
        default:
            return nil
        }
    }

    func performSelectionToolbarTableMenu(_ control: EaselToolbarControl, entry id: String) -> Bool? {
        guard let item = selectedTable, !editingTableText || control == .alignment else { return nil }
        guard styleToolbarReady, !item.isLocked else { return false }
        switch control {
        case .typeface:
            guard let family = EaselTextStyle.Family(rawValue: id) else { return false }
            return setTableTextStyle(preservingSize: true) { $0.family = family }
        case .textSize:
            guard let size = EaselTextStyle.Size(rawValue: id) else { return false }
            return setTableTextStyle { $0.size = size }
        case .alignment:
            guard let alignment = Self.alignments.first(where: { $0.0.rawValue == id }) else { return false }
            return setTableCellsAlignment(alignment.1)
        case .color:
            guard EaselPalette.normalized(id) != nil else { return false }
            return setTableCellsTextColor(id)
        case .cellFill:
            if id == "none" { setTableCellFill(nil); return true }
            guard EaselPalette.normalized(id) != nil else { return false }
            setTableCellFill(id)
            return true
        default:
            return nil
        }
    }

    func selectionToolbarStyleSupports(_ control: EaselToolbarControl, selected: [EaselItem]) -> Bool? {
        switch control {
        case .alignment: return EaselTextSizing.canAlign(selected)
        case .pattern: return selected.allSatisfy { $0.kind == .freehand && $0.resolvedBrush == .washi }
        default: return nil
        }
    }

    func selectionToolbarStyleButton(_ control: EaselToolbarControl, selected: [EaselItem]) -> EaselToolbarButtonModel? {
        let ready = styleToolbarReady
        switch control {
        case .alignment:
            let state = textAlignmentState
            let symbol = Self.alignments.first { $0.0 == state }?.3 ?? "text.alignleft"
            return .init(control: control, face: .symbol(symbol), name: "Alignment", isEnabled: ready, opens: .menu, showsDisclosure: true)
        case .pattern:
            return .init(control: control, face: .text(selectedWashiPattern?.title ?? "Mixed"), name: "Tape pattern",
                         isEnabled: ready && selected.contains { !$0.isLocked }, opens: .menu, showsDisclosure: true)
        default:
            return nil
        }
    }

    func selectionToolbarStyleMenu(_ control: EaselToolbarControl) -> [EaselToolbarMenuEntry]? {
        switch control {
        case .alignment:
            let state = textAlignmentState
            return Self.alignments.map {
                EaselToolbarMenuEntry(id: $0.0.rawValue, title: $0.2, symbol: $0.3, shortcut: $0.4, isChecked: $0.0 == state)
            }
        case .pattern:
            let current = selectedWashiPattern
            return EaselWashiPattern.allCases.map { EaselToolbarMenuEntry(id: $0.rawValue, title: $0.title, isChecked: $0 == current) }
        default:
            return nil
        }
    }

    func performSelectionToolbarStyleMenu(_ control: EaselToolbarControl, entry id: String) -> Bool? {
        guard styleToolbarReady else { return false }
        switch control {
        case .alignment:
            guard let alignment = EaselTextStyle.Alignment(rawValue: id) else { return false }
            return alignText(alignment, editing: editor != nil)
        case .pattern:
            guard let pattern = EaselWashiPattern(rawValue: id) else { return false }
            setWashiPattern(pattern)
            return true
        default:
            return nil
        }
    }
}
