import AppKit

@MainActor final class DragLayer: NSView {
    var region: (frame: NSRect, opacity: CGFloat)?
    var regionColor = NSColor.black
    var image: (image: NSImage, frame: NSRect)?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        if let region, region.opacity > 0, region.frame.width > 2, region.frame.height > 2 {
            let path = NSBezierPath(roundedRect: region.frame.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            path.lineWidth = 2
            regionColor.withAlphaComponent(regionColor.alphaComponent * region.opacity).setStroke()
            path.stroke()
        }
        if let image {
            image.image.draw(in: image.frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                             hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
    }
}

@MainActor final class StackFilm {
    static let pages = "../pages/png/"
    static let fps = 60.0
    static let duration = 9.0
    static let pick = "Add Below This Pane"
    static let keys: [(Double, String)] = [(2.30, "m"), (2.43, "me"), (2.56, "mea"), (2.77, "mead")]
    static let menuAt = 0.85, chooseAt = 1.50, pendingAt = 1.75, returnAt = 3.25, paintAt = 3.50
    static let reachAt = 4.15, hoverAt = 4.70, pressAt = 4.85, liftAt = 4.92, arriveAt = 5.95, dropAt = 6.50, dropPaintAt = 6.70
    static let bow: [(along: CGFloat, off: CGFloat)] = [(0.36, 60), (0.72, 60)]

    let scene: BrowserScene
    let host: NSView
    let split: ParcSplitView
    let margin: SplitMarginHandleView
    let overlay: Overlay
    let bar: StackBar
    let drags: DragLayer
    let palette: ThemeChromePalette
    let arts: [PageArt]
    let placeholder = SplitPanePlaceholder(frame: .zero)
    var views: [NSView] = []
    var tabs: [BrowserTab] = []
    var layout: BrowserSplitLayout
    var shown: BrowserSplitLayout
    var state: BrowserState?
    var focused: Int? = 0
    var pendingOpen = false
    let groupID = UUID()
    var log: [String] = []
    var dropLog: [String] = []
    var beats: [(Double, String)] = []
    var ringFades: [(pane: PaneStandIn, start: Double, to: Float)] = []
    var pointer = NSPoint(x: 640, y: 560)
    var pointerShown = true
    var move: (t0: Double, t1: Double, from: NSPoint, to: NSPoint)?
    var menuRows: [MenuRow] = []
    var menuOrigin = NSPoint.zero
    var menuOpen = false
    var events: [(Double, String, () -> Void)] = []
    var nextEvent = 0
    let source: BrowserTab
    var row: SidebarTabRow?
    var grab = NSPoint.zero
    var rowImage: NSImage?
    var rowFrame = NSRect.zero
    var card: (image: NSImage, size: NSSize)?
    var drop: StackDrop?
    var path: (start: NSPoint, first: NSPoint, second: NSPoint, end: NSPoint)?
    var arc: [(length: CGFloat, point: NSPoint)] = []
    var trail: [[Double]] = []
    var homes: [UUID: UUID] = [:]
    var creation: TabCreationProvenance?

    init() {
        scene = BrowserScene(size: NSSize(width: 1440, height: 900), windowRect: NSRect(x: 80, y: 18, width: 1280, height: 840),
                             scale: 2, pagePath: "")
        palette = scene.themeSurface.palette
        scene.surface.drawPage = { _ in }
        let card = scene.surface.pageCard
        arts = [
            PageArt(path: Self.pages + "article.png", band: (270, 1030), maxScale: card.width / 1300),
            PageArt(path: Self.pages + "picnic.png", band: (20, 680), maxScale: card.width / 1300, height: 822, baseSample: (4, 800)),
            PageArt(path: Self.pages + "map.png", band: (10, 560), maxScale: 1, mirrors: true),
            PageArt(path: Self.pages + "doc.png", band: (250, 1040), maxScale: card.width / 1300),
        ]
        source = scene.scenario.state.tabs.first { $0.title == "Q4 planning" }!
        host = NSView(frame: card)
        host.wantsLayer = true
        host.layer?.cornerRadius = PageCard.cornerRadius
        host.layer?.cornerCurve = .continuous
        split = ParcSplitView(frame: host.bounds)
        host.addSubview(split)
        scene.surface.addSubview(host, positioned: .below, relativeTo: scene.edge)
        margin = SplitMarginHandleView(frame: NSRect(x: card.maxX, y: card.minY, width: 10, height: card.height))
        margin.windowAllows = false
        scene.surface.addSubview(margin, positioned: .below, relativeTo: scene.edge)
        overlay = Overlay(frame: scene.surface.bounds)
        overlay.pillBackground = palette.background.usingColorSpace(.sRGB).map { $0.withAlphaComponent(1) } ?? .white
        scene.surface.addSubview(overlay, positioned: .below, relativeTo: scene.pointer)
        bar = StackBar(scene: scene, below: scene.pointer)
        drags = DragLayer(frame: scene.surface.bounds)
        scene.surface.addSubview(drags, positioned: .below, relativeTo: scene.pointer)
        split.onSnapTransition = {}
        split.marginHandle = margin
        tabs = [scene.scenario.selected, scene.scenario.panes[0]]
        layout = BrowserSplitLayout(id: groupID, spaceID: scene.scenario.work.id, tabIDs: tabs.map(\.id),
                                    orientation: .horizontal, widthFactors: [0.5, 0.5], stacks: nil)
        shown = layout
        views = [PaneStandIn(art: arts[0]), PaneStandIn(art: arts[1])]
        for index in views.indices { configureToolbar(index, loading: false) }
        relayout()
        renderSidebar()
        scene.pointer.location = pointer
        let theme = scene.scenario.work.theme, layer = drags
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            layer.regionColor = ThemeChromePalette.appearanceBasedMaxContrast(theme: theme)
                .withAlphaComponent(0.5).usingColorSpace(.sRGB) ?? .black
        }
        schedule()
    }

    var surface: WindowSurface { scene.surface }
    var panes: [PaneStandIn] { views.compactMap { $0 as? PaneStandIn } }

    func relayout() {
        _ = split.reconcileArrangedSubviews(views)
        for pane in panes { pane.showsBar = true }
        split.configure(orientation: shown.orientation, factors: shown.widthFactors, stacks: shown.stacks)
        split.configureBacking(in: host, hasTranslucentPane: true)
        surface.showsCardShadow = false
        surface.needsDisplay = true
        for (index, view) in views.enumerated() {
            guard let pane = view as? PaneStandIn else { view.needsLayout = true; view.layoutSubtreeIfNeeded(); continue }
            pane.highlight.color = palette.isDark ? palette.shaded : palette.shadedDark
            pane.highlight.update(display: index == focused, width: 2)
            pane.needsLayout = true
            pane.layoutSubtreeIfNeeded()
        }
        placeholder.splitHighlight.update(display: false, width: 2)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for layer in split.layer?.sublayers ?? [] where layer.name == "Split pane shadow" {
            ContentShadowImage.apply(to: layer, scale: 2)
        }
        showGrips(true)
        CATransaction.commit()
        for pane in panes { pane.page.needsDisplay = true }
        log.append("layout tabs \(shown.tabIDs.count) stacks \(String(describing: shown.stacks)) frames \(views.map { NSStringFromRect($0.frame) })")
    }

    func showGrips(_ visible: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for grip in (split.layer?.sublayers ?? []).filter({ $0.name == "Split divider grip" }) {
            grip.removeAllAnimations()
            grip.backgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.2).cgColor
            grip.isHidden = !visible
        }
        CATransaction.commit()
    }

