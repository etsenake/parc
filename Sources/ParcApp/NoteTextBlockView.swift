import AppKit
import Combine

struct NoteTextBlockMetrics: Equatable {
    var leading: CGFloat
    var trailing: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var hint: CGFloat

    static let hintHeight: CGFloat = 28
    static let calloutIconSide: CGFloat = 26

    @MainActor
    static func make(for block: NoteBlock, marker: String?, presentation: NoteTextPresentation, readOnly: Bool) -> NoteTextBlockMetrics {
        let padding = NoteTheme.blockVerticalPadding
        var metrics = NoteTextBlockMetrics(leading: 0, trailing: 0, top: padding, bottom: padding, hint: 0)
        switch block.kind {
        case .heading:
            let level = min(max(block.props.level, 1), 6)
            metrics.top = [22, 16, 12, 8, 6, 6][level - 1]
            metrics.bottom = 2
            if block.props.toggleable { metrics.leading = NoteTheme.listMarkerWidth }
        case .bulletedItem, .todo, .toggle:
            metrics.leading = NoteTheme.listMarkerWidth
        case .numberedItem:
            let width = marker.map { ceil(NoteTextBlockView.markerString($0, presentation).size().width) + 8 } ?? 0
            metrics.leading = max(NoteTheme.listMarkerWidth, width)
        case .quote:
            metrics.leading = NoteTheme.quoteBarWidth + NoteTheme.quoteInset
        case .callout:
            let insets = NoteTheme.calloutPadding
            metrics.top = insets.top
            metrics.bottom = block.children.isEmpty || !block.showsChildren ? insets.bottom : 4
            metrics.leading = block.calloutDisplayIcon == nil ? insets.left : insets.left + calloutIconSide + 6
            metrics.trailing = insets.right
        default:
            break
        }
        if block.isToggle, block.props.expanded, block.children.isEmpty, !readOnly { metrics.hint = hintHeight }
        return metrics
    }
}

@MainActor
final class NoteTextBlockView: NoteBlockView, NoteTextHost {
    let textView = NoteTextView()
    var field: NoteTextField { .body }
    private(set) var presentation: NoteTextPresentation
    private(set) var marker: String?
    private var checkbox: NoteTodoCheckbox?
    private var disclosure: NoteToggleDisclosure?
    private var calloutIcon: NoteCalloutIconButton?
    private var hint: NoteToggleHintView?
    private var subscription: AnyCancellable?
    private var cachedHeight: (width: CGFloat, revision: Int, presentation: NoteTextPresentation, metrics: NoteTextBlockMetrics, height: CGFloat)?
    private weak var iconPanel: NoteFloatingPanel?

    override init(block: NoteBlock, editor: NotePageEditor?) {
        let settings = editor?.session.page.settings ?? NotePageSettings()
        presentation = NoteTextPresentation(block: block, settings: settings)
        super.init(block: block, editor: editor)
        textView.host = self
        textView.editor = editor
        textView.presentation = presentation
        textView.onContentHeightChange = { [weak self] in self?.contentHeightDidChange() }
        textView.onFocusChange = { [weak self] _ in self?.refreshPlaceholder() }
        addSubview(textView)
        if let page = editor?.session.page { marker = NoteListMarker.label(for: block, in: page) }
        configureControls(animated: false)
        textView.apply(block.text, selection: nil)
        refreshPlaceholder()
        refreshAccessibility()
        subscription = editor?.session.changes.sink { [weak self] change in self?.sessionDidChange(change) }
        NoteAnimation.observeReduceMotion(self) { [weak self] in self?.settleAnimations() }
    }

