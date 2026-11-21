import AppKit
import Combine

@MainActor
final class NoteEaselHost {
    enum Absence: Error, Equatable { case deleted, otherProfile, unavailable(String) }

    private static var hosts: [ObjectIdentifier: NoteEaselHost] = [:]
    private weak var editor: NotePageEditor?
    let directory: URL
    let open: (UUID, String) -> Void
    let elsewhere: (UUID) -> Bool

    private init(editor: NotePageEditor, directory: URL, open: @escaping (UUID, String) -> Void, elsewhere: @escaping (UUID) -> Bool) {
        self.editor = editor
        self.directory = directory.standardizedFileURL
        self.open = open
        self.elsewhere = elsewhere
    }

    static func host(for editor: NotePageEditor) -> NoteEaselHost? {
        guard let host = hosts[ObjectIdentifier(editor)], host.editor === editor else { return nil }
        return host
    }

    static func configure(_ editor: NotePageEditor, directory: URL, open: @escaping (UUID, String) -> Void,
                          elsewhere: @escaping (UUID) -> Bool) {
        let previous = host(for: editor)
        hosts = hosts.filter { $0.value.editor != nil }
        hosts[ObjectIdentifier(editor)] = NoteEaselHost(editor: editor, directory: directory, open: open, elsewhere: elsewhere)
        if previous?.directory != directory.standardizedFileURL { notifyBlocks(of: editor) }
    }

    static func adopt(_ host: NoteEaselHost?, for editor: NotePageEditor) {
        guard let host else { return }
        hosts[ObjectIdentifier(editor)] = NoteEaselHost(editor: editor, directory: host.directory, open: host.open, elsewhere: host.elsewhere)
    }

    static func retire(_ editor: NotePageEditor) {
        guard hosts.removeValue(forKey: ObjectIdentifier(editor)) != nil else { return }
        notifyBlocks(of: editor)
    }

    private static func notifyBlocks(of editor: NotePageEditor) {
        for view in editor.canvas.materializedViews { (view as? NoteEaselBlockView)?.hostDidChange() }
    }

    func store() throws -> EaselStore { try EaselEditorViewController.sharedStore(directory: directory) }

    func session(_ id: UUID) -> Result<EaselSession, Absence> {
        do {
            return .success(try store().load(id))
        } catch EaselStoreError.missingDocument {
            return .failure(elsewhere(id) ? .otherProfile : .deleted)
        } catch {
            return .failure(.unavailable(error.localizedDescription))
        }
    }

    func candidates() -> [NoteEaselPicker.Candidate] {
        ((try? store().list()) ?? []).map { NoteEaselPicker.Candidate(id: $0.id, title: $0.title, itemCount: $0.itemCount) }
    }

    func create(title: String) throws -> EaselSession { try store().create(title: title) }

