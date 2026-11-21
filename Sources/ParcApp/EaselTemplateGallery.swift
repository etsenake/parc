import AppKit
import ParcCore

@MainActor
enum EaselTemplateThumbnails {
    private static var cache: [String: NSImage] = [:]

    static func image(_ template: EaselTemplate, dark: Bool) -> NSImage? {
        let key = template.rawValue + (dark ? ".dark" : ".light")
        if let image = cache[key] { return image }
        let drawing = EaselTemplates.placed(template, centeredAt: EaselPoint(x: 0, y: 0), firstZIndex: 0)
        let document = EaselDocument(id: UUID(), title: template.title, createdAt: Date(), modifiedAt: Date(), items: drawing.items)
        guard let session = try? EaselSession(inMemory: document, assets: [:]) else { return nil }
        let canvas = EaselCanvasView(session: session)
        canvas.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard let pdf = canvas.exportPDF(title: template.title), let image = NSImage(data: pdf) else { return nil }
        cache[key] = image
        return image
    }
}

@MainActor
final class EaselTemplateCard: PointingHandButton {
    let template: EaselTemplate
    var isCurrent = false { didSet { if isCurrent != oldValue { needsDisplay = true; refreshSurface() } } }
    var onHover: ((EaselTemplateCard) -> Void)?
    var onHoverEnd: ((EaselTemplateCard) -> Void)?
    private var hoverTracking: NSTrackingArea?
    static let size = NSSize(width: 152, height: 132)
    static let thumbnailHeight: CGFloat = 92

    init(template: EaselTemplate) {
        self.template = template
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        isBordered = false
        title = ""
        focusRingType = .none
        wantsLayer = true
        setButtonType(.momentaryChange)
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self)
            self.refreshSurface()
        }
        setEaselTooltip(template.blurb)
        setAccessibilityRole(.button)
        setAccessibilityLabel(template.title + " template")
        setAccessibilityHelp(template.blurb)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onHover?(self) }
    override func mouseExited(with event: NSEvent) { onHoverEnd?(self) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; refreshSurface() }

    override func highlight(_ flag: Bool) {
        let released = !flag && isHighlighted
        super.highlight(flag)
        needsDisplay = true
        refreshSurface(released: released)
    }

    private var thumbnailPath: CGPath {
        var rect = NSRect(x: 6, y: 6, width: bounds.width - 12, height: Self.thumbnailHeight)
        if layer?.isGeometryFlipped != isFlipped { rect.origin.y = bounds.height - rect.maxY }
        return CGPath(roundedRect: rect, cornerWidth: NoteTheme.controlRadius, cornerHeight: NoteTheme.controlRadius, transform: nil)
    }

    func refreshSurface(released: Bool = false) {
        EaselControlSurface.apply(self, hovered: isCurrent, pressed: isHighlighted, released: released,
                                  hover: EaselControlMotion.cardHoverScale, press: EaselControlMotion.cardPressedScale,
                                  shadowPath: thumbnailPath)
    }

    override func layout() {
        super.layout()
        guard let layer else { return }
        NoteAnimation.withoutAnimation { layer.shadowPath = thumbnailPath }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = NoteTheme.controlRadius + 2
        if isCurrent || isHighlighted {
            (isHighlighted ? NoteTheme.pressedFill : NoteTheme.hoverFill).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        let frame = NSRect(x: 6, y: 6, width: bounds.width - 12, height: Self.thumbnailHeight)
        let plate = NSBezierPath(roundedRect: frame, xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius)
        let dark = NoteTheme.isDark(effectiveAppearance)
        (dark ? NSColor.black : NSColor.white).setFill()
        plate.fill()
        if let image = EaselTemplateThumbnails.image(template, dark: dark), image.size.width > 0, image.size.height > 0 {
            let inset = frame.insetBy(dx: 8, dy: 8)
            let factor = min(inset.width / image.size.width, inset.height / image.size.height)
            let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
            let target = NSRect(x: inset.midX - size.width / 2, y: inset.midY - size.height / 2, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            plate.addClip()
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        }
        (isCurrent ? NoteTheme.accent : EaselAppearance.cardStroke).setStroke()
        plate.lineWidth = isCurrent ? 2 : 1
        plate.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NoteTheme.nunitoBold(13), .foregroundColor: NoteTheme.menuInk,
                                                              .paragraphStyle: paragraph]
        (template.title as NSString).draw(in: NSRect(x: 8, y: frame.maxY + 6, width: bounds.width - 16, height: 18), withAttributes: titleAttributes)
        let blurbAttributes: [NSAttributedString.Key: Any] = [.font: NoteTheme.nunitoRegular(11), .foregroundColor: NoteTheme.menuTertiaryInk,
                                                              .paragraphStyle: paragraph]
        (template.blurb as NSString).draw(in: NSRect(x: 8, y: frame.maxY + 23, width: bounds.width - 16, height: 15), withAttributes: blurbAttributes)
    }
}

