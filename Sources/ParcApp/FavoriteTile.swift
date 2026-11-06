import AppKit
import CoreImage
import QuartzCore

enum FavoritePointerAction: Hashable {
    case activate, resetAndSelect, resetIfNeeded, openInSplit
}

///
/// has no multi-selection of its own: Shift and Command never build a set, and
/// the outline's ordered multi-set reconciles to outline rows, so a Favorite is
/// never a member here and its deferred member branch does not arise.
enum FavoritePointerPolicy {
    ///
    /// without Option. Every other first click is resolved by its release.
    static func selectsOnDown(modifiers: NSEvent.ModifierFlags, isKey: Bool) -> Bool {
        isKey && !modifiers.contains(.option)
    }

    static func mouseUp(modifiers: NSEvent.ModifierFlags, clickCount: Int,
                        isKey: Bool) -> FavoritePointerAction? {
        guard clickCount == 1, !selectsOnDown(modifiers: modifiers, isKey: isKey) else { return nil }
        // Release drops numeric-pad/Caps Lock/help/function before comparing.
        let flags = modifiers.intersection([.shift, .control, .option, .command])
        if flags == [.option, .command] { return nil }
        return flags == .option ? .openInSplit : .activate
    }

    static func mouseDown(modifiers: NSEvent.ModifierFlags, clickCount: Int,
                          isKey: Bool) -> FavoritePointerAction? {
        guard !modifiers.contains(.control) else { return nil }
        // Repeated down takes the double-click branch whatever the key state or
        // modifiers; the reset owner still applies its own window gate.
        if clickCount >= 2 { return .resetIfNeeded }
        guard clickCount == 1, selectsOnDown(modifiers: modifiers, isKey: isKey) else { return nil }
        // The reference compares the complete normalized flags here, including
        // Caps Lock/function/numeric-pad, rather than only command/shift.
        return modifiers.intersection(.deviceIndependentFlagsMask) == .command
            ? .resetAndSelect : .activate
    }
}

struct FavoritePointerOwner: Equatable {
    let tabID: UUID
    let profileID: UUID
    let spaceID: UUID
    let createdAt: Date
}

///
///
/// joins them with ", " and falls back to "Favorite item" for an empty list.
enum FavoriteAccessibilityTitle {
    static func text(_ titles: [String]) -> String {
        titles.isEmpty ? "Favorite item" : titles.joined(separator: ", ")
    }
}

/// A profile-wide saved item. The button does not own a page, selection or
/// destructive action: every activation/menu/AX request asks its original owner.
final class FavoriteTile: NSButton, NSDraggingSource, SidebarItemDragSource {
    var beginMove: (() -> SidebarMoveSession?)?
    private(set) var sidebarDrag: SidebarMoveSession?
    private var dragStart: NSPoint?
    private var pendingMove: SidebarMoveSession?
    var canActivate: (() -> Bool)?
    var activate: (() -> Bool)?
    var preparePointerAction: ((FavoritePointerAction) -> (() -> Bool)?)?
    private var pointerOwner: FavoritePointerOwner?
    private var releaseActions: [FavoritePointerAction: () -> Bool] = [:]
    private weak var pointerWindow: NSWindow?
    private var pointerEventNumber: Int?