    func configureToolbar(_ index: Int, loading: Bool) {
        guard let pane = views[index] as? PaneStandIn else { return }
        let toolbar = pane.toolbar
        toolbar.update(url: URL(string: tabs[index].url), fullURL: false, enabled: true, canBack: index == 0, canForward: false,
                       loading: loading, canReload: true, canCopy: true, canShowSiteInfo: true, canSplit: true,
                       close: true, showSidebar: false, extensionItems: [])
        toolbar.themeBackground = palette.background
        toolbar.setPageColor(loading ? nil : pane.page.art.top, for: pane, animated: false)
        if pane.revealViews.isEmpty { pane.findRevealViews() }
        toolbar.setControlsRevealed(index == focused, duration: nil)
        toolbar.needsLayout = true
        toolbar.layoutSubtreeIfNeeded()
    }

    func sidebarState(_ split: BrowserSplitLayout) -> BrowserState {
        var state = scene.scenario.state
        let base = state.tabs.filter { tab in !tabs.dropFirst().contains { $0.id == tab.id } }
        let anchor = base.firstIndex { $0.id == tabs[0].id }!
        var all = base
        all.replaceSubrange(anchor...anchor, with: tabs)
        state.tabs = all
        state.splitLayouts = [split]
        state.selectedTabIDs = split.tabIDs
        state.selectionBySpace[state.activeSpaceID.uuidString] = split.tabIDs
        return state
    }

