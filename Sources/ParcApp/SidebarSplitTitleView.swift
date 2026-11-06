import AppKit

///
///
/// holds a 24-point `SidebarCellImageContainerView` with the item-count icon or
///
///
/// original activation/close owners.
@MainActor
final class SidebarSplitTitleView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    /// `SplitViewCellItemCountIconView`: a rounded box behind a bold count.
    private let countIcon = NSView()
    private let countLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let titleField = SidebarTitleField()
    private let defaultIconText: String
    var trailingControlWidth: CGFloat = 0 { didSet { needsLayout = true } }
    /// The title's trailing edge: the stack's 18-point trailing inset before
    /// the split's Close, or before the cell edge (`SidebarSplitCellLayout`).
    var titleTrailing: CGFloat? { didSet { if titleTrailing != oldValue { needsLayout = true } } }
    var prepareActivation: (() -> (() -> Bool)?)?
    var selectionClick: ((NSEvent) -> Bool)?
    var makeMenu: (() -> NSMenu?)?
    ///
    /// on it moves the whole split (the press and the drag events).
    var beginMoveDrag: ((NSEvent, NSEvent) -> Void)?
    private var pendingActivation: (() -> Bool)?
    private var pressEvent: NSEvent?
    private weak var pressedWindow: NSWindow?
    private var resignObserver: NSObjectProtocol?
    var editingTitle: Bool { titleField.editingTitle }
    override var isFlipped: Bool { true }

    ///
    /// the split's own name; accessibility then names only the split.
    init(title: String, count: Int, named: Bool = true) {
        defaultIconText = String(count)
        super.init(frame: .zero)
        titleLabel.stringValue = title
        // SidebarCellConstants.Title.font, one weight whether or not current.
        titleLabel.font = .systemFont(ofSize: SidebarSplitCellLayout.titleFontSize)
        titleLabel.textColor = .parcInk
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        countIcon.wantsLayer = true
        countIcon.layer?.cornerRadius = SidebarSplitCellLayout.countIconCornerRadius
        countIcon.layer?.cornerCurve = .continuous
        countIcon.setAccessibilityElement(false)
        countLabel.stringValue = String(count)
        countLabel.font = .systemFont(ofSize: SidebarSplitCellLayout.countFontSize, weight: .bold)
        countLabel.textColor = .parcInk.withAlphaComponent(0.65)
        countLabel.alignment = .center
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.setAccessibilityElement(false)
        countIcon.addSubview(countLabel)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        titleField.setAccessibilityLabel("Split View name")
        for view in [countIcon, iconView, titleLabel, titleField] as [NSView] { addSubview(view) }
        setIcon(nil)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel(!named || title.isEmpty ? "Split View, \(count) tabs" : "\(title), Split View, \(count) tabs")
        //
        //
        // one has none.
        parcTooltip = named && !title.isEmpty ? TooltipConfiguration(title, behavior: .onMouseIdle(delay: 0.01)) : nil
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    ///
    /// icon drawn at the favicon size, `SidebarCustomIcon.image(withSize:)`
    ///
    /// Symbol, or its EmojiIcon image fitted to 16 points, which the
    /// ForegroundSecondary tint does not recolor.
    func setIcon(_ icon: SidebarGroupIcon?) {
        iconView.image = icon?.image(size: SidebarSplitCellLayout.countIconSize)
        iconView.isHidden = iconView.image == nil
        countIcon.isHidden = !iconView.isHidden
        countLabel.stringValue = defaultIconText
        needsLayout = true
    }
    /// The 24-point icon container (`SidebarCellImageContainerView`), which
    ///
    var iconContainerFrame: NSRect {
        NSRect(x: SidebarSplitCellLayout.infoLeadingInset,
               y: ((bounds.height - SidebarSplitCellLayout.infoIconSlot) / 2).rounded(.down),
               width: SidebarSplitCellLayout.infoIconSlot, height: SidebarSplitCellLayout.infoIconSlot)
    }
    /// The title takes the palette's title color, the count its
    ///
    ///
    func applyColors(title: NSColor, secondary: NSColor, countText: NSColor? = nil,
                     countBackground: NSColor? = nil, dark: Bool = false) {
        titleLabel.textColor = title; titleField.textColor = title
        countLabel.textColor = countText ?? secondary
        //
        countIcon.layer?.backgroundColor = countBackground?.withAlphaComponent(SidebarSplitCellLayout.countBackgroundAlpha).cgColor
        iconView.contentTintColor = SidebarSplitCellLayout.customIconTint(dark: dark)
    }
    @discardableResult func begin(title: String, finished: @escaping (String?) -> Void) -> Bool {
        pendingActivation = nil; pressedWindow = nil; pressEvent = nil
        titleField.font = titleLabel.font; titleField.textColor = titleLabel.textColor
        titleField.onFinish = { [weak self] value in
            self?.titleLabel.isHidden = false; self?.needsLayout = true
            self?.setAccessibilityRole(.button); self?.setAccessibilityChildren([])
            finished(value)
        }
        layoutSubtreeIfNeeded()
        guard titleField.begin(title: title) else { titleField.onFinish = nil; return false }
        titleField.placeholderString = "Title"
        titleLabel.isHidden = true
        setAccessibilityRole(.group); setAccessibilityChildren([titleField])
        return true
    }
    func cancel() { titleField.cancel() }
    override func layout() {
        super.layout()
        let slot = iconContainerFrame
        let size = SidebarSplitCellLayout.countIconSize
        let icon = NSRect(x: slot.midX - size / 2, y: slot.midY - size / 2, width: size, height: size)
        countIcon.frame = icon; iconView.frame = icon
        let countHeight = ceil(countLabel.intrinsicContentSize.height)
        countLabel.frame = NSRect(x: 0, y: ((size - countHeight) / 2).rounded(), width: size, height: countHeight)
        let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
        let x = SidebarSplitCellLayout.infoTitleInset - SidebarRowAppearance.titleTextPadding
        let trailing = (titleTrailing ?? bounds.width - 10) - trailingControlWidth
        titleLabel.frame = NSRect(x: x, y: ((bounds.height - titleHeight) / 2).rounded(.down),
                                  width: max(0, trailing + SidebarRowAppearance.titleTextPadding - x), height: titleHeight)
        titleField.frame = titleLabel.frame
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let result = super.hitTest(point) else { return nil }
        return editingTitle ? result : self
    }
    override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }
    override func mouseDown(with event: NSEvent) {
        pendingActivation = nil; pressedWindow = nil; pressEvent = nil
        guard !editingTitle, window?.isKeyWindow == true, window?.attachedSheet == nil else { return }
        if selectionClick?(event) == true { return }
        pendingActivation = prepareActivation?(); pressedWindow = window; pressEvent = event
    }
    override func mouseDragged(with event: NSEvent) {
        guard let press = pressEvent, !editingTitle else { return }
        let start = convert(press.locationInWindow, from: nil), point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        pendingActivation = nil; pressedWindow = nil; pressEvent = nil
        beginMoveDrag?(press, event)
    }
    override func mouseUp(with event: NSEvent) {
        let action = pendingActivation, original = pressedWindow
        pendingActivation = nil; pressedWindow = nil; pressEvent = nil
        guard !editingTitle, let original, window === original, original.isKeyWindow,
              original.attachedSheet == nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        _ = action?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard !editingTitle, window?.isKeyWindow == true, window?.attachedSheet == nil else { return false }
        return prepareActivation?()?() == true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pendingActivation = nil; pressedWindow = nil; pressEvent = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pendingActivation = nil; self?.pressedWindow = nil; self?.pressEvent = nil }
            }
        }
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { pendingActivation = nil; pressedWindow = nil; pressEvent = nil; cancel() }
        super.viewWillMove(toSuperview: newSuperview)
    }
    deinit { if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) } }
}