    var makeMenu: (() -> NSMenu?)?
    var makeAccessibilityActions: (() -> [NSAccessibilityCustomAction])?
    var selected = false {
        didSet { if selected != oldValue { applyState(hoverChanged: false); overlays.setSelected(selected) } }
    }
    /// AppItem.shouldDim (INC-01), from this tile's window; applied at once (S29).
    private(set) var dimmed = false { didSet { if dimmed != oldValue { applyState(hoverChanged: false) } } }
    private var pressed = false
    private var windowObserver: NSObjectProtocol?
    // Layer order follows the recovered App Tray tile: shadow, selected
    // background with its icon wash, page cells, then the selection outline,
    // whose masked ring holds the wash image or, dimmed, a muted fill.
    let shadowLayer = CALayer()
    let selectionFill = CALayer()
    let washLayer = CALayer()
    let outlineLayer = CALayer()
    let outlineImage = CALayer()
    private let outlineMask = CAShapeLayer()
    private var cells: [FavoriteTileCell] = []
    private var orientation: SplitOrientation = .horizontal
    private var customGlyph = false
    private var hovered = false
    private var tracking: NSTrackingArea?
    private var paletteIsDark: Bool?
    private var glyphColor = NSColor.labelColor
    private var washKey: FavoriteWashKey?
    private var washGeneratedAt: CFTimeInterval = -.infinity
    private var pendingWash: DispatchWorkItem?
    /// Recording dot, Peek badge and music particles (FavoriteTileOverlays.swift).
    private(set) lazy var overlays = FavoriteTileOverlays(host: self)
    /// The window key/main input for `dimmed` (FavoriteTileOverlays.swift).
    private(set) lazy var windowActivity = FavoriteWindowActivity { [weak self] dim in self?.dimmed = dim }

    /// `title` is the spoken item title (see `FavoriteAccessibilityTitle`).
    init(title: String, monogram: String, url: String) {
        super.init(frame: .zero)
        isBordered = false; bezelStyle = .regularSquare
        self.title = ""; imagePosition = .noImage
        wantsLayer = true
        focusRingType = .exterior
        //
        // described as "Favorite" that speaks a title, not a description.
        setAccessibilityTitle(title)
        setAccessibilityRoleDescription("Favorite")
        setAccessibilityHelp(url)
        target = self; action = #selector(invoke)
        buildLayers()
        setPages([monogram], orientation: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        pendingWash?.cancel()
    }

    @objc private func invoke() {
        guard window != nil, canActivate?() == true else { return }
        _ = activate?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard window != nil, canActivate?() == true else { return false }
        return activate?() == true
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard window != nil else { return [] }
        return makeAccessibilityActions?() ?? []
    }
    override func isAccessibilitySelected() -> Bool { selected }
    override func isAccessibilityEnabled() -> Bool { window != nil && canActivate?() == true }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard window != nil else { return nil }
        return makeMenu?()
    }
    override func rightMouseDown(with event: NSEvent) {
        cancelPress()
        if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard window != nil, let menu = makeMenu?() else { return false }
        cancelPress()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }
    func update(title: String, monogram: String, url: String, owner: FavoritePointerOwner) {
        if pointerOwner != owner { cancelPress() }
        pointerOwner = owner
        if !customGlyph, cells.count == 1 { cells[0].monogram = monogram; refreshCell(cells[0]) }
        setAccessibilityTitle(title); setAccessibilityHelp(url)
    }

    /// One cell per original page: a split Favorite shows each page's icon.
    func setPages(_ monograms: [String], orientation: SplitOrientation) {
        let count = max(1, monograms.count)
        if customGlyph || cells.count != count || self.orientation != orientation {
            customGlyph = false
            self.orientation = orientation
            cells.forEach { $0.fill.removeFromSuperlayer() }
            cells = (0..<count).map { _ in FavoriteTileCell() }
            for cell in cells { layer?.insertSublayer(cell.fill, below: outlineLayer) }
            needsLayout = true
        }
        for (cell, monogram) in zip(cells, monograms) { cell.monogram = monogram }
        cells.forEach(refreshCell)
        applyState(hoverChanged: false)
    }

    /// A container's own emoji or symbol replaces the page icons.
    func setCustomGlyph(image: NSImage?, text: String?) {
        if !customGlyph { setPages([""], orientation: .horizontal); customGlyph = true }
        let cell = cells[0]
        cell.generation &+= 1
        cell.monogram = text ?? ""; cell.custom = image; cell.favicon = nil
        refreshCell(cell)
        refreshWash()
    }

    /// Real page artwork replaces the monogram; a nil reply keeps the monogram.
    /// The previous image stays until the reply so redraws do not flicker.
    func loadFavicon(page index: Int = 0, _ request: (@escaping (NSImage?) -> Void) -> Void) {
        guard !customGlyph, cells.indices.contains(index) else { return }
        let cell = cells[index]
        cell.generation &+= 1
        let original = cell.generation
        request { [weak self, weak cell] image in
            guard let self, let cell, cell.generation == original, self.cells.contains(where: { $0 === cell }) else { return }
            cell.favicon = image
            self.refreshCell(cell)
            self.refreshWash()
        }
    }

