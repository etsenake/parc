import AppKit
import Combine
import ImageIO

struct EaselPageSnapshot {
    let image: NSImage
    let pageFrame: NSRect
    let visibleFrame: NSRect
}

@MainActor
protocol EaselBrowserObjectHosting: AnyObject {
    func surface(for item: EaselItem) -> NSView?
    func synchronize(items: [EaselItem], selection: Set<UUID>, interacting: Bool)
    func focusPage(for id: UUID) -> Bool
    func accessibilitySurface(for id: UUID) -> NSView?
    func prepareReplacement(_ next: EaselDocument, valid: @escaping () -> Bool,
                            completion: @escaping (Bool) -> Void)
    func exportSnapshots(within deadline: TimeInterval, _ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void)
}

@MainActor
extension EaselBrowserObjectHosting {
    func focusPage(for id: UUID) -> Bool { false }
    func accessibilitySurface(for id: UUID) -> NSView? { nil }
    func exportSnapshots(within deadline: TimeInterval, _ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void) { completion([:]) }
}

@MainActor
final class EaselCanvasView: LocalContentDropView, NSTextViewDelegate, NSMenuItemValidation {
    private final class MenuTarget {
        weak var window: NSWindow?
        let command: EaselObjectCommand?
        let generation: UInt64
        init(window: NSWindow?, command: EaselObjectCommand?, generation: UInt64) {
            self.window = window; self.command = command; self.generation = generation
        }
    }
    private let session: EaselSession
    private var motionInteractionActive = false
    private lazy var motion: EaselCanvasMotion = EaselCanvasMotion(owner: self,
        validOwner: { [weak self] in self?.canPresentMotion == true },
        changed: { [weak self] in
            guard let self else { return }
            if self.motion.isInteracting { self.cancelPointerInteraction() }
            if self.motionInteractionActive != self.motion.isInteracting {
                self.motionInteractionActive = self.motion.isInteracting
                self.keyboardStructureChanged()
                NSAccessibility.post(element: self, notification: .layoutChanged)
            }
            self.resizeCanvas(viewport: self.enclosingScrollView?.contentSize ?? .zero)
            self.refreshTextControls(); self.invalidateIncrementalDisplay(layout: true)
            self.window?.invalidateCursorRects(for: self)
        },
        settleAnnotations: { [weak self] in
            guard let self else { return }
            EaselCanvasMotion.settle(self.textStyleBar)
        })
    weak var pageObjects: EaselBrowserObjectHosting? { didSet { needsLayout = true } }
    private var artwork: [UUID: NSView] = [:]
    private var accessibleObjects: [UUID: EaselAccessibleObject] = [:]
    var onKeyboardStructureChange: (() -> Void)?
    private var keyboardStructurePending = false
    private func keyboardStructureChanged() {
        guard !keyboardStructurePending else { return }
        keyboardStructurePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.keyboardStructurePending = false
            self.onKeyboardStructureChange?()
        }
    }
    var objectKeyViews: [NSView] {
        synchronizeAccessibleObjects()
        return items.compactMap { accessibleObjects[$0.id] }
    }
    private lazy var decoration = EaselCanvasDecoration(canvas: self)
    private var trackedItems: [UUID: EaselItem] = [:]
    private var trackedSelection = Set<UUID>()
    private var trackedHover: UUID?
    private var trackedMarquee: NSRect?
    private var trackedGuideBounds = NSRect.null
    private var trackedCanvasScale: Double?
    private var trackedHidesAnnotations = false
    private var textLayouts: [UUID: CachedTextLayout] = [:]
    private(set) var presentationNoOpSkipCount = 0
    private(set) var presentationDirtyCount = 0

    private var menuGeneration: UInt64 = 0
    private var subscription: AnyCancellable?
    private var selection = Set<UUID>() {
        didSet {
            if selection != oldValue {
                menuGeneration &+= 1
                NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
                keyboardStructureChanged()
                synchronizePageSelection()
                invalidateIncrementalDisplay(layout: true)
            }
            refreshTextControls(); updateAccessibilitySummary(); window?.invalidateCursorRects(for: self)
        }
    }
    private var draft: [EaselItem]?
    private var start: NSPoint?
    private var original: [EaselItem] = []
    private var resizeHandle: EaselResizeHandle?
    private var arrowEndpoint: EaselArrowEndpoint?
    private var resizing: Bool { resizeHandle != nil || arrowEndpoint != nil }
    private var lastGeometryPoint: NSPoint?
    private var lastDragLocation: NSPoint?
    private var dragDistance: CGFloat = 0
    private var geometryEdit: EaselGeometryEdit?
    private var selectionBeforeGesture = Set<UUID>()
    private var marqueeRect: NSRect?
    private var marqueeEnd: NSPoint?
    private var tentativeSelection: Set<UUID>?
    private var hoveredObjectID: UUID?
    private var appearanceTracking: NSTrackingArea?
    private var stroke: [NSPoint] = []
    private var guides: EaselAlignmentGuides?
    private var alignmentGuidesEnabled = true
    private var lastDragTimestamp: TimeInterval?
    private var dragVelocity = EaselPoint(x: 0, y: 0)
    private var editor: EaselStyledTextView?
    private var textUndoGroup: UUID?
    private var synchronizingEditor = false
    private var finishingEditor = false
    private let textStyleBar = EaselTextStyleBar(frame: .zero)
    private var textPaletteSelection: Set<UUID> = []
    private let liveCaptureButton = PointingHandButton(title: "Make Live", target: nil, action: nil)
    private var liveCaptureEducation: ParcDialog?
    private static let liveCaptureEducationKey = "easel.liveCaptureEducationSeen"
    private var editingID: UUID?
    private var editingTextSnapshot: (text: String, rich: EaselRichText?)?
    private var images: [String: NSImage] = [:]
    var onDrawingStateChange: ((Bool) -> Void)?
    var drawing = false {
        didSet {
            if drawing != oldValue { cancelPointerInteraction(); keyboardStructureChanged() }
            onDrawingStateChange?(drawing)
            window?.invalidateCursorRects(for: self)
        }
    }
    var fixedCanvasSize: NSSize?
    private var insertionColor = "#252525"
    var onImageEditingCancel: (() -> Void)?
    func setInsertionColor(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        let hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                         Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        insertionColor = hex
        let ids = selection
        if !ids.isEmpty {
            cancelPointerInteraction(); guard finishEditing() else { return }
            _ = commit("Change color") { document in
                for i in document.items.indices where ids.contains(document.items[i].id) && [.text, .rectangle, .circle, .arrow, .freehand].contains(document.items[i].kind) {
                    document.items[i].color = hex
                    if var rich = document.items[i].richText {
                        for j in rich.runs.indices {
                            rich.runs[j].attributes.ink = hex + "FF"
                            rich.runs[j].attributes.semanticInk = nil
                        }
                        document.items[i].richText = rich
                    }
                }
            }
        }
    }
    @discardableResult
    func finishImageEditing() -> Bool { cancelPointerInteraction(); return finishEditing() }
    var canFinishEditingForTransfer: Bool {
        !session.isDeleted && !session.isClosed && !finishingEditor && editor?.hasMarkedText() != true &&
        start == nil && draft == nil && geometryEdit == nil && marqueeRect == nil
    }
    func finishEditingForTransfer() -> Bool {
        guard canFinishEditingForTransfer else { return false }
        return finishEditing()
    }
    func renderImage(pixelSize: NSSize, backingScale: CGFloat, colorSpace: CGColorSpace? = nil) throws -> CGImage {
        guard finishImageEditing() else { throw EaselStoreError.invalidDocument("finish the current text edit") }
        guard pixelSize.width.isFinite, pixelSize.height.isFinite, pixelSize.width > 0, pixelSize.height > 0,
              pixelSize.width <= 32768, pixelSize.height <= 32768 else { throw EaselStoreError.tooLarge }
        let width = Int(pixelSize.width), height = Int(pixelSize.height)
        let outputSpace = colorSpace?.model == .rgb ? colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard width > 0, height > 0, width <= 32768, height <= 32768,
              width * height <= 128_000_000, backingScale.isFinite, backingScale > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: outputSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EaselStoreError.tooLarge }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: backingScale, y: -backingScale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for item in items { drawObject(item) }
        NSGraphicsContext.restoreGraphicsState()
        guard let output = context.makeImage() else { throw EaselStoreError.invalidImage }
        return output
    }
    func exportImage(backingScale: CGFloat, pages: [UUID: EaselPageSnapshot] = [:]) -> CGImage? {
        let content = session.document.items.sorted { $0.zIndex < $1.zIndex }
        let width = bounds.width
        let size = fixedCanvasSize ?? NSSize(width: width, height: max(width, content.map { $0.frame.y + $0.frame.height }.max() ?? 0) + 60)
        let pixels = NSSize(width: (size.width * backingScale).rounded(), height: (size.height * backingScale).rounded())
        guard backingScale > 0, pixels.width >= 1, pixels.height >= 1, pixels.width < 1e9, pixels.height < 1e9 else { return nil }
        for id in content.compactMap(\.assetID) { _ = image(id) }
        let backing: NSColor = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
        let appearance = effectiveAppearance
        return EaselExportStrips.image(width: Int(pixels.width), height: Int(pixels.height)) { [self] context, firstRow, rows in
            let strip = NSRect(x: 0, y: CGFloat(firstRow) / backingScale, width: size.width, height: CGFloat(rows) / backingScale)
            context.translateBy(x: 0, y: CGFloat(rows)); context.scaleBy(x: backingScale, y: -backingScale)
            context.translateBy(x: 0, y: -strip.minY)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            appearance.performAsCurrentDrawingAppearance {
                backing.setFill(); strip.fill()
                for item in content where displayBounds(of: item).intersects(strip) {
                    if let page = pages[item.id] { drawLivePage(page, in: rect(item)) } else { drawObject(item, showsEditor: false) }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    private func drawLivePage(_ page: EaselPageSnapshot, in frame: NSRect) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        EaselAppearance.surface.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip(); NSBezierPath(rect: page.visibleFrame.offsetBy(dx: frame.minX, dy: frame.minY)).addClip()
        page.image.draw(in: page.pageFrame.offsetBy(dx: frame.minX, dy: frame.minY), from: .zero,
                        operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
    private var collectingExportPages = false
    func collectExportPages(_ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void) -> Bool {
        guard !collectingExportPages else { return false }
        guard let pageObjects, session.document.items.contains(where: \.ownsEmbeddedPage) else { completion([:]); return true }
        collectingExportPages = true
        pageObjects.exportSnapshots(within: 8) { [weak self] pages in self?.collectingExportPages = false; completion(pages) }
        return true
    }
    var onExportImage: (() -> Void)?
    var onError: ((Error) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var canAcceptExternalSplitDrop: Bool {
        !session.isDeleted && start == nil && geometryEdit == nil && draft == nil &&
        marqueeRect == nil && editor?.hasMarkedText() != true
    }
    var canUndo: Bool { editor?.localUndo.canUndo == true || session.canUndo }
    var canRedo: Bool { editor?.localUndo.canRedo == true || session.canRedo }
    private var items: [EaselItem] {
        let current = session.document
        let displayed: [EaselItem]
        if let geometryEdit, let draft, let preview = geometryEdit.applying(draft, to: current) {
            displayed = preview.items
        } else if drawing, start != nil, let draft { displayed = current.items + draft }
        else { displayed = current.items }
        return displayed.sorted { $0.zIndex < $1.zIndex }
    }
    private var displayedSelection: Set<UUID> { tentativeSelection ?? selection }


    init(session: EaselSession) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 1800))
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Easel canvas")
        registerForDraggedTypes([.URL, EaselStyledText.pasteboardType, EaselStyledText.previousPasteboardType, EaselStyledText.legacyPasteboardType, .rtfd, .rtf, .fileURL, .png, .tiff, .string])
        textStyleBar.isHidden = true; addSubview(textStyleBar)
        textStyleBar.wantsLayer = true
        textStyleBar.onVisibilityChange = { [weak self] hidden in
            guard let self else { return }
            EaselCanvasMotion.setAnnotationHidden(hidden, view: self.textStyleBar,
                animated: self.canPresentMotion && self.motion.allowsAnnotationAnimation &&
                    self.window?.isKeyWindow == true && !self.isHiddenOrHasHiddenAncestor)
        }
        textStyleBar.onLayoutChange = { [weak self] in
            self?.refreshTextControls(); self?.keyboardStructureChanged()
        }
        liveCaptureButton.target = self; liveCaptureButton.action = #selector(toggleLiveCapture)
        liveCaptureButton.bezelStyle = .texturedRounded
        liveCaptureButton.toolTip = "Show this region from a live webpage"
        liveCaptureButton.isHidden = true; addSubview(liveCaptureButton)
        textStyleBar.onFamily = { [weak self] family in self?.changeTextStyle(preservingSize: true) { $0.family = family } }
        textStyleBar.onSize = { [weak self] size in self?.changeTextStyle { $0.size = size } }
        textStyleBar.onResize = { [weak self] delta in self?.changeTextStyle { $0.size = $0.size.shifted(by: delta) } }
        textStyleBar.onFill = { [weak self] fill in self?.setTextFill(fill) }
        textStyleBar.onParagraph = { [weak self] kind in guard let self, !self.session.isClosed else { return }; self.editor?.changeParagraph(kind); self.refreshTextControls() }
        textStyleBar.onEmphasis = { [weak self] emphasis in guard let self, !self.session.isClosed else { return }; self.editor?.toggle(emphasis); self.refreshTextControls() }
        textStyleBar.onLink = { [weak self] anchor in guard let self, !self.session.isClosed else { return }; self.editor?.editLink(relativeTo: anchor) }
        subscription = session.$document.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            let document = self.session.document
            self.hoveredObjectID = nil
            self.selection.formIntersection(document.items.map(\.id))
            if let edit = self.geometryEdit, !edit.isCurrent(in: document) { self.cancelPointerInteraction() }
            if let end = self.marqueeEnd { self.updateMarquee(to: end, flags: NSEvent.modifierFlags) }
            if let id = self.editingID, let item = document.items.first(where: { $0.id == id }) {
                self.updateEditor(item)
            } else if self.editingID != nil { self.finishEditing() }
            self.resizeCanvas(viewport: self.enclosingScrollView?.contentSize ?? .zero)
            self.updateAccessibilitySummary()
            self.refreshTextControls()
            self.window?.invalidateCursorRects(for: self)
            self.invalidateIncrementalDisplay(layout: true)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func setFrameSize(_ newSize: NSSize) {
        if geometryEdit != nil, newSize.width != frame.width { cancelPointerInteraction() }
        super.setFrameSize(newSize)
    }
    func resizeCanvas(viewport: NSSize) {
        if let fixedCanvasSize {
            if frame.size != fixedCanvasSize { setFrameSize(fixedCanvasSize) }
            return
        }
        let viewport = enclosingScrollView?.contentView.bounds.size ?? viewport
        let right = session.document.items.map { $0.frame.x + $0.frame.width + 80 }.max() ?? 0
        let bottom = session.document.items.map { $0.frame.y + $0.frame.height + 180 }.max() ?? 0
        let size = NSSize(width: max(viewport.width, right), height: max(viewport.height, 1400, bottom))
        if size != frame.size { setFrameSize(size) }
    }
    private func updateAccessibilitySummary() {
        let document = session.document
        setAccessibilityValue("\(document.items.count) objects, \(selection.count) selected")
        synchronizeAccessibleObjects()
    }
    private func synchronizeAccessibleObjects() {
        let ids = Set(session.document.items.map(\.id))
        var changed = Set(accessibleObjects.keys) != ids
        for id in Array(accessibleObjects.keys) where !ids.contains(id) {
            let retired = accessibleObjects.removeValue(forKey: id)
            if window?.firstResponder === retired { window?.makeFirstResponder(self) }
            retired?.removeFromSuperview()
        }
        let displayed = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in session.document.items {
            let node = accessibleObjects[item.id] ?? EaselAccessibleObject(canvas: self, id: item.id)
            accessibleObjects[item.id] = node
            let frame = rect(displayed[item.id] ?? item)
            if node.frame != frame { node.frame = frame; changed = true }
            node.updateAccessibilityContent(item)
            if node.superview !== self { addSubview(node) }
        }
        if changed {
            keyboardStructureChanged()
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
    }
    override func accessibilityChildren() -> [Any]? {
        synchronizeAccessibleObjects()
        var result: [Any] = items.compactMap { accessibleObjects[$0.id] }
        if !textStyleBar.isHidden { result.append(textStyleBar) }
        if !liveCaptureButton.isHidden { result.append(liveCaptureButton) }
        result.append(contentsOf: accessibleManipulationControls())
        return result
    }
    override func accessibilitySelectedChildren() -> [Any]? {
        synchronizeAccessibleObjects()
        return items.filter { selection.contains($0.id) }.compactMap { accessibleObjects[$0.id] }
    }
    override func setAccessibilitySelectedChildren(_ children: [Any]?) {
        guard accessibleOwnerAvailable, let children else { return }
        let nodes = children.compactMap { $0 as? EaselAccessibleObject }
        guard nodes.count == children.count, nodes.allSatisfy({ $0.canvas === self && accessibleItem($0.id) != nil }), finishEditing() else { return }
        guard nodes.allSatisfy({ accessibleItem($0.id) != nil }) else { return }
        selection = Set(nodes.map(\.id)); invalidateIncrementalDisplay(layout: true)
    }
    override var accessibilityFocusedUIElement: Any? {
        if let responder = window?.firstResponder as? NSView,
           responder !== self, responder.isDescendant(of: self) { return responder }
        guard window?.firstResponder === self else { return super.accessibilityFocusedUIElement }
        return selection.count == 1 ? selection.first.flatMap { accessibleObjects[$0] } ?? self : self
    }
    fileprivate func accessibleItem(_ id: UUID) -> EaselItem? { session.document.items.first { $0.id == id } }
    fileprivate func accessibleSelected(_ id: UUID) -> Bool { selection.contains(id) }
    fileprivate func accessibleChildren(_ id: UUID) -> [Any] {
        if editingID == id, let editor { editor.setAccessibilityParent(accessibleObjects[id]); return [editor] }
        if selection == [id], let surface = pageObjects?.accessibilitySurface(for: id) {
            surface.setAccessibilityParent(accessibleObjects[id]); return [surface]
        }
        return []
    }
    fileprivate var accessibleOwnerAvailable: Bool {
        !session.isDeleted && !session.isClosed && window != nil && window?.attachedSheet == nil && !isHiddenOrHasHiddenAncestor &&
        start == nil && !drawing && editor?.hasMarkedText() != true
    }
    fileprivate func selectAccessibleObject(_ expected: EaselItem) -> Bool {
        guard accessibleOwnerAvailable, accessibleItem(expected.id) == expected, finishEditing(),
              accessibleItem(expected.id) == expected else { return false }
        selection = [expected.id]; scrollToVisible(rect(expected)); invalidateIncrementalDisplay(layout: true)
        layoutSubtreeIfNeeded()
        return true
    }
    fileprivate func activateAccessibleObject(_ expected: EaselItem) -> Bool {
        guard selectAccessibleObject(expected) else { return false }
        if expected.kind == .text { beginEditing(expected); return editingID == expected.id }
        if pageObjects?.focusPage(for: expected.id) == true { return true }
        return false
    }
    fileprivate func accessibleAction(_ name: String, item: EaselItem, owner: NSWindow?) -> Bool {
        guard let owner, owner === window, selectAccessibleObject(item) else { return false }
        if name == "Activate" { return activateAccessibleObject(item) }
        guard let command = EaselObjectCommand(document: session.document, selection: [item.id]) else { return false }
        let sender = NSMenuItem(); sender.representedObject = MenuTarget(window: owner, command: command, generation: menuGeneration)
        switch name {
        case "Duplicate": return duplicateObjects(sender)
        case "Bring to front": return bringToFront(sender)
        case "Delete": deleteObjects(sender)
        case "Open source":
            guard onOpenURL != nil else { return false }
            openObjectSource(sender)
        default: return false
        }
        return true
    }
    fileprivate func showAccessibleMenu(_ item: EaselItem) -> Bool {
        guard window?.isKeyWindow == true, selectAccessibleObject(item) else { return false }
        let menu = makeObjectMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: rect(item).minX, y: rect(item).maxY), in: self)
        return true
    }
    private func accessibleManipulationControls() -> [NSAccessibilityElement] {
        guard accessibleOwnerAvailable, editor == nil, let owner = window,
              let edit = EaselGeometryEdit(document: session.document, selection: selection) else { return [] }
        func make(_ label: String, frame: EaselRect, handle: EaselResizeHandle? = nil,
                  endpoint: EaselArrowEndpoint? = nil) -> NSAccessibilityElement {
            let node = NSAccessibilityElement()
            node.setAccessibilityRole(.handle); node.setAccessibilityLabel(label); node.setAccessibilityParent(self)
            node.setAccessibilityFrame(owner.convertToScreen(convert(NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height), to: nil)))
            let moves: [(String, Double, Double)] = [("Move left", -1, 0), ("Move right", 1, 0), ("Move up", 0, -1), ("Move down", 0, 1)]
            node.setAccessibilityCustomActions(moves.filter { _, x, y in
                endpoint != nil || handle?.isCorner == true || (x != 0 ? handle?.movesLeft == true || handle?.movesRight == true : handle?.movesTop == true || handle?.movesBottom == true)
            }.map { name, x, y in
                NSAccessibilityCustomAction(name: name) { [weak self, weak owner] in
                    guard let self, let owner, self.window === owner, self.accessibleOwnerAvailable,
                          self.editor == nil, self.selection == edit.ids, edit.isCurrent(in: self.session.document) else { return false }
                    let proposal: [EaselItem]?
                    if let endpoint {
                        guard self.showsArrowAnnotation(endpoint) else { return false }
                        proposal = edit.movingEndpoint(endpoint, x: x, y: y)
                    }
                    else if let handle {
                        guard self.showsFrameAnnotation(handle), let bounds = self.resizeBounds,
                              handle.hitRect(in: bounds, scale: self.canvasScale) != nil else { return false }
                        proposal = edit.preservesAspect(shift: false, command: false)
                            ? edit.resizedPreservingAspect(using: handle, x: x, y: y, centering: [])
                            : edit.resized(using: handle, x: x, y: y, centered: false)
                    }
                    else { return false }
                    guard let proposal, let next = edit.applying(proposal, to: self.session.document) else { return false }
                    let accepted = self.commit(endpoint == nil ? "Resize objects" : "Move arrow endpoint") { $0 = next }
                    if accepted { NSAccessibility.post(element: self, notification: .layoutChanged) }
                    return accepted
                }
            })
            return node
        }
        if let arrow = selectedArrow {
            return EaselArrowEndpoint.allCases.compactMap { endpoint in
                guard showsArrowAnnotation(endpoint) else { return nil }
                return endpoint.hitRect(in: arrow, scale: canvasScale).map { make(endpoint == .start ? "Arrow start" : "Arrow end", frame: $0, endpoint: endpoint) }
            }
        }
        guard let frame = resizeBounds else { return [] }
        let labels = ["Top left", "Top right", "Bottom left", "Bottom right", "Top", "Left", "Bottom", "Right"]
        return EaselResizeHandle.allCases.compactMap { handle in
            guard showsFrameAnnotation(handle) else { return nil }
            return handle.hitRect(in: frame, scale: canvasScale).map { make("Resize " + labels[handle.rawValue], frame: $0, handle: handle) }
        }
    }
    private func rect(_ item: EaselItem) -> NSRect {
        NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
    }
    private func color(_ hex: String) -> NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x252525
        return NSColor(srgbRed: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255,
                       blue: Double(value & 255) / 255, alpha: 1)
    }
    private func image(_ id: String) -> NSImage? {
        if let value = images[id] { return value }
        guard let data = try? session.assetData(id), let value = NSImage(data: data) else { return nil }
        images[id] = value; return value
    }
    private var usesObjectSurfaces: Bool { pageObjects != nil && items.contains { $0.ownsEmbeddedPage } }
    private func displayBounds(of item: EaselItem) -> NSRect {
        let pad = 16 / max(canvasScale, 0.2) + 16
        return rect(item).insetBy(dx: -pad, dy: -pad)
    }
    private func guideDirtyBounds() -> NSRect {
        var dirty = NSRect.null
        let pad = 4 / max(canvasScale, 0.2)
        for line in guides?.lines ?? [] {
            for segment in line.targetSegments + line.anchorSegments {
                let origin = NSPoint(x: min(segment.start.x, segment.end.x), y: min(segment.start.y, segment.end.y))
                let size = NSSize(width: max(1, abs(segment.end.x - segment.start.x)),
                                  height: max(1, abs(segment.end.y - segment.start.y)))
                dirty = dirty.union(NSRect(origin: origin, size: size).insetBy(dx: -pad, dy: -pad))
            }
        }
        return dirty
    }
    private func contentRedrawRequired(_ previous: EaselItem, _ item: EaselItem) -> Bool {
        previous.kind != item.kind
            || previous.text != item.text
            || previous.richText != item.richText
            || previous.textStyle != item.textStyle
            || previous.color != item.color
            || previous.url != item.url
            || previous.assetID != item.assetID
            || previous.points != item.points
            || previous.frame.width != item.frame.width
            || previous.frame.height != item.frame.height
            || previous.liveCapture != item.liveCapture
            || previous.captureLayout != item.captureLayout
    }
    private func cachedTextLayout(for item: EaselItem) -> EaselTextLayout.Layout {
        let size = NSSize(width: item.frame.width, height: item.frame.height)
        if let cached = textLayouts[item.id], cached.matches(item, size: size) { return cached.layout }
        let layout = EaselTextLayout.Layout(EaselRichTextCodec.attributed(item), width: size.width, height: size.height)
        textLayouts[item.id] = CachedTextLayout(width: size.width, height: size.height, text: item.text,
                                                rich: item.richText, style: item.textStyle, color: item.color, layout: layout)
        return layout
    }
    private func rememberPaintedArtwork() {
        trackedItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        trackedSelection = displayedSelection
        trackedHover = hoveredObjectID
        trackedMarquee = marqueeRect
        trackedGuideBounds = guideDirtyBounds()
        trackedCanvasScale = canvasScale
        trackedHidesAnnotations = hidesPassiveAnnotations
    }
    private func presentationMatchesPaintedArtwork() -> Bool {
        guard let trackedCanvasScale, trackedCanvasScale == canvasScale,
              trackedHidesAnnotations == hidesPassiveAnnotations,
              trackedHover == hoveredObjectID,
              trackedMarquee == marqueeRect,
              trackedSelection == displayedSelection,
              trackedGuideBounds == guideDirtyBounds() else { return false }
        let current = items
        guard trackedItems.count == current.count else { return false }
        for item in current {
            guard trackedItems[item.id] == item else { return false }
        }
        return true
    }
    private func invalidateIncrementalDisplay(layout: Bool = false) {
        if presentationMatchesPaintedArtwork() {
            presentationNoOpSkipCount += 1
            return
        }
        if layout { needsLayout = true }
        var dirty = NSRect.null
        func add(_ rect: NSRect) {
            guard !rect.isNull, rect.width.isFinite, rect.height.isFinite else { return }
            dirty = dirty.union(rect)
        }
        let current = items
        let ids = Set(current.map(\.id))
        let scaleChanged = trackedCanvasScale.map { $0 != canvasScale } ?? false
        let hideChanged = trackedHidesAnnotations != hidesPassiveAnnotations
        for (id, previous) in trackedItems where !ids.contains(id) {
            add(displayBounds(of: previous))
            textLayouts.removeValue(forKey: id)
        }
        var overlayChanged = trackedHover != hoveredObjectID || trackedMarquee != marqueeRect
            || trackedGuideBounds != guideDirtyBounds() || trackedSelection != displayedSelection
            || scaleChanged || hideChanged
        for item in current {
            if let previous = trackedItems[item.id] {
                if previous != item {
                    add(displayBounds(of: previous)); add(displayBounds(of: item))
                    if contentRedrawRequired(previous, item) {
                        textLayouts.removeValue(forKey: item.id)
                        artwork[item.id]?.needsDisplay = true
                    }
                    if displayedSelection.contains(item.id) || item.id == hoveredObjectID { overlayChanged = true }
                }
            } else {
                add(displayBounds(of: item))
                artwork[item.id]?.needsDisplay = true
                if displayedSelection.contains(item.id) || item.id == hoveredObjectID { overlayChanged = true }
            }
        }
        func addSelectionChrome(_ ids: Set<UUID>, _ source: [EaselItem]) {
            let selected = source.filter { ids.contains($0.id) }
            for item in selected { add(displayBounds(of: item)) }
            if let bounds = EaselGeometryEdit.bounds(of: selected) {
                let pad = 16 / max(canvasScale, 0.2) + 16
                add(NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
                    .insetBy(dx: -pad, dy: -pad))
            }
        }
        addSelectionChrome(trackedSelection, Array(trackedItems.values))
        addSelectionChrome(displayedSelection, current)
        if trackedHover != hoveredObjectID {
            if let id = trackedHover, let item = trackedItems[id] ?? current.first(where: { $0.id == id }) {
                add(displayBounds(of: item))
            }
            if let id = hoveredObjectID, let item = current.first(where: { $0.id == id }) {
                add(displayBounds(of: item))
            }
        }
        let marqueePad = 16 / max(canvasScale, 0.2) + 16
        if let rect = trackedMarquee { add(rect.insetBy(dx: -marqueePad, dy: -marqueePad)) }
        if let rect = marqueeRect { add(rect.insetBy(dx: -marqueePad, dy: -marqueePad)) }
        add(trackedGuideBounds)
        add(guideDirtyBounds())
        if session.document.items.isEmpty || trackedItems.isEmpty {
            add(NSRect(x: 40, y: 50, width: max(180, bounds.width - 80), height: 106))
        }
        rememberPaintedArtwork()
        if usesObjectSurfaces {
            if overlayChanged {
                presentationDirtyCount += 1
                decoration.needsDisplay = true
            }
        } else if scaleChanged || hideChanged {
            presentationDirtyCount += 1
            needsDisplay = true
        } else if !dirty.isNull {
            presentationDirtyCount += 1
            setNeedsDisplay(dirty)
        }
    }
    private func synchronizePageSelection() {
        pageObjects?.synchronize(items: items, selection: selection,
                                 interacting: !drawing && editor == nil && start == nil && !isHiddenOrHasHiddenAncestor)
    }
    override func layout() {
        super.layout(); motion.bind(enclosingScrollView); refreshTextControls(); synchronizeAccessibleObjects()
        let captured = selection.count == 1 ? items.first { selection.contains($0.id) && $0.kind == .webCard && $0.captureLayout != nil && !$0.ownsEmbeddedPage } : nil
        liveCaptureButton.isHidden = captured == nil || pageObjects == nil || start != nil || drawing || fixedCanvasSize != nil || motion.isInteracting
        if let captured {
            let frame = rect(captured)
            liveCaptureButton.frame = NSRect(x: max(frame.minX, frame.maxX - 100), y: frame.minY + 7, width: 92, height: 26)
        }
        synchronizePageSelection()
        guard usesObjectSurfaces else {
            artwork.values.forEach { $0.removeFromSuperview() }; artwork.removeAll()
            decoration.removeFromSuperview(); return
        }
        let ids = Set(items.map(\.id))
        for id in Array(artwork.keys) where !ids.contains(id) { artwork.removeValue(forKey: id)?.removeFromSuperview() }
        var ordered: [NSView] = []
        var overlayDirty = decoration.frame != bounds || marqueeRect != nil || guides != nil
        for item in items {
            let objectView: NSView
            if item.ownsEmbeddedPage, let surface = pageObjects?.surface(for: item) { objectView = surface }
            else if let existing = artwork[item.id] as? EaselCanvasArtwork { objectView = existing }
            else { objectView = EaselCanvasArtwork(canvas: self, id: item.id) }
            if let old = artwork[item.id], old !== objectView { old.removeFromSuperview() }
            artwork[item.id] = objectView
            let previous = trackedItems[item.id]
            let nextFrame = rect(item)
            if objectView.frame != nextFrame { objectView.frame = nextFrame }
            if previous == nil || contentRedrawRequired(previous!, item) {
                objectView.needsDisplay = true
                textLayouts.removeValue(forKey: item.id)
            }
            if displayedSelection.contains(item.id) || item.id == hoveredObjectID, previous?.frame != item.frame {
                overlayDirty = true
            }
            ordered.append(objectView)
        }
        if decoration.frame != bounds { decoration.frame = bounds; overlayDirty = true }
        if overlayDirty { decoration.needsDisplay = true }
        ordered.append(decoration)
        if let editor { ordered.append(editor) }
        ordered.append(contentsOf: items.compactMap { accessibleObjects[$0.id] })
        ordered.append(textStyleBar)
        ordered.append(liveCaptureButton)
        if subviews.map(ObjectIdentifier.init) != ordered.map(ObjectIdentifier.init) {
            for view in ordered { addSubview(view, positioned: .above, relativeTo: nil) }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if fixedCanvasSize == nil {
            EaselAppearance.surface.setFill(); dirtyRect.fill()
        } else { NSColor.clear.setFill(); dirtyRect.fill(using: .copy) }
        if !usesObjectSurfaces {
            for item in items where displayBounds(of: item).intersects(dirtyRect) { drawObject(item) }
            drawDecorations(in: dirtyRect)
        }
        rememberPaintedArtwork()
    }
    fileprivate func drawObject(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        drawObject(item)
    }
    private func drawObject(_ item: EaselItem, showsEditor: Bool = true) {
            let r = rect(item), ink = color(item.color)
            ink.setStroke()
            switch item.kind {
            case .text:
                if showsEditor, editingID == item.id, let editor {
                    if item.resolvedTextStyle.resolvedFill == .contentHugging, let manager = editor.layoutManager, let container = editor.textContainer {
                        let origin = NSPoint(x: r.minX + editor.textContainerOrigin.x, y: r.minY + editor.textContainerOrigin.y)
                        EaselTextLayout.drawFill(manager: manager, container: container, origin: origin, style: item.resolvedTextStyle)
                    }
                } else {
                    cachedTextLayout(for: item).draw(at: r.origin, style: item.resolvedTextStyle)
                }
            case .rectangle, .circle:
                let path = item.kind == .circle ? NSBezierPath(ovalIn: r) : NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
                ink.withAlphaComponent(0.09).setFill(); path.fill(); ink.setStroke(); path.lineWidth = 2.5; path.stroke()
            case .arrow, .freehand:
                guard let first = item.points.first else { return }
                let path = NSBezierPath(); path.move(to: NSPoint(x: r.minX + first.x, y: r.minY + first.y))
                for p in item.points.dropFirst() { path.line(to: NSPoint(x: r.minX + p.x, y: r.minY + p.y)) }
                path.lineWidth = 3; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
                if item.kind == .arrow, let last = item.points.last, item.points.count >= 2 {
                    let previous = item.points[item.points.count - 2], angle = atan2(last.y - previous.y, last.x - previous.x)
                    let end = NSPoint(x: r.minX + last.x, y: r.minY + last.y), head = NSBezierPath()
                    head.move(to: NSPoint(x: end.x - cos(angle - 0.5) * 16, y: end.y - sin(angle - 0.5) * 16))
                    head.line(to: end); head.line(to: NSPoint(x: end.x - cos(angle + 0.5) * 16, y: end.y - sin(angle + 0.5) * 16))
                    head.lineWidth = 3; head.lineCapStyle = .round; head.stroke()
                }
            case .image:
                if let id = item.assetID { image(id)?.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            case .webCard where item.assetID != nil:
                if let id = item.assetID { image(id)?.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            case .link, .webCard, .browser:
                EaselAppearance.surface.setFill(); NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
                ink.withAlphaComponent(0.15).setStroke(); let border = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10); border.stroke()
                let title = item.text.isEmpty ? (item.url ?? "Link") : item.text
                (title as NSString).draw(in: r.insetBy(dx: 16, dy: 16), withAttributes: [.font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: ink])
                ((item.url ?? "") as NSString).draw(in: NSRect(x: r.minX + 16, y: r.maxY - 36, width: r.width - 32, height: 24),
                       withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
            }
    }
    fileprivate func drawDecorations(in dirtyRect: NSRect) {
        for item in items where displayedSelection.contains(item.id) || item.id == hoveredObjectID {
            if displayBounds(of: item).intersects(dirtyRect) {
                drawSelectionOutline(item, exclusive: displayedSelection == [item.id])
            }
        }
        if let frame = resizeBounds {
            let group = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            let pad = 16 / max(canvasScale, 0.2) + 16
            if group.insetBy(dx: -pad, dy: -pad).intersects(dirtyRect) {
                if displayedSelection.count > 1 {
                    easelSelectionColor.setStroke()
                    let outline = NSBezierPath(rect: group); outline.lineWidth = 2.5 / canvasScale; outline.stroke()
                }
                for location in EaselResizeHandle.allCases where location.isCorner && showsFrameAnnotation(location) {
                    let point = location.point(in: frame)
                    EaselAppearance.drawHandle(at: NSPoint(x: point.x, y: point.y), scale: canvasScale)
                }
            }
        }
        if let arrow = selectedArrow, displayBounds(of: arrow).intersects(dirtyRect) {
            for endpoint in EaselArrowEndpoint.allCases where showsArrowAnnotation(endpoint) {
                guard let point = endpoint.point(in: arrow) else { continue }
                EaselAppearance.drawHandle(at: NSPoint(x: point.x, y: point.y), scale: canvasScale)
            }
        }
        if let marqueeRect, marqueeRect.insetBy(dx: -2, dy: -2).intersects(dirtyRect) {
            easelSelectionColor.withAlphaComponent(0.073).setFill(); marqueeRect.fill()
            easelSelectionColor.setStroke()
            let outline = NSBezierPath(rect: marqueeRect); outline.lineWidth = 1 / canvasScale; outline.stroke()
        }
        let highlights = guides?.lines ?? []
        if guideDirtyBounds().intersects(dirtyRect) {
            for (segments, color) in [(highlights.flatMap(\.targetSegments), NSColor(white: 0.92, alpha: 1)),
                                      (highlights.flatMap(\.anchorSegments), easelSelectionColor)] {
                let path = NSBezierPath(); path.lineWidth = 2.5 / canvasScale
                path.lineCapStyle = .round; path.lineJoinStyle = .round
                for segment in segments {
                    path.move(to: NSPoint(x: segment.start.x, y: segment.start.y))
                    path.line(to: NSPoint(x: segment.end.x, y: segment.end.y))
                }
                color.setStroke(); path.stroke()
            }
        }
        if session.document.items.isEmpty && editor == nil {
            let placeholder = NSRect(x: 40, y: 50, width: max(180, bounds.width - 80), height: 106)
            if placeholder.intersects(dirtyRect) {
                ("A place for your ideas" as NSString).draw(at: NSPoint(x: 40, y: 50), withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: NSColor.tertiaryLabelColor])
                ("Add text, images, links or a drawing. Everything saves here on your Mac." as NSString).draw(in: NSRect(x: 40, y: 96, width: max(180, bounds.width - 80), height: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor])
            }
        }
    }
    private func drawSelectionOutline(_ item: EaselItem, exclusive: Bool) {
        let r = rect(item), path: NSBezierPath
        var width: CGFloat = 2.5
        switch item.kind {
        case .circle: path = NSBezierPath(ovalIn: r)
        case .rectangle: path = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
        case .arrow, .freehand:
            path = NSBezierPath()
            guard let first = item.points.first else { return }
            path.move(to: NSPoint(x: r.minX + first.x, y: r.minY + first.y))
            for point in item.points.dropFirst() { path.line(to: NSPoint(x: r.minX + point.x, y: r.minY + point.y)) }
            if item.kind == .arrow, let last = item.points.last, item.points.count >= 2 {
                let previous = item.points[item.points.count - 2], angle = atan2(last.y - previous.y, last.x - previous.x)
                let end = NSPoint(x: r.minX + last.x, y: r.minY + last.y)
                path.move(to: NSPoint(x: end.x - cos(angle - 0.5) * 16, y: end.y - sin(angle - 0.5) * 16))
                path.line(to: end); path.line(to: NSPoint(x: end.x - cos(angle + 0.5) * 16, y: end.y - sin(angle + 0.5) * 16))
            }
            width = 5; path.lineCapStyle = .round; path.lineJoinStyle = .round
        case .text:
            let style = item.resolvedTextStyle
            width = [2.5, 3, 3.5, 3.5, 3.5][style.size.index]
            let layout = cachedTextLayout(for: item)
            let lines = EaselTextLayout.lineRects(manager: layout.manager, container: layout.container)
                .map { $0.offsetBy(dx: r.minX + EaselTextLayout.inset.width, dy: r.minY + EaselTextLayout.inset.height) }
            if exclusive {
                let union = lines.reduce(r) { $0.union($1) }
                path = NSBezierPath(roundedRect: union, xRadius: EaselTextLayout.radius(style), yRadius: EaselTextLayout.radius(style))
            } else {
                guard let context = NSGraphicsContext.current?.cgContext else { return }
                context.saveGState(); defer { context.restoreGState() }
                context.addPath(EaselTextLayout.fillPath(rects: lines, radius: EaselTextLayout.radius(style)))
                context.setStrokeColor(easelSelectionColor.cgColor); context.setLineWidth(width / canvasScale); context.strokePath()
                return
            }
        default: path = NSBezierPath(rect: r)
        }
        easelSelectionColor.setStroke(); path.lineWidth = width / canvasScale; path.stroke()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
        for view in artwork.values { view.needsDisplay = true }
    }
    override func updateTrackingAreas() {
        if let appearanceTracking { removeTrackingArea(appearanceTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking); appearanceTracking = tracking; super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let next = !drawing && start == nil && editor == nil && !session.isClosed ? object(at: point)?.id : nil
        if hoveredObjectID != next { hoveredObjectID = next; invalidateIncrementalDisplay() }
        super.mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) { hoveredObjectID = nil; invalidateIncrementalDisplay(); super.mouseExited(with: event) }
    private var easelSelectionColor: NSColor {
        EaselAppearance.selection
    }
    private var canvasScale: Double {
        let scale = enclosingScrollView?.magnification ?? 1
        return scale.isFinite && scale > 0 ? scale : 1
    }
    private var canPresentMotion: Bool { !session.isDeleted && !session.isClosed }
    private var hidesPassiveAnnotations: Bool { motion.isInteracting || (geometryEdit != nil && draft != nil) }
    private func showsFrameAnnotation(_ handle: EaselResizeHandle) -> Bool {
        !motion.isInteracting && (!hidesPassiveAnnotations || displayedSelection.count > 1 || resizeHandle == handle)
    }
    private func showsArrowAnnotation(_ endpoint: EaselArrowEndpoint) -> Bool {
        !motion.isInteracting && (!hidesPassiveAnnotations || arrowEndpoint == endpoint)
    }
    func refreshMotionOwnership() {
        if !canPresentMotion || isHiddenOrHasHiddenAncestor || window == nil { motion.cancel() }
    }
    private var selectedArrow: EaselItem? {
        guard !drawing, editor == nil, marqueeRect == nil, displayedSelection.count == 1,
              let item = items.first(where: { displayedSelection.contains($0.id) }),
              item.kind == .arrow, item.points.count == 2 else { return nil }
        return item
    }
    private func arrowEndpoint(at point: NSPoint) -> EaselArrowEndpoint? {
        guard let item = selectedArrow else { return nil }
        return EaselArrowEndpoint.allCases.first { endpoint in
            guard showsArrowAnnotation(endpoint), let r = endpoint.hitRect(in: item, scale: canvasScale) else { return false }
            return NSRect(x: r.x, y: r.y, width: r.width, height: r.height).contains(point)
        }
    }
    private var resizeBounds: EaselRect? {
        guard !drawing, editor == nil, marqueeRect == nil, selectedArrow == nil else { return nil }
        return EaselGeometryEdit.bounds(of: items.filter { displayedSelection.contains($0.id) })
    }
    private func resizeHandle(at point: NSPoint) -> EaselResizeHandle? {
        guard let frame = resizeBounds else { return nil }
        return EaselResizeHandle.allCases.first { handle in
            guard showsFrameAnnotation(handle), let r = handle.hitRect(in: frame, scale: canvasScale) else { return false }
            return NSRect(x: r.x, y: r.y, width: r.width, height: r.height).contains(point)
        }
    }
    @discardableResult
    private func commit(_ name: String, coalescing group: UUID? = nil, _ change: (inout EaselDocument) throws -> Void) -> Bool {
        defer { invalidateIncrementalDisplay(layout: true) }
        do { try session.perform(name, coalescing: group, change); return true }
        catch { onError?(error); return false }
    }
    @discardableResult
    func insert(kind: EaselItemKind, text: String = "", edit: Bool = false, styledText: EaselStyledText? = nil, at point: NSPoint? = nil) -> Bool {
        cancelPointerInteraction(); guard finishEditing() else { return false }; drawing = false
        let origin = point.map { NSPoint(x: max(0, $0.x), y: max(0, $0.y - 14)) }
            ?? NSPoint(x: max(30, visibleRect.midX - 140), y: visibleRect.minY + 70 + Double(session.document.items.count % 6) * 24)
        var item = EaselItem(kind: kind, frame: EaselRect(x: origin.x, y: origin.y,
                             width: kind == .text ? (point == nil ? 360 : 280) : 220,
                             height: kind == .text ? (point == nil ? 120 : 28) : 140),
                             zIndex: (session.document.items.map(\.zIndex).max() ?? 0) + 1,
                             text: kind == .text && edit && text.isEmpty && styledText == nil ? EaselTextEditing.defaultText : text,
                             color: insertionColor)
        if kind == .text, let styledText {
            item.textStyle = styledText.style; item.color = styledText.color; item.richText = styledText.richText
            item.frame.height = max(item.frame.height, measuredTextHeight(item))
        }
        if let size = fixedCanvasSize {
            item.frame.width = min(item.frame.width, size.width); item.frame.height = min(item.frame.height, size.height)
            item.frame.x = max(0, min(point == nil ? visibleRect.midX - item.frame.width / 2 : origin.x, size.width - item.frame.width))
            item.frame.y = max(0, min(point == nil ? visibleRect.midY - item.frame.height / 2 : origin.y, size.height - item.frame.height))
        }
        if kind == .arrow { item.points = [EaselPoint(x: 0, y: item.frame.height), EaselPoint(x: item.frame.width, y: 0)] }
        guard commit("Add \(kind.rawValue)", { $0.items.append(item) }) else { return false }
        selection = [item.id]; window?.makeFirstResponder(self)
        if edit { beginEditing(item) }
        return true
    }
    func selectBrowserObject(_ id: UUID) {
        guard let item = session.document.items.first(where: { $0.id == id && $0.ownsEmbeddedPage }) else { return }
        cancelPointerInteraction(); guard finishEditing() else { return }; drawing = false; selection = [id]
        scrollToVisible(rect(item)); needsLayout = true; layoutSubtreeIfNeeded()
    }
    @discardableResult
    func insertLink(_ raw: String, browser: Bool = false) -> Bool {
        guard fixedCanvasSize == nil else { return false }
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            onError?(EaselStoreError.invalidDocument("enter a complete http or https link")); return false
        }
        cancelPointerInteraction(); guard finishEditing() else { return false }; drawing = false
        let item = EaselItem(kind: browser ? .browser : .link, frame: EaselRect(x: max(30, visibleRect.midX - 170), y: visibleRect.minY + 90, width: browser ? 640 : 340, height: browser ? 420 : 120),
                             zIndex: (items.map(\.zIndex).max() ?? 0) + 1, text: url.host ?? input, url: url.absoluteString)
        if commit(browser ? "Add webpage" : "Add link", { $0.items.append(item) }) { selection = [item.id]; return true }
        return false
    }
    func importImage(_ data: Data) throws {
        guard data.count <= EaselStore.maximumAssetBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let widthValue = properties[kCGImagePropertyPixelWidth] as? Int,
              let heightValue = properties[kCGImagePropertyPixelHeight] as? Int,
              widthValue > 0, heightValue > 0, widthValue <= 16_384, heightValue <= 16_384,
              Int64(widthValue) * Int64(heightValue) <= 80_000_000,
              let rep = NSBitmapImageRep(data: data),
              rep.pixelsWide > 0, rep.pixelsHigh > 0, rep.pixelsWide <= 16_384, rep.pixelsHigh <= 16_384,
              Int64(rep.pixelsWide) * Int64(rep.pixelsHigh) <= 80_000_000,
              let png = rep.representation(using: .png, properties: [:]) else { throw EaselStoreError.invalidImage }
        cancelPointerInteraction()
        guard finishEditing() else { throw EaselStoreError.invalidDocument("finish the current text edit") }
        drawing = false
        let assetID = try session.importPNG(png), width = min(480.0, Double(rep.pixelsWide))
        var item = EaselItem(kind: .image, frame: EaselRect(x: max(24, visibleRect.midX - width / 2), y: visibleRect.minY + 70,
                             width: width, height: max(1, width * Double(rep.pixelsHigh) / Double(rep.pixelsWide))),
                             zIndex: (items.map(\.zIndex).max() ?? 0) + 1, assetID: assetID)
        if let size = fixedCanvasSize {
            let ratio = min(1, size.width / item.frame.width, size.height / item.frame.height)
            item.frame.width *= ratio; item.frame.height *= ratio
            item.frame.x = max(0, min(visibleRect.midX - item.frame.width / 2, size.width - item.frame.width))
            item.frame.y = max(0, min(visibleRect.midY - item.frame.height / 2, size.height - item.frame.height))
        }
        try session.perform("Add image") { $0.items.append(item) }; selection = [item.id]
    }
    func importImageFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= EaselStore.maximumAssetBytes else { throw EaselStoreError.tooLarge }
        try importImage(Data(contentsOf: url, options: .mappedIfSafe))
    }
    private func beginEditing(_ item: EaselItem, at point: NSPoint? = nil) {
        guard item.kind == .text else { return }
        guard finishEditing(), session.document.items.contains(where: { $0 == item }) else { return }
        editingID = item.id; textUndoGroup = UUID()
        let text = EaselStyledTextView(frame: rect(item))
        text.drawsBackground = false; text.isRichText = true; text.importsGraphics = false; text.allowsUndo = true
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.isContinuousSpellCheckingEnabled = true
        text.textContainer?.widthTracksTextView = true
        text.usesEaselObjectLayout = true
        text.onObjectLayoutChanged = { [weak self] in self?.invalidateIncrementalDisplay(layout: true) }
        text.textContainer?.lineFragmentPadding = EaselTextLayout.fragmentPadding
        text.textContainerInset = EaselTextLayout.inset; text.delegate = self
        text.setAccessibilityLabel("Easel text"); addSubview(text); editor = text; keyboardStructureChanged()
        text.onClipboardError = { [weak self] in self?.onError?($0) }
        text.onUndoDocument = { [weak self] in self?.undo(nil) }
        text.onRedoDocument = { [weak self] in self?.redo(nil) }
        text.canUndoDocument = { [weak self] in self?.session.canUndo == true }
        text.canRedoDocument = { [weak self] in self?.session.canRedo == true }
        updateEditor(item)
        if window?.makeFirstResponder(text) == true {
            if let point, item.text != EaselTextEditing.defaultText {
                let index = text.characterIndexForInsertion(at: text.convert(point, from: self))
                text.setSelectedRange(text.selectionRange(forProposedRange: NSRange(location: index, length: 0), granularity: .selectByWord))
            } else { text.selectAll(nil) }
        }
        invalidateIncrementalDisplay(layout: true); refreshTextControls()
    }
    private func updateEditor(_ item: EaselItem) {
        guard let text = editor else { return }
        if text.hasMarkedText() {
            guard let previous = editingTextSnapshot,
                  previous.text != item.text || previous.rich != item.richText else { return }
            text.inputContext?.discardMarkedText(); text.unmarkText()
        }
        editingTextSnapshot = (item.text, item.richText)
        synchronizingEditor = true
        defer { synchronizingEditor = false }
        let selected = text.selectedRanges
        let target = EaselRichTextCodec.attributed(item)
        EaselTextAttachments.bind(target, container: text.textContainer)
        let current = try? EaselRichTextCodec.snapshot(text.attributedString())
        let desired = try? EaselRichTextCodec.snapshot(target)
        if !text.hasLoadedDocument || text.string != item.text || current != desired {
            text.retire()
            text.textStorage?.setAttributedString(target); text.resetEditingHistory()
            if target.length == 0 { text.typingAttributes = [.font: EaselTextAppearance.font(item.resolvedTextStyle), .foregroundColor: color(item.color)] }
        }
        text.hasLoadedDocument = true
        text.objectStyle = item.resolvedTextStyle; text.objectColor = item.color
        text.frame = rect(item)
        let length = (text.string as NSString).length
        text.selectedRanges = selected.map { value in
            let range = value.rangeValue, start = min(range.location, length)
            return NSValue(range: NSRange(location: start, length: min(range.length, length - start)))
        }
    }
    @discardableResult
    private func finishEditing(removingEmpty: Bool = true) -> Bool {
        guard !finishingEditor else { return false }
        guard let text = editor, let id = editingID else { return true }
        finishingEditor = true
        defer { finishingEditor = false }
        text.finishComposition()
        if removingEmpty, let item = session.document.items.first(where: { $0.id == id }),
           let snapshot = editingTextSnapshot, item.text == snapshot.text, item.richText == snapshot.rich,
           item.text == text.string, EaselTextEditing.isEmpty(item) {
            guard commit("Remove empty text", coalescing: textUndoGroup, { document in
                document.items.removeAll { $0 == item }
            }) else { return false }
            selection.remove(id)
        }
        text.retire(); text.delegate = nil
        editor = nil; editingID = nil; textUndoGroup = nil; editingTextSnapshot = nil
        text.removeFromSuperview(); refreshTextControls(); invalidateIncrementalDisplay(layout: true); keyboardStructureChanged()
        return true
    }
    func textDidEndEditing(_ notification: Notification) {
        guard let text = notification.object as? EaselStyledTextView, text === editor, !finishingEditor else { return }
        DispatchQueue.main.async { [weak self, weak text] in
            guard let self, let text, self.editor === text, !text.hasPendingRangeAction,
                  let responder = self.window?.firstResponder, responder !== text else { return }
            if let view = responder as? NSView, view === self.textStyleBar || view.isDescendant(of: self.textStyleBar) { return }
            self.finishEditing()
        }
    }
    private func measuredTextHeight(_ item: EaselItem) -> Double {
        let value = item.text.isEmpty ? EaselTextAppearance.attributed(" ", style: item.resolvedTextStyle, color: item.color)
            : EaselRichTextCodec.attributed(item)
        return EaselTextLayout.Layout(value, width: item.frame.width).height
    }
    private struct TextFillState {
        let id: UUID
        let style: EaselTextStyle?
    }
    func setTextFill(_ fill: EaselTextStyle.Fill) {
        guard !session.isClosed, editor?.hasMarkedText() != true else { return }
        let selected = session.document.items.filter { selection.contains($0.id) }
        guard !selected.isEmpty, selected.allSatisfy({ $0.kind == .text }) else { return }
        let original = selected.map { TextFillState(id: $0.id, style: $0.textStyle) }
        let replacement = selected.map { item -> TextFillState in
            var style = item.resolvedTextStyle; style.fill = fill == .none ? nil : fill
            return TextFillState(id: item.id, style: style)
        }
        applyTextFill(replacement, replacing: original, editingOwner: editor)
        if let editor { window?.makeFirstResponder(editor) }
    }
    private func applyTextFill(_ replacement: [TextFillState], replacing original: [TextFillState], editingOwner: EaselStyledTextView?, historyAnchor: EaselDocument? = nil) {
        guard editingOwner == nil || editingOwner === editor,
              editor?.hasMarkedText() != true,
              historyAnchor == nil || session.undoDestination == historyAnchor,
              original.allSatisfy({ state in session.document.items.contains { $0.id == state.id && $0.kind == .text && $0.textStyle == state.style } }) else { return }
        guard zip(replacement, original).contains(where: { $0.style != $1.style }) else { return }
        editingOwner?.breakUndoCoalescing()
        let saved = commit("Text fill", coalescing: editingOwner == nil ? nil : textUndoGroup) { document in
            for state in replacement {
                guard let index = document.items.firstIndex(where: { $0.id == state.id }) else { return }
                document.items[index].textStyle = state.style
            }
        }
        if saved, let editingOwner, let anchor = session.undoDestination {
            editingOwner.localUndo.registerUndo(withTarget: editingOwner) { [weak self] owner in
                self?.applyTextFill(original, replacing: replacement, editingOwner: owner, historyAnchor: anchor)
            }
            editingOwner.localUndo.setActionName("Text fill")
        }
        refreshTextControls()
    }
    private func changeTextStyle(preservingSize: Bool = false, _ mutation: (inout EaselTextStyle) -> Void) {
        guard !session.isClosed else { return }
        if let editor { editor.changeStyle(preservingSize: preservingSize, mutation); refreshTextControls(); return }
        let ids = selection
        guard !ids.isEmpty, items.filter({ ids.contains($0.id) }).allSatisfy({ $0.kind == .text }) else { return }
        commit("Style text") { document in
            for index in document.items.indices where ids.contains(document.items[index].id) {
                var style = document.items[index].resolvedTextStyle; mutation(&style)
                document.items[index].textStyle = style
                if var rich = document.items[index].richText {
                    for i in rich.runs.indices {
                        let old = EaselRichTextCodec.font(rich.runs[i].attributes.font)
                        var next = try EaselTextAppearance.font(style, preservingEmphasisFrom: old)
                        if preservingSize, rich.runs[i].attributes.paragraph?.heading != nil { next = NSFontManager.shared.convert(next, toSize: old.pointSize) }
                        rich.runs[i].attributes.font = EaselRichTextCodec.snapshotFont(next)
                    }
                    document.items[index].richText = rich
                }
                document.items[index].frame.height = max(document.items[index].frame.height, measuredTextHeight(document.items[index]))
            }
        }
        refreshTextControls()
    }
    private func refreshTextControls() {
        if textPaletteSelection != selection { textStyleBar.collapse(); textPaletteSelection = selection }
        let selected = session.document.items.filter { selection.contains($0.id) }
        let textOnly = !selected.isEmpty && selected.allSatisfy { $0.kind == .text }
        textStyleBar.update(styles: textOnly && !hidesPassiveAnnotations && canPresentMotion ? selected.map(\.resolvedTextStyle) : [], editor: editor)
        guard textOnly else { return }
        let x = selected.map { $0.frame.x }.min() ?? 0, y = selected.map { $0.frame.y }.min() ?? 0
        let area = visibleRect
        let scale = canvasScale, size = NSSize(width: textStyleBar.preferredWidth / scale, height: textStyleBar.preferredHeight / scale)
        let margin = 4 / scale
        textStyleBar.frame = NSRect(x: max(area.minX + margin, min(x - 50 / scale - margin, area.maxX - size.width - margin)),
                                    y: max(area.minY + margin, min(y, area.maxY - size.height - margin)), width: size.width, height: size.height)
        textStyleBar.bounds = NSRect(x: 0, y: 0, width: textStyleBar.preferredWidth, height: textStyleBar.preferredHeight)
        if subviews.last !== textStyleBar { addSubview(textStyleBar, positioned: .above, relativeTo: nil) }
    }
    func textDidChange(_ notification: Notification) {
        guard !synchronizingEditor, let id = editingID, let text = editor,
              notification.object as? EaselStyledTextView === text else { return }
        guard !text.hasMarkedText() else { return }
        guard let item = session.document.items.first(where: { $0.id == id && $0.kind == .text }) else { return }
        if let previous = editingTextSnapshot, item.text != previous.text || item.richText != previous.rich {
            updateEditor(item); return
        }
        let payload: EaselStyledText
        do { payload = try EaselStyledText.capture(text.attributedString(), style: text.objectStyle, color: text.objectColor) }
        catch { onError?(error); if let item = session.document.items.first(where: { $0.id == id }) { updateEditor(item) }; return }
        let saved = commit("Edit text", coalescing: textUndoGroup) { document in
            guard let i = document.items.firstIndex(where: { $0.id == id }) else { return }
            document.items[i].text = payload.text; document.items[i].richText = payload.richText
            document.items[i].frame.height = max(document.items[i].frame.height, measuredTextHeight(document.items[i]))
        }
        if saved { editingTextSnapshot = (payload.text, payload.richText) }
        else if let item = session.document.items.first(where: { $0.id == id }) { updateEditor(item) }
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let raw = (link as? URL)?.absoluteString ?? link as? String ?? ""
        guard EaselRichText.validLink(raw), let url = URL(string: raw) else { return true }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { onOpenURL?(url) }
        else { NSWorkspace.shared.open(url) }
        return true
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        guard !synchronizingEditor else { return }; refreshTextControls()
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), textView === editor {
            if finishEditing() { selection.removeAll(); window?.makeFirstResponder(self) }
            return true
        }
        return false
    }
    private func cancelPointerInteraction() {
        let hadPointerOwner = start != nil || geometryEdit != nil || draft != nil || marqueeRect != nil
        if !stroke.isEmpty, start != nil { selection = selectionBeforeGesture.intersection(session.document.items.map(\.id)) }
        draft = nil; start = nil; original = []; stroke = []; geometryEdit = nil
        marqueeRect = nil; marqueeEnd = nil; tentativeSelection = nil
        selectionBeforeGesture = []; resizeHandle = nil; arrowEndpoint = nil; guides = nil
        lastDragTimestamp = nil; dragVelocity = .init(x: 0, y: 0)
        lastGeometryPoint = nil; lastDragLocation = nil; dragDistance = 0
        if hadPointerOwner { synchronizePageSelection(); keyboardStructureChanged() }
        window?.invalidateCursorRects(for: self)
        invalidateIncrementalDisplay(layout: true)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        }
        if newWindow !== window { hoveredObjectID = nil; menuGeneration &+= 1; motion.cancel(); cancelPointerInteraction() }
        if let newWindow {
            NotificationCenter.default.addObserver(self, selector: #selector(ownerResignedKey),
                                                   name: NSWindow.didResignKeyNotification, object: newWindow)
            NotificationCenter.default.addObserver(self, selector: #selector(ownerResignedKey),
                                                   name: NSWindow.willCloseNotification, object: newWindow)
        }
        super.viewWillMove(toWindow: newWindow)
    }
    @objc private func ownerResignedKey(_ notification: Notification) { hoveredObjectID = nil; menuGeneration &+= 1; motion.cancel(); cancelPointerInteraction() }
    override func resignFirstResponder() -> Bool {
        menuGeneration &+= 1; cancelPointerInteraction(); return super.resignFirstResponder()
    }
    private func updateMarquee(to point: NSPoint, flags: NSEvent.ModifierFlags) {
        guard let start, marqueeRect != nil else { return }
        let rect = EaselCanvasSelection.marquee(from: .init(x: start.x, y: start.y), to: .init(x: point.x, y: point.y))
        marqueeRect = NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height); marqueeEnd = point
        let operation: EaselCanvasSelection.Operation = flags.contains(.shift) ? .add : flags.contains(.command) ? .subtract : .replace
        tentativeSelection = EaselCanvasSelection.selecting(in: rect, items: session.document.items,
                                                           original: selectionBeforeGesture, operation: operation)
        invalidateIncrementalDisplay()
    }
    override func flagsChanged(with event: NSEvent) {
        if let end = marqueeEnd { updateMarquee(to: end, flags: event.modifierFlags) }
        else if geometryEdit != nil, let point = lastGeometryPoint { updateGeometry(to: point, flags: event.modifierFlags) }
        super.flagsChanged(with: event)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard usesObjectSurfaces, let hit, hit !== self else { return hit }
        if hit === liveCaptureButton { return hit }
        if hit === editor || editor.map({ hit.isDescendant(of: $0) }) == true
            || hit === textStyleBar || hit.isDescendant(of: textStyleBar) { return hit }
        let local = convert(point, from: superview)
        guard resizeHandle(at: local) == nil, arrowEndpoint(at: local) == nil,
              let item = object(at: local), item.ownsEmbeddedPage, selection == [item.id],
              let surface = artwork[item.id], hit === surface || hit.isDescendant(of: surface) else { return self }
        return hit
    }
    override func mouseDown(with event: NSEvent) {
        hoveredObjectID = nil
        motion.cancel(); cancelPointerInteraction(); guard finishEditing() else { return }; window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil); start = point; original = session.document.items
        selectionBeforeGesture = selection; lastDragLocation = event.locationInWindow; lastDragTimestamp = event.timestamp
        if drawing { stroke = [point]; selection.removeAll(); return }
        if let endpoint = arrowEndpoint(at: point) {
            arrowEndpoint = endpoint; beginGeometry()
            lastGeometryPoint = point; invalidateIncrementalDisplay(layout: true); return
        }
        if let handle = resizeHandle(at: point) {
            resizeHandle = handle
            beginGeometry()
            lastGeometryPoint = point; invalidateIncrementalDisplay(layout: true); return
        }
        let hit = object(at: point)
        guard let hit else {
            if event.clickCount == 2 { insert(kind: .text, edit: true, at: point); return }
            marqueeRect = NSRect(origin: point, size: .zero); updateMarquee(to: point, flags: event.modifierFlags); return
        }
        if event.modifierFlags.contains(.shift) { if !selection.insert(hit.id).inserted { selection.remove(hit.id) } }
        else if !selection.contains(hit.id) { selection = [hit.id] }
        guard selection.contains(hit.id) else { cancelPointerInteraction(); return }
        beginGeometry()
        if event.clickCount == 2 {
            cancelPointerInteraction()
            if hit.kind == .text { beginEditing(hit, at: point) }
            else if !hit.ownsEmbeddedPage, let raw = hit.url, let url = URL(string: raw) { onOpenURL?(url) }
        }
        invalidateIncrementalDisplay(layout: true)
    }
    override func mouseDragged(with event: NSEvent) {
        guard start != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if marqueeRect != nil { updateMarquee(to: point, flags: event.modifierFlags); autoscroll(with: event); return }
        if drawing {
            if stroke.count < 20_000 { stroke.append(point) }
            draft = [strokeItem()]; invalidateIncrementalDisplay(); return
        }
        recordDragTravel(event.locationInWindow, timestamp: event.timestamp)
        updateGeometry(to: point, flags: event.modifierFlags)
        autoscroll(with: event)
    }
    private func recordDragTravel(_ point: NSPoint, timestamp: TimeInterval) {
        if let previous = lastDragLocation {
            dragDistance += hypot(point.x - previous.x, point.y - previous.y)
            if let last = lastDragTimestamp, timestamp > last {
                let local = convert(point, from: nil), prior = convert(previous, from: nil)
                dragVelocity = .init(x: (local.x - prior.x) / (timestamp - last),
                                     y: (local.y - prior.y) / (timestamp - last))
            } else { dragVelocity = .init(x: 0, y: 0) }
        }
        lastDragLocation = point; lastDragTimestamp = timestamp
    }
    private func object(at point: NSPoint) -> EaselItem? {
        items.reversed().first { EaselContentHitTest.contains(.init(x: point.x, y: point.y), item: $0,
                                                             selected: selection.contains($0.id)) }
    }
    private func beginGeometry() {
        geometryEdit = EaselGeometryEdit(document: session.document, selection: selection)
        if let edit = geometryEdit {
            let v = visibleRect
            guides = EaselAlignmentGuides(edit: edit, items: session.document.items,
                viewport: .init(x: v.minX, y: v.minY, width: v.width, height: v.height), canvasWidth: bounds.width, scale: canvasScale)
        }
    }
    private func updateGeometry(to point: NSPoint, flags: NSEvent.ModifierFlags) {
        guard let start else { return }
        lastGeometryPoint = point
        guard let edit = geometryEdit, edit.ids == selection, edit.isCurrent(in: session.document),
              guides?.matchesCanvas(width: bounds.width) == true else {
            cancelPointerInteraction(); return
        }
        let translation = EaselPoint(x: point.x - start.x, y: point.y - start.y)
        var intrinsicGuideRatio: Double?
        if flags.contains(.shift), edit.originals.count == 1, let item = edit.originals.first {
            switch item.kind {
            case .image, .webCard:
                if let asset = item.assetID, let size = image(asset)?.size,
                   size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 {
                    intrinsicGuideRatio = size.width / size.height
                } else if item.kind == .webCard { intrinsicGuideRatio = 1 }
            case .link: intrinsicGuideRatio = 220.0 / 160.0
            default: break
            }
        }
        draft = guides?.proposal(edit: edit, document: session.document, translation: translation,
                                     velocity: dragVelocity, scale: canvasScale, handle: resizeHandle, centered: flags.contains(.option),
                                     enabled: alignmentGuidesEnabled && !flags.contains(.command),
                                     preserveAspect: edit.preservesAspect(shift: flags.contains(.shift), command: flags.contains(.command)),
                                     aspectGuideRatio: intrinsicGuideRatio, viewport: .init(x: visibleRect.minX, y: visibleRect.minY,
                                                     width: visibleRect.width, height: visibleRect.height), endpoint: arrowEndpoint)
        window?.invalidateCursorRects(for: self); invalidateIncrementalDisplay(layout: true)
    }
    private func strokeItem() -> EaselItem {
        let minX = stroke.map(\.x).min() ?? 0, minY = stroke.map(\.y).min() ?? 0
        return EaselItem(kind: .freehand, frame: EaselRect(x: minX, y: minY, width: max(1, (stroke.map(\.x).max() ?? minX) - minX),
                         height: max(1, (stroke.map(\.y).max() ?? minY) - minY)), zIndex: (original.map(\.zIndex).max() ?? 0) + 1,
                         color: insertionColor, points: stroke.map { EaselPoint(x: $0.x - minX, y: $0.y - minY) })
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        defer { cancelPointerInteraction() }
        if marqueeRect != nil {
            updateMarquee(to: convert(event.locationInWindow, from: nil), flags: event.modifierFlags)
            selection = tentativeSelection ?? selection; return
        }
        guard let draft else { return }
        if drawing {
            if commit("Draw", { $0.items.append(contentsOf: draft) }) {
                selection = Set(draft.map(\.id)); selectionBeforeGesture = selection
            }
        } else if let edit = geometryEdit, edit.ids == selection, edit.isCurrent(in: session.document),
                  guides?.matchesCanvas(width: bounds.width) == true {
            guard resizing || dragDistance > 3 else { return }
            commit(arrowEndpoint != nil ? "Move arrow endpoint" : resizing ? "Resize objects" : "Move objects") { document in
                guard let next = edit.applying(draft, to: document) else { return }
                document = next
            }
        }
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: drawing ? .crosshair : .arrow)
        if let arrow = selectedArrow {
            for endpoint in EaselArrowEndpoint.allCases where showsArrowAnnotation(endpoint) {
                guard let r = endpoint.hitRect(in: arrow, scale: canvasScale) else { continue }
                addCursorRect(NSRect(x: r.x, y: r.y, width: r.width, height: r.height), cursor: .pointingHand)
            }
        }
        guard let frame = resizeBounds else { return }
        for handle in EaselResizeHandle.allCases.reversed() where showsFrameAnnotation(handle) {
            guard let r = handle.hitRect(in: frame, scale: canvasScale) else { continue }
            let cursor: NSCursor = handle.isCorner ? .crosshair :
                (handle.movesTop || handle.movesBottom ? .resizeUpDown : .resizeLeftRight)
            addCursorRect(NSRect(x: r.x, y: r.y, width: r.width, height: r.height), cursor: cursor)
        }
    }
    override func cancelOperation(_ sender: Any?) {
        if editor != nil {
            if finishEditing() { selection.removeAll(); window?.makeFirstResponder(self) }
        } else if start != nil { cancelPointerInteraction() }
        else if !drawing, selection.isEmpty, let onImageEditingCancel { onImageEditingCancel() }
        else { drawing = false; selection.removeAll(); invalidateIncrementalDisplay(layout: true) }
    }
    override func keyDown(with event: NSEvent) {
        guard window?.firstResponder === self || (window?.firstResponder as? EaselAccessibleObject)?.canvas === self else {
            super.keyDown(with: event); return
        }
        if event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(window?.firstResponder) }
            else { window?.selectNextKeyView(window?.firstResponder) }
            return
        }
        if event.keyCode == 53 { cancelOperation(nil); return }
        guard start == nil else { return }
        if event.keyCode == 1, event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift],
           let onExportImage { onExportImage(); return }
        if event.keyCode == 51 || event.keyCode == 117 { deleteObjects(nil); return }
        if [UInt16(36), UInt16(76)].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           selection.count == 1, let item = items.first(where: { selection.contains($0.id) }) {
            _ = activateAccessibleObject(item); return
        }
        let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
        let delta: (Double, Double)? = [123: (-step, 0), 124: (step, 0), 125: (0, step), 126: (0, -step)][Int(event.keyCode)]
        if let (dx, dy) = delta, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            guard let edit = EaselGeometryEdit(document: session.document, selection: selection) else { return }
            let changes = edit.translated(x: dx, y: dy)
            commit("Move objects") { document in
                if let next = edit.applying(changes, to: document) { document = next }
            }; return
        }
        super.keyDown(with: event)
    }
    @objc func undo(_ sender: Any?) {
        if let editor, editor.localUndo.canUndo { editor.localUndo.undo(); return }
        cancelPointerInteraction(); guard finishEditing(removingEmpty: false) else { return }
        guard let next = session.undoDestination else { return }
        prepareReplacement(next) { [weak self] in
            guard let self else { return }; do { try self.session.undo() } catch { self.onError?(error) }
        }
    }
    @objc func redo(_ sender: Any?) {
        if let editor, editor.localUndo.canRedo { editor.localUndo.redo(); return }
        cancelPointerInteraction(); guard finishEditing(removingEmpty: false) else { return }
        guard let next = session.redoDestination else { return }
        prepareReplacement(next) { [weak self] in
            guard let self else { return }; do { try self.session.redo() } catch { self.onError?(error) }
        }
    }
    override func selectAll(_ sender: Any?) {
        cancelPointerInteraction(); selection = Set(session.document.items.map(\.id)); invalidateIncrementalDisplay(layout: true)
    }
    private func hasCurrentMenuOwner(_ sender: Any?) -> Bool {
        guard let item = sender as? NSMenuItem, let target = item.representedObject as? MenuTarget else { return true }
        guard let owner = target.window else { return false }
        return owner === window && target.generation == menuGeneration
    }
    private func command(for sender: Any?) -> EaselObjectCommand? {
        guard hasCurrentMenuOwner(sender) else { return nil }
        let command: EaselObjectCommand?
        if let menu = sender as? NSMenuItem, let target = menu.representedObject as? MenuTarget {
            command = target.command
        }
        else { command = EaselObjectCommand(document: session.document, selection: selection) }
        guard let command, command.ids == selection, command.isCurrent(in: session.document) else { return nil }
        return command
    }
    @objc private func deleteObjects(_ sender: Any?) {
        cancelPointerInteraction(); guard finishEditing() else { return }
        guard let command = command(for: sender) else { return }
        var next = session.document; next.items.removeAll { command.ids.contains($0.id) }
        prepareReplacement(next) { [weak self] in
            guard let self, command.isCurrent(in: self.session.document) else { return }
            if self.commit("Delete objects", { $0.items.removeAll { command.ids.contains($0.id) } }) { self.selection.subtract(command.ids) }
        }
    }
    private func prepareReplacement(_ next: EaselDocument, commit: @escaping () -> Void) {
        let original = session.document, originalSelection = selection
        let owner = window
        let valid = { [weak self, weak owner] in
            guard let self, let owner else { return false }
            return self.window === owner && self.session.document == original
                && self.selection == originalSelection
        }
        if let pageObjects { pageObjects.prepareReplacement(next, valid: valid) { allowed in if allowed && valid() { commit() } } }
        else if valid() { commit() }
    }
    @objc @discardableResult private func duplicateObjects(_ sender: Any?) -> Bool {
        cancelPointerInteraction(); guard finishEditing() else { return false }
        guard let command = command(for: sender), let copies = command.duplicates(in: session.document) else { return false }
        guard commit("Duplicate objects", { $0.items.append(contentsOf: copies) }) else { return false }
        selection = Set(copies.map(\.id)); return true
    }
    @objc @discardableResult private func bringToFront(_ sender: Any?) -> Bool {
        cancelPointerInteraction(); guard finishEditing() else { return false }
        guard let command = command(for: sender),
              (session.document.items.map(\.zIndex).max() ?? 0) <= Int.max - command.originals.count else { return false }
        return commit("Bring to front") { document in
            let maximum = document.items.map(\.zIndex).max() ?? 0
            guard maximum <= Int.max - command.originals.count else { return }
            for (offset, original) in command.originals.enumerated() {
                guard let i = document.items.firstIndex(where: { $0.id == original.id }) else { continue }
                document.items[i].zIndex = maximum + offset + 1; document.items[i].movedToFrontAt = Date()
            }
        }
    }
    @objc func copy(_ sender: Any?) {
        guard let command = command(for: sender), command.originals.count == 1, let item = command.originals.first,
              [.text, .image, .link, .webCard, .browser].contains(item.kind) else { return }
        let pasteboard = NSPasteboard.general
        if let id = item.assetID, let data = try? session.assetData(id) {
            pasteboard.clearContents(); pasteboard.setData(data, forType: .png)
        } else if item.kind == .text {
            do { try EaselStyledText(text: item.text, style: item.resolvedTextStyle, color: item.color, richText: item.richText).write(to: pasteboard) }
            catch { onError?(error) }
        } else { pasteboard.clearContents(); pasteboard.setString(item.url ?? item.text, forType: .string) }
    }
    @objc private func openObjectSource(_ sender: Any?) {
        guard let command = command(for: sender), command.originals.count == 1,
              let raw = command.originals.first?.url, let url = URL(string: raw) else { return }
        onOpenURL?(url)
    }
    @objc private func copyObjectSource(_ sender: Any?) {
        guard let command = command(for: sender), command.originals.count == 1,
              let raw = command.originals.first?.url else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setString(raw, forType: .string) { onError?(CocoaError(.fileWriteUnknown)) }
    }
    @objc func paste(_ sender: Any?) {
        guard hasCurrentMenuOwner(sender) else { return }
        _ = readPasteboard(NSPasteboard.general)
    }
    private func embeddedPageOwnsTextCommand(_ sender: Any?) -> Bool {
        if (sender as? NSMenuItem)?.representedObject is MenuTarget { return false }
        guard let page = WebpageEditCommands.pageTarget(in: window) as? NSView else { return false }
        return page !== self && page.isDescendant(of: self)
    }
    @objc private func pasteAsPlainText(_ sender: Any?) {
        guard hasCurrentMenuOwner(sender) else { return }
        if embeddedPageOwnsTextCommand(sender) { WebpageEditCommands.pasteMatchingStyle(from: sender, in: window); return }
        do {
            if let text = try EaselStyledText.plainText(from: .general) { insert(kind: .text, text: text) }
        } catch { onError?(error) }
    }
    func readPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        var imported = false
        do {
            if let url = try EaselClipboardURL.read(from: pasteboard) {
                if fixedCanvasSize == nil { return insertLink(url.absoluteString) }
                return insert(kind: .text, text: url.absoluteString)
            }
            if let text = try EaselStyledText.read(from: pasteboard) {
                return insert(kind: .text, text: text.text, styledText: text)
            }
            if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) { try importImage(data); return true }
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                for url in urls { try importImageFile(url); imported = true }; return imported
            }
            if let text = try EaselStyledText.plainText(from: pasteboard) { return insert(kind: .text, text: text) }
        } catch { onError?(error) }
        return imported
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if fixedCanvasSize == nil, let operation = contentDrop.begin(sender) { return operation }
        return sender.draggingPasteboard.availableType(from: [EaselStyledText.pasteboardType, EaselStyledText.previousPasteboardType, EaselStyledText.legacyPasteboardType, .rtfd, .rtf, .fileURL, .png, .tiff, .URL, .string]) == nil ? [] : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fixedCanvasSize == nil ? super.draggingUpdated(sender) : draggingEntered(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        fixedCanvasSize == nil ? super.prepareForDragOperation(sender) : !draggingEntered(sender).isEmpty
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if fixedCanvasSize == nil, let result = contentDrop.perform(sender) { return result }
        return readPasteboard(sender.draggingPasteboard)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        cancelPointerInteraction(); guard finishEditing() else { return nil }; window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let item = object(at: point), !selection.contains(item.id) { selection = [item.id]; invalidateIncrementalDisplay(layout: true) }
        return makeObjectMenu()
    }
    private func makeObjectMenu() -> NSMenu {
        let menu = NSMenu()
        menuGeneration &+= 1
        let captured = MenuTarget(window: window, command: EaselObjectCommand(document: session.document, selection: selection), generation: menuGeneration)
        for (title, action) in [("Duplicate", #selector(duplicateObjects)), ("Bring to Front", #selector(bringToFront)), ("Copy", #selector(copy(_:))), ("Paste", #selector(paste)), ("Paste as Plain Text", #selector(pasteAsPlainText)), ("Delete", #selector(deleteObjects))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; item.representedObject = captured; menu.addItem(item)
        }
        if let object = captured.command?.originals.first, captured.command?.originals.count == 1, object.url != nil {
            menu.addItem(.separator())
            if object.kind == .webCard, object.captureLayout != nil {
                let row = NSMenuItem(title: object.liveCapture == true ? "Show Captured Image" : "Make Live",
                    action: #selector(toggleLiveCapture), keyEquivalent: "")
                row.target = self; row.representedObject = captured; menu.addItem(row)
            }
            for (title, action) in [("Open Source", #selector(openObjectSource)), ("Copy Source URL", #selector(copyObjectSource))] {
                let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
                row.target = self; row.representedObject = captured; menu.addItem(row)
            }
        }
        menu.addItem(.separator())
        let alignment = NSMenuItem(title: "Use Alignment Guides", action: #selector(toggleAlignmentGuides), keyEquivalent: "")
        alignment.target = self; alignment.representedObject = captured
        alignment.state = alignmentGuidesEnabled ? .on : .off; menu.addItem(alignment)
        return menu
    }
    func setLiveCapture(_ id: UUID, enabled: Bool) {
        guard fixedCanvasSize == nil, pageObjects != nil,
              let item = session.document.items.first(where: { $0.id == id && $0.kind == .webCard && $0.captureLayout != nil }),
              (item.liveCapture == true) != enabled else { return }
        if enabled && !UserDefaults.standard.bool(forKey: Self.liveCaptureEducationKey) {
            guard liveCaptureEducation == nil, let owner = window, owner.isKeyWindow, owner.attachedSheet == nil else { return }
            let original = session.document, originalSelection = selection
            let alert = ParcDialog(.init(title: "Make it Live",
                message: "See an up-to-date, interactive view of the region you captured. This does not work on all sites. You can always return to the original screenshot with Snapshot.",
                confirm: "Make it Live", cancel: "Cancel"))
            liveCaptureEducation = alert
            _ = alert.begin(for: owner) { [weak self, weak owner, weak alert] response in
                guard let self, let owner, let alert, self.liveCaptureEducation === alert else { return }
                self.liveCaptureEducation = nil
                guard response == .confirm, self.window === owner,
                      self.session.document == original, self.selection == originalSelection else { return }
                UserDefaults.standard.set(true, forKey: Self.liveCaptureEducationKey)
                self.setLiveCapture(id, enabled: true)
            }
            return
        }
        var next = session.document
        guard let index = next.items.firstIndex(where: { $0.id == id }) else { return }
        next.items[index].liveCapture = enabled
        prepareReplacement(next) { [weak self] in
            guard let self else { return }
            self.commit(enabled ? "Make captured region live" : "Show captured image") { $0 = next }
            self.window?.makeFirstResponder(self)
        }
    }
    @objc private func toggleLiveCapture(_ sender: Any?) {
        guard let command = command(for: sender), command.originals.count == 1,
              let item = command.originals.first, item.kind == .webCard, item.captureLayout != nil else { return }
        setLiveCapture(item.id, enabled: item.liveCapture != true)
    }
    @objc private func toggleAlignmentGuides(_ sender: Any?) {
        guard hasCurrentMenuOwner(sender) else { return }
        cancelPointerInteraction(); alignmentGuidesEnabled.toggle(); invalidateIncrementalDisplay()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard hasCurrentMenuOwner(menuItem) else { return false }
        if menuItem.action == #selector(toggleAlignmentGuides) {
            menuItem.state = alignmentGuidesEnabled ? .on : .off; return true
        }
        if menuItem.action == #selector(toggleLiveCapture) {
            return pageObjects != nil && command(for: menuItem)?.originals.first?.captureLayout != nil
        }
        if menuItem.action == #selector(undo) { return canUndo }
        if menuItem.action == #selector(redo) { return canRedo }
        if menuItem.action == #selector(openObjectSource) || menuItem.action == #selector(copyObjectSource) {
            guard let command = command(for: menuItem) else { return false }
            return command.originals.count == 1 && command.originals.first?.url != nil
        }
        if menuItem.action == #selector(copy(_:)) {
            guard let command = command(for: menuItem) else { return false }
            return command.originals.count == 1 && command.originals.allSatisfy { [.text, .image, .link, .webCard, .browser].contains($0.kind) }
        }
        if menuItem.action == #selector(pasteAsPlainText) {
            if embeddedPageOwnsTextCommand(menuItem) { return WebpageEditCommands.canPasteMatchingStyle(menuItem, in: window) }
            return NSPasteboard.general.availableType(from: [.string, .URL, .rtfd, .rtf]) != nil
        }
        if menuItem.action == #selector(paste) || menuItem.action == #selector(selectAll) { return true }
        return command(for: menuItem) != nil
    }
}



