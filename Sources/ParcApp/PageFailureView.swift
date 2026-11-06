import AppKit

// A display value copied from the exact native page's current crash snapshot,
//
// when a crash presentation exists; the shell does not classify Chromium
// termination codes or infer recovery from a Reload click.
struct RendererCrashPresentation: Equatable {
    let pageIdentifier: String
    let identity: AnyObject
    let terminationStatus: Int
    let errorCode: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pageIdentifier == rhs.pageIdentifier && lhs.identity === rhs.identity
    }
}

///
/// `SadTabHostView` / `SadTabView` (docs/web-interactions.md, WEB17): over the
/// web content's `FullOpacityBackgroundPrimary` backing, the `SadTab` artwork,
/// 96 points high, then 64 points below it "Tab crashed. Maybe reload the
/// page?" with "reload" as an underlined link, centred as one column, and
/// "Error code: N" 20 points in from the bottom-trailing corner, all in
///
///
///
/// counterpart (Chromium renders its own error page there), so Parc shows its
/// message in the same composition without the artwork.
@MainActor
final class PageFailureView: NSView {
    enum Presentation: Equatable {
        case navigation(String)
        case renderer(RendererCrashPresentation)
    }

    private(set) var presentation: Presentation?
    // The pane retains the real registered browser view. Only visibility is
    // changed here; neither the page nor its native host is replaced.
    weak var pageView: NSView? {
        willSet { restorePage() }
        didSet { if presentation != nil { hidePage() } }
    }
    private var originalAccessibilityHidden: Bool?
    var onReload: (() -> Void)?
    var onRetryRenderer: ((RendererCrashPresentation) -> Void)?
    var onRendererPresented: ((RendererCrashPresentation) -> Bool)?
    private var acknowledged: RendererCrashPresentation?
    let artwork = NSImageView()
    /// The sentence and its link, the column's second row.
    let sentence = PageFailureText()
    /// The bottom-trailing error code (a navigation failure's message).
    let corner = PageFailureText()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        artwork.image = SadTabContent.artwork
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.contentTintColor = SadTabContent.foreground
        // SwiftUI would name the image "SadTab"; it carries no information.
        artwork.setAccessibilityElement(false)
        sentence.identifier = NSUserInterfaceItemIdentifier("page-failure-retry")
        sentence.onActivate = { [weak self] in self?.invokeRetry() }
        addSubview(artwork); addSubview(sentence); addSubview(corner)
        // Sidebar ⌘S contract (docs/sidebar-motion.md): the text is drawn once
        // at its size and held centred while the pane's width animates; the
        // solid backing scales with the view.
        SidebarMotionController.pinDrawnContent(self, to: .scaleAxesIndependently)
        SidebarMotionController.pinDrawnContent(sentence, to: .center)
        SidebarMotionController.pinDrawnContent(corner, to: .center)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        clear()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showNavigationFailure(_ message: String) {
        acknowledged = nil
        presentation = .navigation(message)
        hidePage()
        artwork.isHidden = true
        sentence.segments = [SadTabContent.Segment(text: "This page couldn’t open. ", isLink: false),
                             SadTabContent.Segment(text: "Try again", isLink: true)]
        corner.segments = [SadTabContent.Segment(text: message, isLink: false)]
        corner.toolTip = message
        present()
    }

    func showRendererFailure(_ crash: RendererCrashPresentation) {
        if presentation != .renderer(crash) { acknowledged = nil }
        presentation = .renderer(crash)
        hidePage()
        artwork.isHidden = false
        sentence.segments = SadTabContent.segments(SadTabContent.message)
        corner.segments = [SadTabContent.Segment(text: SadTabContent.errorCode(crash.errorCode), isLink: false)]
        corner.toolTip = nil
        present()
    }

    private func present() {
        sentence.isEnabled = true
        needsLayout = true
        needsDisplay = true
        isHidden = false
    }

    func clear() {
        presentation = nil
        restorePage()
        acknowledged = nil
        sentence.isEnabled = false
        isHidden = true
    }

    private func hidePage() {
        guard let pageView else { return }
        if originalAccessibilityHidden == nil {
            originalAccessibilityHidden = pageView.isAccessibilityHidden()
        }
        pageView.setAccessibilityHidden(true)
        pageView.isHidden = true
    }

    private func restorePage() {
        if let pageView, let originalAccessibilityHidden {
            pageView.setAccessibilityHidden(originalAccessibilityHidden)
            pageView.isHidden = false
        }
        originalAccessibilityHidden = nil
    }

