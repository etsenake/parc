import AppKit
import ParcCore

enum SpaceManagerReloadSkip {
    static func shouldSkip(previous: BrowserState?, next: BrowserState) -> Bool {
        guard let previous else { return false }
        return catalogMatches(next, previous)
    }

    static func catalogMatches(_ current: BrowserState, _ previous: BrowserState) -> Bool {
        current.profiles == previous.profiles
            && current.spaces == previous.spaces
            && current.folders == previous.folders
            && current.splitLayouts == previous.splitLayouts
            && current.sidebarItemOrder == previous.sidebarItemOrder
            && current.activeSpaceID == previous.activeSpaceID
            && current.selectedTabIDs == previous.selectedTabIDs
            && current.selectionBySpace == previous.selectionBySpace
            && current.settings == previous.settings
            && current.profileRemovals == previous.profileRemovals
            && tabsMatch(current.tabs, previous.tabs)
    }

    private static func tabsMatch(_ current: [BrowserTab], _ previous: [BrowserTab]) -> Bool {
        current.count == previous.count
            && zip(current, previous).allSatisfy { tab, prior in
                tab.id == prior.id
                    && tab.spaceID == prior.spaceID
                    && tab.profileID == prior.profileID
                    && tab.kind == prior.kind
                    && tab.folderID == prior.folderID
                    && tab.archivedAt == prior.archivedAt
                    && tab.customTitle == prior.customTitle
                    && tab.isMuted == prior.isMuted
                    && tab.isUnread == prior.isUnread
                    && tab.archiveProvenance == prior.archiveProvenance
                    && tab.referrerID == prior.referrerID
                    && tab.activeTabBeforeCreationID == prior.activeTabBeforeCreationID
                    && InternalPage(urlString: tab.url) == InternalPage(urlString: prior.url)
                    && isBlankPage(tab.url) == isBlankPage(prior.url)
            }
    }

    private static func isBlankPage(_ url: String) -> Bool {
        url.isEmpty || url == "about:blank"
    }
}

enum SpaceClearToday {
    static func ids(in state: BrowserState, spaceID: UUID, profileID: UUID) -> Set<UUID> {
        Set(state.openTabs(where: { $0.kind == .today && $0.spaceID == spaceID && $0.profileID == profileID }).map(\.id))
    }
}

enum SpaceManagementLayout {
    static let cardWidth: CGFloat = 240
    static let gap: CGFloat = 24
    static let verticalInset: CGFloat = 48
    static let horizontalInset: CGFloat = 24
    static let addItemSide: CGFloat = 48
    static let addCircleSide: CGFloat = 30

    static func cardFrame(index: Int, height: CGFloat) -> NSRect {
        NSRect(x: horizontalInset + CGFloat(index) * (cardWidth + gap), y: verticalInset,
               width: cardWidth, height: max(0, height - 2 * verticalInset))
    }
    static func addItemFrame(count: Int, height: CGFloat) -> NSRect {
        NSRect(x: horizontalInset + CGFloat(count) * (cardWidth + gap), y: (height - addItemSide) / 2,
               width: addItemSide, height: addItemSide)
    }
    static func addCircleFrame(count: Int, height: CGFloat) -> NSRect {
        let item = addItemFrame(count: count, height: height)
        return item.insetBy(dx: (addItemSide - addCircleSide) / 2, dy: (addItemSide - addCircleSide) / 2)
    }
    static func contentWidth(count: Int) -> CGFloat {
        addItemFrame(count: count, height: 0).maxX + horizontalInset
    }
    static func libraryWidth(count: Int) -> CGFloat {
        3 * (2 * horizontalInset) + CGFloat(count) * (cardWidth + gap) + addItemSide + gap
    }
    static let pageInset: CGFloat = 4

