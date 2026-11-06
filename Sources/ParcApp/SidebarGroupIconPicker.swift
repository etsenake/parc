import AppKit
import QuartzCore

///
/// tabs and Spaces use `tabAndSpacePicker`; lists and tab groups use
///
enum SidebarIconPickerSet {
    case folderPicker, tabAndSpacePicker
    var icons: [SidebarIconType] { self == .folderPicker ? SidebarIconType.folderPicker : SidebarIconType.tabAndSpacePicker }
}

///
///
enum SidebarIconPickerMetrics {
    static let horizontalPadding: CGFloat = 4
    static let verticalPadding: CGFloat = 6
    static let headerPadding: CGFloat = 8
    static let iconDimension: CGFloat = 14
    static let headerHeight: CGFloat = 20
    static let buttonDimension: CGFloat = 30
    static let emojiDimension: CGFloat = 24
    static let columns = 8
    static let gridSpacing: CGFloat = 1
    static let cornerRadius: CGFloat = 4
    static let removeWidth: CGFloat = 22
    static let removeGlyphSize: CGFloat = 15
    static let removeCornerRadius: CGFloat = 5  // HoverableButtonStyle
    /// SwiftUI's default HStack spacing between the page control and Remove [I].
    static let headerSpacing: CGFloat = 8
    /// 30 · 8 + 8 · 2 + 16 = 272.
    static let width = buttonDimension * CGFloat(columns) + headerPadding * 2 + 16
    static func rows(_ set: SidebarIconPickerSet) -> Int { Int((Double(set.icons.count) / Double(columns)).rounded(.up)) }
    /// rows · 30 + 8 · 2 + rows · 2 + 20 + 6 · 2: 272 for tabs/Spaces, 144 for folders.
    static func size(_ set: SidebarIconPickerSet) -> NSSize {
        let rows = CGFloat(self.rows(set))
        return NSSize(width: width, height: rows * buttonDimension + headerPadding * 2 + rows * 2 + headerHeight + verticalPadding * 2)
    }
}

/// The key-focus half of a split customization lease: the browser window or
/// the editor's own presentation (sheet, picker popover or a window it owns)
/// is key, and no other sheet is attached.
enum SplitCustomizationFocus {
    @MainActor static func isHeld(window: NSWindow, presentation: NSWindow?) -> Bool {
        (window.isKeyWindow || presentation?.isKeyWindow == true)
            && (window.attachedSheet == nil || window.attachedSheet === presentation)
    }
}

/// The original icon picker shared by split groups and Space creation, as
///
/// commits at once; Remove (shown only with an icon) commits nil. Through
/// `CustomInfoPickerHostingView` the picker stays open, as its
/// `didSelectIcon` closes nothing; Space creation's `TextAndIconPicker`
/// hides it on every choice (`closesAfterChoice`). Dismissal never changes
/// the model.
@MainActor
final class SidebarGroupIconPicker: NSViewController, NSPopoverDelegate {
    enum Page { case icon, emoji }
    private let popover = NSPopover()
    private(set) var selected: SidebarGroupIcon?
    let iconSet: SidebarIconPickerSet
    private let initialPage: Page
    private var committing = false
    private(set) var finished = false
    var isCurrent: () -> Bool = { false }
    var onCommit: ((SidebarGroupIcon?) throws -> Void)?
    /// A failed durable commit keeps the picker and old state for retry.
    var onFailure: ((Error) -> Void)?
    var onFinish: (() -> Void)?
    ///
    ///
    var closesAfterChoice = false
    /// The picker's own window, or the key window it owns: the skin-tone
    ///
    var presentationWindow: NSWindow? {
        guard isViewLoaded, let own = view.window else { return nil }
        let tone = pickerView?.emojiPage?.skinTonePopover?.popover.contentViewController.flatMap { $0.isViewLoaded ? $0.view.window : nil }
        return Self.ownedKeyWindow(of: own, extra: tone) ?? own
    }
    static func ownedKeyWindow(of own: NSWindow, extra: NSWindow?) -> NSWindow? {
        func descendants(_ window: NSWindow) -> [NSWindow] { (window.childWindows ?? []).flatMap { [$0] + descendants($0) } }
        return ([own] + descendants(own) + [extra].compactMap { $0 }).first { $0.isKeyWindow }
    }
    var pickerView: SidebarIconPickerView? { isViewLoaded ? view as? SidebarIconPickerView : nil }