    /// True when every page cell already shows settled non-nil favicon art.
    /// Used to skip re-arm only for a true on-screen no-op; monogram-only
    /// tiles keep loading so a later same-URL history hit is not dropped.
    func hasSettledPageFavicons(count: Int) -> Bool {
        !customGlyph && cells.count == count && cells.allSatisfy { $0.favicon != nil }
    }

    ///
    /// (S18); `highlightColor` is its maxContrastColor.
    func applyPalette(isDark: Bool, glyphColor: NSColor, highlightColor: NSColor? = nil) {
        paletteIsDark = isDark; self.glyphColor = glyphColor
        cells.forEach(refreshCell)
        applyState(hoverChanged: false)
        overlays.setPaletteDark(isDark)
        overlays.setHighlightColor(highlightColor)
    }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: FavoriteTileMetrics.cornerRadius,
                     yRadius: FavoriteTileMetrics.cornerRadius).fill()
    }

    override func layout() {
        super.layout()
        let m = FavoriteTileMetrics.self
        let bounds = self.bounds
        let local = CGRect(origin: .zero, size: bounds.size)
        let shadowPath = FavoriteTilePaths.roundedRect(bounds, radius: m.cornerRadius)
        // After apply, outlineLayer.bounds is the local tile size; compute the
        // ring against that so the skip compares the post-layout path.
        let outlinePath = FavoriteTilePaths.selectionRing(bounds: local, count: cells.count,
                                                          orientation: orientation)
        let layouts = FavoriteChildLayouts.layouts(count: cells.count, size: bounds.size, gap: m.childGap,
                                                   orientation: orientation)
        let side = cells.count > 1 ? m.childIconSide : m.iconSide
        let single = cells.count == 1
        var expectedCells: [FavoriteTileLayerLayoutSkip.CellGeometry] = []
        expectedCells.reserveCapacity(layouts.count)
        for item in layouts {
            let frame = backingAlignedRect(item.rect, options: .alignAllEdgesNearest)
            let icon = backingAlignedRect(NSRect(x: frame.midX - side / 2, y: frame.midY - side / 2,
                                                 width: side, height: side), options: .alignAllEdgesNearest)
            let glyph = FavoriteTileLayerLayoutSkip.glyphGeometry(in: frame.size, single: single)
            expectedCells.append(.init(
                fillFrame: frame,
                corners: item.corners,
                iconFrame: icon.offsetBy(dx: -frame.minX, dy: -frame.minY),
                glyphFrame: glyph.frame,
                glyphFontSize: glyph.fontSize
            ))
        }
        let currentCells = cells.map { cell in
            FavoriteTileLayerLayoutSkip.CellGeometry(
                fillFrame: cell.fill.frame,
                corners: cell.fill.maskedCorners,
                iconFrame: cell.icon.frame,
                glyphFrame: cell.glyph.frame,
                glyphFontSize: cell.glyph.fontSize
            )
        }
        // Sidebar chrome can mark the tray dirty without changing tile bounds,
        // split orientation, or child frames. Skip the CATransaction when those
        // layer writes would be identical; overlays and wash keep their own paths.
        if FavoriteTileLayerLayoutSkip.shouldSkip(
            bounds: bounds,
            shadowFrame: shadowLayer.frame,
            shadowPath: shadowLayer.shadowPath,
            expectedShadowPath: shadowPath,
            selectionFrame: selectionFill.frame,
            washFrame: washLayer.frame,
            outlineFrame: outlineLayer.frame,
            outlineMaskFrame: outlineMask.frame,
            outlineImageFrame: outlineImage.frame,
            outlineMaskPath: outlineMask.path,
            expectedOutlinePath: outlinePath,
            cells: currentCells,
            expectedCells: expectedCells
        ) {
            overlays.layout()
            refreshWash()
            return
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = shadowPath
        selectionFill.frame = bounds; washLayer.frame = local
        outlineLayer.frame = bounds; outlineMask.frame = local
        outlineImage.frame = local
        outlineMask.path = outlinePath
        for (cell, expected) in zip(cells, expectedCells) {
            cell.fill.frame = expected.fillFrame
            cell.fill.maskedCorners = expected.corners
            cell.icon.frame = expected.iconFrame
            cell.layoutGlyph(in: expected.fillFrame.size, single: single)
        }
        CATransaction.commit()
        overlays.layout()
        refreshWash()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for layer in [washLayer, outlineImage] { layer.contentsScale = scale }
        for cell in cells { cell.icon.contentsScale = scale; cell.glyph.contentsScale = scale }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if tracking == nil {
            //
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved,
                                                              .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area); tracking = area
        }
        refreshHover()
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        refreshHover(atWindowPoint: event.locationInWindow)
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        refreshHover(atWindowPoint: event.locationInWindow)
    }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); setHovered(false) }

    /// App Tray pointer hover. Tests assert enter/exit and the mouseMoved no-op skip.
    var isPointerHovered: Bool { hovered }

    /// No App Tray item view (wrapper → FlippedView → NSView, tile → HoverableView
    /// → TaggableView → NSView) accepts first mouse, so the click that activates
    /// an inactive window neither presses, selects nor starts a drag. NSButton
    /// would otherwise accept it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        cancelPress()
        guard let window, !isHiddenOrHasHiddenAncestor, isEnabled,
              event.windowNumber == window.windowNumber, canActivate?() == true else { return }
        pointerWindow = window; pointerEventNumber = event.eventNumber
        dragStart = convert(event.locationInWindow, from: nil)
        setPressed(true)
        if let intent = FavoritePointerPolicy.mouseDown(modifiers: event.modifierFlags,
                clickCount: event.clickCount, isKey: window.isKeyWindow) {
            // Ask before dispatch; a synchronous render must not turn a down
            // selection into a second release activation of a rebuilt tile.
            let action = preparePointerAction?(intent)
            _ = action?()
        }
        // Prepare after any synchronous down action so Option added before up
        // sees that original resulting selection. The release event owns flags.
        if event.clickCount == 1, pointerWindow === window {
            if let split = preparePointerAction?(.openInSplit) { releaseActions[.openInSplit] = split }
            if let activate = preparePointerAction?(.activate) { releaseActions[.activate] = activate }
            pendingMove = beginMove?()
        }
    }
    override func mouseUp(with event: NSEvent) {
        let intent = FavoritePointerPolicy.mouseUp(modifiers: event.modifierFlags,
            clickCount: event.clickCount, isKey: window?.isKeyWindow == true)
        let action = intent.flatMap { releaseActions[$0] }
        // Key state belongs to the policy above; each lease applies its own gate.
        let eligible = pointerEventNumber != nil && window === pointerWindow
            && event.windowNumber == window?.windowNumber
            && !isHiddenOrHasHiddenAncestor && isEnabled
            && bounds.contains(convert(event.locationInWindow, from: nil))
        pendingMove?.end(); pendingMove = nil
        releaseActions.removeAll(); pointerWindow = nil; pointerEventNumber = nil; dragStart = nil
        setPressed(false)
        if eligible { _ = action?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, window === pointerWindow,
              event.windowNumber == window?.windowNumber else { return }
        releaseActions.removeAll(); setPressed(false)
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        let original = pendingMove; pendingMove = nil
        cancelPress()
        // Option-copy is a distinct reference route. Only a whole Favorite
        //
        // SP23); a move-only source never changes an Option gesture into a
        // destructive move.
        guard let session = original, session.isValid,
              !event.modifierFlags.contains(.option) || session.allowsCopy else { original?.end(); return }
        sidebarDrag = session
        let item = NSPasteboardItem()
        item.setString(session.identifier.uuidString, forType: SidebarMoveSession.pasteboardType)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(bounds, contents: dragImage())
        beginDraggingSession(with: [dragging], event: event, source: self)
    }
    ///
    /// tile admits copy only when its session can copy (a whole split).
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .withinApplication else { return [] }
        return sidebarDrag?.allowsCopy == true ? [.move, .copy] : .move
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        sidebarDrag?.end(); sidebarDrag = nil
    }
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        setPressed(flag && window?.isKeyWindow == true)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        cancelPress()
        if newWindow !== window { sidebarDrag?.end(); sidebarDrag = nil; setHovered(false, animated: false) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        if let newWindow {
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: newWindow, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelPress(); self?.setHovered(false) }
                }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override var isHidden: Bool { didSet { if isHidden { cancelPress(); setHovered(false, animated: false) } } }
    override var isEnabled: Bool { didSet { if !isEnabled { cancelPress() } } }

    private var isDark: Bool {
        paletteIsDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    private func buildLayers() {
        guard let layer else { return }
        let m = FavoriteTileMetrics.self
        layer.masksToBounds = false
        for sublayer in [shadowLayer, selectionFill, washLayer, outlineLayer, outlineImage, outlineMask] {
            FavoriteTileCell.disableActions(sublayer)
        }
        //
        // its opacity is part of the selected style.
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowRadius = 2
        shadowLayer.shadowOffset = CGSize(width: 0, height: 1)
        selectionFill.cornerRadius = m.cornerRadius; selectionFill.cornerCurve = .continuous
        selectionFill.masksToBounds = true
        washLayer.contentsGravity = .resize
        selectionFill.addSublayer(washLayer)
        // AppTrayItemSelectionOutlineView: a masked content view holding an image view.
        outlineImage.contentsGravity = .resize
        outlineLayer.addSublayer(outlineImage)
        outlineMask.fillColor = NSColor.black.cgColor
        outlineMask.fillRule = .evenOdd
        outlineLayer.mask = outlineMask
        for sublayer in [shadowLayer, selectionFill, outlineLayer] {
            sublayer.isHidden = true
            layer.addSublayer(sublayer)
        }
    }

    private func refreshCell(_ cell: FavoriteTileCell) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        cell.icon.contents = cell.custom.map { FavoriteTileCell.tinted($0, color: glyphColor) } ?? cell.favicon
        cell.glyph.string = cell.icon.contents == nil ? cell.monogram : ""
        cell.glyph.foregroundColor = glyphColor.cgColor
        CATransaction.commit()
        cell.layoutGlyph(in: cell.fill.bounds.size, single: cells.count == 1)
    }

    private func setHovered(_ value: Bool, animated: Bool = true) {
        guard hovered != value else { return }
        hovered = value
        applyState(hoverChanged: animated)
    }

    /// Resolves whether the pointer is over this tile (or a descendant).
    ///
    /// Tracking delivers `mouseMoved` for every point inside the area. When the
    /// tile is already hovered and the pointer remains inside local bounds, the
    /// hover bit cannot change without leaving those bounds (`mouseExited`
    /// clears; App Tray tiles do not stack non-descendant hit targets over the
    /// tile). Skip the window-wide `contentView.hitTest` in that true no-op
    /// case. Enter, leave, resign-key, hide, and first resolution while
    /// unhovered still hit-test.
    private func refreshHover(atWindowPoint windowPoint: NSPoint? = nil) {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor,
              let content = window.contentView else { setHovered(false); return }
        let location = windowPoint ?? window.mouseLocationOutsideOfEventStream
        if hovered {
            let local = convert(location, from: nil)
            if bounds.contains(local) { return }
        }
        let hit = content.hitTest(content.superview?.convert(location, from: nil) ?? location)
        setHovered(hit === self || hit?.isDescendant(of: self) == true)
    }

    /// Selection, dim, idle and hover states. Only hover changes animate
    /// (0.12 s); selection and dim are immediate, as in the recovered sinks
    ///
    private func applyState(hoverChanged: Bool) {
        let dark = isDark
        let style = FavoriteSelectedStyle(dark: dark, hovered: hovered, dimmed: dimmed)
        let animate = hoverChanged && window != nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shadowLayer.isHidden = !selected
        selectionFill.isHidden = !selected
        outlineLayer.isHidden = !selected
        shadowLayer.shadowOpacity = style.shadowOpacity
        selectionFill.backgroundColor = NSColor.white.withAlphaComponent(style.fillAlpha).cgColor
        outlineImage.isHidden = !style.outlineShowsWash
        var muted: CGColor?
        if let alpha = style.outlineFillAlpha {
            effectiveAppearance.performAsCurrentDrawingAppearance { muted = glyphColor.withAlphaComponent(alpha).cgColor }
        }
        outlineLayer.backgroundColor = muted
        CATransaction.commit()
        let fill = FavoriteTileCell.fill(dark: dark, hovered: hovered)
        for cell in cells {
            cell.setFill(selected ? NSColor.clear.cgColor : fill, animated: animate && !selected)
        }
        if animate && selected && style.washAnimates {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = washLayer.presentation()?.opacity ?? washLayer.opacity
            fade.toValue = style.washOpacity; fade.duration = FavoriteTileMetrics.hoverDuration
            washLayer.add(fade, forKey: "wash")
        } else { washLayer.removeAnimation(forKey: "wash") }
        washLayer.opacity = style.washOpacity
        if selected { refreshWash() }
    }

    /// AppTrayVisualEffectImageProvider: the first image is immediate and later
    /// changes are throttled to the latest request every 0.25 s.
    private func refreshWash() {
        guard selected, bounds.width > 0, bounds.height > 0 else { return }
        let icons = customGlyph ? [] : cells.map(\.favicon)
        let key = FavoriteWashKey(icons: icons.map { $0.map(ObjectIdentifier.init) }, size: bounds.size,
                                  orientation: orientation)
        guard key != washKey else { return }
        let wait = washGeneratedAt + FavoriteTileMetrics.washRefreshInterval - CACurrentMediaTime()
        if wait > 0 {
            guard pendingWash == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingWash = nil
                self.refreshWash()
            }
            pendingWash = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
            return
        }
        washKey = key; washGeneratedAt = CACurrentMediaTime()
        let layouts = FavoriteChildLayouts.layouts(count: cells.count, size: bounds.size,
                                                   gap: FavoriteTileMetrics.childGap, orientation: orientation)
        let side = cells.count > 1 ? FavoriteTileMetrics.childIconSide : FavoriteTileMetrics.iconSide
        let sources = zip(icons, layouts).compactMap { icon, item in icon.map { ($0, item.rect) } }
        let image = FavoriteWash.image(icons: sources, renderSide: side, size: bounds.size)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        washLayer.contents = image; outlineImage.contents = image
        CATransaction.commit()
    }

    private func dragImage() -> NSImage {
        guard let layer else { return NSImage(size: bounds.size) }
        return NSImage(size: bounds.size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            layer.render(in: context)
            return true
        }
    }
    private func cancelPress() {
        pendingMove?.end(); pendingMove = nil
        releaseActions.removeAll(); pointerWindow = nil; pointerEventNumber = nil; dragStart = nil
        pressed = false
        layer?.removeAnimation(forKey: "favoritePress")
        layer?.transform = CATransform3DIdentity
    }
    private func setPressed(_ value: Bool) {
        guard pressed != value, let layer else { return }
        pressed = value
        let next = value ? CATransform3DMakeScale(0.99, 0.99, 1) : CATransform3DIdentity
        let previous = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let frame = layer.frame
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.frame = frame
        }
        layer.transform = next; CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window != nil else {
            layer.removeAnimation(forKey: "favoritePress"); return
        }
        //
        // response .2; both transitions start at the current presentation.
        let spring = CASpringAnimation(keyPath: "transform")
        spring.mass = 1
        spring.stiffness = pow(2 * Double.pi / 0.2, 2)
        spring.damping = 4 * Double.pi * 0.5 / 0.2
        spring.fromValue = NSValue(caTransform3D: previous)
        spring.toValue = NSValue(caTransform3D: next)
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "favoritePress")
    }
}

