import AppKit
@testable import Parc
import ParcCore

@MainActor final class SplitFilm {
    static let pages = "../pages/png/"
    static let fps = 60.0
    static let duration = 9.5

    let scene: BrowserScene
    let host: NSView
    let split: ParcSplitView
    let margin: SplitMarginHandleView
    let overlay: Overlay
    let palette: ThemeChromePalette
    let arts: [PageArt]
    var panes: [PaneStandIn] = []
    var tabs: [BrowserTab] = []
    var factors: [Double] = [1]
    var stacks: BrowserSplitStacks?
    var focused = 0
    let groupID = UUID()
    var log: [String] = []
    var beats: [(Double, String)] = []

    var hoverDivider: Int?
    var hoverOn = -10.0
    var hoverOff: Double?
    var ringFades: [(pane: PaneStandIn, start: Double, to: Float)] = []
    var reveal: (pane: PaneStandIn, start: Double)?
    var pointer = NSPoint(x: 940, y: 560)
    var move: (t0: Double, t1: Double, from: NSPoint, to: NSPoint)?
    var drag: (t0: Double, t1: Double, start: NSPoint, distance: CGFloat, last: NSPoint)?
    var glide: (t0: Double, from: [CGFloat], to: [CGFloat])?
    var pillAlpha: (start: Double, from: CGFloat, to: CGFloat)?
    var pillPane: PaneStandIn?
    var menuOpen: Double?
    var menuRows: [MenuRow] = []
    var menuOrigin = NSPoint.zero
    var toast: (image: NSImage, card: NSRect, region: NSRect, start: Double)?
    var events: [(Double, String, () -> Void)] = []
    var nextEvent = 0

    init() {
        scene = BrowserScene(size: NSSize(width: 1440, height: 900), windowRect: NSRect(x: 80, y: 18, width: 1280, height: 840),
                             scale: 2, pagePath: "")
        palette = scene.themeSurface.palette
        scene.surface.drawPage = { _ in }
        let card = scene.surface.pageCard
        arts = [
            PageArt(path: Self.pages + "article.png", band: (270, 1030), maxScale: card.width / 1300),
            PageArt(path: Self.pages + "picnic.png", band: (20, 680), maxScale: card.width / 1300, height: 822, baseSample: (4, 800)),
            PageArt(path: Self.pages + "map.png", band: (0, 400), maxScale: 1, mirrors: true),
            PageArt(path: Self.pages + "kite.png", band: (290, 1010), maxScale: card.width / 1300),
        ]
        host = NSView(frame: card)
        host.wantsLayer = true
        host.layer?.cornerRadius = PageCard.cornerRadius
        host.layer?.cornerCurve = .continuous
        split = ParcSplitView(frame: host.bounds)
        host.addSubview(split)
        scene.surface.addSubview(host, positioned: .below, relativeTo: scene.edge)
        margin = SplitMarginHandleView(frame: NSRect(x: card.maxX, y: card.minY, width: 10, height: card.height))
        margin.windowAllows = true
        scene.surface.addSubview(margin, positioned: .below, relativeTo: scene.edge)
        overlay = Overlay(frame: scene.surface.bounds)
        overlay.pillBackground = palette.background.usingColorSpace(.sRGB).map { $0.withAlphaComponent(1) } ?? .white
        scene.surface.addSubview(overlay, positioned: .below, relativeTo: scene.pointer)
        split.onSnapTransition = {}
        split.prepareDividerResize = { [unowned self] in { factors in self.factors = factors; return true } }
        split.marginHandle = margin
        let first = PaneStandIn(art: arts[0])
        panes = [first]
        tabs = [scene.scenario.selected]
        configureToolbar(first, index: 0, loading: false)
        relayout()
        scene.pointer.location = pointer
        schedule()
    }

    var surface: WindowSurface { scene.surface }

    func relayout() {
        _ = split.reconcileArrangedSubviews(panes)
        let divided = panes.count > 1
        for pane in panes { pane.showsBar = divided }
        split.configure(orientation: .horizontal, factors: factors, stacks: stacks)
        split.configureBacking(in: host, hasTranslucentPane: false)
        surface.showsCardShadow = !divided
        surface.needsDisplay = true
        for (index, pane) in panes.enumerated() {
            pane.highlight.color = palette.isDark ? palette.shaded : palette.shadedDark
            pane.highlight.update(display: divided && index == focused, width: 2)
            pane.needsLayout = true
            pane.layoutSubtreeIfNeeded()
        }
        afterLayout(0)
    }

