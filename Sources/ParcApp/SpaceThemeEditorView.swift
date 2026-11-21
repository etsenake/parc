import AppKit
import Combine
import ParcCore
import QuartzCore
import SwiftUI

final class SpaceThemeEditorView: NSView {
    var onPreview: ((SpaceTheme) -> Void)?
    var onCommit: ((SpaceTheme) -> Void)?
    var onCommitChange: ((SpaceTheme, SpaceTheme) -> SpaceTheme)?
    weak var windowThemeUndo: UndoManager?
    override var undoManager: UndoManager? { windowThemeUndo ?? super.undoManager }
    var onDismiss: (() -> Void)?
    var onSetAppearance: ((AppAppearance) -> Void)?
    var onTooltipThemeChange: ((SpaceTheme) -> Void)?
    var onPresetPageChange: ((Int) -> Void)?
    enum Presentation { case setup, sidebar }
    var presentation: Presentation = .sidebar { didSet { applyPresentation() } }
    var theme: SpaceTheme { editor.theme }
    static let colorPadSide: CGFloat = 340
    static let sidebarEmptyStateText = "Tap to pick a color for this space"
    var emptyStatePrompt: String? {
        guard theme.primaryColor == nil else { return nil }
        switch presentation {
        case .setup: return "Click to pick a color"
        case .sidebar: return Self.sidebarEmptyStateText
        }
    }
    private var editor: SpaceThemeEditorState
    private var committedTheme: SpaceTheme
    private var reportedTooltipTheme: SpaceTheme?
    private let performHapticFeedback: @MainActor () -> Void
    private enum Input { case pad, intensity, noise }
    private var activeInput: Input?
    private let background = NSVisualEffectView()
    private let resources: ThemeEditorResources
    private let pad: ThemeColorPad
    private let intensity = ThemeIntensityControl()
    private let noise: ThemeNoiseControl
    private var appearanceButtons: [ThemeAppearanceButton] = []
    private var appearanceObservation: NSKeyValueObservation?
    private var presets: [ThemePresetButton] = []
    private let previous = ThemeIconButton.chevron("chevron.left", label: "Previous color presets")
    private let next = ThemeIconButton.chevron("chevron.right", label: "Next color presets")
    private let add = ThemeIconButton(symbol: "plus", label: "Add color")
    private let remove = ThemeIconButton(symbol: "minus", label: "Remove color")
    private var page: Int
    private let families = ["Brand", "Brand", "Pastel", "Drab", "Greyscale"]
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 356, height: 508) }

    init(theme: SpaceTheme, presetPage: Int = 0,
         scrollPublisher: ((AnyPublisher<Double, Never>) -> AnyPublisher<Double, Never>)? = nil,
         scrollTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         performHapticFeedback: @escaping @MainActor () -> Void = ThemeHapticFeedback.perform,
         resources: ThemeEditorResources? = nil) {
        let resources = resources ?? .main
        self.resources = resources
        pad = ThemeColorPad(grid: resources.image("DotGrid"))
        editor = SpaceThemeEditorState(theme: theme)
        committedTheme = theme
        page = presetPage
        noise = ThemeNoiseControl(scrollPublisher: scrollPublisher, now: scrollTime, resources: resources)
        self.performHapticFeedback = performHapticFeedback
        super.init(frame: NSRect(x: 0, y: 0, width: 356, height: 508))
        page = min(families.count - 1, max(0, page))
        wantsLayer = true
        layer?.cornerRadius = 12; layer?.masksToBounds = true
        background.material = .popover; background.blendingMode = .withinWindow; background.state = .active
        addSubview(background)
        addSubview(pad)
        pad.editor = editor
        pad.onBegin = { [weak self] in self?.beginEditing(.pad) }
        pad.onDiscreteBegin = { [weak self] in self?.beginDiscreteEditing(.pad) }
        pad.onChange = { [weak self] x, y in
            guard let self, self.editor.isGestureInProgress else { return }
            self.preview(self.editor.moveColor(x: x, y: y))
        }
        pad.onEnd = { [weak self] in self?.completeGesture() }
        for (index, appearance) in AppAppearance.allCases.enumerated() {
            let button = ThemeAppearanceButton(appearance: appearance, resources: resources.bundle)
            button.onAction = { [weak self] in
                guard let self else { return }
                self.finishEditing()
                self.onSetAppearance?(appearance)
                self.refreshAppearance()
            }
            appearanceButtons.append(button); pad.addSubview(button)
            button.frame = NSRect(x: 114 + index * 40, y: 24, width: 32, height: 32)
        }
        remove.onAction = { [weak self] in guard let self else { return }; self.discrete { self.editor.removeColor() } }
        add.onAction = { [weak self] in guard let self else { return }; self.discrete { self.editor.addColor() } }
        pad.addSubview(remove); pad.addSubview(add)
        previous.onAction = { [weak self] in self?.changePage(-1) }
        next.onAction = { [weak self] in self?.changePage(1) }
        addSubview(previous); addSubview(next)
        for index in 0..<9 {
            let button = ThemePresetButton()
            button.onAction = { [weak self] in self?.selectPreset(index) }
            presets.append(button); addSubview(button)
        }
        intensity.onBegin = { [weak self] in self?.beginEditing(.intensity) }
        intensity.onDiscreteBegin = { [weak self] in self?.beginDiscreteEditing(.intensity) }
        intensity.onChange = { [weak self] value in
            guard let self, self.editor.isGestureInProgress else { return }
            let previous = self.theme.intensity
            let changed = self.editor.setIntensity(value)
            if changed, ThemeHapticFeedback.shouldPerformIntensity(from: previous, to: self.theme.intensity) {
                self.performHapticFeedback()
            }
            self.preview(changed)
        }
        intensity.onEnd = { [weak self] in self?.completeGesture() }
        addSubview(intensity)
        noise.onBegin = { [weak self] in self?.beginEditing(.noise) }
        noise.onDiscreteBegin = { [weak self] in self?.beginDiscreteEditing(.noise) }
        noise.onChange = { [weak self] value, gesture in
            guard let self, self.editor.isGestureInProgress else { return }
            let previous = self.theme.noise
            let changed = self.editor.setNoise(value, gesture: gesture)
            if changed, ThemeHapticFeedback.shouldPerformNoise(from: previous, to: self.theme.noise, gesture: gesture) {
                self.performHapticFeedback()
            }
            self.preview(changed)
        }
        noise.onEnd = { [weak self] in self?.completeGesture() }
        noise.onClick = { [weak self] in guard let self else { return }; self.discrete { self.editor.cycleTexture() } }
        addSubview(noise)
        addSubview(noise.marker)
        setAccessibilityLabel("Space theme editor")
        appearanceObservation = NSApplication.shared.observe(\.appearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshAppearance() }
        }
        refresh(); loadPresetPage(); applyPresentation()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        background.frame = bounds
        pad.frame = NSRect(x: 8, y: 8, width: Self.colorPadSide, height: Self.colorPadSide)
        let center = pad.bounds.midX
        for (index, button) in appearanceButtons.enumerated() {
            button.frame = NSRect(x: center - 56 + CGFloat(index) * 40, y: 24, width: 32, height: 32)
        }
        remove.frame = NSRect(x: center - 36, y: pad.bounds.height - 48, width: 32, height: 32)
        add.frame = NSRect(x: center + 4, y: pad.bounds.height - 48, width: 32, height: 32)
        let rowY = pad.frame.maxY + 18
        previous.frame = NSRect(x: 8, y: rowY - 4, width: 32, height: 32)
        next.frame = NSRect(x: bounds.width - 40, y: rowY - 4, width: 32, height: 32)
        let spacing = (bounds.width - 120) / 8
        for (index, button) in presets.enumerated() {
            button.frame = NSRect(x: 48 + CGFloat(index) * spacing, y: rowY, width: 24, height: 24)
        }
        intensity.frame = NSRect(x: 6, y: rowY + 46, width: bounds.width - 108, height: 80)
        noise.frame = NSRect(x: bounds.width - 98, y: rowY + 46, width: 80, height: 80)
        noise.marker.frame = noise.frame.insetBy(dx: -ThemeNoiseMarker.outset, dy: -ThemeNoiseMarker.outset)
    }
    var firstKeyView: NSView { pad }
    func chainKeyViews(to following: NSView) {
        let controls: [NSView] = [pad] + appearanceButtons + [remove, add, previous] + presets + [next, intensity, noise]
        for (view, after) in zip(controls, controls.dropFirst()) { view.nextKeyView = after }
        noise.nextKeyView = following
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportedTooltipTheme = nil
        if window == nil { finishEditing() } else { reportTooltipTheme() }
    }
    private func reportTooltipTheme() {
        guard window != nil, theme != reportedTooltipTheme else { return }
        reportedTooltipTheme = theme
        onTooltipThemeChange?(theme)
    }
    func finishEditing() {
        pad.cancelGesture(); intensity.cancelGesture(); noise.cancelGesture()
        completeGesture()
    }
    private func beginEditing(_ input: Input) {
        if input != .pad { pad.cancelGesture() }
        if input != .intensity { intensity.cancelGesture() }
        if input != .noise { noise.cancelGesture() }
        if let previous = activeInput, previous != input { completeGesture() }
        activeInput = input
        editor.beginGesture()
    }
    private func beginDiscreteEditing(_ input: Input) {
        finishEditing()
        beginEditing(input)
    }
    private func completeGesture() {
        activeInput = nil
        if editor.finishGesture() { commitTheme() }
        refresh()
    }
    private func preview(_ changed: Bool) {
        guard changed else { return }
        refresh(); onPreview?(theme)
    }
    private func discrete(_ change: () -> Bool) {
        finishEditing()
        guard change() else { return }
        refresh(); onPreview?(theme); commitTheme()
    }
    private func commitTheme() {
        let proposed = theme
        let accepted: SpaceTheme
        if let onCommitChange { accepted = onCommitChange(committedTheme, proposed) }
        else { onCommit?(proposed); accepted = proposed }
        committedTheme = accepted
        if accepted != proposed { replaceEditorTheme(accepted); onPreview?(accepted) }
    }
    @discardableResult func synchronizeTheme(_ theme: SpaceTheme) -> Bool {
        guard theme != committedTheme else { return false }
        committedTheme = theme
        replaceEditorTheme(theme)
        return true
    }
    func resetTheme(_ theme: SpaceTheme) {
        committedTheme = theme
        replaceEditorTheme(theme)
    }
    private func replaceEditorTheme(_ theme: SpaceTheme) {
        pad.cancelGesture(); intensity.cancelGesture(); noise.cancelGesture()
        activeInput = nil
        editor = SpaceThemeEditorState(theme: theme)
        pad.editor = editor
        refresh()
    }
    private func applyPresentation() {
        switch presentation {
        case .setup:
            layer?.cornerRadius = 16
            layer?.cornerCurve = .continuous
            background.isHidden = true
        case .sidebar:
            layer?.cornerRadius = 12
            background.isHidden = false
        }
        pad.emptyStateText = emptyStatePrompt
        pad.needsDisplay = true
    }
    private func refresh() {
        pad.refresh(animated: !editor.isGestureInProgress)
        pad.refreshHoverFromPointer()
        pad.emptyStateText = emptyStatePrompt
        intensity.value = theme.intensity
        noise.value = theme.noise; noise.texture = theme.texture
        add.isEnabled = editor.canAddColor; remove.isEnabled = editor.canRemoveColor
        refreshAppearance()
        reportTooltipTheme()
    }
    private func refreshAppearance() {
        let choice = AppAppearance.current
        for button in appearanceButtons {
            button.isSelected = button.appearanceChoice == choice
        }
    }
    private func changePage(_ delta: Int) {
        page = min(families.count - 1, max(0, page + delta)); loadPresetPage()
        onPresetPageChange?(page)
    }
    private func loadPresetPage() {
        let family = families[page]
        for (index, button) in presets.enumerated() {
            button.color = resources.preset(page: page, index: index)?.color
            button.isEnabled = button.color != nil
            button.setAccessibilityLabel("\(family) color \(index + 1)")
            LiveShortcutToolTip.set(button, "\(family) \(index + 1)", anchor: .bottom)
        }
        previous.isEnabled = page > 0; next.isEnabled = page < families.count - 1
    }
    private func selectPreset(_ index: Int) {
        guard let preset = resources.preset(page: page, index: index),
              let rgb = preset.color.usingColorSpace(.displayP3),
              let themeColor = ThemeColor(red: min(1, max(0, rgb.redComponent)), green: min(1, max(0, rgb.greenComponent)),
                                         blue: min(1, max(0, rgb.blueComponent)), colorSpace: .displayP3) else { return }
        discrete { editor.selectPreset(themeColor, colorCount: preset.colorCount, wheel: preset.wheel) }
    }
    fileprivate func editorMenu() -> NSMenu {
        let menu = NSMenu()
        let undoItem = NSMenuItem(title: windowThemeUndo?.undoMenuItemTitle ?? "Undo Theme Change", action: #selector(undo(_:)), keyEquivalent: "")
        undoItem.target = self; undoItem.isEnabled = (windowThemeUndo?.canUndo ?? editor.canUndo) || editor.isGestureInProgress
        menu.addItem(undoItem)
        let redoItem = NSMenuItem(title: windowThemeUndo?.redoMenuItemTitle ?? "Redo Theme Change", action: #selector(redo(_:)), keyEquivalent: "")
        redoItem.target = self; redoItem.isEnabled = windowThemeUndo?.canRedo ?? editor.canRedo; menu.addItem(redoItem)
        menu.addItem(.separator())
        let remove = NSMenuItem(title: "Delete All Colors", action: #selector(deleteAllColors(_:)), keyEquivalent: "")
        remove.target = self; remove.isEnabled = editor.canRemoveColor; menu.addItem(remove)
        menu.autoenablesItems = false
        return menu
    }
    @objc private func deleteAllColors(_ sender: Any?) { discrete { editor.removeAllColors() } }
    @objc func undo(_ sender: Any?) {
        finishEditing()
        if let windowThemeUndo { windowThemeUndo.undo() }
        else if editor.undo() { refresh(); onPreview?(theme); commitTheme() }
    }
    @objc func redo(_ sender: Any?) {
        finishEditing()
        if let windowThemeUndo { windowThemeUndo.redo() }
        else if editor.redo() { refresh(); onPreview?(theme); commitTheme() }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let focused = window?.firstResponder as? NSView
        guard focused === self || focused?.isDescendant(of: self) == true else { return super.performKeyEquivalent(with: event) }
        if event.keyCode == 53, let onDismiss { finishEditing(); onDismiss(); return true }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) { redo(nil) } else { undo(nil) }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onDismiss { finishEditing(); onDismiss(); return }
        super.keyDown(with: event)
    }
}

@MainActor
final class ThemeEditorResources {
    static let main = ThemeEditorResources(bundle: .main)
    struct Preset: Decodable {
        let name: String
        let red: Double
        let green: Double
        let blue: Double
        let colorSpace: ThemeColor.ColorSpace
        let page: Int
        let index: Int
        let colorCount: Int
        let wheel: SpaceTheme.Wheel
        var color: NSColor {
            ThemeEditorResources.color(ThemeColor(red: red, green: green, blue: blue, colorSpace: colorSpace)!)
        }
    }
    let bundle: Bundle
    private lazy var presets: [Preset] = {
        guard let url = url("presets", extension: "json"), let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([Preset].self, from: data),
              records.count == 45, records.allSatisfy({
                  ThemeColor(red: $0.red, green: $0.green, blue: $0.blue, colorSpace: $0.colorSpace) != nil
                      && (0..<5).contains($0.page) && (0..<9).contains($0.index)
                      && (1...3).contains($0.colorCount)
              }), Set(records.map { $0.page * 9 + $0.index }).count == 45 else { return [] }
        return records
    }()
    private lazy var images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in ["DotGrid", "GrainKnob", "SandKnob", "DenimKnob", "TweedKnob"] {
            if let url = url(name, extension: "png"), let image = NSImage(contentsOf: url) { result[name] = image }
        }
        return result
    }()
    init(bundle: Bundle) { self.bundle = bundle }
    private func url(_ name: String, extension ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "ThemeEditor")
    }
    func image(_ name: String) -> NSImage? { images[name] }
    func preset(page: Int, index: Int) -> Preset? {
        presets.first { $0.page == page && $0.index == index }
    }
    nonisolated static func color(_ value: ThemeColor) -> NSColor {
        switch value.colorSpace {
        case .sRGB: return NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: 1)
        case .displayP3: return NSColor(displayP3Red: value.red, green: value.green, blue: value.blue, alpha: 1)
        case .linearSRGB:
            let components: [CGFloat] = [value.red, value.green, value.blue, 1]
            let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            return NSColor(cgColor: CGColor(colorSpace: space, components: components)!)!
        }
    }
}