private struct FavoriteWashKey: Equatable {
    let icons: [ObjectIdentifier?]
    let size: CGSize
    let orientation: SplitOrientation
}

/// One page cell: recovered idle/hover fill (BaseAssets SidebarItemBackground /
/// SidebarItemHoveredBackground), a centered icon and Parc's monogram fallback.
private final class FavoriteTileCell {
    let fill = CALayer()
    let icon = CALayer()
    let glyph = CATextLayer()
    var monogram = ""
    var favicon: NSImage?
    var custom: NSImage?
    var generation: UInt64 = 0

    init() {
        for layer in [fill, icon, glyph] { Self.disableActions(layer) }
        fill.cornerRadius = FavoriteTileMetrics.cornerRadius; fill.cornerCurve = .continuous
        icon.contentsGravity = .resizeAspect
        glyph.alignmentMode = .center
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        icon.contentsScale = scale; glyph.contentsScale = scale
        fill.addSublayer(icon); fill.addSublayer(glyph)
    }

    ///
    func layoutGlyph(in size: CGSize, single: Bool) {
        let font = NSFont.systemFont(ofSize: single ? 15 : 11, weight: .semibold)
        let height = ceil(font.ascender - font.descender)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glyph.font = font; glyph.fontSize = font.pointSize
        glyph.frame = CGRect(x: 0, y: ((size.height - height) / 2).rounded(), width: size.width, height: height)
        CATransaction.commit()
    }