    func afterLayout(_ t: Double) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for layer in split.layer?.sublayers ?? [] where layer.name == "Split pane shadow" {
            ContentShadowImage.apply(to: layer, scale: 2)
        }
        CATransaction.commit()
        let local = split.convert(pointer, from: surface)
        split.updateDividerHover(at: hoverDivider == nil ? nil : local, animated: false)
        applyGrips(t)
        for pane in panes { pane.page.needsDisplay = true }
    }

    func gripAlpha(_ index: Int, _ t: Double) -> CGFloat {
        guard hoverDivider == index else { return 0.2 }
        var f = clamp01((t - hoverOn) / 0.16)
        if let hoverOff { f = min(f, 1 - clamp01((t - hoverOff) / 0.16)) }
        return 0.2 + 0.3 * CGFloat(f)
    }

    func applyGrips(_ t: Double) {
        let grips = (split.layer?.sublayers ?? []).filter { $0.name == "Split divider grip" }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, grip) in grips.enumerated() {
            grip.removeAllAnimations()
            grip.backgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: gripAlpha(index, t)).cgColor
        }
        CATransaction.commit()
    }

    func configureToolbar(_ pane: PaneStandIn, index: Int, loading: Bool) {
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

    func renderSidebar() {
        var state = scene.scenario.state
        let base = state.tabs.filter { tab in !tabs.dropFirst().contains { $0.id == tab.id } }
        let anchor = base.firstIndex { $0.id == tabs[0].id }!
        var all = base
        all.replaceSubrange(anchor...anchor, with: tabs)
        state.tabs = all
        if tabs.count > 1 {
            state.splitLayouts = [BrowserSplitLayout(id: groupID, spaceID: scene.scenario.work.id, tabIDs: tabs.map(\.id),
                                                     orientation: .horizontal, widthFactors: factors, stacks: stacks)]
            state.selectedTabIDs = tabs.map(\.id)
        }
        let sidebar = scene.sidebar
        sidebar.render(state: state, focusedTabID: tabs[focused].id, loading: [], canBack: focused == 0, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        let end = Date().addingTimeInterval(0.25)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        sidebar.needsLayout = true
        sidebar.layoutSubtreeIfNeeded()
    }

    func paneRect(_ pane: PaneStandIn) -> NSRect { surface.convert(pane.bounds, from: pane) }
    func pageRect(_ pane: PaneStandIn) -> NSRect { surface.convert(pane.page.bounds, from: pane.page) }
    func pagePoint(_ pane: PaneStandIn, _ px: CGFloat, _ py: CGFloat) -> NSPoint {
        let local = pane.page.art.point(px, py, in: pane.page.bounds.size)
        return surface.convert(local, from: pane.page)
    }

    func setFocus(_ index: Int, _ t: Double, fadeIn: Bool) {
        let previous = focused
        focused = index
        guard panes.count > 1 else { return }
        for (i, pane) in panes.enumerated() {
            pane.highlight.update(display: i == index, width: 2)
            pane.toolbar.setControlsRevealed(i == index, duration: nil)
        }
        if previous != index, panes.indices.contains(previous) {
            ringFades.append((panes[previous], t, 0))
            panes[previous].highlight.layer.opacity = 1
        }
        if fadeIn {
            ringFades.append((panes[index], t, 1))
            panes[index].highlight.layer.opacity = 0
        }
    }

    func addPane(_ art: Int, after index: Int, _ t: Double) {
        let pane = PaneStandIn(art: arts[art])
        pane.page.painted = false
        let at = index + 1
        var weights = factors
        weights.insert(1 / Double(factors.count), at: at)
        let total = weights.reduce(0, +)
        factors = weights.map { $0 / total }
        panes.insert(pane, at: at)
        tabs.insert(scene.scenario.panes[art - 1], at: at)
        focused = at
        for (i, existing) in panes.enumerated() { configureToolbar(existing, index: i, loading: existing === pane) }
        relayout()
        if panes.indices.contains(index), panes.count > 2 {
            ringFades.append((panes[index], t, 0))
            panes[index].highlight.layer.opacity = 1
        }
        afterLayout(t)
        renderSidebar()
        log.append(String(format: "%.2f add pane %d -> factors %@ frames %@", t, art, factors.map { String(format: "%.4f", $0) }.joined(separator: ","),
                          panes.map { "\(Int($0.frame.minX))-\(Int($0.frame.maxX))" }.joined(separator: " ")))
    }

    func paint(_ index: Int) {
        panes[index].page.painted = true
        configureToolbar(panes[index], index: index, loading: false)
    }

    func at(_ t: Double, _ name: String, _ action: @escaping () -> Void) { events.append((t, name, action)) }

    func moveTo(_ t0: Double, _ t1: Double, _ target: @escaping () -> NSPoint) {
        at(t0, "") { [unowned self] in move = (t0, t1, pointer, target()) }
    }

    func dividerPoint(_ divider: Int, y: CGFloat) -> NSPoint {
        let pane = panes[divider]
        let local = NSPoint(x: pane.frame.maxX + split.dividerThickness / 2, y: y)
        return surface.convert(local, from: split)
    }

    func schedule() {
        let link = NSPoint(x: 700, y: 891)
        moveTo(0.0, 0.45) { [unowned self] in pagePoint(panes[0], link.x, link.y) }
        at(0.45, "Pointer on the article link (pointing hand)") { [unowned self] in scene.pointer.cursor = .pointingHand }
        at(0.95, "Option hint pill fades in (0.5 s after hover)") { [unowned self] in pillPane = panes[0]; pillAlpha = (0.95, 0, 1) }
        at(1.40, "Option-click (Chromium waits 0.5 s)") {}
        at(1.90, "Split: two side-by-side panes (instant)") { [unowned self] in
            addPane(1, after: 0, 1.90)
            scene.pointer.cursor = .arrow
            pillAlpha = (1.90, 1, 0)
        }
        at(2.15, "Picnic pane first paint (cut)") { [unowned self] in paint(1) }
        moveTo(2.30, 2.75) { [unowned self] in pagePoint(panes[1], 597, 34) }
        at(2.75, "") { [unowned self] in scene.pointer.cursor = .pointingHand }
        at(2.85, "Option-click a link in the picnic pane") {}
        at(3.35, "Third pane added (instant)") { [unowned self] in addPane(2, after: 1, 3.35); scene.pointer.cursor = .arrow }
        at(3.55, "Map pane first paint (cut)") { [unowned self] in paint(2) }
        at(3.55, "") { [unowned self] in scene.pointer.cursor = .arrow }
        moveTo(3.55, 3.95) { [unowned self] in pagePoint(panes[2], 112, 48) }
        at(3.95, "") { [unowned self] in scene.pointer.cursor = .pointingHand }
        at(4.00, "Option-click a place in the map pane") {}
        at(4.50, "Fourth pane added (instant): four columns") { [unowned self] in addPane(3, after: 2, 4.50); scene.pointer.cursor = .arrow }
        at(4.75, "Kite pane first paint (cut)") { [unowned self] in paint(3) }
        at(4.75, "") { [unowned self] in scene.pointer.cursor = .arrow }
        moveTo(4.75, 5.15) { [unowned self] in dividerPoint(0, y: 430) }
        at(5.15, "Pointer on the first divider: grip 0.2 -> 0.5 (0.16 s)") { [unowned self] in
            scene.pointer.cursor = .resizeLeftRight; hoverDivider = 0; hoverOn = 5.15; hoverOff = nil
        }
        at(5.30, "Live divider drag via ParcSplitView") { [unowned self] in
            let local = split.convert(pointer, from: surface)
            let began = split.beginDividerResize(at: local)
            split.beginDividerPan(at: local)
            log.append("drag began \(began) at \(local)")
            drag = (5.30, 5.80, pointer, 30, pointer)
        }
        at(5.80, "Drag released (factors committed)") { [unowned self] in
            if let drag { pointer = NSPoint(x: drag.start.x + drag.distance, y: drag.start.y) }
            self.drag = nil
            split.finishDividerResize(commit: true)
            afterLayout(5.80)
            log.append(String(format: "5.80 drag committed factors %@ frames %@", factors.map { String(format: "%.4f", $0) }.joined(separator: ","),
                              panes.map { "\(Int($0.frame.minX))-\(Int($0.frame.maxX))" }.joined(separator: " ")))
        }
        moveTo(5.80, 5.92) { [unowned self] in dividerPoint(0, y: 430) }
        at(5.95, "Double-click the divider (first press)") {}
        at(6.07, "Second press: pair evens over 0.2 s ease-out") { [unowned self] in
            let from = panes.map(\.frame.width)
            let pair = (from[0] + from[1]) / 2
            var to = from; to[0] = pair; to[1] = pair
            glide = (6.07, from, to)
        }
        at(6.40, "Pointer leaves the divider: grip 0.5 -> 0.2") { [unowned self] in
            hoverOff = 6.40; scene.pointer.cursor = .arrow
        }
        moveTo(6.40, 6.85) { [unowned self] in
            let button = panes[1].splitButton!
            return surface.convert(NSPoint(x: button.bounds.midX + 1, y: button.bounds.midY + 1), from: button)
        }
        at(6.85, "") { [unowned self] in scene.pointer.cursor = .pointingHand }
        at(6.95, "Click the split menu button: pane B takes focus, menu opens") { [unowned self] in
            scene.pointer.cursor = .arrow
            hoverDivider = nil
            setFocus(1, 6.95, fadeIn: true)
            reveal = nil
            for view in panes[1].revealViews { view.alphaValue = 1 }
            renderSidebar()
            let menu = SplitPaneMenu.make(orientation: .horizontal, index: 1, count: panes.count, prepare: { _ in {} })
            menuRows = menu.items.map { MenuRow(title: $0.title, image: $0.image, enabled: $0.isEnabled, separator: $0.isSeparatorItem) }
            let button = panes[1].splitButton!
            menuOrigin = surface.convert(NSPoint(x: 0, y: button.isFlipped ? button.bounds.maxY : button.bounds.minY), from: button)
            menuOpen = 6.95
            log.append("menu origin \(menuOrigin) rows \(menuRows.map { $0.separator ? "—" : "\($0.title)\($0.enabled ? "" : " (disabled)")" })")
        }
        moveTo(7.00, 7.45) { [unowned self] in
            let rects = MenuMetrics.rowRects(menuRows, origin: menuOrigin)
            let index = menuRows.firstIndex { $0.title == "Copy Links" }!
            return NSPoint(x: rects[index].minX + 64, y: rects[index].midY + 2)
        }
        at(7.50, "Choose Copy Links (item blinks, menu fades)") {}
        at(7.70, "Copied Links toast springs in (ParcToastCard)") { [unowned self] in
            let region = paneRect(panes[1])
            let size = NSSize(width: region.width, height: region.height / 2)
            let urls = tabs.compactMap { URL(string: $0.url) }
            if let art = ToastArt.render(urls: urls, theme: scene.scenario.work.theme, size: size) {
                toast = (art.image, art.card, NSRect(origin: region.origin, size: size), 7.70)
                log.append("toast card \(art.card) in region \(NSRect(origin: region.origin, size: size))")
            } else { log.append("toast render failed") }
        }
        at(8.25, "Hold: four equal panes, toast up, split group row in the sidebar") {}
        events.sort { $0.0 < $1.0 }
        beats = events.filter { !$0.1.isEmpty }.map { ($0.0, $0.1) }
    }

    func step(_ t: Double) {
        while nextEvent < events.count, events[nextEvent].0 <= t + 1e-9 {
            events[nextEvent].2(); nextEvent += 1
        }
        if let move {
            let u = CGFloat(easeInOut((t - move.t0) / (move.t1 - move.t0)))
            pointer = NSPoint(x: move.from.x + (move.to.x - move.from.x) * u, y: move.from.y + (move.to.y - move.from.y) * u)
            if t >= move.t1 { self.move = nil }
        }
        if var drag {
            let u = CGFloat(easeInOut((t - drag.t0) / (drag.t1 - drag.t0)))
            pointer = NSPoint(x: drag.start.x + drag.distance * u, y: drag.start.y)
            let velocity = (pointer.x - drag.last.x) * CGFloat(Self.fps)
            drag.last = pointer
            self.drag = drag
            split.updateDividerResize(at: split.convert(pointer, from: surface), velocity: velocity)
            afterLayout(t)
        }
        if let glide {
            let u = CGFloat(easeOut((t - glide.t0) / 0.2))
            let lengths = zip(glide.from, glide.to).map { $0 + ($1 - $0) * u }
            let total = lengths.reduce(0, +)
            if t >= glide.t0 + 0.2 {
                var final = factors
                let half = (final[0] + final[1]) / 2
                final[0] = half; final[1] = half
                factors = final
                self.glide = nil
                log.append(String(format: "%.2f glide done factors %@", t, factors.map { String(format: "%.4f", $0) }.joined(separator: ",")))
            } else {
                factors = lengths.map { Double($0 / total) }
            }
            split.configure(orientation: .horizontal, factors: factors, stacks: stacks)
            afterLayout(t)
            pointer = dividerPoint(0, y: 430)
        }
        if hoverDivider != nil { afterLayout(t) } else { applyGrips(t) }
        if panes.count == 4, menuOpen == nil, reveal == nil, t > 6.40 {
            let bar = paneRect(panes[1])
            let region = NSRect(x: bar.minX, y: bar.minY - 40, width: bar.width, height: 32 + 40 + 28)
            if region.contains(pointer) { reveal = (panes[1], t); beats.append((t, "Pointer enters pane B's top bar: controls fade in (0.18 s)")) }
        }
        if let reveal, menuOpen == nil {
            let alpha = CGFloat(easeInOut((t - reveal.start) / 0.18))
            for view in reveal.pane.revealViews { view.alphaValue = alpha }
        }
        for fade in ringFades {
            let u = Float(caDefault((t - fade.start) / 0.11))
            fade.pane.highlight.layer.opacity = fade.to == 1 ? u : 1 - u
        }
        ringFades.removeAll { t - $0.start > 0.11 }
        if let pillAlpha, let pillPane {
            let u = CGFloat(clamp01((t - pillAlpha.start) / 0.25))
            let alpha = pillAlpha.from + (pillAlpha.to - pillAlpha.from) * u
            overlay.pill = Overlay.Pill(content: pageRect(pillPane), url: tabs.count > 1 ? tabs[1].url : scene.scenario.panes[0].url, alpha: alpha)
        }
        if menuOpen != nil {
            let rects = MenuMetrics.rowRects(menuRows, origin: menuOrigin)
            var highlighted = t >= 7.0 ? rects.firstIndex { $0.contains(pointer) } : nil
            if let index = highlighted, !menuRows[index].enabled || menuRows[index].separator { highlighted = nil }
            let copy = menuRows.firstIndex { $0.title == "Copy Links" }
            if t >= 7.45 { highlighted = copy }
            if t >= 7.50 && t < 7.57 { highlighted = nil }
            var alpha: CGFloat = 1
            if t >= 7.57 { alpha = 1 - CGFloat(clamp01((t - 7.57) / 0.15)) }
            overlay.panel = alpha > 0 ? Overlay.Menu(origin: menuOrigin, rows: menuRows, highlighted: highlighted, alpha: alpha) : nil
        }
        if let toast {
            let s = spring(t - toast.start)
            let frame = toast.region
            let card = toast.card.offsetBy(dx: frame.minX, dy: frame.minY)
            let anchor = NSPoint(x: card.midX + 4, y: card.minY - 8 + 0.1 * (card.height + 8))
            overlay.toast = Overlay.Toast(image: toast.image, frame: frame, anchor: anchor, scale: CGFloat(s), alpha: CGFloat(clamp01(s)))
        }
        overlay.rings = panes.count > 1 ? panes.compactMap { pane in
            let layer = pane.highlight.layer
            guard let path = layer.path, let color = layer.strokeColor, layer.opacity > 0, !layer.isHidden else { return nil }
            return Overlay.Ring(frame: paneRect(pane), radius: pane.layer?.cornerRadius ?? 0, path: path, width: layer.lineWidth,
                                color: color, opacity: CGFloat(layer.opacity))
        } : []
        scene.pointer.location = pointer
        scene.pointer.needsDisplay = true
        overlay.needsDisplay = true
        surface.needsDisplay = true
    }
}