    func snapshot(_ block: NoteBlock) -> Data? {
        guard let id = NoteEaselAddress.id(of: block), case .success(let session) = session(id), !session.isDeleted else { return nil }
        let canvas = EaselCanvasView(session: session)
        canvas.resizeCanvas(viewport: NSSize(width: 800, height: 600))
        guard let image = canvas.exportImage(backingScale: 2) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor
final class NoteEaselBlockView: NoteCaptionedBlockView, NoteMediaResizing {
    private static let inset: CGFloat = 4
    private static let handleRoom: CGFloat = 8
    private var picker: NoteEaselPickerView?
    private let surface = NoteEaselSurface()
    private let heightHandle = NoteEmbedResizeHandle(frame: NSRect(origin: .zero, size: NoteEmbedResizeHandle.size))
    private let leadingHandle = NoteMediaResizeHandle(edge: .leading)
    private let trailingHandle = NoteMediaResizeHandle(edge: .trailing)
    private var session: EaselSession?
    private var sessionDirectory: URL?
    private var watch: AnyCancellable?
    private var heightStart: Double?
    private var liveHeight: Double?
    private var widthStart: (width: CGFloat, column: CGFloat)?
    private var liveWidth: CGFloat?
    private var tracking: NSTrackingArea?
    private var pointerMonitor: Any?
    private var alignmentMenu: NoteFloatingPanel?

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        heightHandle.setAccessibilityLabel("Resize Easel")
        heightHandle.onDrag = { [weak self] delta in self?.resizeHeight(by: delta, commit: false) }
        heightHandle.onEnd = { [weak self] delta in self?.resizeHeight(by: delta, commit: true) }
        heightHandle.onStep = { [weak self] delta in
            self?.heightStart = nil
            self?.resizeHeight(by: delta, commit: true)
        }
        for handle in [leadingHandle, trailingHandle] {
            handle.owner = self
            handle.isHidden = true
            handle.alphaValue = 0
        }
        surface.onOpen = { [weak self] in self?.openInTab() }
        surface.onDone = { [weak self] in self?.finish(restoreFocus: true) }
        surface.onRemove = { [weak self] in self?.removeBlock() }
        surface.onAlign = { [weak self] in self?.toggleAlignmentMenu() }
        surface.onActivate = { [weak self] event in self?.activate(with: event) }
        surface.noteScrollView = { [weak self] in self?.editor?.canvas.enclosingScrollView }
        for view in [surface, heightHandle, leadingHandle, trailingHandle] as [NSView] { addSubview(view) }
        setAccessibilityElement(false)
        rebuild(notify: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
    }

    override var allowsCaption: Bool { false }

    var easelID: UUID? { NoteEaselAddress.id(of: block) }

    private var host: NoteEaselHost? { editor.flatMap(NoteEaselHost.host(for:)) }

    private var pageHeight: Double { liveHeight ?? NoteEmbedSizing.height(of: block.props) }

    private var frameHeight: CGFloat { NoteEaselSurface.headerHeight + CGFloat(pageHeight) + 1 }

    func hostDidChange() { rebuild() }

    override func update(_ block: NoteBlock) {
        let previous = self.block
        super.update(block)
        if previous.props.height != block.props.height { liveHeight = nil }
        if previous.props.width != block.props.width { liveWidth = nil }
        rebuild(notify: false)
    }

    override func readOnlyDidChange() {
        if !canEdit { finish(restoreFocus: false) }
        rebuild()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { finish(restoreFocus: false) }
    }

    private func rebuild(notify: Bool = true) {
        if let id = easelID {
            picker?.removeFromSuperview()
            picker = nil
            surface.isHidden = false
            attach(id)
        } else {
            detach()
            surface.isHidden = true
            let view = picker ?? NoteEaselPickerView()
            if picker == nil {
                view.candidates = { [weak self] in self?.host?.candidates() ?? [] }
                view.onChoose = { [weak self] choice in self?.choose(choice) }
                view.overlay = { [weak self] in self?.editor?.canvas.overlayView }
                addSubview(view)
                picker = view
            }
            view.editable = canEdit && host != nil
        }
        let showsHandles = easelID != nil && canEdit && surface.isLive
        heightHandle.isHidden = !showsHandles
        if !showsHandles { setWidthHandlesVisible(false) }
        surface.canAlign = showsHandles
        window?.invalidateCursorRects(for: self)
        if notify { invalidateMeasuredHeight() } else { needsLayout = true }
    }

    private func attach(_ id: UUID) {
        guard let host else {
            detach()
            surface.showAbsence(.unavailable("Easels show up when the note is open in a window."), title: NoteEaselAddress.title(of: block),
                                removable: canEdit)
            return
        }
        if let session, session.document.id == id, sessionDirectory == host.directory, !session.isClosed, !session.isDeleted {
            surface.viewOnly = !canEdit
            refreshTitle()
            return
        }
        detach()
        switch host.session(id) {
        case .success(let next):
            session = next
            sessionDirectory = host.directory
            surface.show(EaselCanvasView(session: next), viewOnly: !canEdit)
            watch = next.objectWillChange.sink { [weak self] (_: Void) in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.sessionDidChange() } }
            }
            refreshTitle()
        case .failure(let absence):
            surface.showAbsence(absence, title: NoteEaselAddress.title(of: block), removable: canEdit)
        }
    }

