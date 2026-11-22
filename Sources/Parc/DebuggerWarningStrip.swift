import AppKit
import ParcEngine
import QuartzCore
import ParcKit
import ParcSidebar

@MainActor
final class DebuggerWarningStrip: NSView {
    var onCancel: ((PCNativeDebuggerWarning) -> Void)?
    var onClose: ((PCNativeDebuggerWarning) -> Void)?
    private var rows: [DebuggerWarningRow] = []
    private var palette = ParcToastPalette(colors: [.windowBackgroundColor])
    var warnings: [PCNativeDebuggerWarning] { rows.map(\.warning) }
    var height: CGFloat { isHidden ? 0 : DebuggerWarningLayout.height(rows: rows.count) }
    var ownsFocus: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: self)
    }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(DebuggerWarningLayout.label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @discardableResult
    func update(_ next: [PCNativeDebuggerWarning], palette: ParcToastPalette, suppressed: Bool) -> Bool {
        let previous = warnings, wasHidden = isHidden
        let animate = window != nil && !suppressed && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var kept: [DebuggerWarningRow] = []
        for warning in next {
            if let row = rows.first(where: { $0.warning === warning }) {
                kept.append(row)
            } else {
                let row = DebuggerWarningRow(warning: warning)
                row.onCancel = { [weak self] warning in self?.onCancel?(warning) }
                row.onClose = { [weak self] warning in self?.onClose?(warning) }
                addSubview(row)
                kept.append(row)
                if animate { row.reveal() }
            }
        }
        for row in rows where !kept.contains(where: { $0 === row }) { row.removeFromSuperview() }
        rows = kept
        apply(palette)
        let hidden = rows.isEmpty || suppressed
        if isHidden != hidden { isHidden = hidden; setAccessibilityHidden(hidden) }
        needsLayout = true
        return DebuggerWarningLayout.keyViewsChanged(warnings, previous: previous, hidden: isHidden, wasHidden: wasHidden)
    }

    func focusFirstCancel() -> Bool {
        guard !isHiddenOrHasHiddenAncestor, let window, let cancel = rows.first?.cancel else { return false }
        return window.makeFirstResponder(cancel) && window.firstResponder === cancel
    }

    func apply(_ next: ParcToastPalette) {
        palette = next
        appearance = NSAppearance(named: next.isDark ? .darkAqua : .aqua)
        for row in rows { row.apply(next) }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * DebuggerWarningLayout.rowHeight,
                               width: bounds.width, height: DebuggerWarningLayout.rowHeight)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.background.setFill()
        bounds.fill()
        let gradient = palette.isDark
            ? NSGradient(starting: NSColor.black.withAlphaComponent(0.2), ending: NSColor.black.withAlphaComponent(0.4))
            : NSGradient(starting: NSColor.white.withAlphaComponent(0.4), ending: NSColor.white.withAlphaComponent(0.2))
        gradient?.draw(in: bounds, angle: 90)
        let hairline = 1 / max(1, window?.backingScaleFactor ?? 2)
        palette.foreground.withAlphaComponent(0.12).setFill()
        for index in 1...max(1, rows.count) {
            NSRect(x: 0, y: CGFloat(index) * DebuggerWarningLayout.rowHeight - hairline,
                   width: bounds.width, height: hairline).fill()
        }
    }
}

@MainActor
private final class DebuggerWarningRow: NSView {
    let warning: PCNativeDebuggerWarning
    var onCancel: ((PCNativeDebuggerWarning) -> Void)?
    var onClose: ((PCNativeDebuggerWarning) -> Void)?
    private let icon = NSImageView()
    private let message = NSTextField(labelWithString: "")
    let cancel: DebuggerWarningCancelButton
    private let close = DeveloperToolbarButton(symbol: "xmark", title: DebuggerWarningLayout.closeTitle)
    override var isFlipped: Bool { true }