    func renderSidebar() {
        let state = self.state ?? sidebarState(layout)
        let sidebar = scene.sidebar
        sidebar.newTabPlaceholderActive = pendingOpen
        sidebar.render(state: state, focusedTabID: tabs[focused ?? 0].id, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        let end = Date().addingTimeInterval(0.25)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        sidebar.needsLayout = true
        sidebar.layoutSubtreeIfNeeded()
    }

    func paneRect(_ view: NSView) -> NSRect { surface.convert(view.bounds, from: view) }

    func at(_ t: Double, _ name: String, _ action: @escaping () -> Void) { events.append((t, name, action)) }

    func moveTo(_ t0: Double, _ t1: Double, _ target: @escaping () -> NSPoint) {
        at(t0, "") { [unowned self] in move = (t0, t1, pointer, target()) }
    }

    func fadeRing(_ index: Int, to: Float, _ t: Double, width: CGFloat = 2) {
        guard let pane = views[index] as? PaneStandIn else { return }
        pane.highlight.update(display: true, width: width)
        pane.highlight.layer.opacity = to == 1 ? 0 : 1
        ringFades.append((pane, t, to))
    }

    func canPropose(_ target: SplitDropTarget, _ orientation: SplitOrientation) -> Bool {
        let state = sidebarState(layout)
        let space = scene.scenario.work
        guard let required = OriginalSplitDrop.savedHomes(source: source.id, state: state, selection: layout.tabIDs, layout: layout,
                                                         target: target, orientation: orientation, spaceID: space.id) else { return false }
        return SidebarDocumentReference.validates(required, references: [:])
            && OriginalSplitDrop.proposal(source: source.id, state: state, selection: layout.tabIDs, layout: layout, target: target,
                                          orientation: orientation, spaceID: space.id, profileID: space.profileID, now: ScenarioBuilder.base,
                                          savedHomeIDs: homes, creation: creation) != nil
    }

    func curvePoint(_ u: CGFloat) -> NSPoint {
        guard let path else { return pointer }
        let v = 1 - u
        let a = path.start, b = path.first, c = path.second, d = path.end
        return NSPoint(x: v * v * v * a.x + 3 * v * v * u * b.x + 3 * v * u * u * c.x + u * u * u * d.x,
                       y: v * v * v * a.y + 3 * v * v * u * b.y + 3 * v * u * u * c.y + u * u * u * d.y)
    }

    func layPath(from start: NSPoint, to end: NSPoint) {
        let dx = end.x - start.x, dy = end.y - start.y, length = max(1, hypot(dx, dy))
        let handles = Self.bow.map { NSPoint(x: start.x + dx * $0.along + dy / length * $0.off,
                                             y: start.y + dy * $0.along - dx / length * $0.off) }
        path = (start, handles[0], handles[1], end)
        arc = [(0, start)]
        for step in 1...1000 {
            let point = curvePoint(CGFloat(step) / 1000)
            arc.append((arc[arc.count - 1].length + hypot(point.x - arc[arc.count - 1].point.x, point.y - arc[arc.count - 1].point.y), point))
        }
    }

    func dragPoint(_ t: Double) -> NSPoint {
        guard let total = arc.last?.length, total > 0 else { return pointer }
        let u = clamp01((t - Self.liftAt) / (Self.arriveAt - Self.liftAt))
        let travel = CGFloat(20 * pow(u, 3) - 45 * pow(u, 4) + 36 * pow(u, 5) - 10 * pow(u, 6)) * total
        let index = max(1, arc.firstIndex { $0.length >= travel } ?? arc.count - 1)
        let a = arc[index - 1], b = arc[index]
        let w = b.length > a.length ? (travel - a.length) / (b.length - a.length) : 0
        return NSPoint(x: a.point.x + (b.point.x - a.point.x) * w, y: a.point.y + (b.point.y - a.point.y) * w)
    }

    func dropEnd() -> NSPoint {
        let picnic = paneRect(views[2])
        return NSPoint(x: picnic.midX + 20, y: picnic.maxY - 24)
    }

    func schedule() {
        moveTo(0.25, 0.75) { [unowned self] in
            let button = panes[0].splitButton!
            return surface.convert(NSPoint(x: button.bounds.midX + 1, y: button.bounds.midY + 1), from: button)
        }
        at(0.75, "") { [unowned self] in scene.pointer.cursor = .pointingHand }
        at(Self.menuAt, "Click the article pane's split button: its menu opens with the stacked rows") { [unowned self] in
            scene.pointer.cursor = .arrow
            let menu = SplitPaneMenu.make(orientation: .horizontal, index: 0, count: tabs.count, layout: layout, prepare: { _ in {} })
            menuRows = menu.items.map { MenuRow(title: $0.title, image: $0.image, enabled: $0.isEnabled, separator: $0.isSeparatorItem) }
            let button = panes[0].splitButton!
            menuOrigin = surface.convert(NSPoint(x: 0, y: button.isFlipped ? button.bounds.maxY : button.bounds.minY), from: button)
            menuOpen = true
            log.append("menu origin \(menuOrigin) rows \(menuRows.map { $0.separator ? "—" : "\($0.title)\($0.enabled ? "" : " (disabled)")" })")
        }
        moveTo(0.95, 1.40) { [unowned self] in
            let rects = MenuMetrics.rowRects(menuRows, origin: menuOrigin)
            let index = menuRows.firstIndex { $0.title == Self.pick }!
            return NSPoint(x: rects[index].minX + 70, y: rects[index].midY + 2)
        }
        at(Self.chooseAt, "Choose Add Below This Pane (item blinks, menu fades)") {}
        at(Self.pendingAt, "Pending pane takes the bottom of the article column; the command bar opens") { [unowned self] in
            menuOpen = false
            overlay.panel = nil
            let state = sidebarState(layout)
            let request = SplitPaneInsertion(paneID: tabs[0].id, stackingAfter: true, state: state)
            guard let request, let preview = request.previewLayout else {
                log.append("FAIL: no stacked insertion request for the article pane"); return
            }
            log.append("insertion index \(request.index) preview stacks \(String(describing: preview.stacks))")
            shown = preview
            views.insert(placeholder, at: request.index)
            fadeRing(0, to: 0, Self.pendingAt)
            focused = nil
            pendingOpen = true
            relayout()
            if let pane = views[0] as? PaneStandIn { pane.toolbar.setControlsRevealed(true, duration: nil) }
            renderSidebar()
            bar.refreshBackdrop()
            bar.show("", caretOpacity: 1)
        }
        at(Self.keys[0].0, "Typing hides the pointer") { [unowned self] in pointerShown = false }
        for (time, text) in Self.keys { at(time, "Keystroke \"\(text)\" (rows republish, top row selected)") {} }
        at(Self.returnAt, "Return: the bar closes in one frame and East Meadow Park fills the pending pane") { [unowned self] in
            bar.hide()
            let tab = scene.scenario.panes[1]
            guard let committed = layout.insertingIntoStack(tab.id, besidePaneAt: 0, after: true) else {
                log.append("FAIL: store edit refused"); return
            }
            log.append("commit matches preview shape \(committed.stacks == shown.stacks && committed.widthFactors == shown.widthFactors)")
            let index = views.firstIndex { $0 === placeholder }!
            let pane = PaneStandIn(art: arts[2])
            pane.page.painted = false
            views[index] = pane
            placeholder.removeFromSuperview()
            tabs.insert(tab, at: index)
            layout = committed
            shown = committed
            pendingOpen = false
            focused = index
            for i in views.indices { configureToolbar(i, loading: i == index) }
            relayout()
            fadeRing(index, to: 1, Self.returnAt)
            renderSidebar()
        }
        at(Self.paintAt, "Map pane first paint (cut)") { [unowned self] in
            if let pane = views[1] as? PaneStandIn { pane.page.painted = true }
            configureToolbar(1, loading: false)
        }
        at(3.75, "Hold: a stacked pair beside one big pane") {}
        at(Self.reachAt, "The pointer comes back and heads for the pinned Q4 planning tab") { [unowned self] in
            pointerShown = true
            guard let row = scene.row(titled: source.title) else { log.append("FAIL: no Q4 planning row"); return }
            self.row = row
            let frame = surface.convert(row.bounds, from: row)
            grab = NSPoint(x: frame.minX + 165, y: frame.midY + 1)
            move = (Self.reachAt, Self.hoverAt, pointer, grab)
        }
        at(Self.hoverAt, "Pointer rests on the Q4 planning row (hover)") { [unowned self] in scene.setHover(row) }
        at(Self.pressAt, "Press on the row") {}
        at(Self.liftAt, "Drag passes 4 pt: the row snapshot lifts and the split's drop session starts") { [unowned self] in
            guard let row else { return }
            scene.setHover(nil)
            row.layoutSubtreeIfNeeded()
            if let bitmap = row.bitmapImageRepForCachingDisplay(in: row.bounds) {
                row.cacheDisplay(in: row.bounds, to: bitmap)
                let image = NSImage(size: row.bounds.size); image.addRepresentation(bitmap)
                rowImage = image
            }
            rowFrame = surface.convert(row.bounds, from: row)
            row.keyDragged = true
            let state = sidebarState(layout)
            homes = [source.id: UUID()]
            creation = TabCreationProvenance(referrerID: nil, activeTabID: tabs[focused ?? 0].id, profileID: scene.scenario.work.profileID, state: state)
            drop = StackDrop(split: split, stacks: layout.stacks!, orientation: layout.orientation,
                             canPropose: { [unowned self] in canPropose($0, $1) })
            layPath(from: pointer, to: dropEnd())
            log.append("drag path \(String(describing: path)) length \(arc.last?.length ?? 0) row \(rowFrame)")
        }
        at(Self.dropAt, "Release: the tab drops into the reserved seat under the picnic plan") { [unowned self] in commitDrop() }
        at(Self.dropPaintAt, "Q4 planning pane first paint (cut)") { [unowned self] in
            if let pane = views.last as? PaneStandIn { pane.page.painted = true }
            configureToolbar(views.count - 1, loading: false)
        }
        at(7.0, "Hold: two by two") {}
        events.sort { $0.0 < $1.0 }
        beats = events.filter { !$0.1.isEmpty }.map { ($0.0, $0.1) }
    }

    func commitDrop() {
        guard let drop, let target = drop.target else { log.append("FAIL: release with no reserved seat"); return }
        let before = sidebarState(layout)
        guard let next = OriginalSplitDrop.proposal(source: source.id, state: before, selection: layout.tabIDs, layout: layout, target: target,
                                                   orientation: layout.orientation, spaceID: scene.scenario.work.id,
                                                   profileID: scene.scenario.work.profileID, now: ScenarioBuilder.base,
                                                   savedHomeIDs: homes, creation: creation),
              let group = next.splitLayouts.first(where: { $0.tabIDs.contains(source.id) }) else {
            log.append("FAIL: drop refused"); return
        }
        drop.finish()
        dropLog = drop.log
        self.drop = nil
        card = nil; rowImage = nil
        row?.keyDragged = false
        log.append("drop committed group \(group.tabIDs.count) stacks \(String(describing: group.stacks)) savedHomes \(homes)")
        let byID = Dictionary(uniqueKeysWithValues: zip(tabs.map(\.id), views))
        let pane = PaneStandIn(art: arts[3])
        pane.page.painted = false
        let q4 = next.tabs.first { $0.id == source.id } ?? source
        views = group.tabIDs.map { byID[$0] ?? pane }
        tabs = group.tabIDs.map { id in next.tabs.first { $0.id == id } ?? q4 }
        layout = group
        shown = group
        state = next
        focused = tabs.firstIndex { $0.id == source.id }
        for i in views.indices { configureToolbar(i, loading: views[i] === pane) }
        relayout()
        if let focused { fadeRing(focused, to: 1, Self.dropAt) }
        renderSidebar()
        log.append("after drop frames \(views.map { NSStringFromRect($0.frame) }) focused \(String(describing: focused))")
    }

    func stepDrag(_ t: Double) {
        guard let drop, t >= Self.liftAt else { return }
        let point = t <= Self.arriveAt ? dragPoint(t) : (path?.end ?? pointer)
        pointer = point
        let local = split.convert(point, from: surface)
        let inside = split.bounds.contains(local)
        let wasReplace = drop.replace
        let hadAppeared = drop.appeared
        if inside {
            if card == nil, let row {
                if let image = SplitDropPlaceholderCard.image(icon: row.splitDropCardContent.icon, title: row.splitDropCardContent.title,
                                                              incomingPane: drop.incomingPaneSize) {
                    card = (image, image.size)
                    beats.append((t, "Drag enters the panes: the row image turns into the placeholder card; the focus ring steps aside"))
                    if let focused { fadeRing(focused, to: 0, t) }
                }
            }
            drop.update(at: local, t)
            if hadAppeared == nil, let appeared = drop.appeared, let target = drop.intent.shown?.target {
                beats.append((appeared, "The pointer eases onto the picnic plan's bottom edge: hover intent opens \(target) and the panes make room"))
            }
            if let row, let card, let size = SplitDropPlaceholderCard.size(forIncomingPane: drop.incomingPaneSize), size != card.size,
               let image = SplitDropPlaceholderCard.image(icon: row.splitDropCardContent.icon, title: row.splitDropCardContent.title,
                                                          incomingPane: drop.incomingPaneSize) {
                self.card = (image, image.size)
                beats.append((t, "Placeholder card reshapes for the seat under the picnic plan"))
            }
        } else if card != nil {
            drop.leave(t)
            card = nil
        }
        if wasReplace != drop.replace {
            if let old = wasReplace { fadeRing(old, to: 0, t, width: 3) }
            if let new = drop.replace { fadeRing(new, to: 1, t, width: 3) }
        }
        let frames = drop.presentedPanes(t)
        let shift = zip(frames, drop.original).map { max(abs($0.minX - $1.minX), abs($0.minY - $1.minY),
                                                         abs($0.width - $1.width), abs($0.height - $1.height)) }.max() ?? 0
        trail.append([t, Double(point.x), Double(point.y), Double(shift), drop.presentedRegion(t) == nil ? 0 : 1].map { ($0 * 1000).rounded() / 1000 })
        for (view, frame) in zip(drop.panes, frames) where view.frame != frame {
            view.frame = frame
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            if let pane = view as? PaneStandIn { pane.page.needsDisplay = true }
        }
        placeShadows(frames)
        showGrips(!drop.reserving)
        if let region = drop.presentedRegion(t) {
            drags.region = (surface.convert(region.frame, from: split), region.opacity)
        } else { drags.region = nil }
    }

    func placeShadows(_ frames: [NSRect]) {
        guard let drop else { return }
        let shadows = (split.layer?.sublayers ?? []).filter { $0.name == "Split pane shadow" }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, original) in drop.original.enumerated() {
            let home = ContentShadowImage.frame(around: original)
            guard let layer = shadows.first(where: { $0.frame.origin.x.rounded() == home.origin.x.rounded() && abs($0.frame.minY - home.minY) < 0.5
                && abs($0.frame.width - home.width) < 0.5 && abs($0.frame.height - home.height) < 0.5 }) ?? shadowMap[index] else { continue }
            shadowMap[index] = layer
            layer.frame = ContentShadowImage.frame(around: frames[index])
        }
        CATransaction.commit()
    }
    var shadowMap: [Int: CALayer] = [:]

