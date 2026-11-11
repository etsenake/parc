import AppKit
import QuartzCore

@MainActor
final class SidebarSpaceHeaderView: NSView, NSTextFieldDelegate {
    static let nameIdentifier = "sidebarSpaceName"
    static let editButtonIdentifier = "sidebarSpaceEditButton"

    let nameField = SidebarMaskedTextField()
    private let symbolView = NSImageView()
    private let emojiField = NSTextField(labelWithString: "")
    private var showsIcon = false
    let profileButton = SpaceProfileIndicatorButton(title: "", target: nil, action: nil)
    let incognitoIndicator = IncognitoProfileIndicatorView()
    private var profileMenuProvider: (() -> NSMenu?)?
    private var isIncognitoIndicator = false
    private var isPrivateUnpinnedHeader = false
    func updateProfile(name: String?, menu: (() -> NSMenu?)?) {
        profileButton.isHidden = name == nil
        profileButton.title = name ?? ""
        profileButton.parcTooltip = name == nil ? nil : TooltipConfiguration(menu == nil ? "Current profile" : "Edit Space profile")
        profileButton.setAccessibilityLabel(name.map { "Profile: " + $0 } ?? "Profile")
        profileButton.cell?.setAccessibilityLabel(name.map { "Profile: " + $0 } ?? "Profile")
        profileButton.setAccessibilityHelp("Choose the Profile used by this Space")
        profileMenuProvider = menu
        profileButton.isEnabled = menu != nil
        needsLayout = true
    }

    func updateIncognitoIndicator(shown: Bool) {
        isPrivateUnpinnedHeader = true
        isIncognitoIndicator = shown
        nameField.isHidden = shown
        profileButton.isHidden = true
        incognitoIndicator.isHidden = !shown
        profileMenuProvider = nil
        needsLayout = true
    }
    @objc private func chooseProfile(_ sender: Any?) {
        profileMenuProvider?()?.popUp(positioning: nil, at: NSPoint(x: 0, y: profileButton.bounds.maxY), in: profileButton)
    }