    init(selected: SidebarGroupIcon?, iconSet: SidebarIconPickerSet = .tabAndSpacePicker) {
        self.selected = selected; self.iconSet = iconSet
        //
        // otherwise an emoji or no icon opens Emoji, an icon or symbol Icon.
        switch (iconSet, selected) {
        case (.folderPicker, _), (_, .icon?), (_, .symbol?): initialPage = .icon
        default: initialPage = .emoji
        }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let root = SidebarIconPickerView(set: iconSet, selected: selected, page: initialPage)
        root.onSelect = { [weak self] icon in self?.choose(icon) }
        view = root
    }

    ///
    ///
    /// with AppKit's default animation.
    func present(from anchor: NSView, rect: NSRect? = nil) {
        guard !finished, anchor.window?.isKeyWindow == true, isCurrent() else { cancel(); return }
        configurePopover()
        popover.show(relativeTo: rect ?? anchor.bounds, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
    }
    /// The popover retains this controller until it has closed.
    func configurePopover() {
        popover.contentViewController = self
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = view.frame.size
    }
    func reconcile() { if !committing && !finished && !isCurrent() { cancel() } }

    /// One `didSelectIcon` publication. The same icon is not republished.
    func choose(_ icon: SidebarGroupIcon?) {
        guard !finished, !committing, icon != selected, icon?.isValid != false else { return }
        guard isCurrent(), let onCommit else { cancel(); return }
        committing = true
        do {
            try onCommit(icon)
            committing = false
            selected = icon
            if closesAfterChoice { cancel(); return }
            pickerView?.update(selected: icon)
        } catch {
            committing = false
            pickerView?.update(selected: selected)
            if let onFailure { onFailure(error) } else { NSSound.beep() }
        }
    }
    override func cancelOperation(_ sender: Any?) { cancel() }
    func cancel() {
        guard !finished, !committing else { return }
        finished = true
        pickerView?.emojiPage?.closeSkinTone()
        popover.close()
        // Break popover → controller once nothing is shown; an animated close
        // finishes in popoverDidClose.
        if !popover.isShown { popover.contentViewController = nil }
        let done = onFinish; onFinish = nil; onCommit = nil; done?()
    }
    func popoverDidClose(_ notification: Notification) {
        cancel()
        popover.contentViewController = nil
    }
}

///
/// the current page, padded 4 horizontally and 6 vertically.
@MainActor
final class SidebarIconPickerView: NSView {
    typealias Page = SidebarGroupIconPicker.Page
    let set: SidebarIconPickerSet
    private(set) var page: Page
    private(set) var canRemoveIcon: Bool
    let segmentedControl: NSSegmentedControl?
    let heading: NSTextField?
    let removeButton = SidebarPickerRemoveButton()
    let iconGrid: SidebarIconGridView
    let emojiPage: SidebarEmojiPickerView?
    var onSelect: ((SidebarGroupIcon?) -> Void)?
    private var pageGeneration = 0
    private var headerGeneration = 0
    override var isFlipped: Bool { true }

