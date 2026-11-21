import AppKit
import Combine
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class EaselEditorViewController: NSViewController, NSTextFieldDelegate {
    private static var stores: [String: EaselStore] = [:]
    static func sharedStore(directory: URL) throws -> EaselStore {
        let key = directory.standardizedFileURL.path
        if let store = stores[key] { return store }
        let store = try EaselStore(directory: URL(fileURLWithPath: key, isDirectory: true))
        EaselHistories.attach(to: store)
        EaselInlineDates.shared.attach(to: store)
        store.onListed = { [weak store] summaries in
            guard let store else { return }
            EaselTabIcons.shared.learn(summaries, directory: store.directory)
        }
        stores[key] = store
        return store
    }

    let session: EaselSession
    let easelStore: EaselStore
    let titleField = NSTextField()
    private lazy var titleIcon = EaselTitleIcon(session: session)
    private let status = NSTextField(labelWithString: "Saved on this Mac")
    private let scroll = NSScrollView()
    let canvas: EaselCanvasView
    private(set) lazy var pageMenu = EaselPageMenu(editor: self)
    private(set) lazy var find = EaselFindController(editor: self)
    private var subscription: AnyCancellable?
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    var palette: EaselToolPalette?
    private let recenter = NoteChip("Recenter", icon: .symbol("scope"), style: .filled)
    private var recenterShown = false
    private var barEntered = false
    private static let canvasTop: CGFloat = 64
    private let quickActions = EaselQuickActions()
    let pageSwitcher = EaselPageSwitcher()
    let pageButton = EaselPageSwitcherButton()
    private var pageButtonWidth: CGFloat = 0
    var emptyTemplates: EaselTemplateGallery?
    private(set) var pageObjects: EaselBrowserObjects?
    private var webpageOwnerValid: (() -> Bool)?
    @discardableResult func configurePages(binding: PCNativeBrowserWindow, profilePath: String,
                        validOwner: @escaping () -> Bool, activeOwner: @escaping () -> Bool,
                        selectionChanged: @escaping () -> Void, metadataChanged: @escaping () -> Void,
                        contextImage: @escaping (PCBrowserView, PCNativeContextImage) -> Void,
                        windowTransfer: EaselBrowserObjects.WindowTransfer? = nil) -> Bool {
        if let windowTransfer {
            guard pageObjects?.rebindWindowTransfer(windowTransfer, binding: binding, profilePath: profilePath,
                validOwner: validOwner, activeOwner: activeOwner, selectionChanged: selectionChanged,
                metadataChanged: metadataChanged) == true else { return false }
        } else {
            guard pageObjects == nil else { return true }
            pageObjects = EaselBrowserObjects(session: session, canvas: canvas, binding: binding,
                profilePath: profilePath, validOwner: validOwner, activeOwner: activeOwner, selectionChanged: selectionChanged, metadataChanged: metadataChanged)
        }
        webpageOwnerValid = validOwner
        pageObjects?.onContextImage = contextImage
        pageObjects?.onError = { [weak self] in self?.show($0) }
        canvas.needsLayout = true
        return true
    }
    func refreshPageVisibility() { pageObjects?.refreshVisibility(); canvas.refreshMotionOwnership(); canvas.needsLayout = true }
    func beginPageOwnerWindowTransfer(_ transfer: EaselBrowserObjects.WindowTransfer) -> Bool {
        guard pageObjects?.beginWindowTransfer(transfer) == true else { return false }
        return true
    }
    func retirePageOwner() {
        pageObjects?.disposeAfterClosure()
    }

    var canPrepareForProfileRelocation: Bool {
        !session.isClosed && canvas.canFinishEditingForTransfer &&
            (titleField.currentEditor() as? NSTextView)?.hasMarkedText() != true
    }
    func prepareForProfileRelocation() -> Bool {
        guard canPrepareForProfileRelocation else { return false }
        return canvas.finishEditingForTransfer()
    }
    func prepareForPreviewClose() -> Bool {
        if session.isDeleted || session.isClosed { return true }
        return prepareForProfileRelocation()
    }

    var canAcceptExternalSplitDrop: Bool {
        canvas.canAcceptExternalSplitDrop &&
        (titleField.currentEditor() as? NSTextView)?.hasMarkedText() != true
    }

    var onKeyboardStructureChange: (() -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onOpenNote: ((URL) -> Void)?
    var notesFolder: (() -> URL?)?
    private var panels: EaselPanels?

    init(directory: URL, documentID: UUID) throws {
        easelStore = try Self.sharedStore(directory: directory)
        session = try easelStore.load(documentID)
        canvas = EaselCanvasView(session: session)
        canvas.imageEditing.chrome = EaselImageChrome()
        EaselWebObjects.install(on: canvas)
        canvas.hostedObjects.append(EaselMediaObjects.inEditor(canvas))
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func focusContent() {
        guard isViewLoaded, let window = view.window, window.isKeyWindow,
              window.attachedSheet == nil, !view.isHiddenOrHasHiddenAncestor else { return }
        if let editor = titleField.currentEditor(), window.firstResponder === editor { return }
        if let responder = window.firstResponder as? NSView,
           responder === view || responder.isDescendant(of: view) { return }
        window.makeFirstResponder(canvas)
    }

    override func loadView() {
        let root = EaselDocumentView(frame: .zero)
        view = root
        titleField.stringValue = session.document.title
        titleField.font = NoteTheme.nunitoExtraBold(24)
        titleField.textColor = NoteTheme.titleInk
        titleField.isBezeled = false; titleField.drawsBackground = false
        titleField.delegate = self; titleField.setAccessibilityLabel("Easel title")
        root.addSubview(titleField)
        installTitleIcon(in: root)
        status.font = NoteTheme.captionFont(); status.textColor = NoteTheme.secondaryInk
        root.addSubview(status)
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.3333; scroll.maxMagnification = 4
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.documentView = canvas; root.addSubview(scroll)

        let palette = EaselToolPalette(frame: .zero)
        let panels = EaselPanels(container: { [weak root] in root }, search: { [weak self] query, limit in
            guard let folder = self?.notesFolder?() else { return [] }
            return NoteLibrary.shared(folder: folder).search(query, limit: limit)
        })
        panels.follow = { [weak self] link in self?.canvas.followLink(link) }
        panels.copy = { [weak self] link in self?.canvas.copyLink(link) }
        panels.toast = { [weak self] content in (self?.view.window?.windowController as? BrowserWindowController)?.showToast(content) }
        canvas.panels = panels
        canvas.onOpenNote = { [weak self] url in self?.onOpenNote?(url) }
        canvas.notesFolder = { [weak self] in self?.notesFolder?() }
        self.panels = panels
        palette.onTool = { [weak self] tool, control in
            guard let self else { return }
            self.canvas.activateTool(tool, from: control); self.focusCanvas()
        }
        palette.onShape = { [weak self] shape in self?.canvas.armShape(shape); self?.focusCanvas() }
        palette.onMindMap = { [weak self] in _ = self?.canvas.insertMindMap() }
        palette.onInsert = { [weak self] insert, control in self?.insert(insert, from: control) }
        palette.onInsertKind = { [weak self] kind in self?.insert(kind) }
        palette.canInsert = { [weak self] kind in self?.canInsert(kind) == true }
        palette.onZoom = { [weak self] command in self?.canvas.zoom(command) }
        palette.onZoomTo = { [weak self] value in self?.canvas.zoom(toMagnification: value) }
        palette.onDrag = { [weak self] tool, point, ended in self?.dragTool(tool, to: point, ended: ended) }
        palette.onMenuClose = { [weak self] in
            guard let window = self?.view.window, window.firstResponder == nil || window.firstResponder === window else { return }
            self?.focusCanvas()
        }
        palette.canZoomToSelection = { [weak self] in self?.canvas.canZoomToSelection == true }
        palette.onPreferredSizeChange = { [weak root] in root?.needsLayout = true }
        palette.keepOpenViews = { [weak self] in self.map { [$0.scroll] } ?? [] }
        palette.scrollPassthrough = { [weak self] in self?.canvas }
        canvas.toolState.onQuickActions = { [weak self] in self?.showQuickActions() }
        canvas.onToolChange = { [weak self, weak palette] tool in
            guard let self else { return }
            palette?.update(tool: tool, shape: self.canvas.toolState.shape)
        }
        palette.update(tool: canvas.tool, shape: canvas.toolState.shape)
        palette.showsMermaid = canvas.acceptsMermaid
        palette.showsTemplates = canvas.acceptsTemplates
        self.palette = palette
        recenter.onPress = { [weak self] in self?.canvas.zoomToFit(maximum: 1) }
        recenter.setToolTip("Bring everything back into view")
        recenter.alphaValue = 0; recenter.isHidden = true
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        let chrome = NSStackView()
        chrome.orientation = .horizontal; chrome.spacing = 2
        chrome.setClippingResistancePriority(.init(999), for: .horizontal)
        chrome.setClippingResistancePriority(.init(999), for: .vertical)
        let chromeSize = NoteTheme.toolbarButtonSize.width
        func chromeButton(_ label: String, _ symbol: String, _ action: Selector, shortcut: String? = nil) -> NSButton {
            let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? NSImage()
            let b = EaselPaletteButton(image: glyph, target: self, action: action)
            b.setEaselTooltip(label, shortcut: shortcut); b.setAccessibilityLabel(label)
            b.widthAnchor.constraint(equalToConstant: chromeSize).isActive = true
            b.heightAnchor.constraint(equalToConstant: chromeSize).isActive = true
            chrome.addArrangedSubview(b); return b
        }
        configurePageSwitcher(in: chrome, height: chromeSize)
        let timer = makeTimerButton()
        chrome.addArrangedSubview(timer)
        undoButton = chromeButton("Undo Easel change", "arrow.uturn.backward", #selector(undoChange), shortcut: "⌘Z")
        redoButton = chromeButton("Redo Easel change", "arrow.uturn.forward", #selector(redoChange), shortcut: "⇧⌘Z")
        let options = chromeButton("Easel Options", "ellipsis", #selector(showPageMenu(_:)))
        options.setAccessibilityRole(.menuButton)
        root.addSubview(chrome)
        root.addSubview(recenter)
        root.addSubview(palette)
        installEmptyTemplates(in: root)
        var lastChromeSize = NSSize(width: -1, height: -1)
        var lastIconWidth: CGFloat = -1
        timer.onResize = { [weak root] in lastChromeSize = NSSize(width: -1, height: -1); root?.needsLayout = true }
        root.onLayout = { [weak self, weak root, weak palette, weak chrome, weak timer] in
            guard let self, let root, let palette, let chrome else { return }
            let width = root.bounds.width, height = root.bounds.height, canvasTop = Self.canvasTop
            let bar = EaselFloatingBar.frame(containerWidth: Double(width), containerHeight: Double(height),
                                             preferredWidth: Double(palette.preferredWidth), height: Double(EaselAppearance.toolbarHeight),
                                             top: Double(canvasTop + 8))
            palette.frame = NSRect(x: bar.x, y: bar.y, width: bar.width, height: bar.height)
            self.canvas.setCoveredBottom(CGFloat(EaselFloatingBar.coveredBottom(containerHeight: Double(height), bar: bar)))
            self.playBarEntranceIfNeeded()
            let size = root.bounds.size
            let pageWidth = self.pageButton.intrinsicContentSize.width
            let iconWidth = self.titleIcon.occupiedWidth
            guard size != lastChromeSize || pageWidth != self.pageButtonWidth || iconWidth != lastIconWidth else { return }
            self.pageButtonWidth = pageWidth
            lastChromeSize = size
            lastIconWidth = iconWidth
            let chromeWidth: CGFloat = 3 * chromeSize + 4 * 2 + (timer?.intrinsicContentSize.width ?? chromeSize) + pageWidth
            let titleBase = NSRect(x: 24, y: 10, width: max(80, width - chromeWidth - 52), height: 32)
            self.titleField.frame = self.titleIcon.place(title: titleBase, in: NSRect(x: 0, y: 0, width: width, height: canvasTop))
            chrome.frame = NSRect(x: max(24, width - chromeWidth - 14), y: 12, width: chromeWidth, height: chromeSize)
            self.status.frame = NSRect(x: 26 + iconWidth, y: 40, width: max(100, width - 52 - iconWidth), height: 18)
            self.scroll.frame = NSRect(x: 0, y: canvasTop, width: width, height: max(80, height - canvasTop))
            self.canvas.resizeCanvas(viewport: self.scroll.contentSize)
            self.canvas.fitOnOpenIfNeeded()
            let chip = self.recenter.intrinsicContentSize
            let spot = EaselFloatingBar.chipFrame(width: Double(chip.width), height: Double(chip.height), containerWidth: Double(width),
                                                  bar: bar, top: Double(canvasTop))
            self.recenter.frame = NSRect(x: spot.x, y: spot.y, width: spot.width, height: spot.height)
            self.viewportChanged()
        }
        canvas.onKeyboardStructureChange = { [weak self] in self?.onKeyboardStructureChange?() }
        canvas.onError = { [weak self] error in self?.show(error) }
        canvas.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
        canvas.onExportImage = { [weak self] in self?.exportImage() }
        installSendProvider()
        canvas.onCopiedImage = { [weak self] in self?.showExportToast(.copiedImage) }
        canvas.onExportSelection = { [weak self] ids, format in self?.exportSelection(ids, as: format) }
        canvas.onKeyEquivalent = { [weak self] event in self?.performBoardKeyEquivalent(event) ?? false }
        subscription = session.$document.receive(on: DispatchQueue.main).sink { [weak self] doc in
            guard let self else { return }
            if self.titleField.currentEditor() == nil { self.titleField.stringValue = doc.title }
            self.onTitleChange?(doc.title)
            self.titleIcon.refresh()
            self.undoButton.isEnabled = self.canvas.canUndo; self.redoButton.isEnabled = self.canvas.canRedo
            self.refreshPages()
            self.status.stringValue = "Saved on this Mac · \(doc.items.count) object\(doc.items.count == 1 ? "" : "s")" + (doc.isLocked ? " · Locked" : "")
            self.applyLock(doc.isLocked)
            self.refreshEmptyTemplates()
            self.viewportChanged()
        }
    }
    @objc private func viewportChanged() {
        guard isViewLoaded else { return }
        palette?.setZoom(percent: EaselZoom.percent(Double(scroll.magnification)))
        refreshEmptyTemplates()
        let away = canvas.contentIsOutOfView
        guard away != recenterShown else { return }
        recenterShown = away
        guard away else {
            NoteAnimation.fade(recenter, visible: false, duration: 0.18) { [weak self] in
                guard let self, !self.recenterShown else { return }
                self.recenter.isHidden = true
            }
            return
        }
        recenter.isHidden = false
        NoteAnimation.fade(recenter, visible: true, duration: NoteAnimation.insertDuration)
        NoteAnimation.pop(recenter, from: 0.9, spring: .pop)
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        playBarEntranceIfNeeded()
    }
    override func viewWillDisappear() {
        super.viewWillDisappear()
        panels?.closeAll()
    }
    private func playBarEntranceIfNeeded() {
        guard !barEntered, let palette, palette.window != nil, palette.bounds.width > 0, !view.isHiddenOrHasHiddenAncestor else { return }
        barEntered = true
        palette.playEntrance()
    }
    private func focusCanvas() { canvas.window?.makeFirstResponder(canvas) }
    private func showQuickActions() {
        guard let palette, !session.isClosed, view.window?.attachedSheet == nil else { return }
        palette.closeMenu(animated: false)
        let strip = view.convert(palette.bounds, from: palette)
        quickActions.toggle(in: view, anchor: NSRect(x: strip.midX - 1, y: strip.minY, width: 2, height: strip.height), edge: .above,
                            actions: quickActionList()) { [weak self] in
            guard let window = self?.view.window, window.firstResponder == nil || window.firstResponder === window else { return }
            self?.focusCanvas()
        }
    }
    private func quickActionList() -> [EaselQuickActions.Action] {
        var inserts = EaselQuickActions.catalogInserts(canvas: canvas, canInsert: { [weak self] in self?.canInsert($0) == true }) { [weak self] in self?.focusCanvas() }
        var extras: [(EaselToolPalette.Insert, [String])] = []
        if canvas.acceptsMermaid { extras.append((.mermaid, ["flowchart", "diagram", "chart", "er"])) }
        if canvas.acceptsTemplates { extras.append((.templates, ["template", "starter", "kanban", "retro", "brainstorm", "board"])) }
        inserts += extras.map { insert, keywords in
            EaselQuickActions.Action(id: "insert-" + insert.rawValue, title: EaselToolPalette.title(for: insert),
                                     icon: EaselToolPalette.icon(for: insert), shortcut: nil, keywords: keywords, section: "Add") { [weak self] in
                guard let self, let control = self.palette?.button(for: insert) else { return }
                self.insert(insert, from: control)
            }
        }
        return EaselQuickActions.boardActions(canvas: canvas, inserts: inserts) { [weak self] in self?.focusCanvas() }
    }
    private func canInsert(_ kind: EaselInsertKind) -> Bool {
        kind != .embed || (pageObjects != nil && webpageOwnerValid?() == true)
    }
    private func insert(_ kind: EaselInsertKind) {
        guard !session.isClosed, view.window?.attachedSheet == nil, !view.isHiddenOrHasHiddenAncestor, canInsert(kind),
              let itemKind = kind.itemKind else { return }
        canvas.placeEmptyObject(itemKind)
        focusCanvas()
    }
    private func insert(_ insert: EaselToolPalette.Insert, from control: NSButton) {
        switch insert {
        case .mermaid: _ = canvas.showMermaidSheet()
        case .templates: EaselTemplatePanel.present(editor: self, from: control)
        }
    }
    private func dragTool(_ tool: EaselTool, to point: NSPoint?, ended: Bool) {
        let target = point.flatMap { canvasDropPoint($0) }
        guard ended else { canvas.previewPlacement(tool, atWindowPoint: target); return }
        canvas.previewPlacement(nil, atWindowPoint: nil)
        guard let target else { return }
        if canvas.placeTool(tool, atWindowPoint: target) { focusCanvas() }
    }
    private func canvasDropPoint(_ point: NSPoint) -> NSPoint? {
        guard scroll.bounds.contains(scroll.convert(point, from: nil)) else { return nil }
        let local = canvas.convert(point, from: nil)
        return canvas.uncoveredVisibleRect.contains(local) ? point : nil
    }
    func controlTextDidChange(_ notification: Notification) {
        let value = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do { try session.perform("Rename Easel") { $0.title = value } }
        catch { titleField.stringValue = session.document.title; titleField.currentEditor()?.string = session.document.title; show(error) }
    }
    func controlTextDidBeginEditing(_ notification: Notification) { titleIcon.updateHover() }
    func controlTextDidEndEditing(_ notification: Notification) { titleField.stringValue = session.document.title; titleIcon.updateHover() }
    private func installTitleIcon(in root: NSView) {
        titleIcon.host = { [weak self] in self?.view }
        titleIcon.onGeometryChange = { [weak root] in root?.needsLayout = true }
        titleIcon.onError = { [weak self] in self?.show($0) }
        titleIcon.isTitleEditing = { [weak self] in self?.titleField.currentEditor() != nil }
        titleIcon.titleTextWidth = { [weak self] in self?.titleField.attributedStringValue.size().width ?? 0 }
        root.addSubview(titleIcon)
    }
    func show(_ error: Error) { status.stringValue = error.localizedDescription; NSSound.beep() }
    @objc private func undoChange() { canvas.undo(nil) }
    @objc private func redoChange() { canvas.redo(nil) }
    @objc private func showPageMenu(_ sender: NSButton) {
        guard canExportImage else { return }
        pageMenu.toggle(from: sender)
    }
    var exportAdmission: (() -> Bool)?
    var canExportImage: Bool {
        !session.isClosed && view.window != nil && view.window?.attachedSheet == nil && !view.isHiddenOrHasHiddenAncestor
            && exportAdmission?() != false
    }
    func exportImage() {
        guard canExportImage, let window = view.window else { return }
        EaselImageExport.run(canvas: canvas, title: session.document.title, in: window) { [weak self] in self?.canExportImage == true }
    }
}
