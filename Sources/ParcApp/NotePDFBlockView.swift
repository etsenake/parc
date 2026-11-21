import AppKit
import PDFKit

extension NoteMediaProblem: Error {}

final class NotePDFBox: @unchecked Sendable {
    let document: PDFDocument?
    init(_ document: PDFDocument?) { self.document = document }
}

@MainActor
final class NotePDFDocuments {
    static let shared = NotePDFDocuments()

    private final class Entry {
        let document: PDFDocument
        let stamp: Date?
        init(document: PDFDocument, stamp: Date?) {
            self.document = document
            self.stamp = stamp
        }
    }

    private let documents = NSCache<NSURL, Entry>()
    private var aspects: [URL: CGFloat] = [:]
    private var waiting: [URL: [(Result<PDFDocument, NoteMediaProblem>) -> Void]] = [:]

    init() { documents.countLimit = 16 }

    static func stamp(_ url: URL) -> Date? {
        guard url.isFileURL else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func aspect(of document: PDFDocument) -> CGFloat? {
        guard !document.isLocked, document.pageCount > 0, let page = document.page(at: 0) else { return nil }
        let box = page.bounds(for: .cropBox)
        return NotePDFLayout.pageAspect(width: box.width, height: box.height, rotation: page.rotation)
    }

    func aspect(of url: URL) -> CGFloat? { aspects[url] }

    func cached(_ url: URL) -> PDFDocument? {
        guard let entry = documents.object(forKey: url as NSURL) else { return nil }
        if url.isFileURL, entry.stamp != Self.stamp(url) {
            documents.removeObject(forKey: url as NSURL)
            return nil
        }
        return entry.document
    }

    func load(_ url: URL, completion: @escaping (Result<PDFDocument, NoteMediaProblem>) -> Void) {
        if let hit = cached(url) { completion(.success(hit)); return }
        if waiting[url] != nil { waiting[url]?.append(completion); return }
        waiting[url] = [completion]
        if url.isFileURL {
            let stamp = Self.stamp(url)
            DispatchQueue.global(qos: .userInitiated).async {
                let box = NotePDFBox(PDFDocument(url: url))
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { NotePDFDocuments.shared.finish(url, box.document, stamp: stamp) }
                }
            }
            return
        }
        NoteMediaImageLoader.shared.data(for: url) { result in
            switch result {
            case .success(let data):
                DispatchQueue.global(qos: .userInitiated).async {
                    let box = NotePDFBox(PDFDocument(data: data))
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { NotePDFDocuments.shared.finish(url, box.document, stamp: nil) }
                    }
                }
            case .failure(let error):
                NotePDFDocuments.shared.deliver(url, .failure(NoteMediaBlockView.problem(for: error)))
            }
        }
    }

    private func remember(_ document: PDFDocument, for url: URL, stamp: Date?) {
        documents.setObject(Entry(document: document, stamp: stamp), forKey: url as NSURL)
        if let aspect = Self.aspect(of: document) { aspects[url] = aspect }
    }

    private func finish(_ url: URL, _ document: PDFDocument?, stamp: Date?) {
        guard let document, document.isLocked || document.pageCount > 0 else {
            deliver(url, .failure(.unreadable))
            return
        }
        remember(document, for: url, stamp: stamp)
        deliver(url, .success(document))
    }

    private func deliver(_ url: URL, _ result: Result<PDFDocument, NoteMediaProblem>) {
        for callback in waiting.removeValue(forKey: url) ?? [] { callback(result) }
    }

    func unlocked(_ document: PDFDocument, at url: URL) {
        if let aspect = Self.aspect(of: document) { aspects[url] = aspect }
    }
}

@MainActor
final class NotePDFViewer: PDFView {
    var routesScrollToNote = false
    var onPageChange: (() -> Void)?
    var onScaleChange: (() -> Void)?
    var onLink: ((URL) -> Void)?
    var onEscape: (() -> Void)?
    var noteScrollView: (() -> NSScrollView?)?
    private var latch = NotePDFScrollLatch()
    private var observers: [NSObjectProtocol] = []
    private let linkRouter = NotePDFLinkRouter()