    func setFill(_ color: CGColor, animated: Bool) {
        guard fill.backgroundColor != color else { return }
        if animated {
            //
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = fill.backgroundColor
            animation.toValue = color
            animation.duration = FavoriteTileMetrics.hoverDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fill.add(animation, forKey: "background_color")
        } else { fill.removeAnimation(forKey: "background_color") }
        fill.backgroundColor = color
    }

    static func fill(dark: Bool, hovered: Bool) -> CGColor {
        dark ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: hovered ? 0.15 : 0.1).cgColor
             : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: hovered ? 0.1 : 0.05).cgColor
    }

    /// Template symbols keep their own aspect; the icon layer fits them to the slot.
    static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        guard image.isTemplate else { return image }
        return NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set(); rect.fill(using: .sourceAtop)
            return true
        }
    }

    static func disableActions(_ layer: CALayer) {
        layer.actions = ["backgroundColor": NSNull(), "contents": NSNull(), "bounds": NSNull(),
                         "position": NSNull(), "frame": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
                         "shadowPath": NSNull(), "path": NSNull(), "string": NSNull(),
                         "foregroundColor": NSNull(), "maskedCorners": NSNull(), "font": NSNull(),
                         "fontSize": NSNull(), "contentsScale": NSNull(), "sublayers": NSNull()]
    }
}

