import AppKit

@MainActor
final class SidebarDockStrip: NSScrollView {
    var items: [NSButton] = [] {
        didSet {
            guard items != oldValue else { return }
            let kept = Dictionary(slots.map { (ObjectIdentifier($0.button), $0) }, uniquingKeysWith: { first, _ in first })
            slots = items.map { kept[ObjectIdentifier($0)] ?? Slot(button: $0) }
            document.subviews = slots.map { $0.background } + items + slots.map { $0.dot }
            func follow(_ index: Int?) -> Int? { index.flatMap { $0 < oldValue.count ? items.firstIndex(of: oldValue[$0]) : nil } }
            let selected = follow(selection)
            if selection != nil, selected == nil { selectionLeft = true }
            selection = selected; hovered = follow(hovered)
            arrange(animated: false)
        }
    }
    var activeTints: [NSColor?] = [] { didSet { if activeTints != oldValue { arrange(animated: false) } } }
    var iconlessButtons: Set<ObjectIdentifier> = [] {
        didSet { if iconlessButtons != oldValue { arrange(animated: false) } }
    }
    var selectedIndex: Int? {
        get { selection }
        set {
            defer { selectionLeft = false }
            guard newValue != selection else { return }
            let animated = selection != nil || selectionLeft
            selection = newValue
            arrange(animated: animated)
            scrollPending = true; scrollToSelection(animated: animated)
        }
    }
    var dark: Bool? { didSet { if dark != oldValue { arrange(animated: true) } } }
    private(set) var layoutState = SidebarChromeLayout.DockLayout(items: [], contentWidth: 0, compact: false)

    private let document = NSView()
    private var slots: [Slot] = []
    private var selection: Int?
    private var selectionLeft = false
    private var hovered: Int?
    private var scrollPending = false
    private var tracking: NSTrackingArea?
    private var resignObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false; contentView.drawsBackground = false
        verticalScrollElasticity = .none; horizontalScrollElasticity = .none
        hasHorizontalScroller = false; hasVerticalScroller = false; autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: 0, left: SidebarChromeLayout.dockContentInset, bottom: 0, right: SidebarChromeLayout.dockContentInset)
        documentView = document
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        arrange(animated: false)
        if scrollPending { scrollToSelection(animated: false) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if dark == nil { arrange(animated: false) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { updateHover() }
    override func mouseMoved(with event: NSEvent) { updateHover() }
    override func mouseExited(with event: NSEvent) { updateHover() }
    var offerScroll: (NSEvent) -> Bool = { _ in false }
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var overflows: Bool {
        let clip = contentView, size = clip.bounds.size
        let low = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: -1e6, y: clip.bounds.minY), size: size)).minX
        let high = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 1e6, y: clip.bounds.minY), size: size)).minX
        return high - low > 0.5
    }
    override func scrollWheel(with event: NSEvent) {
        if overflows || !offerScroll(event) { super.scrollWheel(with: event) }
        updateHover()
    }
    override func viewDidHide() { super.viewDidHide(); setPresented(false) }
    override func viewDidUnhide() { super.viewDidUnhide(); setPresented(true) }
    func setPresented(_ presented: Bool) {
        if presented { updateHover(); return }
        guard hovered != nil else { return }
        hovered = nil; arrange(animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil; hovered = nil
        guard let window else { return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, self.hovered != nil else { return }; self.hovered = nil; self.arrange(animated: true) }
        }
    }

    private func updateHover() {
        updateHover(atWindowPoint: window?.isKeyWindow == true ? window?.mouseLocationOutsideOfEventStream : nil)
    }
    func updateHover(atWindowPoint point: NSPoint?) {
        if let point, let hovered, hovered < layoutState.items.count,
           window != nil, !isHiddenOrHasHiddenAncestor {
            let local = document.convert(point, from: nil)
            if document.visibleRect.contains(local), layoutState.items[hovered].contains(local) {
                return
            }
        }
        var index: Int?
        if let point, window != nil, !isHiddenOrHasHiddenAncestor {
            let point = document.convert(point, from: nil)
            if document.visibleRect.contains(point) { index = layoutState.items.firstIndex { $0.contains(point) } }
        }
        guard index != hovered else { return }
        hovered = index
        arrange(animated: true)
    }

    private func arrange(animated: Bool) {
        layoutState = SidebarChromeLayout.dockLayout(width: bounds.width, height: bounds.height, count: slots.count,
                                                     focused: hovered ?? selectedIndex)
        let documentFrame = NSRect(x: 0, y: 0, width: layoutState.contentWidth, height: bounds.height)
        if document.frame != documentFrame { document.frame = documentFrame }
        let dark = dark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let ink = NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0, alpha: 0.5)
        let fill = SidebarRowAppearance.controlFill(pressed: false, dark: dark)
        let animate = animated && window != nil && !reduceMotion()
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = animate
            if !animate { context.duration = 0 }
            for (index, (slot, item)) in zip(slots, layoutState.items).enumerated() {
                let frame = document.backingAlignedRect(item, options: .alignAllEdgesNearest)
                var side: CGFloat = 8, dotAlpha: CGFloat = 0, active: CGFloat = 0, inactive: CGFloat = 0
                switch SidebarChromeLayout.dockItemPresentation(compact: layoutState.compact, selection: index == selectedIndex ? 1 : 0,
                                                                highlighted: index == hovered, dark: dark,
                                                                iconless: iconlessButtons.contains(ObjectIdentifier(slot.button))) {
                case let .dot(dotSide, alpha): side = dotSide; dotAlpha = alpha
                case let .icon(activeAlpha, inactiveAlpha): active = activeAlpha; inactive = inactiveAlpha
                }
                let activeTint = index < activeTints.count ? activeTints[index] : nil
                slot.apply(Style(frame: frame, alpha: active + inactive, tint: active > 0 ? activeTint ?? ink : ink,
                                 dotFrame: NSRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side),
                                 dotAlpha: dotAlpha, ink: ink,
                                 backgroundAlpha: !layoutState.compact && index == hovered ? 1 : 0, fill: fill),
                           animated: animate)
            }
        }
    }

    private func scrollToSelection(animated: Bool) {
        guard bounds.width > 0 else { return }
        scrollPending = false
        guard let index = selectedIndex, index < layoutState.items.count else { return }
        let clip = contentView
        let proposed = NSRect(origin: NSPoint(x: layoutState.items[index].midX - clip.bounds.width / 2, y: clip.bounds.minY), size: clip.bounds.size)
        let origin = clip.constrainBoundsRect(proposed).origin
        guard origin != clip.bounds.origin else { return }
        if animated, window != nil, !reduceMotion() {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(origin)
            }
        } else { clip.setBoundsOrigin(origin) }
        reflectScrolledClipView(clip)
    }
}

