import AppKit

/// Only actual results for the exact displayed document/query become visible.
/// Unknown is separate from a genuine zero-match response.
enum PageFindResultPresentation: Equatable {
    case pending, notFound, matches(ordinal: Int, total: Int)
    static func resolve(query: String, revision: UInt, resultQuery: String?, resultRevision: UInt?,
                        matches: Int?, ordinal: Int?) -> Self {
        guard !query.isEmpty, resultQuery == query.replacingOccurrences(of: "\r", with: ""),
              resultRevision == revision, let matches, let ordinal,
              matches >= 0, ordinal >= 0 else { return .pending }
        if matches == 0 { return .notFound }
        guard ordinal <= matches else { return .pending }
        return .matches(ordinal: ordinal, total: matches)
    }
    var label: String {
        switch self {
        case .pending: return ""
        case .notFound: return "Not Found"
        case let .matches(ordinal, total): return "\(ordinal)/\(total)"
        }
    }
    var canAdvance: Bool { if case .matches = self { return true }; return false }
}

/// An in-page overlay, anchored to the original native page (also in split or
/// Peek). It never reserves renderer height or owns another page's Find state.
@MainActor final class PageFindView: NSView {
    let field = NSTextField()
    let previous = PageFindButton(), next = PageFindButton(), close = PageFindButton()
    let resultLabel = PageFindResultLabel(labelWithString: "")
    private let search = NSImageView()
    private let separator = NSView()
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var result: PageFindResultPresentation = .pending
    override var isFlipped: Bool { true }

    static func frame(in page: NSRect) -> NSRect {
        let width = min(300, max(0, page.width - 20))
        return NSRect(x: page.maxX - 10 - width, y: page.minY + 10, width: width, height: min(32, max(0, page.height - 20)))
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 5
        setAccessibilityElement(false); setAccessibilityLabel("Find in page")
        field.isBezeled = false; field.isBordered = false; field.drawsBackground = false
        field.font = .systemFont(ofSize: 13); field.focusRingType = .none
        field.usesSingleLineMode = true; field.cell?.isScrollable = true
        field.placeholderString = "Find in page..."
        field.setAccessibilityLabel("Find in page")
        search.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        search.setAccessibilityElement(false)
        let features: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: 37, .selectorIdentifier: 1], [.typeIdentifier: 38, .selectorIdentifier: 1]
        ]
        let descriptor = NSFont.systemFont(ofSize: 12).fontDescriptor.addingAttributes([.featureSettings: features])
        resultLabel.font = NSFont(descriptor: descriptor, size: 12)
        resultLabel.setAccessibilityLabel("Find results")
        resultLabel.lineBreakMode = .byClipping
        resultLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        //
        //
        //
        for (button, title, tooltip, commandID, symbol, action) in [
            (previous, "Previous match", "Previous", "findPrevious:", "chevron.up", #selector(previousPressed)),
            (next, "Next match", "Next", "findNext:", "chevron.down", #selector(nextPressed)),
            (close, "Close Find", "Close", nil, "xmark", #selector(closePressed))
        ] as [(NSButton, String, String, String?, String, Selector)] {
            button.title = ""; button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.imageScaling = .scaleProportionallyDown
            button.image = button.image?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
            button.isBordered = false
            button.target = self; button.action = action
            button.setAccessibilityLabel(title); LiveShortcutToolTip.set(button, tooltip, commandID: commandID)
        }
        separator.wantsLayer = true; separator.setAccessibilityElement(false)
        for view in [search, field, resultLabel, previous, next, separator, close] { addSubview(view) }
        // AppKit owns Tab/Shift-Tab traversal and Full Keyboard Access.
        // There is no parallel key monitor or invented closed focus loop.
        update(result: .pending, available: true)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let background = dark ? NSColor(srgbRed: 21/255, green: 28/255, blue: 48/255, alpha: 1)
            : NSColor(srgbRed: 250/255, green: 251/255, blue: 1, alpha: 1)
        let foreground = dark ? NSColor(displayP3Red: 1, green: 1, blue: 1, alpha: 0.8)
            : NSColor(displayP3Red: 14/255, green: 15/255, blue: 16/255, alpha: 0.9)
        layer?.backgroundColor = background.cgColor
        let shadow = NSShadow(); shadow.shadowBlurRadius = 5; shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowColor = NSColor(displayP3Red: 0.082, green: 0.110, blue: 0.196, alpha: dark ? 0.8 : 0.3)
        self.shadow = shadow
        field.textColor = foreground; search.contentTintColor = foreground
        for button in [previous, next, close] { button.contentTintColor = foreground }
        resultLabel.textColor = result == .notFound
            ? NSColor(displayP3Red: 0.788, green: 0.2, blue: 0.2, alpha: 1) : foreground
        separator.layer?.backgroundColor = NSColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.1).cgColor
    }
    func update(result: PageFindResultPresentation, available: Bool) {
        let old = self.result; self.result = result
        let focused = window?.firstResponder
        let hidesFocusedButton = !result.canAdvance && (focused === previous || focused === next)
        resultLabel.stringValue = result.label
        resultLabel.setAccessibilityValue(result.label)
        resultLabel.isHidden = result == .pending
        resultLabel.setAccessibilityHidden(result == .pending)
        previous.isHidden = !result.canAdvance; next.isHidden = !result.canAdvance
        previous.setAccessibilityHidden(!result.canAdvance); next.setAccessibilityHidden(!result.canAdvance)
        previous.isEnabled = available && result.canAdvance; next.isEnabled = previous.isEnabled
        close.isEnabled = available
        separator.isHidden = result == .pending
        updateColors(); needsLayout = true
        if hidesFocusedButton, available, window?.isKeyWindow == true {
            window?.makeFirstResponder(field)
        }
        if old != result, window != nil, !isHiddenOrHasHiddenAncestor {
            NSAccessibility.post(element: resultLabel, notification: .valueChanged)
        }
    }
    override func layout() {
        super.layout()
        let center = bounds.midY, button: CGFloat = 26
        close.frame = NSRect(x: max(0, bounds.width - 3 - button), y: center - button/2, width: button, height: button)
        var trailing = close.frame.minX - 3
        if !separator.isHidden {
            separator.frame = NSRect(x: trailing - 0.5, y: 7, width: 1, height: max(0, bounds.height - 14))
            trailing -= 4
        }
        if result.canAdvance {
            next.frame = NSRect(x: trailing - button, y: center - button/2, width: button, height: button)
            previous.frame = next.frame.offsetBy(dx: -button, dy: 0)
            trailing = previous.frame.minX - 3
        }
        if !resultLabel.isHidden {
            let width = min(100, ceil(resultLabel.intrinsicContentSize.width))
            resultLabel.frame = NSRect(x: max(27, trailing - width), y: center - 8, width: width, height: 17)
            trailing = resultLabel.frame.minX - 7
        }
        search.frame = NSRect(x: 8, y: center - 7.5, width: 15, height: 15)
        field.frame = NSRect(x: 27, y: center - 9, width: max(0, trailing - 27), height: 20)
    }
    override func cancelOperation(_ sender: Any?) {
        if let input = window?.firstResponder as? NSTextInputClient, input.hasMarkedText() { return }
        onClose?()
    }
    @objc private func previousPressed() { guard previous.isEnabled else { return }; onPrevious?() }
    @objc private func nextPressed() { guard next.isEnabled else { return }; onNext?() }
    @objc private func closePressed() { guard close.isEnabled else { return }; onClose?() }
}

