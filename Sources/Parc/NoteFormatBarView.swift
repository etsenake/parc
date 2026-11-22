import AppKit

@MainActor
final class NoteFormatBarView: NSView, NoteFloatingPanelContent {
    var preferredSizeDidChange: (() -> Void)?
    var onAction: ((NoteFormatItem, NoteToolbarButton, NoteMenuList.Origin) -> Void)?
    var onExitKeyboard: (() -> Void)?
    var keyInterceptor: ((NSEvent) -> Bool)?
    private(set) var items: [NoteFormatItem] = []
    private(set) var buttons: [NoteFormatItem: NoteToolbarButton] = [:]
    private(set) var state: NoteFormatState?
    private(set) var focusedIndex: Int?
    private var dividers: [NSView] = []
    private let focusRing = CALayer()
    var isKeyboardActive = false {
        didSet {
            guard oldValue != isKeyboardActive else { return }
            if !isKeyboardActive { setFocus(nil) }
        }
    }
    var tooltipAnchor: TooltipConfiguration.Anchor = .top {
        didSet { if oldValue != tooltipAnchor { refreshTooltips() } }
    }
    var openItem: NoteFormatItem? {
        didSet { if oldValue != openItem, let state { applyChecks(state) } }
    }

    static let padding: CGFloat = 4
    static let spacing: CGFloat = 1
    static let dividerSlot: CGFloat = 9

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        focusRing.cornerRadius = NoteTheme.controlRadius + 1.5
        focusRing.cornerCurve = .continuous
        focusRing.borderWidth = 1.5
        focusRing.opacity = 0
        layer?.addSublayer(focusRing)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Text Formatting")
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self, let layer = self.layer else { return }
            NoteAnimation.settle(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isKeyboardActive }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        var width = Self.padding * 2
        var previous: Int?
        for item in items {
            guard let button = buttons[item] else { continue }
            if let previous { width += previous == item.group ? Self.spacing : Self.dividerSlot }
            width += button.intrinsicContentSize.width
            previous = item.group
        }
        return NSSize(width: ceil(width), height: NoteTheme.toolbarHeight)
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    func button(for item: NoteFormatItem) -> NoteToolbarButton? { buttons[item] }

    func update(_ state: NoteFormatState) {
        self.state = state
        if state.items != items { rebuild(state.items) }
        for item in items {
            guard let button = buttons[item] else { continue }
            button.isEnabled = state.isEnabled(item)
            switch item {
            case .turnInto:
                button.content = .text(state.turnIntoLabel)
                button.setAccessibilityLabel("Turn Into, " + state.turnIntoLabel)
            case .color:
                let uniform = state.color.uniform
                button.iconTint = state.color.text.map { NoteTheme.color(.text($0)) }
                button.iconFill = state.color.background.map { NoteTheme.color(.background($0)) }
                button.setAccessibilityLabel("Color, " + (uniform.map { NoteColorChoice($0).title } ?? "Default"))
            default:
                break
            }
        }
        applyChecks(state)
        if let focusedIndex, !(items.indices.contains(focusedIndex) && buttons[items[focusedIndex]]?.isEnabled == true) {
            setFocus(NoteFormatBarFocus.move(from: nil, by: 1, enabled: enabledFlags))
        }
        relayout()
    }

    private func applyChecks(_ state: NoteFormatState) {
        for item in items {
            buttons[item]?.isChecked = item == openItem || (item != .color && item != .turnInto && state.isActive(item))
        }
    }

    private func rebuild(_ wanted: [NoteFormatItem]) {
        for button in buttons.values { button.removeFromSuperview() }
        for divider in dividers { divider.removeFromSuperview() }
        buttons.removeAll()
        dividers.removeAll()
        items = wanted
        var previous: Int?
        for item in wanted {
            if let previous, previous != item.group {
                let divider = NoteFormatBarDivider()
                dividers.append(divider)
                addSubview(divider)
            }
            let button = Self.makeButton(for: item)
            button.onPress = { [weak self, weak button] in
                guard let self, let button else { return }
                self.press(item, button: button, origin: .pointer)
            }
            buttons[item] = button
            addSubview(button)
            previous = item.group
        }
        refreshTooltips()
    }

    static func makeButton(for item: NoteFormatItem) -> NoteToolbarButton {
        let button: NoteToolbarButton
        switch item {
        case .turnInto:
            button = NoteToolbarButton(.text(NoteTurnIntoOption.text.title), label: item.title)
            button.showsDisclosure = true
            button.setAccessibilityRole(.menuButton)
        case .link:
            button = NoteToolbarButton(.iconAndText(.symbol("arrow.up.right"), "Link"), label: item.title)
        case .bold:
            button = NoteToolbarButton(icon: .glyph("B"), label: item.title)
        case .italic:
            button = NoteToolbarButton(icon: .glyph("i"), label: item.title)
            button.decoration = [.italic]
        case .underline:
            button = NoteToolbarButton(icon: .glyph("U"), label: item.title)
            button.decoration = [.underline, .regularWeight]
        case .strikethrough:
            button = NoteToolbarButton(icon: .glyph("S"), label: item.title)
            button.decoration = [.strikethrough, .regularWeight]
        case .code:
            button = NoteToolbarButton(icon: .symbol("chevron.left.forwardslash.chevron.right"), label: item.title)
            button.iconPointSize = 12.5
        case .equation:
            button = NoteToolbarButton(icon: .symbol("x.squareroot"), label: item.title)
            button.iconPointSize = 13
        case .color:
            button = NoteToolbarButton(icon: .glyph("A"), label: item.title)
            button.showsDisclosure = true
            button.setAccessibilityRole(.menuButton)
        case .mention:
            button = NoteToolbarButton(icon: .glyph("@"), label: item.title)
            button.decoration = [.regularWeight]
        }
        if item.markKey != nil || item == .mention || item == .color { button.iconPointSize = 15 }
        button.setFrameSize(button.intrinsicContentSize)
        return button
    }