private struct Style: Equatable {
    var frame: NSRect, alpha: CGFloat, tint: NSColor
    var dotFrame: NSRect, dotAlpha: CGFloat, ink: NSColor
    var backgroundAlpha: CGFloat, fill: NSColor
}

@MainActor
private final class Slot {
    static let backgroundIdentifier = NSUserInterfaceItemIdentifier("SidebarDockItemBackground")
    static let dotIdentifier = NSUserInterfaceItemIdentifier("SidebarDockItemPageIndicator")
    let button: NSButton
    let background = DockDot(), dot = DockDot()
    private var style: Style?

    init(button: NSButton) {
        self.button = button
        background.identifier = Self.backgroundIdentifier; dot.identifier = Self.dotIdentifier
        background.layer?.cornerRadius = 6; background.layer?.cornerCurve = .continuous
    }

    func apply(_ next: Style, animated: Bool) {
        let previous = style
        style = next
        let animate = animated && previous != nil
        func set<View: NSView>(_ view: View, _ change: (View) -> Void) { change(animate ? view.animator() : view) }
        if previous?.tint != next.tint { button.contentTintColor = next.tint }
        if previous?.ink != next.ink { dot.layer?.backgroundColor = next.ink.cgColor }
        if previous?.fill != next.fill { background.layer?.backgroundColor = next.fill.cgColor }
        if previous?.frame != next.frame {
            set(button) { $0.frame = next.frame }
            set(background) { $0.frame = next.frame }
        }
        if previous?.alpha != next.alpha { set(button) { $0.alphaValue = next.alpha } }
        if previous?.backgroundAlpha != next.backgroundAlpha { set(background) { $0.alphaValue = next.backgroundAlpha } }
        if previous?.dotFrame != next.dotFrame {
            dot.layer?.cornerRadius = next.dotFrame.width / 2
            set(dot) { $0.frame = next.dotFrame }
        }
        if previous?.dotAlpha != next.dotAlpha { set(dot) { $0.alphaValue = next.dotAlpha } }
    }
}

private final class DockDot: NSView {
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true; alphaValue = 0 }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
