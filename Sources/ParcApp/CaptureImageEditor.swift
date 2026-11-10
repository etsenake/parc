import AppKit
import Combine

/// An accepted edit remains a model snapshot, so reopening the editor preserves
/// object identity and never flattens its own previous output into the source.
struct CaptureImageEditSnapshot {
    let document: EaselDocument
    let assets: [String: Data]
}

@MainActor
final class CaptureImageEditor: NSObject {
    private let session: EaselSession
    private let canvas: EaselCanvasView
    private let pixelSize: NSSize
    private let backingScale: CGFloat
    private let sourceColorSpace: CGColorSpace?
    private let initial: EaselDocument
    private let valid: () -> Bool
    private let apply: (CGImage, CaptureImageEditSnapshot) throws -> Void
    private let completion: () -> Void
    private weak var parent: NSWindow?
    private let panel = CaptureImageEditorPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
    private let root = LayoutView()
    private let scroll = NSScrollView()
    private let status = NSTextField(labelWithString: "")
    private let ink = PointingHandColorWell()
    private var subscription: AnyCancellable?
    private var importPanel: NSOpenPanel?
    private var finished = false

    init(png: Data, pixels: CGImage, backingScale: CGFloat, snapshot: CaptureImageEditSnapshot?, parent: NSWindow,
         valid: @escaping () -> Bool,
         apply: @escaping (CGImage, CaptureImageEditSnapshot) throws -> Void,
         completion: @escaping () -> Void) throws {
        self.parent = parent; self.valid = valid; self.apply = apply; self.completion = completion
        self.backingScale = backingScale; sourceColorSpace = pixels.colorSpace
        pixelSize = NSSize(width: pixels.width, height: pixels.height)
        let size = NSSize(width: CGFloat(pixels.width) / backingScale, height: CGFloat(pixels.height) / backingScale)
        if let snapshot {
            session = try EaselSession(inMemory: snapshot.document, assets: snapshot.assets)
        } else {
            let id = UUID().uuidString.lowercased() + ".png", date = Date()
            let image = EaselItem(kind: .image, frame: EaselRect(x: 0, y: 0, width: size.width, height: size.height), assetID: id)
            let document = EaselDocument(id: UUID(), title: "Capture", createdAt: date, modifiedAt: date, items: [image])
            session = try EaselSession(inMemory: document, assets: [id: png])
        }
        initial = session.document
        canvas = EaselCanvasView(session: session); canvas.fixedCanvasSize = size
        super.init()
        panel.isReleasedWhenClosed = false; panel.title = "Edit Capture"
        panel.contentView = root; panel.onCancel = { [weak self] in self?.close() }; panel.editor = self
        root.wantsLayer = true; root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.01; scroll.maxMagnification = 4
        scroll.documentView = canvas; root.addSubview(scroll)
        canvas.resizeCanvas(viewport: size)
        canvas.setAccessibilityLabel("Capture editing canvas")
        canvas.onImageEditingCancel = { [weak self] in self?.close() }
        canvas.onExportImage = { [weak self] in self?.exportImage() }
        canvas.onError = { [weak self] in self?.status.stringValue = $0.localizedDescription }
        let tools = NSStackView(); tools.spacing = 4
        var controls: [NSView] = []
        func tool(_ title: String, _ symbol: String, action: @escaping () -> Void) -> ActionButton {
            let button = ActionButton("", symbol: symbol); button.setAccessibilityLabel(title); button.toolTip = title
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            button.actionBlock = action; tools.addArrangedSubview(button); controls.append(button); return button
        }
        _ = tool("Select and move objects", "cursorarrow") { [weak self] in self?.canvas.drawing = false; self?.panel.makeFirstResponder(self?.canvas) }
        _ = tool("Add image", "photo") { [weak self] in self?.importImage() }
        _ = tool("Add text", "textformat") { [weak self] in self?.canvas.insert(kind: .text, edit: true) }
        _ = tool("Add circle", "circle") { [weak self] in self?.canvas.insert(kind: .circle) }
        _ = tool("Add rectangle", "rectangle") { [weak self] in self?.canvas.insert(kind: .rectangle) }
        _ = tool("Add arrow", "arrow.up.right") { [weak self] in self?.canvas.insert(kind: .arrow) }
        _ = tool("Draw", "pencil.tip") { [weak self] in self?.canvas.drawing = true; self?.panel.makeFirstResponder(self?.canvas) }
        ink.color = NSColor(parcHex: "252525"); ink.target = self; ink.action = #selector(changeInk(_:))
        ink.setAccessibilityLabel("Annotation color"); ink.widthAnchor.constraint(equalToConstant: 36).isActive = true
        tools.addArrangedSubview(ink); controls.append(ink)
        let undo = tool("Undo edit", "arrow.uturn.backward") { [weak self] in self?.canvas.undo(nil) }
        let redo = tool("Redo edit", "arrow.uturn.forward") { [weak self] in self?.canvas.redo(nil) }
        let cancel = ActionButton("Cancel"); cancel.actionBlock = { [weak self] in self?.close() }
        let done = ActionButton("Apply Changes"); done.actionBlock = { [weak self] in self?.accept() }
        done.keyEquivalent = "\r"; done.keyEquivalentModifierMask = [.command]
        for view in [tools, status, cancel, done] { root.addSubview(view) }
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.stringValue = "Edits apply to the original capture; Crop and Portrait framing stay reversible."
        controls += [cancel, done, canvas]
        let toolControls = controls.filter { $0 !== canvas }
        canvas.onKeyboardStructureChange = { [weak canvas] in
            guard let canvas else { return }
            let chain = toolControls + [canvas] + canvas.objectKeyViews
            for (a, b) in zip(chain, chain.dropFirst() + [chain[0]]) { a.nextKeyView = b }
        }
        canvas.onKeyboardStructureChange?()
        root.onLayout = { [weak self, weak tools, weak cancel, weak done] in
            guard let self, let tools, let cancel, let done else { return }
            let bounds = self.root.bounds
            self.scroll.frame = NSRect(x: 16, y: 48, width: bounds.width - 32, height: bounds.height - 112)
            tools.frame = NSRect(x: 16, y: 8, width: bounds.width - 32, height: 32)
            self.status.frame = NSRect(x: 16, y: bounds.height - 58, width: bounds.width - 32, height: 20)
            cancel.frame = NSRect(x: bounds.width - 240, y: bounds.height - 34, width: 90, height: 28)
            done.frame = NSRect(x: bounds.width - 144, y: bounds.height - 34, width: 128, height: 28)
        }
        subscription = session.$canUndo.combineLatest(session.$canRedo).sink { [weak undo, weak redo] canUndo, canRedo in
            undo?.isEnabled = canUndo; redo?.isEnabled = canRedo
        }
        undo.isEnabled = false; redo.isEnabled = false
    }