///
/// (radius 5), saturated (1.5, brightness .05, contrast .85) and drawn centered
/// on its cell at renderSize × tileWidth / 5.
@MainActor private enum FavoriteWash {
    static let context = CIContext()

    static func image(icons: [(NSImage, CGRect)], renderSide: CGFloat, size: CGSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let drawn: [(NSImage, CGRect)] = icons.compactMap { icon, cell in
            var proposed = CGRect(x: 0, y: 0, width: renderSide, height: renderSide)
            guard let source = icon.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
                  let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: CIImage(cgImage: source),
                                                                          kCIInputRadiusKey: 5]),
                  let blurred = blur.outputImage,
                  let colors = CIFilter(name: "CIColorControls", parameters: [kCIInputImageKey: blurred,
                                                                             kCIInputSaturationKey: 1.5,
                                                                             kCIInputBrightnessKey: 0.05,
                                                                             kCIInputContrastKey: 0.85]),
                  let output = colors.outputImage,
                  let result = context.createCGImage(output, from: output.extent) else { return nil }
            let side = renderSide * size.width / 5
            return (NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)),
                    CGRect(x: cell.midX - side / 2, y: cell.midY - side / 2, width: side, height: side))
        }
        guard !drawn.isEmpty else { return nil }
        return NSImage(size: size, flipped: true) { _ in
            for (image, rect) in drawn {
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            return true
        }
    }
}