    private func detach() {
        finish(restoreFocus: false)
        watch = nil
        session = nil
        sessionDirectory = nil
        surface.clear()
    }

    private func sessionDidChange() {
        guard let session else { return }
        if session.isDeleted || session.isClosed {
            rebuild()
            return
        }
        refreshTitle()
    }

    private func refreshTitle() {
        guard let session else { return }
        surface.title = session.document.title
    }

    private func choose(_ choice: NoteEaselChoice) {
        guard canEdit, let host, let editor else { return }
        let target: (UUID, String)
        switch choice.action {
        case .existing(let id):
            target = (id, choice.title)
        case .create(let title):
            do {
                let created = try host.create(title: title)
                target = (created.document.id, created.document.title)
            } catch {
                editor.onError?(error)
                return
            }
        }
        let id = blockID
        editor.session.edit("Add Easel", affected: [id]) { page in
            page.update(id) {
                $0.props.source = NoteEaselAddress.address(target.0)
                $0.props.alt = target.1
            }
        }
    }

    private func openInTab() {
        guard let id = easelID, let host else { return }
        host.open(id, session?.document.title ?? NoteEaselAddress.title(of: block))
    }

    private func removeBlock() {
        guard canEdit, let editor else { return }
        editor.session.deleteBlocks([blockID])
    }