    init(warning: PCNativeDebuggerWarning) {
        self.warning = warning
        cancel = DebuggerWarningCancelButton(title: warning.cancelTitle)
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(warning.message)
        setAccessibilityHelp(DebuggerWarningLayout.label)
        icon.image = NSImage(systemSymbolName: DebuggerWarningLayout.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        message.stringValue = warning.message
        message.font = .systemFont(ofSize: 13, weight: .medium)
        message.lineBreakMode = .byTruncatingHead
        message.maximumNumberOfLines = 1
        message.cell?.truncatesLastVisibleLine = true
        message.toolTip = warning.message
        message.setAccessibilityElement(false)
        cancel.setAccessibilityLabel(warning.cancelTitle)
        cancel.setAccessibilityHelp(DebuggerWarningLayout.cancelHelp)
        cancel.toolTip = DebuggerWarningLayout.cancelHelp
        cancel.target = self; cancel.action = #selector(cancelPressed)
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: DebuggerWarningLayout.closeTitle)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        close.setAccessibilityHelp(DebuggerWarningLayout.closeHelp)
        LiveShortcutToolTip.set(close, DebuggerWarningLayout.closeTitle)
        close.actionBlock = { [weak self] in
            guard let self else { return }; self.onClose?(self.warning)
        }
        addSubview(icon); addSubview(message); addSubview(cancel); addSubview(close)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func cancelPressed() { onCancel?(warning) }

    func apply(_ palette: ParcToastPalette) {
        let ink = palette.foreground
        icon.contentTintColor = ink.withAlphaComponent(0.85)
        message.textColor = ink
        cancel.style(ink: ink, dark: palette.isDark)
        close.contentTintColor = ink.withAlphaComponent(0.7)
    }

    override func layout() {
        super.layout()
        let frames = DebuggerWarningLayout.frames(in: bounds, cancelWidth: cancel.preferredWidth)
        icon.isHidden = !frames.showsIcon
        icon.frame = frames.icon
        let lineHeight = ceil(message.intrinsicContentSize.height)
        message.frame = NSRect(x: frames.message.minX, y: frames.message.midY - lineHeight / 2,
                               width: frames.message.width, height: lineHeight)
        cancel.frame = frames.cancel
        close.frame = frames.close
    }

    func reveal() {
        guard let layer else { return }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = BlockedContentSign.revealDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
        let spring = DeveloperToolbarSpring.spring(response: DeveloperToolbarSpring.restResponse,
                                                   dampingRatio: DeveloperToolbarSpring.restDampingRatio)
        spring.keyPath = "transform.translation.y"
        spring.fromValue = DebuggerWarningLayout.revealOffset
        spring.toValue = 0
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "parc.debugger-warning.reveal")
    }
}

@MainActor
final class DebuggerWarningCancelButton: PointingHandButton {
    private static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private var ink = NSColor.black
    private var dark = false
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        font = Self.font
        focusRingType = .exterior
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var preferredWidth: CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: Self.font]).width) + DebuggerWarningLayout.cancelPadding * 2
    }

    func style(ink: NSColor, dark: Bool) {
        self.ink = ink; self.dark = dark
        needsDisplay = true
    }

    override var isFlipped: Bool { true }
    override var isEnabled: Bool { didSet { if !isEnabled { hovered = false }; needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = isEnabled; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hovered = false; needsDisplay = true }
    override func viewDidHide() { super.viewDidHide(); hovered = false }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        ParcDialogStyle.continuousRect(bounds, radius: DebuggerWarningLayout.cornerRadius).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = DebuggerWarningLayout.cornerRadius
        let body = bounds
        let shape = ParcDialogStyle.continuousRect(body, radius: radius)
        NSColor.white.withAlphaComponent(dark ? 0.2 : 0.6).setFill()
        shape.fill()
        NSGraphicsContext.saveGraphicsState()
        let ring = ParcDialogStyle.continuousRect(body, radius: radius)
        ring.append(ParcDialogStyle.continuousRect(body.insetBy(dx: 3, dy: 3), radius: max(0, radius - 3)))
        ring.windingRule = .evenOdd
        ring.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(dark ? 0.12 : 0.2), ending: NSColor.white.withAlphaComponent(0))?
            .draw(in: NSRect(x: body.minX, y: body.minY, width: body.width, height: body.height * 0.25), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        let border = ParcDialogStyle.continuousRect(body.insetBy(dx: 0.25, dy: 0.25), radius: radius - 0.25)
        border.lineWidth = 0.5
        ink.withAlphaComponent(dark ? 0.2 : 0.36).setStroke()
        border.stroke()
        let pressed = cell?.isHighlighted == true && isEnabled
        if pressed || hovered {
            NSColor.black.withAlphaComponent(pressed ? 0.05 : 0.025).setFill()
            shape.fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font,
            .foregroundColor: isEnabled ? ink : ink.withAlphaComponent(0.4)]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2),
                                 withAttributes: attributes)
    }
}