    func show() -> Bool {
        guard !finished, valid(), let parent, parent.attachedSheet == nil else { return false }
        panel.setContentSize(NSSize(width: min(1000, max(420, parent.frame.width - 48)), height: min(760, max(300, parent.frame.height - 64))))
        root.layoutSubtreeIfNeeded()
        let fit = min(scroll.contentSize.width / canvas.bounds.width, scroll.contentSize.height / canvas.bounds.height, 1)
        scroll.magnification = max(scroll.minMagnification, fit)
        parent.beginSheet(panel) { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
        panel.makeFirstResponder(canvas)
        return true
    }

    func close() {
        guard !finished else { return }; finished = true
        if let importPanel, panel.attachedSheet === importPanel { panel.endSheet(importPanel, returnCode: .cancel) }
        importPanel = nil; ink.deactivate(); canvas.finishImageEditing(); subscription = nil
        if parent?.attachedSheet === panel { parent?.endSheet(panel) }
        panel.orderOut(nil); completion()
    }

    private func accept() {
        guard !finished, importPanel == nil, valid() else { return }
        canvas.finishImageEditing()
        // A no-op Apply preserves the exact original PNG bytes.
        guard session.document.items != initial.items else { close(); return }
        do {
            let image = try canvas.renderImage(pixelSize: pixelSize, backingScale: backingScale, colorSpace: sourceColorSpace)
            try apply(image, CaptureImageEditSnapshot(document: session.document, assets: session.inMemoryAssets))
            close()
        } catch { status.stringValue = error.localizedDescription }
    }

    fileprivate var canExportImage: Bool { !finished && valid() && panel.attachedSheet == nil }
    ///
    /// export covers the whole image; its untitled document suggests Untitled Easel.
    fileprivate func exportImage() {
        guard canExportImage else { return }
        EaselImageExport.run(canvas: canvas, title: nil, in: panel) { [weak self] in self?.canExportImage == true }
    }

    @objc private func changeInk(_ sender: NSColorWell) { guard !finished, valid() else { return }; canvas.setInsertionColor(sender.color) }
    private func importImage() {
        guard !finished, valid(), panel.attachedSheet == nil else { return }
        let chooser = NSOpenPanel(); chooser.allowedContentTypes = [.image]; chooser.allowsMultipleSelection = true
        importPanel = chooser
        chooser.beginSheetModal(for: panel) { [weak self, weak chooser] response in
            MainActor.assumeIsolated {
                guard let self, !self.finished, self.importPanel === chooser else { return }
                self.importPanel = nil
                guard response == .OK, self.valid(), let chooser else { return }
                do { for url in chooser.urls { try self.canvas.importImageFile(url) } }
                catch { self.status.stringValue = error.localizedDescription }
                self.panel.makeFirstResponder(self.canvas)
            }
        }
    }
}

@MainActor
private final class CaptureImageEditorPanel: NSPanel, EaselImageExporting {
    var onCancel: (() -> Void)?
    weak var editor: CaptureImageEditor?
    var canExportEaselImage: Bool { editor?.canExportImage == true }
    func exportEaselImage() { editor?.exportImage() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func performClose(_ sender: Any?) { onCancel?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers == "w" { onCancel?(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w") { onCancel?(); return }
        super.keyDown(with: event)
    }
}