    override init(frame: NSRect) {
        super.init(frame: frame)
        displayMode = .singlePageContinuous
        displayDirection = .vertical
        displaysPageBreaks = true
        pageBreakMargins = NSEdgeInsets(top: NotePDFLayout.pageInset, left: NotePDFLayout.pageInset,
                                        bottom: NotePDFLayout.pageInset, right: NotePDFLayout.pageInset)
        displayBox = .cropBox
        interpolationQuality = .high
        pageShadowsEnabled = true
        acceptsDraggedFiles = false
        autoScales = true
        backgroundColor = .clear
        linkRouter.viewer = self
        delegate = linkRouter
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFViewPageChanged, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onPageChange?() }
        })
        observers.append(center.addObserver(forName: .PDFViewScaleChanged, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onScaleChange?() }
        })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    var pageIndex: Int {
        guard let document, let page = currentPage else { return 0 }
        return max(0, document.index(for: page))
    }

    var pageCount: Int { document?.pageCount ?? 0 }

    func goToPage(_ index: Int) {
        guard let document, document.pageCount > 0, let page = document.page(at: min(max(index, 0), document.pageCount - 1)) else { return }
        go(to: page)
    }

    var fitScale: CGFloat {
        let fit = scaleFactorForSizeToFit
        return fit > 0 ? fit : max(scaleFactor, 0.01)
    }

    var fitsWidth: Bool { autoScales }

    func fitWidth() {
        autoScales = true
        onScaleChange?()
    }

    func zoom(in zoomingIn: Bool) {
        let outcome = NotePDFZoom.zoomed(current: scaleFactor, fit: fitScale, zoomIn: zoomingIn)
        if outcome.fitsWidth {
            autoScales = true
        } else {
            autoScales = false
            scaleFactor = outcome.scale
        }
        onScaleChange?()
    }

    func canZoom(in zoomingIn: Bool) -> Bool {
        NotePDFZoom.canZoom(current: scaleFactor, fit: fitScale, zoomIn: zoomingIn)
    }

    func open(link url: URL) {
        if let onLink { onLink(url) } else { NSWorkspace.shared.open(url) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let selection = currentSelection, !(selection.string ?? "").isEmpty else { return nil }
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        return menu
    }

    override func cancelOperation(_ sender: Any?) {
        if let onEscape { onEscape() } else { super.cancelOperation(sender) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onEscape { onEscape(); return }
        super.keyDown(with: event)
    }

    private var innerScrollView: NSScrollView? { documentView?.enclosingScrollView }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard routesScrollToNote, hit != nil, NSApp.currentEvent?.type == .scrollWheel else { return hit }
        return self
    }

    private var room: NotePDFScrollLatch.Room {
        guard let scroll = innerScrollView, let document = scroll.documentView else { return .init() }
        let visible = scroll.contentView.documentVisibleRect
        let bounds = document.bounds
        let flipped = document.isFlipped
        let towardStart = flipped ? visible.minY - bounds.minY : bounds.maxY - visible.maxY
        let towardEnd = flipped ? bounds.maxY - visible.maxY : visible.minY - bounds.minY
        return .init(up: towardStart > 0.5, down: towardEnd > 0.5, left: visible.minX - bounds.minX > 0.5, right: bounds.maxX - visible.maxX > 0.5)
    }

    private static func phase(of event: NSEvent) -> NotePDFScrollLatch.Phase {
        if event.momentumPhase == .ended || event.momentumPhase == .cancelled { return .momentumEnded }
        if !event.momentumPhase.isEmpty { return .momentum }
        if event.phase.contains(.began) { return .began }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { return .ended }
        if event.phase.isEmpty { return .discrete }
        return .changed
    }

    override func scrollWheel(with event: NSEvent) {
        guard routesScrollToNote, let inner = innerScrollView else {
            innerScrollView?.scrollWheel(with: event) ?? super.scrollWheel(with: event)
            return
        }
        let phase = Self.phase(of: event)
        let route = latch.receive(phase, deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY),
                                  time: event.timestamp, room: room)
        switch route {
        case .pdf:
            inner.scrollWheel(with: event)
        case .note:
            if let note = noteScrollView?() { note.scrollWheel(with: event) } else { inner.scrollWheel(with: event) }
        case .noteHandedOver:
            if phase == .ended || phase == .momentumEnded { inner.scrollWheel(with: event) }
            scrollNote(with: event, phase: phase)
        }
    }

    private func scrollNote(with event: NSEvent, phase: NotePDFScrollLatch.Phase) {
        guard let scrollView = noteScrollView?() else { return }
        if phase == .discrete {
            scrollView.scrollWheel(with: event)
            return
        }
        let clip = scrollView.contentView
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : scrollView.verticalLineScroll)
        var bounds = clip.bounds
        bounds.origin.y = clip.isFlipped ? bounds.origin.y - delta : bounds.origin.y + delta
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scrollView.reflectScrolledClipView(clip)
    }
}

@MainActor
private final class NotePDFLinkRouter: NSObject, PDFViewDelegate {
    weak var viewer: NotePDFViewer?

    nonisolated func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
        MainActor.assumeIsolated {
            if let viewer { viewer.open(link: url) } else { NSWorkspace.shared.open(url) }
        }
    }
}

extension NotePDFViewer: HistorySwipeScrollRoomProvider {
    var historySwipeScrollRoom: HistorySwipeTargets.ScrollRoom? {
        guard let scroll = innerScrollView, let document = scroll.documentView else { return nil }
        return HistorySwipeTargets.ScrollRoom(content: Double(document.frame.width), visible: Double(scroll.contentView.bounds.width))
    }
}

@MainActor
final class NotePDFStaticPageView: NSView {
    var page: PDFPage? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let page, let cgPage = page.pageRef, let context = NSGraphicsContext.current?.cgContext else { return }
        let box = cgPage.getBoxRect(.cropBox)
        let quarter = ((Int(cgPage.rotationAngle) % 360) + 360) % 360
        let turned = quarter == 90 || quarter == 270
        let size = turned ? CGSize(width: box.height, height: box.width) : box.size
        guard size.width > 0, size.height > 0 else { return }
        let inset = NotePDFLayout.pageInset
        let width = max(1, bounds.width - inset * 2)
        let scale = width / size.width
        let rect = NSRect(x: inset, y: inset, width: width, height: (size.height * scale).rounded())
        context.saveGState()
        context.clip(to: bounds)
        NSColor.white.setFill()
        rect.fill()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: scale, y: -scale)
        switch quarter {
        case 90: context.concatenate(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: box.width))
        case 180: context.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: box.width, ty: box.height))
        case 270: context.concatenate(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: box.height, ty: 0))
        default: break
        }
        context.translateBy(x: -box.minX, y: -box.minY)
        context.clip(to: box)
        context.drawPDFPage(cgPage)
        context.restoreGState()
    }
}

