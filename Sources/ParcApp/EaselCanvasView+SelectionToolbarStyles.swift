import AppKit

extension EaselCanvasView {
    private var styleToolbarReady: Bool { editor?.hasMarkedText() != true && !session.isClosed && !session.isDeleted }

    static func textAlignment(_ alignment: EaselTextStyle.Alignment) -> NSTextAlignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    private static func easelAlignment(_ alignment: NSTextAlignment) -> EaselTextStyle.Alignment {
        switch alignment {
        case .center: return .center
        case .right: return .right
        default: return .left
        }
    }

    private var tableToolbarCells: (item: EaselItem, values: [NSAttributedString])? {
        let target: (item: EaselItem, range: EaselTableRange)
        if let selected = tableCellSelection { target = (selected.item, selected.range) }
        else if let item = selectedTable, let table = item.table { target = (item, table.all) }
        else { return nil }
        guard let table = target.item.table else { return nil }
        let style = target.item.resolvedTextStyle
        let values = table.expanded(target.range).cells.filter { !table.isCovered($0) }.compactMap { table.cell($0) }
            .filter { !$0.text.isEmpty }
            .map { EaselRichTextCodec.attributed($0.text, richText: $0.richText, style: style, color: target.item.color) }
        return (target.item, values)
    }

    var tableCellsAlignment: EaselTextStyle.Alignment? {
        if editingTableText, let editor {
            let style = editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            return Self.easelAlignment(style?.alignment ?? .natural)
        }
        guard let cells = tableToolbarCells else { return nil }
        var found = Set<EaselTextStyle.Alignment>()
        for value in cells.values {
            value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { style, _, _ in
                found.insert(Self.easelAlignment((style as? NSParagraphStyle)?.alignment ?? .natural))
            }
        }
        if found.isEmpty { return .left }
        return found.count == 1 ? found.first : nil
    }

    var tableCellsTextColor: String? {
        guard let cells = tableToolbarCells else { return nil }
        var found = Set<String>()
        for value in cells.values {
            value.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: value.length)) { color, _, _ in
                guard let color = color as? NSColor else { found.insert(EaselPalette.normalized(cells.item.color) ?? cells.item.color); return }
                let hex = EaselInk.canonicalHex(of: color) ?? (try? EaselRichTextCodec.hex(color)).flatMap { EaselPalette.normalized(String($0.prefix(7))) }
                found.insert(hex ?? "")
            }
        }
        if found.isEmpty { return EaselPalette.normalized(cells.item.color) ?? cells.item.color }
        return found.count == 1 ? found.first.flatMap { $0.isEmpty ? nil : $0 } : nil
    }

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
            let current = tableCellsAlignment
            return .init(control: control, face: .symbol(Self.alignmentSymbol(current ?? .left)), name: "Alignment", isEnabled: ready,
                         opens: .menu, showsDisclosure: true, value: current?.title ?? "Mixed")
        case .color:
            let current = tableCellsTextColor
            let tint = current.map { EaselInk.color($0, adaptive: adaptsInk, role: .ink) }
            return .init(control: control, face: .symbol(tint == nil ? "circle.dashed" : "circle.fill"), name: "Text color", isEnabled: ready,
                         opens: .menu, showsDisclosure: true, tint: tint, value: current == nil ? "Mixed" : nil)
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
            let current = tableCellsAlignment
            return EaselTextStyle.Alignment.allCases.map {
                EaselToolbarMenuEntry(id: $0.rawValue, title: $0.title, symbol: Self.alignmentSymbol($0), shortcut: $0.shortcut,
                                      isChecked: $0 == current)
            }
        case .color:
            let dark = NoteTheme.isDark(effectiveAppearance)
            let current = tableCellsTextColor.flatMap(EaselPalette.normalized)
            return EaselPalette.colors(for: .ink).compactMap { color in
                guard let hex = EaselPalette.hex(color, role: .ink) else { return nil }
                return EaselToolbarMenuEntry(id: hex, title: color.title(dark: dark), symbol: "circle.fill",
                                             isChecked: current != nil && current == EaselPalette.normalized(hex),
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
            guard let alignment = EaselTextStyle.Alignment(rawValue: id) else { return false }
            return setTableCellsAlignment(Self.textAlignment(alignment))
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
        case .color: return styleControls != nil
        case .shape: return editor == nil && selected.allSatisfy { $0.resolvedShape != nil }
        default: return nil
        }
    }

    func selectionToolbarStyleButton(_ control: EaselToolbarControl, selected: [EaselItem]) -> EaselToolbarButtonModel? {
        let ready = styleToolbarReady
        switch control {
        case .alignment:
            let current = textAlignmentState
            return .init(control: control, face: .symbol(Self.alignmentSymbol(current ?? .left)), name: "Alignment",
                         isEnabled: ready, opens: .menu, showsDisclosure: true, value: current?.title ?? "Mixed")
        case .color:
            guard let controls = styleControls else { return nil }
            let editing = editor != nil
            let tint = styleSummary.color.map { EaselInk.color($0.hex(role: controls.colorRole), adaptive: adaptsInk, role: controls.colorRole) }
            return .init(control: control, face: .symbol(tint == nil ? "circle.dashed" : "circle.fill"),
                         name: editing ? "Text color" : "Color and style", isEnabled: ready && (editing || !styleTargets.isEmpty),
                         opens: .stylePicker, showsDisclosure: true, tint: tint, value: tint == nil ? "Mixed" : nil)
        case .shape:
            let shapes = Set(selected.compactMap(\.resolvedShape))
            let current = shapes.count == 1 ? shapes.first : nil
            return .init(control: control, face: .symbol("square.on.circle"), name: "Shape",
                         isEnabled: ready && selected.contains { !$0.isLocked }, opens: .shapePicker, showsDisclosure: true,
                         value: current.map(EaselShapeGeometry.displayName) ?? "Mixed")
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
            return EaselTextStyle.Alignment.allCases.map {
                EaselToolbarMenuEntry(id: $0.rawValue, title: $0.title, symbol: Self.alignmentSymbol($0), shortcut: $0.shortcut,
                                      isChecked: $0 == state)
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

    func makeSelectionToolbarShapePicker() -> EaselShapePickerView? {
        let selected = session.document.items.filter { selection.contains($0.id) }
        guard editor == nil, !selected.isEmpty, selected.allSatisfy({ $0.resolvedShape != nil }),
              selected.contains(where: { !$0.isLocked }) else { return nil }
        let picker = EaselShapePickerView(checked: Set(selected.compactMap(\.resolvedShape)), showsPin: false)
        picker.onPick = { [weak self, weak picker] shape in
            guard let self else { return }
            _ = self.changeSelectedShapes(to: shape)
            picker?.checked = Set(self.session.document.items.filter { self.selection.contains($0.id) }.compactMap(\.resolvedShape))
        }
        return picker
    }
}