    let editButton = SidebarSpaceHeaderEditButton()
    private var editButtonWidth: CGFloat = 0
    private var dark = false
    var canShowHeaderButtonsIfPossible = false {
        didSet { if canShowHeaderButtonsIfPossible != oldValue { updateEditButton(animated: false) } }
    }
    var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            if isEditing {
                editButton.image = nil
                editButton.title = NSLocalizedString("Done", comment: "Sidebar space header done button")
            } else {
                editButton.title = ""
                editButton.image = Self.ellipsis
            }
            updateEditButton(animated: true)
        }
    }
    private(set) var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            let delay = SidebarChromeLayout.SpaceHeader.editButtonHoverDelay(hovered: isHovered)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.updateEditButton(animated: self?.showsIcon == false) }
            }
        }
    }
    static var ellipsis: NSImage? {
        NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
    }

    private var renameFinished: ((String?) -> Void)?
    var onChangeIcon: (() -> Void)? { didSet { refreshActions() } }
    var managementMenu: (() -> SidebarSpaceMenu?)? { didSet { refreshActions() } }
    var onRenameSpace: (() -> Void)? { didSet { refreshActions() } }
    var onEditTheme: (() -> Void)? { didSet { refreshActions() } }
    var onNewFolder: (() -> Void)? { didSet { refreshActions() } }
    var onToggleHeader: (() -> Void)? { didSet { refreshActions() } }
    private(set) var toggleTitle: String?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameField.delegate = self
        nameField.usesSingleLineMode = true
        nameField.focusRingType = .none
        nameField.isBezeled = false
        nameField.backgroundColor = .clear
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.lineBreakMode = .byTruncatingTail
        nameField.font = .systemFont(ofSize: SidebarChromeLayout.SpaceHeader.fontSize, weight: .semibold)
        nameField.isMaskingEnabled = true
        nameField.setAccessibilityIdentifier(Self.nameIdentifier)
        nameField.cell?.setAccessibilityIdentifier(Self.nameIdentifier)
        symbolView.imageScaling = .scaleNone
        symbolView.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        emojiField.font = .systemFont(ofSize: 16)
        emojiField.alignment = .center
        for view in [symbolView, emojiField] as [NSControl] {
            view.setAccessibilityElement(false); view.cell?.setAccessibilityElement(false)
            view.isHidden = true
        }
        profileButton.isBordered = false
        profileButton.font = .systemFont(ofSize: 11, weight: .medium)
        profileButton.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)
        profileButton.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        profileButton.lineBreakMode = .byTruncatingTail
        profileButton.imagePosition = .imageLeading
        profileButton.contentTintColor = .tertiaryLabelColor
        profileButton.target = self; profileButton.action = #selector(chooseProfile(_:))
        profileButton.isHidden = true
        editButton.image = Self.ellipsis
        editButton.target = self
        editButton.action = #selector(didClickEditButton(_:))
        editButton.setAccessibilityIdentifier(Self.editButtonIdentifier)
        editButton.cell?.setAccessibilityIdentifier(Self.editButtonIdentifier)
        editButton.refusesFirstResponder = true
        incognitoIndicator.isHidden = true
        for view in [symbolView, emojiField, nameField, profileButton, incognitoIndicator, editButton] as [NSView] { addSubview(view) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: SidebarSpaceHeaderEditButton.trackingOptions, owner: self))
        symbolView.addCursorUpdateArea(owner: self); emojiField.addCursorUpdateArea(owner: self)
        applyStyle(dark: false, tint: nil)
        updateEditButton(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ content: SidebarChromeLayout.SpaceHeader.Content, symbol: NSImage?, emoji: String?) {
        if !isEditing, nameField.stringValue != content.title { nameField.stringValue = content.title }
        if nameField.placeholderString != content.placeholder { nameField.placeholderString = content.placeholder }
        toggleTitle = content.toggleTitle
        refreshActions()
        symbolView.image = emoji == nil ? symbol : nil
        emojiField.stringValue = emoji ?? ""
        symbolView.isHidden = symbolView.image == nil
        emojiField.isHidden = emoji == nil
        let icon = !symbolView.isHidden || !emojiField.isHidden
        if icon != showsIcon { showsIcon = icon; needsLayout = true; updateEditButton(animated: false) }
    }

    func applyStyle(dark: Bool, tint: NSColor?) {
        self.dark = dark
        profileButton.dark = dark
        incognitoIndicator.dark = dark
        let white: CGFloat = dark ? 1 : 0
        nameField.textColor = NSColor(srgbRed: white, green: white, blue: white, alpha: 0.45)
        symbolView.contentTintColor = tint ?? NSColor(srgbRed: white, green: white, blue: white, alpha: 0.3)
        editButton.contentTintColor = NSColor(srgbRed: white, green: white, blue: white, alpha: dark ? 0.592 : 0.565)
        editButton.hoveredBackgroundColor = editButtonHoverFill
    }

    private var editButtonHoverFill: NSColor {
        isEditing ? .clear : SidebarRowAppearance.controlFill(pressed: false, dark: dark)
    }

    private func updateEditButton(animated: Bool) {
        typealias H = SidebarChromeLayout.SpaceHeader
        let shown = H.showsEditButton(editing: isEditing, hovered: isHovered, canShowHeaderButtons: canShowHeaderButtonsIfPossible)
        editButton.hoveredBackgroundColor = editButtonHoverFill
        let width = H.editButtonWidth(shown: shown, editing: isEditing)
        if width != editButtonWidth {
            editButtonWidth = width
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        let alpha: CGFloat = shown ? 1 : 0
        guard animated else { editButton.alphaValue = alpha; return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = H.editButtonFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            editButton.animator().alphaValue = alpha
        }
    }

    override func layout() {
        super.layout()
        let frames = SidebarChromeLayout.SpaceHeader.frames(width: bounds.width, icon: showsIcon,
                                                            titleHeight: nameField.intrinsicContentSize.height,
                                                            editButtonWidth: editButtonWidth)
        let titleFrame: NSRect
        if isPrivateUnpinnedHeader {
            let leading: CGFloat = isIncognitoIndicator ? 10.5 : 14
            titleFrame = NSRect(x: leading, y: 8 + (26 - nameField.intrinsicContentSize.height) / 2,
                                width: max(0, bounds.width - leading - 8 - 4),
                                height: nameField.intrinsicContentSize.height)
        } else { titleFrame = frames.title }
        nameField.frame = titleFrame
        if !profileButton.isHidden {
            let width = min(max(28, profileButton.intrinsicContentSize.width + 8), min(110, titleFrame.width * 0.5))
            profileButton.frame = NSRect(x: titleFrame.maxX - width, y: (bounds.height - 20) / 2, width: width, height: 20)
            nameField.frame.size.width = max(0, titleFrame.width - width - 4)
        }
        if !incognitoIndicator.isHidden {
            let width = min(incognitoIndicator.intrinsicContentSize.width, titleFrame.width)
            let height = incognitoIndicator.intrinsicContentSize.height
            incognitoIndicator.frame = NSRect(x: titleFrame.minX, y: 21 - height / 2, width: width, height: height)
        }
        editButton.frame = frames.editButton
        if let icon = frames.icon {
            symbolView.frame = icon
            let height = emojiField.intrinsicContentSize.height
            emojiField.frame = NSRect(x: icon.minX, y: icon.midY - height / 2, width: icon.width, height: height)
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func viewDidHide() { super.viewDidHide(); clearHover() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        if let window { center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window) }
        if let newWindow { center.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: newWindow) }
        clearHover()
    }
    @objc private func windowDidResignKey(_ notification: Notification) { clearHover() }
    func clearHover() { isHovered = false; editButton.clearHover() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === editButton || hit === profileButton || isEditing && (hit === nameField || hit.isDescendant(of: nameField)) { return hit }
        return self
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsIcon, symbolView.frame.contains(point) || emojiField.frame.contains(point) { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsIcon, symbolView.frame.contains(point) || emojiField.frame.contains(point) {
            onChangeIcon?(); return
        }
        super.mouseDown(with: event)
    }

    @discardableResult func beginNameEditing(title: String?, finished: @escaping (String?) -> Void) -> Bool {
        guard !isEditing, let window else { return false }
        renameFinished = finished
        isEditing = true
        nameField.stringValue = title ?? ""
        nameField.isEditable = true; nameField.isSelectable = true
        guard window.makeFirstResponder(nameField) else { finishNameEditing(cancelled: true); return false }
        (nameField.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: (nameField.stringValue as NSString).length))
        return isEditing
    }
    func cancelNameEditing() { finishNameEditing(cancelled: true) }
    private func finishNameEditing(cancelled: Bool) {
        guard isEditing else { return }
        if !cancelled, (nameField.currentEditor() as? NSTextView)?.hasMarkedText() == true { return }
        let result = cancelled ? nil : nameField.stringValue
        let completion = renameFinished; renameFinished = nil
        isEditing = false; nameField.isEditable = false; nameField.isSelectable = false
        nameField.abortEditing(); nameField.layer?.mask = nil
        completion?(result)
    }
    func controlTextDidEndEditing(_ notification: Notification) { finishNameEditing(cancelled: false) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if command == #selector(NSResponder.cancelOperation(_:)) { finishNameEditing(cancelled: true); return true }
        if command == #selector(NSResponder.insertNewline(_:)) { finishNameEditing(cancelled: false); return true }
        return false
    }
    override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }

    @objc private func didClickEditButton(_ sender: Any?) {
        if isEditing { finishNameEditing(cancelled: false); return }
        guard let event = NSApp.currentEvent else { return }
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: editButton)
    }

    func makeMenu() -> NSMenu { spaceMenu?.makeMenu() ?? NSMenu() }

    private var spaceMenu: SidebarSpaceMenu? {
        if let managementMenu { return managementMenu() }
        return SidebarSpaceMenu(rename: onRenameSpace, editTheme: onEditTheme, newFolder: onNewFolder,
                         toggleTitle: toggleTitle, toggleHeader: onToggleHeader)
    }

    private func refreshActions() {
        let custom = spaceMenu?.accessibilityActions ?? []
        nameField.setAccessibilityCustomActions(custom)
        nameField.cell?.setAccessibilityCustomActions(custom)
    }
}

