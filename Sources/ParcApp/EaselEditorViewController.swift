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
    private var webpageButton: NSButton!
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

        let tools = NSStackView()
        tools.orientation = .horizontal; tools.spacing = 2
        tools.setClippingResistancePriority(.init(999), for: .horizontal)
        tools.setClippingResistancePriority(.init(999), for: .vertical)
        let toolInset = EaselAppearance.toolbarInset
        tools.edgeInsets = NSEdgeInsets(top: toolInset, left: toolInset, bottom: toolInset, right: toolInset)
        let toolSurface = EaselToolbarPill(frame: .zero)
        let toolScroll = NSScrollView()
        EaselAppearance.configureToolbarScroll(toolScroll)
        toolScroll.documentView = tools; toolSurface.addSubview(toolScroll)
        let buttonSize = EaselAppearance.toolbarButton
        func tool(_ label: String, _ symbol: String?, _ action: Selector, tag: Int = 0, title: String? = nil) -> EaselPaletteButton {
            let b: EaselPaletteButton
            if let symbol {
                let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                    .withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? NSImage()
                b = EaselPaletteButton(image: glyph, target: self, action: action)
            } else {
                b = EaselPaletteButton(title: title ?? "", target: self, action: action)
                b.font = NoteTheme.nunitoExtraBold(16)
                b.imagePosition = .noImage
            }
            b.usesToolbarInk = true; b.toolTip = label; b.setAccessibilityLabel(label); b.tag = tag
            b.widthAnchor.constraint(equalToConstant: buttonSize).isActive = true
            b.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true
            tools.addArrangedSubview(b); return b
        }
        let select = tool("Select objects", "cursorarrow", #selector(selectTool))
        select.setButtonType(.pushOnPushOff); select.state = .on
        _ = tool("Add image", "photo", #selector(addImage))
        _ = tool("Add text", nil, #selector(addText), title: "A")
        _ = tool("Add circle", "circle", #selector(addShape), tag: 1)
        _ = tool("Add rectangle", "square", #selector(addShape), tag: 0)
        _ = tool("Add arrow", "arrow.up.right", #selector(addShape), tag: 2)
        let draw = tool("Draw", "scribble", #selector(drawTool))
        draw.setButtonType(.pushOnPushOff)
        canvas.onDrawingStateChange = { [weak select, weak draw] drawing in
            select?.state = drawing ? .off : .on; draw?.state = drawing ? .on : .off
        }
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
        _ = chromeButton("Add link", "link", #selector(addLink(_:)))
        webpageButton = chromeButton("Add webpage", "globe", #selector(addWebpage))
        webpageButton.isEnabled = pageObjects != nil
        undoButton = chromeButton("Undo Easel change", "arrow.uturn.backward", #selector(undoChange))
        redoButton = chromeButton("Redo Easel change", "arrow.uturn.forward", #selector(redoChange))
        let options = chromeButton("Easel Options", "ellipsis", #selector(showPageMenu(_:)))
        options.setAccessibilityRole(.menuButton)
        root.addSubview(toolSurface)
        root.addSubview(chrome)
        let toolWidth: CGFloat = 2 * toolInset + 7 * buttonSize + 6 * tools.spacing
        var lastChromeSize = NSSize(width: -1, height: -1)
        root.onLayout = { [weak self, weak root, weak tools, weak toolSurface, weak toolScroll, weak chrome] in
            guard let self, let root, let tools, let toolSurface, let toolScroll, let chrome else { return }
            let width = root.bounds.width, height = root.bounds.height
            let size = root.bounds.size
            guard size != lastChromeSize else { return }
            lastChromeSize = size
            let chromeWidth: CGFloat = 5 * chromeSize + 4 * 2
            self.titleField.frame = NSRect(x: 24, y: 10, width: max(80, width - chromeWidth - 52), height: 32)
            chrome.frame = NSRect(x: max(24, width - chromeWidth - 14), y: 12, width: chromeWidth, height: chromeSize)
            self.status.frame = NSRect(x: 26, y: 40, width: max(100, width - 52), height: 18)
            let strip = min(width - 24, toolWidth)
            toolSurface.frame = NSRect(x: (width - strip) / 2, y: 62, width: strip, height: EaselAppearance.toolbarHeight)
            toolScroll.frame = toolSurface.bounds
            tools.frame = NSRect(x: 0, y: 0, width: toolWidth, height: EaselAppearance.toolbarHeight)
            let canvasTop = toolSurface.frame.maxY + 8
            self.scroll.frame = NSRect(x: 0, y: canvasTop, width: width, height: max(80, height - canvasTop))
            self.canvas.resizeCanvas(viewport: self.scroll.contentSize)
        }
        canvas.onKeyboardStructureChange = { [weak self] in self?.onKeyboardStructureChange?() }
        canvas.onError = { [weak self] error in self?.show(error) }
        canvas.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
        canvas.onExportImage = { [weak self] in self?.exportImage() }
        canvas.onKeyEquivalent = { [weak self] event in self?.performBoardKeyEquivalent(event) ?? false }
        subscription = session.$document.receive(on: DispatchQueue.main).sink { [weak self] doc in
            guard let self else { return }
            if self.titleField.currentEditor() == nil { self.titleField.stringValue = doc.title }
            self.onTitleChange?(doc.title)
            self.undoButton.isEnabled = self.canvas.canUndo; self.redoButton.isEnabled = self.canvas.canRedo
            self.status.stringValue = "Saved on this Mac · \(doc.items.count) object\(doc.items.count == 1 ? "" : "s")"
        }
    }
    func controlTextDidChange(_ notification: Notification) {
        let value = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do { try session.perform("Rename Easel") { $0.title = value } }
        catch { titleField.stringValue = session.document.title; titleField.currentEditor()?.string = session.document.title; show(error) }
    }
    func controlTextDidEndEditing(_ notification: Notification) { titleField.stringValue = session.document.title }
    private func show(_ error: Error) { status.stringValue = error.localizedDescription; NSSound.beep() }
    @objc private func selectTool() { canvas.drawing = false; canvas.window?.makeFirstResponder(canvas) }
    @objc private func drawTool() { canvas.drawing = true; canvas.window?.makeFirstResponder(canvas) }
    @objc private func addText() { canvas.insert(kind: .text, text: "", edit: true) }
    @objc private func addShape(_ sender: NSButton) { canvas.insert(kind: [.rectangle, .circle, .arrow][sender.tag]) }
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
    @objc private func addImage() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let self else { return }
            for url in panel.urls {
                do { try self.canvas.importImageFile(url) }
                catch { self.show(error) }
            }
        }
    }
    @objc private func addWebpage() {
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
        if !input.show(from: webpageButton) { input.cancel(restoreFocus: false) }
    }
    @objc private func addLink(_ sender: NSButton) {
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