/// Find's original control is a native momentary-change button. Its hover
/// surface is decoration; AppKit still owns pressing, key traversal and AX.
@MainActor final class PageFindButton: PointingHandButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var resignationObserver: NSObjectProtocol?
    private(set) var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setButtonType(.momentaryChange)
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let resignationObserver { NotificationCenter.default.removeObserver(resignationObserver) }
    }
    override var wantsUpdateLayer: Bool { true }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            //
            layer?.backgroundColor = (isHovered && isEnabled
                ? NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0,
                          blue: dark ? 1 : 0, alpha: dark ? 0.077 : 0.071)
                : NSColor.clear).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        hoverTrackingArea = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === hoverTrackingArea else { super.mouseEntered(with: event); return }
        refreshHover()
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event); refreshHover()
    }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === hoverTrackingArea else { super.mouseExited(with: event); return }
        setHovered(false)
    }
    private func refreshHover() {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor,
              let content = window.contentView else { setHovered(false); return }
        let location = content.superview?.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            ?? window.mouseLocationOutsideOfEventStream
        let hit = content.hitTest(location)
        setHovered(hit === self || hit?.isDescendant(of: self) == true)
    }
    private func setHovered(_ value: Bool) {
        guard isHovered != value else { return }
        isHovered = value; needsDisplay = true
    }
    override func viewDidHide() {
        super.viewDidHide(); setHovered(false)
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview); setHovered(false)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow); setHovered(false)
        if let resignationObserver { NotificationCenter.default.removeObserver(resignationObserver) }
        resignationObserver = nil
        if let newWindow {
            resignationObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main
            ) { [weak self, weak newWindow] _ in
                MainActor.assumeIsolated {
                    guard let self, let newWindow, self.window === newWindow else { return }
                    self.setHovered(false)
                }
            }
        }
    }
}

/// The count is one readable AX label and cannot intercept native input.
@MainActor final class PageFindResultLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
