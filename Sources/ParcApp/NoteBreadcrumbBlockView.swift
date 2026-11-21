import AppKit
import Combine
import ParcCore

@MainActor
enum NoteBreadcrumbCache {
    private struct Key: Hashable {
        var document: String
        var notes: String?
    }

    private static var trails: [Key: [NoteBreadcrumbSegment]] = [:]

    static func trail(for document: URL, notesFolder: URL?) -> [NoteBreadcrumbSegment] {
        let key = Key(document: document.standardizedFileURL.path, notes: notesFolder?.standardizedFileURL.path)
        if let hit = trails[key] { return hit }
        if trails.count >= 64 { trails.removeAll() }
        let trail = NoteBreadcrumb.trail(for: document, places: .system(notesFolder: notesFolder))
        trails[key] = trail
        return trail
    }

    static func icon(for segment: NoteBreadcrumbSegment) -> NoteIcon {
        switch segment.kind {
        case .notes: return .symbol("note.text")
        case .home: return .symbol("house")
        case .volume: return .symbol(segment.url.path.hasPrefix("/Volumes/") ? "externaldrive" : "internaldrive")
        case .folder: return .symbol("folder")
        case .note: return .symbol("doc.text")
        }
    }
}

@MainActor
final class NoteBreadcrumbBlockView: NoteBlockView {
    static let verticalPadding: CGFloat = 3
    static let rowGap: CGFloat = 2
    static let separatorWidth: CGFloat = 16
    static let unsavedText = "Save this note somewhere to see its path"