@MainActor
private enum ThemeEditorColors {
    static let separator = color(dark: 0.15, light: 0.15)
    static let track = color(dark: 0.075, light: 0.075)
    static let foreground = color(dark: 0.45, light: 0.3)
    static let chevron = labelColor(opacity: 0.6)
    static func thumbShadow(hover: CGFloat) -> NSShadow {
        let shadow = NSShadow(), opacity = ThemeControlHandle.shadowOpacity(hover: hover)
        shadow.shadowColor = color(dark: opacity, light: opacity)
        shadow.shadowBlurRadius = ThemeControlHandle.shadowBlur(hover: hover)
        shadow.shadowOffset = NSSize(width: 0, height: -ThemeControlHandle.shadowDrop(hover: hover))
        return shadow
    }
    nonisolated private static func labelColor(opacity: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            var label = NSColor.labelColor
            appearance.performAsCurrentDrawingAppearance { label = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor }
            return label.withAlphaComponent(label.alphaComponent * opacity)
        }
    }
    nonisolated private static func color(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: dark) : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: light)
        }
    }
}

private class ThemeIconButton: NSButton {
    var onAction: (() -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?
    init(symbol: String, label: String, configuration: NSImage.SymbolConfiguration? = nil,
         tint: NSColor = .secondaryLabelColor) {
        super.init(frame: .zero)
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        title = ""; image = configuration.flatMap { symbolImage?.withSymbolConfiguration($0) } ?? symbolImage
        imagePosition = .imageOnly; isBordered = false; focusRingType = .exterior
        contentTintColor = tint
        (cell as? NSButtonCell)?.imageDimsWhenDisabled = false
        target = self; action = #selector(invoke)
        setAccessibilityLabel(label); LiveShortcutToolTip.set(self, label, anchor: .bottom)
    }
    static func chevron(_ symbol: String, label: String) -> ThemeIconButton {
        ThemeIconButton(symbol: symbol, label: label,
                        configuration: NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold, scale: .medium),
                        tint: ThemeEditorColors.chevron)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { onAction?() }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); super.mouseDown(with: event) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .cursorUpdate], owner: self)
        addTrackingArea(tracking!)
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    var hoverStyleEnabled = true { didSet { if hoverStyleEnabled != oldValue { updateHover(animated: false) } } }
    override var isEnabled: Bool {
        didSet { if isEnabled != oldValue { updateHover(animated: false); needsDisplay = true } }
    }
    private lazy var motion = ThemeButtonMotionDriver(view: self)
    override func mouseEntered(with event: NSEvent) { hovered = true; updateHover(animated: true) }
    override func mouseExited(with event: NSEvent) { hovered = false; updateHover(animated: true) }
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        hovered = ThemeButtonMotionDriver.pointerInside(self); updateHover(animated: true)
        motion.update(pressed: flag)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { hovered = false; motion.reset() }
    }
    private func updateHover(animated: Bool) {
        motion.update(hovered: hovered && hoverStyleEnabled && isEnabled, animatesHover: animated)
    }
    override func draw(_ dirtyRect: NSRect) {
        ThemeButtonStyle.draw(in: bounds, motion: motion.motion, isEnabled: isEnabled) { super.draw(dirtyRect) }
    }
}