    init(set: SidebarIconPickerSet, selected: SidebarGroupIcon?, page: Page) {
        self.set = set; self.page = page
        canRemoveIcon = selected != nil
        iconGrid = SidebarIconGridView(icons: set.icons)
        if case .icon(let type)? = selected { iconGrid.selectedIcon = type }
        if set == .tabAndSpacePicker {
            //
            let control = NSSegmentedControl(labels: ["Emoji", "Icon"], trackingMode: .selectOne, target: nil, action: nil)
            control.segmentDistribution = .fillEqually
            control.selectedSegment = page == .emoji ? 0 : 1
            segmentedControl = control; heading = nil
            emojiPage = SidebarEmojiPickerView(selectedEmoji: selected?.emoji)
        } else {
            //
            let title = NSTextField(labelWithString: "Icon")
            title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            heading = title; segmentedControl = nil; emojiPage = nil
        }
        super.init(frame: NSRect(origin: .zero, size: SidebarIconPickerMetrics.size(set)))
        segmentedControl?.target = self; segmentedControl?.action = #selector(pageChanged(_:))
        for view in [segmentedControl, heading, removeButton, iconGrid, emojiPage].compactMap({ $0 as NSView? }) { addSubview(view) }
        removeButton.isHidden = !canRemoveIcon
        removeButton.onPress = { [weak self] in self?.onSelect?(nil) }
        iconGrid.onSelect = { [weak self] type in self?.onSelect?(.icon(type)) }
        emojiPage?.onEmojiSelected = { [weak self] emoji in self?.onSelect?(.emoji(emoji)) }
        iconGrid.isHidden = page != .icon
        emojiPage?.isHidden = page != .emoji
        layoutPicker()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The selected icon after a commit (or the unchanged one after a failure).
    func update(selected: SidebarGroupIcon?) {
        if case .icon(let type)? = selected { iconGrid.selectedIcon = type } else { iconGrid.selectedIcon = nil }
        emojiPage?.selectedEmoji = selected?.emoji
        setCanRemoveIcon(selected != nil)
    }

    private var headerControl: NSView? { segmentedControl ?? heading }
    private var controlHeight: CGFloat { ceil(headerControl?.fittingSize.height ?? SidebarIconPickerMetrics.headerHeight) }
    private var headerFrame: NSRect {
        let m = SidebarIconPickerMetrics.self
        let inset = m.horizontalPadding + m.headerPadding
        return NSRect(x: inset, y: m.verticalPadding + m.headerPadding, width: bounds.width - inset * 2, height: controlHeight)
    }
    /// The header's control and Remove; Remove takes 22 points at the end.
    /// The folder title keeps its natural width, centered in what remains.
    func headerFrames(removable: Bool) -> (control: NSRect, remove: NSRect) {
        let m = SidebarIconPickerMetrics.self, header = headerFrame
        let reserved = removable ? m.removeWidth + m.headerSpacing : 0
        var control = header; control.size.width -= reserved
        if let heading {
            let width = min(control.width, ceil(heading.fittingSize.width))
            control.origin.x = header.minX + (control.width - width) / 2; control.size.width = width
        }
        let remove = NSRect(x: header.maxX - m.removeWidth, y: header.minY, width: m.removeWidth, height: header.height)
        return (control, remove)
    }
    /// The page area under the header (`.frame(maxHeight: .infinity)`).
    var pageFrame: NSRect {
        let m = SidebarIconPickerMetrics.self, top = headerFrame.maxY + m.headerPadding
        return NSRect(x: m.horizontalPadding, y: top, width: bounds.width - m.horizontalPadding * 2,
                      height: max(0, bounds.height - m.verticalPadding - top))
    }
    /// IconPickerGrid at its natural size, centered in the page area.
    var gridFrame: NSRect {
        let page = pageFrame, size = iconGrid.fittingSize
        return NSRect(x: page.midX - size.width / 2, y: page.midY - size.height / 2, width: size.width, height: size.height)
    }
    private func layoutPicker() {
        let frames = headerFrames(removable: canRemoveIcon)
        headerControl?.frame = frames.control
        removeButton.frame = frames.remove
        iconGrid.frame = page == .icon ? gridFrame : gridFrame.offsetBy(dx: gridFrame.width, dy: 0)
        emojiPage?.frame = page == .emoji ? pageFrame : pageFrame.offsetBy(dx: -pageFrame.width, dy: 0)
    }
    override func resizeSubviews(withOldSize oldSize: NSSize) { super.resizeSubviews(withOldSize: oldSize); layoutPicker() }

    /// `.animation(.easeOut(duration: 0.12), value: canRemoveIcon)` on the
    ///
    private func setCanRemoveIcon(_ removable: Bool) {
        guard removable != canRemoveIcon else { return }
        canRemoveIcon = removable
        headerGeneration += 1
        let generation = headerGeneration, frames = headerFrames(removable: removable)
        removeButton.frame = frames.remove
        if removable { removeButton.alphaValue = 0; removeButton.isHidden = false }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            headerControl?.animator().frame = frames.control
            removeButton.animator().alphaValue = removable ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.headerGeneration == generation, !removable else { return }
                self.removeButton.isHidden = true; self.removeButton.alphaValue = 1
            }
        })
    }

    /// `$page.animation(.easeOut(duration: 0.2))`: the icon page moves in from
    /// and out to the trailing edge, the emoji page the leading edge, each by
    ///
    @objc private func pageChanged(_ sender: NSSegmentedControl) { show(sender.selectedSegment == 0 ? .emoji : .icon) }
    func show(_ next: Page) {
        guard next != page, let emojiPage else { return }
        page = next
        segmentedControl?.selectedSegment = next == .emoji ? 0 : 1
        pageGeneration += 1
        let generation = pageGeneration
        emojiPage.closeSkinTone()
        let gridHome = gridFrame, emojiHome = pageFrame
        let gridAway = gridHome.offsetBy(dx: gridHome.width, dy: 0), emojiAway = emojiHome.offsetBy(dx: -emojiHome.width, dy: 0)
        iconGrid.isHidden = false; emojiPage.isHidden = false
        iconGrid.frame = next == .icon ? gridAway : gridHome
        emojiPage.frame = next == .emoji ? emojiAway : emojiHome
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            iconGrid.animator().frame = next == .icon ? gridHome : gridAway
            emojiPage.animator().frame = next == .emoji ? emojiHome : emojiAway
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pageGeneration == generation else { return }
                self.iconGrid.isHidden = next != .icon
                self.emojiPage?.isHidden = next != .emoji
            }
        })
    }
}