@MainActor
final class NotePDFControlBar: NSView {
    let zoomOut = NoteToolbarButton(icon: .symbol("minus.magnifyingglass"), label: "Zoom out")
    let fit = NoteToolbarButton(icon: .symbol("arrow.left.and.right"), label: "Fit width")
    let zoomIn = NoteToolbarButton(icon: .symbol("plus.magnifyingglass"), label: "Zoom in")
    let previous = NoteToolbarButton(icon: .symbol("chevron.up"), label: "Previous page")
    let next = NoteToolbarButton(icon: .symbol("chevron.down"), label: "Next page")
    private let label = NSTextField(labelWithString: "")
    private let card = CALayer()
    private let divider = CALayer()
    private static let labelWidth: CGFloat = 64
    static let height = NoteMediaToolbar.height

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        card.cornerRadius = 9
        card.cornerCurve = .continuous
        card.borderWidth = 0.5
        card.shadowOpacity = 1
        card.shadowRadius = 7
        card.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(card)
        layer?.addSublayer(divider)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.textColor = NoteTheme.menuSecondaryInk
        label.isSelectable = false
        for view in [zoomOut, fit, zoomIn, previous, label, next] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("PDF controls")
        isHidden = true
        layer?.opacity = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var buttons: [NoteToolbarButton] { [zoomOut, fit, zoomIn, previous, next] }

    var fittingWidth: CGFloat {
        let button = NoteTheme.toolbarButtonSize.width
        return NoteMediaToolbar.padding * 2 + button * 5 + NoteMediaToolbar.spacing * 5 + 9 + Self.labelWidth
    }

    func setPage(current: Int, count: Int) {
        label.stringValue = NotePDFPages.label(current: current, count: count)
        label.setAccessibilityLabel(NotePDFPages.spokenLabel(current: current, count: count))
        previous.isEnabled = current > 0
        next.isEnabled = current < count - 1
    }

    func setZoom(canZoomOut: Bool, canZoomIn: Bool, fitsWidth: Bool) {
        zoomOut.isEnabled = canZoomOut
        zoomIn.isEnabled = canZoomIn
        fit.isEnabled = !fitsWidth
    }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            card.frame = bounds
            card.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 9, cornerHeight: 9, transform: nil)
        }
        let size = NoteTheme.toolbarButtonSize
        let y = (bounds.height - size.height) / 2
        var x = NoteMediaToolbar.padding
        for button in [zoomOut, fit, zoomIn] {
            button.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + NoteMediaToolbar.spacing
        }
        NoteMediaMotion.instant { divider.frame = NSRect(x: x + 3, y: 8, width: 1, height: bounds.height - 16) }
        x += 9
        previous.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        x += size.width
        label.frame = NSRect(x: x, y: (bounds.height - 16) / 2, width: Self.labelWidth, height: 16)
        x += Self.labelWidth
        next.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        refreshColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        NoteMediaMotion.instant {
            card.backgroundColor = NoteMediaStyle.cg(NoteTheme.menuFill, in: self)
            card.borderColor = NoteMediaStyle.cg(NoteTheme.menuHairline, in: self)
            card.shadowColor = NoteTheme.menuShadow.cgColor
            divider.backgroundColor = NoteMediaStyle.cg(NoteTheme.separator, in: self)
        }
    }

    var isShown: Bool { !isHidden && (layer?.opacity ?? 0) > 0 }

    func show() {
        guard !isShown else { return }
        NoteMediaMotion.present(self, anchor: CGPoint(x: 0.5, y: 1))
    }

    func hide() {
        guard isShown else { return }
        NoteMediaMotion.dismiss(self, anchor: CGPoint(x: 0.5, y: 1))
    }

    func showImmediately() {
        isHidden = false
        NoteMediaMotion.instant { layer?.opacity = 1 }
    }
}

@MainActor
final class NotePDFLockView: NSView, NSTextFieldDelegate {
    var onUnlock: ((String) -> Bool)?
    private let icon = NSImageView()
    private let title = NoteMediaStyle.label("This PDF has a password", font: NoteMediaStyle.titleFont, color: NoteTheme.ink)
    private let hint = NoteMediaStyle.label("Not quite. Try again?", font: NoteMediaStyle.smallFont, color: NoteMediaStyle.warningInk)
    private let field = NSSecureTextField()
    private let unlockChip = NoteChip("Unlock", icon: .symbol("lock.open"), style: .filled)
    private let fieldBox = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        icon.image = NoteMediaStyle.symbol("lock.fill", size: 22, weight: .semibold)
        icon.contentTintColor = NoteTheme.tertiaryInk
        title.alignment = .center
        hint.alignment = .center
        hint.isHidden = true
        fieldBox.cornerRadius = NoteTheme.controlRadius
        fieldBox.cornerCurve = .continuous
        layer?.addSublayer(fieldBox)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NoteMediaStyle.nunito(14)
        field.textColor = NoteTheme.ink
        field.placeholderAttributedString = NSAttributedString(string: "Password",
                                                               attributes: [.font: NoteMediaStyle.nunito(14), .foregroundColor: NoteTheme.placeholderInk])
        field.delegate = self
        field.setAccessibilityLabel("PDF password")
        unlockChip.onPress = { [weak self] in self?.submit() }
        for view in [icon, title, field, unlockChip, hint] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("This PDF has a password")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func focus() { window?.makeFirstResponder(field) }