@MainActor
final class EaselTemplateGallery: NSView, NoteFloatingPanelContent {
    static let gap: CGFloat = 8
    static let inset: CGFloat = 12
    var onPick: ((EaselTemplate) -> Void)?
    var onCancel: (() -> Void)?
    var preferredSizeDidChange: (() -> Void)?
    var columns: Int { didSet { if columns != oldValue { needsLayout = true; invalidateIntrinsicContentSize(); preferredSizeDidChange?() } } }
    var maximumRows: Int? { didSet { if maximumRows != oldValue { needsLayout = true; invalidateIntrinsicContentSize(); preferredSizeDidChange?() } } }
    let showsHeader: Bool
    private let titleLabel = NSTextField(labelWithString: "Templates")
    private let subtitleLabel = NSTextField(labelWithString: "Start from a board and make it yours.")
    private(set) var cards: [EaselTemplateCard] = []
    private(set) var current: Int?
    private var pointerDriven = false

    init(columns: Int = 4, showsHeader: Bool = true) {
        self.columns = max(1, columns)
        self.showsHeader = showsHeader
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Templates")
        titleLabel.font = NoteTheme.nunitoExtraBold(17)
        titleLabel.textColor = NoteTheme.menuInk
        subtitleLabel.font = NoteTheme.nunitoRegular(12)
        subtitleLabel.textColor = NoteTheme.menuTertiaryInk
        if showsHeader { addSubview(titleLabel); addSubview(subtitleLabel) }
        for template in EaselTemplate.allCases {
            let card = EaselTemplateCard(template: template)
            card.target = self
            card.action = #selector(cardPressed(_:))
            card.onHover = { [weak self] card in
                guard let self else { return }
                self.pointerDriven = true
                self.setCurrent(self.cards.firstIndex { $0 === card })
            }
            card.onHoverEnd = { [weak self] card in
                guard let self, self.pointerDriven, let current = self.current, self.cards[current] === card else { return }
                self.setCurrent(nil)
            }
            cards.append(card)
            addSubview(card)
        }
        setFrameSize(fittingSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    static func columns(fitting width: CGFloat) -> Int {
        max(1, Int((width - 2 * inset + gap) / (EaselTemplateCard.size.width + gap)))
    }

    static func rows(fitting height: CGFloat) -> Int {
        let rows = (height - 2 * inset + gap) / (EaselTemplateCard.size.height + gap)
        guard rows.isFinite, rows < 1000 else { return rows.isNaN ? 0 : 1000 }
        return max(0, Int(rows))
    }

    var shownCount: Int {
        guard let maximumRows else { return cards.count }
        let limit = maximumRows.multipliedReportingOverflow(by: max(1, columns))
        return limit.overflow ? cards.count : min(cards.count, max(0, limit.partialValue))
    }

    private var headerHeight: CGFloat { showsHeader ? 52 : 0 }

    override var fittingSize: NSSize {
        let count = shownCount
        let rows = (count + columns - 1) / columns
        let shown = min(columns, max(1, count))
        let width = 2 * Self.inset + CGFloat(shown) * EaselTemplateCard.size.width + CGFloat(shown - 1) * Self.gap
        let height = headerHeight + 2 * Self.inset + CGFloat(rows) * EaselTemplateCard.size.height + CGFloat(max(0, rows - 1)) * Self.gap
        return NSSize(width: width, height: height)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    override func layout() {
        super.layout()
        if showsHeader {
            titleLabel.frame = NSRect(x: Self.inset + 6, y: 14, width: bounds.width - 2 * Self.inset - 12, height: 22)
            subtitleLabel.frame = NSRect(x: Self.inset + 6, y: 36, width: bounds.width - 2 * Self.inset - 12, height: 16)
        }
        let shown = shownCount
        if let current, current >= shown { setCurrent(nil) }
        for (index, card) in cards.enumerated() {
            card.isHidden = index >= shown
            let row = index / columns, column = index % columns
            card.frame = NSRect(x: Self.inset + CGFloat(column) * (EaselTemplateCard.size.width + Self.gap),
                                y: headerHeight + Self.inset + CGFloat(row) * (EaselTemplateCard.size.height + Self.gap),
                                width: EaselTemplateCard.size.width, height: EaselTemplateCard.size.height)
        }
    }

    func setCurrent(_ index: Int?) {
        let next = index.flatMap { $0 >= 0 && $0 < shownCount ? $0 : nil }
        current = next
        for (offset, card) in cards.enumerated() { card.isCurrent = offset == next }
        if let next { NSAccessibility.post(element: cards[next], notification: .focusedUIElementChanged) }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags.isEmpty || (flags == .shift && event.keyCode == 48) else { return false }
        let count = shownCount
        guard count > 0 else { return false }
        pointerDriven = false
        let index = current
        func move(_ delta: Int) {
            guard let index else { setCurrent(delta < 0 ? count - 1 : 0); return }
            setCurrent(min(count - 1, max(0, index + delta)))
        }
        switch event.keyCode {
        case 123: move(-1)
        case 124: move(1)
        case 126: if index == nil { move(-1) } else if let index, index - columns >= 0 { setCurrent(index - columns) }
        case 125: if index == nil { move(1) } else if let index, index + columns < count { setCurrent(index + columns) }
        case 48: move(flags == .shift ? -1 : 1)
        case 36, 76, 49:
            guard let index else { setCurrent(0); return true }
            pick(cards[index].template)
        case 53:
            guard let onCancel else { return false }
            onCancel()
        default: return false
        }
        return true
    }

    @objc private func cardPressed(_ sender: EaselTemplateCard) { pick(sender.template) }

    private func pick(_ template: EaselTemplate) { onPick?(template) }
}

@MainActor
enum EaselTemplatePanel {
    private static var openPopover: NotePagePopover?

    static func present(editor: EaselEditorViewController, from control: NSView? = nil) {
        if let openPopover, openPopover.isOpen { openPopover.close(animated: false) }
        guard editor.canvas.acceptsTemplates, editor.view.window?.attachedSheet == nil else { return }
        let gallery = EaselTemplateGallery(columns: 4)
        let popover = NotePagePopover(content: gallery)
        if let control { popover.exempt(control) }
        gallery.onPick = { [weak editor, weak popover] template in
            popover?.close()
            editor?.canvas.insertTemplate(template)
        }
        gallery.onCancel = { [weak popover] in popover?.close() }
        popover.onKeyDown = { [weak gallery] event in gallery?.handleKeyDown(event) ?? false }
        popover.onClose = { openPopover = nil }
        openPopover = popover
        let host = editor.view
        if NSApp.currentEvent?.type == .keyDown { gallery.setCurrent(0) }
        if let control, control.window === host.window {
            popover.present(in: host, anchor: host.convert(control.bounds, from: control), edge: .below, alignment: .center)
        } else {
            let area = editor.canvas.enclosingScrollView.map { host.convert($0.frame, from: $0.superview) } ?? host.bounds
            popover.present(in: host, anchor: NSRect(x: area.midX - 1, y: area.minY + 24, width: 2, height: 0), edge: .below, alignment: .center)
        }
    }
}

@MainActor
extension EaselEditorViewController {
    func installEmptyTemplates(in root: NSView) {
        guard canvas.acceptsTemplates, emptyTemplates == nil else { return }
        let gallery = EaselTemplateGallery(columns: 4, showsHeader: false)
        gallery.onPick = { [weak self] template in self?.canvas.insertTemplate(template) }
        emptyTemplates = gallery
        canvas.onboarding.templateRow = EaselEmptyStateRow(title: "Or start from a template", view: gallery,
                                                           inset: EaselTemplateGallery.inset + 6) { [weak gallery] width, height in
            guard let gallery else { return .zero }
            gallery.columns = min(4, EaselTemplateGallery.columns(fitting: width))
            let rows = EaselTemplateGallery.rows(fitting: height)
            guard rows > 0 else { return .zero }
            gallery.maximumRows = rows
            return gallery.fittingSize
        }
        canvas.refreshOnboarding()
    }

    func refreshEmptyTemplates() {
        guard isViewLoaded else { return }
        if !canvas.acceptsTemplates, canvas.onboarding.templateRow != nil { canvas.onboarding.templateRow = nil }
        canvas.refreshOnboarding()
    }
}