    private(set) var trail: [NoteBreadcrumbSegment] = []
    private var pageIcon: String?
    private var pageImage: NSImage?
    private var items: [NoteBreadcrumbItemView] = []
    private var separatorFrames: [NSRect] = []
    private var subscriptions: Set<AnyCancellable> = []

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Breadcrumb")
        if let editor {
            editor.session.changes.sink { [weak self] change in
                guard change.kind != .selection, change.kind != .text else { return }
                self?.reload()
            }.store(in: &subscriptions)
            NoteFileSession.openSessions.first { $0.page === editor.session }?.urlChanges
                .sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
            NoteFolderPreferences.changes.sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        }
        reload(force: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var settings: NotePageSettings { editor?.session.page.settings ?? NotePageSettings() }

    private var font: NSFont {
        let settings = settings
        let base = NoteTheme.bodyFont(settings.font, small: true)
        return settings.smallText ? (NSFont(descriptor: base.fontDescriptor, size: base.pointSize - 1.5) ?? base) : base
    }

    private var rowHeight: CGFloat { (font.pointSize * 1.45).rounded() + 6 }

    private var textColor: NSColor? {
        guard let color = block.color, !color.isBackground else { return nil }
        return NoteTheme.color(color)
    }

    private var shownTrail: [NoteBreadcrumbSegment] {
        guard trail.isEmpty else { return trail }
        return [NoteBreadcrumbSegment(kind: .note, name: Self.unsavedText, url: URL(fileURLWithPath: "/", isDirectory: true))]
    }

    func reload(force: Bool = false) {
        let next = editor?.breadcrumbTrail ?? []
        let icon = settings.icon
        guard force || next != trail || icon != pageIcon else { return }
        let resized = force || next != trail
        trail = next
        if icon != pageIcon { pageImage = nil }
        pageIcon = icon
        loadPageImage()
        rebuildItems()
        needsLayout = true
        needsDisplay = true
        if resized, window != nil { editor?.canvas.blockHeightDidChange(blockID) }
    }

    private func loadPageImage() {
        guard pageImage == nil, let icon = pageIcon, NotePageImageLoader.isImageSource(icon),
              let url = editor?.environment.resolve(icon) else { return }
        if let cached = NotePageImageLoader.shared.cached(url) { pageImage = cached; return }
        NotePageImageLoader.shared.load(url) { [weak self] image in
            guard let self, self.pageIcon == icon, let image else { return }
            self.pageImage = image
            self.restyleItems()
        }
    }

    private func rebuildItems() {
        let shown = shownTrail
        while items.count > shown.count { items.removeLast().removeFromSuperview() }
        while items.count < shown.count {
            let item = NoteBreadcrumbItemView()
            item.onActivate = { [weak self, weak item] in
                guard let self, let segment = item?.segment, segment.isFolder else { return }
                self.editor?.openFolder(segment.url)
            }
            items.append(item)
            addSubview(item)
        }
        restyleItems()
        setAccessibilityChildren(items)
    }

    private func restyleItems() {
        let font = font
        let custom = textColor
        let unsaved = trail.isEmpty
        for (item, segment) in zip(items, shownTrail) {
            var icon = NoteBreadcrumbCache.icon(for: segment)
            var image: NSImage?
            let ink: NSColor
            if unsaved {
                icon = .symbol("signpost.right")
                ink = NoteTheme.placeholderInk
            } else if segment.kind == .note {
                if let pageIcon, !pageIcon.isEmpty {
                    if NotePageImageLoader.isImageSource(pageIcon) { image = pageImage } else { icon = .emoji(pageIcon) }
                }
                ink = custom ?? NoteTheme.ink
            } else {
                ink = custom ?? NoteTheme.secondaryInk
            }
            item.configure(segment, icon: icon, image: image, font: font, ink: ink, interactive: segment.isFolder && !unsaved)
        }
        needsDisplay = true
    }

    private func frames(width: CGFloat) -> (items: [NSRect], separators: [NSRect], height: CGFloat) {
        let font = font, row = rowHeight
        let available = max(NoteBreadcrumbItemView.minimumWidth, width)
        let shown = shownTrail
        var itemFrames: [NSRect] = [], separators: [NSRect] = []
        var x: CGFloat = 0, y = Self.verticalPadding
        for (index, segment) in shown.enumerated() {
            let last = index == shown.count - 1
            let natural = NoteBreadcrumbItemView.width(of: segment.name, font: font)
            let itemWidth = min(natural, available - (last ? 0 : Self.separatorWidth))
            if x > 0, x + itemWidth + (last ? 0 : Self.separatorWidth) > available {
                x = 0
                y += row + Self.rowGap
            }
            itemFrames.append(NSRect(x: x, y: y, width: itemWidth, height: row))
            x += itemWidth
            if !last {
                separators.append(NSRect(x: x, y: y, width: Self.separatorWidth, height: row))
                x += Self.separatorWidth
            }
        }
        return (itemFrames, separators, y + row + Self.verticalPadding)
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        if editor != nil, window == nil { reload() }
        return frames(width: width).height
    }

    override var handleAnchorY: CGFloat { Self.verticalPadding + rowHeight / 2 }

    override func layout() {
        super.layout()
        let laid = frames(width: bounds.width)
        NoteAnimation.withoutAnimation {
            for (item, frame) in zip(items, laid.items) { item.frame = frame }
        }
        separatorFrames = laid.separators
        needsDisplay = true
    }

    override func update(_ block: NoteBlock) {
        super.update(block)
        restyleItems()
    }

    override func themeDidChange() {
        super.themeDidChange()
        restyleItems()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyleItems()
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let color = block.color, color.isBackground {
                NoteTheme.color(color).setFill()
                NSBezierPath(roundedRect: bounds, xRadius: NoteTheme.blockRadius, yRadius: NoteTheme.blockRadius).fill()
            }
            let font = font
            let ink = (textColor ?? NoteTheme.tertiaryInk).withAlphaComponent(textColor == nil ? 1 : 0.55)
            let mark = NSAttributedString(string: NoteBreadcrumb.separator, attributes: [.font: font, .foregroundColor: ink])
            let size = mark.size()
            for frame in separatorFrames {
                mark.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        NoteBlockPointer.selectBlock(self, with: event)
    }
}

@MainActor
final class NoteBreadcrumbItemView: NSView {
    static let padding: CGFloat = 6
    static let iconSide: CGFloat = 16
    static let iconGap: CGFloat = 5
    static let minimumWidth: CGFloat = 72

    private(set) var segment: NoteBreadcrumbSegment?
    var onActivate: (() -> Void)?
    private var isInteractive = false
    private let fill = CALayer()
    private let content = NoteBreadcrumbItemContent()
    private var isHovered = false
    private var isPressed = false
    private var tracking: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        fill.cornerRadius = NoteTheme.controlRadius
        fill.cornerCurve = .continuous
        fill.opacity = 0
        layer?.addSublayer(fill)
        addSubview(content)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    static func width(of name: String, font: NSFont) -> CGFloat {
        padding * 2 + iconSide + iconGap + ceil(NSAttributedString(string: name, attributes: [.font: font]).size().width)
    }

    func configure(_ segment: NoteBreadcrumbSegment, icon: NoteIcon, image: NSImage?, font: NSFont, ink: NSColor, interactive: Bool) {
        let changedRole = interactive != isInteractive || self.segment != segment
        self.segment = segment
        isInteractive = interactive
        content.show(name: segment.name, icon: icon, image: image, font: font, ink: ink)
        if changedRole {
            setAccessibilityRole(interactive ? .link : .staticText)
            setAccessibilityLabel(segment.name)
            setAccessibilityHelp(interactive ? "Shows this folder in the Notes Library" : nil)
            if interactive {
                LiveShortcutToolTip.set(self, (segment.url.path as NSString).abbreviatingWithTildeInPath)
            } else {
                parcTooltip = nil
                setHovered(false)
            }
            refreshPointingHand(interactive)
        }
        refreshFill()
    }

    override func layout() {
        super.layout()
        content.frame = bounds
        NoteAnimation.withoutAnimation { fill.frame = bounds }
    }

    private func refreshFill() {
        NoteAnimation.withoutAnimation {
            fill.backgroundColor = NoteMediaStyle.cg(isPressed ? NoteTheme.pressedFill : NoteTheme.hoverFill, in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) {
        if !applyNoteCursor(isInteractive ? .pointingHand : .arrow, for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseEntered(with event: NSEvent) { setHovered(isInteractive && NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }

    override func mouseMoved(with event: NSEvent) { setHovered(isInteractive && NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }

    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        guard value != isHovered else { return }
        isHovered = value
        NoteAnimation.fade(fill, to: value ? 1 : 0, duration: NoteAnimation.hoverDuration)
    }

    private func setPressed(_ value: Bool) {
        guard value != isPressed else { return }
        isPressed = value
        refreshFill()
        guard let layer else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let target = value ? NoteAnimation.scaleTransform(NoteAnimation.pressedScale, about: center) : CATransform3DIdentity
        NoteAnimation.spring(layer, "transform", to: NSValue(caTransform3D: target), spring: .press, key: NoteAnimation.keyPrefix + "press")
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { super.mouseDown(with: event); return }
        setPressed(true)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            setPressed(inside)
            if next.type == .leftMouseUp {
                setPressed(false)
                if inside { onActivate?() }
                return
            }
        }
        setPressed(false)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isInteractive else { return false }
        onActivate?()
        return true
    }
}

@MainActor
final class NoteBreadcrumbItemContent: NSView {
    private var name = ""
    private var icon: NoteIcon = .symbol("folder")
    private var image: NSImage?
    private var font = NSFont.systemFont(ofSize: 15)
    private var ink = NSColor.secondaryLabelColor

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(name: String, icon: NoteIcon, image: NSImage?, font: NSFont, ink: NSColor) {
        self.name = name
        self.icon = icon
        self.image = image
        self.font = font
        self.ink = ink
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let side = NoteBreadcrumbItemView.iconSide
            let iconRect = NSRect(x: NoteBreadcrumbItemView.padding, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
            if let image, image.size.width > 0, image.size.height > 0 {
                let scale = min(iconRect.width / image.size.width, iconRect.height / image.size.height)
                let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                let rect = NSRect(x: iconRect.midX - size.width / 2, y: iconRect.midY - size.height / 2, width: size.width, height: size.height)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).addClip()
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.high])
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NoteIconRenderer.draw(icon, in: iconRect, tint: ink, pointSize: 12.5, weight: .medium)
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            let text = NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
            let height = ceil(font.ascender - font.descender + font.leading)
            let left = iconRect.maxX + NoteBreadcrumbItemView.iconGap
            text.draw(with: NSRect(x: left, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - left - NoteBreadcrumbItemView.padding),
                                   height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}