    private func invokeRetry() {
        switch presentation {
        case .navigation:
            onReload?()
        case .renderer(let crash):
            guard isActuallyVisible, acknowledged == crash else { return }
            //
            // real SadTab's button reloads (unbranded Chromium never offers
            // feedback), and the crash stays visible until the native
            // producer clears it. The callback validates page and snapshot.
            onRetryRenderer?(crash)
        case nil:
            break
        }
    }

    private var isActuallyVisible: Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized &&
            !isHiddenOrHasHiddenAncestor && bounds.width > 0 && bounds.height > 0
    }

    var ownsFirstResponder: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === self || responder.isDescendant(of: self)
    }

    @discardableResult
    func focusRendererAction(_ crash: RendererCrashPresentation) -> Bool {
        guard presentation == .renderer(crash), isActuallyVisible,
              let window, sentence.window === window else { return false }
        return sentence.takeExplicitFocus()
    }

    override func draw(_ dirtyRect: NSRect) {
        SadTabContent.backing.setFill()
        dirtyRect.fill()
        guard isActuallyVisible, case .renderer(let crash) = presentation,
              acknowledged != crash else { return }
        // Actual native drawing, not a nonnull snapshot or hidden preparation,
        // satisfies the real SadTab model's first-paint prerequisite.
        let accepted = onRendererPresented?(crash) == true
        guard presentation == .renderer(crash) else {
            // AppKit may clear this draw's dirty bit after callback reentry.
            // A replacement needs its own later real draw, never the old ACK.
            if case .renderer(let replacement) = presentation {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.presentation == .renderer(replacement) else { return }
                    self.needsDisplay = true
                }
            }
            return
        }
        if accepted { acknowledged = crash }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// SadTabView's body: a full-size ZStack holding the bottom-trailing
    /// error code and the centred column (artwork, 64 points, sentence).
    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height
        let showsArtwork = !artwork.isHidden
        let art = showsArtwork ? SadTabContent.artworkSize : .zero
        let spacing = showsArtwork ? SadTabContent.artworkSpacing : 0
        // The column is offered the full width (`frame(maxWidth: .infinity)`).
        let line = sentence.fittingSize(width: width)
        let column = art.height + spacing + line.height
        let top = (height - column) / 2
        artwork.frame = aligned(NSRect(x: (width - art.width) / 2, y: top, width: art.width, height: art.height))
        sentence.frame = aligned(NSRect(x: (width - line.width) / 2, y: top + art.height + spacing,
                                        width: line.width, height: line.height))
        // `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment:
        //
        // the two; only Parc's own long navigation message is cut short of
        // the column instead of running under it.
        let inset = SadTabContent.cornerInset
        corner.maximumHeight = showsArtwork ? .greatestFiniteMagnitude
            : max(SadTabContent.lineHeight, height - inset - max(0, top + column) - 8)
        let code = corner.fittingSize(width: max(0, width - 2 * inset))
        corner.frame = aligned(NSRect(x: width - inset - code.width, y: height - inset - code.height,
                                      width: code.width, height: code.height))
    }

    private func aligned(_ rect: NSRect) -> NSRect {
        backingAlignedRect(rect, options: [.alignMinXNearest, .alignMinYNearest, .alignWidthOutward, .alignHeightOutward])
    }
}

/// One row of SadTabView's text: an `HStack(spacing: 0)` of `Text`s in the
///
/// Hovering the link pushes the pointing-hand cursor and a tap activates it
///
/// explicit crash focus, so a crash in the focused page keeps the keyboard on
/// its action; a click does not focus it and it stays out of the key-view
///
@MainActor
final class PageFailureText: NSView {
    var segments: [SadTabContent.Segment] = [] {
        didSet {
            guard segments != oldValue else { return }
            rects = []; needsLayout = true; needsDisplay = true; refreshLink()
        }
    }
    var isEnabled = false { didSet { if isEnabled != oldValue { refreshLink() } } }
    var onActivate: (() -> Void)?
    /// A cap on each text's height; its last visible line is truncated.
    var maximumHeight: CGFloat = .greatestFiniteMagnitude {
        didSet { if maximumHeight != oldValue { rects = []; needsLayout = true; needsDisplay = true } }
    }
    private var rects: [NSRect] = []
    private var pressedInLink = false

    override var isFlipped: Bool { true }
    var text: String { segments.map(\.text).joined() }
    var hasLink: Bool { segments.contains { $0.isLink } }