    private func settleAnimations() {
        textView.layer?.removeAnimation(forKey: NoteAnimation.fadeKey)
        checkbox?.settle()
        disclosure?.settle()
        if let layer = calloutIcon?.layer { NoteAnimation.settle(layer) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var textHosts: [NoteTextHost] { [self] }

    private var settings: NotePageSettings { editor?.session.page.settings ?? NotePageSettings() }

    private var metrics: NoteTextBlockMetrics {
        NoteTextBlockMetrics.make(for: block, marker: marker, presentation: presentation, readOnly: isReadOnly)
    }

    override func update(_ block: NoteBlock) {
        let old = self.block
        super.update(block)
        let next = NoteTextPresentation(block: block, settings: settings)
        let checkedChanged = old.kind == .todo && block.kind == .todo && old.props.checked != block.props.checked
        if checkedChanged { crossfadeText() }
        presentation = next
        textView.presentation = next
        if textView.noteText != block.text { textView.apply(block.text, selection: nil) }
        if let page = editor?.session.page { marker = NoteListMarker.label(for: block, in: page) }
        configureControls(animated: true)
        if checkedChanged, block.props.checked { checkbox?.pop() }
        refreshPlaceholder()
        refreshAccessibility()
        if old.kind != block.kind || old.props != block.props || old.children.map(\.id) != block.children.map(\.id) {
            contentHeightDidChange()
        }
    }

    private func sessionDidChange(_ change: NotePageChange) {
        guard change.kind != .text, change.kind != .selection, let page = editor?.session.page else { return }
        let label = page.block(block.id).flatMap { NoteListMarker.label(for: $0, in: page) }
        if label != marker {
            let widthChanged = block.kind == .numberedItem && label?.count != marker?.count
            marker = label
            needsDisplay = true
            refreshAccessibility()
            if widthChanged { contentHeightDidChange() }
        }
        if change.kind == .settings || change.kind == .replaced {
            let next = NoteTextPresentation(block: block, settings: page.settings)
            if next != presentation {
                presentation = next
                textView.presentation = next
                contentHeightDidChange()
            }
        }
    }

    override func readOnlyDidChange() {
        textView.isEditable = !isReadOnly
        textView.isSelectable = true
        checkbox?.isEnabled = !isReadOnly
        disclosure?.needsDisplay = true
        calloutIcon?.isEnabled = !isReadOnly
        configureControls(animated: false)
        refreshPlaceholder()
        contentHeightDidChange()
    }

    override func themeDidChange() {
        super.themeDidChange()
        let next = NoteTextPresentation(block: block, settings: settings)
        presentation = next
        textView.presentation = next
        textView.refreshRendering()
        checkbox?.refreshAppearance()
        disclosure?.refreshAppearance()
        calloutIcon?.needsDisplay = true
        hint?.needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redisplayChromeSubtree()
        checkbox?.refreshAppearance()
        disclosure?.refreshAppearance()
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        let metrics = self.metrics
        if let cached = cachedHeight, cached.width == width, cached.revision == textView.textRevision,
           cached.presentation == presentation, cached.metrics == metrics { return cached.height }
        let textWidth = max(1, width - metrics.leading - metrics.trailing)
        let text: CGFloat
        if let storage = textView.textStorage, storage.length > 0 {
            text = NoteTextRendering.height(of: storage, width: textWidth, emptyHeight: textView.lineHeight)
        } else {
            text = textView.lineHeight
        }
        let height = ceil(metrics.top + text + metrics.bottom + metrics.hint)
        cachedHeight = (width, textView.textRevision, presentation, metrics, height)
        return height
    }

    static func measureHeight(of block: NoteBlock, page: NotePage, width: CGFloat, readOnly: Bool = false) -> CGFloat {
        let presentation = NoteTextPresentation(block: block, settings: page.settings)
        let marker = NoteListMarker.label(for: block, in: page)
        let metrics = NoteTextBlockMetrics.make(for: block, marker: marker, presentation: presentation, readOnly: readOnly)
        let text = NoteTextRendering.height(of: block.text, presentation, width: max(1, width - metrics.leading - metrics.trailing))
        return ceil(metrics.top + text + metrics.bottom + metrics.hint)
    }

    override var handleAnchorY: CGFloat { metrics.top + textView.lineHeight / 2 }

    override var contentLeadingInset: CGFloat { metrics.leading }

    private var firstLineMidY: CGFloat { metrics.top + textView.lineHeight / 2 }

    override func layout() {
        super.layout()
        let metrics = self.metrics
        let textWidth = max(1, bounds.width - metrics.leading - metrics.trailing)
        let textHeight = max(textView.lineHeight, bounds.height - metrics.top - metrics.bottom - metrics.hint)
        NoteAnimation.withoutAnimation {
            textView.frame = NSRect(x: metrics.leading, y: metrics.top, width: textWidth, height: textHeight)
            let mid = firstLineMidY
            if let checkbox {
                let side = NoteTheme.toggleTriangleSize
                checkbox.frame = NSRect(x: (metrics.leading - side) / 2, y: mid - side / 2, width: side, height: side)
            }
            if let disclosure {
                let side = NoteTheme.toggleTriangleSize
                disclosure.frame = NSRect(x: (metrics.leading - side) / 2 - 1, y: mid - side / 2, width: side, height: side)
            }
            if let calloutIcon {
                let side = NoteTextBlockMetrics.calloutIconSide
                calloutIcon.frame = NSRect(x: NoteTheme.calloutPadding.left - 2, y: mid - side / 2, width: side, height: side)
            }
            if let hint {
                hint.frame = NSRect(x: metrics.leading - 4, y: bounds.height - metrics.bottom - metrics.hint,
                                    width: max(0, bounds.width - metrics.leading + 4 - metrics.trailing), height: metrics.hint)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            super.draw(dirtyRect)
            let metrics = self.metrics
            let ink = NoteTextRendering.metrics(presentation).ink
            switch block.kind {
            case .bulletedItem:
                drawBullet(level: NoteListMarker.bullets.firstIndex(of: marker ?? "") ?? 0, metrics: metrics, ink: ink)
            case .numberedItem:
                guard let marker else { break }
                let string = Self.markerString(marker, presentation)
                let size = string.size()
                let line = textView.lineHeight
                string.draw(with: NSRect(x: metrics.leading - 6 - ceil(size.width), y: metrics.top, width: ceil(size.width) + 2, height: line),
                            options: [.usesLineFragmentOrigin])
            case .quote:
                let color = presentation.color.map { $0.isBackground ? NoteTheme.quoteBar : NoteTheme.color($0) } ?? NoteTheme.quoteBar
                color.setFill()
                let bar = NSRect(x: 1, y: metrics.top, width: NoteTheme.quoteBarWidth, height: max(0, bounds.height - metrics.top - metrics.bottom - metrics.hint))
                NSBezierPath(roundedRect: bar, xRadius: NoteTheme.quoteBarWidth / 2, yRadius: NoteTheme.quoteBarWidth / 2).fill()
            default:
                break
            }
        }
    }

    private func drawBullet(level: Int, metrics: NoteTextBlockMetrics, ink: NSColor) {
        let size = NoteTextRendering.metrics(presentation).font.pointSize
        let diameter = max(5, (size * 0.36).rounded())
        let center = NSPoint(x: metrics.leading / 2, y: firstLineMidY)
        let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        ink.set()
        switch level % 3 {
        case 0:
            NSBezierPath(ovalIn: rect).fill()
        case 1:
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
            path.lineWidth = 1.4
            path.stroke()
        default:
            let square = rect.insetBy(dx: 0.5, dy: 0.5)
            NSBezierPath(roundedRect: square, xRadius: 1, yRadius: 1).fill()
        }
    }

    static func markerString(_ marker: String, _ presentation: NoteTextPresentation) -> NSAttributedString {
        let metrics = NoteTextRendering.metrics(presentation)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = metrics.lineHeight
        style.maximumLineHeight = metrics.lineHeight
        var font = metrics.font
        if font.fontDescriptor.symbolicTraits.contains(.monoSpace) == false {
            font = NSFont(descriptor: font.fontDescriptor.addingAttributes([
                .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]],
            ]), size: font.pointSize) ?? font
        }
        return NSAttributedString(string: marker, attributes: [
            .font: font,
            .foregroundColor: metrics.ink,
            .paragraphStyle: style,
            .baselineOffset: metrics.baselineOffset,
        ])
    }

    private func configureControls(animated: Bool) {
        let wantsCheckbox = block.kind == .todo
        if wantsCheckbox, checkbox == nil {
            let control = NoteTodoCheckbox()
            control.onToggle = { [weak self] in self?.toggleChecked() }
            addSubview(control)
            checkbox = control
        } else if !wantsCheckbox, let control = checkbox {
            control.removeFromSuperview()
            checkbox = nil
        }
        checkbox?.isEnabled = !isReadOnly
        checkbox?.setChecked(block.props.checked)

        if block.isToggle, disclosure == nil {
            let control = NoteToggleDisclosure()
            control.onToggle = { [weak self] in self?.toggleExpanded() }
            control.setExpanded(block.props.expanded, animated: false)
            addSubview(control)
            disclosure = control
        } else if !block.isToggle, let control = disclosure {
            control.removeFromSuperview()
            disclosure = nil
        }
        disclosure?.setExpanded(block.props.expanded, animated: animated)

        if block.kind == .callout, let icon = block.calloutDisplayIcon {
            if calloutIcon == nil {
                let button = NoteCalloutIconButton()
                button.target = self
                button.action = #selector(calloutIconPressed)
                addSubview(button)
                calloutIcon = button
            }
            calloutIcon?.icon = icon
            calloutIcon?.resolveImage = { [weak editor] source in
                if NoteCustomEmojiName.isReference(source) {
                    return NoteCustomEmojiImages.image(forReference: source, in: editor?.environment.emojiLibrary)
                }
                return editor?.environment.resolve(source).flatMap { NSImage(contentsOf: $0) }
            }
            calloutIcon?.isEnabled = !isReadOnly
        } else if let button = calloutIcon {
            button.removeFromSuperview()
            calloutIcon = nil
        }

        let wantsHint = metrics.hint > 0
        if wantsHint, hint == nil {
            let row = NoteToggleHintView()
            row.onActivate = { [weak self] in self?.insertFirstChild() }
            addSubview(row)
            hint = row
        } else if !wantsHint, let row = hint {
            row.removeFromSuperview()
            hint = nil
        }
        needsLayout = true
        needsDisplay = true
    }

    private func refreshPlaceholder() {
        guard !isReadOnly else { textView.placeholder = nil; return }
        if editor?.environment.isPlainText == true {
            textView.placeholder = "Just start writing"
            textView.placeholderShowsWhenUnfocused = false
            return
        }
        textView.placeholder = NoteTheme.placeholder(for: block.kind, level: block.props.level)
        textView.placeholderShowsWhenUnfocused = block.kind != .paragraph
    }

    private func refreshAccessibility() {
        textView.setAccessibilityLabel(Self.accessibilityLabel(for: block, marker: marker))
    }

    static func accessibilityLabel(for block: NoteBlock, marker: String?) -> String {
        switch block.kind {
        case .heading:
            let level = "Heading \(min(max(block.props.level, 1), 6))"
            return block.props.toggleable ? "Toggle " + level.lowercased() : level
        case .bulletedItem: return "Bulleted list item"
        case .numberedItem: return "Numbered list item" + (marker.map { " " + $0 } ?? "")
        case .todo: return block.props.checked ? "To-do, done" : "To-do"
        case .toggle: return block.props.expanded ? "Toggle, open" : "Toggle, closed"
        case .quote: return "Quote"
        case .callout: return "Callout"
        default: return "Text"
        }
    }

    private func contentHeightDidChange() {
        cachedHeight = nil
        needsLayout = true
        needsDisplay = true
        guard window != nil else { return }
        editor?.canvas.blockHeightDidChange(block.id)
    }

    private func crossfadeText() {
        guard window != nil, let layer = textView.layer else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = NoteAnimation.reduceMotion ? NoteAnimation.reducedFadeDuration : 0.2
        transition.timingFunction = NoteCurve.easeOut
        layer.add(transition, forKey: NoteAnimation.fadeKey)
    }

    private func toggleChecked() {
        guard !isReadOnly, let editor else { return }
        editor.session.toggleChecked([block.id])
    }

    private func toggleExpanded() {
        guard let editor else { return }
        editor.session.toggleExpanded(block.id)
    }

    private func insertFirstChild() {
        guard !isReadOnly, let editor else { return }
        let child = NoteBlock.paragraph()
        editor.session.insertBlocks([child], .firstChild(of: block.id), select: .caret(NotePosition(child.id, 0)))
        editor.focus(NotePosition(child.id, 0))
    }

    func calloutIconDidChange() {
        calloutIcon?.needsDisplay = true
        calloutIcon?.refreshAccessibility()
    }

    @objc private func calloutIconPressed() {
        guard !isReadOnly, let editor, let calloutIcon else { return }
        if let panel = iconPanel, panel.isPresented { panel.dismiss(animated: true); return }
        let picker = NoteEmojiPicker(showsRemove: true, showsRandom: true, library: editor.environment.emojiLibrary)
        picker.currentEmoji = block.props.icon
        let panel = NoteFloatingPanel(content: picker)
        let id = block.id
        picker.onPick = { [weak editor, weak panel] emoji in
            editor?.session.updateBlock(id, name: "Callout Icon") { $0.props.icon = emoji }
            panel?.dismiss(animated: true)
        }
        picker.onRemove = { [weak editor, weak panel] in
            editor?.session.updateBlock(id, name: "Callout Icon") { $0.props.icon = $0.calloutIconRemoval }
            panel?.dismiss(animated: true)
        }
        picker.onCancel = { [weak panel] in panel?.dismiss(animated: true) }
        let host = editor.canvas.overlayView
        panel.present(in: host, anchor: host.convert(calloutIcon.bounds, from: calloutIcon), edge: .below, animated: true)
        iconPanel = panel
    }
}

@MainActor
final class NoteTodoCheckbox: NSView {
    var onToggle: (() -> Void)?
    var isEnabled = true { didSet { if oldValue != isEnabled { refreshAppearance(); window?.invalidateCursorRects(for: self) } } }
    private(set) var isChecked = false
    private let mark = CALayer()
    private var isPressed = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true
        layer?.addSublayer(mark)
        mark.contentsGravity = .resizeAspect
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("Done")
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func setChecked(_ checked: Bool) {
        guard checked != isChecked else { return }
        isChecked = checked
        refreshAppearance()
    }

