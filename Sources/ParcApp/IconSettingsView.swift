import AppKit
import Combine

@MainActor
final class IconSettingsView: NSView {
    override var isFlipped: Bool { true }
    private let icons: AppIconController
    private let group = IconListGroup()
    private let list = NSScrollView()
    private let choices = IconChoiceStack()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let retry = PointingHandButton(title: "Try Again", target: nil, action: nil)
    private var rows: [IconChoiceRow] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var displayedSelection: String?

    init(icons: AppIconController) {
        self.icons = icons
        super.init(frame: NSRect(x: 0, y: 0, width: 596, height: 562))
        autoresizingMask = [.width]
        addSubview(group); addSubview(status); addSubview(retry)
        list.drawsBackground = false; list.hasVerticalScroller = true; list.autohidesScrollers = true
        list.documentView = choices; group.addSubview(list)
        list.wantsLayer = true; list.layer?.cornerRadius = 12; list.layer?.cornerCurve = .continuous
        list.layer?.masksToBounds = true
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        retry.bezelStyle = .rounded; retry.target = self; retry.action = #selector(retryApplication)
        for variant in icons.variants {
            let row = IconChoiceRow(variant: variant)
            row.onChoose = { [weak self] in self?.select(variant.id) }
            row.onMove = { [weak self, weak row] direction in
                guard let row else { return }
                self?.move(from: row, direction: direction)
            }
            choices.addSubview(row); rows.append(row)
        }
        choices.setAccessibilityRole(.radioGroup)
        choices.setAccessibilityLabel("App icon")
        icons.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func refresh() {
        if displayedSelection != icons.selectedID {
            rows.forEach { $0.cancelActivation() }
            displayedSelection = icons.selectedID
        }
        for row in rows { row.setSelected(row.iconID == icons.selectedID) }
        status.stringValue = icons.availabilityError ?? icons.message ?? ""
        status.isHidden = status.stringValue.isEmpty
        retry.isHidden = !icons.canRetry
        needsLayout = true
    }
    private func select(_ id: String) {
        icons.select(id)
        refresh()
    }
    private func move(from row: IconChoiceRow, direction: Int) {
        guard let index = rows.firstIndex(where: { $0 === row }) else { return }
        let next = index + direction
        guard rows.indices.contains(next) else { return }
        let destination = rows[next]
        guard window?.makeFirstResponder(destination) == true else { return }
        destination.scrollToVisible(destination.bounds)
        select(destination.iconID)
    }
    override func layout() {
        super.layout()
        let noticeHeight: CGFloat = status.isHidden ? 0 : (retry.isHidden ? 62 : 92)
        status.frame = NSRect(x: 32, y: 20, width: max(0, bounds.width - 64), height: 52)
        retry.frame = NSRect(x: 28, y: 72, width: 105, height: 28)
        let rowHeight: CGFloat = 81
        let content = CGFloat(rows.count) * rowHeight + 24
        let height = max(rowHeight + 2, min(515, content + 2, 562 - 40 - noticeHeight))
        group.frame = NSRect(x: 20, y: 20 + noticeHeight, width: max(0, bounds.width - 40), height: height)
        list.frame = group.bounds
        choices.frame = NSRect(x: 0, y: 0, width: list.contentSize.width, height: content)
        list.tile()
        choices.frame = NSRect(x: 0, y: 0, width: list.contentSize.width, height: content)
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: 12 + CGFloat(index) * rowHeight, width: choices.bounds.width, height: rowHeight)
            row.showsSeparator = index < rows.count - 1
        }
        let requiredHeight = max(562, group.frame.maxY + 20)
        if frame.height != requiredHeight { setFrameSize(NSSize(width: frame.width, height: requiredHeight)) }
    }
    @objc private func retryApplication() { icons.applyCurrent() }
}