    func step(_ t: Double) {
        while nextEvent < events.count, events[nextEvent].0 <= t + 1e-9 {
            events[nextEvent].2(); nextEvent += 1
        }
        if let move {
            let u = CGFloat(easeInOut((t - move.t0) / (move.t1 - move.t0)))
            pointer = NSPoint(x: move.from.x + (move.to.x - move.from.x) * u, y: move.from.y + (move.to.y - move.from.y) * u)
            if t >= move.t1 { self.move = nil }
        }
        if t >= Self.pressAt && t < Self.liftAt { pointer = NSPoint(x: grab.x + CGFloat((t - Self.pressAt) / (Self.liftAt - Self.pressAt)) * 3, y: grab.y) }
        stepDrag(t)
        if drop != nil, t >= Self.liftAt {
            let offset = NSPoint(x: pointer.x - grab.x, y: pointer.y - grab.y)
            if let card {
                let frame = NSRect(x: rowFrame.minX + offset.x, y: rowFrame.maxY + offset.y - card.size.height,
                                   width: card.size.width, height: card.size.height)
                drags.image = (card.image, frame)
            } else if let rowImage {
                drags.image = (rowImage, rowFrame.offsetBy(dx: offset.x, dy: offset.y))
            }
        } else { drags.image = nil; if self.drop == nil { drags.region = nil } }
        for fade in ringFades {
            let u = Float(caDefault((t - fade.start) / 0.11))
            fade.pane.highlight.layer.opacity = fade.to == 1 ? u : 1 - u
        }
        ringFades.removeAll { t - $0.start > 0.11 }
        if menuOpen {
            let rects = MenuMetrics.rowRects(menuRows, origin: menuOrigin)
            var highlighted = t >= Self.menuAt + 0.1 ? rects.firstIndex { $0.contains(pointer) } : nil
            if let index = highlighted, !menuRows[index].enabled || menuRows[index].separator { highlighted = nil }
            let pick = menuRows.firstIndex { $0.title == Self.pick }
            if t >= Self.chooseAt - 0.05 { highlighted = pick }
            if t >= Self.chooseAt && t < Self.chooseAt + 0.07 { highlighted = nil }
            var alpha: CGFloat = 1
            if t >= Self.chooseAt + 0.07 { alpha = 1 - CGFloat(clamp01((t - Self.chooseAt - 0.07) / 0.15)) }
            overlay.panel = alpha > 0 ? Overlay.Menu(origin: menuOrigin, rows: menuRows, highlighted: highlighted, alpha: alpha) : nil
        }
        if bar.overlay.shown {
            let query = Self.keys.last(where: { $0.0 <= t })?.1 ?? ""
            let lastKey = max(Self.pendingAt, Self.keys.last(where: { $0.0 <= t })?.0 ?? Self.pendingAt)
            let idle = t - lastKey
            var opacity: CGFloat = 1
            if idle > 0.5 {
                let phase = (idle - 0.5).truncatingRemainder(dividingBy: 1.0)
                let fade = 0.12
                if phase < 0.5 { opacity = phase < fade ? CGFloat(1 - phase / fade) : 0 }
                else { opacity = phase - 0.5 < fade ? CGFloat((phase - 0.5) / fade) : 1 }
            }
            bar.show(query, caretOpacity: opacity)
        }
        overlay.rings = panes.compactMap { pane in
            let layer = pane.highlight.layer
            guard let path = layer.path, let color = layer.strokeColor, layer.opacity > 0, !layer.isHidden else { return nil }
            return Overlay.Ring(frame: paneRect(pane), radius: pane.layer?.cornerRadius ?? 0, path: path, width: layer.lineWidth,
                                color: color, opacity: CGFloat(layer.opacity))
        }
        scene.pointer.location = pointerShown ? pointer : nil
        scene.pointer.needsDisplay = true
        drags.needsDisplay = true
        overlay.needsDisplay = true
        surface.needsDisplay = true
    }
}
