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
        stores[key] = store
        return store
    }

    let session: EaselSession
    private let titleField = NSTextField()
    private let status = NSTextField(labelWithString: "Saved on this Mac")
    private let scroll = NSScrollView()
    let canvas: EaselCanvasView
    private(set) lazy var pageMenu = EaselPageMenu(editor: self)
    private(set) lazy var find = EaselFindController(editor: self)
    private var subscription: AnyCancellable?
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var webpageButton: NSButton?
    private var palette: EaselToolPalette?
    private let recenter = NoteChip("Recenter", icon: .symbol("scope"), style: .filled)
    private var recenterShown = false
    private let quickActions = EaselQuickActions()
    private(set) var pageObjects: EaselBrowserObjects?
    private var webpageInput: EaselWebInput?
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
        webpageButton?.isEnabled = true; canvas.needsLayout = true
        return true
    }
    func refreshPageVisibility() { webpageInput?.validate(); pageObjects?.refreshVisibility(); canvas.refreshMotionOwnership(); canvas.needsLayout = true }
    func beginPageOwnerWindowTransfer(_ transfer: EaselBrowserObjects.WindowTransfer) -> Bool {
        guard pageObjects?.beginWindowTransfer(transfer) == true else { return false }
        webpageInput?.cancel(restoreFocus: false); webpageInput = nil
        return true
    }
    func retirePageOwner() {
        webpageInput?.cancel(restoreFocus: false); webpageInput = nil; pageObjects?.disposeAfterClosure()
    }

    var canPrepareForProfileRelocation: Bool {
        !session.isClosed && canvas.canFinishEditingForTransfer && webpageInput == nil &&
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
        canvas.canAcceptExternalSplitDrop && webpageInput == nil &&
        (titleField.currentEditor() as? NSTextView)?.hasMarkedText() != true
    }

    var onKeyboardStructureChange: (() -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onOpenURL: ((URL) -> Void)?

    init(directory: URL, documentID: UUID) throws {
        session = try Self.sharedStore(directory: directory).load(documentID)
        canvas = EaselCanvasView(session: session)
        canvas.imageEditing.chrome = EaselImageChrome()
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
        status.font = NoteTheme.captionFont(); status.textColor = NoteTheme.secondaryInk
        root.addSubview(status)
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.3333; scroll.maxMagnification = 4
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.documentView = canvas; root.addSubview(scroll)

        let palette = EaselToolPalette(frame: .zero)
        palette.onTool = { [weak self] tool, control in
            guard let self else { return }
            self.canvas.activateTool(tool, from: control); self.focusCanvas()
        }
        palette.onShape = { [weak self] shape in self?.canvas.armShape(shape); self?.focusCanvas() }
        palette.onInsert = { [weak self] insert, control in self?.insert(insert, from: control) }
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
        canvas.toolState.onQuickActions = { [weak self] in self?.showQuickActions() }
        canvas.onToolChange = { [weak self, weak palette] tool in
            guard let self else { return }
            palette?.update(tool: tool, shape: self.canvas.toolState.shape)
        }
        palette.update(tool: canvas.tool, shape: canvas.toolState.shape)
        palette.showsMermaid = canvas.acceptsMermaid
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
        func chromeButton(_ label: String, _ symbol: String, _ action: Selector) -> NSButton {
            let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? NSImage()
            let b = EaselPaletteButton(image: glyph, target: self, action: action)
            b.toolTip = label; b.setAccessibilityLabel(label)
            b.widthAnchor.constraint(equalToConstant: chromeSize).isActive = true
            b.heightAnchor.constraint(equalToConstant: chromeSize).isActive = true
            chrome.addArrangedSubview(b); return b
        }
        webpageButton = palette.button(for: .webpage)
        webpageButton?.isEnabled = pageObjects != nil
        let timer = makeTimerButton()
        chrome.addArrangedSubview(timer)
        undoButton = chromeButton("Undo Easel change", "arrow.uturn.backward", #selector(undoChange))
        redoButton = chromeButton("Redo Easel change", "arrow.uturn.forward", #selector(redoChange))
        let options = chromeButton("Easel Options", "ellipsis", #selector(showPageMenu(_:)))
        options.setAccessibilityRole(.menuButton)
        root.addSubview(palette)
        root.addSubview(chrome)
        root.addSubview(recenter)
        var lastChromeSize = NSSize(width: -1, height: -1)
        timer.onResize = { [weak root] in lastChromeSize = NSSize(width: -1, height: -1); root?.needsLayout = true }
        root.onLayout = { [weak self, weak root, weak palette, weak chrome, weak timer] in
            guard let self, let root, let palette, let chrome else { return }
            let width = root.bounds.width, height = root.bounds.height
            let strip = min(width - 24, palette.preferredWidth)
            palette.frame = NSRect(x: ((width - strip) / 2).rounded(), y: 62, width: strip, height: EaselAppearance.toolbarHeight)
            let size = root.bounds.size
            guard size != lastChromeSize else { return }
            lastChromeSize = size
            let chromeWidth: CGFloat = 3 * chromeSize + 3 * 2 + (timer?.intrinsicContentSize.width ?? chromeSize)
            self.titleField.frame = NSRect(x: 24, y: 10, width: max(80, width - chromeWidth - 52), height: 32)
            chrome.frame = NSRect(x: max(24, width - chromeWidth - 14), y: 12, width: chromeWidth, height: chromeSize)
            self.status.frame = NSRect(x: 26, y: 40, width: max(100, width - 52), height: 18)
            let canvasTop = palette.frame.maxY + 8
            self.scroll.frame = NSRect(x: 0, y: canvasTop, width: width, height: max(80, height - canvasTop))
            self.canvas.resizeCanvas(viewport: self.scroll.contentSize)
            self.canvas.fitOnOpenIfNeeded()
            let chip = self.recenter.intrinsicContentSize
            self.recenter.frame = NSRect(x: ((width - chip.width) / 2).rounded(), y: max(canvasTop, height - chip.height - 20),
                                         width: chip.width, height: chip.height)
            self.viewportChanged()
        }
        canvas.onKeyboardStructureChange = { [weak self] in self?.onKeyboardStructureChange?() }
        canvas.onError = { [weak self] error in self?.show(error) }
        canvas.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
        canvas.onExportImage = { [weak self] in self?.exportImage() }
        canvas.onCopiedImage = { [weak self] in self?.showExportToast(.copiedImage) }
        canvas.onKeyEquivalent = { [weak self] event in self?.performBoardKeyEquivalent(event) ?? false }
        subscription = session.$document.receive(on: DispatchQueue.main).sink { [weak self] doc in
            guard let self else { return }
            if self.titleField.currentEditor() == nil { self.titleField.stringValue = doc.title }
            self.onTitleChange?(doc.title)
            self.undoButton.isEnabled = self.canvas.canUndo; self.redoButton.isEnabled = self.canvas.canRedo
            self.status.stringValue = "Saved on this Mac · \(doc.items.count) object\(doc.items.count == 1 ? "" : "s")"
            self.viewportChanged()
        }
    }
    @objc private func viewportChanged() {
        guard isViewLoaded else { return }
        palette?.setZoom(percent: EaselZoom.percent(Double(scroll.magnification)))
        let away = canvas.contentIsOutOfView
        guard away != recenterShown else { return }
        recenterShown = away
        if away { recenter.isHidden = false }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            recenter.animator().alphaValue = away ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.recenterShown else { return }
                self.recenter.isHidden = true
            }
        })
    }
    private func focusCanvas() { canvas.window?.makeFirstResponder(canvas) }
    private func showQuickActions() {
        guard let palette, !session.isClosed, view.window?.attachedSheet == nil else { return }
        palette.closeMenu(animated: false)
        let strip = view.convert(palette.bounds, from: palette)
        quickActions.toggle(in: view, anchor: NSRect(x: strip.midX - 1, y: strip.minY, width: 2, height: strip.height),
                            actions: quickActionList()) { [weak self] in
            guard let window = self?.view.window, window.firstResponder == nil || window.firstResponder === window else { return }
            self?.focusCanvas()
        }
    }
    private func quickActionList() -> [EaselQuickActions.Action] {
        var actions: [EaselQuickActions.Action] = []
        func tool(_ tool: EaselTool, _ keywords: [String], section: String) {
            guard tool.isAvailable else { return }
            actions.append(.init(id: tool.rawValue, title: tool.title, icon: EaselToolPalette.icon(for: tool), shortcut: tool.key?.label,
                                 keywords: keywords, section: section) { [weak self] in
                self?.canvas.activateTool(tool); self?.focusCanvas()
            })
        }
        tool(.sticky, ["note", "card", "idea"], section: "Objects")
        for shape in EaselToolPalette.shapeTools {
            let shapeTool: EaselTool = shape == .ellipse ? .ellipse : .rectangle
            actions.append(.init(id: "shape-" + shape.rawValue,
                                 title: shape == .ellipse ? shapeTool.title : EaselToolPalette.shapeTitle(shape),
                                 icon: EaselToolPalette.icon(for: shape),
                                 shortcut: shape == .ellipse || shape == .rectangle ? shapeTool.key?.label : nil,
                                 keywords: ["shape", shape == .ellipse ? "circle oval" : shape == .rectangle ? "square box" : ""],
                                 section: "Objects") { [weak self] in
                self?.canvas.armShape(shape); self?.focusCanvas()
            })
        }
        for connector in EaselToolPalette.connectorTools { tool(connector, ["arrow", "line", "connector", "link"], section: "Objects") }
        tool(.text, ["type", "words", "label", "title"], section: "Objects")
        tool(.section, ["frame", "area", "group", "region"], section: "Objects")
        tool(.table, ["grid", "rows", "columns", "cells"], section: "Objects")
        for drawing in EaselToolPalette.drawTools { tool(drawing, ["draw", "pen", "pencil", "doodle"], section: "Tools") }
        tool(.stamp, ["emoji", "sticker", "vote", "react"], section: "Tools")
        tool(.select, ["move", "pointer", "cursor", "arrow"], section: "Tools")
        tool(.hand, ["pan", "scroll", "move", "grab"], section: "Tools")
        var inserts: [(EaselToolPalette.Insert, [String])] = [(.image, ["picture", "photo", "file"]), (.link, ["url", "bookmark", "address"]),
                                                              (.webpage, ["site", "browser", "page", "web"])]
        if canvas.acceptsMermaid { inserts.append((.mermaid, ["flowchart", "diagram", "chart", "er"])) }
        for (insert, keywords) in inserts {
            actions.append(.init(id: "insert-" + insert.rawValue, title: EaselToolPalette.title(for: insert),
                                 icon: EaselToolPalette.icon(for: insert), shortcut: nil, keywords: keywords, section: "Inserts",
                                 isEnabled: insert != .webpage || pageObjects != nil) { [weak self] in
                guard let self, let control = self.palette?.button(for: insert) else { return }
                self.insert(insert, from: control)
            })
        }
        tool(.codeBlock, ["code", "snippet", "monospace", "program"], section: "Inserts")
        let zoomSymbols: [EaselZoomCommand: String] = [.zoomIn: "plus.magnifyingglass", .zoomOut: "minus.magnifyingglass",
                                                       .fit: "viewfinder", .selection: "scope", .actualSize: "1.magnifyingglass"]
        for command in [EaselZoomCommand.zoomIn, .zoomOut, .fit, .selection, .actualSize] {
            actions.append(.init(id: "zoom-" + command.rawValue, title: command.title, icon: .symbol(zoomSymbols[command] ?? "magnifyingglass"),
                                 shortcut: command.shortcut, keywords: ["zoom", "view", "scale"], section: "View",
                                 isEnabled: command != .selection || canvas.canZoomToSelection) { [weak self] in
                self?.canvas.zoom(command); self?.focusCanvas()
            })
        }
        return actions
    }
    private func insert(_ insert: EaselToolPalette.Insert, from control: NSButton) {
        switch insert {
        case .image: addImage()
        case .link: addLink(control)
        case .webpage: addWebpage()
        case .mermaid: _ = canvas.showMermaidSheet()
        case .templates: break
        }
    }
    private func dragTool(_ tool: EaselTool, to point: NSPoint?, ended: Bool) {
        guard ended else { canvas.previewPlacement(tool, atWindowPoint: point); return }
        canvas.previewPlacement(nil, atWindowPoint: nil)
        guard let point, scroll.bounds.contains(scroll.convert(point, from: nil)) else { return }
        if canvas.placeTool(tool, atWindowPoint: point) { focusCanvas() }
    }
    func controlTextDidChange(_ notification: Notification) {
        let value = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do { try session.perform("Rename Easel") { $0.title = value } }
        catch { titleField.stringValue = session.document.title; titleField.currentEditor()?.string = session.document.title; show(error) }
    }
    func controlTextDidEndEditing(_ notification: Notification) { titleField.stringValue = session.document.title }
    private func show(_ error: Error) { status.stringValue = error.localizedDescription; NSSound.beep() }
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
    private func addImage() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image] + EaselCanvasView.movieTypes; panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let self else { return }
            for url in panel.urls {
                do { try self.canvas.importImageFile(url) }
                catch { self.show(error) }
            }
        }
    }
    private func addWebpage() {
        guard webpageOwnerValid?() == true, view.window?.attachedSheet == nil,
              !view.isHiddenOrHasHiddenAncestor else { return }
        webpageInput?.cancel(); canvas.cancelOperation(nil)
        let documentID = session.document.id
        let input = EaselWebInput(submitTitle: "Add Webpage", validOwner: { [weak self] in
            guard let self else { return false }
            return !self.session.isClosed && self.session.document.id == documentID && self.webpageOwnerValid?() == true
                && !self.view.isHiddenOrHasHiddenAncestor
        }, submit: { [weak self] url, _ in
            self?.canvas.insertLink(url.absoluteString, browser: true) == true
        })
        webpageInput = input
        input.onClose = { [weak self, weak input] in if self?.webpageInput === input { self?.webpageInput = nil } }
        guard let webpageButton, input.show(from: webpageButton) else { input.cancel(restoreFocus: false); return }
    }
    private func addLink(_ sender: NSButton) {
        guard !session.isClosed, let window = view.window, window.attachedSheet == nil else { return }
        webpageInput?.cancel(); canvas.cancelOperation(nil)
        let documentID = session.document.id
        let input = EaselWebInput(submitTitle: "Add Link", allowsSearch: false, validOwner: { [weak self, weak window] in
            guard let self, let window else { return false }
            return !self.session.isClosed && self.session.document.id == documentID && self.view.window === window
                && !self.view.isHiddenOrHasHiddenAncestor
        }, submit: { [weak self] url, _ in
            guard let self, !self.session.isClosed else { return false }
            return self.canvas.insertLink(url.absoluteString)
        })
        webpageInput = input
        input.onClose = { [weak self, weak input] in if self?.webpageInput === input { self?.webpageInput = nil } }
        if !input.show(from: sender) { input.cancel(restoreFocus: false) }
    }
}