private final class ThemePresetButton: PointingHandButton {
    var onAction: (() -> Void)?
    var color: NSColor? { didSet { needsDisplay = true } }
    init() {
        super.init(frame: .zero)
        title = ""; isBordered = false; focusRingType = .exterior
        target = self; action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { onAction?() }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); super.mouseDown(with: event) }
    override func draw(_ dirtyRect: NSRect) {
        guard let color else { return }
        color.setFill(); NSBezierPath(ovalIn: bounds).fill()
        NSColor.black.withAlphaComponent(isHighlighted ? 0.22 : 0.1).setStroke()
        let width: CGFloat = isHighlighted ? 3 : 2
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: width / 2, dy: width / 2)); ring.lineWidth = width; ring.stroke()
    }
}

enum ThemeColorPadMotion {
    static func update(_ handle: CALayer, position: CGPoint, scale: CGFloat,
                       animatePosition: Bool, allowsMotion: Bool) {
        let oldPosition = handle.presentation()?.position ?? handle.position
        let oldScale = handle.presentation()?.transform.m11 ?? handle.transform.m11
        let positionChanged = handle.position != position
        let scaleChanged = handle.transform.m11 != scale
        handle.position = position
        handle.transform = CATransform3DMakeScale(scale, scale, 1)
        if !allowsMotion {
            handle.removeAnimation(forKey: "position")
            handle.removeAnimation(forKey: "hover")
            return
        }
        if scaleChanged {
            let spring = CASpringAnimation(keyPath: "transform.scale")
            let omega = 2 * Double.pi / 0.25
            spring.mass = 1; spring.stiffness = omega * omega; spring.damping = 2 * 0.9 * omega
            spring.fromValue = oldScale; spring.toValue = scale; spring.duration = spring.settlingDuration
            handle.add(spring, forKey: "hover")
        }
        if !animatePosition {
            handle.removeAnimation(forKey: "position")
        } else if positionChanged {
            let spring = CASpringAnimation(keyPath: "position")
            let omega = 2 * Double.pi / 0.28
            spring.mass = 1; spring.stiffness = omega * omega; spring.damping = 2 * 0.63 * omega
            spring.fromValue = NSValue(point: oldPosition); spring.toValue = NSValue(point: position)
            spring.duration = spring.settlingDuration
            handle.add(spring, forKey: "position")
        }
    }
}

struct ThemeButtonMotion {
    private(set) var isHovered = false
    private(set) var isPressed = false
    private(set) var press: CGFloat = 1
    private var pressVelocity = 0.0
    private var hoverFrom: CGFloat = 0
    private var hoverElapsed = 0.1
    var hover: CGFloat {
        let target: CGFloat = isHovered ? 1 : 0
        return hoverElapsed >= 0.1 ? target : hoverFrom + (target - hoverFrom) * CGFloat(Self.easeOut(hoverElapsed / 0.1))
    }
    var hoverScale: CGFloat { 1 + 0.05 * hover }
    var scale: CGFloat { press * hoverScale }
    var isSettled: Bool { press == pressTarget && hoverElapsed >= 0.1 }
    private var pressTarget: CGFloat { isPressed ? 0.9 : 1 }
    mutating func setHovered(_ hovered: Bool, animated: Bool) {
        guard hovered != isHovered else { return }
        hoverFrom = hover; isHovered = hovered; hoverElapsed = animated ? 0 : 0.1
    }
    mutating func setPressed(_ pressed: Bool, animated: Bool) {
        isPressed = pressed
        if !animated { press = pressTarget; pressVelocity = 0 }
    }
    mutating func settle() { hoverElapsed = 0.1; press = pressTarget; pressVelocity = 0 }
    mutating func advance(_ dt: Double) {
        hoverElapsed = min(0.1, hoverElapsed + dt)
        let w0 = 2 * Double.pi / 0.3, zeta = 0.5, wd = w0 * (1 - zeta * zeta).squareRoot()
        let x0 = Double(press - pressTarget), a = pressVelocity + zeta * w0 * x0
        let e = exp(-zeta * w0 * dt), c = cos(wd * dt), s = sin(wd * dt)
        let x = e * (x0 * c + a / wd * s)
        pressVelocity = e * (a * c - x0 * wd * s) - zeta * w0 * x
        if abs(x) < 0.0005 && abs(pressVelocity) < 0.005 { press = pressTarget; pressVelocity = 0 }
        else { press = pressTarget + CGFloat(x) }
    }
    private static func easeOut(_ x: Double) -> Double {
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let t = (low + high) / 2
            if 3 * (1 - t) * t * t * 0.58 + t * t * t < x { low = t } else { high = t }
        }
        let t = (low + high) / 2
        return 3 * (1 - t) * t * t + t * t * t
    }
}

