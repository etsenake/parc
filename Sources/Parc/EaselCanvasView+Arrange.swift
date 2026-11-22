import AppKit
import ParcCore

struct EaselCanvasArrangeState {
    var enteredGroup: UUID?
    var lastDuplicate: (sources: [UUID], copies: [UUID])?
    var duplicateDragArmed = false
    var duplicateDrag: (group: UUID, before: EaselDocument, selected: Set<UUID>, sources: [UUID], copies: [UUID])?
    var lastPaste: (fingerprint: Int, step: Int, pointer: EaselPoint?)?
    var nudge: (ids: Set<UUID>, group: UUID, at: TimeInterval)?
    var menu: EaselCanvasMenuPresenting?
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
        return withObjectMotion(.arrange) { commit(name) { $0 = settled } }
    }

    @discardableResult
    func duplicateSelection() -> Bool {
        guard beginArrangeCommand(), !selection.isEmpty else { return false }
        let document = session.document
        let expanded = EaselArrange.withFollowers(selection, in: document)
        let sources = EaselArrange.paintOrder(document).filter { expanded.contains($0.id) }.map(\.id)
        var offset = EaselPoint(x: EaselArrange.duplicateOffset, y: EaselArrange.duplicateOffset)
        if let last = arrangeState.lastDuplicate, Set(last.copies) == selection,
           let repeated = EaselArrange.repeatOffset(sources: last.sources, copies: last.copies, in: document) {
            offset = repeated
        }
        guard let duplication = EaselArrange.duplicating(selection, in: document, offset: offset),
              withObjectMotion(.copies(sources: sources, copies: duplication.copies), { commit("Duplicate objects", { $0 = duplication.document }) })
        else { return false }
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
        let forward = move == .front || move == .forward
        return withObjectMotion(.layer(forward: forward, ids: selection)) { commit(move.title) { $0 = next } }
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

    func nudgeUndoGroup(for ids: Set<UUID>) -> UUID {
        let now = ProcessInfo.processInfo.systemUptime
        if let nudge = arrangeState.nudge, nudge.ids == ids, now - nudge.at < 1 {
            arrangeState.nudge = (ids, nudge.group, now)
            return nudge.group
        }
        let group = UUID()
        arrangeState.nudge = (ids, group, now)
        return group
    }

    func selectAfterHistoryStep(from before: EaselDocument) {
        guard let picked = EaselArrange.historySelection(from: session.view(of: before), to: session.document) else { return }
        let document = session.document, shown = Set(items.map(\.id)), next = picked.intersection(shown)
        if let group = EaselArrange.sharedGroup(next, in: document) {
            let members = EaselArrange.members(of: group, in: document)
            if !members.isSubset(of: next), EaselArrange.unlocked(members, in: document) != next { arrangeState.enteredGroup = group }
        }
        selection = next
    }

    func isInside(group: UUID) -> Bool {
        EaselArrange.isInside(group, entered: arrangeState.enteredGroup, selection: selection, in: session.document)
    }

    func selectForClick(_ hit: EaselItem, extending: Bool, clickCount: Int) -> Bool {
        let result = EaselArrange.clickSelection(hit: hit, selection: selection, entered: arrangeState.enteredGroup,
                                                 extending: extending, clickCount: clickCount, in: session.document)
        let changedGroup = result.enteredGroup != arrangeState.enteredGroup
        arrangeState.enteredGroup = result.enteredGroup
        selection = result.selection
        if changedGroup { refreshDecorations() }
        return result.enteredByClick
    }

    func marqueeSelection(in rect: EaselRect, items candidates: [EaselItem], original: Set<UUID>,
                          operation: EaselCanvasSelection.Operation) -> Set<UUID> {
        if operation == .replace, arrangeState.enteredGroup != nil { arrangeState.enteredGroup = nil; refreshDecorations() }
        let hits = EaselCanvasSelection.selecting(in: rect, items: candidates.filter { !$0.isLocked },
                                                  original: original, operation: .replace)
        return EaselArrange.marqueeSelection(hits: hits, original: original, operation: operation,
                                             entered: arrangeState.enteredGroup, in: session.document)
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
        guard event.type == .keyDown, window?.isKeyWindow == true else { return super.performKeyEquivalent(with: event) }
        if canvasOwnsKeyFocus, performZoomKeyEquivalent(event) { return true }
        if isDocumentLocked { return super.performKeyEquivalent(with: event) }
        guard EaselChords.consults(canvasFocus: canvasOwnsKeyFocus, editorFocus: textEditorOwnsKeyFocus),
              let command = EaselChords.command(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode,
                                                modifiers: easelChordModifiers(event.modifierFlags),
                                                  stampArmed: tool == .stamp),
              performChord(command) else { return super.performKeyEquivalent(with: event) }
        return true
    }

    func performChord(_ command: EaselChordCommand) -> Bool {
        let document = session.document
        let ready = canFinishEditingForTransfer
        let applies = ready && EaselChords.applies(command, selection: selection, in: document)
        switch command {
        case .duplicate:
            if ready, duplicateTableRowsOrColumns() { return true }
            return claim(applies) { duplicateSelection() }
        case .group: return claim(applies) { groupSelection() }
        case .ungroup: return claim(applies) { ungroupSelection() }
        case .unwrap:
            if selectionContainsSection { return claim(ready && selectedSections.contains { !$0.isLocked }) { deleteSectionsKeepingContents() } }
            return claim(applies) { ungroupSelection() }
        case .toggleLock: return claim(applies) { toggleLock() }
        case .layer(let move): return claim(applies) { moveLayer(move) }
        case .alignText(let alignment):
            if isEditingTableCell || (editor == nil && selectedTable != nil) { return setTableCellsAlignment(Self.textAlignment(alignment)) }
            return alignText(alignment, editing: textEditorOwnsKeyFocus)
        case .stampSelection:
            if stampChordReady, stampSelection() { return true }
            return performMindMapChord(.quickCreate) || performQuickCreate()
        case .quickCreate: return performMindMapChord(command) || performQuickCreate()
        case .mindMapSibling: return performMindMapChord(command)
        case .focusSelectionToolbar: return selectionToolbar?.focusFromKeyboard() == true
        case .exportSelection: return claim(applies && canvasOwnsKeyFocus) { presentExportSelectionMenu() }
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
        let expanded = EaselArrange.withFollowers(ids, in: before)
        let sources = EaselArrange.paintOrder(before).filter { expanded.contains($0.id) }.map(\.id)
        arrangeState.duplicateDrag = (group, before, selection, sources, duplication.copies)
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
        do { try session.undo() } catch { onError?(error); return }
        selection = drag.selected.intersection(Set(session.document.items.map(\.id)))
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

    func addLockBadgeCursorRects() {
        for item in lockBadgeItems { addCursorRect(lockBadgeRect(for: item), cursor: .pointingHand) }
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