@MainActor
private final class EaselExportStrips {
    private static let rowsPerStrip = 256
    private let width: Int, height: Int, rowBytes: Int
    private let draw: (CGContext, Int, Int) -> Void
    private var strip: [UInt8]
    private var stripStart = -1
    private var offset = 0

    private init(width: Int, height: Int, draw: @escaping (CGContext, Int, Int) -> Void) {
        self.width = width; self.height = height; rowBytes = width * 4; self.draw = draw
        strip = [UInt8](repeating: 0, count: width * 4 * Self.rowsPerStrip)
    }

    static func image(width: Int, height: Int, draw: @escaping (CGContext, Int, Int) -> Void) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = Unmanaged.passRetained(EaselExportStrips(width: width, height: height, draw: draw)).toOpaque()
        var callbacks = CGDataProviderSequentialCallbacks(version: 0,
            getBytes: { info, buffer, count in MainActor.assumeIsolated { EaselExportStrips.owner(info).read(into: buffer, count: count) } },
            skipForward: { info, count in MainActor.assumeIsolated { EaselExportStrips.owner(info).skip(count) } },
            rewind: { info in MainActor.assumeIsolated { EaselExportStrips.owner(info).offset = 0 } },
            releaseInfo: { info in if let info { Unmanaged<EaselExportStrips>.fromOpaque(info).release() } })
        guard let provider = CGDataProvider(sequentialInfo: info, callbacks: &callbacks) else {
            Unmanaged<EaselExportStrips>.fromOpaque(info).release(); return nil
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private nonisolated static func owner(_ info: UnsafeMutableRawPointer?) -> EaselExportStrips {
        Unmanaged<EaselExportStrips>.fromOpaque(info!).takeUnretainedValue()
    }

    private func read(into output: UnsafeMutableRawPointer, count: Int) -> Int {
        var written = 0
        while written < count, offset < rowBytes * height {
            let row = offset / rowBytes
            if stripStart < 0 || row < stripStart || row >= stripStart + Self.rowsPerStrip { render(from: row - row % Self.rowsPerStrip) }
            let length = min(count - written, min(stripStart + Self.rowsPerStrip, height) * rowBytes - offset)
            strip.withUnsafeBytes { output.advanced(by: written).copyMemory(from: $0.baseAddress!.advanced(by: offset - stripStart * rowBytes), byteCount: length) }
            written += length; offset += length
        }
        return written
    }

    private func skip(_ count: off_t) -> off_t {
        let skipped = min(Int(count), rowBytes * height - offset)
        offset += skipped
        return off_t(skipped)
    }

    private func render(from first: Int) {
        let rows = min(Self.rowsPerStrip, height - first)
        stripStart = first
        strip.withUnsafeMutableBytes { raw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: raw.baseAddress, width: width, height: rows, bitsPerComponent: 8, bytesPerRow: rowBytes,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.clear(CGRect(x: 0, y: 0, width: width, height: rows))
            draw(context, first, rows)
        }
    }
}

private struct CachedTextLayout {
    let width: CGFloat
    let height: CGFloat
    let text: String
    let rich: EaselRichText?
    let style: EaselTextStyle?
    let color: String
    let layout: EaselTextLayout.Layout
    func matches(_ item: EaselItem, size: NSSize) -> Bool {
        width == size.width && height == size.height && text == item.text
            && rich == item.richText && style == item.textStyle && color == item.color
    }
}

@MainActor
private final class EaselCanvasArtwork: NSView {
    override var wantsDefaultClipping: Bool { false }
    weak var canvas: EaselCanvasView?
    let id: UUID
    init(canvas: EaselCanvasView, id: UUID) { self.canvas = canvas; self.id = id; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = AffineTransform(translationByX: -frame.minX, byY: -frame.minY); (transform as NSAffineTransform).concat()
        canvas?.drawObject(id: id)
    }
}
@MainActor
private final class EaselCanvasDecoration: NSView {
    weak var canvas: EaselCanvasView?
    init(canvas: EaselCanvasView) { self.canvas = canvas; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { canvas?.drawDecorations(in: dirtyRect) }
}

@MainActor
private final class EaselAccessibleObject: NSView {
    weak var canvas: EaselCanvasView?
    let id: UUID
    private var previousItem: EaselItem?
    func updateAccessibilityContent(_ item: EaselItem) {
        let previous = previousItem; previousItem = item
        if let previous, previous.text != item.text || previous.url != item.url || previous.kind != item.kind {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
    init(canvas: EaselCanvasView, id: UUID) {
        self.canvas = canvas; self.id = id
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityIdentifier("easel-object-" + id.uuidString)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { canvas?.accessibleOwnerAvailable == true && canvas?.accessibleItem(id) != nil }
    override func becomeFirstResponder() -> Bool {
        guard let canvas, let item = canvas.accessibleItem(id), canvas.selectAccessibleObject(item) else { return false }
        let result = super.becomeFirstResponder()
        if result { NSAccessibility.post(element: self, notification: .focusedUIElementChanged) }
        return result
    }
    override func keyDown(with event: NSEvent) { canvas?.keyDown(with: event) }
    override func accessibilityLabel() -> String? {
        guard let item = canvas?.accessibleItem(id) else { return nil }
        switch item.kind {
        case .text: return "Text"
        case .webCard: return "Captured webpage"
        case .browser: return "Webpage"
        case .freehand: return "Drawing"
        default: return item.kind.rawValue.capitalized
        }
    }
    override func accessibilityValue() -> Any? {
        guard let item = canvas?.accessibleItem(id) else { return nil }
        return item.text.isEmpty ? item.url : item.text
    }
    override func isAccessibilityEnabled() -> Bool { acceptsFirstResponder }
    override func isAccessibilitySelected() -> Bool { canvas?.accessibleSelected(id) == true }
    override func isAccessibilityFocused() -> Bool { window?.firstResponder === self }
    override func setAccessibilityFocused(_ value: Bool) {
        if value && acceptsFirstResponder { window?.makeFirstResponder(self) }
    }
    override func accessibilityChildren() -> [Any]? { canvas?.accessibleChildren(id) ?? [] }
    override func accessibilityPerformPress() -> Bool {
        guard let canvas, let item = canvas.accessibleItem(id), canvas.selectAccessibleObject(item) else { return false }
        return window?.makeFirstResponder(self) == true
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard let canvas, let item = canvas.accessibleItem(id) else { return false }
        return canvas.showAccessibleMenu(item)
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let canvas, let item = canvas.accessibleItem(id), let owner = window, acceptsFirstResponder else { return [] }
        var names = ["Duplicate", "Bring to front", "Delete"]
        if item.url != nil { names.insert("Open source", at: 0) }
        if item.kind == .text || !canvas.accessibleChildren(id).isEmpty || item.ownsEmbeddedPage { names.insert("Activate", at: 0) }
        return names.map { name in
            NSAccessibilityCustomAction(name: name == "Activate" ? (item.kind == .text ? "Edit text" : "Interact with webpage") : name) { [weak canvas, weak owner] in
                canvas?.accessibleAction(name, item: item, owner: owner) == true
            }
        }
    }
}