@MainActor final class ThemeButtonMotionDriver {
    private(set) var motion = ThemeButtonMotion()
    private weak var view: NSView?
    private var timer: Timer?
    private var frameTime: CFTimeInterval = 0
    private let now: () -> CFTimeInterval
    private let allowsMotionOverride: (() -> Bool)?
    private let scheduleFrame: (Timer) -> Void
    private var reduceMotionObserver: NSObjectProtocol?
    init(view: NSView, now: @escaping () -> CFTimeInterval = { CACurrentMediaTime() },
         allowsMotion: (() -> Bool)? = nil,
         scheduleFrame: @escaping (Timer) -> Void = { RunLoop.main.add($0, forMode: .common) }) {
        self.view = view; self.now = now
        allowsMotionOverride = allowsMotion
        self.scheduleFrame = scheduleFrame
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                self?.settle()
            }
        }
    }
    deinit {
        timer?.invalidate()
        if let reduceMotionObserver { NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver) }
    }
    static func pointerInside(_ view: NSView) -> Bool {
        view.window.map { view.bounds.contains(view.convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
    }
    func update(hovered: Bool? = nil, pressed: Bool? = nil, animatesHover: Bool = true) {
        let hovered = hovered ?? motion.isHovered, pressed = pressed ?? motion.isPressed
        guard hovered != motion.isHovered || pressed != motion.isPressed else { return }
        let allowsMotion = allowsMotionOverride?()
            ?? (view?.window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        motion.setHovered(hovered, animated: allowsMotion && animatesHover)
        motion.setPressed(pressed, animated: allowsMotion)
        view?.needsDisplay = true
        guard !motion.isSettled, timer == nil else { return }
        frameTime = now()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated { self?.frame(timer) }
        }
        self.timer = timer; scheduleFrame(timer)
    }
    func reset() { timer?.invalidate(); timer = nil; motion = ThemeButtonMotion() }
    private func settle() {
        guard timer != nil else { return }
        timer?.invalidate(); timer = nil
        motion.settle(); view?.needsDisplay = true
    }
    private func frame(_ timer: Timer) {
        guard self.timer === timer else { return }
        let time = now()
        motion.advance(time - frameTime); frameTime = time
        view?.needsDisplay = true
        if motion.isSettled { timer.invalidate(); self.timer = nil }
    }
}

@MainActor enum ThemeButtonStyle {
    static func shape(_ rect: NSRect) -> CGPath {
        RoundedRectangle(cornerRadius: 8, style: .continuous).path(in: rect).cgPath
    }
    static func fill(_ share: CGFloat = 1) -> NSColor {
        let secondary = NSColor.secondaryLabelColor.usingColorSpace(.sRGB) ?? .gray
        return secondary.withAlphaComponent(secondary.alphaComponent * 0.2 * share)
    }
    static func draw(in rect: NSRect, motion: ThemeButtonMotion, isEnabled: Bool, label: () -> Void) {
        guard let context = NSGraphicsContext.current?.cgContext else { label(); return }
        context.saveGState()
        if !isEnabled { context.setAlpha(0.33); context.beginTransparencyLayer(auxiliaryInfo: nil) }
        context.addPath(shape(rect)); context.clip()
        func scale(_ factor: CGFloat) {
            context.translateBy(x: rect.midX, y: rect.midY); context.scaleBy(x: factor, y: factor)
            context.translateBy(x: -rect.midX, y: -rect.midY)
        }
        scale(motion.hoverScale)
        if motion.hover > 0 { fill(motion.hover).setFill(); NSBezierPath(rect: rect).fill() }
        scale(motion.press)
        label()
        if !isEnabled { context.endTransparencyLayer() }
        context.restoreGState()
    }
}

private final class ThemeColorPad: NSView {
    weak var editor: SpaceThemeEditorState?
    var onBegin: (() -> Void)?
    var onDiscreteBegin: (() -> Void)?
    var onChange: ((Double, Double) -> Void)?
    var onEnd: (() -> Void)?
    var emptyStateText: String? { didSet { needsDisplay = true } }
    private let grid: NSImage?
    private let handleContainer = CALayer()
    private var handles: [CALayer] = []
    private var hovered: Int?
    private var tracking: NSTrackingArea?
    private var dragOrigin: NSPoint?
    private var dragHandleOrigin: NSPoint?
    private var motionObserver: NSObjectProtocol?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(grid: NSImage?) {
        self.grid = grid
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 8; layer?.cornerCurve = .continuous; layer?.masksToBounds = true
        layer?.addSublayer(handleContainer)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider); setAccessibilityLabel("Theme color pad")
        setAccessibilityHelp("Drag to adjust hue and lightness. Arrow keys move the primary color.")
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                self?.handles.forEach { $0.removeAllAnimations() }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { handles.forEach { $0.removeAllAnimations() } }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.05).setFill(); bounds.fill()
        if let grid, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState(); context.beginTransparencyLayer(auxiliaryInfo: nil)
            grid.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSColor.labelColor.withAlphaComponent(0.4).setFill(); bounds.fill(using: .sourceIn)
            context.endTransparencyLayer(); context.restoreGState()
        }
        if editor?.theme.primaryColor == nil, let emptyStateText, !emptyStateText.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.45)
            ]
            let size = emptyStateText.size(withAttributes: attributes)
            emptyStateText.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                                withAttributes: attributes)
        }
    }
    func cancelGesture() {
        if dragOrigin != nil { NSCursor.arrow.set(); setHoveredHandle(nil) }
        dragOrigin = nil; dragHandleOrigin = nil
        updateButtonHoverStyle(at: window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) })
    }
    override func layout() { super.layout(); handleContainer.frame = bounds; refresh(animated: false) }
    func refresh(animated: Bool) {
        guard let editor else { return }
        let colors = editor.theme.colors
        while handles.count > colors.count { handles.removeLast().removeFromSuperlayer() }
        let existingCount = handles.count
        while handles.count < colors.count {
            let handle = CALayer(); handle.borderColor = NSColor.white.cgColor
            handle.shadowColor = NSColor.black.cgColor; handle.shadowOpacity = 0.12
            handle.shadowRadius = 4; handle.shadowOffset = CGSize(width: 0, height: 1)
            handles.append(handle); handleContainer.addSublayer(handle)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, color) in colors.enumerated() {
            let handle = handles[index], normalized = editor.normalizedPosition(for: color)
            let point = CGPoint(x: (normalized.x + 1) * bounds.width / 2, y: (normalized.y + 1) * bounds.height / 2)
            if index >= existingCount { handle.position = point }
            let size: CGFloat = index == 0 ? 44 : 27
            handle.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            handle.cornerRadius = size / 2; handle.borderWidth = index == 0 ? 4 : 3
            handle.backgroundColor = ThemeEditorResources.color(color).cgColor
            let scale: CGFloat = hovered == index ? 1.1 : 1
            ThemeColorPadMotion.update(handle, position: point, scale: scale,
                animatePosition: animated,
                allowsMotion: window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        CATransaction.commit()
        setAccessibilityValue(editor.theme.primaryColor?.hex ?? "No colors")
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
                                  owner: self)
        addTrackingArea(tracking!)
    }
    private func handle(at point: NSPoint) -> Int? {
        handles.indices.first { handles[$0].frame.insetBy(dx: -4, dy: -4).contains(point) }
    }
    private func buttonContains(_ point: NSPoint) -> Bool {
        subviews.contains { !$0.isHidden && $0.frame.contains(point) }
    }
    private func hoverCursor(at point: NSPoint) -> NSCursor {
        buttonContains(point) ? .pointingHand : handle(at: point) == nil ? .arrow : .openHand
    }
    private func updateButtonHoverStyle(at point: NSPoint?) {
        let enabled = dragHandleOrigin == nil && point.map { handle(at: $0) == nil } ?? true
        for case let button as ThemeIconButton in subviews { button.hoverStyleEnabled = enabled }
        for case let button as ThemeAppearanceButton in subviews { button.hoverStyleEnabled = enabled }
    }
    override func cursorUpdate(with event: NSEvent) {
        if dragOrigin == nil { hoverCursor(at: convert(event.locationInWindow, from: nil)).set() }
    }
    private func setHoveredHandle(_ index: Int?) {
        if index != hovered { hovered = index; refresh(animated: editor?.isGestureInProgress == false) }
    }
    private func updateHoveredHandle(at point: NSPoint) {
        setHoveredHandle(buttonContains(point) ? nil : handle(at: point))
    }
    func refreshHoverFromPointer() {
        guard dragOrigin == nil, editor?.isGestureInProgress != true, let window, window.isKeyWindow else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(point) else { setHoveredHandle(nil); return }
        updateHoveredHandle(at: point)
        updateButtonHoverStyle(at: point)
        hoverCursor(at: point).set()
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHoveredHandle(at: point)
        updateButtonHoverStyle(at: point)
        hoverCursor(at: point).set()
    }
    override func mouseExited(with event: NSEvent) {
        if dragHandleOrigin == nil { setHoveredHandle(nil); NSCursor.arrow.set() }
        updateButtonHoverStyle(at: nil)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard !buttonContains(point) else { return }
        window?.makeFirstResponder(self)
        onBegin?()
        refresh(animated: false)
        dragOrigin = point
        dragHandleOrigin = handle(at: point).map { handles[$0].position }
        if dragHandleOrigin != nil { NSCursor.closedHand.set() }
        updateButtonHoverStyle(at: point)
        updateColor(dragHandleOrigin ?? point)
        if dragHandleOrigin != nil { updateHoveredHandle(at: point) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let handleOrigin = dragHandleOrigin {
            if NSCursor.current != .closedHand { NSCursor.closedHand.set() }
            updateColor(NSPoint(x: handleOrigin.x + point.x - origin.x, y: handleOrigin.y + point.y - origin.y))
        } else {
            updateColor(point)
            let inside = bounds.contains(point)
            if inside { updateHoveredHandle(at: point) } else { setHoveredHandle(nil) }
            (inside ? hoverCursor(at: point) : NSCursor.arrow).set()
            updateButtonHoverStyle(at: point)
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard dragOrigin != nil else { return }
        let draggedKnob = dragHandleOrigin != nil
        dragOrigin = nil; dragHandleOrigin = nil; onEnd?()
        let point = convert(event.locationInWindow, from: nil), inside = bounds.contains(point)
        if draggedKnob {
            if inside { updateHoveredHandle(at: point) } else { setHoveredHandle(nil) }
            (inside ? hoverCursor(at: point) : NSCursor.arrow).set()
        }
        updateButtonHoverStyle(at: inside ? point : nil)
    }
    private func updateColor(_ point: NSPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        onChange?((point.x - bounds.midX) / bounds.midX, (point.y - bounds.midY) / bounds.midY)
    }
    override func keyDown(with event: NSEvent) {
        guard [123,124,125,126].contains(event.keyCode) else { super.keyDown(with: event); return }
        onDiscreteBegin?()
        guard let editor else { return }
        let position = editor.theme.primaryColor.map { editor.normalizedPosition(for: $0) } ?? (x: 0, y: 0)
        let step = event.modifierFlags.contains(.shift) ? 0.1 : 0.02
        onChange?(position.x + (event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0),
                  position.y + (event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0))
        onEnd?()
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let owner = superview as? SpaceThemeEditorView else { return nil }
        return owner.editorMenu()
    }
}

enum ThemeControlHandle {
    static let dialSteps = 20
    static func shadowOpacity(hover: CGFloat) -> CGFloat { 0.05 + 0.07 * hover }
    static func shadowBlur(hover: CGFloat) -> CGFloat { 1.5 + 2.5 * hover }
    static func shadowDrop(hover: CGFloat) -> CGFloat { 2 + hover }
    static func dotFill(step: Int, value: Double) -> CGFloat {
        CGFloat(min(1, max(0, value * Double(dialSteps) - Double(step))))
    }
}

private final class ThemeIntensityControl: NSControl {
    var value: Double = 0 { didSet { needsDisplay = true; setAccessibilityValue(Int(value * 100)) } }
    var onBegin: (() -> Void)?
    var onDiscreteBegin: (() -> Void)?
    var onChange: ((Double) -> Void)?
    var onEnd: (() -> Void)?
    static let drawingOutset = NSSize(width: 4, height: 10)
    private var pointerActive = false
    private var pointerInside = false
    private var tracking: NSTrackingArea?
    private lazy var thumbMotion = ThemeButtonMotionDriver(view: self)
    private var track: NSRect { bounds.insetBy(dx: Self.drawingOutset.width, dy: Self.drawingOutset.height) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider); setAccessibilityLabel("Theme intensity")
        setAccessibilityMinValue(0); setAccessibilityMaxValue(100)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let track = self.track
        let width = track.width - 16, padding = 8.0, waveWidth = width - 2 * padding
        let amplitude = 15 * value, frequency = waveWidth / (2 * .pi - 0.25)
        let centerX = track.minX + 8 + padding + waveWidth * value
        let wave = NSBezierPath()
        for x in stride(from: CGFloat(0), through: waveWidth, by: 1) {
            let point = NSPoint(x: track.minX + x + 8 + padding,
                               y: bounds.midY + amplitude * sin(x / (waveWidth / frequency) + .pi))
            if x == 0 { wave.move(to: point) } else { wave.line(to: point) }
        }
        wave.lineWidth = 5; wave.lineCapStyle = .round
        ThemeEditorColors.separator.setStroke(); wave.stroke()
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: 0, y: 0, width: centerX, height: bounds.height).clip()
        ThemeEditorColors.track.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX + 8, y: bounds.midY - 8, width: width, height: 16), xRadius: 8, yRadius: 8).fill()
        ThemeEditorColors.foreground.setStroke(); wave.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let hover = thumbMotion.motion.hover, scale = thumbMotion.motion.hoverScale
        let thumbWidth = (12 + amplitude) * scale, thumbHeight = (44 + amplitude) * scale
        NSGraphicsContext.saveGraphicsState()
        ThemeEditorColors.thumbShadow(hover: hover).set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: centerX - thumbWidth / 2, y: bounds.midY - thumbHeight / 2,
                                        width: thumbWidth, height: thumbHeight),
                     xRadius: thumbWidth / 2, yRadius: thumbWidth / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, track.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
    override func accessibilityFrame() -> NSRect {
        guard let window else { return super.accessibilityFrame() }
        return window.convertToScreen(convert(track, to: nil))
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: track, options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking!)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { pointerInside = false; thumbMotion.reset() }
    }
    override func mouseEntered(with event: NSEvent) { pointerInside = true; updateHover() }
    override func mouseExited(with event: NSEvent) { pointerInside = false; updateHover() }
    private func updateHover() { thumbMotion.update(hovered: pointerInside || pointerActive) }
    private func pointerIsInside(_ point: NSPoint?) -> Bool { point.map(track.contains) ?? false }
    func cancelGesture() {
        if pointerActive { NSCursor.arrow.set() }
        pointerActive = false
        pointerInside = pointerIsInside(window.flatMap { $0.isKeyWindow ? convert($0.mouseLocationOutsideOfEventStream, from: nil) : nil })
        updateHover()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); onBegin?(); pointerActive = true
        updateHover()
        NSCursor.closedHand.set(); update(event)
    }
    override func mouseDragged(with event: NSEvent) { if pointerActive { update(event) } }
    override func mouseUp(with event: NSEvent) {
        pointerInside = pointerIsInside(convert(event.locationInWindow, from: nil))
        guard pointerActive else { updateHover(); return }
        pointerActive = false; onEnd?(); NSCursor.openHand.set()
        updateHover()
    }
    private func update(_ event: NSEvent) {
        let track = self.track
        guard track.width > 32 else { return }
        let x = convert(event.locationInWindow, from: nil).x - track.minX - 16
        let next = min(1, max(0, x / (track.width - 32)))
        if abs(next - value) >= 0.001 { onChange?(next) }
    }
    override func keyDown(with event: NSEvent) {
        if [123,124,125,126].contains(event.keyCode) {
            onDiscreteBegin?(); onChange?(value + ([124,126].contains(event.keyCode) ? 0.05 : -0.05)); onEnd?()
        } else { super.keyDown(with: event) }
    }
    override func accessibilityPerformIncrement() -> Bool { onDiscreteBegin?(); onChange?(value + 0.05); onEnd?(); return true }
    override func accessibilityPerformDecrement() -> Bool { onDiscreteBegin?(); onChange?(value - 0.05); onEnd?(); return true }
}

