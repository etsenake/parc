import AppKit

@MainActor
enum EaselSectionArt {
    static let radius: CGFloat = 14
    static let titleSize: CGFloat = 13
    static let renameWidth = 220.0

    static func titleFont(scale: Double) -> NSFont { NoteTheme.nunitoExtraBold(titleSize * CGFloat(scale)) }

    static func titleWidth(_ section: EaselItem) -> Double {
        let title = EaselBoardObjects.displayTitle(section) as NSString
        return Double(ceil(title.size(withAttributes: [.font: titleFont(scale: 1)]).width))
    }

    static func titleTab(_ section: EaselItem, zoom: Double) -> NSRect {
        let tab = EaselBoardObjects.titleTab(section, titleWidth: titleWidth(section), zoom: zoom)
        return NSRect(x: tab.x, y: tab.y, width: tab.width, height: tab.height)
    }

    static func renameTab(_ section: EaselItem, zoom: Double) -> NSRect {
        var tab = titleTab(section, zoom: zoom)
        let wanted = renameWidth * EaselBoardObjects.titleScale(zoom: zoom)
        tab.size.width = max(tab.width, min(CGFloat(section.frame.width), CGFloat(wanted)))
        return tab
    }

    static func vectorTitle(_ section: EaselItem, in items: [EaselItem]) -> EaselVectorSectionTitle {
        let font = titleFont(scale: 1), attributes: [NSAttributedString.Key: Any] = [.font: font]
        let room = max(0, section.frame.width - 2 * EaselBoardObjects.sectionTitlePadding)
        var title = EaselBoardObjects.displayTitle(section)
        func width(_ text: String) -> Double { Double(ceil((text as NSString).size(withAttributes: attributes).width)) }
        if width(title) > room {
            var characters = Array(title)
            while !characters.isEmpty, width(String(characters) + "…") > room { characters.removeLast() }
            title = String(characters).trimmingCharacters(in: .whitespaces) + "…"
        }
        return EaselVectorSectionTitle(text: title, width: width(title), baseline: Double(font.ascender + font.descender) / 2,
            hiddenCount: section.contentsHidden == true ? EaselBoardObjects.contents(of: section, in: items).count : nil)
    }

    static func border(_ section: EaselItem, adaptive: Bool) -> NSColor {
        let ink = EaselInk.color(section.color, adaptive: adaptive)
        return ink.withAlphaComponent(EaselInk.isAutomatic(section.color) ? 0.22 : 0.5)
    }

