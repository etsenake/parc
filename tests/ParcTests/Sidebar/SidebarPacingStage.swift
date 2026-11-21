import AppKit
import QuartzCore
@testable import Parc
@testable import ParcCore

@MainActor final class SidebarPacingTally {
    var layouts: [String: Int] = [:]
    var labelSizes: [String: Int] = [:]
    var rendererSizes = 0
    func reset() { layouts = [:]; labelSizes = [:]; rendererSizes = 0 }
    var mostLayouts: Int { layouts.values.max() ?? 0 }
    var mostLabelSizes: Int { labelSizes.values.max() ?? 0 }
}

@MainActor class SidebarPacingHostView: NSView {
    var onLayout: (() -> Void)?
    weak var tally: SidebarPacingTally?
    override var isFlipped: Bool { true }
    override func layout() {
        tally?.layouts[identifier?.rawValue ?? "?", default: 0] += 1
        super.layout(); onLayout?()
    }
}

@MainActor final class SidebarPacingDrawnStrip: SidebarPacingHostView {
    override func draw(_ dirtyRect: NSRect) { NSColor.separatorColor.setFill(); dirtyRect.fill() }
}

@MainActor final class SidebarPacingLabel: NSTextField {
    weak var tally: SidebarPacingTally?
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { tally?.labelSizes[identifier?.rawValue ?? "?", default: 0] += 1 }
        super.setFrameSize(newSize)
    }
}

@MainActor final class SidebarPacingRenderer: NSView {
    weak var tally: SidebarPacingTally?
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { tally?.rendererSizes += 1 }
        super.setFrameSize(newSize)
    }
}

@MainActor final class SidebarPacingPage: NSView {
    let host = SidebarPacingRenderer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; host.wantsLayer = true; host.identifier = .init("page.renderWidget"); addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func resizeSubviews(withOldSize oldSize: NSSize) {}
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        for subview in subviews { subview.frame = bounds }
    }
}

@MainActor final class SidebarPacingPane: SidebarPacingHostView {
    let content = SidebarPacingHostView(), page = SidebarPacingPage(frame: .zero)
    let developerToolbar = SidebarPacingDrawnStrip(), browserToolbar = SidebarPacingDrawnStrip(), failure = SidebarPacingDrawnStrip()
    let toolbarField = SidebarPacingLabel(string: "parc://start"), failureTitle = SidebarPacingLabel(labelWithString: "This page couldn’t load")
    let header = NSButton(title: "", target: nil, action: nil), headerLabel = SidebarPacingLabel(labelWithString: "A long page title for the slot")
    let grabber = NSView()

    init(visibleStrip: Bool, tally: SidebarPacingTally) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = NSColor.white.cgColor
        for (view, name) in [(content, "pane.content"), (page, "page"), (developerToolbar, "developerToolbar"), (browserToolbar, "browserToolbar"),
                             (failure, "failure"), (toolbarField, "browserToolbar.field"), (failureTitle, "failure.title"),
                             (header, "header"), (headerLabel, "header.label"), (grabber, "grabber")] as [(NSView, String)] {
            view.identifier = .init(name)
        }
        for view in [self, content, developerToolbar, browserToolbar, failure] as [SidebarPacingHostView] { view.tally = tally }
        for label in [toolbarField, failureTitle, headerLabel] { label.tally = tally }
        page.host.tally = tally
        addSubview(content); addSubview(grabber); addSubview(header); header.addSubview(headerLabel)
        addSubview(developerToolbar); addSubview(browserToolbar); browserToolbar.addSubview(toolbarField)
        content.addSubview(page); content.addSubview(failure); failure.addSubview(failureTitle)
        SidebarMotionController.pinDrawnContent(failure, to: .scaleAxesIndependently)
        SidebarMotionController.pinDrawnContent(failureTitle, to: .center)
        header.isBordered = false; header.isHidden = true
        developerToolbar.isHidden = !visibleStrip; browserToolbar.isHidden = true; failure.isHidden = true
        content.onLayout = { [weak self] in
            guard let self else { return }
            for view in [page, failure] as [NSView] { view.frame = content.bounds }
            failureTitle.frame = NSRect(x: 0, y: content.bounds.midY, width: content.bounds.width, height: 24)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let strip: CGFloat = developerToolbar.isHidden ? 0 : 40
        browserToolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 0)
        toolbarField.frame = NSRect(x: 60, y: 0, width: max(0, bounds.width - 120), height: 0)
        developerToolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: strip)
        header.frame = NSRect(x: 13, y: 0, width: max(0, min(bounds.width - 80, 900)), height: 26)
        headerLabel.frame = header.bounds
        content.frame = NSRect(x: 0, y: strip, width: bounds.width, height: bounds.height - strip)
        grabber.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 10)
    }
}

