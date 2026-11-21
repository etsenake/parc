import AppKit

extension EaselCanvasView {
    static let codeLanguageDefaultsKey = "easel.codeBlockLanguage"

    static var rememberedCodeLanguage: String? {
        get { UserDefaults.standard.string(forKey: codeLanguageDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: codeLanguageDefaultsKey) }
    }

    private var codeScale: CGFloat {
        let scale = enclosingScrollView?.magnification ?? 1
        return scale.isFinite && scale > 0 ? scale : 1
    }

    private func codeItem(_ id: UUID?) -> EaselItem? {
        guard let id else { return nil }
        return session.document.items.first { $0.id == id && $0.kind == .code }
    }

    private var canEditCode: Bool { !session.isClosed && !session.isDeleted && fixedCanvasSize == nil }

    func drawCodeBlock(_ item: EaselItem, showsEditor: Bool) {
        let r = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        let radius = CGFloat(EaselCodeBlock.cornerRadius)
        let card = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        EaselCodeBlockStyle.cardFill.setFill()
        card.fill()
        EaselCodeBlockStyle.cardStroke.setStroke()
        card.lineWidth = 1
        card.stroke()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        card.addClip()
        let label = EaselCodeBlockStyle.labelFont
        (EaselCodeBlock.displayName(item.language) as NSString).draw(
            at: NSPoint(x: r.minX + EaselCodeBlock.sidePadding, y: r.minY + EaselCodeBlock.labelBaseline - label.ascender),
            withAttributes: [.font: label, .foregroundColor: EaselCodeBlockStyle.labelInk])
        if showsEditor, codeBlocks.editingID == item.id, codeBlocks.editor != nil { return }
        EaselCodeLayoutCache.layout(for: item).draw(in: r)
    }

    func codeBlockItem(frame proposed: EaselRect, id: UUID = UUID()) -> EaselItem {
        let width = proposed.width >= EaselCodeBlock.minimumWidth ? proposed.width : EaselCodeBlock.defaultWidth
        let height = EaselCodeBlock.height(lines: EaselCodeBlock.starterLineCount)
        let origin = EaselPoint(x: proposed.x + proposed.width / 2 - width / 2, y: proposed.y + proposed.height / 2 - height / 2)
        let top = session.document.items.map(\.zIndex).max() ?? 0
        var item = EaselCodeBlock.item(at: origin, language: EaselCodeBlock.newLanguage(remembered: Self.rememberedCodeLanguage),
                                       zIndex: top < Int.max ? top + 1 : top, width: width)
        item.id = id
        return item
    }

