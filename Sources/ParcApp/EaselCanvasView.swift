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
    func snapshotHeader(for item: EaselItem) -> NSView?
}

@MainActor
extension EaselBrowserObjectHosting {
    func focusPage(for id: UUID) -> Bool { false }
    func accessibilitySurface(for id: UUID) -> NSView? { nil }
    func exportSnapshots(within deadline: TimeInterval, _ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void) { completion([:]) }
    func snapshotHeader(for item: EaselItem) -> NSView? { nil }
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
    let session: EaselPageSession
    let pageState = EaselCanvasPageState()
    let boardState = EaselBoardState()
    private var motionInteractionActive = false
    lazy var motion: EaselCanvasMotion = EaselCanvasMotion(owner: self,
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
            self.selectionToolbar?.settle()
            self.imageZoomChanged()
            self.settleObjectMotion()
            self.settleCanvasFeedback()
        })
    weak var pageObjects: EaselBrowserObjectHosting? { didSet { needsLayout = true } }
    var hostedObjects: [EaselHostedObjects] = [] { didSet { needsLayout = true; needsDisplay = true } }
    var artwork: [UUID: NSView] = [:]
    private var accessibleObjects: [UUID: EaselAccessibleObject] = [:]
    var onKeyboardStructureChange: (() -> Void)?
    private var keyboardStructurePending = false
    func keyboardStructureChanged() {
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
    var canvasOwnsKeyFocus: Bool {
        window?.firstResponder === self || (window?.firstResponder as? EaselAccessibleObject)?.canvas === self
    }
    var textEditorOwnsKeyFocus: Bool {
        guard let editor, let responder = window?.firstResponder as? NSView else { return false }
        return responder === editor || responder.isDescendant(of: editor)
    }
    func refreshDecorations() { decoration.needsDisplay = true; needsDisplay = true }
    lazy var decoration = EaselCanvasDecoration(canvas: self)
    private var trackedItems: [UUID: EaselItem] = [:]
    private var trackedSelection = Set<UUID>()
    private var trackedHover: UUID?
    private var trackedMarquee: NSRect?
    private var trackedGuideBounds = NSRect.null
    private var trackedCanvasScale: Double?
    private var trackedHidesAnnotations = false
    private var trackedEditingID: UUID?
    private var trackedEditingCell: EaselTableCoordinate?
    private var trackedHiddenCounts: [UUID: Int] = [:]
    private var trackedChrome = NSRect.null
    private var textLayouts: [UUID: CachedTextLayout] = [:]
    private(set) var presentationNoOpSkipCount = 0
    private(set) var presentationDirtyCount = 0

    private var menuGeneration: UInt64 = 0
    private var subscription: AnyCancellable?
    var selection = Set<UUID>() {
        didSet {
            if selection != oldValue {
                refreshImagePlayback()
                tableSelectionDidChange()
                menuGeneration &+= 1
                NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
                keyboardStructureChanged()
                synchronizePageSelection()
                invalidateIncrementalDisplay(layout: true)
                if arrangeState.enteredGroup != nil { refreshDecorations() }
            }
            refreshTextControls(); updateAccessibilitySummary(); window?.invalidateCursorRects(for: self)
        }
    }
    var draft: [EaselItem]? { didSet { connectors.draftGeneration &+= 1 } }
    var connectors = EaselConnectorCanvasState()
    private var textPreview: [UUID: EaselItem] = [:]
    private var textSizeBadge: (label: String, rect: NSRect)?
    private var objectLinkPopover: NSPopover?
    private var textSizePopover: NSPopover?
    var start: NSPoint?
    var original: [EaselItem] = []
    private var resizeHandle: EaselResizeHandle?
    private var rotationDrag: EaselRotationDrag?
    private var rotationTurn: Double?
    private var rotationDirty = NSRect.null
    var resizing: Bool { resizeHandle != nil }
    private var lastGeometryPoint: NSPoint?
    private var lastDragLocation: NSPoint?
    var dragDistance: CGFloat = 0
    private var geometryEdit: EaselGeometryEdit?
    var selectionBeforeGesture = Set<UUID>()
    var marqueeRect: NSRect?
    private var marqueeEnd: NSPoint?
    private var tentativeSelection: Set<UUID>?
    var hoveredObjectID: UUID?
    var barHoverID: UUID?
    private var appearanceTracking: NSTrackingArea?
    var stroke: [NSPoint] = []
    let brushes = EaselCanvasBrushes()
    private var guides: EaselAlignmentGuides?
    var alignmentGuidesEnabled = true
    let canvasFeedback = EaselCanvasFeedbackState()
    var currentGuideLines: [EaselAlignmentGuides.Line] { (guides?.lines ?? []) + canvasFeedback.sizeLines }
    var arrangeState = EaselCanvasArrangeState() {
        didSet { if arrangeState.enteredGroup != oldValue.enteredGroup { refreshDecorations() } }
    }
    private var lastDragTimestamp: TimeInterval?
    private var dragVelocity = EaselPoint(x: 0, y: 0)
    var editor: EaselStyledTextView?
    var textUndoGroup: UUID?
    var synchronizingEditor = false
    private var finishingEditor = false
    lazy var selectionToolbar: EaselSelectionToolbarPresenting? = Self.selectionToolbarFactory?()
    let codeBlocks = EaselCodeBlockState()
    let objectMotion = EaselCanvasObjectMotionState()
    let onboarding = EaselCanvasOnboardingState()
    private var snapshotHeader: NSView?
    private var snapshotHeaderItem: UUID?
    private var snapshotHeaderDriven = false
    private weak var headerScrollClip: NSClipView?
    private var headerScrollObserver: NSObjectProtocol?
    private var liveCaptureEducation: ParcDialog?
    private static let liveCaptureEducationKey = "easel.liveCaptureEducationSeen"
    var editingID: UUID?
    var editingTextSnapshot: (text: String, rich: EaselRichText?)?
    var tableState = EaselTableCanvasState()
    private var images: [String: NSImage] = [:]
    let imageEditing = EaselImageEditing()
    var onDrawingStateChange: ((Bool) -> Void)?
    var onToolChange: ((EaselTool) -> Void)?
    let toolState = EaselCanvasToolState()
    let stamps = EaselCanvasStampState()
    let mindMaps = EaselMindMapCanvasState()
    var tool: EaselTool = .select {
        didSet {
            if tool != oldValue { cancelPointerInteraction(); keyboardStructureChanged(); toolDidChange() }
            onToolChange?(tool)
            onDrawingStateChange?(drawing)
            window?.invalidateCursorRects(for: self)
        }
    }
    var drawing: Bool {
        get { tool.draws }
        set { tool = newValue ? .marker : .select }
    }
    var fixedCanvasSize: NSSize?
    var viewOnly = false { didSet { if viewOnly != oldValue { keyboardStructureChanged() } } }
    weak var selectionToolbarContainer: NSView?
    var insertionColor = EaselInk.automatic
    var adaptsInk = true {
        didSet {
            guard adaptsInk != oldValue else { return }
            textLayouts.removeAll(); needsDisplay = true
            for view in artwork.values { view.needsDisplay = true }
        }
    }
    var onImageEditingCancel: (() -> Void)?
    func setInsertionColor(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        let hex = EaselInk.canonicalHex(of: color) ?? String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
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
        !session.isDeleted && !session.isClosed && !finishingEditor && editor?.hasMarkedText() != true && codeBlocks.editor?.hasMarkedText() != true &&
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
    func exportImage(backingScale requested: CGFloat, pages: [UUID: EaselPageSnapshot] = [:], hugsContent: Bool = false) -> CGImage? {
        let content = EaselBoardObjects.displayed(session.document.items)
        let width = bounds.width
        var origin = NSPoint.zero
        var size = fixedCanvasSize ?? NSSize(width: width, height: max(width, content.map { EaselCanvasRotation.bounds($0).maxY }.max() ?? 0) + 60)
        if hugsContent, fixedCanvasSize == nil, !content.isEmpty {
            let area = EaselVectorExport.contentBounds(content)
            origin = NSPoint(x: area.x, y: area.y)
            size = NSSize(width: area.width, height: area.height)
        }
        let backingScale = CGFloat(EaselExportScale.capped(Double(requested), width: Double(size.width), height: Double(size.height)))
        let pixels = NSSize(width: (size.width * backingScale).rounded(), height: (size.height * backingScale).rounded())
        guard backingScale > 0, pixels.width >= 1, pixels.height >= 1, pixels.width < 1e9, pixels.height < 1e9 else { return nil }
        for id in content.compactMap(\.assetID) { _ = image(id) }
        let appearance = effectiveAppearance
        let backing: NSColor = NoteTheme.isDark(appearance) ? .black : .white
        return EaselExportStrips.image(width: Int(pixels.width), height: Int(pixels.height)) { [self] context, firstRow, rows in
            let strip = NSRect(x: origin.x, y: origin.y + CGFloat(firstRow) / backingScale, width: size.width, height: CGFloat(rows) / backingScale)
            context.translateBy(x: 0, y: CGFloat(rows)); context.scaleBy(x: backingScale, y: -backingScale)
            context.translateBy(x: -strip.minX, y: -strip.minY)
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
    func exportPDF(title: String, pages: [UUID: EaselPageSnapshot] = [:], only ids: Set<UUID>? = nil) -> Data? {
        let content = EaselBoardObjects.displayed(session.document.items).filter { ids?.contains($0.id) ?? true }
        let area = EaselVectorExport.contentBounds(content)
        let scale = min(1, 14_400 / max(area.width, area.height))
        var box = CGRect(x: 0, y: 0, width: (area.width * scale).rounded(.up), height: (area.height * scale).rounded(.up))
        let data = NSMutableData()
        guard scale.isFinite, scale > 0, let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box,
                                      [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Parc"] as CFDictionary) else { return nil }
        let appearance = effectiveAppearance
        let backing: NSColor = NoteTheme.isDark(appearance) ? .black : .white
        context.beginPDFPage(nil)
        context.translateBy(x: 0, y: box.height); context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -area.x, y: -area.y)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        appearance.performAsCurrentDrawingAppearance {
            backing.setFill(); NSRect(x: area.x, y: area.y, width: area.width, height: area.height).fill()
            for item in content {
                if let page = pages[item.id] { drawLivePage(page, in: rect(item)) } else { drawObject(item, showsEditor: false) }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
    func exportObjectImage(_ item: EaselItem, page: EaselPageSnapshot?, backingScale: CGFloat) -> CGImage? {
        let frame = rect(item)
        let width = Int((frame.width * backingScale).rounded()), height = Int((frame.height * backingScale).rounded())
        guard backingScale.isFinite, backingScale > 0, width > 0, height > 0, width * height <= 64_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: backingScale, y: -backingScale)
        context.translateBy(x: -frame.minX, y: -frame.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let page { drawLivePage(page, in: frame) } else { drawObject(item, showsEditor: false) }
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
    func drawLivePage(_ page: EaselPageSnapshot, in frame: NSRect) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        EaselAppearance.cardFill.setFill(); shape.fill()
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
    static var textCompletionFactory: (@MainActor () -> EaselTextCompletion)?
    var onCopiedImage: (() -> Void)?
    var onExportSelection: ((Set<UUID>, EaselSelectionExportFormat) -> Void)?
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onDrawOverlay: ((NSRect, CGFloat) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { !viewOnly }
    var canAcceptExternalSplitDrop: Bool {
        !session.isDeleted && start == nil && geometryEdit == nil && draft == nil &&
        marqueeRect == nil && editor?.hasMarkedText() != true
    }
    var canUndo: Bool { editor?.localUndo.canUndo == true || session.canUndo }
    var canRedo: Bool { editor?.localUndo.canRedo == true || session.canRedo }
    var items: [EaselItem] {
        let current = session.document
        let displayed: [EaselItem]
        if let geometryEdit, let draft, let preview = geometryEdit.applying(draft, to: current) {
            let settled = settledDragPreview(preview, previous: current, moved: geometryEdit.ids)
            displayed = textPreview.isEmpty ? settled : settled.map { textPreview[$0.id] ?? $0 }
        } else if tool.createsObjects, start != nil, let draft {
            let saved = Set(current.items.map(\.id))
            displayed = current.items + draft.filter { !saved.contains($0.id) }
        }
        else { displayed = current.items }
        return boardState.displayed(tablePreview(mergingConnectorPreview(displayed)))
    }
    var displayedSelection: Set<UUID> { tentativeSelection ?? selection }


    init(session: EaselSession) {
        self.session = EaselPageSession(session)
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 1800))
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Easel canvas")
        registerForDraggedTypes([.URL, EaselStyledText.pasteboardType, EaselStyledText.previousPasteboardType, EaselStyledText.legacyPasteboardType, .rtfd, .rtf, .fileURL, Self.gifPasteboardType, .png, .tiff, .string])
        subscription = session.$document.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.documentDidChange() }
    }
    func documentDidChange() {
        let document = self.session.document
        self.hoveredObjectID = nil
        self.settleStaleFeedback(in: document)
        self.selection.formIntersection(document.items.map(\.id))
        if let edit = self.geometryEdit, !edit.isCurrent(in: document) { self.cancelPointerInteraction() }
        self.imageDocumentChanged()
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
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func setFrameSize(_ newSize: NSSize) {
        if geometryEdit != nil, newSize.width != frame.width { cancelPointerInteraction() }
        super.setFrameSize(newSize)
    }
    @discardableResult override func scrollToVisible(_ rect: NSRect) -> Bool {
        let covered = toolState.coveredBottom / max(CGFloat(magnification), 0.01)
        return super.scrollToVisible(covered > 0 ? NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + covered) : rect)
    }
    func resizeCanvas(viewport: NSSize) {
        if let fixedCanvasSize {
            if frame.size != fixedCanvasSize { setFrameSize(fixedCanvasSize) }
            return
        }
        let viewport = enclosingScrollView?.contentView.bounds.size ?? viewport
        let right = session.document.items.map { EaselCanvasRotation.bounds($0).maxX + 80 }.max() ?? 0
        let covered = toolState.coveredBottom / max(CGFloat(magnification), 0.01)
        let bottom = session.document.items.map { EaselCanvasRotation.bounds($0).maxY + 180 + covered }.max() ?? 0
        let size = NSSize(width: max(viewport.width, right), height: max(viewport.height, 1400, bottom))
        guard !EaselZoom.extentMatches((Double(size.width), Double(size.height)), (Double(frame.width), Double(frame.height))) else { return }
        setFrameSize(size)
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
        let displayed = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for item in session.document.items {
            let node = accessibleObjects[item.id] ?? EaselAccessibleObject(canvas: self, id: item.id)
            accessibleObjects[item.id] = node
            let frame = EaselCanvasRotation.bounds(displayed[item.id] ?? item)
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
        let toolbar = selectionToolbar?.accessibilityToolbar
        let lastSelected = toolbar == nil ? nil : items.last { selection.contains($0.id) && accessibleObjects[$0.id] != nil }?.id
        var result: [Any] = []
        for item in items {
            guard let node = accessibleObjects[item.id] else { continue }
            result.append(node)
            if item.id == lastSelected, let toolbar { result.append(toolbar) }
        }
        if lastSelected == nil, let toolbar { result.append(toolbar) }
        if let snapshotHeader { result.append(snapshotHeader) }
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
        !viewOnly && !session.isDeleted && !session.isClosed && window != nil && window?.attachedSheet == nil && !isHiddenOrHasHiddenAncestor &&
        start == nil && tool == .select && editor?.hasMarkedText() != true
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
        if expected.kind == .section { beginSectionRename(expected.id); return boardState.titleField != nil }
        if expected.kind.holdsText { beginEditing(expected); return editingID == expected.id }
        if expected.kind == .image || expected.kind == .video { return openMedia(expected) }
        if expected.kind == .table { return activateTable(expected) }
        if expected.kind == .code { return beginCodeEditing(expected) }
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
        case "Edit label": beginConnectorLabelEditing(item, at: nil); return editingID == item.id
        case "Add next": return quickCreate(from: item, side: .right)
        case "Bring to front": return bringToFront(sender)
        case "Copy code": return copyCode(item.id)
        case "Change language": return showCodeLanguageMenu(item.id)
        case "Rotate left", "Rotate right":
            guard rotateSelection(by: name == "Rotate left" ? -EaselRotation.largeKeyStep : EaselRotation.largeKeyStep) else { return false }
            announceTurn(of: item.id); return true
        case "Flip horizontal", "Flip vertical": return flipSelection(horizontal: name == "Flip horizontal")
        case "Delete": deleteObjects(sender)
        case "Lock", "Unlock": return toggleLock()
        case "Open source":
            guard onOpenURL != nil else { return false }
            openObjectSource(sender)
        default: return performBoardAction(name, item: item) || performMindMapAction(name, item: item)
        }
        return true
    }
    fileprivate func showAccessibleMenu(_ item: EaselItem) -> Bool {
        guard window?.isKeyWindow == true, selectAccessibleObject(item) else { return false }
        presentContextMenu(at: NSPoint(x: rect(item).minX, y: rect(item).maxY), keyboard: true)
        return true
    }
    private func accessibleManipulationControls() -> [NSAccessibilityElement] {
        guard accessibleOwnerAvailable, editor == nil, let owner = window,
              let edit = EaselGeometryEdit(document: session.document, selection: movableSelection) else { return [] }
        func make(_ label: String, frame: EaselRect, handle: EaselResizeHandle) -> NSAccessibilityElement {
            let node = NSAccessibilityElement()
            node.setAccessibilityRole(.handle); node.setAccessibilityLabel(label); node.setAccessibilityParent(self)
            node.setAccessibilityFrame(owner.convertToScreen(convert(NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height), to: nil)))
            let moves: [(String, Double, Double)] = [("Move left", -1, 0), ("Move right", 1, 0), ("Move up", 0, -1), ("Move down", 0, 1)]
            node.setAccessibilityCustomActions(moves.filter { _, x, y in
                handle.isCorner || (x != 0 ? handle.movesLeft || handle.movesRight : handle.movesTop || handle.movesBottom)
            }.map { name, x, y in
                NSAccessibilityCustomAction(name: name) { [weak self, weak owner] in
                    guard let self, let owner, self.window === owner, self.accessibleOwnerAvailable,
                          self.editor == nil, self.movableSelection == edit.ids, edit.isCurrent(in: self.session.document) else { return false }
                    guard self.showsFrameAnnotation(handle), let bounds = self.resizeBounds,
                          self.handleRect(handle, in: bounds) != nil else { return false }
                    let proposal = edit.preservesAspect(shift: false, command: false)
                        ? edit.resizedPreservingAspect(using: handle, x: x, y: y, centering: [])
                        : edit.resized(using: handle, x: x, y: y, centered: false)
                    let adjusted = self.textGeometry(proposal, edit: edit, handle: handle, centered: false)
                    guard let fitted = adjusted.proposal, let moved = edit.applying(fitted, to: self.session.document) else { return false }
                    let next = adjusted.text.isEmpty ? moved : EaselTextSizing.merging(Array(adjusted.text.values), into: moved)
                    let accepted = self.commit("Resize objects", moved: edit.ids) { $0 = self.fittedTables(next, ids: edit.ids) }
                    if accepted { NSAccessibility.post(element: self, notification: .layoutChanged) }
                    return accepted
                }
            })
            return node
        }
        if selectedConnector != nil { return accessibleConnectorControls(owner: owner) }
        guard let chrome = selectionChrome else { return [] }
        let labels = ["Top left", "Top right", "Bottom left", "Bottom right", "Top", "Left", "Bottom", "Right"]
        return EaselResizeHandle.allCases.compactMap { handle in
            guard showsFrameAnnotation(handle) else { return nil }
            return handleRect(handle, in: chrome.frame).map {
                make("Resize " + labels[handle.rawValue], frame: chrome.transform.bounds(of: $0), handle: handle)
            }
        }
    }
    func rect(_ item: EaselItem) -> NSRect {
        NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
    }
    func color(_ hex: String) -> NSColor { EaselInk.color(hex, adaptive: adaptsInk) }
    func displayedText(_ item: EaselItem) -> NSAttributedString {
        if item.kind == .sticky { return EaselStickyText.presented(item, adaptive: adaptsInk) }
        let value = EaselTextPresentation.displayed(EaselRichTextCodec.attributed(item), for: item)
        return adaptsInk ? EaselInk.adapting(value) : value
    }
    func image(_ id: String) -> NSImage? {
        if let value = images[id] { return value }
        guard let data = try? session.assetData(id), let value = NSImage(data: data) else { return nil }
        images[id] = value; return value
    }
    var usesObjectSurfaces: Bool { (pageObjects != nil && items.contains { $0.ownsEmbeddedPage }) || hostsObjectViews }
    func displayBounds(of item: EaselItem) -> NSRect {
        let pad = 16 / max(canvasScale, 0.2) + 16 + CGFloat(EaselPaintRules.strokeWidth(item)) * 1.5 + boardOverhang(item)
            + CGFloat(EaselObjectLink.badgeAllowance(item, scale: max(canvasScale, 0.2)))
        let visible = EaselShapeGeometry.visualBounds(of: item)
        return EaselCanvasRotation.bounds(item).union(NSRect(x: visible.x, y: visible.y, width: visible.width, height: visible.height))
            .insetBy(dx: -pad, dy: -pad).union(connectorOverhang(item))
    }
    private func guideDirtyBounds() -> NSRect {
        var dirty = NSRect.null
        let pad = 4 / max(canvasScale, 0.2)
        for line in currentGuideLines {
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
        var placed = previous
        placed.frame.x = item.frame.x; placed.frame.y = item.frame.y
        placed.zIndex = item.zIndex; placed.movedToFrontAt = item.movedToFrontAt; placed.capturedAt = item.capturedAt
        return placed != item
    }
    private func cachedTextLayout(for item: EaselItem) -> EaselTextLayout.Layout {
        let box = EaselTextPlacement.box(for: item), size = NSSize(width: box.width, height: box.height)
        if let cached = textLayouts[item.id], cached.matches(item, size: size) { return cached.layout }
        let layout = EaselTextLayout.Layout(displayedText(item), width: size.width, height: size.height, scale: EaselTextLayout.scale(for: item))
        textLayouts[item.id] = CachedTextLayout(width: size.width, height: size.height, text: item.text,
                                                rich: item.richText, style: item.textStyle, color: item.color, layout: layout)
        return layout
    }
    private func rememberPaintedArtwork(chrome: NSRect? = nil) {
        trackedItems = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        trackedSelection = displayedSelection
        trackedHover = hoveredObjectID
        trackedMarquee = marqueeRect
        trackedGuideBounds = guideDirtyBounds()
        trackedCanvasScale = canvasScale
        trackedHidesAnnotations = hidesPassiveAnnotations
        trackedEditingID = paintedEditingID
        trackedEditingCell = paintedEditingCell
        trackedHiddenCounts = hiddenSectionCounts
        trackedChrome = chrome ?? controlChromeBounds
    }
    private var controlChromeBounds: NSRect { mindMapChromeBounds().union(connectorChromeBounds()) }
    private var paintedEditingID: UUID? { editor == nil ? nil : editingID }
    private var paintedEditingCell: EaselTableCoordinate? { paintedEditingID == nil ? nil : tableState.editingCell }
    private var hiddenSectionCounts: [UUID: Int] {
        let all = session.document.items
        var counts: [UUID: Int] = [:]
        for section in all where section.kind == .section && section.contentsHidden == true {
            counts[section.id] = EaselBoardObjects.contents(of: section, in: all).count
        }
        return counts
    }
    private func presentationMatchesPaintedArtwork(chrome: NSRect) -> Bool {
        guard let trackedCanvasScale, trackedCanvasScale == canvasScale,
              trackedHidesAnnotations == hidesPassiveAnnotations,
              trackedEditingID == paintedEditingID,
              trackedEditingCell == paintedEditingCell,
              trackedHover == hoveredObjectID,
              trackedMarquee == marqueeRect,
              trackedSelection == displayedSelection,
              trackedGuideBounds == guideDirtyBounds(),
              trackedChrome == chrome else { return false }
        let current = items
        guard trackedItems.count == current.count else { return false }
        for item in current {
            guard trackedItems[item.id] == item else { return false }
        }
        return true
    }
    func invalidateIncrementalDisplay(layout: Bool = false) {
        if layout { needsLayout = true }
        let chrome = controlChromeBounds
        if presentationMatchesPaintedArtwork(chrome: chrome) {
            presentationNoOpSkipCount += 1
            return
        }
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
                    if displayedSelection.contains(item.id) || item.id == hoveredObjectID
                        || EaselObjectLink.hasLink(item) || EaselObjectLink.hasLink(previous) { overlayChanged = true }
                }
            } else {
                add(displayBounds(of: item))
                artwork[item.id]?.needsDisplay = true
                if displayedSelection.contains(item.id) || item.id == hoveredObjectID { overlayChanged = true }
            }
        }
        if trackedEditingID != paintedEditingID || trackedEditingCell != paintedEditingCell {
            overlayChanged = true
            for id in Set([trackedEditingID, paintedEditingID].compactMap { $0 }) {
                guard let item = current.first(where: { $0.id == id }) ?? trackedItems[id] else { continue }
                add(displayBounds(of: item))
                artwork[id]?.needsDisplay = true
            }
        }
        for (id, count) in hiddenSectionCounts where trackedHiddenCounts[id] != count {
            guard let section = current.first(where: { $0.id == id }) else { continue }
            add(displayBounds(of: section))
            artwork[id]?.needsDisplay = true
        }
        if trackedChrome != chrome {
            overlayChanged = true
            add(trackedChrome)
            add(chrome)
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
        rememberPaintedArtwork(chrome: chrome)
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
    var objectBarHoverOpen: Bool {
        !toolOwnsPointer && start == nil && editor == nil && !session.isClosed && !hidesPassiveAnnotations && window?.isKeyWindow == true
    }
    func updateObjectBarHover(at point: NSPoint?, windowPoint: NSPoint?) {
        var next: UUID?
        if let point, let windowPoint, objectBarHoverOpen, isTopmost(atWindowPoint: windowPoint) {
            if let id = barHoverID, barHoverReach(id).contains(point) { next = id }
            else if let id = hoveredObjectID, items.contains(where: { $0.id == id && ($0.kind == .code || EaselWebItemChrome.isSnapshot($0)) }) { next = id }
        }
        guard next != barHoverID else { return }
        barHoverID = next
        refreshSnapshotHeader()
        refreshCodeBlockChrome(hidden: hidesPassiveAnnotations || !canPresentMotion)
    }
    private func barHoverReach(_ id: UUID) -> NSRect {
        var reach = NSRect.null
        let bar = codeBlocks.bar
        if bar.itemID == id, !bar.isHidden, bar.superview === self { reach = reach.union(bar.frame) }
        if snapshotHeaderItem == id, let snapshotHeader { reach = reach.union(snapshotHeader.frame) }
        return reach
    }
    private func refreshSnapshotHeader() {
        let selected = selection.count == 1 ? items.first { selection.contains($0.id) && EaselWebItemChrome.isSnapshot($0) } : nil
        let hovered = objectBarHoverOpen ? items.first { $0.id == barHoverID && EaselWebItemChrome.isSnapshot($0) } : nil
        let snapshot = hovered ?? selected
        let dragging = start != nil && (dragDistance > 3 || resizing || marqueeRect != nil)
        let hidden = dragging || tool != .select || editor != nil || fixedCanvasSize != nil || motion.isInteracting
        let header = hidden ? nil : snapshot.flatMap { pageObjects?.snapshotHeader(for: $0) }
        let appearing = header != nil && snapshotHeader !== header
        if snapshotHeader !== header {
            let previous = snapshotHeader
            snapshotHeader = header
            if let previous {
                NoteAnimation.fade(previous, visible: false, duration: snapshotHeaderDriven && !hidden ? NoteAnimation.hoverDuration : 0) { [weak self, weak previous] in
                    guard let previous, self?.snapshotHeader !== previous else { return }
                    previous.removeFromSuperview()
                }
            }
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
        snapshotHeaderItem = header == nil ? nil : snapshot?.id
        guard let header else { snapshotHeaderDriven = false; return }
        let driven = snapshot?.id != selected?.id
        if appearing || (snapshotHeaderDriven && !driven) {
            if appearing, driven, header.superview == nil { header.alphaValue = 0 }
            NoteAnimation.fade(header, visible: true, duration: appearing && driven ? NoteAnimation.hoverDuration : 0)
        }
        snapshotHeaderDriven = driven
        bindHeaderScroll()
        positionSnapshotHeader()
        if subviews.last !== header { addSubview(header, positioned: .above, relativeTo: nil) }
    }
    private func positionSnapshotHeader() {
        guard let header = snapshotHeader, let id = snapshotHeaderItem, let item = items.first(where: { $0.id == id }) else { return }
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        let placed = EaselWebItemChrome.headerFrame(item: item.frame,
            visible: EaselRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height))
        let next = NSRect(x: placed.x, y: placed.y, width: placed.width, height: placed.height)
        if header.frame != next { header.frame = next }
    }
    private func bindHeaderScroll() {
        let clip = enclosingScrollView?.contentView
        guard headerScrollClip !== clip || (clip != nil && headerScrollObserver == nil) else { return }
        if let headerScrollObserver { NotificationCenter.default.removeObserver(headerScrollObserver) }
        headerScrollClip = clip; headerScrollObserver = nil
        guard let clip else { return }
        clip.postsBoundsChangedNotifications = true
        headerScrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionSnapshotHeader() }
        }
    }
    private func synchronizePageSelection() {
        let interacting = tool == .select && editor == nil && start == nil && !isHiddenOrHasHiddenAncestor
        pageObjects?.synchronize(items: items, selection: selection, interacting: interacting)
        synchronizeHostedObjects(interacting: interacting)
    }
    override func layout() {
        super.layout(); motion.bind(enclosingScrollView); refreshTextControls(); synchronizeAccessibleObjects()
        layoutVideoSurface()
        refreshSnapshotHeader()
        positionSectionTitleField()
        synchronizePageSelection()
        guard usesObjectSurfaces else {
            artwork.values.forEach { $0.removeFromSuperview() }; artwork.removeAll()
            decoration.removeFromSuperview(); return
        }
        let ids = Set(items.map(\.id))
        for id in Array(artwork.keys) where !ids.contains(id) { retireArtwork(artwork.removeValue(forKey: id), id: id) }
        var ordered: [NSView] = []
        var overlayDirty = decoration.frame != bounds || marqueeRect != nil || guides != nil
        for item in items {
            let objectView: NSView
            if item.ownsEmbeddedPage, let surface = pageObjects?.surface(for: item) { objectView = surface }
            else if let hosted = hostedObjectView(for: item) { objectView = hosted }
            else if let existing = artwork[item.id] as? EaselCanvasArtwork { objectView = existing }
            else { objectView = EaselCanvasArtwork(canvas: self, id: item.id) }
            if let old = artwork[item.id], old !== objectView { old.removeFromSuperview() }
            artwork[item.id] = objectView
            let previous = trackedItems[item.id]
            let nextFrame = item.ownsEmbeddedPage || !(objectView is EaselCanvasArtwork) ? rect(item)
                : displayBounds(of: item).union(EaselCanvasRotation.bounds(item).insetBy(dx: -boardOverhang(item), dy: -boardOverhang(item)))
                    .union(feedbackSurfaceExtent(item))
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
        ordered.append(contentsOf: videoSurfaces)
        ordered.append(decoration)
        if let burst = burstOverlay { ordered.append(burst) }
        if let preview = toolState.previewView { ordered.append(preview) }
        if let editor { ordered.append(editor) }
        if let field = boardState.titleField { ordered.append(field) }
        ordered.append(contentsOf: codeBlockOverlayViews)
        ordered.append(contentsOf: items.compactMap { accessibleObjects[$0.id] })
        if let snapshotHeader { ordered.append(snapshotHeader) }
        if subviews.map(ObjectIdentifier.init) != ordered.map(ObjectIdentifier.init) {
            for view in ordered { addSubview(view, positioned: .above, relativeTo: nil) }
        }
        applySurfaceObjectMotion()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill(using: .copy)
        if !usesObjectSurfaces {
            paintingLive { drawPresentedObjects(in: dirtyRect) }
            drawDecorations(in: dirtyRect)
        }
        rememberPaintedArtwork()
    }
    fileprivate func drawObject(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        paintingLive { drawObject(item) }
    }
    func drawObject(_ item: EaselItem, showsEditor: Bool = true) {
            if item.isEmptyPlaceholder, !showsEditor { return }
            let turned = EaselCanvasRotation.begin(item, straight: showsEditor && editingID == item.id)
            defer { if turned { NSGraphicsContext.restoreGraphicsState() } }
            let r = rect(item), ink = color(item.color)
            ink.setStroke()
            switch item.kind {
            case .text:
                drawText(item, showsEditor: showsEditor)
            case .rectangle, .circle:
                EaselShapeRendering.draw(item, adaptive: adaptsInk)
                drawText(item, showsEditor: showsEditor)
            case .arrow:
                drawConnector(item)
            case .freehand:
                drawDrawing(item)
            case .image: drawImageObject(item, in: r)
            case .video: drawVideoObject(item, in: r, controls: showsEditor)
            case .webCard where item.assetID != nil:
                if let id = item.assetID { image(id)?.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            case .link, .webCard, .browser:
                EaselAppearance.cardFill.setFill(); NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
                EaselAppearance.cardStroke.setStroke(); let border = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10); border.stroke()
                let title = item.text.isEmpty ? (item.url ?? "Link") : item.text
                (title as NSString).draw(in: r.insetBy(dx: 16, dy: 16), withAttributes: [.font: NoteTheme.nunitoBold(17), .foregroundColor: ink])
                ((item.url ?? "") as NSString).draw(in: NSRect(x: r.minX + 16, y: r.maxY - 36, width: r.width - 32, height: 24),
                       withAttributes: [.font: NoteTheme.nunitoRegular(12), .foregroundColor: EaselAppearance.secondaryText])
            case .code: drawCodeBlock(item, showsEditor: showsEditor)
            case .sticky: drawSticky(item, showsEditor: showsEditor)
            case .section: drawSection(item, showsEditor: showsEditor)
            case .table:
                drawTable(item, showsEditor: showsEditor)
            case .stamp:
                EaselStampArtwork.draw(item, in: r, ink: ink)
            case .audio, .file, .pdf, .equation:
                break
            }
    }
    private func drawText(_ item: EaselItem, showsEditor: Bool) {
        if showsEditor, editingID == item.id, let editor {
            guard item.resolvedTextStyle.resolvedFill == .contentHugging, let manager = editor.layoutManager, let container = editor.textContainer else { return }
            let origin = NSPoint(x: editor.frame.minX + editor.textContainerOrigin.x, y: editor.frame.minY + editor.textContainerOrigin.y)
            EaselTextLayout.drawFill(manager: manager, container: container, origin: origin, style: item.resolvedTextStyle)
            return
        }
        guard item.kind == .text || !item.text.isEmpty else { return }
        let layout = cachedTextLayout(for: item), placed = EaselTextPlacement.box(for: item)
        let shown = layout.manager.characterRange(forGlyphRange: layout.manager.glyphRange(for: layout.container), actualGlyphRange: nil)
        let overflowing = EaselTextPlacement.clipsOverflow(item) && NSMaxRange(shown) < layout.storage.length
        let origin = EaselTextPlacement.origin(for: item, textHeight: Double(layout.height), overflowing: overflowing)
        layout.draw(at: NSPoint(x: origin.x, y: origin.y), style: item.resolvedTextStyle)
        if overflowing, showsEditor {
            EaselShapeRendering.drawOverflowMark(in: NSRect(x: placed.x, y: placed.y, width: placed.width, height: placed.height), scale: canvasScale)
        }
    }
    fileprivate func drawDecorations(in dirtyRect: NSRect) {
        onDrawOverlay?(dirtyRect, canvasScale)
        drawBrushOverlay(in: dirtyRect)
        if drawImageDecorations(in: dirtyRect) { return }
        noteObjectChrome()
        for item in items where displayedSelection.contains(item.id) || (item.id == hoveredObjectID && !item.isLocked) {
            if displayBounds(of: item).intersects(dirtyRect) {
                withObjectChrome(opacity: objectChromeOpacity(for: item.id)) { drawSelectionOutline(item, exclusive: displayedSelection == [item.id]) }
            }
        }
        if let frame = resizeBounds, let chrome = selectionChrome {
            let group = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            let pad = 16 / max(canvasScale, 0.2) + 16
            if group.insetBy(dx: -pad, dy: -pad).intersects(dirtyRect) { withObjectChrome(opacity: handleChromeOpacity) {
                if displayedSelection.count > 1 {
                    easelSelectionColor.setStroke()
                    let outline = rotationOutline ?? NSBezierPath(rect: group); outline.lineWidth = 2.5 / canvasScale; outline.stroke()
                }
                for location in EaselResizeHandle.allCases where location.isCorner && showsFrameAnnotation(location) {
                    let point = chrome.point(location)
                    EaselAppearance.drawHandle(at: NSPoint(x: point.x, y: point.y), scale: canvasScale, grow: handleScale(location))
                }
                let sides = EaselTextSizing.sideHandlePoints(in: chrome.frame, items: items.filter { displayedSelection.contains($0.id) })
                NSGraphicsContext.saveGraphicsState()
                if chrome.isTurned { EaselCanvasRotation.affine(chrome.transform).concat() }
                for (location, point) in zip([EaselResizeHandle.left, .right], sides) where showsFrameAnnotation(location) {
                    EaselTextLayout.drawWidthHandle(at: NSPoint(x: point.x, y: point.y), scale: canvasScale)
                }
                NSGraphicsContext.restoreGraphicsState()
            } }
        }
        drawConnectorChrome(in: dirtyRect)
        drawMindMapChrome(in: dirtyRect)
        if let rotationTurn, let point = lastGeometryPoint, rotationDirty.intersects(dirtyRect) {
            EaselCanvasRotation.drawBadge(EaselRotation.turnLabel(rotationTurn), at: point, scale: canvasScale)
        }
        drawTableDecorations(in: dirtyRect)
        if let marqueeRect, marqueeRect.insetBy(dx: -2, dy: -2).intersects(dirtyRect) {
            easelSelectionColor.withAlphaComponent(0.073).setFill(); marqueeRect.fill()
            easelSelectionColor.setStroke()
            let outline = NSBezierPath(rect: marqueeRect); outline.lineWidth = 1 / canvasScale; outline.stroke()
        }
        if guideDirtyBounds().intersects(dirtyRect) { drawGuideLines(currentGuideLines) }
        drawArrangeDecorations(in: dirtyRect)
        for item in items where EaselObjectLink.hasLink(item) {
            let r = EaselObjectLink.badgeRect(for: EaselRotation.bounds(of: item), scale: canvasScale), badge = NSRect(x: r.x, y: r.y, width: r.width, height: r.height)
            if badge.intersects(dirtyRect) { EaselTextLayout.drawLinkBadge(in: badge, scale: canvasScale) }
        }
        if let badge = textSizeBadge, badge.rect.intersects(dirtyRect) { EaselTextLayout.drawSizeBadge(badge.label, in: badge.rect, scale: canvasScale) }
    }
    private func drawSelectionOutline(_ item: EaselItem, exclusive: Bool) {
        let turned = EaselCanvasRotation.begin(item, straight: editingID == item.id)
        defer { if turned { NSGraphicsContext.restoreGraphicsState() } }
        let r = rect(item), path: NSBezierPath
        var width: CGFloat = 2.5
        switch item.kind {
        case .circle, .rectangle: path = EaselShapeRendering.outlinePath(for: item) ?? NSBezierPath(rect: r)
        case .table: path = NSBezierPath(roundedRect: r, xRadius: EaselTableMetrics.cornerRadius, yRadius: EaselTableMetrics.cornerRadius)
        case .section: path = NSBezierPath(roundedRect: r, xRadius: EaselSectionArt.radius, yRadius: EaselSectionArt.radius)
        case .code: path = NSBezierPath(roundedRect: r, xRadius: EaselCodeBlock.cornerRadius, yRadius: EaselCodeBlock.cornerRadius)
        case .arrow:
            drawConnectorOutline(item, exclusive: exclusive); return
        case .freehand:
            if drawBrushSelection(item) { return }
            path = NSBezierPath()
            guard let first = item.points.first else { return }
            path.move(to: NSPoint(x: r.minX + first.x, y: r.minY + first.y))
            for point in item.points.dropFirst() { path.line(to: NSPoint(x: r.minX + point.x, y: r.minY + point.y)) }
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
        let next = !toolOwnsPointer && start == nil && editor == nil && !session.isClosed
            && isTopmost(atWindowPoint: event.locationInWindow)
            ? hoverTarget(at: point, hit: object(at: point) ?? object(at: point, includingLocked: true)) : nil
        if hoveredObjectID != next { hoveredObjectID = next; invalidateIncrementalDisplay(); window?.invalidateCursorRects(for: self) }
        updateObjectBarHover(at: point, windowPoint: event.locationInWindow)
        updateHandleHover(start == nil && !toolOwnsPointer ? resizeHandle(at: point) : nil)
        updateTableHover(at: point)
        updateConnectorHover(at: point)
        updateMindMapHover(at: point)
        updatePlacementPreview(at: isTopmost(atWindowPoint: event.locationInWindow) ? point : nil)
        super.mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) {
        hoveredObjectID = nil; updateObjectBarHover(at: nil, windowPoint: nil); updateHandleHover(nil); updateTableHover(at: nil)
        clearQuickCreateHover(); clearMindMapHover()
        invalidateIncrementalDisplay(); updatePlacementPreview(at: nil); super.mouseExited(with: event)
    }
    private var easelSelectionColor: NSColor {
        EaselAppearance.selection
    }
    var canvasScale: Double {
        let scale = enclosingScrollView?.magnification ?? 1
        return scale.isFinite && scale > 0 ? scale : 1
    }
    var canPresentMotion: Bool { !session.isDeleted && !session.isClosed }
    var hidesPassiveAnnotations: Bool { motion.isInteracting || (geometryEdit != nil && draft != nil) || connectors.travelled }
    private func showsFrameAnnotation(_ handle: EaselResizeHandle) -> Bool {
        allowsFrameHandle(handle) && showsCodeHandle(handle) && !motion.isInteracting && rotationDrag == nil && (!hidesPassiveAnnotations || displayedSelection.count > 1 || resizeHandle == handle)
    }
    func refreshMotionOwnership() {
        if !canPresentMotion || isHiddenOrHasHiddenAncestor || window == nil { motion.cancel(); stopVideoPlayback() }
    }
    private var resizeBounds: EaselRect? {
        guard tool == .select, editor == nil, marqueeRect == nil, selectedConnector == nil, !isCroppingImage else { return nil }
        return EaselGeometryEdit.bounds(of: items.filter { displayedSelection.contains($0.id) && !$0.isLocked })
    }
    private func resizeHandle(at point: NSPoint) -> EaselResizeHandle? {
        guard let chrome = selectionChrome else { return nil }
        let selected = items.filter { displayedSelection.contains($0.id) }
        let local = chrome.local(EaselPoint(x: point.x, y: point.y))
        return EaselTextSizing.handleOrder(for: selected).first { handle in
            guard showsFrameAnnotation(handle), let r = handleRect(handle, in: chrome.frame, items: selected) else { return false }
            return NSRect(x: r.x, y: r.y, width: r.width, height: r.height).contains(NSPoint(x: local.x, y: local.y))
        }
    }
    private var selectionChrome: EaselSelectionChrome? {
        guard let frame = resizeBounds else { return nil }
        return EaselSelectionChrome(frame: frame, items: items.filter { displayedSelection.contains($0.id) && !$0.isLocked })
    }
    private var showsRotateZones: Bool {
        !motion.isInteracting && !hidesPassiveAnnotations && rotationDrag == nil
            && EaselRotation.canRotate(items.filter { displayedSelection.contains($0.id) })
    }
    private func rotateZone(at point: NSPoint) -> EaselResizeHandle? {
        guard showsRotateZones, let chrome = selectionChrome else { return nil }
        return chrome.rotateZone(at: EaselPoint(x: point.x, y: point.y), scale: canvasScale)
    }
    private var rotationOutline: NSBezierPath? {
        guard let drag = rotationDrag, drag.baseRotation == nil, let turn = rotationTurn, let box = geometryEdit?.bounds else { return nil }
        let spin = EaselTransform.rotation(degrees: turn, around: drag.pivot)
        return EaselCanvasRotation.polygonPath(EaselRotation.corners(of: box).map(spin.apply))
    }
    private func invalidateRotationChrome() {
        var next = NSRect.null
        if rotationTurn != nil, let point = lastGeometryPoint { next = EaselCanvasRotation.badgeRect(at: point, scale: canvasScale) }
        if let outline = rotationOutline { next = next.union(outline.bounds) }
        let pad = 8 / max(canvasScale, 0.2) + 8
        if !next.isNull { next = next.insetBy(dx: -pad, dy: -pad) }
        let dirty = rotationDirty.union(next)
        rotationDirty = next
        guard !dirty.isNull else { return }
        if usesObjectSurfaces { decoration.setNeedsDisplay(dirty) } else { setNeedsDisplay(dirty) }
    }
    @discardableResult
    func rotateSelection(by degrees: Double) -> Bool {
        cancelPointerInteraction(); guard finishEditing() else { return false }
        guard let edit = EaselGeometryEdit(document: session.document, selection: movableSelection), edit.canRotate,
              let box = EaselGeometryEdit.bounds(of: edit.originals) else { return false }
        let pivot = edit.originals.count == 1 ? edit.originals.first.map { EaselRotation.center(of: $0.frame) } ?? EaselRotation.center(of: box)
            : EaselRotation.center(of: box)
        guard let turned = edit.rotated(by: degrees, around: pivot), let next = edit.applying(turned, to: session.document) else { return false }
        return commit("Rotate objects", moved: edit.ids) { $0 = next }
    }
    @discardableResult
    func flipSelection(horizontal: Bool) -> Bool {
        cancelPointerInteraction(); guard finishEditing() else { return false }
        guard let edit = EaselGeometryEdit(document: session.document, selection: movableSelection), edit.canFlip,
              let flipped = edit.flipped(horizontally: horizontal), let next = edit.applying(flipped, to: session.document) else { return false }
        return commit(horizontal ? "Flip horizontal" : "Flip vertical", moved: edit.ids) { $0 = next }
    }
    private func handleRect(_ handle: EaselResizeHandle, in frame: EaselRect, items selected: [EaselItem]? = nil) -> EaselRect? {
        EaselTextSizing.handleRect(handle, in: frame, items: selected ?? items.filter { displayedSelection.contains($0.id) }, scale: canvasScale)
    }
    @discardableResult
    func commit(_ name: String, coalescing group: UUID? = nil, moved: Set<UUID> = [],
                _ change: (inout EaselDocument) throws -> Void) -> Bool {
        defer { invalidateIncrementalDisplay(layout: true) }
        do {
            let before = session.document
            try session.perform(name, coalescing: group) { document in
                let previous = document
                try change(&document)
                document = EaselDependents.settle(document, previous: previous, moved: moved)
            }
            noteConnectorStyleChanges(from: before, to: session.document)
            recordObjectMotion(from: before, to: session.document)
            return true
        }
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
        stampRememberedStyle(on: &item)
        if kind == .text, let styledText {
            item.textStyle = styledText.style; item.color = styledText.color; item.richText = styledText.richText
            if fixedCanvasSize != nil { item.textStyle?.autoWidth = nil }
            item.frame = fittedTextFrame(item)
        } else if kind == .text, edit, text.isEmpty, fixedCanvasSize == nil {
            item.textStyle = EaselTextStyle(autoWidth: true)
            item.frame = fittedTextFrame(item)
        }
        if let size = fixedCanvasSize {
            item.frame.width = min(item.frame.width, size.width); item.frame.height = min(item.frame.height, size.height)
            item.frame.x = max(0, min(point == nil ? visibleRect.midX - item.frame.width / 2 : origin.x, size.width - item.frame.width))
            item.frame.y = max(0, min(point == nil ? visibleRect.midY - item.frame.height / 2 : origin.y, size.height - item.frame.height))
        }
        if kind == .arrow { item.points = [EaselPoint(x: 0, y: item.frame.height), EaselPoint(x: item.frame.width, y: 0)] }
        if kind == .arrow, fixedCanvasSize == nil, let style = EaselConnectorCanvasState.styles[session.document.id] { style.apply(to: &item) }
        guard withObjectMotion(.appear, { commit("Add " + (kind == .arrow ? "connector" : kind == .circle ? "ellipse" : kind == .sticky ? "sticky note" : kind.rawValue), { $0.items.append(item) }) }) else { return false }
        selection = [item.id]; window?.makeFirstResponder(self)
        if edit { beginEditing(item) }
        return true
    }
    @discardableResult
    func selectOnly(_ id: UUID) -> Bool {
        guard session.document.items.contains(where: { $0.id == id }) else { return false }
        cancelPointerInteraction(); guard finishEditing() else { return false }; drawing = false
        selection = [id]; invalidateIncrementalDisplay(layout: true)
        return true
    }
    func setOverlayNeedsDisplay(_ rect: NSRect) {
        if usesObjectSurfaces { decoration.setNeedsDisplay(rect) } else { setNeedsDisplay(rect) }
    }
    @discardableResult
    func insertText(at point: NSPoint, width: Double? = nil) -> Bool {
        guard let width, width.isFinite else { return insert(kind: .text, edit: true, at: point) }
        cancelPointerInteraction(); guard finishEditing() else { return false }; drawing = false
        var item = EaselItem(kind: .text, frame: EaselRect(x: max(0, point.x), y: max(0, point.y),
                             width: max(EaselTextSizing.minimumWidth, width), height: 28),
                             zIndex: (session.document.items.map(\.zIndex).max() ?? 0) + 1,
                             text: EaselTextEditing.defaultText, color: insertionColor)
        stampRememberedStyle(on: &item)
        if let size = fixedCanvasSize {
            item.frame.width = min(item.frame.width, size.width)
            item.frame.x = max(0, min(item.frame.x, size.width - item.frame.width))
        }
        item.frame = fittedTextFrame(item)
        if let size = fixedCanvasSize { item.frame.y = max(0, min(item.frame.y, size.height - item.frame.height)) }
        guard commit("Add text", { $0.items.append(item) }) else { return false }
        selection = [item.id]; window?.makeFirstResponder(self)
        beginEditing(item)
        return true
    }
    @discardableResult
    func insertShape(_ shape: EaselShape, in frame: EaselRect? = nil, editing: Bool = false) -> Bool {
        cancelPointerInteraction(); guard finishEditing(), !session.isClosed else { return false }; drawing = false
        let size = EaselShapeGeometry.defaultSize(shape), top = session.document.items.map(\.zIndex).max() ?? 0
        let shown = uncoveredVisibleRect
        var target = frame ?? EaselRect(x: max(24, (shown.midX - size.width / 2).rounded()),
                                         y: max(24, (shown.midY - size.height / 2).rounded()), width: size.width, height: size.height)
        guard top < Int.max, [target.x, target.y, target.width, target.height].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
              target.width >= 1, target.height >= 1 else { return false }
        if frame == nil {
            for _ in 0..<12 where session.document.items.contains(where: { abs($0.frame.x - target.x) < 1 && abs($0.frame.y - target.y) < 1 }) {
                target.x += 24; target.y += 24
            }
        }
        target.x = max(0, target.x); target.y = max(0, target.y)
        if let canvas = fixedCanvasSize {
            target.width = min(target.width, canvas.width); target.height = min(target.height, canvas.height)
            target.x = min(target.x, max(0, canvas.width - target.width)); target.y = min(target.y, max(0, canvas.height - target.height))
        }
        let item = EaselShapeStyle.newItem(shape, frame: target, ink: insertionColor, zIndex: top + 1)
        guard withObjectMotion(.appear, { commit("Add shape", { $0.items.append(item) }) }) else { return false }
        selection = [item.id]; window?.makeFirstResponder(self)
        if editing { beginEditing(item) }
        return true
    }
    var selectedShapes: Set<EaselShape> {
        Set(session.document.items.filter { selection.contains($0.id) }.compactMap(\.resolvedShape))
    }
    @discardableResult
    func changeSelectedShapes(to shape: EaselShape) -> Bool {
        cancelPointerInteraction(); guard finishEditing() else { return false }
        let ids = Set(session.document.items.filter {
            selection.contains($0.id) && $0.resolvedShape != nil && $0.resolvedShape != shape && !$0.isLocked
        }.map(\.id))
        guard !ids.isEmpty else { return false }
        return withObjectMotion(.restyle) { commit("Change shape") { document in
            for index in document.items.indices where ids.contains(document.items[index].id) {
                document.items[index] = EaselShapeGeometry.reshaped(document.items[index], to: shape)
            }
        } }
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
    func importImage(_ data: Data) throws { try insertImageData(data) }
    func importImageFile(_ url: URL) throws { try insertMediaFile(url) }
    func beginEditing(_ item: EaselItem, at point: NSPoint? = nil) {
        guard item.kind.holdsText || item.kind == .arrow, !item.isLocked else { return }
        guard finishEditing(), session.document.items.contains(where: { $0 == item }) else { return }
        editingID = item.id; textUndoGroup = UUID()
        let text = EaselStyledTextView(frame: editingFrame(for: item))
        text.drawsBackground = false; text.isRichText = true; text.importsGraphics = false; text.allowsUndo = true
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.isContinuousSpellCheckingEnabled = true
        text.textContainer?.widthTracksTextView = true
        text.usesEaselObjectLayout = true
        text.onObjectLayoutChanged = { [weak self, weak text] in
            guard let self else { return }
            if let text, self.editor === text, let id = self.editingID,
               let current = self.session.document.items.first(where: { $0.id == id }), EaselTextPlacement.centresVertically(current) {
                self.placeEditor(text, for: current)
            }
            self.invalidateIncrementalDisplay(layout: true)
        }
        text.textContainer?.lineFragmentPadding = EaselTextLayout.fragmentPadding
        text.textContainerInset = EaselTextLayout.inset; text.delegate = self
        text.adaptsInk = adaptsInk
        if adaptsInk { text.caretColor = NoteTheme.caret; text.selectedTextAttributes = [.backgroundColor: NoteTheme.selection] }
        text.setAccessibilityLabel("Easel text")
        if item.kind == .arrow { configureConnectorLabelEditor(text) }
        addSubview(text); editor = text; keyboardStructureChanged()
        text.onClipboardError = { [weak self] in self?.onError?($0) }
        text.onUndoDocument = { [weak self] in self?.undo(nil) }
        text.onRedoDocument = { [weak self] in self?.redo(nil) }
        text.canUndoDocument = { [weak self] in self?.session.canUndo == true }
        text.canRedoDocument = { [weak self] in self?.session.canRedo == true }
        text.onAlign = { [weak self] alignment in _ = self?.alignText(alignment, editing: true) }
        text.completion = Self.textCompletionFactory?()
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
        if item.kind == .table { updateTableCellEditor(item); return }
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
        let target = editorText(for: item)
        EaselTextAttachments.bind(target, container: text.textContainer)
        let current = try? EaselRichTextCodec.snapshot(EaselTextPresentation.stored(text.attributedString(), for: item))
        let desired = try? EaselRichTextCodec.snapshot(EaselTextPresentation.stored(target, for: item))
        if !text.hasLoadedDocument || text.string != item.text || current != desired {
            text.retire()
            text.textStorage?.setAttributedString(target); text.resetEditingHistory()
            if target.length == 0, item.kind == .sticky {
                text.typingAttributes = EaselStickyText.typingAttributes(item, color: color(item.color))
            } else if target.length == 0 {
                text.typingAttributes = EaselTextPresentation.typingAttributes([.font: EaselTextAppearance.font(item.resolvedTextStyle),
                                                                                .foregroundColor: color(item.color)], for: item)
            }
            if target.length == 0, item.kind == .arrow { text.typingAttributes[.paragraphStyle] = Self.centeredParagraph }
        }
        EaselTextPresentation.enforce(item, in: text)
        text.hasLoadedDocument = true
        text.objectStyle = item.resolvedTextStyle; text.objectColor = item.color
        text.fontScale = item.kind == .sticky ? EaselBoardObjects.textScale(item) : 1
        if item.kind == .sticky { EaselStickyText.applyInsets(item, to: text) }
        placeEditor(text, for: item)
        let length = (text.string as NSString).length
        text.selectedRanges = selected.map { value in
            let range = value.rangeValue, start = min(range.location, length)
            return NSValue(range: NSRange(location: start, length: min(range.length, length - start)))
        }
    }
    func placeEditor(_ text: EaselStyledTextView, for item: EaselItem) {
        if item.kind == .arrow {
            let frame = editingFrame(for: item)
            if text.frame != frame { text.frame = frame }
            return
        }
        let placed = EaselTextPlacement.canvasBox(for: item)
        let box = NSRect(x: placed.x, y: placed.y, width: placed.width, height: placed.height)
        guard EaselTextPlacement.centresVertically(item), let manager = text.layoutManager, let container = text.textContainer else {
            if text.frame != box { text.frame = box }
            return
        }
        manager.ensureLayout(for: container)
        let used = ceil(max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY))
        let inset = EaselTextLayout.inset, top = max(inset.height, floor((box.height - used) / 2))
        if text.textContainerInset.height != top { text.textContainerInset = NSSize(width: inset.width, height: top) }
        if text.minSize.height != box.height { text.minSize = NSSize(width: 0, height: box.height) }
        let frame = NSRect(x: box.minX, y: box.minY, width: box.width, height: max(box.height, used + 2 * top))
        if text.frame != frame { text.frame = frame }
    }
    @discardableResult
    func finishEditing(removingEmpty: Bool = true) -> Bool {
        guard finishCodeEditing() else { return false }
        guard !finishingEditor else { return false }
        commitPendingSectionRename()
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
        if removingEmpty, let item = session.document.items.first(where: { $0.id == id }), item.kind == .arrow,
           !item.text.isEmpty, item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard commit("Remove label", coalescing: textUndoGroup, { document in
                guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
                document.items[index].text = ""; document.items[index].richText = nil
            }) else { return false }
        }
        text.retire(); text.delegate = nil
        editor = nil; editingID = nil; textUndoGroup = nil; editingTextSnapshot = nil; connectors.pendingLabel = nil
        text.removeFromSuperview(); refreshTextControls(); invalidateIncrementalDisplay(layout: true); keyboardStructureChanged()
        return true
    }
    private func finishEditingFromEscape() {
        let id = editingID
        guard finishEditing() else { return }
        selection = id.flatMap { id in session.document.items.contains { $0.id == id } ? [id] : nil } ?? []
        window?.makeFirstResponder(self)
    }
    func textDidEndEditing(_ notification: Notification) {
        guard let text = notification.object as? EaselStyledTextView, text === editor, !finishingEditor else { return }
        DispatchQueue.main.async { [weak self, weak text] in
            guard let self, let text, self.editor === text, !text.hasPendingRangeAction,
                  let responder = self.window?.firstResponder, responder !== text else { return }
            if self.selectionToolbar?.owns(responder) == true { return }
            self.finishEditing()
        }
    }
    private func measuredTextHeight(_ item: EaselItem) -> Double {
        if item.kind == .sticky { return EaselStickyText.height(item) }
        let value = item.text.isEmpty ? EaselTextAppearance.attributed(" ", style: item.resolvedTextStyle, color: item.color)
            : EaselTextPresentation.displayed(EaselRichTextCodec.attributed(item), for: item)
        return EaselTextLayout.Layout(value, width: EaselTextPlacement.box(for: item).width).height
    }
    private struct TextFillState {
        let id: UUID
        let style: EaselTextStyle?
    }
    func setTextFill(_ fill: EaselTextStyle.Fill) {
        guard !session.isClosed, editor?.hasMarkedText() != true else { return }
        let selected = session.document.items.filter { selection.contains($0.id) }
        guard !selected.isEmpty, selected.allSatisfy({ $0.kind.holdsText }) else { return }
        let original = selected.map { TextFillState(id: $0.id, style: $0.textStyle) }
        let replacement = selected.map { item -> TextFillState in
            var style = item.resolvedTextStyle; style.fill = fill == .none ? nil : fill
            return TextFillState(id: item.id, style: style)
        }
        applyTextStyles(replacement, replacing: original, editingOwner: editor, name: "Text fill")
        if let editor { window?.makeFirstResponder(editor) }
    }
    private func applyTextStyles(_ replacement: [TextFillState], replacing original: [TextFillState], editingOwner: EaselStyledTextView?, name: String, historyAnchor: EaselDocument? = nil) {
        guard editingOwner == nil || editingOwner === editor,
              editor?.hasMarkedText() != true,
              historyAnchor == nil || session.undoDestination == historyAnchor,
              original.allSatisfy({ state in session.document.items.contains { $0.id == state.id && $0.kind.holdsText && $0.textStyle == state.style } }) else { return }
        guard zip(replacement, original).contains(where: { $0.style != $1.style }) else { return }
        editingOwner?.breakUndoCoalescing()
        let saved = commit(name, coalescing: editingOwner == nil ? nil : textUndoGroup) { document in
            for state in replacement {
                guard let index = document.items.firstIndex(where: { $0.id == state.id }) else { return }
                document.items[index].textStyle = state.style
            }
        }
        if saved, let editingOwner, let anchor = session.undoDestination {
            editingOwner.localUndo.registerUndo(withTarget: editingOwner) { [weak self] owner in
                self?.applyTextStyles(original, replacing: replacement, editingOwner: owner, name: name, historyAnchor: anchor)
            }
            editingOwner.localUndo.setActionName(name)
        }
        refreshTextControls()
    }
    func changeTextStyle(preservingSize: Bool = false, _ mutation: (inout EaselTextStyle) -> Void) {
        guard !session.isClosed else { return }
        if let editor { editor.changeStyle(preservingSize: preservingSize, mutation); refreshTextControls(); return }
        let ids = selection
        guard !ids.isEmpty, items.filter({ ids.contains($0.id) }).allSatisfy({ $0.kind.holdsText }) else { return }
        withObjectMotion(.restyle) { commit("Style text") { document in
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
                document.items[index].frame = fittedFrame(document.items[index])
            }
        } }
        refreshTextControls()
    }
    func resizeText(by delta: Int) { changeTextStyle { $0 = EaselTextSizing.stepped($0, by: delta) ?? $0 } }
    func applyParagraph(_ kind: EaselParagraphEditing.Kind) {
        guard !session.isClosed else { return }
        editor?.changeParagraph(kind); refreshTextControls()
    }
    func applyEmphasis(_ emphasis: EaselStyledTextView.Emphasis) {
        guard !session.isClosed else { return }
        editor?.toggle(emphasis); refreshTextControls()
    }
    func editLink(relativeTo anchor: NSView, rect: NSRect? = nil) {
        guard !session.isClosed else { return }
        editor?.editLink(relativeTo: anchor, rect: rect)
    }
    private var formattingEditor: EaselStyledTextView? {
        guard let editor, let window, window.isKeyWindow, window.attachedSheet == nil,
              !session.isClosed, !session.isDeleted else { return nil }
        let responder = window.firstResponder
        guard responder === editor || selectionToolbar?.owns(responder) == true else { return nil }
        return editor
    }
    private func canFormat(_ command: TextFormatCommand) -> Bool {
        if command == .bigger || command == .smaller {
            guard let window, window.isKeyWindow, window.attachedSheet == nil, !session.isClosed, !session.isDeleted else { return false }
            let responder = window.firstResponder
            let selected = session.document.items.filter { selection.contains($0.id) }
            let canvasFocus = responder === self || (responder as? EaselAccessibleObject)?.canvas === self
                || selectionToolbar?.owns(responder) == true
            guard !hidesPassiveAnnotations, !selected.isEmpty, selected.allSatisfy({ $0.kind.holdsText }),
                  formattingEditor != nil || (editor == nil && canvasFocus) else { return false }
            return EaselTextStyleState.canResize(by: command == .bigger ? 1 : -1, styles: selected.map(\.resolvedTextStyle), editor: editor)
        }
        if command == .link, editor == nil { return objectLinkTarget != nil }
        guard let editor = formattingEditor, editor.isEditable, !editor.hasMarkedText() else { return false }
        if editingLabel { return command == .bold || command == .strikethrough }
        switch command {
        case .increaseIndent, .decreaseIndent: return editor.canChangeListIndent(outdent: command == .decreaseIndent)
        case .link: return editor.selectedRange().length > 0
        default: return command.paragraph == nil || editor.selectedRanges.count == 1
        }
    }
    @objc func formatText(_ sender: Any?) {
        if let command = TextFormatCommand(sender), performTableFormat(command) { return }
        guard let command = TextFormatCommand(sender), canFormat(command) else { return }
        switch command {
        case .bigger, .smaller: resizeText(by: command == .bigger ? 1 : -1)
        case .increaseIndent, .decreaseIndent:
            _ = editor?.changeListIndent(outdent: command == .decreaseIndent); refreshTextControls()
        case .link:
            if let editor { editLink(relativeTo: editor, rect: editor.revealedSelectionRect()) } else { editObjectLink() }
        default:
            if let emphasis = command.emphasis { applyEmphasis(emphasis) }
            if let kind = command.paragraph { applyParagraph(kind) }
        }
    }
    func refreshTextControls() {
        refreshCodeBlockChrome(hidden: hidesPassiveAnnotations || !canPresentMotion)
        refreshSelectionToolbar()
        refreshOnboarding()
    }
    func textDidChange(_ notification: Notification) {
        if tableCellTextDidChange(notification) { return }
        guard !synchronizingEditor, let id = editingID, let text = editor,
              notification.object as? EaselStyledTextView === text else { return }
        guard !text.hasMarkedText() else { fitComposingEditor(text, id: id); return }
        guard let item = session.document.items.first(where: { $0.id == id && ($0.kind.holdsText || $0.kind == .arrow) }) else { return }
        if let previous = editingTextSnapshot, item.text != previous.text || item.richText != previous.rich {
            updateEditor(item); return
        }
        EaselTextPresentation.enforce(item, in: text)
        let payload: EaselStyledText
        let authored = item.kind == .sticky ? EaselStickyText.stored(text.attributedString(), for: item)
            : EaselTextPresentation.stored(text.attributedString(), for: item)
        do { payload = try EaselStyledText.capture(authored, style: text.objectStyle, color: text.objectColor) }
        catch { onError?(error); if let item = session.document.items.first(where: { $0.id == id }) { updateEditor(item) }; return }
        let saved = commit("Edit text", coalescing: textUndoGroup) { document in
            guard let i = document.items.firstIndex(where: { $0.id == id }) else { return }
            document.items[i].text = payload.text; document.items[i].richText = payload.richText
            document.items[i].frame = fittedFrame(document.items[i])
            if let pending = self.connectors.pendingLabel, pending.id == id, document.items[i].kind == .arrow {
                let filled = !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                document.items[i].labelPosition = filled ? pending.position : pending.original
            }
        }
        if saved {
            editingTextSnapshot = (payload.text, payload.richText)
        }
        else if let item = session.document.items.first(where: { $0.id == id }) { updateEditor(item) }
        if editor === text, let current = session.document.items.first(where: { $0.id == id }) { placeEditor(text, for: current) }
    }
    private func textMeasure(_ item: EaselItem) -> NSAttributedString {
        item.text.isEmpty ? EaselTextAppearance.attributed(" ", style: item.resolvedTextStyle, color: item.color) : EaselRichTextCodec.attributed(item)
    }
    private func fittedFrame(_ item: EaselItem) -> EaselRect {
        if item.kind == .text { return fittedTextFrame(item) }
        guard let height = EaselTextPlacement.fittedFrameHeight(item, textHeight: measuredTextHeight(item)) else { return item.frame }
        var frame = item.frame
        frame.height = height
        return frame
    }
    func fittedTextFrame(_ item: EaselItem, measuring value: NSAttributedString? = nil) -> EaselRect {
        let value = value ?? textMeasure(item)
        let natural = EaselTextSizing.isAutoWidth(item) ? Double(EaselTextLayout.naturalWidth(value)) : 0
        return EaselTextSizing.fittedFrame(item, naturalWidth: natural) { Double(EaselTextLayout.Layout(value, width: $0).height) }
    }
    private func fitComposingEditor(_ text: EaselStyledTextView, id: UUID) {
        guard let item = session.document.items.first(where: { $0.id == id }), EaselTextSizing.isAutoWidth(item) else { return }
        let frame = fittedTextFrame(item, measuring: text.attributedString())
        text.frame = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }
    @discardableResult
    func alignText(_ alignment: EaselTextStyle.Alignment, editing: Bool = false) -> Bool {
        guard !session.isClosed, !session.isDeleted, editor?.hasMarkedText() != true else { return false }
        let ids: Set<UUID> = editingID.map { [$0] } ?? selection
        let targets = session.document.items.filter { ids.contains($0.id) }
        guard EaselTextSizing.canAlign(targets) else { return false }
        if let next = EaselTextSizing.aligning(session.document, ids: ids, to: alignment) {
            let changed = next.items.filter { item in targets.contains { $0.id == item.id && $0.textStyle != item.textStyle } }
            let original = targets.filter { item in changed.contains { $0.id == item.id } }.map { TextFillState(id: $0.id, style: $0.textStyle) }
            let replacement = original.map { state in TextFillState(id: state.id, style: changed.first { $0.id == state.id }?.textStyle) }
            applyTextStyles(replacement, replacing: original, editingOwner: editor, name: "Align text")
        }
        if let editor { window?.makeFirstResponder(editor) }
        return true
    }
    var objectLinkTarget: EaselItem? {
        guard editor == nil, !isCaptureBoard, let window, window.isKeyWindow, window.attachedSheet == nil, !session.isClosed, !session.isDeleted,
              !hidesPassiveAnnotations, selection.count == 1,
              let item = session.document.items.first(where: { selection.contains($0.id) }),
              EaselObjectLink.canLink(item), !item.isLocked else { return nil }
        let responder = window.firstResponder
        guard responder === self || (responder as? EaselAccessibleObject)?.canvas === self
                || selectionToolbar?.owns(responder) == true else { return nil }
        return item
    }
    @discardableResult
    func editObjectLink(relativeTo anchor: NSView? = nil) -> Bool {
        guard let target = objectLinkTarget else { return false }
        objectLinkPopover?.close()
        let controller = EaselLinkEditor(value: target.url ?? "", webOnly: true)
        let popover = NSPopover(); popover.behavior = .transient; popover.contentViewController = controller
        controller.onCommit = { [weak self, weak popover] link in
            popover?.close()
            guard let self, self.session.document.items.contains(target),
                  let next = EaselObjectLink.linking(self.session.document, id: target.id, to: link) else { return }
            self.commit(link == nil ? "Remove link" : target.url == nil ? "Add link" : "Edit link") { document in
                guard document.items.contains(target) else { return }
                document = next
            }
        }
        objectLinkPopover = popover
        let badge = EaselObjectLink.badgeRect(for: target.frame, scale: canvasScale)
        let host = anchor ?? self
        let place = anchor == nil ? NSRect(x: badge.x, y: badge.y, width: badge.width, height: badge.height) : host.bounds
        popover.show(relativeTo: place, of: host, preferredEdge: host.isFlipped ? .maxY : .minY)
        return true
    }
    @discardableResult
    func removeObjectLink() -> Bool {
        guard let target = objectLinkTarget, target.url != nil,
              let next = EaselObjectLink.linking(session.document, id: target.id, to: nil) else { return false }
        return commit("Remove link") { $0 = next }
    }
    var textAlignmentState: EaselTextStyle.Alignment? {
        let ids: Set<UUID> = editingID.map { [$0] } ?? selection
        return EaselTextSizing.sharedAlignment(session.document.items.filter { ids.contains($0.id) })
    }
    @discardableResult
    func restoreTextAutoWidth() -> Bool {
        guard !session.isClosed, editor == nil, fixedCanvasSize == nil else { return false }
        let changes = session.document.items.filter { selection.contains($0.id) }.compactMap { item -> EaselItem? in
            let value = textMeasure(item)
            return EaselTextSizing.autoWidthFrame(item, naturalWidth: Double(EaselTextLayout.naturalWidth(value))) {
                Double(EaselTextLayout.Layout(value, width: $0).height)
            }
        }
        guard !changes.isEmpty else { return false }
        let originals = session.document.items.filter { item in changes.contains { $0.id == item.id } }
        return commit("Auto width") { document in
            guard originals.allSatisfy({ original in document.items.contains(original) }) else { return }
            document = EaselTextSizing.merging(changes, into: document)
        }
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
        if tableTextCommand(textView, commandSelector) { return true }
        if mindMapTextCommand(textView, commandSelector) { return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), textView === editor {
            finishEditingFromEscape()
            return true
        }
        return false
    }
    func cancelPointerInteraction() {
        dropCarriedObjects()
        abandonDuplicateDrag()
        let hadPointerOwner = start != nil || geometryEdit != nil || draft != nil || marqueeRect != nil
        cancelTableInteraction()
        if !stroke.isEmpty, start != nil { selection = selectionBeforeGesture.intersection(session.document.items.map(\.id)) }
        draft = nil; textPreview = [:]; start = nil; original = []; stroke = []; geometryEdit = nil
        marqueeRect = nil; marqueeEnd = nil; tentativeSelection = nil
        selectionBeforeGesture = []; resizeHandle = nil; guides = nil
        resetSnapFeedback()
        resetSectionGesture()
        cancelConnectorGesture()
        rotationDrag = nil; rotationTurn = nil; invalidateRotationChrome()
        lastDragTimestamp = nil; dragVelocity = .init(x: 0, y: 0)
        lastGeometryPoint = nil; lastDragLocation = nil; dragDistance = 0
        updateTextSizeBadge()
        cancelBrushStroke()
        cancelToolGesture()
        clearMindMapDrop()
        if hadPointerOwner { synchronizePageSelection(); keyboardStructureChanged() }
        window?.invalidateCursorRects(for: self)
        invalidateIncrementalDisplay(layout: true)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        }
        if newWindow !== window {
            hoveredObjectID = nil; menuGeneration &+= 1; motion.cancel(); settleObjectMotion(); cancelPointerInteraction(); releaseTemporaryHand(); stopZoomAnimation()
            settleCanvasFeedback()
            stopVideoPlayback(); finishImageCrop(save: true); stopImagePlayback()
            if newWindow != nil { DispatchQueue.main.async { [weak self] in self?.refreshImagePlayback() } }
        }
        if newWindow !== window { selectionToolbar?.detach(); dismissStampPanels(animated: false) }
        if let newWindow {
            NotificationCenter.default.addObserver(self, selector: #selector(ownerResignedKey),
                                                   name: NSWindow.didResignKeyNotification, object: newWindow)
            NotificationCenter.default.addObserver(self, selector: #selector(ownerResignedKey),
                                                   name: NSWindow.willCloseNotification, object: newWindow)
        }
        super.viewWillMove(toWindow: newWindow)
    }
    @objc private func ownerResignedKey(_ notification: Notification) {
        dismissStampPanels(animated: false); hoveredObjectID = nil; clearQuickCreateHover(); clearMindMapHover()
        menuGeneration &+= 1; motion.cancel(); cancelPointerInteraction(); releaseTemporaryHand()
    }
    override func resignFirstResponder() -> Bool {
        menuGeneration &+= 1; cancelPointerInteraction(); finishImageCrop(save: true); releaseTemporaryHand(); return super.resignFirstResponder()
    }
    private func updateMarquee(to point: NSPoint, flags: NSEvent.ModifierFlags) {
        guard let start, marqueeRect != nil else { return }
        let rect = EaselCanvasSelection.marquee(from: .init(x: start.x, y: start.y), to: .init(x: point.x, y: point.y))
        marqueeRect = NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height); marqueeEnd = point
        let operation: EaselCanvasSelection.Operation = flags.contains(.shift) ? .add : flags.contains(.command) ? .subtract : .replace
        tentativeSelection = marqueeSelection(in: rect, items: marqueeItems(in: rect), original: selectionBeforeGesture, operation: operation)
        invalidateIncrementalDisplay()
    }
    override func flagsChanged(with event: NSEvent) {
        if let end = marqueeEnd { updateMarquee(to: end, flags: event.modifierFlags) }
        else if geometryEdit != nil, let point = lastGeometryPoint { updateGeometry(to: point, flags: event.modifierFlags) }
        else { refreshBrushStroke(flags: event.modifierFlags); refreshToolGesture(flags: event.modifierFlags) }
        super.flagsChanged(with: event)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard usesObjectSurfaces, let hit, hit !== self else { return hit }
        if let snapshotHeader, hit === snapshotHeader || hit.isDescendant(of: snapshotHeader) { return hit }
        if hit === editor || editor.map({ hit.isDescendant(of: $0) }) == true || ownsCodeBlockView(hit) { return hit }
        if let field = boardState.titleField, hit === field || hit.isDescendant(of: field) { return hit }
        if videoSurfaceHit(hit) { return hit }
        let local = convert(point, from: superview)
        guard tool == .select, !toolState.spaceHeld, resizeHandle(at: local) == nil, connectorChrome(at: local) == nil,
              let item = object(at: local, includingLocked: true), item.ownsEmbeddedPage, selection == [item.id],
              let surface = artwork[item.id], hit === surface || hit.isDescendant(of: surface) else { return self }
        return hit
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { presentContextMenu(for: event); return }
        if imageMouseDown(event) { return }
        if tableMouseDown(with: event) { return }
        hoveredObjectID = nil
        settleCanvasFeedback()
        motion.cancel(); cancelPointerInteraction(); guard finishEditing() else { return }; window?.makeFirstResponder(self)
        if beginNavigationGesture(event) { return }
        let point = convert(event.locationInWindow, from: nil); start = point; original = session.document.items
        selectionBeforeGesture = selection; lastDragLocation = event.locationInWindow; lastDragTimestamp = event.timestamp
        noteLockedPress(at: point)
        if drawing { beginBrushStroke(tool.brush ?? .marker, at: point, flags: event.modifierFlags); return }
        if tool == .eraser { beginErasing(at: point); return }
        if beginToolGesture(at: point, event: event) { return }
        if offerUnlock(at: point) { cancelPointerInteraction(); return }
        if mindMapControlPress(at: point) { cancelPointerInteraction(); return }
        if beginConnectorGesture(at: point, event: event) { return }
        if let handle = resizeHandle(at: point) {
            if event.clickCount == 2, EaselTextSizing.setsTextWidth(handle), restoreTextAutoWidth() { cancelPointerInteraction(); return }
            resizeHandle = handle
            beginGeometry()
            lastGeometryPoint = point; invalidateIncrementalDisplay(layout: true); return
        }
        if let linked = EaselObjectLink.item(at: .init(x: point.x, y: point.y), in: items, scale: canvasScale),
           let url = EaselObjectLink.link(of: linked), let onOpenURL {
            cancelPointerInteraction(); onOpenURL(url); return
        }
        if rotateZone(at: point) != nil,
           let drag = EaselRotationDrag(items: items.filter { movableSelection.contains($0.id) }, pointer: EaselPoint(x: point.x, y: point.y)) {
            rotationDrag = drag; beginGeometry(); primeRotationSnap(drag.baseRotation ?? 0)
            lastGeometryPoint = point; invalidateIncrementalDisplay(layout: true); return
        }
        var hit = object(at: point, includingLocked: event.modifierFlags.contains(.shift))
        switch sectionPress(at: point, hit: hit, event: event) {
        case .handled: return
        case .object(let section): hit = section
        case .marquee: hit = nil
        case .none: break
        }
        guard let hit else {
            if event.clickCount == 2 { insert(kind: .text, edit: true, at: point); return }
            marqueeRect = NSRect(origin: point, size: .zero); updateMarquee(to: point, flags: event.modifierFlags); return
        }
        let adds = event.modifierFlags.contains(.command) && !selection.contains(hit.id)
        let enteredGroup = selectForClick(hit, extending: event.modifierFlags.contains(.shift) || adds, clickCount: event.clickCount)
        guard selection.contains(hit.id) else { cancelPointerInteraction(); return }
        beginGeometry()
        arrangeState.duplicateDragArmed = event.modifierFlags.contains(.option) && !hit.isLocked
        if event.clickCount == 2, !enteredGroup {
            cancelPointerInteraction()
            if hit.kind.holdsText { beginEditing(hit, at: point) }
            else if hit.kind == .image || hit.kind == .video { openMedia(hit) }
            else if hit.kind == .code { beginCodeEditing(hit, at: point) }
            else if !hit.ownsEmbeddedPage, let raw = hit.url, let url = URL(string: raw) { onOpenURL?(url) }
        }
        invalidateIncrementalDisplay(layout: true)
    }
    override func mouseDragged(with event: NSEvent) {
        if continueNavigationGesture(event) { return }
        if imageMouseDragged(event) { return }
        if tableMouseDragged(with: event) { return }
        guard start != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if continueConnectorGesture(to: point, event: event) { return }
        if marqueeRect != nil { refuseLockedDrag(to: point); updateMarquee(to: point, flags: event.modifierFlags); autoscroll(with: event); return }
        if drawing { dragBrushStroke(to: point, flags: event.modifierFlags); return }
        if tool == .eraser { continueErasing(to: point); autoscroll(with: event); return }
        if continueToolGesture(at: point, event: event) { return }
        recordDragTravel(event.locationInWindow, timestamp: event.timestamp)
        if arrangeState.duplicateDragArmed, dragDistance > 3, !resizing, beginDuplicateDrag() { beginGeometry() }
        updateGeometry(to: point, flags: event.modifierFlags)
        carryDraggedObjects(rotating: rotationDrag != nil, velocity: dragVelocity); refuseLockedDrag(to: point)
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
    func object(at point: NSPoint, includingLocked: Bool = false) -> EaselItem? {
        items.reversed().first { item in
            guard includingLocked || !item.isLocked else { return false }
            if item.kind == .arrow { return connectorContains(point, item: item) }
            return EaselContentHitTest.contains(.init(x: point.x, y: point.y), item: item, selected: selection.contains(item.id))
        }
    }
    private func beginGeometry() {
        geometryEdit = EaselGeometryEdit(document: session.document, selection: movableSelection)
        if let edit = geometryEdit {
            let v = visibleRect
            guides = EaselAlignmentGuides(edit: edit, items: session.document.items,
                viewport: .init(x: v.minX, y: v.minY, width: v.width, height: v.height), canvasWidth: bounds.width, scale: canvasScale)
        }
    }
    private func updateGeometry(to point: NSPoint, flags: NSEvent.ModifierFlags) {
        guard let start else { return }
        lastGeometryPoint = point
        guard let edit = geometryEdit, edit.ids == movableSelection, edit.isCurrent(in: session.document),
              guides?.matchesCanvas(width: bounds.width) == true else {
            cancelPointerInteraction(); return
        }
        if let drag = rotationDrag {
            let pointer = EaselPoint(x: point.x, y: point.y)
            guard let delta = drag.delta(to: pointer, free: flags.contains(.command)),
                  let turned = edit.rotated(by: delta, around: drag.pivot) else { return }
            draft = turned
            rotationTurn = drag.baseRotation.map { EaselRotation.normalized($0 + delta) } ?? EaselRotation.normalized(delta)
            noteRotationSnap(flags.contains(.command) ? nil : rotationTurn)
            EaselCanvasRotation.cursor(toward: EaselPoint(x: pointer.x - drag.pivot.x, y: pointer.y - drag.pivot.y)).set()
            invalidateRotationChrome(); invalidateIncrementalDisplay(layout: true); return
        }
        let translation = EaselArrange.axisLocked(EaselPoint(x: point.x - start.x, y: point.y - start.y),
                                                  when: flags.contains(.shift) && resizeHandle == nil)
        var intrinsicGuideRatio: Double?
        if flags.contains(.shift), edit.originals.count == 1, let item = edit.originals.first {
            switch item.kind {
            case .image, .webCard:
                if item.kind == .image, let aspect = imageAspect(item) { intrinsicGuideRatio = aspect }
                else if let asset = item.assetID, let size = image(asset)?.size,
                   size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 {
                    intrinsicGuideRatio = size.width / size.height
                } else if item.kind == .webCard { intrinsicGuideRatio = 1 }
            case .link: intrinsicGuideRatio = 220.0 / 160.0
            default: break
            }
        }
        let scalingText = EaselTextSizing.scalesText(edit.originals, handle: resizeHandle)
        let proposal = guides?.proposal(edit: edit, document: session.document, translation: translation,
                                     velocity: dragVelocity, scale: canvasScale, handle: resizeHandle, centered: flags.contains(.option),
                                     enabled: alignmentGuidesEnabled && !flags.contains(.command) && !scalingText,
                                     preserveAspect: scalingText || edit.preservesAspect(shift: flags.contains(.shift), command: flags.contains(.command)),
                                     aspectGuideRatio: intrinsicGuideRatio, viewport: .init(x: visibleRect.minX, y: visibleRect.minY,
                                                     width: visibleRect.width, height: visibleRect.height))
        let sized = equalSizeSnap(proposal, edit: edit, handle: resizeHandle, centered: flags.contains(.option),
                                  enabled: alignmentGuidesEnabled && !flags.contains(.command) && !scalingText
                                      && !edit.preservesAspect(shift: flags.contains(.shift), command: flags.contains(.command)))
        noteGuideFeedback(currentGuideLines)
        (draft, textPreview) = textGeometry(sized, edit: edit, handle: resizeHandle, centered: flags.contains(.option))
        if let proposal = draft { draft = fittedBoardGeometry(proposal, edit: edit, handle: resizeHandle) }
        draft = settledCodeBlocks(draft, edit: edit)
        for item in draft ?? [] where textPreview[item.id] != nil { textPreview[item.id]?.frame = item.frame }
        let dragged = resizeHandle == nil && edit.ids.count == 1 ? draft?.first(where: { edit.ids.contains($0.id) }) : nil
        refreshMindMapDrop(id: dragged?.id, frame: dragged?.frame, pointer: point)
        noteSectionCarry(resizeHandle == nil ? draft : nil, originals: edit.originals)
        updateTextSizeBadge()
        window?.invalidateCursorRects(for: self); invalidateIncrementalDisplay(layout: true)
    }
    private func textGeometry(_ proposal: [EaselItem]?, edit: EaselGeometryEdit, handle: EaselResizeHandle?,
                              centered: Bool) -> (proposal: [EaselItem]?, text: [UUID: EaselItem]) {
        let scaling = EaselTextSizing.scalesText(edit.originals, handle: handle)
        guard var proposal, let handle, scaling || EaselTextSizing.setsTextWidth(handle) else { return (proposal, [:]) }
        let originals = Dictionary(edit.originals.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let board = fixedCanvasSize.map { EaselRect(x: 0, y: 0, width: Double($0.width), height: Double($0.height)) }
        var changes: [UUID: EaselItem] = [:]
        for index in proposal.indices {
            guard let original = originals[proposal[index].id], original.kind == .text else { continue }
            var next: EaselItem
            if scaling {
                let proposed = proposal[index].frame
                func scale(_ factor: Double) -> EaselItem? {
                    guard var scaled = EaselTextSizing.scaled(original, factor: factor) else { return nil }
                    let value = textMeasure(scaled)
                    let natural = EaselTextSizing.isAutoWidth(scaled) ? Double(EaselTextLayout.naturalWidth(value)) : 0
                    scaled.frame = EaselTextSizing.scaledFrame(scaled, original: original.frame, proposed: proposed, handle: handle,
                                                               centered: centered, single: edit.originals.count == 1, naturalWidth: natural) {
                        Double(EaselTextLayout.Layout(value, width: $0).height)
                    }
                    return scaled
                }
                var factor = original.frame.width > 0 ? proposed.width / original.frame.width : 1
                guard var scaled = scale(factor) else { continue }
                if let board {
                    for _ in 0..<4 where !EaselTextSizing.fits(scaled.frame, in: board) {
                        factor *= min(board.width / scaled.frame.width, board.height / scaled.frame.height)
                        guard let smaller = scale(factor), smaller != scaled else { break }
                        scaled = smaller
                    }
                }
                next = scaled
                if edit.resizesRotated { next.frame = EaselRotation.recentred(original, frame: next.frame) }
            } else {
                var item = original
                item.frame = edit.resizesRotated ? EaselRotation.localFrame(original, from: proposal[index].frame) : proposal[index].frame
                if let board, item.frame.width > board.width { item.frame.width = board.width }
                let value = textMeasure(item)
                next = EaselTextSizing.widthResized(item) { Double(EaselTextLayout.Layout(value, width: $0).height) }
                if edit.resizesRotated { next.frame = EaselRotation.recentred(original, frame: next.frame) }
            }
            if let board { next.frame = EaselTextSizing.placed(next.frame, in: board) }
            proposal[index].frame = next.frame
            changes[next.id] = next
        }
        return (proposal, changes)
    }
    private func updateTextSizeBadge() {
        let previous = textSizeBadge?.rect
        textSizeBadge = nil
        let scaled = Array(textPreview.values)
        if resizeHandle?.isCorner == true, let top = scaled.max(by: { $0.zIndex < $1.zIndex }),
           let bounds = EaselGeometryEdit.bounds(of: scaled) {
            let label = EaselTextSizing.sizeLabel(for: top.resolvedTextStyle)
            let area = NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
            textSizeBadge = (label, EaselTextLayout.sizeBadgeRect(label, below: area, scale: canvasScale))
        }
        for rect in [previous, textSizeBadge?.rect].compactMap({ $0 }) {
            setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
            if decoration.superview === self { decoration.setNeedsDisplay(rect.insetBy(dx: -2, dy: -2)) }
        }
    }
    func setTextSize(_ size: EaselTextStyle.Size) { changeTextStyle { $0 = EaselTextSizing.preset($0, size: size) } }
    func setCustomTextSize(_ points: Double) {
        guard points.isFinite else { return }
        changeTextStyle { $0 = EaselTextSizing.customSized($0, points: points) ?? $0 }
    }
    func editCustomTextSize(relativeTo anchor: NSView? = nil, rect: NSRect? = nil) {
        guard !session.isClosed, !session.isDeleted, editor?.hasMarkedText() != true else { return }
        let styles = session.document.items.filter { selection.contains($0.id) && $0.kind.holdsText }.map(\.resolvedTextStyle)
        guard !styles.isEmpty else { return }
        let owner = editor, ranges = editor?.selectedRanges, ids = selection
        let controller = EaselTextSizeEditor(value: EaselTextStyleState.points(of: styles, editor: owner))
        let popover = NSPopover(); popover.behavior = .transient; popover.contentViewController = controller
        controller.onCommit = { [weak self, weak popover] points in
            popover?.close()
            guard let self, self.selection == ids, self.editor === owner else { return }
            if let owner, let ranges { owner.selectedRanges = ranges }
            self.setCustomTextSize(points)
        }
        textSizePopover?.close(); textSizePopover = popover
        owner?.pendingPopover = popover
        let host = anchor ?? self
        let place = rect ?? (anchor == nil ? EaselGeometryEdit.bounds(of: session.document.items.filter { ids.contains($0.id) })
            .map { NSRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) } ?? host.bounds : host.bounds)
        popover.show(relativeTo: place, of: host, preferredEdge: host.isFlipped ? .maxY : .minY)
    }
    override func mouseUp(with event: NSEvent) {
        if finishNavigationGesture(event) { return }
        if imageMouseUp(event) { return }
        if tableMouseUp(with: event) { return }
        guard start != nil else { return }
        defer { cancelPointerInteraction() }
        if endConnectorGesture(at: convert(event.locationInWindow, from: nil), event: event) { return }
        if marqueeRect != nil {
            updateMarquee(to: convert(event.locationInWindow, from: nil), flags: event.modifierFlags)
            if finishSectionClick(marqueeRect, shift: event.modifierFlags.contains(.shift)) { return }
            selection = tentativeSelection ?? selection; return
        }
        if finishToolGesture(at: convert(event.locationInWindow, from: nil), event: event) { return }
        guard let draft else { return }
        if drawing {
            endBrushStroke(flags: event.modifierFlags)
        } else if tool == .eraser {
            endErasing()
        } else if let edit = geometryEdit, edit.ids == movableSelection, edit.isCurrent(in: session.document),
                  guides?.matchesCanvas(width: bounds.width) == true {
            guard resizing || dragDistance > 3 else { return }
            if rotationDrag == nil, !resizing, commitMindMapDrop() { return }
            let carried = commit(rotationDrag != nil ? "Rotate objects" : resizing ? "Resize objects" : "Move objects", coalescing: finishDuplicateDrag(), moved: edit.ids) { document in
                guard let next = edit.applying(draft, to: document) else { return }
                let fitted = fittedTables(textPreview.isEmpty ? next : EaselTextSizing.merging(Array(textPreview.values), into: next), ids: edit.ids)
                document = fitted
            }
            if carried { flashSectionCarry() }
        }
    }
    override func resetCursorRects() {
        if addImageCropCursorRects() { return }
        if let drag = rotationDrag, let point = lastGeometryPoint {
            addCursorRect(bounds, cursor: EaselCanvasRotation.cursor(toward: EaselPoint(x: point.x - drag.pivot.x, y: point.y - drag.pivot.y)))
            return
        }
        addCursorRect(bounds, cursor: toolCursor)
        guard !toolState.spaceHeld, toolState.pan == nil, tool == .select else { return }
        addImageBadgeCursorRects()
        addLockBadgeCursorRects()
        addTableCursorRects()
        addSectionCursorRects()
        if !drawing, onOpenURL != nil {
            for item in items where EaselObjectLink.hasLink(item) {
                let r = EaselObjectLink.badgeRect(for: EaselRotation.bounds(of: item), scale: canvasScale)
                addCursorRect(NSRect(x: r.x, y: r.y, width: r.width, height: r.height), cursor: .pointingHand)
            }
        }
        addConnectorCursorRects()
        addMindMapCursorRects()
        guard let chrome = selectionChrome else { return }
        let selected = items.filter { displayedSelection.contains($0.id) }
        if showsRotateZones {
            for zone in chrome.rotateZones(scale: canvasScale) {
                let r = zone.rect
                addCursorRect(NSRect(x: r.x, y: r.y, width: r.width, height: r.height), cursor: EaselCanvasRotation.cursor(toward: chrome.outward(zone.corner)))
            }
        }
        for handle in EaselTextSizing.handleOrder(for: selected).reversed() where showsFrameAnnotation(handle) {
            guard var r = handleRect(handle, in: chrome.frame, items: selected) else { continue }
            if chrome.isTurned {
                let middle = chrome.point(handle), half = (handle.isCorner ? 10 : 7) / canvasScale
                r = EaselRect(x: middle.x - half, y: middle.y - half, width: 2 * half, height: 2 * half)
            }
            let direction = chrome.outward(handle)
            let cursor: NSCursor = handle.isCorner ? .crosshair : (abs(direction.y) > abs(direction.x) ? .resizeUpDown : .resizeLeftRight)
            addCursorRect(NSRect(x: r.x, y: r.y, width: r.width, height: r.height), cursor: cursor)
        }
    }
    override func cancelOperation(_ sender: Any?) {
        if cancelImageCrop() { return }
        if editor != nil { finishEditingFromEscape() }
        else if start != nil || toolState.pan != nil { cancelPointerInteraction() }
        else if !selection.isEmpty { selection.removeAll(); invalidateIncrementalDisplay(layout: true) }
        else if tool != .select { tool = .select }
        else if let onImageEditingCancel { onImageEditingCancel() }
        else if sender is NSEvent { nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender) }
    }
    override func keyDown(with event: NSEvent) {
        guard canvasOwnsKeyFocus else {
            super.keyDown(with: event); return
        }
        if imageKeyDown(event) { return }
        if tableKeyDown(with: event) { return }
        if event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if performMindMapTab(backward: event.modifierFlags.contains(.shift)) { return }
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(window?.firstResponder) }
            else { window?.selectNextKeyView(window?.firstResponder) }
            return
        }
        if event.keyCode == 53 { cancelOperation(event); return }
        if handlePageKey(event) { return }
        if handleToolKey(event) { return }
        guard start == nil else { return }
        if handleArrangeKey(event) { return }
        if event.keyCode == 1, event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift],
           let onExportImage { onExportImage(); return }
        if event.keyCode == 51 || event.keyCode == 117 { deleteObjects(nil); return }
        if [UInt16(36), UInt16(76)].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           selection.count == 1, let item = items.first(where: { selection.contains($0.id) }) {
            if item.kind == .arrow { beginConnectorLabelEditing(item, at: nil); return }
            _ = activateAccessibleObject(item); return
        }
        let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
        if [UInt16(123), UInt16(124)].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option]) == [.option],
           rotateSelection(by: (event.keyCode == 123 ? -1 : 1) * (event.modifierFlags.contains(.shift) ? EaselRotation.largeKeyStep : EaselRotation.keyStep)) {
            return
        }
        let delta: (Double, Double)? = [123: (-step, 0), 124: (step, 0), 125: (0, step), 126: (0, -step)][Int(event.keyCode)]
        if let (dx, dy) = delta, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            guard !selection.isEmpty else { panByKeyboard(dx: dx, dy: dy, fast: event.modifierFlags.contains(.shift)); return }
            guard let edit = EaselGeometryEdit(document: session.document, selection: movableSelection) else { refuseLocked(selection); return }
            let changes = edit.translated(x: dx, y: dy)
            commit("Move objects", coalescing: nudgeUndoGroup(for: edit.ids), moved: edit.ids) { document in
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
            guard let self else { return }
            let before = self.session.fullDocument
            do { try self.applyHistory { try self.session.undo() } } catch { self.onError?(error); return }
            self.selectAfterHistoryStep(from: before)
        }
    }
    @objc func redo(_ sender: Any?) {
        if let editor, editor.localUndo.canRedo { editor.localUndo.redo(); return }
        cancelPointerInteraction(); guard finishEditing(removingEmpty: false) else { return }
        guard let next = session.redoDestination else { return }
        prepareReplacement(next) { [weak self] in
            guard let self else { return }
            let before = self.session.fullDocument
            do { try self.applyHistory { try self.session.redo() } } catch { self.onError?(error); return }
            self.selectAfterHistoryStep(from: before)
        }
    }
    override func selectAll(_ sender: Any?) {
        cancelPointerInteraction(); arrangeState.enteredGroup = nil
        selection = Set(items.filter { !$0.isLocked }.map(\.id)); invalidateIncrementalDisplay(layout: true)
    }
    private func hasCurrentMenuOwner(_ sender: Any?) -> Bool {
        guard let item = sender as? NSMenuItem, let target = item.representedObject as? MenuTarget else { return true }
        guard let owner = target.window else { return false }
        return owner === window && target.generation == menuGeneration
    }
    func command(for sender: Any?) -> EaselObjectCommand? {
        guard hasCurrentMenuOwner(sender) else { return nil }
        let command: EaselObjectCommand?
        if let menu = sender as? NSMenuItem, let target = menu.representedObject as? MenuTarget {
            command = target.command
        }
        else { command = EaselObjectCommand(document: session.document, selection: selection) }
        guard let command, command.ids == selection, command.isCurrent(in: session.document) else { return nil }
        return command
    }
    @objc func deleteObjects(_ sender: Any?) {
        guard command(for: sender) != nil else { return }
        deleteSelection()
    }
    func prepareReplacement(_ next: EaselDocument, commit: @escaping () -> Void) {
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
    @objc @discardableResult func duplicateObjects(_ sender: Any?) -> Bool {
        guard command(for: sender) != nil else { return false }
        return duplicateSelection()
    }
    @objc @discardableResult func bringToFront(_ sender: Any?) -> Bool {
        guard command(for: sender) != nil else { return false }
        return moveLayer(.front)
    }
    @objc func copy(_ sender: Any?) {
        if copyTableCells() { return }
        guard command(for: sender) != nil else { return }
        copySelection()
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
        pasteHere(nil)
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
        if readTablePasteboard(pasteboard) { return true }
        var imported = false
        do {
            if let url = try EaselClipboardURL.read(from: pasteboard) {
                if fixedCanvasSize == nil { return insertLink(url.absoluteString) }
                return insert(kind: .text, text: url.absoluteString)
            }
            if pasteMermaid(from: pasteboard) { return true }
            if let text = try EaselStyledText.read(from: pasteboard) {
                return insert(kind: .text, text: text.text, styledText: text)
            }
            if let data = pasteboard.data(forType: Self.gifPasteboardType) ?? pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) { try importImage(data); return true }
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                for url in urls { try importImageFile(url); imported = true }; return imported
            }
            if let text = try EaselStyledText.plainText(from: pasteboard) { return insert(kind: .text, text: text) }
        } catch { onError?(error) }
        return imported
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if fixedCanvasSize == nil, let operation = contentDrop.begin(sender) { return operation }
        return sender.draggingPasteboard.availableType(from: [EaselStyledText.pasteboardType, EaselStyledText.previousPasteboardType, EaselStyledText.legacyPasteboardType, .rtfd, .rtf, .fileURL, Self.gifPasteboardType, .png, .tiff, .URL, .string]) == nil ? [] : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fixedCanvasSize == nil ? super.draggingUpdated(sender) : draggingEntered(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        fixedCanvasSize == nil ? super.prepareForDragOperation(sender) : !draggingEntered(sender).isEmpty
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if fixedCanvasSize == nil, let result = contentDrop.perform(sender) { return result }
        if let replaced = replaceImage(fromDrop: sender) { return replaced }
        return withObjectMotion(.appear) { readPasteboard(sender.draggingPasteboard) }
    }
    func setLiveCapture(_ id: UUID, enabled: Bool) {
        guard fixedCanvasSize == nil, pageObjects != nil,
              let item = session.document.items.first(where: { $0.id == id && $0.kind == .webCard && $0.captureLayout != nil }),
              (item.liveCapture == true) != enabled else { return }
        if enabled && !UserDefaults.standard.bool(forKey: Self.liveCaptureEducationKey) {
            guard liveCaptureEducation == nil, let owner = window, owner.isKeyWindow, owner.attachedSheet == nil else { return }
            let original = session.document, originalSelection = selection
            let alert = ParcDialog(.init(title: "Make it Live",
                message: "See an up-to-date, interactive view of the region you captured. This does not work on all sites. You can always return to the original screenshot with Back to snapshot.",
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
    @objc private func flipObjectsHorizontally(_ sender: Any?) { if command(for: sender) != nil { flipSelection(horizontal: true) } }
    @objc private func flipObjectsVertically(_ sender: Any?) { if command(for: sender) != nil { flipSelection(horizontal: false) } }
    @objc private func rotateObjectsLeft(_ sender: Any?) { if command(for: sender) != nil { rotateSelection(by: -90) } }
    @objc private func rotateObjectsRight(_ sender: Any?) { if command(for: sender) != nil { rotateSelection(by: 90) } }
    private func announceTurn(of id: UUID) {
        guard let item = session.document.items.first(where: { $0.id == id }) else { return }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "Rotated to " + EaselRotation.turnLabel(EaselRotation.degrees(of: item)),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
    @objc private func toggleAlignmentGuides(_ sender: Any?) {
        guard hasCurrentMenuOwner(sender) else { return }
        cancelPointerInteraction(); alignmentGuidesEnabled.toggle(); invalidateIncrementalDisplay()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard hasCurrentMenuOwner(menuItem) else { return false }
        if let verdict = validateImageMenuItem(menuItem) { return verdict }
        if let valid = validateTableMenuItem(menuItem) { return valid }
        if let command = TextFormatCommand(menuItem) {
            if let editor = formattingEditor {
                if command == .link { menuItem.title = editor.hasLink() ? TextFormatCommand.editLinkTitle : TextFormatCommand.addLinkTitle }
                else { menuItem.state = editor.formatState(command) }
            } else if command == .link, let target = objectLinkTarget {
                menuItem.title = target.url == nil ? TextFormatCommand.addLinkTitle : TextFormatCommand.editLinkTitle
            }
            return canFormat(command)
        }
        if menuItem.action == #selector(flipObjectsHorizontally) || menuItem.action == #selector(flipObjectsVertically) {
            return command(for: menuItem).map { EaselRotation.canFlip($0.originals) } == true
        }
        if menuItem.action == #selector(rotateObjectsLeft) || menuItem.action == #selector(rotateObjectsRight) {
            return command(for: menuItem).map { EaselRotation.canRotate($0.originals) } == true
        }
        if menuItem.action == #selector(toggleAlignmentGuides) {
            menuItem.state = alignmentGuidesEnabled ? .on : .off; return true
        }
        if menuItem.action == #selector(toggleLiveCapture) {
            return pageObjects != nil && fixedCanvasSize == nil && command(for: menuItem)?.originals.first.map(EaselWebItemChrome.canMakeLive) == true
        }
        if menuItem.action == #selector(undo) { return canUndo }
        if menuItem.action == #selector(redo) { return canRedo }
        if menuItem.action == #selector(openObjectSource) || menuItem.action == #selector(copyObjectSource) {
            guard let command = command(for: menuItem) else { return false }
            return command.originals.count == 1 && command.originals.first?.url != nil
        }
        if menuItem.action == #selector(copy(_:)) { return command(for: menuItem) != nil }
        if menuItem.action == #selector(cut(_:)) || menuItem.action == #selector(deleteObjects) { return command(for: menuItem) != nil && canCutSelection }
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
final class EaselCanvasDecoration: NSView {
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
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            DispatchQueue.main.async { [weak canvas = self.canvas] in
                guard let canvas, !canvas.canvasOwnsKeyFocus else { return }
                canvas.releaseTemporaryHand()
            }
        }
        return resigned
    }
    override func keyDown(with event: NSEvent) { canvas?.keyDown(with: event) }
    override func accessibilityLabel() -> String? {
        guard let item = canvas?.accessibleItem(id) else { return nil }
        switch item.kind {
        case .text: return "Text"
        case .rectangle, .circle: return item.resolvedShape.map(EaselShapeGeometry.displayName) ?? "Shape"
        case .webCard: return "Captured webpage"
        case .browser: return "Webpage"
        case .freehand: return item.resolvedBrush.title
        case .sticky: return "Sticky note"
        case .section: return EaselBoardObjects.displayTitle(item)
        case .code: return "Code block, " + EaselCodeBlock.displayName(item.language)
        case .stamp: return EaselStampArtwork.accessibilityLabel(item)
        case .arrow: return "Connector"
        case .image, .video, .audio, .file, .pdf, .equation: return EaselMediaPlacement.accessibilityLabel(item)
        default: return item.kind.rawValue.capitalized
        }
    }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        canvas?.accessibleItem(id)?.kind == .section ? NSAccessibility.Subrole(rawValue: "AXLandmarkRegion") : nil
    }
    override func accessibilityValue() -> Any? {
        guard let item = canvas?.accessibleItem(id), item.kind != .stamp else { return nil }
        let value: String?
        if item.kind.isMedia { value = item.altText ?? item.fileName ?? item.url }
        else if let table = item.table { value = table.accessibilitySummary }
        else if item.kind == .section { value = canvas?.sectionSummary(item) }
        else { value = item.text.isEmpty ? item.url : item.text }
        return item.isLocked ? ["Locked", value].compactMap { $0 }.joined(separator: ", ") : value
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
        var names = item.isLocked ? ["Unlock", "Duplicate"] : ["Duplicate", "Bring to front", "Lock", "Delete"]
        if !item.isLocked, EaselRotation.canRotate(item) { names += ["Rotate left", "Rotate right"] }
        if !item.isLocked, EaselRotation.canFlip(item) { names += ["Flip horizontal", "Flip vertical"] }
        if item.url != nil { names.insert("Open source", at: 0) }
        names += canvas.boardActionNames(item) + canvas.mindMapActionNames(item)
        if item.kind == .code { names.insert(contentsOf: ["Copy code", "Change language"], at: 0) }
        if item.kind == .arrow, !item.isLocked { names.insert("Edit label", at: 0) }
        if canvas.quickCreates(item), canvas.fixedCanvasSize == nil { names.insert("Add next", at: 0) }
        if item.kind.holdsText || item.kind == .table || item.kind == .code || !canvas.accessibleChildren(id).isEmpty || item.ownsEmbeddedPage { names.insert("Activate", at: 0) }
        let linked = EaselObjectLink.link(of: item) != nil
        return names.map { name in
            let title = name == "Activate" ? (item.kind.holdsText ? "Edit text" : item.kind == .table ? "Edit cells" : item.kind == .code ? "Edit code" : "Interact with webpage")
                : name == "Open source" && linked ? "Open link" : name.hasPrefix("Rotate") ? name + " 15°" : name
            return NSAccessibilityCustomAction(name: title) { [weak canvas, weak owner] in
                canvas?.accessibleAction(name, item: item, owner: owner) == true
            }
        } + canvas.imageAccessibilityActions(for: item, owner: owner)
    }
}