@MainActor final class SidebarPacingEmptyContent: SidebarPacingHostView {
    let highlight = CAShapeLayer()
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; highlight.fillColor = nil; highlight.opacity = 0; layer?.addSublayer(highlight)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateLayer() { layer?.backgroundColor = NSColor(white: 1, alpha: 0.1).cgColor }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        highlight.frame = bounds; highlight.path = CGPath(rect: bounds, transform: nil)
        CATransaction.commit()
    }
}

@MainActor final class SidebarPacingStage {
    enum Pass { case full, preparation, geometry }
    let tally = SidebarPacingTally()
    let completions = SidebarMotionCompletions()
    let motion: SidebarMotionController
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1470, height: 831), styleMask: [.borderless], backing: .buffered, defer: false)
    let rootView = ThemeRendererView(), sidebarContainer = ThemeRendererView(), sidebar = SidebarPacingHostView()
    let lights = WindowStandardButtons(), toggle = NSButton(title: "", target: nil, action: nil)
    let rows: [SidebarPacingLabel]
    let pageHost = SidebarPacingHostView(), splitView = SidebarPacingHostView(), pane: SidebarPacingPane, empty = SidebarPacingEmptyContent()
    let pageShadow = PageCardShadowView()
    let loadingIndicator = PageLoadingIndicatorHost(), findHost = NSView()
    let width: CGFloat = 228
    var presentation = SidebarPresentation.locked
    var pass = Pass.full
    var motionVisible = false, floatingSurface = false, revealsAnchored = false
    var settled = 0
    var didPrepare: (() -> Void)?, willSettle: (() -> Void)?
    var passesTwice = false

    init(showsPage: Bool = false, pinsSurface: Bool = true, visibleStrip: Bool = false) {
        motion = SidebarMotionController(completions: completions)
        pane = SidebarPacingPane(visibleStrip: visibleStrip, tally: tally)
        rows = (0..<12).map { index in
            let row = SidebarPacingLabel(labelWithString: "Sidebar row \(index)")
            row.identifier = .init("sidebar.row.\(index)")
            return row
        }
        for (view, name) in [(rootView, "root"), (sidebarContainer, "sidebarContainer"), (sidebar, "sidebar"), (pageHost, "pageHost"),
                             (splitView, "splitView"), (pane, "pane"), (empty, "emptyContent"), (pageShadow, "pageShadow"),
                             (loadingIndicator, "loadingIndicator"), (findHost, "findHost"), (toggle, "toggle")] as [(NSView, String)] {
            view.identifier = .init(name)
        }
        for view in [sidebar, pageHost, splitView, empty] as [SidebarPacingHostView] { view.tally = tally }
        rows.forEach { $0.tally = tally }
        window.isReleasedWhenClosed = false
        window.contentView = rootView
        rootView.wantsLayer = true
        rootView.layer?.speed = 0
        rootView.addSubview(pageShadow); rootView.addSubview(pageHost); rootView.addSubview(loadingIndicator); rootView.addSubview(findHost)
        rootView.addSubview(sidebarContainer)
        sidebarContainer.coordinateSpace = rootView
        if let color = ThemeColor(red: 0.42, green: 0.36, blue: 0.86) { rootView.theme = .singleColor(color); sidebarContainer.theme = .singleColor(color) }
        sidebarContainer.addSubview(sidebar)
        if pinsSurface { SidebarMotionController.pinSurface(of: sidebarContainer, except: sidebar) }
        sidebar.addSubview(lights); sidebar.addSubview(toggle); rows.forEach(sidebar.addSubview)
        sidebar.onLayout = { [weak self] in
            guard let self else { return }
            let bar = SidebarChromeLayout.toolbar(width: sidebar.bounds.width, windowButtons: WindowStandardButtons.stackSize, showsNavigation: true)
            lights.frame = bar.windowButtons ?? .zero; toggle.frame = bar.toggle ?? .zero
            for (index, row) in rows.enumerated() {
                row.frame = NSRect(x: 16, y: 90 + CGFloat(index) * 36, width: sidebar.bounds.width - 32, height: 20)
            }
        }
        pageHost.wantsLayer = true; pageHost.layer?.cornerRadius = PageCard.cornerRadius; pageHost.layer?.cornerCurve = .continuous
        pageHost.layer?.masksToBounds = true
        pageHost.layer?.backgroundColor = (showsPage ? NSColor.white : .clear).cgColor
        pageHost.addSubview(splitView)
        splitView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([splitView.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
                                     splitView.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
                                     splitView.topAnchor.constraint(equalTo: pageHost.topAnchor),
                                     splitView.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor)])
        let content: NSView = showsPage ? pane : empty
        splitView.addSubview(content)
        splitView.onLayout = { [weak self] in if let self { content.frame = splitView.bounds } }
        findHost.isHidden = true
        rootView.onLayout = { [weak self] in self?.layoutChrome() }
        layoutChrome()
        rootView.layoutSubtreeIfNeeded(); commit()
    }

    var participants: [NSView] { [sidebarContainer, pageHost, pageShadow, findHost, loadingIndicator] }

    func frames() -> SidebarChromeFrames {
        let placement = SidebarPresentationFrame(presentation, inMotion: motionVisible, floatingSurface: floatingSurface, revealsAnchored: revealsAnchored)
        return SidebarChromeFrames(bounds: rootView.bounds, sidebarWidth: width, presentation: presentation, placement: placement)
    }

    func layoutChrome() {
        let frames = frames()
        if pass == .geometry {
            sidebarContainer.frame = frames.sidebar
            sidebar.frame = sidebarContainer.bounds
            if floatingSurface && presentation == .locked { sidebarContainer.docksFloatingSurface = true }
            pageHost.frame = frames.pageHost; pageShadow.place(around: frames.pageHost)
            loadingIndicator.frame = PageLoadingIndicatorHost.frame(pageHost: frames.pageHost)
            pageHost.needsLayout = true
            pageHost.layoutSubtreeIfNeeded()
            return
        }
        let surface = presentation == .floating || floatingSurface
        if sidebarContainer.drawsBackground != surface { sidebarContainer.drawsBackground = surface }
        sidebarContainer.frame = frames.sidebar
        sidebarContainer.floatingCornerRadius = surface ? FloatingSidebarSurface.cornerRadius : nil
        sidebarContainer.docksFloatingSurface = pass == .full && floatingSurface && presentation == .locked
        if pass == .full { sidebarContainer.preparesFloatingDock = false }
        sidebar.layer?.cornerRadius = surface ? FloatingSidebarSurface.cornerRadius : 0
        sidebar.clipsToBounds = surface
        if pass == .full { sidebarContainer.invalidateCoordinates() }
        sidebar.frame = sidebarContainer.bounds
        pageHost.frame = frames.pageHost; pageShadow.place(around: frames.pageHost)
        loadingIndicator.frame = PageLoadingIndicatorHost.frame(pageHost: frames.pageHost)
        guard pass == .full else { return }
        pageHost.layoutSubtreeIfNeeded()
    }

    func present(_ next: SidebarPresentation) {
        let transition = SidebarTransition(from: presentation, to: next)
        motionVisible = true
        floatingSurface = transition.keepsFloatingSurface
        revealsAnchored = transition.revealsAnchored
        pass = .preparation
        layoutChrome()
        sidebarContainer.preparesFloatingDock = transition.docksFloatingSurface
        didPrepare?()
        pass = .geometry
        motion.animate(layoutRoot: rootView, views: participants, style: transition.style, flushesPreviousLayout: transition.flushesPreparation) {
            presentation = next
            if passesTwice {
                let final = frames().pageHost
                pageHost.frame = final.insetBy(dx: 20, dy: 0); pageHost.layoutSubtreeIfNeeded()
            }
            layoutChrome()
        } completion: { [weak self] in
            guard let self else { return }
            willSettle?()
            motionVisible = false; floatingSurface = false
            layoutChrome()
            settled += 1
        }
        pass = .full
        revealsAnchored = false
    }

    func settle() { motion.cancel(); motionVisible = false; floatingSurface = false; layoutChrome() }
    func commit() { rootView.displayIfNeeded(); CATransaction.flush() }
    func set(_ settledPresentation: SidebarPresentation) {
        motion.cancel(); presentation = settledPresentation; settle(); rootView.layoutSubtreeIfNeeded(); commit()
    }
    func finish() { completions.finishAll(); commit() }

    struct Snapshot {
        let frames: [ObjectIdentifier: NSRect]
        let presented: [ObjectIdentifier: CGRect]
    }

    func scope(_ view: NSView, exempt: Bool) -> Bool {
        guard exempt else { return true }
        return !sidebarContainer.subviews.contains { $0 is NSVisualEffectView && !$0.isHidden && (view === $0 || view.isDescendant(of: $0)) }
    }

    func visibleViews(_ view: NSView? = nil) -> [NSView] {
        let view = view ?? rootView
        guard !view.isHidden else { return [] }
        return [view] + view.subviews.flatMap { visibleViews($0) }
    }

    func snapshot() -> Snapshot {
        var frames: [ObjectIdentifier: NSRect] = [:], presented: [ObjectIdentifier: CGRect] = [:]
        for view in visibleViews() {
            frames[ObjectIdentifier(view)] = view.frame
            if let layer = view.layer { presented[ObjectIdentifier(view)] = layer.presentation()?.frame ?? layer.frame }
        }
        return Snapshot(frames: frames, presented: presented)
    }

    func ticked(since before: Snapshot, exemptingMaterials exempt: Bool) -> [String] {
        visibleViews().compactMap { view in
            guard scope(view, exempt: exempt), let old = before.frames[ObjectIdentifier(view)], old != view.frame else { return nil }
            let sized = old.size != view.frame.size
            let resized = sized && (view.layer?.animation(forKey: "bounds") == nil || Self.redrawsWhileResizing(view))
            let moved = old.origin != view.frame.origin && view.layer?.animation(forKey: "position") == nil
            return resized || moved ? (view.identifier?.rawValue ?? String(describing: type(of: view))) : nil
        }
    }

    func staleFrames() -> [String] {
        let settled = frames()
        let pageContent: NSView = pane.superview != nil ? pane : empty
        var expected: [(String, NSView, NSRect)] = [
            ("sidebarContainer", sidebarContainer, settled.sidebar), ("pageHost", pageHost, settled.pageHost),
            ("sidebar", sidebar, sidebarContainer.bounds), ("splitView", splitView, pageHost.bounds),
            ("content", pageContent, splitView.bounds),
        ]
        if let canvas = sidebarContainer.subviews.first(where: { String(describing: type(of: $0)) == "ThemeMetalCanvas" }) {
            expected.append(("ThemeMetalCanvas", canvas, sidebarContainer.bounds))
        }
        if pane.superview != nil {
            let strip: CGFloat = pane.developerToolbar.isHidden ? 0 : 40
            expected += [("pane.content", pane.content, NSRect(x: 0, y: strip, width: pane.bounds.width, height: pane.bounds.height - strip)),
                         ("page", pane.page, pane.content.bounds), ("page.renderWidget", pane.page.host, pane.page.bounds)]
            if !pane.developerToolbar.isHidden {
                expected.append(("developerToolbar", pane.developerToolbar, NSRect(x: 0, y: 0, width: pane.bounds.width, height: strip)))
            }
        }
        return expected.filter { $0.1.frame != $0.2 }.map(\.0)
    }

    static func redrawsWhileResizing(_ view: NSView) -> Bool {
        let draw = #selector(NSView.draw(_:))
        return view.layerContentsRedrawPolicy == .duringViewResize && view.method(for: draw) != NSView.instanceMethod(for: draw)
    }

    func jumps(since before: Snapshot, tolerance: CGFloat) -> [String] {
        participants.compactMap { view in
            guard !view.isHidden, let layer = view.layer, let old = before.presented[ObjectIdentifier(view)] else { return nil }
            let start: CGPoint
            if let animation = layer.animation(forKey: "position") as? CABasicAnimation, let from = (animation.fromValue as? NSValue)?.pointValue {
                start = from
            } else {
                start = layer.position
            }
            let oldPosition = CGPoint(x: old.minX + layer.anchorPoint.x * old.width, y: old.minY + layer.anchorPoint.y * old.height)
            let jump = max(abs(start.x - oldPosition.x), abs(start.y - oldPosition.y))
            return jump > tolerance ? "\(view.identifier?.rawValue ?? "?") \(jump)" : nil
        }
    }

    func needsLayout(_ view: NSView? = nil) -> Bool {
        let view = view ?? rootView
        return view.needsLayout || view.subviews.contains { needsLayout($0) }
    }

    var settledFramesMatch: Bool {
        let settled = frames()
        return sidebarContainer.frame == settled.sidebar && pageHost.frame == settled.pageHost
            && pageShadow.frame == ContentShadowImage.frame(around: settled.pageHost)
            && loadingIndicator.frame == PageLoadingIndicatorHost.frame(pageHost: settled.pageHost)
    }

    var geometryAnimationsRemain: Bool {
        participants.contains { view in ["position", "bounds"].contains { view.layer?.animation(forKey: $0) != nil } }
    }

    var shadow: NSView? { sidebarContainer.subviews.first { $0 is FloatingSidebarShadowView } }
    var materials: [NSVisualEffectView] { sidebarContainer.subviews.compactMap { $0 as? NSVisualEffectView } }
    var fades: [CFTimeInterval?] {
        sidebarContainer.subviews.filter { $0 is NSVisualEffectView || $0 is FloatingSidebarShadowView }
            .map { ($0.layer?.animation(forKey: "opacity") as? CABasicAnimation)?.duration }
    }
}