///
/// trash glyph (U+E9F0) under `HoverableButtonStyle(cornerRadius: 5)`, clear
///
/// while the window is key. Its action publishes `didSelectIcon(nil)`.
@MainActor
final class SidebarPickerRemoveButton: NSView {
    var onPress: (() -> Void)?
    private(set) var hovered = false { didSet { needsDisplay = true } }
    private(set) var pressed = false { didSet { needsDisplay = true } }
    private let glyph = NSImageView()
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = SidebarIconPickerMetrics.removeCornerRadius
        glyph.image = SidebarIconCatalog.featherImage(0xE9F0, size: SidebarIconPickerMetrics.removeGlyphSize)
        glyph.contentTintColor = .labelColor
        glyph.imageScaling = .scaleNone
        addSubview(glyph)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("Remove Icon")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let side = SidebarIconPickerMetrics.removeGlyphSize
        glyph.frame = NSRect(x: ((bounds.width - side) / 2).rounded(), y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseDragged(with event: NSEvent) { pressed = bounds.contains(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { onPress?() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = pressed || hovered ? SidebarRowAppearance.controlFill(pressed: pressed, dark: dark).cgColor : NSColor.clear.cgColor
    }
}

///
/// 30-point items one point apart; indexes past the catalog stay empty.
/// Before macOS 14 the grid is focusable and arrows move the selection
///
@MainActor
final class SidebarIconGridView: NSView {
    let icons: [SidebarIconType]
    let items: [SidebarIconItemView]
    var selectedIcon: SidebarIconType? { didSet { items.forEach { $0.isSelectedIcon = $0.type == selectedIcon } } }
    var onSelect: ((SidebarIconType) -> Void)?
    override var isFlipped: Bool { true }

    init(icons: [SidebarIconType]) {
        self.icons = icons
        items = icons.map(SidebarIconItemView.init(type:))
        super.init(frame: .zero)
        for (index, item) in items.enumerated() {
            item.onSelected = { [weak self] in self?.selectIcon(at: index) }
            addSubview(item)
        }
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Icon")
        frame.size = fittingSize
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private var columns: Int { SidebarIconPickerMetrics.columns }
    private var rows: Int { (icons.count + columns - 1) / columns }
    override var fittingSize: NSSize {
        let m = SidebarIconPickerMetrics.self
        return NSSize(width: CGFloat(columns) * m.buttonDimension + CGFloat(columns - 1) * m.gridSpacing,
                      height: CGFloat(rows) * m.buttonDimension + CGFloat(max(0, rows - 1)) * m.gridSpacing)
    }
    func itemFrame(at index: Int) -> NSRect {
        let m = SidebarIconPickerMetrics.self, step = m.buttonDimension + m.gridSpacing
        return NSRect(x: CGFloat(index % columns) * step, y: CGFloat(index / columns) * step,
                      width: m.buttonDimension, height: m.buttonDimension)
    }
    override func layout() {
        super.layout()
        for (index, item) in items.enumerated() { item.frame = itemFrame(at: index) }
    }

    ///
    func selectIcon(at index: Int) {
        guard icons.indices.contains(index), icons[index] != selectedIcon else { return }
        onSelect?(icons[index])
    }

    override var acceptsFirstResponder: Bool { !Self.isMacOS14 }
    /// Arrows from the selected index, handled even when nothing moves.
    override func keyDown(with event: NSEvent) {
        guard !Self.isMacOS14, let selectedIcon, let index = icons.firstIndex(of: selectedIcon) else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 126: selectIcon(at: index - columns)
        case 125: selectIcon(at: index + columns)
        case 123: if index % columns != 0 { selectIcon(at: index - 1) }
        case 124: if index % columns != columns - 1 { selectIcon(at: index + 1) }
        default: super.keyDown(with: event)
        }
    }
    private static var isMacOS14: Bool {
        if #available(macOS 14, *) { return true }
        return false
    }
}

///
/// button, white in the dark appearance and BrandGray otherwise. The
/// background is clear, 0.1 of that colour while hovered, 0.25 while selected
///
/// scales the content to 0.9 at 0.75 opacity with a spring (response 0.2,
/// damping fraction 0.4) while the background stays (`ScaleButtonStyle`
///
@MainActor
final class SidebarIconItemView: NSView {
    let type: SidebarIconType
    var isSelectedIcon = false { didSet { if isSelectedIcon != oldValue { setAccessibilitySelected(isSelectedIcon); needsDisplay = true } } }
    var onSelected: (() -> Void)?
    private(set) var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private(set) var pressed = false
    /// The scaled label content; the background stays on this view's layer.
    let glyphView = NSImageView()

    init(type: SidebarIconType) {
        self.type = type
        super.init(frame: NSRect(x: 0, y: 0, width: SidebarIconPickerMetrics.buttonDimension, height: SidebarIconPickerMetrics.buttonDimension))
        wantsLayer = true
        layer?.cornerRadius = SidebarIconPickerMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        glyphView.image = SidebarIconCatalog.image(for: type, size: SidebarIconPickerMetrics.iconDimension)
        glyphView.imageScaling = .scaleNone
        glyphView.wantsLayer = true
        glyphView.setAccessibilityElement(false)
        addSubview(glyphView)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel(type.rawValue)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    var glyphColor: NSColor { isDark ? .white : SidebarIconCatalog.brandGray }
    var backgroundColor: NSColor {
        isSelectedIcon ? glyphColor.withAlphaComponent(0.25) : hovered ? glyphColor.withAlphaComponent(0.1) : .clear
    }

    override func layout() {
        super.layout()
        let side = SidebarIconPickerMetrics.iconDimension
        glyphView.frame = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        applyPressTransform(animated: false)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = backgroundColor.cgColor
        if glyphView.contentTintColor != glyphColor { glyphView.contentTintColor = glyphColor }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { setPressed(true) }
    override func mouseDragged(with event: NSEvent) { setPressed(bounds.contains(convert(event.locationInWindow, from: nil))) }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        setPressed(false)
        if inside { onSelected?() }
    }
    override func accessibilityPerformPress() -> Bool { onSelected?(); return true }

    func setPressed(_ value: Bool) {
        guard value != pressed else { return }
        pressed = value
        applyPressTransform(animated: true)
    }
    /// Scale about the glyph's center whatever the layer's anchor point.
    private func pressTransform(_ scale: CGFloat, in layer: CALayer) -> CATransform3D {
        let anchor = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
        let dx = layer.bounds.midX - anchor.x, dy = layer.bounds.midY - anchor.y
        return CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), scale, scale, 1), -dx, -dy, 0)
    }
    /// Spring(response 0.2, dampingFraction 0.4): stiffness (2π / 0.2)²,
    /// damping 4π · 0.4 / 0.2, unit mass, from the presented value.
    private func applyPressTransform(animated: Bool) {
        guard let layer = glyphView.layer else { return }
        let transform = pressTransform(pressed ? 0.9 : 1, in: layer)
        let opacity: Float = pressed ? 0.75 : 1
        if animated {
            let presented = layer.presentation()
            for (keyPath, from, to) in [("transform", presented.map { NSValue(caTransform3D: $0.transform) } ?? NSValue(caTransform3D: layer.transform), NSValue(caTransform3D: transform)),
                                        ("opacity", NSNumber(value: presented?.opacity ?? layer.opacity), NSNumber(value: opacity))] as [(String, Any, Any)] {
                let spring = CASpringAnimation(keyPath: keyPath)
                spring.mass = 1
                spring.stiffness = pow(2 * .pi / 0.2, 2)
                spring.damping = 4 * .pi * 0.4 / 0.2
                spring.fromValue = from; spring.toValue = to
                spring.duration = spring.settlingDuration
                layer.add(spring, forKey: keyPath)
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = transform; layer.opacity = opacity
        CATransaction.commit()
    }
}