    func settle() { NoteAnimation.settle(mark) }

    func pop() {
        guard window != nil else { return }
        NoteAnimation.pop(mark, from: NoteAnimation.checkPopScale, spring: .check)
    }

    override func layout() {
        super.layout()
        let side = NoteTheme.todoBoxSize + 2
        NoteAnimation.withoutAnimation {
            mark.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        }
        refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshAppearance()
    }

    func refreshAppearance() {
        let scale = window?.backingScaleFactor ?? 2
        let name = isChecked ? "checkmark.circle.fill" : "circle"
        let colors: [NSColor] = isChecked ? [.white, NoteTheme.todoCheckFill] : [NoteTheme.todoBox]
        var image: CGImage?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let resolved = colors.map { NSColor(cgColor: $0.cgColor) ?? $0 }
            let configuration = NSImage.SymbolConfiguration(pointSize: NoteTheme.todoBoxSize, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: resolved))
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
            var rect = NSRect(origin: .zero, size: NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale))
            image = symbol.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
        }
        NoteAnimation.withoutAnimation {
            mark.contents = image
            mark.contentsScale = scale
        }
        setAccessibilityValue(isChecked ? 1 : 0)
    }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        setPressed(false)
        if inside { onToggle?() }
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        NoteAnimation.spring(mark, "transform.scale", to: pressed ? NoteAnimation.pressedScale : 1, spring: .press)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onToggle?()
        return true
    }
}

