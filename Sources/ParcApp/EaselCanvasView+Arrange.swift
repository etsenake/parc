import AppKit

struct EaselCanvasArrangeState {
    var enteredGroup: UUID?
    var lastDuplicate: (sources: [UUID], copies: [UUID])?
    var duplicateDragArmed = false
    var duplicateDrag: (group: UUID, before: EaselDocument, sources: [UUID], copies: [UUID])?
    var lastPaste: (fingerprint: Int, step: Int)?
    var menu: EaselCanvasMenuPresenter?
}

private func easelChordModifiers(_ flags: NSEvent.ModifierFlags) -> EaselKeyModifiers {
    var result: EaselKeyModifiers = []
    if flags.contains(.shift) { result.insert(.shift) }
    if flags.contains(.control) { result.insert(.control) }
    if flags.contains(.option) { result.insert(.option) }
    if flags.contains(.command) { result.insert(.command) }
    return result
}

extension EaselCanvasView {
    var movableSelection: Set<UUID> {
        Set(session.document.items.filter { selection.contains($0.id) && !$0.isLocked }.map(\.id))
    }

    var selectedObjects: [EaselItem] {
        EaselArrange.paintOrder(session.document).filter { selection.contains($0.id) }
    }

    var arrangeScale: Double {
        let scale = enclosingScrollView?.magnification ?? 1
        return scale.isFinite && scale > 0 ? scale : 1
    }

    private func beginArrangeCommand() -> Bool {
        cancelPointerInteraction()
        return !session.isClosed && !session.isDeleted && finishEditing()
    }

    @discardableResult
    private func commitArrangement(_ name: String, moved: Set<UUID>, _ transform: (EaselDocument) -> EaselDocument?) -> Bool {
        guard beginArrangeCommand() else { return false }
        let document = session.document
        guard let next = transform(document) else { return false }
        let settled = EaselDependents.settle(next, previous: document, moved: moved)
        return commit(name) { $0 = settled }
    }

    @discardableResult
    func duplicateSelection() -> Bool {
        guard beginArrangeCommand(), !selection.isEmpty else { return false }
        let document = session.document
        let sources = EaselArrange.paintOrder(document).filter { selection.contains($0.id) }.map(\.id)
        var offset = EaselPoint(x: EaselArrange.duplicateOffset, y: EaselArrange.duplicateOffset)
        if let last = arrangeState.lastDuplicate, Set(last.copies) == selection,
           let repeated = EaselArrange.repeatOffset(sources: last.sources, copies: last.copies, in: document) {
            offset = repeated
        }
        guard let duplication = EaselArrange.duplicating(selection, in: document, offset: offset),
              commit("Duplicate objects", { $0 = duplication.document }) else { return false }
        arrangeState.lastDuplicate = (sources, duplication.copies)
        selection = Set(duplication.copies)
        return true
    }

    @discardableResult
    func groupSelection() -> Bool {
        guard beginArrangeCommand() else { return false }
        let group = UUID()
        guard let next = EaselArrange.grouped(session.document, ids: selection, groupID: group),
              commit("Group objects", { $0 = next }) else { return false }
        arrangeState.enteredGroup = nil
        selection = EaselArrange.members(of: group, in: session.document)
        return true
    }

    @discardableResult
    func ungroupSelection() -> Bool {
        guard beginArrangeCommand(), let next = EaselArrange.ungrouped(session.document, ids: selection),
              commit("Ungroup objects", { $0 = next }) else { return false }
        arrangeState.enteredGroup = nil
        refreshDecorations()
        return true
    }

    @discardableResult
    func setLock(_ locked: Bool, ids: Set<UUID>) -> Bool {
        guard beginArrangeCommand(), let next = EaselArrange.settingLock(locked, ids: ids, in: session.document) else { return false }
        let accepted = commit(locked ? "Lock objects" : "Unlock objects") { $0 = next }
        if accepted { refreshDecorations(); NSAccessibility.post(element: self, notification: .layoutChanged) }
        return accepted
    }

    @discardableResult
    func toggleLock() -> Bool {
        let ids = selection
        guard !ids.isEmpty else { return false }
        return setLock(EaselArrange.shouldLock(ids, in: session.document), ids: ids)
    }

    @discardableResult
    func moveLayer(_ move: EaselLayerMove) -> Bool {
        guard beginArrangeCommand(), let next = EaselArrange.layered(session.document, ids: selection, move) else { return false }
        return commit(move.title) { $0 = next }
    }

    @discardableResult
    func alignSelection(_ alignment: EaselAlignment) -> Bool {
        let ids = selection
        return commitArrangement(alignment.title, moved: ids) { EaselArrange.aligned($0, ids: ids, to: alignment) }
    }