@MainActor
final class SidebarSpaceHeaderEditButton: PointingHandButton {
    static let trackingOptions: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect]
    static let cornerRadius: CGFloat = 6
    var hoveredBackgroundColor: NSColor = .clear { didSet { needsDisplay = true } }
    private(set) var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        setButtonType(.momentaryChange)
        isBordered = false
        alignment = .center
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: Self.trackingOptions, owner: self))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    func clearHover() { isHovered = false }

    override func updateLayer() {
        super.updateLayer()
        guard let layer else { return }
        layer.borderWidth = 0
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        layer.backgroundColor = (isHovered && isEnabled ? hoveredBackgroundColor : .clear).cgColor
    }
}

extension SidebarChromeLayout.SpaceHeader {
    struct Content: Equatable {
        var isShown: Bool
        var title: String
        var placeholder: String?
        var toggleTitle: String?
    }

    static func content(spaces: [BrowserSpace], activeSpaceID: UUID?, privateWindow: Bool,
                        showOnSingleUnnamedSpace: Bool) -> Content {
        guard let position = spaces.firstIndex(where: { $0.id == activeSpaceID }) else {
            return Content(isShown: false, title: "", placeholder: nil, toggleTitle: nil)
        }
        let space = spaces[position]
        let titled = space.title != nil
        let customIcon = space.customIcon != nil
        return Content(isShown: isShown(spaceCount: spaces.count, titled: titled, customIcon: customIcon,
                                        privateWindow: privateWindow, showOnSingleUnnamedSpace: showOnSingleUnnamedSpace),
                       title: space.title ?? "",
                       placeholder: titled ? nil : placeholderTitle(position: position),
                       toggleTitle: toggleTitle(spaceCount: spaces.count, titled: titled, customIcon: customIcon,
                                                showOnSingleUnnamedSpace: showOnSingleUnnamedSpace))
    }
}

