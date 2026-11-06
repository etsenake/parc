import AppKit

/// The menu owns the original provider query and native UTF-16 edit range.
/// It never promotes a selected suggestion's displayed text into a request.
struct CommandBarScopeEditing {
    let query: String
    let displayedText: String
    let selection: NSRange
    init(query: String, displayedText: String, selection: NSRange?) {
        self.query = query; self.displayedText = displayedText
        let length = (displayedText as NSString).length
        if let selection, selection.location != NSNotFound, selection.location <= length,
           selection.length <= length - selection.location { self.selection = selection }
        else { self.selection = NSRange(location: length, length: 0) }
    }
    var selectionForQuery: NSRange {
        displayedText == query ? selection : NSRange(location: (query as NSString).length, length: 0)
    }
    func removingScope(prefix: String?) -> (text: String, selection: NSRange) {
        //
        // query without an added separator, placing the caret at that boundary.
        guard let prefix else {
            return (query, NSRange(location: 0, length: (query as NSString).length))
        }
        let text = prefix + query
        return (text, NSRange(location: (prefix as NSString).length, length: 0))
    }
}

final class CommandBarScopePill: NSButton {
    var onOpen: (() -> Void)?
    ///
    var focusColor: NSColor = CommandBarPalette.colourless.scopePill {
        didSet { if focusColor != oldValue { refreshGlow(); refreshLayer() } }
    }
    init() {
        super.init(frame: .zero)
        title = ""; isBordered = false
        target = self; action = #selector(openMenu)
        wantsLayer = true
        refreshGlow()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Search scope")
        setAccessibilityHelp("Open the site search menu to change, remove or manage this search scope.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    ///
    static let titleInset: CGFloat = 10
    private static let titleMeasure = NSTextField(labelWithString: "")
    ///
    /// a label, since NSButton and a framed NSTextField add their own padding.
    static func width(title: String, font: NSFont?) -> CGFloat {
        titleMeasure.font = font; titleMeasure.stringValue = title
        return titleMeasure.intrinsicContentSize.width + 2 * titleInset
    }
    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width(title: title, font: font), height: super.intrinsicContentSize.height)
    }
    override func layout() { super.layout(); refreshLayer() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); refreshGlow(); refreshLayer()
    }
    /// CommandBarInputScopedSearchPillView draws a half-height continuous capsule
    ///
    private func refreshLayer() {
        guard let layer else { return }
        let radius = (bounds.height / 2).rounded(.towardZero)
        layer.cornerRadius = radius; layer.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance { layer.backgroundColor = focusColor.cgColor }
        layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    ///
    private func refreshGlow() {
        let glow = NSShadow()
        glow.shadowBlurRadius = 8; glow.shadowOffset = NSSize(width: 0, height: -1)
        glow.shadowColor = focusColor.withAlphaComponent(0.3)
        shadow = glow
    }
    @objc private func openMenu() { if isEnabled { onOpen?() } }
    override func rightMouseDown(with event: NSEvent) { openMenu() }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isHidden else { return false }
        openMenu(); return true
    }
}

///
/// CommandBarTextSecondaryColor, then each trigger key on a keycap, 8 points
///
///
final class CommandBarScopeHint: NSButton {
    static let textColor = NSColor(name: nil) { $0.isDark ? .white.withAlphaComponent(0.33) : .black.withAlphaComponent(0.33) }
    static let keyColor = NSColor(name: nil) { $0.isDark ? .white.withAlphaComponent(0.66) : .black.withAlphaComponent(0.5) }
    static let keyFill = NSColor(name: nil) { $0.isDark ? .white.withAlphaComponent(0.05) : .black.withAlphaComponent(0.05) }
    static let spacing: CGFloat = 8, keyPadding: CGFloat = 4, keyRadius: CGFloat = 4
    ///
    static let font = CommandBarTypography.label