private final class ThemeNoiseMarker: NSView {
    static let outset: CGFloat = 8
    var value: Double = 0 { didSet { if value != oldValue { needsDisplay = true } } }
    private(set) lazy var motion = ThemeButtonMotionDriver(view: self)
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("ThemeNoiseMarker")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY), angle = (-90 + value * 360) * .pi / 180
        let hover = motion.motion.hover, scale = motion.motion.hoverScale, radius = 32 - 8 * (scale - 1)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x + cos(angle) * radius, yBy: center.y + sin(angle) * radius)
        transform.rotate(byRadians: angle + .pi / 2); transform.concat()
        ThemeEditorColors.thumbShadow(hover: hover).set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: -4 * scale, y: -8 * scale, width: 8 * scale, height: 16 * scale),
                     xRadius: 4 * scale, yRadius: 4 * scale).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class ThemeNoiseControl: NSControl {
    var value: Double = 0 { didSet { needsDisplay = true; marker.value = value; setAccessibilityValue(Int(value * 100)) } }
    let marker = ThemeNoiseMarker()
    var texture: SpaceTheme.Texture = .grain { didSet { needsDisplay = true } }
    var onBegin: (() -> Void)?
    var onDiscreteBegin: (() -> Void)?
    var onChange: ((Double, SpaceThemeNoiseGesture) -> Void)?
    var onEnd: (() -> Void)?
    var onClick: (() -> Void)?
    private var startPoint: NSPoint?
    private var didDrag = false
    private var pressedKnob = false
    private var pointerInsideCenter = false
    private var pointerOnRing = false
    private lazy var knobMotion = ThemeButtonMotionDriver(view: self)
    private var tracking: NSTrackingArea?
    private var rotationActive = false
    private var rotationSequenceActive = false
    private var pendingRotation: Double = 0
    private var cancelledRotation = false
    private var scrollSequenceActive = false
    private var cancelledScroll = false
    private var cancelledScrollUntil: TimeInterval = 0
    private let scrollEvents = PassthroughSubject<Double, Never>()
    private let scrollPublisher: (AnyPublisher<Double, Never>) -> AnyPublisher<Double, Never>
    private let now: () -> TimeInterval
    private var scrollDelivery: AnyCancellable?
    private var lastScrollTime: TimeInterval = 0
    private let tooltipAnchor = TooltipAnchorView()
    private let resources: ThemeEditorResources
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(scrollPublisher: ((AnyPublisher<Double, Never>) -> AnyPublisher<Double, Never>)?,
         now: @escaping () -> TimeInterval, resources: ThemeEditorResources) {
        self.resources = resources
        self.scrollPublisher = scrollPublisher ?? {
            $0.throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true).eraseToAnyPublisher()
        }
        self.now = now
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider); setAccessibilityLabel("Theme texture and noise")
        setAccessibilityHelp("Click to cycle textures. Rotate or scroll to adjust noise.")
        addSubview(tooltipAnchor)
        tooltipAnchor.frame = knobRect
        tooltipAnchor.parcTooltip = TooltipConfiguration("Noise", anchor: .bottom)
        setAccessibilityMinValue(0); setAccessibilityMaxValue(100)
        observeScroll()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        tooltipAnchor.frame = knobRect
    }
    private var knobRect: NSRect {
        let side = min(bounds.width, bounds.height) / 2
        return NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }
    private func knobContains(_ point: NSPoint) -> Bool {
        hypot(point.x - knobRect.midX, point.y - knobRect.midY) <= knobRect.width / 2
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { pointerInsideCenter = false; pointerOnRing = false; knobMotion.reset(); marker.motion.reset(); marker.needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        for index in 1..<20 {
            let step = (index + 10) % 20
            let a = (90 + Double(index) * 18) * .pi / 180
            let p = NSPoint(x: center.x + cos(a) * 32, y: center.y + sin(a) * 32)
            let fill = ThemeControlHandle.dotFill(step: step, value: value)
            let dot = NSBezierPath(ovalIn: NSRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
            ThemeEditorColors.separator.setFill(); dot.fill()
            guard fill > 0 else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(fill)
            ThemeEditorColors.foreground.setFill(); dot.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let name = texture.rawValue.prefix(1).uppercased() + texture.rawValue.dropFirst() + "Knob"
        let knob = knobRect, side = knob.width * 1.2 * knobMotion.motion.scale
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: knob).addClip()
        resources.image(name)?.draw(in: NSRect(x: knob.midX - side / 2, y: knob.midY - side / 2, width: side, height: side),
                                               from: .zero, operation: .sourceOver,
                                               fraction: 0.6, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        ThemeEditorColors.separator.setStroke()
        NSBezierPath(ovalIn: knob).stroke()
    }
    private func angleValue(_ point: NSPoint) -> Double {
        var angle = atan2(point.y - bounds.midY, point.x - bounds.midX) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        return angle / (2 * .pi)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointerInsideCenter = knobRect.contains(point)
        pointerOnRing = ringContains(point)
        knobMotion.update(hovered: pointerInsideCenter)
        updateMarkerHover()
        if !didDrag && !rotationActive { (pointerInsideCenter ? NSCursor.pointingHand : NSCursor.openHand).set() }
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        pointerInsideCenter = false; pointerOnRing = false
        knobMotion.update(hovered: false)
        updateMarkerHover()
        if !didDrag && !rotationActive { NSCursor.arrow.set() }
    }
    private func ringContains(_ point: NSPoint?) -> Bool {
        point.map { bounds.contains($0) && !knobRect.contains($0) } ?? false
    }
    private func updateMarkerHover() {
        marker.motion.update(hovered: didDrag || rotationActive || (pointerOnRing && !pressedKnob))
    }

    private func observeScroll() {
        scrollDelivery = scrollPublisher(scrollEvents.eraseToAnyPublisher())
            .sink { [weak self] delta in
                guard let self, self.pointerInsideCenter, !self.cancelledScroll,
                      self.startPoint == nil, !self.rotationSequenceActive,
                      delta.isFinite, delta != 0 else { return }
                self.onBegin?()
                self.onChange?(self.value + (delta > 0 ? 0.125 : -0.125), .scrollWheel)
                self.onEnd?()
            }
    }

    private func cancelScrollInput() {
        if scrollSequenceActive || now() < lastScrollTime + 0.2 {
            cancelledScroll = true
            cancelledScrollUntil = now() + 0.2
        }
        scrollDelivery?.cancel(); observeScroll()
    }
    func cancelGesture() {
        if rotationSequenceActive { cancelledRotation = true }
        cancelScrollInput()
        if didDrag || rotationActive { NSCursor.arrow.set() }
        startPoint = nil; didDrag = false; pressedKnob = false; rotationActive = false; pendingRotation = 0
        knobMotion.update(pressed: false)
        pointerOnRing = ringContains(window.flatMap { $0.isKeyWindow ? convert($0.mouseLocationOutsideOfEventStream, from: nil) : nil })
        updateMarkerHover()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if rotationActive { rotationActive = false; onEnd?() }
        cancelGesture()
        let p = convert(event.locationInWindow, from: nil)
        startPoint = p; didDrag = false; pressedKnob = knobContains(p)
        knobMotion.update(hovered: knobRect.contains(p), pressed: pressedKnob)
        pointerOnRing = ringContains(p)
        updateMarkerHover()
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        knobMotion.update(hovered: knobRect.contains(p), pressed: pressedKnob && knobContains(p))
        guard let startPoint, !pressedKnob else { return }
        if !didDrag {
            guard hypot(p.x - startPoint.x, p.y - startPoint.y) >= 10 else { return }
            onBegin?()
            self.startPoint = startPoint; didDrag = true; NSCursor.closedHand.set()
            updateMarkerHover()
        }
        onChange?(angleValue(p), .drag)
    }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        knobMotion.update(hovered: knobRect.contains(p), pressed: false)
        pointerOnRing = ringContains(p)
        guard startPoint != nil else { updateMarkerHover(); return }
        if didDrag { onEnd?() }
        else if pressedKnob { if knobContains(p) { onClick?() } }
        else if bounds.contains(p) { onBegin?(); onChange?(angleValue(p), .dialClick); onEnd?() }
        startPoint = nil; didDrag = false; pressedKnob = false; NSCursor.arrow.set()
        updateMarkerHover()
    }
    override func rotate(with event: NSEvent) {
        if event.phase.contains(.began) {
            guard knobContains(convert(event.locationInWindow, from: nil)) else { cancelledRotation = true; return }
            cancelScrollInput()
            cancelledRotation = false; pendingRotation = 0; rotationSequenceActive = true
        }
        if cancelledRotation {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                cancelledRotation = false; rotationSequenceActive = false
            }
            return
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            pendingRotation = 0; rotationSequenceActive = false
            if rotationActive { rotationActive = false; onEnd?(); NSCursor.arrow.set(); updateMarkerHover() }
            return
        }
        let delta = Double(event.rotation)
        guard delta.isFinite else { return }
        rotationSequenceActive = true
        pendingRotation += delta
        let admittedRotation = pendingRotation
        if !rotationActive {
            guard abs(admittedRotation) >= 1 else { return }
            if didDrag { didDrag = false; onEnd?() }
            onBegin?()
            startPoint = nil; pressedKnob = false; rotationActive = true
            rotationSequenceActive = true; cancelledRotation = false
            knobMotion.update(pressed: false)
            updateMarkerHover()
            NSCursor.closedHand.set()
        }
        pendingRotation = 0
        onChange?(value + admittedRotation / 720, .rotation)
    }
    override func scrollWheel(with event: NSEvent) {
        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if cancelledScroll {
            if event.phase.contains(.began) || (!phased && event.timestamp >= cancelledScrollUntil) {
                cancelledScroll = false; scrollSequenceActive = false
            } else {
                if !phased { cancelledScrollUntil = max(cancelledScrollUntil, event.timestamp + 0.2) }
                return
            }
        }
        guard startPoint == nil, !rotationActive else { return }
        lastScrollTime = event.timestamp
        if phased { scrollSequenceActive = true }
        if event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled) { scrollSequenceActive = false }
        scrollEvents.send(event.scrollingDeltaY)
    }
    override func keyDown(with event: NSEvent) {
        if [123,124,125,126].contains(event.keyCode) {
            onDiscreteBegin?(); onChange?(value + ([124,126].contains(event.keyCode) ? 0.05 : -0.05), .slider); onEnd?()
        } else if event.keyCode == 49 { onClick?() }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformIncrement() -> Bool { onDiscreteBegin?(); onChange?(value + 0.05, .slider); onEnd?(); return true }
    override func accessibilityPerformDecrement() -> Bool { onDiscreteBegin?(); onChange?(value - 0.05, .slider); onEnd?(); return true }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

struct ThemeAppearanceAnimation {
    let layers: [[String: Any]]
    let frameRate: Double
    let start: Double
    let end: Double
    let size: CGSize
    init?(name: String, resources: Bundle = .main) {
        guard let url = resources.url(forResource: name, withExtension: "json", subdirectory: "ThemeEditor"),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let layers = root["layers"] as? [[String: Any]],
              let fr = root["fr"] as? Double, let end = root["op"] as? Double,
              let width = root["w"] as? Double, let height = root["h"] as? Double,
              width > 0, height > 0, fr > 0, end > 0 else { return nil }
        self.layers = layers; frameRate = fr; self.end = end
        start = root["ip"] as? Double ?? 0; size = CGSize(width: width, height: height)
    }
    private func numbers(_ value: Any?) -> [Double] {
        if let values = value as? [Double] { return values }
        if let value = value as? Double { return [value] }
        return []
    }
    private func value(_ property: Any?, frame: Double, fallback: [Double]) -> [Double] {
        guard let p = property as? [String: Any] else { return fallback }
        guard (p["a"] as? Int) == 1, let keys = p["k"] as? [[String: Any]], !keys.isEmpty else {
            let n = numbers(p["k"]); return n.isEmpty ? fallback : n
        }
        let i = keys.lastIndex { ($0["t"] as? Double ?? 0) <= frame } ?? 0
        let current = keys[i], from = numbers(current["s"])
        guard i + 1 < keys.count else { return from.isEmpty ? fallback : from }
        let next = keys[i + 1], to = numbers(next["s"])
        let t0 = current["t"] as? Double ?? 0, t1 = next["t"] as? Double ?? t0
        guard t1 > t0, from.count == to.count else { return from }
        if current["h"] as? Int == 1 { return from }
        let fraction = min(1, max(0, (frame - t0) / (t1 - t0)))
        let outgoing = current["o"] as? [String: Any], incoming = current["i"] as? [String: Any]
        func component(_ object: [String: Any]?, _ key: String, _ index: Int, _ defaultValue: Double) -> Double {
            let array = numbers(object?[key]); return array.isEmpty ? defaultValue : array[min(index, array.count - 1)]
        }
        func cubic(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1-t) * (1-t) * t * a + 3 * (1-t) * t * t * b + t * t * t
        }
        return from.enumerated().map { index, initial in
            let x1 = component(outgoing, "x", index, 0), x2 = component(incoming, "x", index, 1)
            let y1 = component(outgoing, "y", index, 0), y2 = component(incoming, "y", index, 1)
            var lo = 0.0, hi = 1.0
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if cubic(mid, x1, x2) < fraction { lo = mid } else { hi = mid }
            }
            let progress = cubic((lo + hi) / 2, y1, y2)
            return initial + (to[index] - initial) * progress
        }
    }
    private func transform(_ properties: [String: Any], frame: Double, context: CGContext) {
        let p = value(properties["p"], frame: frame, fallback: [0,0])
        let a = value(properties["a"], frame: frame, fallback: [0,0])
        let s = value(properties["s"], frame: frame, fallback: [100,100])
        let r = value(properties["r"], frame: frame, fallback: [0])
        context.translateBy(x: p[0], y: p[1]); context.rotate(by: r[0] * .pi / 180)
        context.scaleBy(x: s[0] / 100, y: s[1] / 100); context.translateBy(x: -a[0], y: -a[1])
    }
    private func hashTransform(_ properties: [String: Any], frame: Double, into hasher: inout Hasher) {
        for key in ["p", "a", "s", "r"] {
            let fallback: [Double] = key == "s" ? [100, 100] : key == "r" ? [0] : [0, 0]
            for component in value(properties[key], frame: frame, fallback: fallback) {
                hasher.combine(component.bitPattern)
            }
        }
    }
    func presentationFingerprint(seconds: Double, size: CGSize) -> Int {
        let span = end - start
        let frame = start + (seconds * frameRate).truncatingRemainder(dividingBy: span)
        var hasher = Hasher()
        hasher.combine(Int((size.width * 1000).rounded()))
        hasher.combine(Int((size.height * 1000).rounded()))
        for layer in layers.reversed() {
            guard let ks = layer["ks"] as? [String: Any], let groups = layer["shapes"] as? [[String: Any]] else { continue }
            hashTransform(ks, frame: frame, into: &hasher)
            for group in groups {
                guard let items = group["it"] as? [[String: Any]],
                      items.contains(where: { $0["ty"] as? String == "fl" }) else { continue }
                if let tr = items.first(where: { $0["ty"] as? String == "tr" }) {
                    hashTransform(tr, frame: frame, into: &hasher)
                }
                for shape in items where shape["ty"] as? String == "sh" {
                    guard let prop = shape["ks"] as? [String: Any], let path = prop["k"] as? [String: Any],
                          let vertices = path["v"] as? [[Double]], let incoming = path["i"] as? [[Double]],
                          let outgoing = path["o"] as? [[Double]],
                          vertices.count == incoming.count, vertices.count == outgoing.count else {
                        hasher.combine(0); continue
                    }
                    hasher.combine(path["c"] as? Bool == true)
                    hasher.combine(vertices.count)
                    for point in vertices + incoming + outgoing {
                        for component in point.prefix(2) { hasher.combine(component.bitPattern) }
                    }
                }
            }
        }
        return hasher.finalize()
    }
    func draw(in rect: NSRect, seconds: Double, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let frame = start + (seconds * frameRate).truncatingRemainder(dividingBy: end - start)
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / size.width, y: rect.height / size.height)
        for layer in layers.reversed() {
            guard let ks = layer["ks"] as? [String: Any], let groups = layer["shapes"] as? [[String: Any]] else { continue }
            context.saveGState(); transform(ks, frame: frame, context: context)
            for group in groups {
                guard let items = group["it"] as? [[String: Any]],
                      items.contains(where: { $0["ty"] as? String == "fl" }) else { continue }
                context.saveGState()
                if let tr = items.first(where: { $0["ty"] as? String == "tr" }) { transform(tr, frame: frame, context: context) }
                context.setFillColor(color.cgColor)
                for shape in items where shape["ty"] as? String == "sh" {
                    guard let prop = shape["ks"] as? [String: Any], let path = prop["k"] as? [String: Any],
                          let vertices = path["v"] as? [[Double]], let incoming = path["i"] as? [[Double]],
                          let outgoing = path["o"] as? [[Double]], !vertices.isEmpty,
                          incoming.count == vertices.count, outgoing.count == vertices.count else { continue }
                    let bezier = CGMutablePath(); bezier.move(to: CGPoint(x: vertices[0][0], y: vertices[0][1]))
                    let closed = path["c"] as? Bool ?? false
                    for step in 1..<(vertices.count + (closed ? 1 : 0)) {
                        let index = step % vertices.count, previous = step - 1
                        bezier.addCurve(to: CGPoint(x: vertices[index][0], y: vertices[index][1]),
                            control1: CGPoint(x: vertices[previous][0] + outgoing[previous][0], y: vertices[previous][1] + outgoing[previous][1]),
                            control2: CGPoint(x: vertices[index][0] + incoming[index][0], y: vertices[index][1] + incoming[index][1]))
                    }
                    if closed { bezier.closeSubpath() }
                    context.addPath(bezier); context.fillPath()
                }
                context.restoreGState()
            }
            context.restoreGState()
        }
        context.restoreGState()
    }
}