@MainActor
private final class IconChoiceStack: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class IconListGroup: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class IconChoiceRow: PointingHandButton {
    override var isFlipped: Bool { true }
    let iconID: String
    private let preview: NSImageView
    private let name: NSTextField
    private let current = NSTextField(labelWithString: "CURRENT ICON")
    private var activation: Activation?
    private var windowIsClosed = false
    private enum Activation { case mouse, keyboard(UInt16) }
    private var selected = false
    var onChoose: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var showsSeparator = true { didSet { needsDisplay = true } }
    init(variant: AppIconController.Variant) {
        iconID = variant.id
        preview = NSImageView(image: variant.image)
        name = NSTextField(labelWithString: variant.title)
        super.init(frame: .zero)
        cell = IconRadioCell(textCell: "")
        setButtonType(.momentaryChange)
        isBordered = false
        focusRingType = .none
        target = self; action = #selector(selectIcon)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(variant.title)
        setAccessibilityHelp("Use this icon for Parc in the Dock and Finder.")
        preview.imageScaling = .scaleProportionallyUpOrDown
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        current.font = .systemFont(ofSize: 10, weight: .bold)
        current.textColor = .controlAccentColor
        [preview, name, current].forEach { $0.setAccessibilityElement(false); addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { NotificationCenter.default.removeObserver(self) }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        state = selected ? .on : .off
        current.isHidden = !selected
        setAccessibilityValue(selected ? 1 : 0)
        needsLayout = true
        needsDisplay = true
    }
    override func layout() {
        super.layout()
        preview.frame = NSRect(x: 58, y: 7, width: 64, height: 64)
        name.frame = NSRect(x: 130, y: 29, width: max(0, bounds.width - 256), height: 22)
        current.frame = NSRect(x: max(130, bounds.width - 116), y: 32, width: 100, height: 16)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsSeparator else { return }
        NSColor.separatorColor.setFill()
        NSRect(x: 40, y: bounds.height - 1, width: max(0, bounds.width - 80), height: 0.5).fill()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point) == nil ? nil : self
    }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { selected && super.canBecomeKeyView }
    var applicationIsActive: () -> Bool = { NSApp.isActive }
    var showsIconFocusRing: Bool {
        window?.isKeyWindow == true && applicationIsActive() && window?.firstResponder === self
    }
    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        cancelActivation()
        needsDisplay = true
        return super.resignFirstResponder()
    }
    private var canActivate: Bool { isEnabled && window != nil && !windowIsClosed && !isHiddenOrHasHiddenAncestor }
    private func isInside(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return event.windowNumber == window?.windowNumber && bounds.contains(point) && visibleRect.contains(point)
    }
    override func mouseDown(with event: NSEvent) {
        cancelActivation()
        guard canActivate, isInside(event) else { return }
        window?.makeFirstResponder(self)
        activation = .mouse
        highlight(true)
    }
    override func mouseDragged(with event: NSEvent) {
        guard case .mouse = activation else { return }
        highlight(canActivate && isInside(event))
    }
    override func mouseUp(with event: NSEvent) {
        guard case .mouse = activation else { return }
        let commit = canActivate && isInside(event)
        cancelActivation()
        if commit { performClick(nil) }
    }
    override func keyDown(with event: NSEvent) {
        guard canActivate else { return }
        if event.keyCode == 53 { cancelActivation(); return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 49, 36, 76:
            guard !event.isARepeat, activation == nil else { return }
            activation = .keyboard(event.keyCode)
            highlight(true)
        case 123, 126: cancelActivation(); onMove?(-1)
        case 124, 125: cancelActivation(); onMove?(1)
        default: super.keyDown(with: event)
        }
    }
    override func keyUp(with event: NSEvent) {
        guard case .keyboard(let key) = activation, key == event.keyCode else { return }
        let commit = canActivate && window?.firstResponder === self &&
            event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        cancelActivation()
        if commit { performClick(nil) }
    }
    override func cancelOperation(_ sender: Any?) { cancelActivation() }
    override func performClick(_ sender: Any?) {
        guard canActivate else { return }
        cancelActivation()
        _ = sendAction(action, to: target)
    }
    override func accessibilityPerformPress() -> Bool {
        guard canActivate else { return false }
        performClick(nil)
        return true
    }
    override func accessibilityChildren() -> [Any]? { [] }
    override var isEnabled: Bool {
        didSet { if !isEnabled { cancelActivation() } }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelActivation()
        windowIsClosed = false
        let center = NotificationCenter.default
        center.removeObserver(self)
        guard let window else { return }
        center.addObserver(self, selector: #selector(interruptActivation), name: NSWindow.didResignKeyNotification, object: window)
        center.addObserver(self, selector: #selector(windowClosed), name: NSWindow.willCloseNotification, object: window)
        center.addObserver(self, selector: #selector(windowBecameKey), name: NSWindow.didBecomeKeyNotification, object: window)
        center.addObserver(self, selector: #selector(interruptActivation), name: NSApplication.didResignActiveNotification, object: NSApp)
        center.addObserver(self, selector: #selector(interruptActivation), name: NSApplication.didBecomeActiveNotification, object: NSApp)
    }
    override func viewDidHide() { super.viewDidHide(); cancelActivation() }
    func cancelActivation() { activation = nil; highlight(false); needsDisplay = true }
    @objc private func interruptActivation() { cancelActivation() }
    @objc private func windowClosed() { windowIsClosed = true; cancelActivation() }
    @objc private func windowBecameKey() { windowIsClosed = false; needsDisplay = true }
    @objc private func selectIcon() { onChoose?() }
}

@MainActor
private final class IconRadioCell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let rect = NSRect(x: 15, y: 28, width: 22, height: 22)
        let outline = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
        if (controlView as? IconChoiceRow)?.showsIconFocusRing == true {
            NSGraphicsContext.saveGraphicsState()
            NSFocusRingPlacement.only.set(); outline.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        (isHighlighted ? NSColor(white: 0.9, alpha: 1) : NSColor.white).setFill(); outline.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke(); outline.lineWidth = 1.5; outline.stroke()
        if state == .on {
            NSColor.controlAccentColor.setStroke(); outline.lineWidth = 2; outline.stroke()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
        }
    }
}