    private func relayout() {
        let before = frame.size
        var x = Self.padding
        var previous: Int?
        var dividerIndex = 0
        let height = NoteTheme.toolbarHeight
        NoteAnimation.withoutAnimation {
            for item in items {
                guard let button = buttons[item] else { continue }
                if let previous {
                    if previous == item.group {
                        x += Self.spacing
                    } else {
                        let divider = dividers[dividerIndex]
                        dividerIndex += 1
                        divider.frame = NSRect(x: x + (Self.dividerSlot - 1) / 2, y: (height - 18) / 2, width: 1, height: 18)
                        x += Self.dividerSlot
                    }
                }
                let size = button.intrinsicContentSize
                button.frame = NSRect(x: x, y: ((height - size.height) / 2).rounded(), width: size.width, height: size.height)
                x += size.width
                previous = item.group
            }
        }
        invalidateIntrinsicContentSize()
        if intrinsicContentSize != before {
            setFrameSize(intrinsicContentSize)
            preferredSizeDidChange?()
        }
        placeFocusRing(animated: false)
    }

    static func tooltip(for item: NoteFormatItem) -> String {
        switch item {
        case .turnInto: return "Turn into"
        case .link: return "Add a link"
        case .code: return "Inline code"
        case .equation: return "Inline equation"
        case .color: return "Text and background color"
        case .mention: return "Mention a note or date"
        default: return item.title
        }
    }

    private func refreshTooltips() {
        for (item, button) in buttons {
            button.setToolTip(Self.tooltip(for: item), shortcut: item.chord?.display, anchor: tooltipAnchor)
        }
    }

    private func press(_ item: NoteFormatItem, button: NoteToolbarButton, origin: NoteMenuList.Origin) {
        guard button.isEnabled else { return }
        if origin == .keyboard, let index = items.firstIndex(of: item) { setFocus(index) }
        onAction?(item, button, origin)
    }

    var enabledFlags: [Bool] { items.map { buttons[$0]?.isEnabled ?? false } }

    var focusedItem: NoteFormatItem? { focusedIndex.flatMap { items.indices.contains($0) ? items[$0] : nil } }

    func focusFirst() {
        isKeyboardActive = true
        setFocus(focusedIndex ?? NoteFormatBarFocus.move(from: nil, by: 1, enabled: enabledFlags))
    }

    func focus(_ item: NoteFormatItem) {
        isKeyboardActive = true
        setFocus(items.firstIndex(of: item))
    }

    func moveFocus(by delta: Int) {
        setFocus(NoteFormatBarFocus.move(from: focusedIndex, by: delta, enabled: enabledFlags))
    }

    private func setFocus(_ index: Int?) {
        let previous = focusedIndex
        focusedIndex = index
        placeFocusRing(animated: previous != nil)
        if let item = focusedItem, let button = buttons[item] {
            NSAccessibility.post(element: button, notification: .focusedUIElementChanged)
        }
    }

    private func placeFocusRing(animated: Bool) {
        guard let item = focusedItem, let button = buttons[item] else {
            NoteAnimation.fade(focusRing, to: 0, duration: animated ? NoteAnimation.hoverDuration : 0)
            return
        }
        NoteAnimation.withoutAnimation { focusRing.borderColor = NoteTheme.resolved(NoteTheme.accent.withAlphaComponent(0.75), in: self) }
        let target = button.frame.insetBy(dx: -1.5, dy: -1.5)
        if animated, focusRing.opacity > 0 {
            NoteAnimation.slideLayer(focusRing, to: target, spring: .glide)
        } else {
            NoteAnimation.withoutAnimation { focusRing.frame = target }
            NoteAnimation.fade(focusRing, to: 1, duration: NoteAnimation.hoverDuration)
        }
    }

    func activateFocused() -> Bool {
        guard let item = focusedItem, let button = buttons[item], button.isEnabled else { return false }
        press(item, button: button, origin: .keyboard)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if keyInterceptor?(event) == true { return }
        if !handleKeyboard(event) { super.keyDown(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, openItem == nil { isKeyboardActive = false }
        return resigned
    }

    func handleKeyboard(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 123: moveFocus(by: -1); return true
        case 124: moveFocus(by: 1); return true
        case 48: moveFocus(by: event.modifierFlags.contains(.shift) ? -1 : 1); return true
        case 115: setFocus(NoteFormatBarFocus.move(from: nil, by: 1, enabled: enabledFlags)); return true
        case 119: setFocus(NoteFormatBarFocus.move(from: nil, by: -1, enabled: enabledFlags)); return true
        case 36, 76, 49, 125: return activateFocused()
        case 53:
            onExitKeyboard?()
            return true
        default:
            return false
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        placeFocusRing(animated: false)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

@MainActor
private final class NoteFormatBarDivider: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
