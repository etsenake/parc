import AppKit
import Combine

@MainActor
final class NoteBacklinksListView: NSView, NoteFloatingPanelContent {
    enum Style { case menu, inline }

    static let rowHeight: CGFloat = 46
    static let menuWidth: CGFloat = 340
    static let iconSide: CGFloat = 22

    let style: Style
    var onOpen: ((NoteBacklink) -> Void)?
    var preferredSizeDidChange: (() -> Void)?
    var maximumHeight: CGFloat = 380
    var title: String? { didSet { if title != oldValue { relayout() } } }
    var items: [NoteBacklink] = [] {
        didSet {
            guard items != oldValue else { return }
            if let highlighted, highlighted >= items.count { setHighlight(nil, animated: false) }
            relayout()
        }
    }
    var iconImage: (NoteBacklink) -> NSImage? = { NoteBacklinksListView.artwork(for: $0) }

    private let scrollView = NSScrollView()
    private let container = NoteBacklinksContainerView()
    private let plate = NSView()
    private let rows = NoteBacklinksRowsView()
    private(set) var highlighted: Int?
    private var pressed: Int?
    private var artSubscription: AnyCancellable?

    init(style: Style) {
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: Self.menuWidth, height: Self.rowHeight))
        wantsLayer = true
        plate.wantsLayer = true
        plate.layer?.cornerRadius = NoteTheme.menuHighlightRadius
        plate.layer?.cornerCurve = .continuous
        plate.layer?.opacity = 0
        plate.setAccessibilityElement(false)
        rows.list = self
        container.addSubview(plate)
        container.addSubview(rows)
        if style == .menu {
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.horizontalScrollElasticity = .none
            scrollView.contentView.drawsBackground = false
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.documentView = container
            addSubview(scrollView)
        } else {
            addSubview(container)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Backlinks")
        artSubscription = NoteTabIconArt.shared.changes.sink { [weak self] _ in self?.rows.needsDisplay = true }
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self, let layer = self.plate.layer else { return }
            NoteAnimation.settle(layer)
        }
        refreshPlate()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var headerHeight: CGFloat { title == nil ? 0 : NoteTheme.menuHeaderHeight }
    var inset: CGFloat { style == .menu ? NoteTheme.menuInset : 0 }
    var contentHeight: CGFloat { headerHeight + CGFloat(items.count) * Self.rowHeight + inset * 2 }

    override var intrinsicContentSize: NSSize {
        NSSize(width: style == .menu ? Self.menuWidth : NSView.noIntrinsicMetric,
               height: style == .menu ? min(contentHeight, maximumHeight) : contentHeight)
    }

    override var fittingSize: NSSize {
        NSSize(width: style == .menu ? Self.menuWidth : bounds.width, height: intrinsicContentSize.height)
    }

    func rowFrame(_ index: Int) -> NSRect {
        NSRect(x: inset, y: inset + headerHeight + CGFloat(index) * Self.rowHeight, width: max(0, container.bounds.width - inset * 2),
               height: Self.rowHeight)
    }

    func index(at point: NSPoint) -> Int? {
        let y = point.y - inset - headerHeight
        guard y >= 0, point.x >= inset, point.x <= container.bounds.width - inset else { return nil }
        let index = Int(y / Self.rowHeight)
        return items.indices.contains(index) ? index : nil
    }

    private func relayout() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        rows.needsDisplay = true
        rows.refreshAccessibility()
        preferredSizeDidChange?()
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            let size = NSSize(width: bounds.width, height: max(bounds.height, contentHeight))
            if style == .menu {
                scrollView.frame = bounds
                container.frame = NSRect(origin: .zero, size: NSSize(width: bounds.width, height: contentHeight))
            } else {
                container.frame = NSRect(origin: .zero, size: size)
            }
            rows.frame = container.bounds
            if let highlighted { plate.frame = rowFrame(highlighted) }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPlate()
        rows.needsDisplay = true
    }

    private func refreshPlate() {
        let color = pressed != nil ? (style == .menu ? NoteTheme.menuPressed : NoteTheme.pressedFill)
            : (style == .menu ? NoteTheme.menuHighlight : NoteTheme.hoverFill)
        NoteAnimation.withoutAnimation { plate.layer?.backgroundColor = NoteTheme.resolved(color, in: self) }
    }

    func setHighlight(_ index: Int?, animated: Bool) {
        guard index != highlighted else { return }
        let wasVisible = highlighted != nil
        highlighted = index
        rows.needsDisplay = true
        guard let index else {
            NoteAnimation.fade(plate, visible: false, duration: NoteAnimation.hoverDuration)
            return
        }
        let frame = rowFrame(index)
        if wasVisible, animated, !NoteAnimation.reduceMotion {
            _ = NoteAnimation.slide(plate, to: frame, spring: .highlight)
        } else {
            NoteAnimation.withoutAnimation { plate.frame = frame }
        }
        if !wasVisible { NoteAnimation.fade(plate, visible: true, duration: NoteAnimation.hoverDuration) }
        if style == .menu { container.scrollToVisible(frame) }
    }

    func press(_ index: Int?) {
        pressed = index
        refreshPlate()
        guard let layer = plate.layer else { return }
        let center = CGPoint(x: plate.bounds.midX, y: plate.bounds.midY)
        let target = index == nil ? CATransform3DIdentity : NoteAnimation.scaleTransform(NoteAnimation.rowPressedScale, about: center)
        NoteAnimation.spring(layer, "transform", to: NSValue(caTransform3D: target), spring: .press, key: NoteAnimation.keyPrefix + "press")
    }

    func open(_ index: Int) {
        guard items.indices.contains(index) else { return }
        onOpen?(items[index])
    }

    @discardableResult
    func moveHighlight(by delta: Int) -> Bool {
        guard !items.isEmpty else { return false }
        let next = highlighted.map { min(max(0, $0 + delta), items.count - 1) } ?? (delta > 0 ? 0 : items.count - 1)
        setHighlight(next, animated: true)
        return true
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: return moveHighlight(by: 1)
        case 126: return moveHighlight(by: -1)
        case 36, 76:
            guard let highlighted else { return false }
            open(highlighted)
            return true
        default: return false
        }
    }

    static func countLabel(_ count: Int) -> String {
        count == 1 ? "1 backlink" : "\(count) backlinks"
    }

    static func artwork(for item: NoteBacklink) -> NSImage? {
        guard let icon = item.icon, NoteTabIcon.emoji(icon) == nil else { return nil }
        return NoteTabIconArt.shared.image(forNote: item.source, size: iconSide)
    }

    func drawRow(_ index: Int, in frame: NSRect) {
        let item = items[index]
        let menu = style == .menu
        let ink = menu ? NoteTheme.menuInk : NoteTheme.ink
        let secondary = menu ? NoteTheme.menuSecondaryInk : NoteTheme.secondaryInk
        let box = NSRect(x: frame.minX + 10, y: (frame.midY - Self.iconSide / 2).rounded(), width: Self.iconSide, height: Self.iconSide)
        if item.isEasel {
            NoteIconRenderer.draw(.easelMark, in: box, tint: secondary, pointSize: 15)
        } else if let emoji = item.icon.flatMap(NoteTabIcon.emoji) {
            NoteIconRenderer.draw(.emoji(emoji), in: box, tint: ink, pointSize: 16)
        } else if let image = iconImage(item) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).addClip()
            image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NoteIconRenderer.draw(.noteMark, in: box, tint: secondary, pointSize: 15)
        }
        let x = box.maxX + 12
        let width = max(0, frame.maxX - 10 - x)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleFont = NoteTheme.menuTitleFont()
        var titleText = item.title.isEmpty ? "Untitled" : item.title
        if item.links > 1 { titleText += "  ·  \(item.links) links" }
        let title = NSMutableAttributedString(string: titleText, attributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: paragraph])
        if item.links > 1 {
            let suffix = (titleText as NSString).length - ((item.title.isEmpty ? "Untitled" : item.title) as NSString).length
            title.addAttributes([.foregroundColor: menu ? NoteTheme.menuTertiaryInk : NoteTheme.tertiaryInk, .font: NoteTheme.menuSubtitleFont()],
                                range: NSRange(location: title.length - suffix, length: suffix))
        }
        let titleHeight = ceil(titleFont.ascender - titleFont.descender)
        let snippetFont = NoteTheme.menuSubtitleFont()
        let snippetHeight = ceil(snippetFont.ascender - snippetFont.descender)
        let top = (frame.midY - (titleHeight + 1 + snippetHeight) / 2).rounded()
        title.draw(with: NSRect(x: x, y: top, width: width, height: titleHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        let snippetText = item.snippet.text.isEmpty ? "Linked here" : item.snippet.text
        let snippet = NSMutableAttributedString(string: snippetText, attributes: [.font: snippetFont, .foregroundColor: secondary, .paragraphStyle: paragraph])
        if let highlight = item.snippet.highlight, highlight.upperBound <= snippet.length {
            snippet.addAttributes([.foregroundColor: ink, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .underlineColor: NoteTheme.mentionUnderline],
                                  range: NSRange(location: highlight.lowerBound, length: highlight.count))
        }
        snippet.draw(with: NSRect(x: x, y: top + titleHeight + 1, width: width, height: snippetHeight),
                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

@MainActor
private final class NoteBacklinksContainerView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class NoteBacklinksRowsView: NSView {
    weak var list: NoteBacklinksListView?
    private var trackingArea: NSTrackingArea?
    private var elements: [NoteBacklinkAccessibilityRow] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let list else { return }
        drawInOwnAppearance {
            if let title = list.title {
                let font = NoteTheme.menuHeaderFont()
                let height = ceil(font.ascender - font.descender)
                NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NoteTheme.menuTertiaryInk])
                    .draw(at: NSPoint(x: list.inset + 10, y: list.inset + (NoteTheme.menuHeaderHeight - height) / 2))
            }
            for index in list.items.indices {
                let frame = list.rowFrame(index)
                guard frame.intersects(dirtyRect) else { continue }
                list.drawRow(index, in: frame)
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    private func pointerCursor(for event: NSEvent) -> NSCursor {
        guard let list else { return .arrow }
        let point = convert(event.locationInWindow, from: nil)
        return list.items.indices.contains { list.rowFrame($0).contains(point) } ? .pointingHand : .arrow
    }

    override func cursorUpdate(with event: NSEvent) {
        if !applyNoteCursor(pointerCursor(for: event), for: event) { super.cursorUpdate(with: event) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func hover(_ event: NSEvent) {
        guard let list else { return }
        let point = convert(event.locationInWindow, from: nil)
        let allowed = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        list.setHighlight(allowed ? list.index(at: point) : nil, animated: true)
        if allowed { applyNoteCursor(pointerCursor(for: event), for: event) }
    }

    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseMoved(with event: NSEvent) { hover(event) }

    override func mouseExited(with event: NSEvent) {
        guard let list, list.style == .inline else { return }
        list.setHighlight(nil, animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard let list, let index = list.index(at: convert(event.locationInWindow, from: nil)) else { return }
        list.setHighlight(index, animated: true)
        list.press(index)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let list else { return }
        let index = list.index(at: convert(event.locationInWindow, from: nil))
        list.press(index == list.highlighted ? index : nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard let list else { return }
        let index = list.index(at: convert(event.locationInWindow, from: nil))
        let wasPressed = list.highlighted
        list.press(nil)
        if let index, index == wasPressed { list.open(index) }
    }

    func refreshAccessibility() {
        guard let list else { return }
        elements = list.items.indices.map { index in
            let item = list.items[index]
            let element = NoteBacklinkAccessibilityRow(index: index, owner: self)
            element.setAccessibilityRole(.link)
            element.setAccessibilityLabel((item.title.isEmpty ? "Untitled" : item.title) + ", " + item.snippet.text)
            element.setAccessibilityParent(self)
            return element
        }
    }

    func accessibilityFrame(forRow index: Int) -> NSRect {
        guard let list else { return .zero }
        return list.rowFrame(index)
    }

    func performPress(row index: Int) -> Bool {
        guard let list, list.items.indices.contains(index) else { return false }
        list.open(index)
        return true
    }

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { elements }
}

@MainActor
final class NoteBacklinkAccessibilityRow: NSAccessibilityElement {
    let index: Int
    weak var owner: NoteBacklinksRowsView?

    init(index: Int, owner: NoteBacklinksRowsView) {
        self.index = index
        self.owner = owner
        super.init()
    }

    override func accessibilityFrameInParentSpace() -> NSRect {
        owner?.accessibilityFrame(forRow: index) ?? .zero
    }

    override func accessibilityPerformPress() -> Bool {
        owner?.performPress(row: index) ?? false
    }
}

@MainActor
final class NotePageBacklinksView: NSView {
    static let gutter: CGFloat = 8
    static let collapsedLimit = 6

    var onOpen: ((URL) -> Void)?
    var onHeightChange: (() -> Void)?
    var overlayHost: (() -> NSView?)?
    private(set) var items: [NoteBacklink] = []
    private(set) var display: NoteBacklinksDisplay = .popup
    let chip = NoteChip("", icon: .symbol("arrow.turn.up.left"), style: .ghost)
    let list = NoteBacklinksListView(style: .inline)
    let more = NoteChip("", icon: .symbol("chevron.down"), style: .ghost)
    private var showsAll = false
    private var popover: NotePagePopover?
    private weak var popoverList: NoteBacklinksListView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Backlinks")
        chip.onPress = { [weak self] in self?.chipPressed() }
        more.onPress = { [weak self] in self?.toggleAll() }
        list.onOpen = { [weak self] item in self?.onOpen?(item.destination) }
        addSubview(list)
        addSubview(chip)
        addSubview(more)
        refreshFaces()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var isShowing: Bool { display != .off && !items.isEmpty }

    private var shownRows: Int {
        guard display == .expanded else { return 0 }
        return showsAll || items.count <= Self.collapsedLimit + 1 ? items.count : Self.collapsedLimit
    }

    private var showsMore: Bool { display == .expanded && items.count > Self.collapsedLimit + 1 }

    var preferredHeight: CGFloat {
        guard isShowing else { return 0 }
        var height = NoteTheme.chipHeight
        if display == .expanded {
            height += 2 + CGFloat(shownRows) * NoteBacklinksListView.rowHeight
            if showsMore { height += NoteTheme.chipHeight }
        }
        return height
    }

    func update(_ next: [NoteBacklink], display nextDisplay: NoteBacklinksDisplay) {
        let wasShowing = isShowing
        let previousCount = items.count
        let heightBefore = preferredHeight
        items = next
        display = nextDisplay
        if items.count <= Self.collapsedLimit + 1 { showsAll = false }
        refreshFaces()
        if display != .popup || items.isEmpty { popover?.close() }
        popoverList?.items = items
        popoverList?.title = NoteBacklinksListView.countLabel(items.count)
        if isShowing, !wasShowing, window != nil {
            NoteAnimation.insert(self)
        } else if isShowing, previousCount != items.count, previousCount > 0, let layer = chip.layer, window != nil {
            NoteAnimation.pop(layer, from: 0.96, spring: .pill, about: CGPoint(x: chip.bounds.midX, y: chip.bounds.midY))
        }
        needsLayout = true
        if preferredHeight != heightBefore || wasShowing != isShowing { onHeightChange?() }
    }

    private func refreshFaces() {
        let label = NoteBacklinksListView.countLabel(items.count)
        chip.chipTitle = label
        chip.setToolTip(display == .expanded ? label : "Show the notes that link here")
        chip.setAccessibilityLabel(label)
        list.items = Array(items.prefix(shownRows))
        list.isHidden = display != .expanded
        more.isHidden = !showsMore
        more.chipTitle = showsAll ? "Show fewer" : "Show \(items.count - Self.collapsedLimit) more"
        more.icon = .symbol(showsAll ? "chevron.up" : "chevron.down")
        isHidden = !isShowing
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            let size = chip.intrinsicContentSize
            chip.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
            let rowsHeight = CGFloat(shownRows) * NoteBacklinksListView.rowHeight
            list.frame = NSRect(x: 0, y: NoteTheme.chipHeight + 2, width: bounds.width, height: rowsHeight)
            let moreSize = more.intrinsicContentSize
            more.frame = NSRect(x: 0, y: list.frame.maxY, width: moreSize.width, height: moreSize.height)
        }
    }

    private func chipPressed() {
        guard display == .popup else { return }
        if let popover, popover.isOpen {
            popover.close()
            return
        }
        guard let overlay = overlayHost?(), !items.isEmpty else { return }
        let content = NoteBacklinksListView(style: .menu)
        content.title = NoteBacklinksListView.countLabel(items.count)
        content.items = items
        let popover = NotePagePopover(content: content)
        content.onOpen = { [weak self, weak popover] item in
            popover?.close()
            self?.onOpen?(item.destination)
        }
        content.preferredSizeDidChange = { [weak popover] in popover?.panel.contentSizeDidChange() }
        popover.exempt(chip)
        popover.onKeyDown = { [weak content] event in content?.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self] in
            self?.popover = nil
            self?.chip.isChecked = false
        }
        self.popover = popover
        popoverList = content
        chip.isChecked = true
        popover.present(in: overlay, anchor: overlay.convert(chip.bounds, from: chip), edge: .below)
        if NSApp.currentEvent?.type == .keyDown { content.moveHighlight(by: 1) }
    }

    func closePopover(animated: Bool = true) {
        popover?.close(animated: animated)
    }

    private func toggleAll() {
        showsAll.toggle()
        refreshFaces()
        needsLayout = true
        onHeightChange?()
    }

    override func accessibilityChildren() -> [Any]? {
        display == .expanded ? [chip, list] + (more.isHidden ? [] : [more]) : [chip]
    }
}