    private func submit() {
        if onUnlock?(field.stringValue) == true { return }
        hint.isHidden = false
        field.stringValue = ""
        guard let layer = field.layer ?? { field.wantsLayer = true; return field.layer }(), !NoteAnimation.reduceMotion else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -6, 5, -3, 2, 0]
        shake.duration = 0.32
        shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(shake, forKey: "pdf.shake")
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        submit()
        return true
    }

    func controlTextDidChange(_ obj: Notification) { hint.isHidden = true }

    override func layout() {
        super.layout()
        let midX = bounds.midX
        let top = max(16, (bounds.height - 150) / 2)
        icon.frame = NSRect(x: midX - 14, y: top, width: 28, height: 28)
        title.frame = NSRect(x: 16, y: top + 36, width: bounds.width - 32, height: 21)
        let chipWidth = unlockChip.intrinsicContentSize.width
        let fieldWidth = min(220, max(80, bounds.width - 64 - chipWidth))
        let rowX = midX - (fieldWidth + 8 + chipWidth) / 2
        let rowY = top + 68
        NoteMediaMotion.instant {
            fieldBox.frame = NSRect(x: rowX, y: rowY, width: fieldWidth, height: NoteTheme.chipHeight)
            fieldBox.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.fieldFill, in: self)
        }
        field.frame = NSRect(x: rowX + 8, y: rowY + 3, width: fieldWidth - 16, height: 20)
        unlockChip.frame = NSRect(x: rowX + fieldWidth + 8, y: rowY, width: chipWidth, height: NoteTheme.chipHeight)
        hint.frame = NSRect(x: 16, y: rowY + NoteTheme.chipHeight + 8, width: bounds.width - 32, height: 16)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}

@MainActor
final class NotePDFContentView: NoteMediaContentView, NoteMediaResizing {
    private let frameView = NSView()
    private let shimmer = NoteMediaShimmer()
    private let ring = CALayer()
    private let leadingHandle = NoteMediaResizeHandle(edge: .leading)
    private let trailingHandle = NoteMediaResizeHandle(edge: .trailing)
    private let toolbar = NoteMediaToolbar()
    private let controls = NotePDFControlBar()
    private let alignChip = NoteToolbarButton(icon: .symbol("text.aligncenter"), label: "Alignment")
    private let captionChip = NoteToolbarButton(icon: .symbol("text.below.photo"), label: "Caption")
    private let fullScreenChip = NoteToolbarButton(icon: .symbol("arrow.up.left.and.arrow.down.right"), label: "Full screen")
    private let downloadChip = NoteToolbarButton(icon: .symbol("arrow.down.to.line"), label: "Download")
    private let originalChip = NoteToolbarButton(icon: .symbol("arrow.up.forward.square"), label: "View original")
    private let replaceChip = NoteToolbarButton(icon: .symbol("arrow.triangle.2.circlepath"), label: "Replace")
    private let deleteChip = NoteToolbarButton(icon: .symbol("trash"), label: "Delete")
    private var viewer: NotePDFViewer?
    private var staticPage: NotePDFStaticPageView?
    private var lockView: NotePDFLockView?
    private var source: NoteMediaSource = .empty
    private var props = NoteBlockProps()
    private var document: PDFDocument?
    private var aspect: CGFloat?
    private var liveWidth: CGFloat?
    private var resizeStart: (width: CGFloat, column: CGFloat)?
    private var settleScale: CGFloat?
    private var hovered = false
    private var flashGeneration = 0
    private var alignmentMenu: NoteFloatingPanel?
    private var menuMonitor: Any?
    private weak var fullScreen: NotePDFFullScreenOverlay?

    override init(host: NoteMediaHost) {
        super.init(host: host)
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = NoteMediaStyle.cardRadius
        frameView.layer?.cornerCurve = .continuous
        frameView.layer?.masksToBounds = true
        frameView.layer?.borderWidth = 1
        addSubview(frameView)
        shimmer.cornerRadius = NoteMediaStyle.cardRadius
        addSubview(shimmer)
        ring.cornerRadius = NoteMediaStyle.cardRadius + 3
        ring.cornerCurve = .continuous
        ring.borderWidth = 2
        ring.isHidden = true
        layer?.addSublayer(ring)
        for handle in [leadingHandle, trailingHandle] {
            handle.owner = self
            handle.isHidden = true
            handle.alphaValue = 0
            addSubview(handle)
        }
        alignChip.onPress = { [weak self] in self?.toggleAlignmentMenu() }
        captionChip.onPress = { [weak self] in self?.host?.revealCaption() }
        fullScreenChip.onPress = { [weak self] in _ = self?.presentFullScreen() }
        downloadChip.onPress = { [weak self] in self?.host?.download() }
        originalChip.onPress = { [weak self] in self?.viewOriginal() }
        replaceChip.onPress = { [weak self] in self?.host?.replace() }
        deleteChip.onPress = { [weak self] in self?.host?.deleteBlock() }
        controls.zoomOut.onPress = { [weak self] in self?.viewer?.zoom(in: false) }
        controls.zoomIn.onPress = { [weak self] in self?.viewer?.zoom(in: true) }
        controls.fit.onPress = { [weak self] in self?.viewer?.fitWidth() }
        controls.previous.onPress = { [weak self] in self?.viewer?.goToPreviousPage(nil) }
        controls.next.onPress = { [weak self] in self?.viewer?.goToNextPage(nil) }
        addSubview(controls)
        toolbar.anchor = CGPoint(x: 1, y: 0)
        addSubview(toolbar)
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            self.frameView.layer?.removeAllAnimations()
            NoteMediaMotion.instant { self.frameView.layer?.transform = CATransform3DIdentity }
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let menuMonitor { NSEvent.removeMonitor(menuMonitor) }
    }

    private var editable: Bool { host?.canEdit == true }
    private var locked: Bool { document?.isLocked == true }

    override func update(block: NoteBlock, source: NoteMediaSource) {
        let changed = source != self.source
        self.source = source
        let previousWidth = props.width
        props = block.props
        if changed { reload() }
        if previousWidth != props.width { liveWidth = nil }
        configureToolbar()
        refreshAccessibility()
        needsLayout = true
    }

    override func rebind(to source: NoteMediaSource) {
        guard document != nil else { return }
        self.source = source
    }