@MainActor
final class NoteToggleDisclosure: NSView {
    var onToggle: (() -> Void)?
    private(set) var isExpanded = false
    private let triangle = CAShapeLayer()
    private var isHovered = false
    private var isPressed = false
    private var area: NSTrackingArea?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        layer?.addSublayer(triangle)
        setAccessibilityElement(true)
        setAccessibilityRole(.disclosureTriangle)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func settle() { NoteAnimation.settle(triangle) }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        let changed = expanded != isExpanded
        isExpanded = expanded
        let angle = expanded ? CGFloat.pi / 2 : 0
        if changed, animated, window != nil {
            NoteAnimation.spring(triangle, "transform.rotation.z", to: angle, spring: .toggle)
        } else {
            NoteAnimation.withoutAnimation { triangle.setValue(angle, forKeyPath: "transform.rotation.z") }
        }
        setAccessibilityValue(expanded ? 1 : 0)
        setAccessibilityLabel(expanded ? "Hide contents" : "Show contents")
    }

    override func layout() {
        super.layout()
        let side: CGFloat = 10
        NoteAnimation.withoutAnimation {
            let rotation = triangle.value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
            triangle.transform = CATransform3DIdentity
            triangle.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            triangle.position = CGPoint(x: bounds.midX, y: bounds.midY)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 2.5, y: 1))
            path.addLine(to: CGPoint(x: 9, y: 5))
            path.addLine(to: CGPoint(x: 2.5, y: 9))
            path.closeSubpath()
            triangle.path = path
            triangle.lineJoin = .round
            triangle.lineWidth = 1.6
            triangle.setValue(rotation, forKeyPath: "transform.rotation.z")
        }
        refreshAppearance()
    }

    func refreshAppearance() {
        let ink = NoteTheme.resolved(NoteTheme.handleInk, in: self)
        let fill = isPressed ? NoteTheme.pressedFill : (isHovered ? NoteTheme.hoverFill : NSColor.clear)
        NoteAnimation.withoutAnimation {
            triangle.fillColor = ink
            triangle.strokeColor = ink
            layer?.backgroundColor = NoteTheme.resolved(fill, in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; refreshAppearance() }

    override func mouseExited(with event: NSEvent) { isHovered = false; refreshAppearance() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        refreshAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        refreshAppearance()
        if inside { onToggle?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onToggle?()
        return true
    }
}

@MainActor
final class NoteCalloutIconButton: PointingHandButton {
    var icon = "" { didSet { if oldValue != icon { needsDisplay = true; refreshAccessibility() } } }
    var resolveImage: ((String) -> NSImage?)?
    private var isHovered = false
    private var area: NSTrackingArea?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: NoteTextBlockMetrics.calloutIconSide, height: NoteTextBlockMetrics.calloutIconSide))
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        wantsLayer = true
        setAccessibilityLabel("Callout icon")
        toolTip = "Change icon"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var isCustomEmoji: Bool { NoteCustomEmojiName.isReference(icon) }

    private var isImageSource: Bool {
        isCustomEmoji || icon.contains("/") || icon.lowercased().hasSuffix(".png") || icon.lowercased().hasSuffix(".svg")
    }

    func refreshAccessibility() {
        let name = NoteCustomEmojiName.name(inReference: icon) ?? NoteEmojiCatalog.shared.entry(for: icon)?.displayName ?? icon
        setAccessibilityLabel("Callout icon, " + name)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            if isHovered, isEnabled {
                NoteTheme.hoverFill.setFill()
                NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
            }
            let side = NoteTheme.calloutIconSize - 2
            let box = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            if isImageSource, let image = resolveImage?(icon) {
                if isCustomEmoji {
                    NoteCustomEmojiImages.draw(image, fittingIn: box)
                } else {
                    image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                return
            }
            if isCustomEmoji {
                NoteTheme.mediaPlaceholderFill.setFill()
                NSBezierPath(roundedRect: box.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).fill()
                return
            }
            let font = NSFont(name: "Apple Color Emoji", size: NoteTheme.calloutIconSize - 4) ?? .systemFont(ofSize: NoteTheme.calloutIconSize - 4)
            let string = NSAttributedString(string: icon, attributes: [.font: font])
            let size = string.size()
            string.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }

    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let layer else { super.mouseDown(with: event); return }
        NoteAnimation.pop(layer, from: NoteAnimation.pressedScale, spring: .press)
        super.mouseDown(with: event)
    }
}

@MainActor
final class NoteToggleHintView: NSView {
    static let text = "Empty toggle. Drop blocks in or click to add one."
    var onActivate: (() -> Void)?
    private var isHovered = false
    private var area: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            if isHovered {
                NoteTheme.hoverFill.setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 2), xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
            }
            let font = NoteTheme.nunitoRegular(NoteTheme.smallBodySize)
            let string = NSAttributedString(string: Self.text, attributes: [.font: font, .foregroundColor: NoteTheme.tertiaryInk])
            let size = string.size()
            string.draw(with: NSRect(x: 4, y: (bounds.height - size.height) / 2, width: max(0, bounds.width - 8), height: size.height),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }

    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onActivate?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}