    @discardableResult
    func distributeSelection(_ axis: EaselAxis) -> Bool {
        let ids = selection
        return commitArrangement(axis.distributeTitle, moved: ids) { EaselArrange.distributed($0, ids: ids, along: axis) }
    }

    @discardableResult
    func tidyUpSelection() -> Bool {
        let ids = selection
        return commitArrangement("Tidy up", moved: ids) { EaselArrange.tidied($0, ids: ids) }
    }

    func isInside(group: UUID) -> Bool {
        arrangeState.enteredGroup == group && !selection.isDisjoint(with: EaselArrange.members(of: group, in: session.document))
    }

    func selectForClick(_ hit: EaselItem, extending: Bool, clickCount: Int) -> Bool {
        guard let group = hit.groupID, !isInside(group: group) else {
            if arrangeState.enteredGroup != hit.groupID { arrangeState.enteredGroup = nil }
            if extending { if !selection.insert(hit.id).inserted { selection.remove(hit.id) } }
            else if !selection.contains(hit.id) { selection = [hit.id] }
            return false
        }
        arrangeState.enteredGroup = nil
        if clickCount >= 2, !extending {
            arrangeState.enteredGroup = group
            selection = [hit.id]
            refreshDecorations()
            return true
        }
        let members = EaselArrange.members(of: group, in: session.document)
        if extending {
            if members.isSubset(of: selection) { selection.subtract(members) } else { selection.formUnion(members) }
        } else if !members.isSubset(of: selection) {
            selection = members
        }
        return false
    }

    func marqueeSelection(in rect: EaselRect, items candidates: [EaselItem], original: Set<UUID>,
                          operation: EaselCanvasSelection.Operation) -> Set<UUID> {
        let document = session.document
        if operation == .replace, arrangeState.enteredGroup != nil { arrangeState.enteredGroup = nil; refreshDecorations() }
        let hits = EaselCanvasSelection.selecting(in: rect, items: candidates.filter { !$0.isLocked },
                                                  original: original, operation: .replace)
        let entered = arrangeState.enteredGroup
        let inside = Set(document.items.filter { hits.contains($0.id) && entered != nil && $0.groupID == entered }.map(\.id))
        let caught = EaselArrange.expandingGroups(hits.subtracting(inside), in: document).union(inside)
        let available = Set(document.items.map(\.id))
        switch operation {
        case .replace: return caught
        case .add: return original.union(caught).intersection(available)
        case .subtract: return original.subtracting(caught).intersection(available)
        }
    }

    func handleArrangeKey(_ event: NSEvent) -> Bool {
        let flags = easelChordModifiers(event.modifierFlags)
        if let command = EaselKeyCommands.command(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode, modifiers: flags),
           case .layer(let move) = command {
            guard EaselArrange.canMoveLayer(selection, in: session.document) else { return false }
            moveLayer(move)
            return true
        }
        guard [UInt16(36), UInt16(76)].contains(event.keyCode), flags.isDisjoint(with: [.command, .control, .option]) else { return false }
        let document = session.document
        if flags.contains(.shift) {
            guard let group = EaselArrange.sharedGroup(selection, in: document) else { return false }
            arrangeState.enteredGroup = nil
            selection = EaselArrange.members(of: group, in: document)
            refreshDecorations()
            return true
        }
        guard let group = EaselArrange.wholeGroup(selection, in: document), !isInside(group: group) else { return false }
        arrangeState.enteredGroup = group
        refreshDecorations()
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        if performQuickCreateKey(event) { return true }
        guard event.type == .keyDown, window?.isKeyWindow == true else { return super.performKeyEquivalent(with: event) }
        let editing = textEditorOwnsKeyFocus
        guard editing || canvasOwnsKeyFocus,
              let command = EaselChords.command(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode,
                                                modifiers: easelChordModifiers(event.modifierFlags)),
              performChord(command, editing: editing) else { return super.performKeyEquivalent(with: event) }
        return true
    }

    func performChord(_ command: EaselChordCommand, editing: Bool) -> Bool {
        let document = session.document
        let ready = !editing && canFinishEditingForTransfer
        switch command {
        case .duplicate: return claim(ready && !selection.isEmpty) { duplicateSelection() }
        case .group: return claim(ready && EaselArrange.canGroup(selection, in: document)) { groupSelection() }
        case .ungroup: return claim(ready && EaselArrange.canUngroup(selection, in: document)) { ungroupSelection() }
        case .unwrap:
            if selectionContainsSection { return claim(ready && selectedSections.contains { !$0.isLocked }) { deleteSectionsKeepingContents() } }
            return claim(ready && EaselArrange.canUngroup(selection, in: document)) { ungroupSelection() }
        case .toggleLock: return claim(ready && !selection.isEmpty) { toggleLock() }
        case .layer(let move): return claim(ready && EaselArrange.canMoveLayer(selection, in: document)) { moveLayer(move) }
        case .alignText(let alignment): return alignText(alignment, editing: editing)
        case .focusSelectionToolbar: return selectionToolbar?.focusFromKeyboard() == true
        }
    }