    private func attributed(_ segment: SadTabContent.Segment) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: SadTabContent.font, .foregroundColor: SadTabContent.foreground]
        if segment.isLink { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return NSAttributedString(string: segment.text, attributes: attributes)
    }

    private func measure(_ segment: SadTabContent.Segment, width: CGFloat) -> NSSize {
        attributed(segment).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading]).size
    }

    /// The HStack's layout for a proposed width: each text keeps its ideal
    /// width when they all fit; otherwise the narrowest first takes at most an
    /// equal share of what remains and wraps inside it. Heights are capped by
    /// `maximumHeight`; texts are centred vertically.
    private func layoutRects(width: CGFloat) -> [NSRect] {
        let ideal = segments.map { measure($0, width: .greatestFiniteMagnitude).width }
        var widths = ideal
        if ideal.reduce(0, +) > width + 0.5 {
            var remaining = max(0, width)
            let order = ideal.indices.sorted { ideal[$0] < ideal[$1] }
            for (position, index) in order.enumerated() {
                widths[index] = min(ideal[index], floor(remaining / CGFloat(order.count - position)))
                remaining -= widths[index]
            }
        }
        // Measured with the same slack `draw` gives each text.
        let heights = segments.indices.map { min(maximumHeight, ceil(measure(segments[$0], width: widths[$0] + 1).height)) }
        let rowHeight = heights.max() ?? 0
        var x: CGFloat = 0
        return segments.indices.map { index in
            defer { x += widths[index] }
            return NSRect(x: x, y: (rowHeight - heights[index]) / 2, width: widths[index], height: heights[index])
        }
    }

    func fittingSize(width: CGFloat) -> NSSize {
        let laid = layoutRects(width: width)
        return NSSize(width: laid.last?.maxX ?? 0, height: laid.map(\.maxY).max() ?? 0)
    }

    private var currentRects: [NSRect] {
        if rects.count != segments.count { rects = layoutRects(width: bounds.width) }
        return rects
    }

    var linkRect: NSRect { zip(segments, currentRects).first { $0.0.isLink }?.1 ?? .zero }

    override func layout() {
        super.layout()
        rects = layoutRects(width: bounds.width)
        refreshLink()
    }

    override func draw(_ dirtyRect: NSRect) {
        for (segment, rect) in zip(segments, currentRects) {
            // Fractional widths are kept, as SwiftUI keeps them; the slack
            // keeps a measured line from wrapping on rounding.
            attributed(segment).draw(with: NSRect(x: rect.minX, y: rect.minY, width: rect.width + 1, height: rect.height),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func refreshLink() {
        window?.invalidateCursorRects(for: self)
        if !isEnabled, window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    override func resetCursorRects() {
        if isEnabled, hasLink { addCursorRect(linkRect, cursor: .pointingHand) }
    }

    /// Only the link takes the pointer; the rest of the text passes it on.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, hasLink, let superview, linkRect.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        pressedInLink = linkRect.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = linkRect.contains(convert(event.locationInWindow, from: nil))
        defer { pressedInLink = false }
        if pressedInLink, inside { performClick(nil) }
    }

    /// The link's action, as a click, Space or Return, or AX press sends it.
    @objc func performClick(_ sender: Any?) {
        guard isEnabled, hasLink else { return }
        onActivate?()
    }

    /// Only the engine's explicit crash focus moves the keyboard here; a
    ///
    private var takingExplicitFocus = false
    func takeExplicitFocus() -> Bool {
        guard let window else { return false }
        takingExplicitFocus = true
        defer { takingExplicitFocus = false }
        return window.makeFirstResponder(self)
    }
    override var acceptsFirstResponder: Bool {
        isEnabled && hasLink && (takingExplicitFocus || window?.firstResponder === self)
    }
    override var canBecomeKeyView: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case " ", "\r", "\u{3}": performClick(nil)
        default: super.keyDown(with: event)
        }
    }

    //
    override var focusRingMaskBounds: NSRect { NSApp.isFullKeyboardAccessEnabled ? linkRect : .zero }
    override func drawFocusRingMask() {
        guard NSApp.isFullKeyboardAccessEnabled else { return }
        NSBezierPath(rect: linkRect).fill()
    }

    override func isAccessibilityElement() -> Bool { !segments.isEmpty }
    override func accessibilityRole() -> NSAccessibility.Role? { hasLink ? .link : .staticText }
    override func accessibilityLabel() -> String? { text }
    override func accessibilityValue() -> Any? { hasLink ? nil : text }
    override func isAccessibilityEnabled() -> Bool { !hasLink || isEnabled }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, hasLink else { return false }
        performClick(nil)
        return true
    }
}
