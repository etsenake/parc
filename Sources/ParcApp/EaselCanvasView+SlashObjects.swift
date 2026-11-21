import AppKit

extension EaselCanvasView {
    var slashContext: EaselSlashContext {
        EaselSlashContext(objects: fixedCanvasSize == nil && !editingLabel && !isEditingTableCell && !viewOnly)
    }

    var slashMenuAvailable: Bool { !editingLabel && !isEditingTableCell && !viewOnly }

    @discardableResult
    func placeSlashObject(_ object: EaselSlashObject) -> Bool {
        guard fixedCanvasSize == nil, !session.isClosed, !session.isDeleted, let id = editingID,
              let text = session.document.items.first(where: { $0.id == id }) else { return false }
        let anchor = text.frame
        let occupied = session.document.items.filter { $0.id != id }.map(\.frame)
        func frame(_ size: (width: Double, height: Double)) -> EaselRect {
            EaselSlashPlacement.frame(size: size, beside: anchor, occupied: occupied)
        }
        switch object {
        case .sticky:
            let side = EaselBoardObjects.stickySide
            let target = frame((side, side))
            return insertSticky(at: NSPoint(x: target.x + target.width / 2, y: target.y + target.height / 2))
        case .shape:
            let size = EaselShapeGeometry.defaultSize(.rectangle)
            return insertShape(.rectangle, in: frame(size))
        case .table:
            let columns = EaselTable.defaultColumns, rows = EaselTable.defaultRows
            let target = frame((Double(columns) * EaselTable.defaultColumnWidth, Double(rows) * EaselTable.defaultRowHeight))
            guard finishEditing() else { return false }
            let top = (session.document.items.map(\.zIndex).max() ?? 0) + 1
            return addTable(EaselTableGeometry.item(columns: columns, rows: rows, frame: target, zIndex: top), name: "Add table")
        case .code:
            let height = EaselCodeBlock.height(lines: EaselCodeBlock.starterLineCount)
            return placeCodeBlock(in: frame((EaselCodeBlock.defaultWidth, height)))
        case .image, .video, .audio, .file, .pdf, .embed, .bookmark, .equation:
            guard let kind = Self.slashKind(object) else { return false }
            return placeEmptyObject(kind, beside: frame(EaselMediaPlacement.placeholderSize(for: kind))) != nil
        }
    }

    private static func slashKind(_ object: EaselSlashObject) -> EaselItemKind? {
        switch object {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .file: return .file
        case .pdf: return .pdf
        case .embed: return .browser
        case .bookmark: return .link
        case .equation: return .equation
        case .sticky, .shape, .table, .code: return nil
        }
    }
}
