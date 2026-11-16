import AppKit
import QuartzCore

@MainActor final class Checks {
    var count = 0
    func expect(_ value: @autoclosure () -> Bool, _ description: String) {
        count += 1
        guard value() else { fatalError("SidebarMotion: \(description)") }
    }
}
@MainActor final class CountedView: NSView {
    var sizeChanges = 0
    override func setFrameSize(_ newSize: NSSize) {
        if frame.size != newSize { sizeChanges += 1 }
        super.setFrameSize(newSize)
    }
}
@MainActor final class ToolbarHost: NSView {
    let lights = NSView()
    let toggle = NSView()
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; addSubview(lights); addSubview(toggle) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let bar = SidebarChromeLayout.toolbar(width: bounds.width, windowButtons: WindowStandardButtons.stackSize, showsNavigation: true)
        lights.frame = bar.windowButtons ?? .zero; toggle.frame = bar.toggle ?? .zero
    }
}
@MainActor final class CountedLabel: NSTextField {
    var sizeChanges = 0
    override func setFrameSize(_ newSize: NSSize) {
        if frame.size != newSize { sizeChanges += 1 }
        super.setFrameSize(newSize)
    }
}
@MainActor func basic(_ view: NSView, _ key: String) -> CABasicAnimation? {
    view.layer?.animation(forKey: key) as? CABasicAnimation
}
@MainActor func run() {
    let c = Checks()
    _ = NSApplication.shared
    let rootBounds = NSRect(x: 0, y: 0, width: 1470, height: 831)
    func frame(_ placement: SidebarPresentationFrame) -> NSRect { placement.rect(width: 228, in: rootBounds) }
    c.expect(frame(.locked) == NSRect(x: 0, y: 0, width: 228, height: 831), "locked fills the leading edge")
    c.expect(frame(.floating) == NSRect(x: 5, y: 5, width: 228, height: 821), "floating is inset 5 points")
    c.expect(frame(.hiding) == NSRect(x: -238, y: 0, width: 228, height: 831), "the anchored hide ends at x − width − 10 at the locked height")
    c.expect(frame(.hidden) == NSRect(x: -238, y: 5, width: 228, height: 821), "a hidden sidebar settles where the floating container waits")
    c.expect(frame(.revealing) == NSRect(x: -228, y: 0, width: 228, height: 831), "the anchored reveal starts at x − width")
    c.expect([SidebarPresentationFrame.hiding, .hidden, .revealing].allSatisfy { frame($0).maxX <= rootBounds.minX },
             "every hidden frame lies wholly outside the root")
    let placements: [(SidebarPresentation, Bool, Bool, Bool, SidebarPresentationFrame, String)] = [
        (.locked, false, false, false, .locked, "settled locked"),
        (.floating, false, false, false, .floating, "settled floating"),
        (.hidden, false, false, false, .hidden, "a settled hide, also a hide without motion"),
        (.locked, true, false, false, .locked, "an anchored hide's preparation"),
        (.hidden, true, false, false, .hiding, "inside an anchored hide's group, also a reversed reveal's"),
        (.hidden, true, false, true, .revealing, "an anchored reveal's preparation, also a reversed hide's"),
        (.locked, true, false, true, .locked, "inside an anchored reveal's group"),
        (.hidden, true, true, false, .hidden, "a floating reveal's preparation and a floating dismissal's group"),
        (.floating, true, true, false, .floating, "inside a floating reveal's group, also a floating → locked preparation"),
        (.locked, true, true, false, .locked, "inside a floating → locked group")]
    for (presentation, inMotion, surface, anchored, expected, name) in placements {
        c.expect(SidebarPresentationFrame(presentation, inMotion: inMotion, floatingSurface: surface, revealsAnchored: anchored) == expected,
                 "placement: \(name)")
    }
    let transitions: [(SidebarPresentation, SidebarPresentation, SidebarMotionController.Style, Bool, Bool, Bool, Bool)] = [
        (.locked, .hidden, .anchored, false, false, false, false), (.hidden, .locked, .anchored, false, false, true, true),
        (.hidden, .floating, .floating, true, false, false, true), (.floating, .hidden, .floating, true, false, false, false),
        (.floating, .locked, .anchored, true, true, false, false), (.locked, .floating, .anchored, true, false, false, false)]
    for (from, to, style, surface, docks, anchored, flushes) in transitions {
        let transition = SidebarTransition(from: from, to: to)
        c.expect(transition.style == style && transition.keepsFloatingSurface == surface && transition.docksFloatingSurface == docks
                 && transition.revealsAnchored == anchored && transition.flushesPreparation == flushes,
                 "transition \(from) → \(to)")
    }
    func chrome(_ presentation: SidebarPresentation, _ placement: SidebarPresentationFrame, previewingHidden: Bool = false,
                fullscreen: Bool = false, library: Bool = false, popup: Bool = false, panel: Bool = false) -> SidebarChromeFrames {
        SidebarChromeFrames(bounds: rootBounds, sidebarWidth: 228, presentation: presentation, placement: placement, previewingHidden: previewingHidden,
                            fullscreen: fullscreen, library: library, popup: popup, sidePanel: panel)
    }
    let locked = chrome(.locked, .locked), away = chrome(.hidden, .hidden)
    c.expect(locked.sidebar == frame(.locked) && locked.pageHost == NSRect(x: 228, y: 10, width: 1232, height: 811),
             "locked chrome frames")
    c.expect(away.sidebar == frame(.hidden) && away.pageHost == NSRect(x: 10, y: 10, width: 1450, height: 811), "hidden chrome frames")
    let preview = chrome(.locked, .locked, previewingHidden: true)
    c.expect(preview.sidebar.minX == -228 && preview.pageHost.minX == 10, "a width drag's hidden preview shows hidden geometry")
    let paneled = chrome(.locked, .locked, panel: true)
    c.expect(paneled.showsSidePanel && paneled.pageHost == NSRect(x: 228, y: 10, width: 872, height: 811)
             && paneled.sidePanel == NSRect(x: 1100, y: 10, width: 360, height: 811), "side panel beside the page")
    let fullscreen = chrome(.locked, .locked, fullscreen: true, panel: true)
    c.expect(fullscreen.pageHost == rootBounds && !fullscreen.showsSidePanel, "page full screen fills the window")
    let popup = chrome(.hidden, .hidden, popup: true)
    c.expect(popup.pageHost == NSRect(x: 8, y: 57, width: 1452, height: 764) && popup.popupChrome == NSRect(x: 8, y: 0, width: 1454, height: 47),
             "popup chrome")
    let library = chrome(.locked, .locked, library: true)
    c.expect(library.library.width == 417 && library.pageHost.minX == 417, "Library width before a page reports")
    let libraryWindow = NSRect(x: 0, y: 0, width: 1280, height: 832)
    let wideLibrary = SidebarChromeFrames(bounds: libraryWindow, sidebarWidth: 228, presentation: .locked, placement: .locked,
                                          library: true, libraryContentWidth: SidebarChromeFrames.libraryMinimumWidth)
    c.expect(wideLibrary.library == NSRect(x: 0, y: 0, width: 417, height: 832)
             && wideLibrary.pageHost == NSRect(x: 417, y: 10, width: 853, height: 812),
             "a 417-point page's Library is 417 wide and its page is inset 10 vertically")
    func libraryWidth(_ content: CGFloat, in width: CGFloat) -> SidebarChromeFrames {
        SidebarChromeFrames(bounds: NSRect(x: 0, y: 0, width: width, height: 831), sidebarWidth: 228, presentation: .locked,
                            placement: .locked, library: true, libraryContentWidth: content)
    }
    for (content, width, expected, name) in [(480.0, 1470.0, 480.0, "one Space's 216 + 264"),
                                             (744.0, 1470.0, 744.0, "two Spaces"),
                                             (1536.0, 1470.0, 1414.0, "five Spaces stop at width − 56"),
                                             (744.0, 760.0, 704.0, "two Spaces in the narrowest window stop at width − 56"),
                                             (417.0, 1470.0, 417.0, "the default page width"),
                                             (300.0, 1470.0, 417.0, "a narrower page keeps the 417 floor"),
                                             (0.0, 1470.0, 417.0, "no reported width keeps the 417 floor"),
                                             (480.0, 400.0, 417.0, "the floor wins over width − 56")] {
        let frames = libraryWidth(content, in: width)
        c.expect(frames.library == NSRect(x: 0, y: 0, width: expected, height: 831)
                 && frames.pageHost == NSRect(x: expected, y: 10, width: max(0, width - expected - 10), height: 811),
                 "Library width, \(name): \(frames.library.width)")
    }
    let panelled = SidebarChromeFrames(bounds: libraryWindow, sidebarWidth: 228, presentation: .locked, placement: .locked,
                                       library: true, libraryContentWidth: 1008, sidePanel: true)
    c.expect(panelled.library.width == 1008 && panelled.showsSidePanel && panelled.sidePanel.minX == 1008
             && panelled.sidePanel.maxX == 1270 && panelled.pageHost.width == 0,
             "the extension panel starts at a wide Library's edge: \(panelled.sidePanel)")
    let narrowLibrary = SidebarChromeFrames(bounds: NSRect(x: 0, y: 0, width: 400, height: 600), sidebarWidth: 228,
                                            presentation: .locked, placement: .locked, library: true)
    c.expect(narrowLibrary.library.width == 417 && narrowLibrary.pageHost.minX == 417, "417 is a floor, not a cap")
    let libraryFullscreen = SidebarChromeFrames(bounds: libraryWindow, sidebarWidth: 228, presentation: .locked, placement: .locked,
                                                fullscreen: true, library: true, libraryContentWidth: 744)
    c.expect(libraryFullscreen.library.width == 0 && libraryFullscreen.pageHost == libraryWindow, "Full screen hides the Library column")
    for (width, height, sidebarWidth, isPopup, isLibrary) in [
        (1470.0, 831.0, 228.0, false, false),
        (760.0, 540.0, 420.0, false, false),
        (760.0, 540.0, 228.0, false, true),
        (300.0, 160.0, 0.0, true, false),
        (400.0, 300.0, 300.0, false, false),
        (0.0, 0.0, 228.0, false, false)
    ] {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let panel = SidebarChromeFrames(bounds: bounds, sidebarWidth: sidebarWidth,
            presentation: isPopup ? .hidden : .locked, placement: isPopup ? .hidden : .locked,
            library: isLibrary, popup: isPopup, sidePanel: true)
        c.expect(panel.sidePanel.width >= 0 && panel.sidePanel.minX >= 0
                 && panel.sidePanel.maxX <= width && panel.pageHost.width >= 0,
                 "extension panel fits the window at \(width) points")
        c.expect(panel.sidePanel.minY == panel.pageHost.minY && panel.sidePanel.maxY == panel.pageHost.maxY,
                 "extension panel shares page geometry below capture and popup chrome")
        if panel.sidePanel.width > 0 {
            c.expect(panel.sidePanel.minX == panel.pageHost.maxX,
                     "extension panel follows the actual page without overlap or a gap")
        }
    }
    c.expect(!SidebarPresentation.hidden.presents(inMotion: false) && SidebarPresentation.hidden.presents(inMotion: true)
             && [SidebarPresentation.locked, .floating].allSatisfy { $0.presents(inMotion: false) && $0.presents(inMotion: true) },
             "only a settled hide is not presented")
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    root.wantsLayer = true; window.contentView = root
    let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
    let page = CountedView(frame: NSRect(x: 228, y: 9, width: 763, height: 682))
    let pane = CountedView(frame: page.bounds)
    let editor = NSTextField(frame: NSRect(x: 12, y: 12, width: 120, height: 24))
    for view in [sidebar, page, pane] { view.wantsLayer = true }
    root.addSubview(sidebar); root.addSubview(page); page.addSubview(pane); sidebar.addSubview(editor)
    window.orderFront(nil); window.makeFirstResponder(editor)
    root.layoutSubtreeIfNeeded(); CATransaction.flush()
    let responder = window.firstResponder
    let motion = SidebarMotionController()
    let views = [sidebar, page]
    var finished: [String] = []
    func layout(_ locked: Bool) {
        sidebar.frame.origin.x = locked ? 0 : -228
        page.frame = NSRect(x: locked ? 228 : 9, y: 9, width: locked ? 763 : 982, height: 682)
        pane.frame = page.bounds
    }
    let unrelated = CABasicAnimation(keyPath: "opacity")
    unrelated.fromValue = 0.5; unrelated.toValue = 1; unrelated.duration = 10
    pane.layer!.add(unrelated, forKey: "other.owner")
    let oldUnrelated = pane.layer!.animation(forKey: "other.owner")
    motion.animate(layoutRoot: root, views: views, style: .anchored, changes: { layout(false) }, completion: { finished.append("hide") })
    c.expect(motion.isAnimating, "active transaction")
    c.expect(page.frame.minX == 9 && page.bounds.width == 982, "real destination frame is authoritative")
    c.expect(pane.bounds.width == 982, "original child layout committed")
    c.expect(page.sizeChanges == 1 && pane.sizeChanges == 1, "no interpolated native frame ticker")
    c.expect(basic(page, "position") != nil, "outer position participates")
    c.expect(basic(page, "bounds")?.duration == 0.08, "outer bounds timing")
    c.expect(basic(pane, "bounds")?.duration == 0.08, "nested bounds share the transaction")
    c.expect((basic(pane, "bounds")?.fromValue as? NSValue)?.rectValue.width == 763, "nested old geometry retained for presentation")
    c.expect(pane.layer!.animation(forKey: "other.owner") === oldUnrelated, "unrelated animation retained")
    c.expect(window.firstResponder === responder, "layout preserves field-editor focus")
    CATransaction.flush()
    let visible = page.layer?.presentation()?.position
    motion.animate(layoutRoot: root, views: views, style: .anchored, changes: { layout(true) }, completion: { finished.append("show") })
    let from = (basic(page, "position")?.fromValue as? NSValue)?.pointValue
    if let visible, let from {
        c.expect(abs(from.x - visible.x) < 20, "reversal starts at native presentation geometry")
    } else { fatalError("Missing AppKit reversal geometry") }
    c.expect(page.frame.minX == 228 && pane.bounds.width == 763, "reversal keeps original final hierarchy")
    c.expect(page.sizeChanges == 2 && pane.sizeChanges == 2, "reversal commits native bounds once")
    c.expect(window.firstResponder === responder, "reversal preserves editor")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0)); CATransaction.flush()
    c.expect(finished == ["show"], "only newest generation completes")
    c.expect(!motion.isAnimating, "completion releases motion owner")
    c.expect(basic(page, "position") == nil && basic(pane, "bounds") == nil, "completed geometry removed")

    motion.animate(layoutRoot: root, views: views, style: .anchored, changes: { layout(false) }, completion: { finished.append("obsolete") })
    let replacement = CABasicAnimation(keyPath: "bounds")
    replacement.fromValue = NSValue(rect: pane.bounds); replacement.duration = 10
    pane.layer!.add(replacement, forKey: "bounds")
    let replacementIdentity = pane.layer!.animation(forKey: "bounds")
    motion.cancel()
    c.expect(!motion.isAnimating, "explicit interruption settles")
    c.expect(pane.layer!.animation(forKey: "bounds") === replacementIdentity, "new geometry owner survives cancellation")
    c.expect(pane.layer!.animation(forKey: "other.owner") === oldUnrelated, "unrelated property survives cancellation")
    c.expect(basic(page, "position") == nil, "owned ancestor motion canceled")
    c.expect(page.frame.minX == 9, "settle keeps authoritative destination")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
    c.expect(finished == ["show"], "canceled completion cannot finalize visibility")
    pane.layer!.removeAnimation(forKey: "bounds")

    let custom = CABasicAnimation(keyPath: "opacity")
    sidebar.animations = ["alphaValue": custom]
    motion.animate(layoutRoot: root, views: views, style: .floating, changes: { sidebar.frame.origin.x = 0 }, completion: { finished.append("float") })
    c.expect(sidebar.animations.count == 1 && sidebar.animations["alphaValue"] as? CABasicAnimation === custom, "floating restores exact existing animation dictionary")
    let spring = sidebar.layer!.animation(forKey: "position") as? CASpringAnimation
    c.expect(spring != nil, "floating uses real native spring")
    c.expect(abs((spring?.stiffness ?? 0) - pow(2 * Double.pi / 0.18, 2)) < 0.001, "recovered spring response")
    c.expect(abs((spring?.damping ?? 0) - 2 * 0.8 * 2 * Double.pi / 0.18) < 0.001, "recovered spring damping")
    c.expect(page.sizeChanges == 3 && pane.sizeChanges == 3, "floating does not resize page")
    c.expect(window.firstResponder === responder, "floating has no focus side effect")
    motion.cancel()
    c.expect(sidebar.layer!.animation(forKey: "position") == nil, "floating interruption removes owned spring")
    c.expect(sidebar.animations.count == 1, "cancel leaves original view definitions")

    layout(true); root.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0)); CATransaction.flush()
    c.expect(finished == ["show"], "reduced-motion settle invalidates pending completion")
    c.expect(page.frame.minX == 228 && pane.bounds.width == 763, "new layout remains authoritative")
    c.expect(window.firstResponder === responder, "settle does not choose a different responder")
    for index in 0..<6 {
        motion.animate(layoutRoot: root, views: views, style: .anchored,
                       changes: { layout(index.isMultiple(of: 2)) },
                       completion: { finished.append("repeat-\(index)") })
    }
    c.expect(motion.isAnimating, "repeat retains a current transition")
    c.expect(page.frame.minX == 9 && pane.bounds.width == 982, "last repeated destination wins")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0)); CATransaction.flush()
    c.expect(finished == ["show", "repeat-5"], "only last repeated request finalizes")
    c.expect(!motion.isAnimating && basic(pane, "bounds") == nil, "repeat completion releases child motion")
    c.expect(window.firstResponder === responder, "repeats preserve original field editor")

    func controlPoints(_ timing: CAMediaTimingFunction?) -> [Float] {
        guard let timing else { return [] }
        var first: [Float] = [0, 0], second: [Float] = [0, 0]
        timing.getControlPoint(at: 1, values: &first); timing.getControlPoint(at: 2, values: &second)
        return first + second
    }
    motion.animate(layoutRoot: root, views: views, style: .libraryWidth, changes: { layout(true) },
                   completion: { finished.append("library") })
    c.expect(basic(page, "position")?.duration == 0.2 && basic(page, "bounds")?.duration == 0.2
             && basic(pane, "bounds")?.duration == 0.2, "the Library width group moves the page for 0.2 s")
    c.expect(controlPoints(basic(page, "bounds")?.timingFunction) == [0.25, 0.46, 0.45, 0.94],
             "the Library width group uses the anchored cubic")
    motion.cancel(); layout(false); root.layoutSubtreeIfNeeded()
    c.expect(!motion.isAnimating && basic(page, "position") == nil && basic(page, "bounds") == nil && basic(pane, "bounds") == nil,
             "closing or resizing settles the Library width group")
    c.expect(page.frame.minX == 9 && pane.bounds.width == 982, "the settling layout's frames are authoritative")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4)); CATransaction.flush()
    c.expect(!finished.contains("library"), "a settled Library width group never completes")

    let container = NSView(frame: NSRect(x: -228, y: 5, width: 228, height: 690))
    container.wantsLayer = true
    let toolbar = ToolbarHost(frame: container.bounds)
    container.addSubview(toolbar); root.addSubview(container)
    root.layoutSubtreeIfNeeded(); CATransaction.flush()
    let lightsSize = WindowStandardButtons.stackSize, toggleX = 13 + lightsSize.width + 4
    c.expect(toolbar.lights.frame == NSRect(origin: NSPoint(x: 13, y: 17), size: lightsSize) && toolbar.toggle.frame.minX == toggleX,
             "lights lead the header and the toggle follows 4 points after them")
    motion.animate(layoutRoot: root, views: [container], style: .floating, changes: { container.frame.origin.x = 5 },
                   completion: { finished.append("reveal") })
    c.expect(basic(toolbar.toggle, "position") == nil && basic(toolbar.lights, "position") == nil, "lights and toggle ride the surface")
    c.expect(container.layer!.animation(forKey: "position") is CASpringAnimation, "the surface itself slides")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0)); CATransaction.flush()
    c.expect(container.frame.minX + toolbar.lights.frame.minX == 18 && container.frame.minX + toolbar.toggle.frame.minX == 5 + toggleX,
             "floating header sits inside the 5-point inset")
    motion.animate(layoutRoot: root, views: [container], style: .anchored, flushesPreviousLayout: false, changes: {
        container.frame = NSRect(x: 0, y: 0, width: 228, height: 700)
        toolbar.frame = container.bounds
    }, completion: { finished.append("lock") })
    c.expect(toolbar.toggle.frame.minX == toggleX && toolbar.lights.frame.minX == 13, "locking keeps the header's sidebar positions")
    c.expect(basic(container, "position")?.duration == 0.08 && basic(toolbar.toggle, "position") == nil
             && basic(toolbar.lights, "position") == nil, "the container's 0.08 s group carries lights and toggle")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0)); CATransaction.flush()
    c.expect(finished.suffix(2) == ["reveal", "lock"] && !toolbar.needsLayout && container.frame.minX + toolbar.toggle.frame.minX == toggleX,
             "completion leaves no pending header move")

    func label(_ y: CGFloat) -> CountedLabel {
        let field = CountedLabel(labelWithString: "Parc"); field.alignment = .center
        field.frame = NSRect(x: 0, y: y, width: 300, height: 40); pane.addSubview(field); return field
    }
    let ticking = label(100), pinned = label(150)
    let hiddenHost = NSView(frame: NSRect(x: 0, y: 320, width: 300, height: 30)); hiddenHost.isHidden = true; pane.addSubview(hiddenHost)
    let hidden = CountedLabel(labelWithString: "Hidden"); hidden.frame = hiddenHost.bounds; hiddenHost.addSubview(hidden)
    let stretched = NSButton(title: "Capture", target: nil, action: nil), anchored = NSButton(title: "Capture", target: nil, action: nil)
    for (index, button) in [stretched, anchored].enumerated() {
        button.isBordered = false; button.frame = NSRect(x: 0, y: 200 + CGFloat(index) * 40, width: 300, height: 30); pane.addSubview(button)
    }
    let bar = NSProgressIndicator(frame: NSRect(x: 0, y: 280, width: 300, height: 2))
    bar.style = .bar; bar.isIndeterminate = true; pane.addSubview(bar)
    c.expect(ticking.layerContentsRedrawPolicy == .duringViewResize && stretched.layerContentsRedrawPolicy != .duringViewResize,
             "AppKit's default policies differ by view kind")
    SidebarMotionController.pinDrawnContent(pinned, to: .center)
    SidebarMotionController.pinDrawnContent(anchored, to: .left)
    SidebarMotionController.pinDrawnContent(bar, to: .left, clips: true)
    c.expect(pinned.layerContentsRedrawPolicy == .beforeViewResize && pinned.layerContentsPlacement == .center
             && anchored.layerContentsPlacement == .left && bar.layer?.masksToBounds == true, "pinned policies")
    root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
    ticking.sizeChanges = 0; pinned.sizeChanges = 0; hidden.sizeChanges = 0
    motion.animate(layoutRoot: root, views: views, style: .anchored, changes: {
        for view in [ticking, pinned, stretched, anchored, bar, hidden] as [NSView] { view.frame.size.width = 600 }
    }, completion: { finished.append("drawn") })
    c.expect(basic(ticking, "bounds") == nil, "default drawing view has no Core Animation geometry")
    c.expect(basic(pinned, "bounds")?.duration == 0.08 && pinned.layer?.contentsGravity == .center, "pinned label animates unscaled in the group")
    c.expect(basic(stretched, "bounds") != nil && stretched.layer?.contentsGravity == .resize, "default button scales its contents")
    c.expect(basic(anchored, "bounds")?.duration == 0.08 && anchored.layer?.contentsGravity == .left, "pinned button keeps its left alignment")
    c.expect(basic(bar, "bounds")?.duration == 0.08, "pinned progress bar joins the group")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4)); CATransaction.flush()
    c.expect(ticking.sizeChanges > 1, "default drawing view is resized every frame (\(ticking.sizeChanges) sizes)")
    c.expect(pinned.sizeChanges == 1, "pinned label is sized once")
    c.expect(hidden.sizeChanges == 1 && hidden.layerContentsRedrawPolicy == .duringViewResize,
             "a hidden drawing view is sized once and keeps its own policy (\(hidden.sizeChanges) sizes)")
    c.expect(finished.last == "drawn" && basic(pinned, "bounds") == nil, "group completion releases pinned geometry")

    final class FlushCountingRoot: NSView {
        var zeroDurationLayouts = 0
        override func layoutSubtreeIfNeeded() {
            let context = NSAnimationContext.current
            if context.duration == 0, !context.allowsImplicitAnimation { zeroDurationLayouts += 1 }
            super.layoutSubtreeIfNeeded()
        }
    }
    let flushWindow = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 300),
                               styleMask: [.borderless], backing: .buffered, defer: false)
    flushWindow.isReleasedWhenClosed = false
    let flushRoot = FlushCountingRoot(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    flushRoot.wantsLayer = true
    let flushSidebar = NSView(frame: NSRect(x: -200, y: 0, width: 200, height: 300))
    flushSidebar.wantsLayer = true
    flushRoot.addSubview(flushSidebar)
    flushWindow.contentView = flushRoot
    flushWindow.orderFront(nil)
    flushRoot.layoutSubtreeIfNeeded(); flushRoot.displayIfNeeded(); CATransaction.flush()
    c.expect(!SidebarMotionController.shouldFlushPreviousLayout(of: flushRoot),
             "clean laid-out root does not need the reveal flush")
    flushRoot.needsLayout = true
    c.expect(SidebarMotionController.shouldFlushPreviousLayout(of: flushRoot),
             "dirty layout root still requires the reveal flush")
    flushRoot.layoutSubtreeIfNeeded(); CATransaction.flush()
    c.expect(!SidebarMotionController.shouldFlushPreviousLayout(of: flushRoot),
             "layout clears the flush requirement")
    flushSidebar.layer?.removeAllAnimations()
    CATransaction.flush()
    let oldPresentation = flushSidebar.layer!.presentation()!.position
    flushSidebar.frame.origin.x += 40
    c.expect(!flushRoot.needsLayout && !flushSidebar.needsLayout,
             "origin-only frame move does not dirty AppKit layout")
    c.expect(flushSidebar.layer!.position != oldPresentation
             && flushSidebar.layer!.presentation()!.position == oldPresentation,
             "origin-only prep leaves presentation behind the model")
    c.expect(SidebarMotionController.shouldFlushPreviousLayout(of: flushRoot),
             "uncommitted geometry still requires the reveal flush")
    CATransaction.flush()
    c.expect(!SidebarMotionController.shouldFlushPreviousLayout(of: flushRoot),
             "flushing uncommitted geometry clears the requirement")

    let flushMotion = SidebarMotionController()
    flushRoot.zeroDurationLayouts = 0
    var flushFinished = 0
    flushMotion.animate(layoutRoot: flushRoot, views: [flushSidebar], style: .anchored, flushesPreviousLayout: true,
                        changes: { flushSidebar.frame.origin.x = 0 }, completion: { flushFinished += 1 })
    c.expect(flushRoot.zeroDurationLayouts == 0, "clean reveal skips the zero-duration layout pass")
    flushMotion.cancel()
    flushSidebar.frame.origin.x = -200
    flushRoot.layoutSubtreeIfNeeded(); CATransaction.flush()
    flushRoot.needsLayout = true
    flushRoot.zeroDurationLayouts = 0
    flushMotion.animate(layoutRoot: flushRoot, views: [flushSidebar], style: .anchored, flushesPreviousLayout: true,
                        changes: { flushSidebar.frame.origin.x = 0 }, completion: { flushFinished += 1 })
    c.expect(flushRoot.zeroDurationLayouts == 1, "dirty reveal still runs the zero-duration layout")
    flushMotion.cancel()
    flushWindow.orderOut(nil)

    window.orderOut(nil)
    print("SidebarMotion: \(c.count) assertions passed")
}
MainActor.assumeIsolated { exitOnFailure(run) }