    static let controlsHeight: CGFloat = 34
    static func sidebarFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: 0, y: 5, width: bounds.width, height: max(0, bounds.height - controlsHeight - 15))
    }
    static func controlsFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: 0, y: max(0, bounds.height - controlsHeight - 5), width: bounds.width, height: controlsHeight)
    }
    static let cornerRadius: CGFloat = 12
}

@MainActor final class SpaceManagerView: NSView, LibrarySpacesPage {
    static let dragType = NSPasteboard.PasteboardType("org.parc.space-manager")
    var configureSidebar: ((UUID, SidebarView) -> Void)? {
        didSet { for (id, card) in cards { configureSidebar?(id, card.sidebar) } }
    }
    var makeMenu: ((UUID, NSView) -> NSMenu?)?
    var onCreate: (() -> Void)?
    var onClose: (() -> Void)?
    var onReorder: ((UUID, UUID?, [UUID]) -> Bool)?
    var ownerValid: () -> Bool = { false }
    var windowSpaceID: () -> UUID? = { nil }
    private var addTheme: SpaceTheme?
    private let scroll = NSScrollView()
    private let content = LayoutView()
    private let add = SpaceManagementAddButton()
    private var cards: [UUID: SpaceManagementCard] = [:]
    private var order: [UUID] = []
    private var dragging: (UUID, [UUID])?
    private var lastAppliedState: BrowserState?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.group); setAccessibilityLabel("Spaces")
        scroll.documentView = content; scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        addSubview(scroll); content.addSubview(add)
        LiveShortcutToolTip.set(add, "Create a Space"); add.setAccessibilityLabel("Create a Space")
        add.actionBlock = { [weak self] in guard let self, self.ownerValid() else { return }; self.onCreate?() }
        registerForDraggedTypes([Self.dragType])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func cancelEditing() { for card in cards.values { card.sidebar.cancelSpaceNameEditing() } }
    func previewTheme(_ theme: SpaceTheme, spaceID: UUID) {
        cards[spaceID]?.theme.theme = theme
        lastAppliedState = nil
    }
    func sidebar(for id: UUID) -> SidebarView? { cards[id]?.sidebar }
    func anchor(for id: UUID) -> NSView? { cards[id]?.appearanceAnchor }
    func reload(_ state: BrowserState) {
        let windowSpace = windowSpaceID().flatMap { id in state.spaces.first { $0.id == id } } ?? state.spaces.first
        if addTheme != windowSpace?.theme { addTheme = windowSpace?.theme; updateAddPalette() }
        if SpaceManagerReloadSkip.shouldSkip(previous: lastAppliedState, next: state) { return }
        lastAppliedState = state
        let next = state.spaces.map(\.id)
        for id in Set(cards.keys).subtracting(next) {
            cards[id]?.sidebar.cancelSpaceNameEditing()
            cards.removeValue(forKey: id)?.removeFromSuperview()
        }
        order = next
        for space in state.spaces {
            let card: SpaceManagementCard
            if let retained = cards[space.id] { card = retained }
            else {
                card = SpaceManagementCard(id: space.id)
                cards[space.id] = card; content.addSubview(card)
                configureSidebar?(space.id, card.sidebar)
                card.menuProvider = { [weak self, weak card] in
                    guard let self, let card, self.ownerValid() else { return nil }
                    let menu = self.makeMenu?(space.id, card) ?? NSMenu()
                    menu.addItem(.separator())
                    for (title, step) in [("Move Space Left", -1), ("Move Space Right", 1)] {
                        let expected = self.order, destination = self.destination(space.id, by: step)
                        let reduced = expected.filter { $0 != space.id }
                        let before = destination.flatMap { $0 < reduced.count ? reduced[$0] : nil }
                        let item = MenuAction.item(title) { [weak self] in
                            guard let self, self.ownerValid(), destination != nil else { return }
                            if self.onReorder?(space.id, before, expected) != true { NSSound.beep() }
                        }
                        item.isEnabled = destination != nil
                        menu.addItem(item)
                    }
                    return menu
                }
                card.move = { [weak self] in self?.move(space.id, by: $0) ?? false }
                card.beginDrag = { [weak self] in
                    guard let self, self.ownerValid(), self.order.contains(space.id) else { return false }
                    self.dragging = (space.id, self.order); return true
                }
                card.endDrag = { [weak self] in self?.dragging = nil }
            }
            card.setAccessibilityLabel(space.name)
            card.theme.theme = space.theme
            var presented = state; presented.activeSpaceID = space.id
            presented.selectedTabIDs = []
            card.sidebar.render(state: presented, focusedTabID: nil, loading: [], canBack: false, canForward: false)
            card.sidebar.palette = card.theme.palette
            card.applyPalette()
        }
        needsLayout = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updateAddPalette()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); updateAddPalette()
    }
    private func updateAddPalette() {
        add.palette = addTheme.map { ThemeChromePalette(theme: $0, appearance: window?.effectiveAppearance ?? effectiveAppearance) }
    }
    override func cancelOperation(_ sender: Any?) { onClose?() }
    func focusFirst() { window?.makeFirstResponder(order.first.flatMap { cards[$0] } ?? add) }
    private func destination(_ id: UUID, by delta: Int) -> Int? {
        guard let index = order.firstIndex(of: id), order.indices.contains(index + delta) else { return nil }
        return index + delta
    }
    @discardableResult private func move(_ id: UUID, by delta: Int) -> Bool {
        guard ownerValid(), let index = destination(id, by: delta) else { return false }
        let reduced = order.filter { $0 != id }, before = index < reduced.count ? reduced[index] : nil
        return onReorder?(id, before, order) ?? false
    }
    override func layout() {
        super.layout(); scroll.frame = bounds
        typealias Layout = SpaceManagementLayout
        let height = max(180 + 2 * Layout.verticalInset, scroll.contentSize.height)
        content.frame = NSRect(x: 0, y: 0, width: max(scroll.contentSize.width, Layout.contentWidth(count: order.count)), height: height)
        for (index, id) in order.enumerated() {
            cards[id]?.frame = Layout.cardFrame(index: index, height: height)
            let next: NSView = index + 1 < order.count ? cards[order[index + 1]]! : add
            cards[id]?.followingKeyView = next
        }
        add.frame = Layout.addCircleFrame(count: order.count, height: height)
    }
    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard ownerValid(), let (id, expected) = dragging, expected == order,
              let source = sender.draggingSource as? SpaceManagementCard, cards[id] === source,
              sender.draggingPasteboard.string(forType: Self.dragType) == id.uuidString else { return false }
        return true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .move : [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .move : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard accepts(sender), let (id, expected) = dragging else { return false }
        let point = content.convert(sender.draggingLocation, from: nil)
        let others = order.filter { $0 != id }
        let before = others.first { cards[$0].map { point.x < $0.frame.midX } ?? false }
        return onReorder?(id, before, expected) ?? false
    }
}