    private func claim(_ applies: Bool, _ action: () -> Bool) -> Bool {
        guard applies else { return false }
        _ = action()
        return true
    }

    func beginDuplicateDrag() -> Bool {
        arrangeState.duplicateDragArmed = false
        let ids = movableSelection, before = session.document
        guard !ids.isEmpty, let duplication = EaselArrange.duplicating(ids, in: before, offset: EaselPoint(x: 0, y: 0)) else { return false }
        let group = UUID()
        guard commit("Duplicate objects", coalescing: group, { $0 = duplication.document }) else { return false }
        let sources = EaselArrange.paintOrder(before).filter { ids.contains($0.id) }.map(\.id)
        arrangeState.duplicateDrag = (group, before, sources, duplication.copies)
        selection = Set(duplication.copies)
        return true
    }

    func finishDuplicateDrag() -> UUID? {
        guard let drag = arrangeState.duplicateDrag else { return nil }
        arrangeState.duplicateDrag = nil
        arrangeState.lastDuplicate = (drag.sources, drag.copies)
        return drag.group
    }

    func abandonDuplicateDrag() {
        arrangeState.duplicateDragArmed = false
        guard let drag = arrangeState.duplicateDrag else { return }
        arrangeState.duplicateDrag = nil
        guard session.undoDestination == drag.before else { return }
        do { try session.undo() } catch { onError?(error) }
    }

    func lockBadgeRect(for item: EaselItem) -> NSRect {
        let scale = arrangeScale, size = 22 / scale, inset = 6 / scale
        let frame = EaselArrange.visualFrame(item)
        if frame.width >= size + 2 * inset, frame.height >= size + 2 * inset {
            return NSRect(x: frame.x + frame.width - size - inset, y: frame.y + inset, width: size, height: size)
        }
        return NSRect(x: frame.x + frame.width + 2 / scale, y: frame.y - size / 2, width: size, height: size)
    }

    var lockBadgeItems: [EaselItem] {
        guard !drawing, !session.isClosed else { return [] }
        return EaselArrange.paintOrder(session.document).filter { $0.isLocked && (selection.contains($0.id) || $0.id == hoveredObjectID) }
    }

    func lockBadge(at point: NSPoint) -> EaselItem? {
        lockBadgeItems.last { lockBadgeRect(for: $0).insetBy(dx: -3 / arrangeScale, dy: -3 / arrangeScale).contains(point) }
    }

    func offerUnlock(at point: NSPoint) -> Bool {
        guard let item = lockBadge(at: point) else { return false }
        presentUnlockMenu(for: item)
        return true
    }

    func drawArrangeDecorations(in dirtyRect: NSRect) {
        let scale = arrangeScale
        if let group = arrangeState.enteredGroup, isInside(group: group),
           let bounds = EaselArrange.union(session.document.items.filter { $0.groupID == group }.map(EaselArrange.visualFrame)) {
            let pad = 6 / scale
            let rect = NSRect(x: bounds.x - pad, y: bounds.y - pad, width: bounds.width + 2 * pad, height: bounds.height + 2 * pad)
            if rect.insetBy(dx: -4 / scale, dy: -4 / scale).intersects(dirtyRect) {
                let path = NSBezierPath(roundedRect: rect, xRadius: 6 / scale, yRadius: 6 / scale)
                path.lineWidth = 1.5 / scale
                path.setLineDash([5 / scale, 4 / scale], count: 2, phase: 0)
                EaselAppearance.selection.withAlphaComponent(0.75).setStroke()
                path.stroke()
            }
        }
        for item in lockBadgeItems {
            let rect = lockBadgeRect(for: item)
            guard rect.insetBy(dx: -4 / scale, dy: -4 / scale).intersects(dirtyRect) else { continue }
            drawLockBadge(in: rect, scale: scale)
        }
    }

    private func drawLockBadge(in rect: NSRect, scale: Double) {
        let circle = NSBezierPath(ovalIn: rect)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NoteTheme.menuShadow
        shadow.shadowBlurRadius = 3 / scale
        shadow.shadowOffset = NSSize(width: 0, height: -1 / scale)
        shadow.set()
        EaselAppearance.surface.setFill()
        circle.fill()
        NSGraphicsContext.restoreGraphicsState()
        EaselAppearance.outline.setStroke()
        circle.lineWidth = 1 / scale
        circle.stroke()
        guard let symbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) else { return }
        let width = symbol.size.width / scale, height = symbol.size.height / scale
        let glyph = NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        symbol.draw(in: glyph, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        EaselAppearance.toolbarInk.setFill()
        glyph.fill(using: .sourceAtop)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
