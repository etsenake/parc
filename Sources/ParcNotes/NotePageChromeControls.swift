import AppKit

@MainActor
package final class NotePagePopover {
    private static var stack: [NotePagePopover] = []

    package let panel: NoteFloatingPanel
    weak var parent: NotePagePopover?
    package var onClose: (() -> Void)?
    package var onKeyDown: ((NSEvent) -> Bool)?
    var closesOnScroll = false
    private var exempt: [WeakView] = []
    private var monitor: Any?

    package init(content: NSView, parent: NotePagePopover? = nil) {
        panel = NoteFloatingPanel(content: content)
        self.parent = parent
        panel.onDismiss = { [weak self] in self?.didDismiss() }
    }

    package var isOpen: Bool { panel.isPresented }

    package static var topmost: NotePagePopover? { stack.last { $0.isOpen } }

    static func closeAll(animated: Bool = true) {
        for popover in stack.reversed() { popover.close(animated: animated) }
    }

    package func exempt(_ view: NSView) {
        exempt.removeAll { $0.view == nil }
        exempt.append(WeakView(view: view))
    }

    package func present(in host: NSView, anchor: NSRect, edge: NoteFloatingPanel.Edge = .below,
                 alignment: NoteFloatingPanel.Alignment = .leading, animated: Bool = true) {
        if parent == nil {
            for other in Self.stack where other !== self { other.close(animated: animated) }
        } else {
            for other in Self.stack where other !== self && other !== parent && !isAncestor(other) { other.close(animated: animated) }
        }
        Self.stack.removeAll { $0 === self || !$0.isOpen }
        Self.stack.append(self)
        panel.alignment = alignment
        panel.present(in: host, anchor: anchor, edge: edge, animated: animated)
        install()
    }

    package func reposition(anchor: NSRect, edge: NoteFloatingPanel.Edge = .below) {
        panel.reposition(anchor: anchor, edge: edge, animated: true)
    }

    package func close(animated: Bool = true) {
        for child in Self.stack where child.parent === self { child.close(animated: animated) }
        guard panel.isPresented else { return }
        panel.dismiss(animated: animated)
    }

    func contains(windowPoint point: NSPoint, in window: NSWindow?) -> Bool {
        guard panel.window === window else { return false }
        if panel.bounds.contains(panel.convert(point, from: nil)) { return true }
        for item in exempt {
            guard let view = item.view, view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
            if view.bounds.contains(view.convert(point, from: nil)) { return true }
        }
        return Self.stack.contains { $0.parent === self && $0.isOpen && $0.contains(windowPoint: point, in: window) }
    }

    private func isAncestor(_ other: NotePagePopover) -> Bool {
        var cursor = parent
        while let current = cursor {
            if current === other { return true }
            cursor = current.parent
        }
        return false
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.shouldSwallow(event) ?? false }
            return swallow ? nil : event
        }
    }

    private func shouldSwallow(_ event: NSEvent) -> Bool {
        guard isOpen else { return false }
        switch event.type {
        case .keyDown:
            guard Self.topmost === self, event.window === panel.window else { return false }
            if let onKeyDown, onKeyDown(event) { return true }
            if event.keyCode == 53 {
                close()
                return true
            }
            return false
        case .scrollWheel:
            if closesOnScroll, !isAuxiliary(event.window), !contains(windowPoint: event.locationInWindow, in: event.window) { close() }
            return false
        default:
            if isAuxiliary(event.window) { return false }
            if !contains(windowPoint: event.locationInWindow, in: event.window) { close() }
            return false
        }
    }

    private func isAuxiliary(_ window: NSWindow?) -> Bool {
        guard let window, let host = panel.window, window !== host else { return false }
        return window.sheetParent === host || host.attachedSheet === window || window is NSSavePanel
    }

    private func didDismiss() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Self.stack.removeAll { $0 === self }
        onClose?()
    }

    private struct WeakView {
        weak var view: NSView?
    }
}

@MainActor
enum NotePageChrome {
    static let controlsFill = NoteTheme.adaptive("Chrome.ControlsFill", light: NoteTheme.rgb(0xFFFFFF, 0.92), dark: NSColor(srgbRed: 0.071, green: 0.059, blue: 0.180, alpha: 0.9))

    static func fade(_ view: NSView, to alpha: CGFloat, duration: CFTimeInterval = NoteAnimation.hoverDuration) {
        guard let layer = view.layer else { view.alphaValue = alpha; return }
        NoteAnimation.fade(layer, to: Float(alpha), duration: NoteAnimation.reduceMotion ? min(duration, NoteAnimation.reducedFadeDuration) : duration)
    }
}

@MainActor
final class NotePageChromeGroup: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
        }
    }

    private func refresh() {
        NoteAnimation.withoutAnimation {
            layer?.backgroundColor = NoteTheme.resolved(NotePageChrome.controlsFill, in: self)
            layer?.borderColor = NoteTheme.resolved(NoteTheme.menuHairline, in: self)
            layer?.borderWidth = NoteTheme.isDark(effectiveAppearance) ? 0.5 : 0
        }
    }

    func arrange(_ views: [NSView], spacing: CGFloat = 2, inset: CGFloat = 3) {
        for view in subviews where !views.contains(view) { view.removeFromSuperview() }
        var x = inset
        var height: CGFloat = 0
        for view in views where !view.isHidden {
            if view.superview !== self { addSubview(view) }
            let size = view.intrinsicContentSize
            view.frame = NSRect(x: x, y: inset, width: size.width, height: size.height)
            x += size.width + spacing
            height = max(height, size.height)
        }
        setFrameSize(NSSize(width: x - spacing + inset, height: height + inset * 2))
    }
}

extension NSView {
    func drawInOwnAppearance(_ body: () -> Void) {
        effectiveAppearance.performAsCurrentDrawingAppearance(body)
    }

    package func redisplayChromeSubtree() {
        needsDisplay = true
        for view in subviews { view.redisplayChromeSubtree() }
    }
}
