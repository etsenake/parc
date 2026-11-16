import AppKit
import QuartzCore

@MainActor
final class ShortcutRecorderView: NSView {
    var shortcut: KeyboardShortcut? { didSet { needsDisplay = true; setAccessibilityValue(shortcut?.spokenDisplay ?? "No shortcut") } }
    var isConflicting = false { didSet { needsDisplay = true } }
    var rowSelected = false { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { if !isEnabled { cancelRecording() }; needsDisplay = true; setAccessibilityEnabled(isEnabled) } }
    var onBegin: (() -> Void)?
    var onPreview: (([String]) -> Void)?
    var onEnd: (() -> Void)?
    var onChange: ((KeyboardShortcut?) -> Bool)?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var tracking: NSTrackingArea?
    private var hovered = false
    private let borderLayer = CALayer()
    private let focusBorderLayer = CALayer()
    private let label = NSTextField(labelWithString: "---")
    private var appearanceObserver: NSObjectProtocol?
    private var animatedSize: NSSize?
    override var wantsUpdateLayer: Bool { true }
    var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private(set) var isRecording = false
    private var pendingSymbols: [String] = []
    override var acceptsFirstResponder: Bool { isEnabled }
    override var focusRingType: NSFocusRingType { get { .none } set {} }
    override init(frame: NSRect) {
        super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityChildren([])
        setAccessibilityHelp("Press to record a shortcut. Escape cancels; Delete removes the shortcut.")
        wantsLayer = true; layer?.masksToBounds = false
        layer?.addSublayer(borderLayer); layer?.addSublayer(focusBorderLayer)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center; label.isEditable = false; label.isSelectable = false
        label.setAccessibilityElement(false); label.setAccessibilityHidden(true); addSubview(label)
        appearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsDisplay = true; self?.updateLayer() }
            }
    }
    deinit {
        if let appearanceObserver { NSWorkspace.shared.notificationCenter.removeObserver(appearanceObserver) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override var isHidden: Bool {
        didSet { if isHidden { cancelRecording(); stopPulse() }; needsDisplay = true }
    }
    override func layout() { super.layout(); updateLayer() }
    override func viewDidHide() { super.viewDidHide(); hovered = false; cancelRecording(); stopPulse() }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { if isEnabled { window?.makeFirstResponder(self) } }
    override func accessibilityPerformPress() -> Bool { isEnabled && (window?.makeFirstResponder(self) ?? false) }
    override func becomeFirstResponder() -> Bool {
        guard isEnabled, super.becomeFirstResponder() else { return false }
        stopRecording(notify: false)
        isRecording = true; needsDisplay = true; onBegin?()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording, self.window?.isKeyWindow == true,
                  self.window?.firstResponder === self, event.window == nil || event.window === self.window else { return event }
            self.handle(event); return nil
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelRecording() }
        }
        return true
    }
    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        stopRecording(); return true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { hovered = false; stopRecording(); stopPulse() }; super.viewWillMove(toWindow: newWindow)
    }
    func cancelRecording() {
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        stopRecording()
    }
    private func stopRecording(notify: Bool = true) {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
        let ended = isRecording
        isRecording = false; pendingSymbols = []; stopPulse(); needsDisplay = true
        if ended, notify { onEnd?() }
    }
    override func keyDown(with event: NSEvent) { if isRecording { handle(event) } else { super.keyDown(with: event) } }
    override func flagsChanged(with event: NSEvent) { if isRecording { handle(event) } else { super.flagsChanged(with: event) } }
    private func handle(_ event: NSEvent) {
        guard isRecording else { return }
        if event.type == .flagsChanged {
            pendingSymbols = KeyboardShortcut(key: "", flags: event.modifierFlags).symbols.filter { !$0.isEmpty }
            onPreview?(pendingSymbols); needsDisplay = true; return
        }
        guard !event.isARepeat else { return }
        let flags = event.modifierFlags.intersection(KeyboardShortcut.modifierMask)
        if flags.isEmpty && event.keyCode == 53 { cancelRecording(); return }
        if event.keyCode == 48 && flags.subtracting(.shift).isEmpty {
            if flags.contains(.shift) { window?.selectPreviousKeyView(self) } else { window?.selectNextKeyView(self) }; return
        }
        let value: KeyboardShortcut?
        if flags.isEmpty && (event.keyCode == 51 || event.keyCode == 117) { value = nil }
        else {
            guard let captured = KeyboardShortcuts.shared.recordedChord(for: event) else { NSSound.beep(); cancelRecording(); return }
            value = captured
        }
        if onChange?(value) == true { shortcut = value }
        else { NSSound.beep() }
        cancelRecording()
    }
    override func updateLayer() { refreshPresentation(reduceMotion: reducesMotion) }
    func refreshPresentation(reduceMotion: Bool) {
        let focused = isRecording && window?.firstResponder === self
        let explicitDark = NSApp.appearance?.name == .darkAqua
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tint: NSColor? = isConflicting ? .systemRed :
            (focused || rowSelected || hovered ? .controlAccentColor : nil)
        let outline: NSColor
        if focused { outline = tint ?? .controlAccentColor }
        else if hovered, let tint { outline = tint.withAlphaComponent(0.4) }
        else if explicitDark { outline = rowSelected ? NSColor.white.withAlphaComponent(0.1) : gray(light: 0.858, dark: 0.243, isDark: dark) }
        else { outline = gray(light: 0.930, dark: 0.158, isDark: dark) }
        let background = explicitDark ? NSColor.white.withAlphaComponent(focused ? 0.8 : 0.1) : .white
        let ink = focused ? (tint ?? .controlAccentColor) :
            (explicitDark ? NSColor.white.withAlphaComponent(0.8) : gray(light: 0.523, dark: 0.494, isDark: dark))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        borderLayer.frame = bounds; borderLayer.cornerRadius = 6; borderLayer.cornerCurve = .continuous
        borderLayer.borderWidth = 1; borderLayer.borderColor = outline.cgColor(in: effectiveAppearance)
        borderLayer.backgroundColor = background.cgColor(in: effectiveAppearance)
        focusBorderLayer.frame = bounds; focusBorderLayer.cornerRadius = 6; focusBorderLayer.cornerCurve = .continuous
        focusBorderLayer.borderColor = tint?.cgColor(in: effectiveAppearance); focusBorderLayer.borderWidth = focused ? 1 : 0
        focusBorderLayer.opacity = 0
        label.stringValue = isRecording && !pendingSymbols.isEmpty ? pendingSymbols.joined() : (shortcut?.display ?? "---")
        label.textColor = ink
        let availableWidth = max(0, bounds.width)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        if label.cell!.cellSize.width > availableWidth {
            var lower: CGFloat = 8, upper: CGFloat = 12
            for _ in 0..<10 {
                let size = (lower + upper) / 2
                label.font = .systemFont(ofSize: size, weight: .medium)
                if label.cell!.cellSize.width <= availableWidth { lower = size }
                else { upper = size }
            }
            label.font = .systemFont(ofSize: lower, weight: .medium)
        }
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (bounds.height - height) / 2, width: availableWidth, height: height)
        CATransaction.commit()
        if focused, isEnabled, window?.isVisible == true, window?.isKeyWindow == true,
           window?.attachedSheet == nil, !isHiddenOrHasHiddenAncestor, !reduceMotion, bounds.width > 0, bounds.height > 0 {
            startPulseIfNeeded()
        } else { stopPulse() }
    }
    private func gray(light: CGFloat, dark: CGFloat, isDark: Bool) -> NSColor {
        NSColor(srgbRed: isDark ? dark : light, green: isDark ? dark : light, blue: isDark ? dark : light, alpha: 1)
    }
    private func startPulseIfNeeded() {
        guard animatedSize != bounds.size || focusBorderLayer.animation(forKey: "opacity") == nil else { return }
        stopPulse(); animatedSize = bounds.size
        let start = focusBorderLayer.convertTime(CACurrentMediaTime(), from: nil) + 0.5
        for (key, from, to) in [("transform.scale.x", 1.0, 1.175), ("transform.scale.y", 1.0, 1.4),
                                 ("opacity", 1.0, 0.0), ("cornerRadius", 6.0, 7.0)] {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from; animation.toValue = to
            animation.duration = 1.5; animation.beginTime = start; animation.repeatDuration = .infinity
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            focusBorderLayer.add(animation, forKey: key)
        }
    }
    private func stopPulse() {
        focusBorderLayer.removeAllAnimations(); animatedSize = nil
    }
}