    override func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        guard easelID == nil, let picker, picker.editable else { return false }
        return picker.beginEditing()
    }

    private func activate(with event: NSEvent?) {
        guard surface.isLive, !surface.active, let window, window.attachedSheet == nil, let canvas = surface.canvas else { return }
        dismissAlignmentMenu()
        surface.active = true
        canvas.onImageEditingCancel = { [weak self] in self?.finish(restoreFocus: true) }
        if pointerMonitor == nil {
            pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.pointerDown(event) }
                return event
            }
        }
        window.makeFirstResponder(canvas)
        window.invalidateCursorRects(for: self)
        if let event { window.postEvent(event, atStart: true) }
    }

    private func pointerDown(_ event: NSEvent) {
        guard surface.active, let window, event.window === window else { return }
        let point = surface.convert(event.locationInWindow, from: nil)
        if !surface.bounds.contains(point) { finish(restoreFocus: false) }
    }

    func finish(restoreFocus: Bool) {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        guard surface.active else { return }
        surface.active = false
        surface.canvas?.onImageEditingCancel = nil
        guard let window else { return }
        window.invalidateCursorRects(for: self)
        let focusInside = (window.firstResponder as? NSView).map { $0 === surface || $0.isDescendant(of: surface) } ?? false
        guard restoreFocus || focusInside, let editor, window.attachedSheet == nil else { return }
        window.makeFirstResponder(editor.canvas)
        if restoreFocus { editor.session.setSelection(.blocks([blockID])) }
    }

    private func resizeHeight(by delta: CGFloat, commit: Bool) {
        guard canEdit, easelID != nil else { return }
        let start = heightStart ?? NoteEmbedSizing.height(of: block.props)
        heightStart = commit ? nil : start
        let height = NoteEmbedSizing.resized(from: start, by: Double(delta))
        guard commit else {
            if liveHeight != height {
                liveHeight = height
                invalidateMeasuredHeight()
            }
            return
        }
        let stored = NoteEmbedSizing.stored(height)
        liveHeight = nil
        guard stored != block.props.height, let session = editor?.session else {
            invalidateMeasuredHeight()
            return
        }
        let id = blockID
        session.edit("Resize Easel", affected: [id]) { page in
            page.update(id) { $0.props.height = stored }
        }
        invalidateMeasuredHeight()
    }

    private var columnWidth: CGFloat { bounds.width }

    private var boxWidth: CGFloat {
        liveWidth ?? NotePDFLayout.displayWidth(fraction: block.props.width, columnWidth: columnWidth)
    }

    func beginResize() {
        guard canEdit, easelID != nil else { return }
        dismissAlignmentMenu()
        widthStart = (boxWidth, columnWidth)
    }

    func updateResize(edge: NoteMediaEdge, delta: CGFloat) {
        guard let start = widthStart else { return }
        let raw = NotePDFLayout.rawResize(start: start.width, dragDelta: delta, leading: edge == .leading, alignment: block.props.alignment)
        liveWidth = NotePDFLayout.rubberBanded(raw, columnWidth: start.column).rounded()
        needsLayout = true
    }

    func endResize() {
        guard let start = widthStart else { return }
        widthStart = nil
        let fraction = NotePDFLayout.storedFraction(width: liveWidth ?? start.width, columnWidth: start.column)
        liveWidth = nil
        needsLayout = true
        guard canEdit, fraction != block.props.width else { return }
        editor?.session.updateBlock(blockID, name: "Resize Easel") { $0.props.width = fraction }
    }

    private func toggleAlignmentMenu() {
        if alignmentMenu != nil { dismissAlignmentMenu(); return }
        guard canEdit, let overlay = editor?.canvas.overlayView else { return }
        let list = NoteMenuList()
        list.items = NoteAlignment.allCases.map { alignment in
            NoteMenuList.Item(id: alignment.rawValue, title: NoteImageContentView.alignmentTitle(alignment),
                              icon: .symbol(NoteImageContentView.alignmentSymbol(alignment)), isChecked: alignment == block.props.alignment)
        }
        list.prepare(origin: .pointer)
        list.onActivate = { [weak self] item in
            guard let self, let alignment = NoteAlignment(rawValue: item.id) else { return }
            self.dismissAlignmentMenu()
            guard self.canEdit, alignment != self.block.props.alignment else { return }
            self.editor?.session.updateBlock(self.blockID, name: "Align Easel") { $0.props.alignment = alignment }
        }
        list.onCancel = { [weak self] in self?.dismissAlignmentMenu() }
        let panel = NoteFloatingPanel(content: list)
        alignmentMenu = panel
        panel.present(in: overlay, anchor: overlay.convert(surface.alignAnchor, from: surface), edge: .below, animated: true)
    }

    private func dismissAlignmentMenu() {
        alignmentMenu?.dismiss(animated: true)
        alignmentMenu = nil
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        guard easelID != nil else { return ceil(Self.inset * 2 + NoteEaselPickerView.height) }
        return ceil(Self.inset + frameHeight + Self.handleRoom + Self.inset)
    }

    override var handleAnchorY: CGFloat {
        easelID == nil ? Self.inset + NoteEaselPickerView.height / 2 : Self.inset + NoteEaselSurface.headerHeight / 2
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        guard easelID != nil else {
            picker?.frame = NSRect(x: 0, y: Self.inset, width: width, height: NoteEaselPickerView.height)
            return
        }
        let boxWidth = min(self.boxWidth, width + NotePDFLayout.rubberBandDimension)
        let x = NotePDFLayout.originX(width: boxWidth, alignment: block.props.alignment, columnWidth: width)
        let box = NSRect(x: x, y: Self.inset, width: boxWidth, height: frameHeight)
        NoteAnimation.withoutAnimation { surface.frame = box }
        let size = NoteEmbedResizeHandle.size
        heightHandle.frame = NSRect(x: (box.midX - size.width / 2).rounded(), y: box.maxY - size.height / 2 + 1, width: size.width, height: size.height)
        let handleHeight = min(48, max(24, (box.height - NoteEaselSurface.headerHeight) * 0.25))
        let handleY = (box.minY + NoteEaselSurface.headerHeight + (box.height - NoteEaselSurface.headerHeight - handleHeight) / 2).rounded()
        leadingHandle.frame = NSRect(x: box.minX - 10, y: handleY, width: 14, height: handleHeight)
        trailingHandle.frame = NSRect(x: box.maxX - 4, y: handleY, width: 14, height: handleHeight)
    }

    override func setBlockSelected(_ selected: Bool, animated: Bool) {
        super.setBlockSelected(selected, animated: animated)
        surface.selected = selected
    }

    override func resetCursorRects() {
        guard surface.isLive, !surface.active, !surface.viewOnly else { return }
        addCursorRect(convert(surface.canvasRect, from: surface), cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func setWidthHandlesVisible(_ visible: Bool) {
        let show = visible && !heightHandle.isHidden
        leadingHandle.setRevealed(show)
        trailingHandle.setRevealed(show)
    }

    override func mouseEntered(with event: NSEvent) {
        heightHandle.setVisible(!heightHandle.isHidden)
        setWidthHandlesVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        heightHandle.setVisible(false)
        if widthStart == nil { setWidthHandlesVisible(false) }
    }
}

@MainActor
final class NoteEaselSurface: NSView {
    static let headerHeight: CGFloat = 38
    var onOpen: (() -> Void)?
    var onDone: (() -> Void)?
    var onRemove: (() -> Void)?
    var onAlign: (() -> Void)?
    var onActivate: ((NSEvent?) -> Void)?
    var noteScrollView: () -> NSScrollView? = { nil }
    private(set) var canvas: EaselCanvasView?
    var viewOnly = false { didSet { if viewOnly != oldValue { refresh() } } }
    var canAlign = false { didSet { if canAlign != oldValue { refresh() } } }
    var active = false {
        didSet {
            guard active != oldValue else { return }
            refresh()
            refreshRing()
        }
    }
    var selected = false { didSet { if selected != oldValue { refreshRing() } } }
    var title = "" {
        didSet {
            titleLabel.stringValue = title.isEmpty ? NoteEaselAddress.defaultTitle : title
            setAccessibilityLabel("Easel: " + titleLabel.stringValue)
        }
    }
    var isLive: Bool { canvas != nil }
    private let content = NSView()
    private let ring = CALayer()
    private let headerRule = CALayer()
    private let icon = NSImageView()
    private let titleLabel: NSTextField
    private let alignButton = NoteToolbarButton(icon: .symbol("text.aligncenter"), label: "Alignment")
    private let openButton = NoteToolbarButton(icon: .symbol("arrow.up.right.square"), label: "Open in a tab")
    private let doneButton = NoteToolbarButton(icon: .symbol("checkmark"), label: "Back to the note")
    private let scroll = NoteEaselScrollView()
    private let shield = NoteEaselShield()
    private let absence = NoteEaselAbsenceView()

    override init(frame: NSRect) {
        titleLabel = NoteMediaStyle.label(NoteEaselAddress.defaultTitle, font: NoteTheme.nunitoBold(13), color: NoteTheme.ink)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        content.wantsLayer = true
        content.layer?.cornerRadius = NoteMediaStyle.cardRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.borderWidth = 1
        content.layer?.masksToBounds = true
        addSubview(content)
        ring.cornerRadius = NoteMediaStyle.cardRadius + 3
        ring.cornerCurve = .continuous
        ring.borderWidth = 2
        ring.opacity = 0
        layer?.addSublayer(ring)
        content.layer?.addSublayer(headerRule)
        icon.image = NoteMediaStyle.symbol(InternalPage.easel(UUID()).sidebarFallbackSymbol, size: 13, weight: .medium)
        icon.contentTintColor = NoteTheme.secondaryInk
        icon.setAccessibilityElement(false)
        titleLabel.setAccessibilityElement(false)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.3333
        scroll.maxMagnification = 4
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.isActive = { [weak self] in self?.active == true }
        scroll.noteScrollView = { [weak self] in self?.noteScrollView() }
        shield.onPress = { [weak self] event in
            guard let self, !self.viewOnly else { return }
            self.onActivate?(event)
        }
        shield.scrollTarget = { [weak self] in self?.noteScrollView() }
        absence.onRemove = { [weak self] in self?.onRemove?() }
        for view in [icon, titleLabel, scroll, shield, absence] as [NSView] { content.addSubview(view) }
        alignButton.onPress = { [weak self] in self?.onAlign?() }
        openButton.onPress = { [weak self] in self?.onOpen?() }
        doneButton.onPress = { [weak self] in self?.onDone?() }
        for button in [alignButton, openButton, doneButton] { content.addSubview(button) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Easel")
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self.ring)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var canvasRect: NSRect {
        NSRect(x: 1, y: Self.headerHeight, width: max(1, bounds.width - 2), height: max(1, bounds.height - Self.headerHeight - 1))
    }

    var alignAnchor: NSRect { alignButton.frame }

    func show(_ canvas: EaselCanvasView, viewOnly: Bool) {
        clear()
        self.canvas = canvas
        self.viewOnly = viewOnly
        scroll.documentView = canvas
        refresh()
        needsLayout = true
    }

    func showAbsence(_ reason: NoteEaselHost.Absence, title: String, removable: Bool) {
        clear()
        self.title = title
        absence.configure(reason, removable: removable)
        refresh()
        needsLayout = true
    }

    func clear() {
        active = false
        scroll.documentView = nil
        canvas = nil
        refresh()
    }

    private func refresh() {
        let live = canvas != nil
        scroll.isHidden = !live
        shield.isHidden = !live || active
        absence.isHidden = live
        openButton.isHidden = !live
        alignButton.isHidden = !canAlign
        doneButton.isHidden = !active
        shield.toolTip = live && !viewOnly ? "Click to edit the Easel" : nil
        needsLayout = true
    }

    private func refreshRing() {
        let target: Float = active || selected ? 1 : 0
        guard ring.opacity != target else { return }
        NoteAnimation.fade(ring, to: target, duration: 0.12)
    }

    override func keyDown(with event: NSEvent) {
        guard !active else { return }
        super.keyDown(with: event)
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        content.frame = bounds
        NoteMediaMotion.instant {
            ring.frame = bounds.insetBy(dx: -3, dy: -3)
            headerRule.frame = NSRect(x: 1, y: Self.headerHeight - 1, width: max(0, width - 2), height: 1)
            content.layer?.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardFill, in: self)
            content.layer?.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
            headerRule.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
        icon.frame = NSRect(x: 12, y: (Self.headerHeight - 16) / 2, width: 16, height: 16)
        var right = width - 8
        for button in [doneButton, openButton, alignButton] where !button.isHidden {
            let size = NSSize(width: 26, height: 26)
            right -= size.width
            button.frame = NSRect(x: right, y: (Self.headerHeight - size.height) / 2, width: size.width, height: size.height)
            right -= 2
        }
        titleLabel.frame = NSRect(x: 34, y: (Self.headerHeight - 18) / 2, width: max(0, right - 40), height: 18)
        let body = canvasRect
        scroll.frame = body
        shield.frame = body
        absence.frame = body
        if let canvas { canvas.resizeCanvas(viewport: scroll.contentSize) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}

@MainActor
private final class NoteEaselScrollView: NSScrollView {
    var isActive: () -> Bool = { false }
    var noteScrollView: () -> NSScrollView? = { nil }
    private var latch = NoteEmbedScrollLatch()
    private let pageID = UUID()

    override func scrollWheel(with event: NSEvent) {
        guard isActive() else {
            if let note = noteScrollView() { note.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
            return
        }
        let phase = NoteEmbeddedPages.scrollPhase(of: event)
        let starts = latch.startsGesture(phase, time: event.timestamp)
        let route = latch.receive(phase, deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY),
                                  time: event.timestamp, pageUnderPointer: starts ? pageID : nil)
        defer { if phase == .momentumEnded || (phase == .ended && event.momentumPhase.isEmpty && !latch.handedOver) { latch = NoteEmbedScrollLatch() } }
        switch route {
        case .note, .native:
            guard let note = noteScrollView() else { return }
            NoteEmbeddedPages.scroll(note, with: event, phase: phase)
        case .page:
            if phase == .began { latch.pageScrollBegan(momentum: false) }
            let before = contentView.bounds.origin
            super.scrollWheel(with: event)
            if event.scrollingDeltaY != 0 { latch.pageScrollUpdated(consumed: contentView.bounds.origin.y != before.y) }
        }
    }

    override func magnify(with event: NSEvent) {
        guard isActive() else { nextResponder?.magnify(with: event); return }
        super.magnify(with: event)
    }
}

@MainActor
private final class NoteEaselShield: NSView {
    var onPress: ((NSEvent) -> Void)?
    var scrollTarget: () -> NSScrollView? = { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { isHidden ? nil : super.hitTest(point) }
    override func mouseDown(with event: NSEvent) { onPress?(event) }
    override func rightMouseDown(with event: NSEvent) { onPress?(event) }

    override func scrollWheel(with event: NSEvent) {
        if let note = scrollTarget() { note.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
}

@MainActor
private final class NoteEaselAbsenceView: NSView {
    var onRemove: (() -> Void)?
    private let icon = NSImageView()
    private let message: NSTextField
    private let remove = NoteChip("Remove", icon: .symbol("trash"))

    override init(frame: NSRect) {
        message = NoteMediaStyle.label("", font: NoteMediaStyle.detailFont, color: NoteTheme.secondaryInk, lines: 2)
        super.init(frame: frame)
        message.alignment = .center
        icon.image = NoteMediaStyle.symbol("square.dashed", size: 22, weight: .regular)
        icon.contentTintColor = NoteTheme.tertiaryInk
        remove.onPress = { [weak self] in self?.onRemove?() }
        for view in [icon, message, remove] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(_ reason: NoteEaselHost.Absence, removable: Bool) {
        switch reason {
        case .deleted: message.stringValue = "This Easel was deleted."
        case .otherProfile: message.stringValue = "This Easel lives in another Profile, so it can’t open in this Space."
        case .unavailable(let text): message.stringValue = text
        }
        remove.isHidden = !removable
        setAccessibilityLabel(message.stringValue)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = min(360, max(0, bounds.width - 32))
        let chip = remove.isHidden ? .zero : remove.intrinsicContentSize
        let total = 26 + 10 + 38 + (chip.height > 0 ? 10 + chip.height : 0)
        var y = max(8, ((bounds.height - total) / 2).rounded())
        icon.frame = NSRect(x: ((bounds.width - 26) / 2).rounded(), y: y, width: 26, height: 26)
        y += 36
        message.frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: y, width: width, height: 38)
        y += 48
        remove.frame = NSRect(x: ((bounds.width - chip.width) / 2).rounded(), y: y, width: chip.width, height: chip.height)
    }
}

@MainActor
final class NoteEaselPickerView: NoteMediaContentHostlessCard, NSTextFieldDelegate {
    static let height: CGFloat = 52
    var candidates: () -> [NoteEaselPicker.Candidate] = { [] }
    var onChoose: ((NoteEaselChoice) -> Void)?
    var overlay: () -> NSView? = { nil }
    var editable = true { didSet { applyMode() } }
    private let icon = NSImageView()
    private let field = NSTextField()
    private let readOnlyLabel: NSTextField
    private var list: NoteMenuList?
    private var panel: NoteFloatingPanel?
    private var choices: [NoteEaselChoice] = []
    private var known: [NoteEaselPicker.Candidate] = []

    override init(frame: NSRect) {
        readOnlyLabel = NoteMediaStyle.label("No Easel here yet", font: NoteMediaStyle.titleFont, color: NoteTheme.secondaryInk)
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = NoteTheme.tertiaryInk
        icon.image = NoteMediaStyle.symbol(InternalPage.easel(UUID()).sidebarFallbackSymbol, size: 16, weight: .medium)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NoteTheme.nunitoRegular(14)
        field.textColor = NoteTheme.ink
        field.placeholderAttributedString = NSAttributedString(string: "Find an Easel, or name a new one…",
            attributes: [.font: NoteTheme.nunitoRegular(14), .foregroundColor: NoteTheme.placeholderInk])
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel("Find an Easel")
        for view in [icon, field, readOnlyLabel] as [NSView] { addSubview(view) }
        applyMode()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyMode() {
        field.isHidden = !editable
        readOnlyLabel.isHidden = editable
        if !editable { dismissList() }
        needsLayout = true
    }

    func beginEditing() -> Bool {
        guard editable, let window, window.makeFirstResponder(field) else { return false }
        known = candidates()
        showList()
        return true
    }

    private func showList() {
        guard editable, let overlay = overlay() else { return }
        choices = NoteEaselPicker.choices(known, query: field.stringValue)
        let items = choices.enumerated().map { index, choice -> NoteMenuList.Item in
            let isNew: Bool
            if case .create = choice.action { isNew = true } else { isNew = false }
            return NoteMenuList.Item(id: String(index), title: choice.title, subtitle: choice.subtitle,
                                     icon: .symbol(isNew ? "plus" : InternalPage.easel(UUID()).sidebarFallbackSymbol),
                                     section: isNew ? nil : "Easels in this Profile", separatorBefore: isNew && index > 0)
        }
        if let list, panel != nil {
            list.setItems(items, keepingHighlight: false)
            panel?.contentSizeDidChange(animated: false)
            return
        }
        let list = NoteMenuList()
        list.rowStyle = .detailed
        list.items = items
        list.prepare(origin: .keyboard)
        list.onActivate = { [weak self] item in self?.activate(item.id) }
        list.onCancel = { [weak self] in self?.dismissList() }
        list.setAccessibilityLabel("Easels")
        let panel = NoteFloatingPanel(content: list)
        self.list = list
        self.panel = panel
        panel.present(in: overlay, anchor: overlay.convert(field.frame.insetBy(dx: -28, dy: -16), from: self), edge: .below, animated: true)
    }

    private func dismissList() {
        panel?.dismiss(animated: true)
        panel = nil
        list = nil
    }

    private func activate(_ id: String) {
        guard let index = Int(id), choices.indices.contains(index) else { return }
        let choice = choices[index]
        dismissList()
        onChoose?(choice)
    }

    func controlTextDidChange(_ obj: Notification) { showList() }

    func controlTextDidEndEditing(_ obj: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.firstResponder !== self.field.currentEditor() else { return }
            self.dismissList()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if panel != nil { dismissList() } else {
                field.stringValue = ""
                window?.makeFirstResponder(nil)
            }
            return true
        }
        if panel == nil, commandSelector == #selector(NSResponder.moveDown(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) {
            showList()
            if commandSelector == #selector(NSResponder.moveDown(_:)) { return true }
        }
        return list?.handle(command: commandSelector) ?? false
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        icon.frame = NSRect(x: 16, y: (height - 18) / 2, width: 18, height: 18)
        field.frame = NSRect(x: 44, y: (height - 20) / 2, width: max(40, bounds.width - 56), height: 20)
        readOnlyLabel.frame = NSRect(x: 44, y: (height - 20) / 2, width: max(0, bounds.width - 56), height: 20)
    }

    override func mouseDown(with event: NSEvent) { _ = beginEditing() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { dismissList() }
    }
}