@MainActor
final class SidebarMaskedTextField: NSTextField {
    static let rampWidth: CGFloat = 16
    let leadingMask: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [NSColor.clear.cgColor, NSColor.black.cgColor]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        return layer
    }()
    var isMaskingEnabled = false { didSet { updateMask(layer?.mask != nil) } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func updateMask(_ apply: Bool) {
        var mask: CALayer?
        if apply, isMaskingEnabled, isEditable, let cell {
            if let editor = currentEditor() {
                if editor.visibleRect.minX > 0 { mask = leadingMask }
            } else if cell.expansionFrame(withFrame: bounds, in: self) != .zero {
                mask = leadingMask
            }
        }
        layer?.mask = mask
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        updateMask(!stringValue.isEmpty)
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        layer?.mask = nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leadingMask.frame = bounds
        if bounds.width > 0 {
            leadingMask.locations = [0, NSNumber(value: Double(Self.rampWidth / bounds.width))]
        }
        CATransaction.commit()
    }
}

@MainActor final class SpaceProfileIndicatorButton: PointingHandButton {
    var dark = false { didSet { needsDisplay = true } }
    private var hover = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func viewDidHide() { super.viewDidHide(); hover = false }
    override func viewWillMove(toWindow newWindow: NSWindow?) { hover = false; super.viewWillMove(toWindow: newWindow) }
    override func draw(_ dirtyRect: NSRect) {
        let activeHover = hover && window?.isKeyWindow == true
        if isEnabled && (activeHover || isHighlighted) {
            SidebarRowAppearance.controlFill(pressed: isHighlighted, dark: dark).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        contentTintColor = NSColor(white: dark ? 1 : 0, alpha: activeHover || isHighlighted ? 0.65 : 0.45)
        super.draw(dirtyRect)
    }
}

@MainActor final class IncognitoProfileIndicatorView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "Incognito")
    var dark = false { didSet { applyColor() } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        icon.imageScaling = .scaleNone
        icon.imageAlignment = .alignCenter
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        icon.setAccessibilityElement(false); label.setAccessibilityElement(false)
        addSubview(icon); addSubview(label)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        LiveShortcutToolTip.set(self, "Incognito tabs")
        setAccessibilityElement(true); setAccessibilityLabel("Incognito tabs")
        applyColor()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize {
        NSSize(width: 5 + 20 + 2 + label.intrinsicContentSize.width + 6,
               height: max(11, label.intrinsicContentSize.height) + 8)
    }
    override func layout() {
        super.layout()
        let contentHeight = max(0, bounds.height - 8)
        icon.frame = NSRect(x: 5, y: 4, width: 20, height: contentHeight)
        let height = min(label.intrinsicContentSize.height, contentHeight)
        label.frame = NSRect(x: 27, y: (bounds.height - height) / 2, width: max(0, bounds.width - 33), height: height)
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? { "Incognito" }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityPerformPress() -> Bool { false }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(accessibilityPerformPress) { return false }
        return super.isAccessibilitySelectorAllowed(selector)
    }
    private func applyColor() {
        let color = NSColor(white: dark ? 1 : 0, alpha: 0.3)
        icon.contentTintColor = color; label.textColor = color
        layer?.backgroundColor = NSColor(srgbRed: dark ? 0.11 : 0.973,
                                         green: dark ? 0.11 : 0.973,
                                         blue: dark ? 0.11 : 0.973, alpha: 0.3).cgColor
    }
}