    @discardableResult
    func insertCodeBlock(at point: NSPoint? = nil) -> Bool {
        let width = EaselCodeBlock.defaultWidth, height = EaselCodeBlock.height(lines: EaselCodeBlock.starterLineCount)
        let origin: EaselPoint
        if let point {
            origin = EaselPoint(x: point.x - width / 2, y: point.y - height / 2)
        } else {
            let visible = visibleRect
            origin = EaselCodeBlock.placedOrigin(in: EaselRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height),
                                                 width: width, height: height, occupied: session.document.items.map(\.frame))
        }
        return placeCodeBlock(in: EaselRect(x: origin.x, y: origin.y, width: width, height: height))
    }

    @discardableResult
    func placeCodeBlock(in frame: EaselRect) -> Bool {
        guard canEditCode, finishImageEditing() else { return false }
        drawing = false
        return addCodeBlock(codeBlockItem(frame: frame), edit: true)
    }

    @discardableResult
    func insertCodeBlockBelow(_ id: UUID) -> Bool {
        guard canEditCode, codeItem(id) != nil, finishImageEditing(), let source = codeItem(id) else { return false }
        let height = EaselCodeBlock.height(lines: EaselCodeBlock.starterLineCount)
        let others = session.document.items.filter { $0.id != source.id }.map(\.frame)
        let origin = EaselCodeBlock.originBelow(source.frame, height: height, occupied: [source.frame] + others)
        let top = session.document.items.map(\.zIndex).max() ?? 0
        let item = EaselCodeBlock.item(at: origin, language: source.language, zIndex: top < Int.max ? top + 1 : top, width: source.frame.width)
        Self.rememberedCodeLanguage = EaselCodeBlock.rememberedValue(source.language)
        return addCodeBlock(item, edit: true)
    }

    private func addCodeBlock(_ item: EaselItem, edit: Bool) -> Bool {
        do { try session.perform("Add code block") { $0.items.append(item) } } catch { onError?(error); return false }
        selection = [item.id]
        scrollToVisible(NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height).insetBy(dx: -24, dy: -24))
        window?.makeFirstResponder(self)
        if edit { beginCodeEditing(item) }
        return true
    }

    @discardableResult
    func setCodeLanguage(_ language: String?, for ids: Set<UUID>? = nil) -> Bool {
        let stored = language.flatMap(NoteCodeLanguage.named).flatMap(EaselCodeBlock.stored)
        let wanted = ids ?? selection
        let targets = Set(session.document.items.filter { wanted.contains($0.id) && $0.kind == .code && !$0.isLocked }.map(\.id))
        guard canEditCode, !targets.isEmpty else { return false }
        Self.rememberedCodeLanguage = EaselCodeBlock.rememberedValue(stored)
        guard session.document.items.contains(where: { targets.contains($0.id) && $0.language != stored }) else { return true }
        do {
            try session.perform("Change code language") { document in
                for index in document.items.indices where targets.contains(document.items[index].id) {
                    document.items[index].language = stored
                }
            }
        } catch { onError?(error); return false }
        if let editor = codeBlocks.editor, let id = codeBlocks.editingID, targets.contains(id) { editor.applyLanguage(stored) }
        refreshCodeBlockChrome(hidden: false)
        return true
    }

    var selectedCodeLanguages: Set<String> {
        Set(session.document.items.filter { selection.contains($0.id) && $0.kind == .code }.map { EaselCodeBlock.language($0.language).id })
    }

    @discardableResult
    func copyCode(_ id: UUID) -> Bool {
        guard let item = codeItem(id) else { return false }
        let text = codeBlocks.editingID == id ? (codeBlocks.editor?.string ?? item.text) : item.text
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(NoteCodeEditing.trimmedForExit(text), forType: .string)
    }

    @discardableResult
    func beginCodeEditing(_ item: EaselItem, at point: NSPoint? = nil) -> Bool {
        guard canEditCode, item.kind == .code, !item.isLocked, finishImageEditing(), let current = codeItem(item.id) else { return false }
        selection = [current.id]
        let editor = EaselCodeTextView(usingTextLayoutManager: false)
        editor.frame = codeEditorFrame(current)
        editor.configure()
        editor.load(current.text, language: current.language)
        editor.setAccessibilityLabel("Code, " + EaselCodeBlock.displayName(current.language))
        editor.onEdit = { [weak self, weak editor] in
            guard let self, let editor, self.codeBlocks.editor === editor else { return }
            self.codeTextDidChange()
        }
        editor.onExit = { [weak self, weak editor] in
            guard let self, let editor, self.codeBlocks.editor === editor, let id = self.codeBlocks.editingID else { return }
            guard self.finishCodeEditing() else { return }
            self.selection = self.codeItem(id) == nil ? [] : [id]
            self.window?.makeFirstResponder(self)
        }
        editor.onCommandReturn = { [weak self, weak editor] in
            guard let self, let editor, self.codeBlocks.editor === editor, let id = self.codeBlocks.editingID else { return }
            self.insertCodeBlockBelow(id)
        }
        editor.onResign = { [weak self, weak editor] in
            guard let self, let editor, self.codeBlocks.editor === editor, !editor.hasMarkedText(),
                  let responder = self.window?.firstResponder, responder !== editor,
                  self.selectionToolbar?.owns(responder) != true else { return }
            self.finishCodeEditing()
        }
        editor.onUndoDocument = { [weak self] in self?.undo(nil) }
        editor.onRedoDocument = { [weak self] in self?.redo(nil) }
        editor.canUndoDocument = { [weak self] in self?.session.canUndo == true }
        editor.canRedoDocument = { [weak self] in self?.session.canRedo == true }
        codeBlocks.editor = editor
        codeBlocks.editingID = current.id
        codeBlocks.undoGroup = UUID()
        codeBlocks.committedText = current.text
        addSubview(editor, positioned: .above, relativeTo: nil)
        if window?.makeFirstResponder(editor) == true {
            let length = (current.text as NSString).length
            var offset = current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : length
            if let point { offset = min(length, max(0, editor.characterIndexForInsertion(at: editor.convert(point, from: self)))) }
            editor.setSelectedRange(NSRange(location: offset, length: 0))
        }
        invalidateCodeBlock(current.frame)
        needsLayout = true
        refreshCodeBlockChrome(hidden: false)
        return codeBlocks.editingID == current.id
    }

    @discardableResult
    func finishCodeEditing() -> Bool {
        guard let editor = codeBlocks.editor else { return true }
        guard !codeBlocks.finishing else { return false }
        codeBlocks.finishing = true
        defer { codeBlocks.finishing = false }
        if editor.hasMarkedText() {
            editor.unmarkText()
            codeTextDidChange()
        }
        let frame = codeItem(codeBlocks.editingID)?.frame
        codeBlocks.editor = nil
        codeBlocks.editingID = nil
        codeBlocks.undoGroup = nil
        codeBlocks.committedText = nil
        editor.onEdit = nil
        editor.onResign = nil
        if window?.firstResponder === editor { window?.makeFirstResponder(self) }
        editor.removeFromSuperview()
        if let frame { invalidateCodeBlock(frame) }
        refreshCodeBlockChrome(hidden: false)
        return true
    }

    private func codeEditorFrame(_ item: EaselItem) -> NSRect {
        let lines = max(1, Int(((item.frame.height - EaselCodeBlock.headerHeight - EaselCodeBlock.bottomPadding) / EaselCodeBlock.lineHeight).rounded()))
        return NSRect(x: item.frame.x + EaselCodeBlock.sidePadding, y: item.frame.y + EaselCodeBlock.headerHeight,
                      width: EaselCodeBlock.textWidth(forWidth: item.frame.width), height: Double(lines) * EaselCodeBlock.lineHeight)
    }

    private func codeTextDidChange() {
        guard let editor = codeBlocks.editor, let id = codeBlocks.editingID, !editor.hasMarkedText() else { return }
        guard let item = codeItem(id) else { finishCodeEditing(); return }
        let text = editor.string
        let height = EaselCodeBlock.height(lines: editor.lineCount)
        guard text != item.text || height != item.frame.height else { return }
        do {
            try session.perform("Edit code", coalescing: codeBlocks.undoGroup) { document in
                guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
                document.items[index].text = text
                document.items[index].frame.height = height
            }
            codeBlocks.committedText = text
        } catch {
            onError?(error)
            if let current = codeItem(id) { editor.load(current.text, language: current.language); codeBlocks.committedText = current.text }
        }
        if let current = codeItem(id) { editor.frame = codeEditorFrame(current) }
    }

    private func synchronizeCodeEditor() {
        guard let editor = codeBlocks.editor, !codeBlocks.finishing else { return }
        guard let item = codeItem(codeBlocks.editingID), !item.isLocked, canEditCode else { finishCodeEditing(); return }
        if item.text != codeBlocks.committedText, item.text != editor.string, !editor.hasMarkedText() {
            editor.load(item.text, language: item.language)
            codeBlocks.committedText = item.text
        }
        editor.applyLanguage(item.language)
        editor.setAccessibilityLabel("Code, " + EaselCodeBlock.displayName(item.language))
        let frame = codeEditorFrame(item)
        if editor.frame != frame { editor.frame = frame }
    }

    private func invalidateCodeBlock(_ frame: EaselRect) {
        let rect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height).insetBy(dx: -4, dy: -4)
        setNeedsDisplay(rect)
        for view in subviews where view.frame.intersects(rect) && view !== codeBlocks.editor && view !== codeBlocks.bar {
            view.setNeedsDisplay(view.convert(rect, from: self))
        }
    }

    func settledCodeBlocks(_ draft: [EaselItem]?, edit: EaselGeometryEdit) -> [EaselItem]? {
        guard let draft, draft.contains(where: { $0.kind == .code }) else { return draft }
        let originals = Dictionary(edit.originals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let single = edit.originals.count == 1
        return draft.map { item in
            guard item.kind == .code, let original = originals[item.id],
                  item.frame.width != original.frame.width || item.frame.height != original.frame.height else { return item }
            var next = item
            next.frame.width = max(EaselCodeBlock.minimumWidth, item.frame.width)
            let lines = EaselCodeLayoutCache.layout(for: next).lineCount
            next.frame = EaselCodeBlock.settledFrame(item.frame, original: original.frame, lines: lines, keepsTop: single)
            return next
        }
    }

    func showsCodeHandle(_ handle: EaselResizeHandle) -> Bool {
        guard handle == .top || handle == .bottom, !selection.isEmpty, selection.count <= 64 else { return true }
        return !session.document.items.filter { selection.contains($0.id) }.allSatisfy { $0.kind == .code }
    }

    var codeBlockOverlayViews: [NSView] {
        [codeBlocks.editor, codeBlocks.bar.superview === self ? codeBlocks.bar : nil].compactMap { $0 }
    }

    func ownsCodeBlockView(_ view: NSView) -> Bool {
        codeBlockOverlayViews.contains { view === $0 || view.isDescendant(of: $0) }
    }

    func refreshCodeBlockChrome(hidden: Bool) {
        synchronizeCodeEditor()
        let bar = codeBlocks.bar
        let editing = codeItem(codeBlocks.editingID)
        let selected = selection.count == 1 ? codeItem(selection.first) : nil
        guard let item = editing ?? selected, !hidden, !drawing, !session.isClosed else {
            bar.isHidden = true
            return
        }
        if bar.superview !== self { addSubview(bar, positioned: .above, relativeTo: nil) }
        bar.copy.setAccessibilityLabel("Copy code")
        if bar.itemID != item.id || bar.copy.onPress == nil {
            bar.itemID = item.id
            let id = item.id
            bar.copy.onPress = { [weak self, weak bar] in
                guard let self, let bar, self.copyCode(id) else { return }
                bar.copy.flash("Copied!", symbol: "checkmark")
                bar.needsLayout = true
                self.refreshCodeBlockChrome(hidden: false)
            }
            bar.copy.onSizeChange = { [weak self] in self?.refreshCodeBlockChrome(hidden: false) }
        }
        let scale = codeScale, size = bar.preferredSize
        let width = size.width / scale, height = size.height / scale
        let inset = 4 / scale
        guard item.frame.width * scale >= size.width + 24 else { bar.isHidden = true; return }
        let header = EaselCodeBlock.headerHeight
        let y = header * scale >= size.height + 4 ? item.frame.y + (header - height) / 2 : item.frame.y + inset
        bar.frame = NSRect(x: item.frame.x + item.frame.width - inset - width, y: y, width: width, height: height)
        bar.bounds = NSRect(origin: .zero, size: size)
        bar.needsLayout = true
        bar.isHidden = false
    }

    @discardableResult
    func showCodeLanguageMenu(_ id: UUID, from anchor: NSView? = nil) -> Bool {
        guard let item = codeItem(id), canEditCode, !item.isLocked else { return false }
        let current = EaselCodeBlock.language(item.language).id
        let target = EaselCodeLanguageMenuTarget { [weak self] language in
            guard let self else { return }
            self.setCodeLanguage(language, for: [id])
            if let editor = self.codeBlocks.editor, self.codeBlocks.editingID == id { self.window?.makeFirstResponder(editor) }
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for language in NoteCodeLanguage.all {
            let row = NSMenuItem(title: language.name, action: #selector(EaselCodeLanguageMenuTarget.chooseLanguage(_:)), keyEquivalent: "")
            row.target = target
            row.representedObject = language.id
            row.state = language.id == current ? .on : .off
            menu.addItem(row)
        }
        let view = anchor ?? self
        let point = view === self ? NSPoint(x: item.frame.x + EaselCodeBlock.sidePadding, y: item.frame.y + EaselCodeBlock.headerHeight)
            : NSPoint(x: 0, y: view.bounds.maxY + 4)
        withExtendedLifetime(target) {
            _ = menu.popUp(positioning: nil, at: point, in: view)
        }
        return true
    }
}