    static func draw(_ section: EaselItem, hiddenCount: Int?, zoom: Double, adaptive: Bool, renaming: Bool) {
        let frame = NSRect(x: section.frame.x, y: section.frame.y, width: section.frame.width, height: section.frame.height)
        let paint = EaselPaint(section, adaptive: adaptive)
        let ink = EaselInk.color(section.color, adaptive: adaptive)
        let line = border(section, adaptive: adaptive)
        let body = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        paint.fill(body)
        line.setStroke(); body.lineWidth = 1.5; body.stroke()
        if let hiddenCount { drawHidden(hiddenCount, in: frame, ink: ink) }
        let scale = EaselBoardObjects.titleScale(zoom: zoom)
        let tab = renaming ? renameTab(section, zoom: zoom) : titleTab(section, zoom: zoom)
        let corner = 7 * CGFloat(scale)
        let pill = NSBezierPath(roundedRect: tab, xRadius: corner, yRadius: corner)
        let tabFill = paint.fillColor.map { $0.withAlphaComponent(max($0.alphaComponent, 0.12)) } ?? line
        tabFill.setFill(); pill.fill()
        line.setStroke(); pill.lineWidth = CGFloat(scale); pill.stroke()
        guard !renaming else { return }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let font = titleFont(scale: scale)
        let inset = CGFloat(EaselBoardObjects.sectionTitlePadding * scale)
        let lineHeight = font.ascender - font.descender
        let textRect = NSRect(x: tab.minX + inset, y: tab.midY - lineHeight / 2, width: max(0, tab.width - 2 * inset), height: lineHeight)
        (EaselBoardObjects.displayTitle(section) as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
    }

    private static func drawHidden(_ count: Int, in frame: NSRect, ink: NSColor) {
        let label = EaselBoardObjects.hiddenSummary(count) as NSString
        let tint = ink.withAlphaComponent(0.72)
        let attributes: [NSAttributedString.Key: Any] = [.font: NoteTheme.nunitoBold(15), .foregroundColor: tint]
        let size = label.size(withAttributes: attributes)
        let symbol = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        let glyph = symbol?.size ?? .zero
        let gap: CGFloat = glyph.width > 0 ? 8 : 0
        let total = glyph.width + gap + size.width
        guard total + 24 <= frame.width, size.height + 24 <= frame.height else { return }
        let left = frame.midX - total / 2
        if let symbol {
            let tinted = NSImage(size: glyph, flipped: false) { bounds in
                symbol.draw(in: bounds)
                tint.set()
                bounds.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: left, y: frame.midY - glyph.height / 2, width: glyph.width, height: glyph.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        label.draw(at: NSPoint(x: left + glyph.width + gap, y: frame.midY - size.height / 2), withAttributes: attributes)
    }
}

@MainActor
final class EaselSectionTitleField: NSTextField, NSTextFieldDelegate {
    let sectionID: UUID
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var finished = false

    init(sectionID: UUID, title: String) {
        self.sectionID = sectionID
        super.init(frame: .zero)
        stringValue = title
        isBordered = false; isBezeled = false; focusRingType = .none
        drawsBackground = true; backgroundColor = NoteTheme.menuFill
        usesSingleLineMode = true; lineBreakMode = .byClipping
        cell?.isScrollable = true; cell?.wraps = false
        delegate = self
        setAccessibilityLabel("Section title")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { finish(commit: true); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finish(commit: false); return true }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        if stringValue.count > EaselBoardObjects.sectionTitleLimit {
            stringValue = String(stringValue.prefix(EaselBoardObjects.sectionTitleLimit))
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) { finish(commit: true) }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        if commit { onCommit?(stringValue) } else { onCancel?() }
    }
}

enum EaselSectionPress {
    case none, handled, marquee
    case object(EaselItem)
}

extension EaselCanvasView {
    func sectionOverhang(_ item: EaselItem) -> CGFloat {
        CGFloat((EaselBoardObjects.sectionTitleHeight + EaselBoardObjects.sectionTitleGap)
            * EaselBoardObjects.titleScale(zoom: canvasScale)) + 4
    }

    func drawSection(_ item: EaselItem, showsEditor: Bool) {
        let hidden = item.contentsHidden == true
            ? EaselBoardObjects.contents(of: item, in: session.document.items).count : nil
        EaselSectionArt.draw(item, hiddenCount: hidden, zoom: showsEditor ? canvasScale : 1, adaptive: adaptsInk,
                             renaming: showsEditor && boardState.titleField?.sectionID == item.id)
        guard showsEditor, paintsLiveFeedback else { return }
        let tray = sectionTrayLevel(item.id), flash = sectionFlashLevel(item.id)
        guard tray > 0 || flash > 0 else { return }
        let frame = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        let body = NSBezierPath(roundedRect: frame, xRadius: EaselSectionArt.radius, yRadius: EaselSectionArt.radius)
        let ink = EaselInk.color(item.color, adaptive: adaptsInk)
        if tray > 0 {
            ink.withAlphaComponent(0.07 * tray).setFill(); body.fill()
            body.lineWidth = 1.5 + 1.5 * tray
            ink.withAlphaComponent(0.25 + 0.45 * tray).setStroke(); body.stroke()
        }
        if flash > 0 {
            body.lineWidth = 2 + 2.5 * flash
            EaselAppearance.selection.withAlphaComponent(0.85 * flash).setStroke(); body.stroke()
        }
    }

    private func sectionTrayLevel(_ id: UUID) -> CGFloat {
        if let tray = canvasFeedback.trays[id] {
            return CGFloat(EaselFeedbackCurve.trayLevel(CACurrentMediaTime() - tray.start, from: tray.from, rising: tray.rising))
        }
        return canvasFeedback.trayTarget == id ? 1 : 0
    }

    private func sectionFlashLevel(_ id: UUID) -> CGFloat {
        guard let start = canvasFeedback.flashes[id] else { return 0 }
        return CGFloat(EaselFeedbackCurve.flashLevel(CACurrentMediaTime() - start))
    }

    func noteSectionCarry(_ moving: [EaselItem]?, originals: [EaselItem]) {
        let target = moving.flatMap { EaselSectionDrop.target(moving: $0, original: originals, in: session.document.items) }
        guard target != canvasFeedback.trayTarget else { return }
        let reduced = feedbackReducesMotion
        let now = CACurrentMediaTime()
        if let old = canvasFeedback.trayTarget {
            let from = Double(sectionTrayLevel(old))
            canvasFeedback.trays[old] = .init(start: now, from: reduced ? 0 : from, rising: false)
        }
        if let target {
            let from = Double(sectionTrayLevel(target))
            canvasFeedback.trays[target] = .init(start: now, from: from, rising: true)
        }
        canvasFeedback.trayTarget = target
        if let target, let section = session.document.items.first(where: { $0.id == target }) { redrawSectionTray(section) }
        startCanvasFeedback()
    }

    func endSectionCarry() {
        guard canvasFeedback.trayTarget != nil else { return }
        noteSectionCarry(nil, originals: [])
    }

    func flashSectionCarry() {
        guard let target = canvasFeedback.trayTarget, canAnimateObjects,
              session.document.items.contains(where: { $0.id == target }) else { return }
        canvasFeedback.flashes[target] = CACurrentMediaTime()
        startCanvasFeedback()
    }

    private func redrawSectionTray(_ section: EaselItem) {
        if usesObjectSurfaces { artwork[section.id]?.needsDisplay = true } else { setNeedsDisplay(displayBounds(of: section)) }
    }

    var selectedSections: [EaselItem] { session.document.items.filter { selection.contains($0.id) && $0.kind == .section } }

    var selectionContainsSection: Bool { !selectedSections.isEmpty }

    func sectionTab(at point: NSPoint) -> EaselItem? {
        items.reversed().first { $0.kind == .section && EaselSectionArt.titleTab($0, zoom: canvasScale).contains(point) }
    }

    func hoverTarget(at point: NSPoint, hit: EaselItem?) -> UUID? {
        if hit == nil || hit?.kind == .section, let tab = sectionTab(at: point) { return tab.id }
        return hit?.kind == .section ? nil : hit?.id
    }

    func marqueeItems(in rect: EaselRect) -> [EaselItem] {
        EaselBoardObjects.marqueeCandidates(session.document.items, in: rect, excluding: boardState.marqueeSections)
    }

    func resetSectionGesture() {
        boardState.pendingSectionClick = nil
        boardState.marqueeSections = []
    }

    func sectionPress(at point: NSPoint, hit: EaselItem?, event: NSEvent) -> EaselSectionPress {
        let shift = event.modifierFlags.contains(.shift)
        if hit == nil || hit?.kind == .section, let tab = sectionTab(at: point) {
            if event.clickCount >= 2 && !shift && !tab.isLocked { beginSectionRename(tab.id); return .handled }
            return .object(tab)
        }
        guard let hit, hit.kind == .section else { return .none }
        if event.clickCount >= 2 && !shift { return .marquee }
        guard shift || !selection.contains(hit.id) else { return .none }
        boardState.pendingSectionClick = hit.id
        boardState.marqueeSections = EaselBoardObjects.sections(containing: EaselPoint(x: point.x, y: point.y), in: session.document.items)
        return .marquee
    }

    func finishSectionClick(_ marquee: NSRect?, shift: Bool) -> Bool {
        guard let id = boardState.pendingSectionClick, let marquee else { return false }
        boardState.pendingSectionClick = nil
        let travel = max(marquee.width, marquee.height) * CGFloat(canvasScale)
        guard travel <= 3, session.document.items.contains(where: { $0.id == id }) else { return false }
        if shift { if !selection.insert(id).inserted { selection.remove(id) } } else { selection = [id] }
        return true
    }

    func addSectionCursorRects() {
        guard !drawing else { return }
        for section in items where section.kind == .section {
            addCursorRect(EaselSectionArt.titleTab(section, zoom: canvasScale), cursor: .pointingHand)
        }
    }

    @discardableResult
    func insertSection(at point: NSPoint) -> Bool {
        addSection(EaselBoardObjects.sectionFrame(centeredAt: EaselPoint(x: point.x, y: point.y)), action: "Add section")
    }

    @discardableResult
    func insertSection(frame: NSRect) -> Bool {
        addSection(EaselBoardObjects.sectionFrame(dragged: EaselRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)),
                   action: "Add section")
    }

    @discardableResult
    func createSection(from ids: Set<UUID>) -> Bool {
        let chosen = session.document.items.filter { ids.contains($0.id) }
        guard !chosen.isEmpty, let frame = EaselBoardObjects.sectionFrame(fitting: chosen.map(\.frame)) else { return false }
        return addSection(frame, action: "Create section")
    }

    private func addSection(_ frame: EaselRect, action: String) -> Bool {
        guard !session.isClosed, !session.isDeleted, fixedCanvasSize == nil else { return false }
        cancelPointerInteraction(); guard finishEditing() else { return false }; drawing = false
        var item = EaselBoardObjects.section(frame: frame, in: session.document.items, zIndex: nextZIndex)
        stampRememberedStyle(on: &item)
        guard commit(action, { $0.items.append(item) }) else { return false }
        selection = [item.id]; window?.makeFirstResponder(self)
        return true
    }

    func beginSectionRename(_ id: UUID) {
        guard !session.isClosed, !session.isDeleted, window != nil,
              let section = session.document.items.first(where: { $0.id == id && $0.kind == .section }), !section.isLocked else { return }
        cancelPointerInteraction(); guard finishEditing() else { return }
        endSectionRename()
        selection = [id]
        let field = EaselSectionTitleField(sectionID: id, title: EaselBoardObjects.displayTitle(section))
        field.onCommit = { [weak self, weak field] value in
            guard let self, let field, self.boardState.titleField === field else { return }
            self.commitSectionRename(id, value)
        }
        field.onCancel = { [weak self, weak field] in
            guard let self, let field, self.boardState.titleField === field else { return }
            self.endSectionRename()
        }
        boardState.titleField = field
        addSubview(field, positioned: .above, relativeTo: nil)
        positionSectionTitleField()
        if window?.makeFirstResponder(field) == true { field.currentEditor()?.selectAll(nil) }
        redrawBoardObject(id)
        invalidateIncrementalDisplay(layout: true)
    }

    func redrawBoardObject(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let reach = boardOverhang(item) + 4
        setNeedsDisplay(rect(item).insetBy(dx: -reach, dy: -reach))
        artwork[id]?.needsDisplay = true
    }

    func positionSectionTitleField() {
        guard let field = boardState.titleField else { return }
        guard let section = session.document.items.first(where: { $0.id == field.sectionID && $0.kind == .section }),
              !section.isLocked, !session.isClosed else {
            endSectionRename(); return
        }
        let scale = EaselBoardObjects.titleScale(zoom: canvasScale)
        let tab = EaselSectionArt.renameTab(section, zoom: canvasScale)
        let font = EaselSectionArt.titleFont(scale: scale)
        let inset = CGFloat(EaselBoardObjects.sectionTitlePadding * scale)
        let height = ceil(font.ascender - font.descender) + 4
        let frame = NSRect(x: tab.minX + inset - 2, y: tab.midY - height / 2, width: max(1, tab.width - 2 * inset + 4), height: height)
        if field.font != font { field.font = font }
        field.textColor = EaselInk.color(section.color, adaptive: adaptsInk)
        if field.frame != frame { field.frame = frame }
    }

    func endSectionRename() {
        guard let field = boardState.titleField else { return }
        let focused = field.currentEditor() != nil
        boardState.titleField = nil
        field.onCommit = nil; field.onCancel = nil
        field.removeFromSuperview()
        if focused { window?.makeFirstResponder(self) }
        redrawBoardObject(field.sectionID)
        invalidateIncrementalDisplay(layout: true)
    }

    private func commitSectionRename(_ id: UUID, _ raw: String) {
        endSectionRename()
        let title = EaselBoardObjects.sectionTitle(raw)
        commit("Rename section") { document in
            guard let index = document.items.firstIndex(where: { $0.id == id && $0.kind == .section && !$0.isLocked }) else { return }
            document.items[index].text = title.isEmpty ? EaselBoardObjects.sectionName(in: document.items, excluding: id) : title
        }
    }

    @discardableResult
    func setSectionContentsHidden(_ hidden: Bool) -> Bool {
        guard !session.isClosed, editor?.hasMarkedText() != true else { return false }
        let ids = Set(selectedSections.map(\.id))
        guard !ids.isEmpty, EaselBoardObjects.settingContentsHidden(hidden, sections: ids, in: session.document) != nil else { return false }
        cancelPointerInteraction(); guard finishEditing() else { return false }
        guard commit(hidden ? "Hide section contents" : "Show section contents", { document in
            if let next = EaselBoardObjects.settingContentsHidden(hidden, sections: ids, in: document) { document = next }
        }) else { return false }
        selection.subtract(EaselBoardObjects.hiddenIDs(in: session.document.items))
        return true
    }

    @discardableResult
    func lockSections(all: Bool) -> Bool {
        let targets = EaselBoardObjects.lockTargets(selection, all: all, in: session.document)
        return !targets.isEmpty && setLock(true, ids: targets)
    }

    @discardableResult
    func unlockSections() -> Bool {
        let targets = EaselBoardObjects.lockTargets(selection, all: true, in: session.document)
        return session.document.items.contains(where: { targets.contains($0.id) && $0.isLocked }) && setLock(false, ids: targets)
    }

    func sectionMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        let chosen = context.items, sections = chosen.filter { $0.kind == .section }
        guard !chosen.isEmpty else {
            let point = NSPoint(x: context.point.x, y: context.point.y)
            return fixedCanvasSize == nil ? [EaselMenuRow(id: "section.add", title: "Add Section", symbol: "rectangle.dashed") { [weak self] in
                self?.insertSection(at: point)
            }] : []
        }
        var rows: [EaselMenuRow] = []
        if sections.count < chosen.count || chosen.count > 1, fixedCanvasSize == nil {
            let ids = Set(chosen.map(\.id))
            rows.append(EaselMenuRow(id: "section.create", title: "Create Section", symbol: "rectangle.dashed") { [weak self] in
                self?.createSection(from: ids)
            })
        }
        guard !sections.isEmpty else { return rows }
        let locked = sections.contains { $0.isLocked }
        if sections.count == 1, let section = sections.first, !section.isLocked {
            rows.append(EaselMenuRow(id: "section.rename", title: "Rename Section", symbol: "pencil", shortcut: "↩") { [weak self] in
                self?.beginSectionRename(section.id)
            })
        }
        let hidden = sections.allSatisfy { $0.contentsHidden == true }
        rows.append(EaselMenuRow(id: "section.contents", title: hidden ? "Show Contents" : "Hide Contents",
                                 symbol: hidden ? "eye" : "eye.slash") { [weak self] in
            self?.setSectionContentsHidden(!hidden)
        })
        if locked {
            rows.append(EaselMenuRow(id: "section.unlock", title: "Unlock Section", symbol: "lock.open") { [weak self] in
                self?.unlockSections()
            })
            return rows
        }
        rows.append(EaselMenuRow(id: "section.lock.all", title: "Lock All", symbol: "lock") { [weak self] in
            self?.lockSections(all: true)
        })
        rows.append(EaselMenuRow(id: "section.lock.background", title: "Lock Background Only", symbol: "square.dashed") { [weak self] in
            self?.lockSections(all: false)
        })
        rows.append(EaselMenuRow(id: "section.deleteOnly", title: "Delete Section Only", symbol: "trash", shortcut: "⌘⌫",
                                 isDestructive: true) { [weak self] in
            self?.deleteSectionsKeepingContents()
        })
        return rows
    }

    @discardableResult
    func deleteSectionsKeepingContents() -> Bool {
        guard !session.isClosed else { return false }
        cancelPointerInteraction(); guard finishEditing() else { return false }
        let ids = Set(selectedSections.filter { !$0.isLocked }.map(\.id))
        guard !ids.isEmpty else { return false }
        guard commit("Delete section", { document in
            guard EaselBoardObjects.removingSections(ids, from: document) != nil else { return }
            document = EaselDependents.removing(ids, from: document, keepingSectionContents: true)
        }) else { return false }
        selection.subtract(ids)
        return true
    }

    func sectionSummary(_ section: EaselItem) -> String {
        let count = EaselBoardObjects.contents(of: section, in: session.document.items).count
        if section.contentsHidden == true { return EaselBoardObjects.hiddenSummary(count) }
        return count == 1 ? "1 object" : "\(count) objects"
    }

    func boardActionNames(_ item: EaselItem) -> [String] {
        guard item.kind == .section else { return [] }
        var names = [item.contentsHidden == true ? "Show contents" : "Hide contents"]
        if !item.isLocked { names.insert("Rename section", at: 0); names.append("Delete section only") }
        return names
    }

    func performBoardAction(_ name: String, item: EaselItem) -> Bool {
        guard item.kind == .section, selection == [item.id] else { return false }
        switch name {
        case "Rename section": beginSectionRename(item.id); return boardState.titleField != nil
        case "Hide contents": return setSectionContentsHidden(true)
        case "Show contents": return setSectionContentsHidden(false)
        case "Delete section only": return deleteSectionsKeepingContents()
        default: return false
        }
    }
}
