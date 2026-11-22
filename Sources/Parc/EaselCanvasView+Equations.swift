import AppKit
import ParcCore

extension EaselCanvasView {
    static var equationEditorFactory: (@MainActor (_ host: NSView, _ source: String, _ isInsideOwner: @escaping (NSEvent) -> Bool) -> EaselEquationEditing)?

    private func equationItem(_ id: UUID?) -> EaselItem? {
        guard let id else { return nil }
        return session.document.items.first { $0.id == id && $0.kind == .equation }
    }

    var canEditEquations: Bool { !session.isClosed && !session.isDeleted && !viewOnly && fixedCanvasSize == nil }

    var editingEquationID: UUID? { equations.editingID }

    func drawEquation(_ item: EaselItem, in rect: NSRect, ink: NSColor, showsEditor: Bool) {
        EaselEquationArtwork.draw(item, in: rect, ink: ink, showsPlaceholder: showsEditor)
    }

    @discardableResult
    func placeEmptyEquation(tex: String = "", beside target: EaselRect? = nil) -> UUID? {
        guard canEditEquations else { return nil }
        cancelPointerInteraction()
        guard finishEditing() else { return nil }
        drawing = false
        let shown = uncoveredVisibleRect
        let visible = EaselRect(x: shown.minX, y: shown.minY, width: shown.width, height: shown.height)
        let top = session.document.items.map(\.zIndex).max() ?? 0
        let text = EaselEquation.clamped(tex)
        guard top < Int.max,
              var frame = target ?? EaselMediaPlacement.placeholderFrame(for: .equation, visible: visible, occupied: session.document.items.map(\.frame)) else { return nil }
        if !EaselEquation.isBlank(text) {
            frame = EaselEquation.frame(natural: EaselEquationArtwork.natural(text), scale: 1,
                                        centeredOn: EaselPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2))
        }
        let item = EaselItem(kind: .equation, frame: frame, zIndex: top + 1, text: text, color: insertionColor)
        let group = session.adoptedGroup ?? UUID()
        guard withObjectMotion(.appear, { commit(EaselMediaPlacement.addName(for: .equation), coalescing: group, { $0.items.append(item) }) }) else { return nil }
        selection = [item.id]
        window?.makeFirstResponder(self)
        needsLayout = true
        NSAccessibility.post(element: self, notification: .layoutChanged)
        if EaselEquation.isBlank(text) { _ = beginEquationEditing(item.id, group: group) }
        return item.id
    }

    @discardableResult
    func beginEquationEditing(_ id: UUID, group: UUID? = nil) -> Bool {
        if equations.editingID == id, let session = equations.session {
            window?.makeFirstResponder(session.textView)
            return true
        }
        guard canEditEquations, equationItem(id) != nil, !(equationItem(id)?.isLocked ?? true), finishImageEditing(),
              let item = equationItem(id), window != nil, let factory = Self.equationEditorFactory else { return false }
        selection = [id]
        let opened = factory(menuHost, item.text) { [weak self] event in
            guard let self, let current = self.equationItem(id) else { return false }
            return self.rect(current).contains(self.convert(event.locationInWindow, from: nil))
        }
        opened.onChange = { [weak self] text in self?.equationTextDidChange(text) }
        opened.onCommit = { [weak self] in self?.endEquationEditing(reselect: true) }
        opened.onCancel = { [weak self] in self?.endEquationEditing(reselect: true, cancelling: true) }
        opened.onClickAway = { [weak self] in self?.endEquationEditing(reselect: false) }
        opened.onDismiss = { [weak self] in self?.finishEquationEditing() }
        equations.session = opened
        equations.editingID = id
        equations.undoGroup = group ?? UUID()
        equations.original = item
        equations.fitNatural = EaselEquationArtwork.typesetSize(item.text) != nil ? EaselEquationArtwork.natural(item.text) : EaselEquation.emptySize
        watchEquationViewport()
        let failure = EaselEquationArtwork.error(of: item.text)
        opened.present(anchor: equationAnchor(item), error: failure?.message, range: failure.map { NSRange(location: $0.offset, length: $0.length) })
        invalidateIncrementalDisplay(layout: true)
        return true
    }

    private func equationAnchor(_ item: EaselItem) -> NSRect {
        menuHost.convert(rect(item), from: self)
    }

    private func watchEquationViewport() {
        unwatchEquationViewport()
        guard let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        equations.observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionEquationPanel() }
        })
    }

    private func unwatchEquationViewport() {
        for observer in equations.observers { NotificationCenter.default.removeObserver(observer) }
        equations.observers.removeAll()
    }

    private func positionEquationPanel() {
        guard let session = equations.session, let item = equationItem(equations.editingID) else { return }
        session.reposition(anchor: equationAnchor(item))
    }

    private func equationTextDidChange(_ raw: String) {
        guard let id = equations.editingID, let item = equationItem(id), !equations.finishing else { return }
        let text = EaselEquation.clamped(raw)
        var frame = item.frame
        if let size = EaselEquationArtwork.typesetSize(text) {
            let next = EaselEquation.natural(typeset: size)
            frame = EaselEquation.refitted(item.frame, from: equations.fitNatural, to: next)
            equations.fitNatural = next
        }
        if text != item.text || frame != item.frame {
            let saved = commit("Edit equation", coalescing: equations.undoGroup) { document in
                guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
                document.items[index].text = text
                document.items[index].frame = frame
            }
            guard saved else { return }
        }
        let failure = EaselEquationArtwork.error(of: text)
        equations.session?.setError(failure?.message, range: failure.map { NSRange(location: $0.offset, length: $0.length) })
        positionEquationPanel()
        invalidateIncrementalDisplay(layout: true)
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    private func endEquationEditing(reselect: Bool, cancelling: Bool = false) {
        let id = equations.editingID
        guard finishEquationEditing(cancelling: cancelling) else { return }
        guard reselect, let id, equationItem(id) != nil else { return }
        selection = [id]
        window?.makeFirstResponder(self)
    }

    @discardableResult
    func finishEquationEditing(cancelling: Bool = false) -> Bool {
        guard let opened = equations.session, let id = equations.editingID else { return true }
        guard !equations.finishing else { return false }
        equations.finishing = true
        defer { equations.finishing = false }
        let group = equations.undoGroup
        if cancelling, let original = equations.original, let current = equationItem(id),
           current.text != original.text || current.frame != original.frame {
            let restored = commit("Edit equation", coalescing: group) { document in
                guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
                document.items[index].text = original.text
                document.items[index].frame = original.frame
            }
            guard restored else { return false }
        }
        let blank = equationItem(id).map { EaselEquation.isBlank($0.text) } ?? false
        unwatchEquationViewport()
        equations.session = nil
        equations.editingID = nil
        equations.undoGroup = nil
        equations.original = nil
        if let responder = window?.firstResponder as? NSView, opened.contains(responder) { window?.makeFirstResponder(self) }
        opened.close(animated: true)
        if blank {
            guard commit("Remove empty equation", coalescing: group, { $0.items.removeAll { $0.id == id } }) else { return false }
            selection.remove(id)
        }
        invalidateIncrementalDisplay(layout: true)
        keyboardStructureChanged()
        return true
    }

    func refreshEquationChrome() {
        guard let opened = equations.session, let id = equations.editingID, !equations.finishing else { return }
        guard let item = equationItem(id), !item.isLocked, canEditEquations, selection == [id] else {
            finishEquationEditing()
            return
        }
        let field = opened.textView
        if item.text != field.string, !field.hasMarkedText() {
            field.string = item.text
            let failure = EaselEquationArtwork.error(of: item.text)
            opened.setError(failure?.message, range: failure.map { NSRange(location: $0.offset, length: $0.length) })
        }
        positionEquationPanel()
    }

    @discardableResult
    func copyEquationTeX(_ id: UUID) -> Bool {
        guard let item = equationItem(id), let text = EaselEquationArtwork.plainText(item) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func equationAccessibilityLabel(_ item: EaselItem) -> String {
        NoteEquationSpeech.label(source: item.text, error: EaselEquationArtwork.error(of: item.text)?.message)
    }

    func equationMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard context.target == .object, context.items.count == 1, let item = context.items.first, item.kind == .equation else { return [] }
        let id = item.id
        return [
            EaselMenuRow(id: "edit-tex", title: "Edit Equation", symbol: "x.squareroot", isEnabled: canEditEquations && !item.isLocked,
                         perform: guardedMenuAction { canvas in _ = canvas.beginEquationEditing(id) }),
            EaselMenuRow(id: "copy-tex", title: "Copy as TeX", symbol: "doc.on.doc", isEnabled: !EaselEquation.isBlank(item.text),
                         perform: guardedMenuAction { canvas in _ = canvas.copyEquationTeX(id) }),
        ]
    }

    func equationToolbarEntries(_ selected: [EaselItem], ready: Bool) -> [EaselToolbarMenuEntry] {
        guard selected.count == 1, let item = selected.first, item.kind == .equation else { return [] }
        return [
            EaselToolbarMenuEntry(id: "equation.edit", title: "Edit Equation", symbol: "x.squareroot",
                                  isEnabled: ready && canEditEquations && !item.isLocked),
            EaselToolbarMenuEntry(id: "equation.copy", title: "Copy as TeX", symbol: "doc.on.doc",
                                  isEnabled: ready && !EaselEquation.isBlank(item.text)),
        ]
    }

    func performEquationToolbar(_ id: String) -> Bool? {
        guard id.hasPrefix("equation."), let target = selection.first, selection.count == 1 else { return nil }
        switch id {
        case "equation.edit": return beginEquationEditing(target)
        case "equation.copy": return copyEquationTeX(target)
        default: return false
        }
    }
}
