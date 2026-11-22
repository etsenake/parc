import AppKit

final class WindowStandardButtons: NSView {
    static let buttonDimension: CGFloat = 14
    static var buttonSpace: CGFloat {
        if #available(macOS 26, *) { return 9 }
        return 6
    }
    static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    static var stackSize: CGSize {
        let count = CGFloat(types.count)
        return CGSize(width: count * buttonDimension + max(0, (count - 1) * buttonSpace), height: buttonDimension)
    }

    private(set) var buttons: [NSButton] = []
    private var overlays: [DimmedOverlay] = []
    private(set) var mouseInside = false
    private var windowObservers: [NSObjectProtocol] = []

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.stackSize))
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { windowObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }; windowObservers = []
        guard let window else { return }
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.retestPointer() }
            })
        }
        retestPointer()
        guard buttons.isEmpty else { return }
        let made = Self.types.compactMap { NSWindow.standardWindowButton($0, for: window.styleMask) }
        let enabled = Self.types.map { window.standardWindowButton($0)?.isEnabled ?? true }
        guard made.count == Self.types.count else { return }
        for (button, enabled) in zip(made, enabled) {
            button.isEnabled = enabled
            let overlay = DimmedOverlay()
            addSubview(button); addSubview(overlay)
            buttons.append(button); overlays.append(overlay)
        }
        refreshHover()
        needsLayout = true; superview?.needsLayout = true
    }

    override func layout() {
        super.layout()
        for (index, (button, overlay)) in zip(buttons, overlays).enumerated() {
            let slot = CGRect(x: CGFloat(index) * (Self.buttonDimension + Self.buttonSpace), y: 0,
                              width: Self.buttonDimension, height: bounds.height)
            var size = button.intrinsicContentSize
            if #available(macOS 26, *) { size.width = Self.buttonDimension }
            button.frame = NSRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2, width: size.width, height: size.height)
            overlay.frame = button.frame.insetBy(dx: 1, dy: 1)
        }
    }

    var onGroupQuery: ((Bool) -> Void)?
    @objc(_mouseInGroup:) func mouseInGroup(_ button: Any?) -> Bool {
        onGroupQuery?(mouseInside)
        return mouseInside
    }

    override func mouseEntered(with event: NSEvent) { setMouseInside(true) }
    override func mouseMoved(with event: NSEvent) { setMouseInside(true) }
    override func mouseExited(with event: NSEvent) { setMouseInside(false) }
    override func viewDidHide() { super.viewDidHide(); setPresented(false) }
    override func viewDidUnhide() { super.viewDidUnhide(); setPresented(true) }
    func setPresented(_ presented: Bool) {
        if presented { retestPointer() } else { setMouseInside(false) }
    }
    private func retestPointer() {
        guard let window else { return setMouseInside(false) }
        setMouseInside(!isHiddenOrHasHiddenAncestor && bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }
    func setMouseInside(_ inside: Bool) {
        guard inside != mouseInside else { return }
        mouseInside = inside
        refreshHover()
    }
    private func refreshHover() {
        for overlay in overlays { overlay.isHidden = mouseInside }
        for button in buttons {
            button.needsDisplay = true
            if #available(macOS 26, *) { button.needsLayout = true }
        }
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        alphaValue = mouseInside ? 1 : (Self.isDark(effectiveAppearance) ? 0.33 : 0.1)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        overlays.forEach { $0.needsDisplay = true }
    }
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static func systemButtons(of window: NSWindow) -> [NSButton] {
        types.compactMap { window.standardWindowButton($0) }
    }
}

private final class DimmedOverlay: NSView {
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = WindowStandardButtons.isDark(effectiveAppearance)
            ? CGColor(srgbRed: 0.953, green: 0.953, blue: 0.918, alpha: 1) : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    }
    override func layout() { super.layout(); layer?.cornerRadius = bounds.height / 2 }
}

enum WindowFullscreenPhase: Equatable {
    case entering, expanded, exiting

    static func showsSystemButtons(_ phase: Self?, sidebarless: Bool) -> Bool {
        phase == .expanded || (phase == nil && sidebarless)
    }
    static func showsSidebarButtons(_ phase: Self?) -> Bool { phase == nil || phase == .exiting }

    static func current(_ tracked: Self?, inFullScreen: Bool) -> Self? {
        switch tracked {
        case nil, .expanded?: return inFullScreen ? .expanded : nil
        case .entering?, .exiting?: return tracked
        }
    }
    static func apply(_ phase: Self?, sidebarless: Bool, system: [NSButton]) -> Bool {
        let hidden = !showsSystemButtons(phase, sidebarless: sidebarless)
        for button in system where button.isHidden != hidden { button.isHidden = hidden }
        return showsSidebarButtons(phase)
    }
}