    private func reload() {
        document = nil
        viewer?.document = nil
        lockView?.removeFromSuperview()
        lockView = nil
        staticPage?.page = nil
        aspect = source.url.flatMap { NotePDFDocuments.shared.aspect(of: $0) }
        guard let url = source.url else { return }
        if let cached = NotePDFDocuments.shared.cached(url) {
            show(cached, animated: false)
            return
        }
        shimmer.isHidden = false
        let expected = source
        NotePDFDocuments.shared.load(url) { [weak self] result in
            guard let self, self.source == expected else { return }
            switch result {
            case .success(let document): self.show(document, animated: self.window != nil)
            case .failure(let problem): self.host?.contentDidFail(problem)
            }
        }
    }

    private func show(_ document: PDFDocument, animated: Bool) {
        self.document = document
        shimmer.isHidden = true
        let next = NotePDFDocuments.aspect(of: document) ?? aspect
        let changed = abs(NotePDFLayout.aspect(next) - NotePDFLayout.aspect(aspect)) > 0.001
        aspect = next
        attachRenderer()
        if animated, let layer = frameView.layer { NoteMediaMotion.fadeIn(layer, duration: 0.2) }
        if changed { host?.invalidateMeasuredHeight() }
        refreshControls()
        refreshAccessibility()
        setHovered(hovered)
        needsLayout = true
    }

    private func attachRenderer() {
        guard let document else { return }
        if document.isLocked {
            viewer?.removeFromSuperview()
            viewer = nil
            staticPage?.removeFromSuperview()
            staticPage = nil
            if lockView == nil {
                let view = NotePDFLockView()
                view.onUnlock = { [weak self] password in self?.unlock(password) ?? false }
                frameView.addSubview(view)
                lockView = view
            }
            return
        }
        lockView?.removeFromSuperview()
        lockView = nil
        if window != nil {
            staticPage?.removeFromSuperview()
            staticPage = nil
            let viewer = self.viewer ?? makeViewer()
            if viewer.document !== document {
                viewer.document = document
                viewer.fitWidth()
            }
        } else {
            viewer?.removeFromSuperview()
            viewer = nil
            let page = staticPage ?? {
                let view = NotePDFStaticPageView()
                frameView.addSubview(view)
                staticPage = view
                return view
            }()
            page.page = document.page(at: 0)
        }
        needsLayout = true
    }

    private func makeViewer() -> NotePDFViewer {
        let viewer = NotePDFViewer(frame: frameView.bounds)
        viewer.routesScrollToNote = true
        viewer.onPageChange = { [weak self] in self?.pageDidChange() }
        viewer.onScaleChange = { [weak self] in self?.refreshControls() }
        viewer.onLink = { [weak self] url in self?.host?.open(url) }
        viewer.onEscape = { [weak self] in self?.returnToNote() }
        viewer.noteScrollView = { [weak self] in self?.host?.mediaCanvas?.enclosingScrollView }
        frameView.addSubview(viewer)
        self.viewer = viewer
        return viewer
    }

    private func unlock(_ password: String) -> Bool {
        guard let document, document.unlock(withPassword: password) else { return false }
        if let url = source.url { NotePDFDocuments.shared.unlocked(document, at: url) }
        let next = NotePDFDocuments.aspect(of: document)
        let changed = abs(NotePDFLayout.aspect(next) - NotePDFLayout.aspect(aspect)) > 0.001
        aspect = next
        attachRenderer()
        if let layer = frameView.layer { NoteMediaMotion.fadeIn(layer, duration: 0.2) }
        if changed { host?.invalidateMeasuredHeight() }
        refreshControls()
        refreshAccessibility()
        setHovered(hovered)
        return true
    }

    private func returnToNote() {
        guard let host, let window else { return }
        window.makeFirstResponder(host)
        host.focusHostBlock()
    }

    private func viewOriginal() {
        guard let url = source.url else { return }
        host?.open(url)
    }

    private func refreshAccessibility() {
        let name = props.alt.flatMap { $0.isEmpty ? nil : $0 } ?? host?.mediaFileName ?? source.fileName
        var label = "PDF" + (name.isEmpty ? "" : ": " + name)
        if let document, !document.isLocked { label += ", " + NotePDFPages.summary(count: document.pageCount) }
        setAccessibilityLabel(label)
    }

    private func viewerRect(for column: CGFloat) -> NSRect {
        let width = liveWidth ?? NotePDFLayout.displayWidth(fraction: props.width, columnWidth: column)
        let height = locked ? NotePDFLayout.viewerHeight(width: width, aspect: nil) : NotePDFLayout.viewerHeight(width: width, aspect: aspect)
        return NSRect(x: NotePDFLayout.originX(width: width, alignment: props.alignment, columnWidth: column), y: 0, width: width, height: height)
    }

    var viewerFrame: NSRect { viewerRect(for: bounds.width) }

    override func measureHeight(width: CGFloat) -> CGFloat { viewerRect(for: width).height }
    override var handleAnchorY: CGFloat { 14 }

    override func captionSpan(width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let frame = viewerRect(for: width)
        return (frame.minX, frame.width)
    }

