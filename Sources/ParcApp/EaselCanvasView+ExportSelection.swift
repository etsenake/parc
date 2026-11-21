import AppKit
import ParcCore

@MainActor
extension EaselCanvasView {
    func exportSelectionRows() -> [EaselMenuRow] {
        let document = session.document
        let scope = EaselSelectionExport.scope(selection, in: document)
        let hasStickies = !EaselSelectionExport.stickies(in: document, within: selection).isEmpty
        let enabled = onExportSelection != nil && !scope.isEmpty && window?.attachedSheet == nil
        return EaselSelectionExportFormat.allCases.compactMap { format in
            guard format != .stickies || hasStickies else { return nil }
            return EaselMenuRow(id: "export-selection-" + format.rawValue, title: format.title, symbol: format.symbol,
                                isEnabled: enabled, perform: guardedMenuAction { canvas in canvas.exportSelection(as: format) })
        }
    }

    func exportSelectionMenuRow() -> EaselMenuRow {
        let children = exportSelectionRows()
        return EaselMenuRow(id: "export-selection", title: "Export Selection", symbol: "square.and.arrow.up",
                            isEnabled: children.contains { $0.isEnabled }, children: children)
    }

    func exportSelection(as format: EaselSelectionExportFormat) {
        let ids = selection
        guard !ids.isEmpty, let onExportSelection, finishEditing() else { return }
        onExportSelection(ids, format)
    }

    @discardableResult
    func presentExportSelectionMenu() -> Bool {
        let objects = selectedObjects
        guard !objects.isEmpty, onExportSelection != nil, finishEditing(),
              let bounds = EaselArrange.union(objects.map(EaselArrange.visualFrame)) else { return false }
        let visible = visibleRect.insetBy(dx: 24, dy: 24)
        let x = min(max(bounds.x + bounds.width / 2, visible.minX), visible.maxX)
        let y = min(max(bounds.y + bounds.height, visible.minY), visible.maxY)
        presentMenu([exportSelectionRows()], anchor: NSRect(x: x, y: y, width: 1, height: 1), keyboard: true, label: "Export Selection")
        return true
    }
}