@MainActor private final class SpaceManagementCard: NSView, NSDraggingSource {
    let id: UUID
    private let base = SpaceManagementCardBase()
    let theme = ThemeRendererView(frame: .zero)
    let sidebar = SidebarView(frame: .zero)
    private let more = SpaceManagementMoreButton()
    private let grip = SpaceManagementGrip(frame: .zero)
    var appearanceAnchor: NSView {
        if let anchor = sidebar.spaceAppearanceAnchor(id), anchor !== sidebar, !anchor.isHiddenOrHasHiddenAncestor { return anchor }
        return more
    }
    var followingKeyView: NSView? {
        didSet { nextKeyView = sidebar; sidebar.keyViewExit = more; more.nextKeyView = followingKeyView }
    }
    var menuProvider: (() -> NSMenu?)?
    var move: ((Int) -> Bool)?
    var beginDrag: (() -> Bool)?
    var endDrag: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(id: UUID) {
        self.id = id; super.init(frame: .zero)
        setAccessibilityRole(.group)
        theme.wantsLayer = true; theme.drawsMaterial = false
        theme.layer?.cornerRadius = SpaceManagementLayout.cornerRadius; theme.layer?.masksToBounds = true
        sidebar.isSpaceManagement = true
        addSubview(base); addSubview(theme); theme.addSubview(sidebar); addSubview(more); addSubview(grip)
        theme.onPaletteChange = { [weak self] in self?.sidebar.palette = $0; self?.applyPalette() }
        LiveShortcutToolTip.set(more, "More options"); more.setAccessibilityLabel("Space Options")
        more.actionBlock = { [weak self] in
            guard let self else { return }
            self.menuProvider?()?.popUp(positioning: nil, at: NSPoint(x: 0, y: self.more.bounds.maxY), in: self.more)
        }
        grip.setAccessibilityElement(false)
        grip.beginDrag = { [weak self] event in self?.startDrag(event) }
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Move Space Left") { [weak self] in self?.move?(-1) ?? false },
            NSAccessibilityCustomAction(name: "Move Space Right") { [weak self] in self?.move?(1) ?? false },
            NSAccessibilityCustomAction(name: "Space Options") { [weak self] in
                guard let self, let menu = self.menuProvider?() else { return false }
                menu.popUp(positioning: nil, at: .zero, in: self.more); return true
            }
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func applyPalette() {
        let dark = theme.surfaceStyle.backgroundIsDark
        base.dark = dark; grip.dark = dark; more.dark = dark
    }
    override func layout() {
        super.layout()
        typealias Layout = SpaceManagementLayout
        base.frame = bounds; theme.frame = bounds
        sidebar.frame = Layout.sidebarFrame(in: theme.bounds)
        let controls = Layout.controlsFrame(in: bounds), side: CGFloat = 28
        grip.frame = NSRect(x: controls.minX + 8, y: controls.midY - side / 2, width: side, height: side)
        more.frame = NSRect(x: controls.maxX - 8 - side, y: controls.midY - side / 2, width: side, height: side)
    }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == [.command, .option], event.keyCode == 123 || event.keyCode == 124 {
            if move?(event.keyCode == 123 ? -1 : 1) != true { NSSound.beep() }; return
        }
        if event.keyCode == 36 || event.keyCode == 49 { window?.makeFirstResponder(sidebar); return }
        super.keyDown(with: event)
    }
    private func startDrag(_ event: NSEvent) {
        guard beginDrag?() == true else { return }
        let item = NSPasteboardItem(); item.setString(id.uuidString, forType: SpaceManagerView.dragType)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) { cacheDisplay(in: bounds, to: rep); image.addRepresentation(rep) }
        dragging.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { endDrag?() }
}