    override func layout() {
        super.layout()
        let frame = viewerFrame
        NoteAnimation.withoutAnimation {
            frameView.frame = frame
            viewer?.frame = frameView.bounds
            staticPage?.frame = frameView.bounds
            lockView?.frame = frameView.bounds
        }
        shimmer.frame = frame
        NoteMediaMotion.instant {
            frameView.layer?.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardFill, in: self)
            frameView.layer?.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
            ring.frame = frame.insetBy(dx: -3, dy: -3)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
        let handleHeight = min(48, max(24, frame.height * 0.3))
        leadingHandle.frame = NSRect(x: frame.minX + 4, y: frame.midY - handleHeight / 2, width: 14, height: handleHeight)
        trailingHandle.frame = NSRect(x: frame.maxX - 18, y: frame.midY - handleHeight / 2, width: 14, height: handleHeight)
        let toolbarWidth = toolbar.fittingWidth
        toolbar.frame = NSRect(x: min(max(0, frame.maxX - 8 - toolbarWidth), max(0, bounds.width - toolbarWidth)), y: frame.minY + 8,
                               width: toolbarWidth, height: NoteMediaToolbar.height)
        let controlsWidth = min(controls.fittingWidth, frame.width - 16)
        controls.frame = NSRect(x: (frame.midX - controlsWidth / 2).rounded(), y: frame.maxY - 10 - NotePDFControlBar.height,
                                width: controlsWidth, height: NotePDFControlBar.height)
        controls.isHidden = controls.isHidden || controls.fittingWidth > frame.width - 16
        if let settleScale {
            self.settleScale = nil
            settle(from: settleScale)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { dismissMenu() } else { attachRenderer() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func setSelected(_ selected: Bool) {
        NoteMediaMotion.instant { ring.isHidden = !selected }
    }

    override func readOnlyDidChange() {
        configureToolbar()
        setHovered(hovered)
    }

    private func configureToolbar() {
        let column = bounds.width > 0 ? bounds.width : 10_000
        let fullWidth = viewerRect(for: column).width >= column - 1
        alignChip.content = .icon(.symbol(NoteImageContentView.alignmentSymbol(props.alignment)))
        var chips: [NoteControlButton] = []
        if editable {
            if !fullWidth { chips.append(alignChip) }
            if host?.offersCaption == true { chips.append(captionChip) }
        }
        if document != nil, !locked { chips.append(fullScreenChip) }
        chips.append(downloadChip)
        chips.append(originalChip)
        if editable {
            chips.append(replaceChip)
            chips.append(deleteChip)
        }
        toolbar.setButtons(chips)
        needsLayout = true
    }

    private func refreshControls() {
        guard let viewer else { return }
        controls.setPage(current: viewer.pageIndex, count: viewer.pageCount)
        controls.setZoom(canZoomOut: viewer.canZoom(in: false), canZoomIn: viewer.canZoom(in: true), fitsWidth: viewer.fitsWidth)
    }

    private func pageDidChange() {
        refreshControls()
        guard !hovered, viewer != nil, controls.fittingWidth <= viewerFrame.width - 16 else { return }
        controls.show()
        flashGeneration += 1
        let generation = flashGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.flashGeneration == generation, !self.hovered else { return }
            self.controls.hide()
        }
    }

    override func setHovered(_ hovered: Bool) {
        self.hovered = hovered
        let active = hovered || resizeStart != nil || alignmentMenu != nil
        if active, document != nil || source.url != nil {
            configureToolbar()
            layoutSubtreeIfNeeded()
            toolbar.show()
        } else {
            toolbar.hide()
        }
        if active, viewer != nil, !locked, controls.fittingWidth <= viewerFrame.width - 16 {
            flashGeneration += 1
            refreshControls()
            controls.show()
        } else if !active {
            controls.hide()
        }
        let showsHandles = active && editable && viewerFrame.height >= 36 && host?.offersColumnLayout == true
        for handle in [leadingHandle, trailingHandle] { handle.setRevealed(showsHandles) }
    }

    @discardableResult
    func presentFullScreen() -> Bool {
        guard let document, !document.isLocked, let host, let canvas = host.mediaCanvas, let stage = host.mediaOverlay,
              fullScreen == nil else { return false }
        let title = props.alt.flatMap { $0.isEmpty ? nil : $0 } ?? host.mediaFileName
        let overlay = NotePDFFullScreenOverlay.present(document: document, title: title.isEmpty ? "PDF" : title,
                                                       page: viewer?.pageIndex ?? 0, from: frameView.frame, of: self, in: canvas, overlay: stage)
        overlay.onDownload = { [weak self] in self?.host?.download() }
        overlay.onOpenOriginal = { [weak self] in self?.viewOriginal() }
        overlay.onLink = { [weak self] url in self?.host?.open(url) }
        overlay.onClose = { [weak self] page in
            self?.viewer?.goToPage(page)
            self?.refreshControls()
        }
        fullScreen = overlay
        return true
    }

    func beginResize() {
        guard editable else { return }
        resizeStart = (viewerFrame.width, bounds.width)
        dismissMenu()
    }

    func updateResize(edge: NoteMediaEdge, delta: CGFloat) {
        guard let start = resizeStart else { return }
        let raw = NotePDFLayout.rawResize(start: start.width, dragDelta: delta, leading: edge == .leading, alignment: props.alignment)
        liveWidth = NotePDFLayout.rubberBanded(raw, columnWidth: start.column).rounded()
        needsLayout = true
        host?.invalidateMeasuredHeight()
    }

    func endResize() {
        guard let start = resizeStart else { return }
        resizeStart = nil
        let live = liveWidth ?? start.width
        let fraction = NotePDFLayout.storedFraction(width: live, columnWidth: start.column)
        let settled = NotePDFLayout.displayWidth(fraction: fraction, columnWidth: start.column)
        liveWidth = nil
        if settled > 0, abs(live - settled) > 0.5 { settleScale = live / settled }
        if props.width != fraction { host?.commitWidth(fraction) }
        needsLayout = true
        host?.invalidateMeasuredHeight()
        setHovered(hovered)
    }

    private func settle(from scale: CGFloat) {
        guard !NoteAnimation.reduceMotion, let layer = frameView.layer else { return }
        let center = NoteAnimation.layerCenter(layer)
        let from = NoteAnimation.scaleTransform(scale, about: center)
        NoteMediaMotion.instant { layer.transform = CATransform3DIdentity }
        layer.add(NoteAnimation.spring("transform", .settle, from: NSValue(caTransform3D: from), to: NSValue(caTransform3D: CATransform3DIdentity)),
                  forKey: "pdf.settle")
    }

    private func toggleAlignmentMenu() {
        if alignmentMenu != nil { dismissMenu(); return }
        guard let overlay = host?.mediaOverlay else { return }
        let list = NoteMenuList()
        list.items = NoteAlignment.allCases.map { alignment in
            NoteMenuList.Item(id: alignment.rawValue, title: NoteImageContentView.alignmentTitle(alignment),
                              icon: .symbol(NoteImageContentView.alignmentSymbol(alignment)), isChecked: alignment == props.alignment)
        }
        list.onActivate = { [weak self] item in
            guard let self, let alignment = NoteAlignment(rawValue: item.id) else { return }
            self.dismissMenu()
            self.host?.setAlignment(alignment)
        }
        let panel = NoteFloatingPanel(content: list)
        panel.onDismiss = { [weak self, weak panel] in self?.menuDidClose(panel) }
        panel.present(in: overlay, anchor: overlay.convert(alignChip.bounds, from: alignChip), edge: .below)
        alignmentMenu = panel
        removeMenuMonitor()
        menuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let isKey = event.type == .keyDown, keyCode = event.keyCode
            let location = event.locationInWindow, windowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated {
                self?.menuEvent(isKey: isKey, keyCode: keyCode, location: location, windowNumber: windowNumber) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func menuEvent(isKey: Bool, keyCode: UInt16, location: NSPoint, windowNumber: Int) -> Bool {
        guard let panel = alignmentMenu else { return false }
        if isKey {
            guard keyCode == 53 else { return false }
            dismissMenu()
            return true
        }
        guard windowNumber == window?.windowNumber else { dismissMenu(); return false }
        if panel.bounds.contains(panel.convert(location, from: nil)) { return false }
        if alignChip.bounds.contains(alignChip.convert(location, from: nil)) { return false }
        dismissMenu()
        return false
    }

    private func dismissMenu() {
        guard let panel = alignmentMenu else { return }
        alignmentMenu = nil
        removeMenuMonitor()
        panel.dismiss(animated: true)
    }

    private func menuDidClose(_ panel: NoteFloatingPanel?) {
        guard alignmentMenu == nil || alignmentMenu === panel else { return }
        alignmentMenu = nil
        removeMenuMonitor()
        setHovered(hovered)
    }

    private func removeMenuMonitor() {
        if let menuMonitor { NSEvent.removeMonitor(menuMonitor) }
        menuMonitor = nil
    }
}

@MainActor
final class NotePDFFullScreenOverlay: NSView {
    var onClose: ((Int) -> Void)?
    var onDownload: (() -> Void)?
    var onOpenOriginal: (() -> Void)?
    var onLink: ((URL) -> Void)? {
        didSet { viewer.onLink = onLink }
    }
    private let backdrop = CALayer()
    private let stage = NSView()
    private let viewer = NotePDFViewer(frame: .zero)
    private let titleLabel: NSTextField
    private let toolbar = NoteMediaToolbar()
    private let controls = NotePDFControlBar()
    private let downloadChip = NoteToolbarButton(icon: .symbol("arrow.down.to.line"), label: "Download")
    private let originalChip = NoteToolbarButton(icon: .symbol("arrow.up.forward.square"), label: "View original")
    private let closeChip = NoteToolbarButton(icon: .symbol("xmark"), label: "Close", shortcut: "ESC")
    private var originRect: NSRect = .zero
    private weak var previousResponder: NSResponder?
    private weak var canvas: NSView?
    private var observers: [NSObjectProtocol] = []
    private var closing = false
    private static let header: CGFloat = 56
    private static let margin: CGFloat = 32

    private init(document: PDFDocument, title: String) {
        titleLabel = NoteMediaStyle.label(title, font: NoteMediaStyle.nunito(16, weight: .bold), color: NoteTheme.ink)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        backdrop.opacity = 0
        layer?.addSublayer(backdrop)
        stage.wantsLayer = true
        addSubview(stage)
        viewer.document = document
        viewer.onEscape = { [weak self] in self?.close() }
        viewer.onPageChange = { [weak self] in self?.refreshControls() }
        viewer.onScaleChange = { [weak self] in self?.refreshControls() }
        stage.addSubview(viewer)
        downloadChip.onPress = { [weak self] in self?.onDownload?() }
        originalChip.onPress = { [weak self] in self?.onOpenOriginal?() }
        closeChip.onPress = { [weak self] in self?.close() }
        toolbar.setButtons([downloadChip, originalChip, closeChip])
        controls.zoomOut.onPress = { [weak self] in self?.viewer.zoom(in: false) }
        controls.zoomIn.onPress = { [weak self] in self?.viewer.zoom(in: true) }
        controls.fit.onPress = { [weak self] in self?.viewer.fitWidth() }
        controls.previous.onPress = { [weak self] in self?.viewer.goToPreviousPage(nil) }
        controls.next.onPress = { [weak self] in self?.viewer.goToNextPage(nil) }
        for view in [titleLabel, toolbar, controls] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Full screen PDF: " + title)
        setAccessibilityHelp("Press Escape to close.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func present(document: PDFDocument, title: String, page: Int, from rect: NSRect, of view: NSView,
                        in canvas: NSView, overlay host: NSView) -> NotePDFFullScreenOverlay {
        let overlay = NotePDFFullScreenOverlay(document: document, title: title)
        overlay.canvas = canvas
        overlay.frame = host.convert(canvas.visibleRect.isEmpty ? canvas.bounds : canvas.visibleRect, from: canvas)
        host.addSubview(overlay)
        overlay.originRect = overlay.convert(rect, from: view)
        overlay.layoutSubtreeIfNeeded()
        overlay.viewer.fitWidth()
        overlay.viewer.goToPage(page)
        overlay.open()
        return overlay
    }

    private var stageFrame: NSRect {
        NSRect(x: Self.margin, y: Self.header, width: max(1, bounds.width - Self.margin * 2), height: max(1, bounds.height - Self.header - 20))
    }

    private func open() {
        previousResponder = window?.firstResponder
        window?.makeFirstResponder(viewer)
        refreshColors()
        refreshControls()
        controls.showImmediately()
        if let clip = canvas?.enclosingScrollView?.contentView {
            clip.postsFrameChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.followCanvas() }
            })
        }
        fadeBackdrop(visible: true)
        toolbar.show()
        for view in [titleLabel, controls] as [NSView] {
            view.wantsLayer = true
            if let layer = view.layer { NoteMediaMotion.fadeIn(layer, duration: 0.2) }
        }
        guard let layer = stage.layer else { return }
        if NoteAnimation.reduceMotion {
            NoteMediaMotion.fadeIn(layer, duration: 0.15)
        } else {
            let from = zoomTransform(for: layer)
            NoteMediaMotion.instant { layer.transform = CATransform3DIdentity }
            layer.add(NoteAnimation.spring("transform", .settle, from: NSValue(caTransform3D: from), to: NSValue(caTransform3D: CATransform3DIdentity)),
                      forKey: "pdf.zoom")
            NoteMediaMotion.fadeIn(layer, duration: 0.15)
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    private func zoomTransform(for layer: CALayer) -> CATransform3D {
        let target = stageFrame
        guard target.width > 0, originRect.width > 0 else { return CATransform3DIdentity }
        let scale = originRect.width / target.width
        let center = NoteAnimation.layerCenter(layer)
        var transform = CATransform3DMakeTranslation(center.x + originRect.midX - target.midX, center.y + originRect.midY - target.midY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -center.x, -center.y, 0)
    }

    private func followCanvas() {
        guard let canvas, let host = superview, !closing else { return }
        frame = host.convert(canvas.visibleRect.isEmpty ? canvas.bounds : canvas.visibleRect, from: canvas)
    }

    func close() {
        guard !closing else { return }
        closing = true
        if let window, let responder = window.firstResponder as? NSView, responder === self || responder.isDescendant(of: self) {
            let returns = (previousResponder as? NSView).map({ SavedFocus.mayReturn(to: $0, in: window) }) ?? true
            window.makeFirstResponder(returns ? previousResponder : nil)
        }
        let page = viewer.pageIndex
        onClose?(page)
        onClose = nil
        fadeBackdrop(visible: false)
        toolbar.hide()
        for view in [titleLabel, controls] as [NSView] { NoteAnimation.fade(view, visible: false, duration: 0.12) }
        guard let layer = stage.layer else { removeFromSuperview(); return }
        let target = NoteAnimation.reduceMotion ? CATransform3DIdentity : zoomTransform(for: layer)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated { self?.removeFromSuperview() } }
        NoteAnimation.fade(layer, to: 0, duration: 0.15)
        if !NoteAnimation.reduceMotion {
            let from = layer.presentation()?.transform ?? layer.transform
            NoteMediaMotion.instant { layer.transform = target }
            layer.add(NoteAnimation.spring("transform", .reorder, from: NSValue(caTransform3D: from), to: NSValue(caTransform3D: target)),
                      forKey: "pdf.zoom")
        }
        CATransaction.commit()
    }

    private func fadeBackdrop(visible: Bool) {
        let from = backdrop.presentation()?.opacity ?? backdrop.opacity
        let to: Float = visible ? 1 : 0
        NoteMediaMotion.instant { backdrop.opacity = to }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = to
        fade.duration = visible ? 0.2 : 0.15
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        backdrop.add(fade, forKey: "pdf.backdrop")
    }

    private func refreshControls() {
        controls.setPage(current: viewer.pageIndex, count: viewer.pageCount)
        controls.setZoom(canZoomOut: viewer.canZoom(in: false), canZoomIn: viewer.canZoom(in: true), fitsWidth: viewer.fitsWidth)
    }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant { backdrop.frame = bounds }
        let stageRect = stageFrame
        NoteAnimation.withoutAnimation {
            stage.frame = stageRect
            viewer.frame = stage.bounds
        }
        let toolbarWidth = toolbar.fittingWidth
        toolbar.frame = NSRect(x: bounds.width - Self.margin - toolbarWidth, y: (Self.header - NoteMediaToolbar.height) / 2,
                               width: toolbarWidth, height: NoteMediaToolbar.height)
        titleLabel.frame = NSRect(x: Self.margin, y: (Self.header - 22) / 2, width: max(0, toolbar.frame.minX - Self.margin - 16), height: 22)
        let controlsWidth = min(controls.fittingWidth, stageRect.width)
        controls.frame = NSRect(x: (stageRect.midX - controlsWidth / 2).rounded(), y: stageRect.maxY - 14 - NotePDFControlBar.height,
                                width: controlsWidth, height: NotePDFControlBar.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        NoteMediaMotion.instant { backdrop.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.backdrop, in: self) }
    }

    override func mouseDown(with event: NSEvent) {
        if !stage.frame.contains(convert(event.locationInWindow, from: nil)) { close() }
    }

    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close(); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { close() }

    override func accessibilityPerformCancel() -> Bool {
        close()
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, !closing {
            closing = true
            onClose?(viewer.pageIndex)
            onClose = nil
        }
    }
}
