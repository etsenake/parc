import AppKit
import ParcCore

@MainActor
final class NoteEquationBlockView: NoteBlockView {
    static let verticalPadding: CGFloat = 10
    static let minimumHeight: CGFloat = 46
    static let placeholderHeight: CGFloat = 46
    static let horizontalInset = NoteEquationArtwork.horizontalInset
    static let displayScale: CGFloat = 1.2

    private var rendering: NoteMathRendering?
    private var draft: String?
    private var session: NoteEquationEditSession?
    private var isHovered = false { didSet { if oldValue != isHovered { needsDisplay = true } } }
    private var tracking: NSTrackingArea?
    private var scrollOffset: CGFloat = 0

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        rerender()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var source: String { draft ?? block.text.string }
    var isEditing: Bool { session != nil }

    private var pageSettings: NotePageSettings { editor?.session.page.settings ?? NotePageSettings() }

    private var mathSize: CGFloat {
        let body = NoteTheme.bodyFont(pageSettings.font, small: pageSettings.smallText)
        return (NoteMathRenderer.fontSize(matching: body) * Self.displayScale * 4).rounded() / 4
    }

    private var ink: NSColor {
        if let color = block.color, !color.isBackground { return NoteTheme.color(color) }
        return NoteTheme.ink
    }

    private var isBlank: Bool { source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var numbering: NoteMathNumberingContext { editor?.math.context(for: blockID) ?? NoteMathNumberingContext() }
    private var numberingFingerprint = ""

    func mathNumberingDidChange() {
        guard numbering.fingerprint(for: source, display: true) != numberingFingerprint else { return }
        let height = measureHeight(width: bounds.width)
        rerender()
        if measureHeight(width: bounds.width) != height { invalidateHeight() }
    }

    private func linkFrames() -> [NoteMathLinkMark] {
        guard let rendering, rendering.error == nil else { return [] }
        let available = bounds.width - Self.horizontalInset * 2
        let fits = rendering.size.width <= available
        let x = fits ? Self.horizontalInset : Self.horizontalInset - scrollOffset
        let y = ((bounds.height - rendering.size.height) / 2).rounded()
        return rendering.links(width: fits ? available : rendering.size.width).map { link in
            var placed = link
            placed.rect = link.rect.offsetBy(dx: x, dy: y)
            return placed
        }
    }

    private func link(at event: NSEvent) -> NoteMathLinkMark? {
        let point = convert(event.locationInWindow, from: nil)
        return linkFrames().first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private func refreshLinkTooltip(_ event: NSEvent) {
        if let link = link(at: event), !link.resolved {
            parcTooltip = TooltipConfiguration(NotePageMath.missingReferenceTooltip(link.key), anchor: .bottom, anchorRect: link.rect)
        } else if parcTooltip != nil {
            parcTooltip = nil
        }
    }

    private func rerender() {
        let context = numbering
        numberingFingerprint = context.fingerprint(for: source, display: true)
        rendering = isBlank ? nil : NoteMathRenderer.render(source, fontSize: mathSize, color: ink, display: true, numbering: context)
        setAccessibilityLabel(NoteEquationSpeech.label(source: source, error: rendering?.error))
        setAccessibilityHelp(isReadOnly ? nil : "Click to edit the TeX")
        session?.setError(rendering?.error, range: rendering?.errorRange)
        clampScroll()
        needsDisplay = true
    }

    override func update(_ block: NoteBlock) {
        super.update(block)
        rerender()
    }

    override func themeDidChange() {
        super.themeDidChange()
        rerender()
    }

    override func readOnlyDidChange() {
        if isReadOnly { closeEditor(commit: true, reselect: false) }
        window?.refreshCursorUnderPointer()
        rerender()
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        guard !isBlank else { return Self.placeholderHeight }
        guard let rendering else { return Self.minimumHeight }
        if rendering.error != nil { return Self.minimumHeight }
        return max(Self.minimumHeight, ceil(rendering.size.height) + Self.verticalPadding * 2)
    }

    override var handleAnchorY: CGFloat {
        isBlank || rendering?.error != nil ? Self.minimumHeight / 2 : measureHeight(width: bounds.width) / 2
    }

    private func invalidateHeight() {
        needsLayout = true
        needsDisplay = true
        guard window != nil else { return }
        editor?.canvas.blockHeightDidChange(blockID)
    }

    override func layout() {
        super.layout()
        clampScroll()
        repositionPanel()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        repositionPanel()
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = NoteTheme.blockRadius
        if let color = block.color, color.isBackground {
            NoteTheme.color(color).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        if isBlank {
            drawPlaceholder()
        } else if let rendering, rendering.error != nil {
            drawError()
        } else if let rendering, let context = NSGraphicsContext.current?.cgContext {
            if isHovered && !isEditing && !isReadOnly {
                NoteTheme.hoverFill.setFill()
                NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
            }
            let available = bounds.width - Self.horizontalInset * 2
            let fits = rendering.size.width <= available
            let x = fits ? Self.horizontalInset : Self.horizontalInset - scrollOffset
            let y = ((bounds.height - rendering.size.height) / 2).rounded()
            context.saveGState()
            context.clip(to: bounds.insetBy(dx: fits ? 0 : Self.horizontalInset / 2, dy: 0))
            rendering.drawFlipped(in: context, at: CGPoint(x: x, y: y), width: fits ? available : rendering.size.width)
            context.restoreGState()
        }
        if isEditing {
            NoteTheme.blockSelection.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
    }

    private func drawPlaceholder() {
        NoteEquationArtwork.drawPlaceholder(in: bounds, font: NoteTheme.bodyFont(pageSettings.font, small: true),
                                            fill: isHovered && !isReadOnly ? NoteTheme.hoverFill : NoteTheme.mediaPlaceholderFill)
    }

    private func drawError() {
        let radius = NoteTheme.blockRadius
        if isHovered && !isEditing && !isReadOnly {
            NoteTheme.hoverFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        NoteEquationArtwork.drawError(source: source, in: bounds)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func pointerCursor(for event: NSEvent) -> NSCursor {
        guard isReadOnly else { return .pointingHand }
        let point = convert(event.locationInWindow, from: nil)
        return linkFrames().contains { $0.resolved && $0.rect.contains(point) } ? .pointingHand : .arrow
    }

    override func cursorUpdate(with event: NSEvent) {
        if !applyNoteCursor(pointerCursor(for: event), for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        refreshLinkTooltip(event)
    }

    override func mouseMoved(with event: NSEvent) {
        isHovered = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        if isHovered { applyNoteCursor(pointerCursor(for: event), for: event) }
        refreshLinkTooltip(event)
    }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func scrollWheel(with event: NSEvent) {
        guard let rendering, rendering.error == nil, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            super.scrollWheel(with: event)
            return
        }
        let overflow = rendering.size.width - (bounds.width - Self.horizontalInset * 2)
        guard overflow > 0 else { super.scrollWheel(with: event); return }
        scrollOffset -= event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 8)
        clampScroll()
        needsDisplay = true
    }

    private func clampScroll() {
        let overflow = (rendering?.size.width ?? 0) - (bounds.width - Self.horizontalInset * 2)
        scrollOffset = overflow > 0 ? min(max(0, scrollOffset), overflow) : 0
    }

    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .command])
        if modifiers.isEmpty, !isEditing, let link = link(at: event), link.resolved, let editor, editor.math.follow(link) {
            return
        }
        if isReadOnly || !modifiers.isEmpty {
            NoteBlockPointer.selectBlock(self, with: event)
            return
        }
        if isEditing {
            window?.makeFirstResponder(session?.textView)
            return
        }
        openEditor()
    }

    override func accessibilityPerformPress() -> Bool {
        guard !isReadOnly else { return false }
        openEditor()
        return true
    }

    override func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        guard !isReadOnly else { return false }
        openEditor()
        return isEditing
    }

    func openEditor() {
        guard !isReadOnly, session == nil, let editor, window != nil else { return }
        draft = block.text.string
        let opened = NoteEquationEditSession(source: block.text.string, host: editor.canvas.overlayView) { [weak self] event in
            guard let self else { return false }
            return self.bounds.contains(self.convert(event.locationInWindow, from: nil))
        }
        opened.onChange = { [weak self] text in self?.draftDidChange(text) }
        opened.onCommit = { [weak self] in self?.closeEditor(commit: true, reselect: true) }
        opened.onCancel = { [weak self] in self?.closeEditor(commit: false, reselect: true) }
        opened.onClickAway = { [weak self] in self?.closeEditor(commit: true, reselect: false) }
        opened.onDismiss = { [weak self] in self?.finishEditing() }
        session = opened
        opened.present(anchor: anchorRect(in: editor.canvas.overlayView), error: rendering?.error, range: rendering?.errorRange)
        needsDisplay = true
    }

    private func anchorRect(in overlay: NSView) -> NSRect {
        overlay.convert(bounds, from: self)
    }

    private func repositionPanel() {
        guard let session, let overlay = session.panel.superview else { return }
        session.reposition(anchor: anchorRect(in: overlay))
    }

    private func draftDidChange(_ text: String) {
        draft = text
        rerender()
        invalidateHeight()
        editor?.math.draftDidChange(text, for: blockID)
    }

    func closeEditor(commit: Bool, reselect: Bool) {
        guard let closing = session else { return }
        if commit, let final = draft, final != block.text.string {
            editor?.session.updateBlock(blockID, name: "Edit Equation") { $0.text = NoteText(final) }
        }
        finishEditing()
        closing.panel.dismiss(animated: true)
        guard let editor else { return }
        if reselect {
            window?.makeFirstResponder(editor.canvas)
            editor.session.setSelection(.blocks([blockID]))
        }
    }

    private func finishEditing(endingDraft: Bool = true) {
        session?.stopWatching()
        session = nil
        draft = nil
        if endingDraft { editor?.math.endDraft(for: blockID) }
        rerender()
        invalidateHeight()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, let closing = session else { return }
        let final = draft
        let id = blockID
        finishEditing(endingDraft: false)
        closing.panel.dismiss(animated: false)
        guard let editor else { return }
        DispatchQueue.main.async { [weak editor] in
            guard let editor else { return }
            if let final, let current = editor.session.page.block(id), current.text.string != final {
                editor.session.updateBlock(id, name: "Edit Equation") { $0.text = NoteText(final) }
            }
            editor.math.endDraft(for: id)
        }
    }
}