    /// Hint text and "or" are drawn here; each key is a keycap subview.
    private var hint = ""
    private(set) var textFrames: [(text: String, frame: NSRect)] = []
    private var keycaps: [CommandBarKeycap] = []
    init() {
        super.init(frame: .zero)
        title = ""; isBordered = false
        if #available(macOS 14, *) { clipsToBounds = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(site: String, spaceTriggerEnabled: Bool) {
        hint = "Search \(site)"
        let keys = spaceTriggerEnabled ? ["Space", "Tab"] : ["Tab"]
        if keycaps.map(\.key) != keys {
            keycaps.forEach { $0.removeFromSuperview() }
            keycaps = keys.map { CommandBarKeycap(key: $0) }
            keycaps.forEach(addSubview)
        }
        invalidateIntrinsicContentSize(); needsLayout = true; needsDisplay = true
    }
    static var textHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }
    static func width(_ text: String) -> CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }
    /// Hint, then Space, "or" and Tab when Space also enters the scope.
    private var parts: [Any] {
        keycaps.count == 2 ? [hint, keycaps[0], "or", keycaps[1]] : [hint] + keycaps
    }
    private func partWidth(_ part: Any) -> CGFloat {
        (part as? CommandBarKeycap)?.intrinsicContentSize.width ?? Self.width(part as? String ?? "")
    }
    override var intrinsicContentSize: NSSize {
        let parts = parts
        return NSSize(width: parts.map(partWidth).reduce(0, +) + Self.spacing * CGFloat(max(0, parts.count - 1)),
                      height: Self.textHeight + 2 * Self.keyPadding)
    }
    /// Keys keep their size at the trailing edge; a narrow frame tail-truncates
    /// the hint text, then drops it.
    override func layout() {
        super.layout()
        let parts = parts, natural = intrinsicContentSize.width, hintWidth = partWidth(hint)
        let fitted = max(0, min(hintWidth, bounds.width - (natural - hintWidth)))
        let shown = fitted > 0 ? parts : Array(parts.dropFirst())
        var x = bounds.maxX - (fitted > 0 ? natural - hintWidth + fitted : natural - hintWidth - Self.spacing)
        let y = ((bounds.height - Self.textHeight) / 2).rounded()
        var drawn: [(text: String, frame: NSRect)] = []
        for (index, part) in shown.enumerated() {
            let width = fitted > 0 && index == 0 ? fitted : partWidth(part)
            if let keycap = part as? CommandBarKeycap {
                let size = keycap.intrinsicContentSize
                keycap.frame = NSRect(x: x, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
            } else if let text = part as? String {
                drawn.append((text, NSRect(x: x, y: y, width: width, height: Self.textHeight)))
            }
            x += width + Self.spacing
        }
        textFrames = drawn
    }
    override func draw(_ dirtyRect: NSRect) {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        for (text, frame) in textFrames {
            (text as NSString).draw(with: frame, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                    attributes: [.font: Self.font, .foregroundColor: Self.textColor, .paragraphStyle: style])
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden || !frame.contains(point) ? nil : self
    }
}

///
final class CommandBarKeycap: NSView {
    let key: String
    init(key: String) {
        self.key = key
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = CommandBarScopeHint.keyRadius; layer?.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize {
        NSSize(width: CommandBarScopeHint.width(key) + 2 * CommandBarScopeHint.keyPadding,
               height: CommandBarScopeHint.textHeight + 2 * CommandBarScopeHint.keyPadding)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        layer?.backgroundColor = CommandBarScopeHint.keyFill.cgColor
        (key as NSString).draw(at: NSPoint(x: CommandBarScopeHint.keyPadding, y: CommandBarScopeHint.keyPadding),
                               withAttributes: [.font: CommandBarScopeHint.font, .foregroundColor: CommandBarScopeHint.keyColor])
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// Native Tab is scope entry/exit only at the actual empty-query boundary.
/// Nonempty scoped Tab remains editing; no command is executed by completion.
enum CommandBarScopeKeyboard {
    enum Scope { case ordinary, actions, website, unavailable }
    enum TabAction { case enterActions, leaveScope, complete }
    static func matchesPasswords(query: String) -> Bool {
        query.count >= 3 && ["manage passwords", "password manager", "saved passwords"]
            .contains { $0.hasPrefix(query.lowercased()) }
    }
    static func tab(query: String, scope: Scope) -> TabAction {
        guard query.isEmpty else { return .complete }
        switch scope {
        case .ordinary: return .enterActions
        case .actions, .website: return .leaveScope
        case .unavailable: return .complete
        }
    }
}

/// Actions has no site-provider menu. It is a scope label, not a disabled
/// website button or a control that pretends to mutate a native template.
final class CommandBarActionsPill: NSTextField {
    init() {
        super.init(frame: .zero)
        stringValue = "Actions"
        isEditable = false; isSelectable = false; isBordered = false
        drawsBackground = false; alignment = .center
        font = CommandBarTypography.label; textColor = .white
        cell?.lineBreakMode = .byTruncatingTail
        // CommandBar fills it with the theme's focus (CommandBarPalette.scopePill).
        wantsLayer = true; layer?.cornerRadius = 12
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
        showActions()
    }
    func showActions() {
        stringValue = "Actions"
        setAccessibilityLabel("Actions search scope")
        setAccessibilityValue("Actions")
        setAccessibilityHelp("Search commands. Escape leaves Actions; Tab or Backspace leaves when the query is empty.")
    }
    func showExtension(name: String) {
        stringValue = name
        setAccessibilityLabel("Extension search scope")
        setAccessibilityValue(name)
        setAccessibilityHelp("Send a query to this extension. Escape leaves the scope; Tab or Backspace leaves when the query is empty.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