final class ThemeAppearanceButton: NSButton {
    let appearanceChoice: AppAppearance
    var onAction: (() -> Void)?
    var isSelected = false {
        didSet {
            invalidateDisplay()
            updatePlayback()
            setAccessibilityValue(isSelected ? 1 : 0)
        }
    }
    private let animation: ThemeAppearanceAnimation?
    private let allowsPlaybackOverride: (() -> Bool)?
    private let scheduleFrame: (Timer) -> Void
    private var timer: Timer?
    var now: () -> CFTimeInterval = { CACurrentMediaTime() }
    var onDisplayInvalidated: (() -> Void)?
    private var startedAt = 0.0
    private var frozenAt = 0.0
    private var lastDisplayFingerprint: Int?
    private var hovered = false
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    init(appearance: AppAppearance, resources: Bundle = .main, allowsPlayback: (() -> Bool)? = nil,
         scheduleFrame: @escaping (Timer) -> Void = { RunLoop.main.add($0, forMode: .common) }) {
        appearanceChoice = appearance
        allowsPlaybackOverride = allowsPlayback
        self.scheduleFrame = scheduleFrame
        let asset = appearance == .automatic ? "automatic" : appearance == .light ? "sun" : "moon"
        animation = ThemeAppearanceAnimation(name: asset, resources: resources)
        super.init(frame: .zero)
        title = ""; isBordered = false; focusRingType = .exterior
        target = self; action = #selector(invoke)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(appearance == .automatic ? "Automatic appearance" : appearance == .light ? "Light appearance" : "Dark appearance")
        parcTooltip = TooltipConfiguration(appearance == .automatic ? "Automatic Appearance" : appearance == .light ? "Light Appearance" : "Dark Appearance",
                                           anchor: .bottom)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { timer?.invalidate() }
    @objc private func invoke() { onAction?() }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); super.mouseDown(with: event) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); updatePlayback()
        if window == nil { hovered = false; motion.reset() }
    }
    override func viewDidHide() { super.viewDidHide(); updatePlayback() }
    override func viewDidUnhide() { super.viewDidUnhide(); updatePlayback() }
    private var shouldPlay: Bool {
        isSelected && !isHiddenOrHasHiddenAncestor
            && (allowsPlaybackOverride?() ?? (window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
    }
    private func updatePlayback() {
        if shouldPlay && timer == nil {
            startedAt = now() - frozenAt
            let artworkSize = bounds.insetBy(dx: 6, dy: 6).size
            if let animation {
                lastDisplayFingerprint = animation.presentationFingerprint(
                    seconds: frozenAt, size: artworkSize)
            } else {
                lastDisplayFingerprint = nil
            }
            startFrames()
        } else if !shouldPlay, timer != nil {
            frozenAt = now() - startedAt
            stopFrames()
        }
    }
    private func tick(_ timer: Timer) {
        guard self.timer === timer else { return }
        guard shouldPlay else {
            frozenAt = now() - startedAt
            stopFrames()
            return
        }
        let seconds = now() - startedAt
        let artworkSize = bounds.insetBy(dx: 6, dy: 6).size
        if let animation {
            let fingerprint = animation.presentationFingerprint(seconds: seconds, size: artworkSize)
            if fingerprint != lastDisplayFingerprint {
                lastDisplayFingerprint = fingerprint
                invalidateDisplay()
            }
        } else {
            invalidateDisplay()
        }
    }
    private func startFrames() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated { self?.tick(timer) }
        }
        self.timer = timer; scheduleFrame(timer)
    }
    private func stopFrames() { timer?.invalidate(); timer = nil }
    private func invalidateDisplay() {
        needsDisplay = true
        onDisplayInvalidated?()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .cursorUpdate], owner: self)
        addTrackingArea(tracking!)
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    var hoverStyleEnabled = true { didSet { if hoverStyleEnabled != oldValue { updateHover(animated: false) } } }
    override var isEnabled: Bool {
        didSet { if isEnabled != oldValue { updateHover(animated: false); invalidateDisplay() } }
    }
    private lazy var motion = ThemeButtonMotionDriver(view: self, now: { [weak self] in self?.now() ?? CACurrentMediaTime() })
    override func mouseEntered(with event: NSEvent) { hovered = true; updateHover(animated: true) }
    override func mouseExited(with event: NSEvent) { hovered = false; updateHover(animated: true) }
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        hovered = ThemeButtonMotionDriver.pointerInside(self); updateHover(animated: true)
        motion.update(pressed: flag)
    }
    private func updateHover(animated: Bool) {
        motion.update(hovered: hovered && hoverStyleEnabled && isEnabled, animatesHover: animated)
    }
    override func draw(_ dirtyRect: NSRect) {
        ThemeButtonStyle.draw(in: bounds, motion: motion.motion, isEnabled: isEnabled) {
            if isSelected, let context = NSGraphicsContext.current?.cgContext {
                ThemeButtonStyle.fill().setFill(); context.addPath(ThemeButtonStyle.shape(bounds)); context.fillPath()
            }
            let seconds = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : timer == nil ? frozenAt : now() - startedAt
            animation?.draw(in: bounds.insetBy(dx: 6, dy: 6), seconds: seconds, color: .secondaryLabelColor)
        }
    }
}
