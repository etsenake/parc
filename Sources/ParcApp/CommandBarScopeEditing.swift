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

///
///
/// keyword scopes the same token. Only a site's pill opens the site search menu.
final class CommandBarScopePill: NSButton {
    var onOpen: (() -> Void)?
    ///
    var focusColor: NSColor = CommandBarPalette.colourless.scopePill {
        didSet { if focusColor != oldValue { refreshGlow(); refreshLayer() } }
    }
    ///
    ///
    private static let titleInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
    ///
    let titleLabel = NSTextField(labelWithString: "")
    private var opensMenu = false
    init() {
        super.init(frame: .zero)
        title = ""; isBordered = false
        target = self; action = #selector(openMenu)
        wantsLayer = true
        titleLabel.font = CommandBarTypography.label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)
        refreshGlow()
        setAccessibilityElement(true)
        showActions()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func showSite(name: String, unavailable: Bool) {
        show(name, color: unavailable ? .disabledControlTextColor : .white, opensMenu: true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Search scope")
        setAccessibilityValue(unavailable ? "\(name), unavailable" : name)
        setAccessibilityHelp("Open the site search menu to change, remove or manage this search scope.")
    }
    /// Actions has no site-provider menu, so it reads as a scope label.
    func showActions() {
        show("Actions", color: .white, opensMenu: false)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Actions search scope")
        setAccessibilityValue("Actions")
        setAccessibilityHelp("Search commands. Escape leaves Actions; Tab or Backspace leaves when the query is empty.")
    }
    func showExtension(name: String) {
        show(name, color: .white, opensMenu: false)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Extension search scope")
        setAccessibilityValue(name)
        setAccessibilityHelp("Send a query to this extension. Escape leaves the scope; Tab or Backspace leaves when the query is empty.")
    }
    private func show(_ name: String, color: NSColor, opensMenu: Bool) {
        titleLabel.stringValue = name; titleLabel.textColor = color
        self.opensMenu = opensMenu
        invalidateIntrinsicContentSize(); needsLayout = true
    }
    override var intrinsicContentSize: NSSize {
        let label = titleLabel.intrinsicContentSize, insets = Self.titleInsets
        return NSSize(width: label.width + insets.left + insets.right, height: label.height + insets.top + insets.bottom)
    }
    override func layout() {
        super.layout()
        let insets = Self.titleInsets
        //
        // text padding. A pill held at its 50-point minimum centres a short title.
        let width = max(0, min(titleLabel.intrinsicContentSize.width, bounds.width - insets.left - insets.right))
        titleLabel.frame = titleLabel.frame(forAlignmentRect: NSRect(x: ((bounds.width - width) / 2).rounded(),
            y: insets.bottom, width: width, height: max(0, bounds.height - insets.top - insets.bottom)))
        refreshLayer()
    }
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
    @objc private func openMenu() { if isEnabled && opensMenu { onOpen?() } }
    override func rightMouseDown(with event: NSEvent) { openMenu() }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, opensMenu, !isHidden else { return false }
        openMenu(); return true
    }
    /// Clicks on the title belong to the pill.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden || !frame.contains(point) ? nil : self
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