@MainActor private final class SpaceManagementCardBase: NSView {
    var dark = false { didSet { if dark != oldValue { updateColors() } } }
    private let backgroundLayer = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        backgroundLayer.shadowColor = NSColor.black.cgColor; backgroundLayer.shadowOpacity = 0.15
        backgroundLayer.shadowRadius = 12; backgroundLayer.shadowOffset = CGSize(width: 0, height: 1)
        layer?.addSublayer(backgroundLayer)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        let radius = SpaceManagementLayout.cornerRadius
        let path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        backgroundLayer.frame = bounds; backgroundLayer.path = path; backgroundLayer.shadowPath = path
        CATransaction.commit()
    }
    private func updateColors() {
        backgroundLayer.fillColor = (dark ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
                                          : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)).cgColor
    }
}

@MainActor private enum SpaceManagementControlStyle {
    static func draw(_ glyph: UInt32, in bounds: NSRect, dark: Bool, hovered: Bool, pressed: Bool) {
        if hovered || pressed {
            SidebarRowAppearance.controlFill(pressed: pressed, dark: dark).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let image = SidebarIconCatalog.featherImage(glyph, size: 16)
        let rect = NSRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16)
        NSImage(size: rect.size, flipped: false) { frame in
            image.draw(in: frame)
            SidebarIconCatalog.foregroundSecondary(dark: dark).setFill(); frame.fill(using: .sourceIn)
            return true
        }.draw(in: rect)
    }
}

@MainActor private final class SpaceManagementGrip: NSView {
    var beginDrag: ((NSEvent) -> Void)?
    var dark = false { didSet { if dark != oldValue { needsDisplay = true } } }
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        LiveShortcutToolTip.set(self, "Drag to Reorder Space")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func mouseDragged(with event: NSEvent) { beginDrag?(event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = isTopmost(atWindowPoint: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        hovered = isTopmost(atWindowPoint: event.locationInWindow)
    }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hovered = false }
        super.viewWillMove(toWindow: newWindow)
    }
    override func draw(_ dirtyRect: NSRect) {
        SpaceManagementControlStyle.draw(0xE9A7, in: bounds, dark: dark, hovered: hovered, pressed: false)
    }
}

@MainActor private final class SpaceManagementMoreButton: PointingHandButton {
    var actionBlock: (() -> Void)?
    var dark = false { didSet { if dark != oldValue { needsDisplay = true } } }
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?
    init() {
        super.init(frame: .zero)
        isBordered = false; title = ""; focusRingType = .exterior
        target = self; action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { actionBlock?() }
    override var isHighlighted: Bool { didSet { if isHighlighted != oldValue { needsDisplay = true } } }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = isEnabled && isTopmost(atWindowPoint: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        hovered = isEnabled && isTopmost(atWindowPoint: event.locationInWindow)
    }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hovered = false }
        super.viewWillMove(toWindow: newWindow)
    }
    override func draw(_ dirtyRect: NSRect) {
        SpaceManagementControlStyle.draw(0xE9A4, in: bounds, dark: dark, hovered: hovered, pressed: isHighlighted && isEnabled)
    }
}

@MainActor private final class SpaceManagementAddButton: PointingHandButton {
    var palette: ThemeChromePalette? { didSet { updateColors() } }
    var actionBlock: (() -> Void)?
    private let circle = CAShapeLayer()
    private let glyph = CALayer()
    private let symbol = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Space")?
        .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
    init() {
        super.init(frame: .zero)
        isBordered = false; title = ""; focusRingType = .exterior
        target = self; action = #selector(invoke)
        wantsLayer = true
        circle.shadowColor = NSColor.black.cgColor; circle.shadowOpacity = 0.3
        circle.shadowRadius = 1.5; circle.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(circle); layer?.addSublayer(glyph)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { actionBlock?() }
    override func layout() {
        super.layout()
        let size = symbol?.size ?? .zero
        CATransaction.begin(); CATransaction.setDisableActions(true)
        circle.frame = bounds; circle.path = CGPath(ellipseIn: bounds, transform: nil); circle.shadowPath = circle.path
        glyph.frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
                             width: size.width, height: size.height)
        CATransaction.commit()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties(); updateColors()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(ovalIn: bounds).fill() }
    private func updateColors() {
        let tint = palette?.maxContrastColor ?? .labelColor, fill = palette?.cutoutColor ?? .white
        let scale = window?.backingScaleFactor ?? 2
        var fillColor: CGColor?, contents: CGImage?
        (palette?.contentAppearance ?? effectiveAppearance).performAsCurrentDrawingAppearance {
            fillColor = fill.cgColor
            guard let symbol else { return }
            let tinted = NSImage(size: symbol.size, flipped: false) { frame in
                symbol.draw(in: frame)
                tint.setFill(); frame.fill(using: .sourceIn)
                return true
            }
            contents = tinted.cgImage(forProposedRect: nil, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        circle.fillColor = fillColor
        glyph.contentsScale = scale; glyph.contents = contents
        CATransaction.commit()
    }
}
