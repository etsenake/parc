import AppKit

/// Gate for forced `layoutSubtreeIfNeeded` after mini-player height/content updates.
///
/// Deck `resize` and row `failure` previously always walked layout even when the
/// owning sidebar flush already left frames current. Skip only when no frame
/// moved and the tree is already clean; keep the flush when height/content
/// changes or a child still needs layout.
enum MiniPlayerLayoutFlushSkip {
    /// True no-op: identical geometry with a clean subtree skips layoutSubtree.
    /// A moved frame, a dirty view, or a dirty child still flushes.
    static func shouldFlush(
        frameChanged: Bool = false,
        needsLayout: Bool,
        subtreeNeedsLayout: Bool
    ) -> Bool {
        frameChanged || needsLayout || subtreeNeedsLayout
    }
}

/// A prepared row keeps the original page and media episode. It never opens a
/// URL or materializes a replacement browser to control background playback.
@MainActor
final class MiniPlayerHostLease {
    weak var window: NSWindow?
    init(_ window: NSWindow) { self.window = window }
}

@MainActor
struct MiniPlayerItem {
    let page: PCNativePage
    let state: PCNativeMediaState
    let icon: NSImage?
    let host: MiniPlayerHostLease
    let valid: () -> Bool
    let reveal: () -> Void
    var id: String { state.identifier }
}

@MainActor
final class MiniPlayerDeck: NSView {
    var onHeightChanged: (() -> Void)?
    var motionCompanion: (() -> NSView?)?
    private let motion = MiniPlayerMotion()
    var onKeyViewsChanged: (() -> Void)?
    var palette: ThemeChromePalette? { didSet { rows.values.forEach { $0.palette = palette } } }
    private let scroll = NSScrollView()
    private let expand = ActionButton("Show All Mini Players", symbol: "chevron.up")
    private let content = LayoutView()
    private var rows: [String: MiniPlayerRow] = [:]
    private var order: [String] = []
    private var dismissed = Set<String>()
    private var expanded = false
    private var tracking: NSTrackingArea?
    private var collapse: DispatchWorkItem?
    private var collapseDue = false
    private var pointerInside = false
    private var focusObserver: NSObjectProtocol?
    private var motionObserver: NSObjectProtocol?
    override var isFlipped: Bool { true }
    var desiredHeight: CGFloat {
        guard !order.isEmpty else { return 0 }
        let controlsHeight: CGFloat = order.count > 1 ? 22 : 0
        if expanded {
            return controlsHeight + min(276, order.reduce(0) { $0 + (rows[$1]?.desiredHeight ?? 0) + 5 } - 5)
        }
        return controlsHeight + 33 + CGFloat(order.count - 1) * 7
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.documentView = content
        addSubview(scroll); addSubview(expand)
        expand.font = .systemFont(ofSize: 10, weight: .medium)
        // Sidebar key-view ring (docs/sidebar-accessibility.md): an
        // ActionButton has none by default.
        expand.focusRingCornerRadius = 5
        expand.actionBlock = { [weak self] in guard let self else { return }; self.setExpanded(!self.expanded) }
        setAccessibilityElement(false)
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self.motion.settle() }
                self.rows.values.forEach { $0.updateRouteMotion() }
            }
        }
    }
    deinit {
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func update(_ items: [MiniPlayerItem]) {
        let oldHeight = desiredHeight
        let oldOrder = order
        let alive = Set(items.map(\.id)); dismissed.formIntersection(alive)
        let visible = Array(items.filter { !dismissed.contains($0.id) }.prefix(5))
        let previousCount = order.count
        let next = Set(visible.map(\.id))
        if next.count < 2 { relinquishFocus(in: expand) }
        for key in Array(rows.keys) where !next.contains(key) {
            if let row = rows.removeValue(forKey: key) {
                relinquishFocus(in: row)
                row.removeFromSuperview()
            }
        }
        // The source registry preserves admission order even across a
        // temporary transfer; row instances remain keyed by their episode.
        order = visible.map(\.id)
        for item in visible {
            let row = rows[item.id] ?? MiniPlayerRow()
            if rows[item.id] == nil {
                rows[item.id] = row; content.addSubview(row)
                row.palette = palette
                row.onHeightChanged = { [weak self] in self?.resize() }
                row.onKeyViewsChanged = { [weak self] in self?.onKeyViewsChanged?() }
                row.onClose = { [weak self] in self?.dismiss(item.id) }
                row.onFocus = { [weak self] in self?.expandForFocus() }
            }
            row.update(item)
        }
        if order.isEmpty || (order.count < 2 && !pointerInside) { resetExpansion() }
        else if !pointerInside && previousCount < 2 && order.count >= 2 { resetExpansion() }
        isHidden = order.isEmpty
        needsLayout = true
        if oldHeight != desiredHeight { onHeightChanged?() }
        if oldOrder != order { onKeyViewsChanged?() }
    }
    private func dismiss(_ id: String) {
        guard rows[id]?.dismiss() == true else { return }
        dismissed.insert(id)
        if let row = rows.removeValue(forKey: id) {
            relinquishFocus(in: row)
            row.removeFromSuperview()
        }
        order.removeAll { $0 == id }; isHidden = order.isEmpty
        if order.count < 2 {
            relinquishFocus(in: expand)
            if order.isEmpty || !pointerInside { resetExpansion() }
        }
        resize()
    }
    /// A retiring row must not leave a focused control in the detached
    /// subtree. Continue after the deck only in the active owning window.
    private func relinquishFocus(in row: NSView) {
        guard NSApp.isActive, let window, window.isKeyWindow, window.attachedSheet == nil,
              let focused = window.firstResponder as? NSView,
              focused === row || focused.isDescendant(of: row) else { return }
        var next = focused.nextValidKeyView
        var visited: Set<ObjectIdentifier> = [ObjectIdentifier(focused)]
        while let candidate = next, candidate === self || candidate.isDescendant(of: self) {
            guard visited.insert(ObjectIdentifier(candidate)).inserted else { next = nil; break }
            next = candidate.nextValidKeyView
        }
        if next?.window !== window { next = nil }
        _ = window.makeFirstResponder(next)
    }
    private func resize() {
        let root = superview?.superview ?? self
        motion.layout(in: root, deck: self, companion: motionCompanion?(), animated: true) {
            // Height/content changes still dirty and notify the sidebar. The
            // owning onHeightChanged flush often leaves this deck clean; skip a
            // second layoutSubtree walk when frames/subtree are already current.
            needsLayout = true
            onHeightChanged?()
            if MiniPlayerLayoutFlushSkip.shouldFlush(
                needsLayout: needsLayout,
                subtreeNeedsLayout: subviews.contains(where: \.needsLayout)
            ) {
                layoutSubtreeIfNeeded()
            }
            onKeyViewsChanged?()
        }
    }
    private func resetExpansion() {
        collapse?.cancel(); collapse = nil; collapseDue = false; expanded = false
        rows.values.forEach { $0.collapseVolume() }
    }
    private func expandForFocus() {
        guard !expanded else { return }
        expanded = true; resize()
    }
    private func setExpanded(_ value: Bool) {
        collapse?.cancel(); collapse = nil; collapseDue = false
        guard expanded != value else { return }
        expanded = value
        if !value { rows.values.forEach { $0.collapseVolume() } }
        resize()
    }
    override func layout() {
        super.layout()
        let header: CGFloat = order.count > 1 ? 22 : 0
        expand.isHidden = order.count < 2
        expand.title = expanded ? "Collapse Mini Players" : "Show All Mini Players (\(order.count))"
        expand.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.up", accessibilityDescription: nil)
        SidebarAccessibility.label(expand, expand.title)
        LiveShortcutToolTip.set(expand, expand.title)
        expand.setAccessibilityExpanded(expanded)
        expand.cell?.setAccessibilityExpanded(expanded)
        expand.frame = NSRect(x: 0, y: 0, width: bounds.width, height: header)
        scroll.frame = NSRect(x: 0, y: header, width: bounds.width, height: max(0, bounds.height - header))
        if expanded {
            var y: CGFloat = 0
            for id in order {
                guard let row = rows[id] else { continue }
                row.setPresentation(expanded: true, front: true)
                row.isHidden = false
                content.addSubview(row, positioned: .above, relativeTo: nil)
                row.alphaValue = 1
                row.frame = NSRect(x: 0, y: y, width: scroll.contentSize.width, height: row.desiredHeight)
                y += row.desiredHeight + 5
            }
            content.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(0, y - 5))
        } else {
            let height = 33 + CGFloat(max(0, order.count - 1)) * 7
            content.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: height)
            // Add the leading episode last in z-order: the other cards remain
            // visible behind it, but never intercept its controls.
            for (index, id) in order.enumerated().reversed() {
                guard let row = rows[id] else { continue }
                let inset = min(90, CGFloat(index) * 10) / 2
                row.setPresentation(expanded: false, front: index == 0)
                row.isHidden = false
                content.addSubview(row, positioned: .above, relativeTo: nil)
                row.alphaValue = max(0.4, 1 - CGFloat(index) * 0.2)
                row.frame = NSRect(x: inset, y: height - 33 - CGFloat(index) * 7,
                                   width: max(0, scroll.contentSize.width - 2 * inset), height: 33)
            }
        }
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { updateHover(true) }
    override func mouseExited(with event: NSEvent) { updateHover(false) }
    func updateHover(_ inside: Bool) {
        pointerInside = inside
        if inside { setExpanded(true); return }
        collapse?.cancel(); collapseDue = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapse = nil; self.collapseDue = true
            self.finishDeferredCollapse()
        }
        collapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + MiniPlayerMotion.hoverOffDelay, execute: work)
    }
    private func finishDeferredCollapse() {
        guard collapseDue, !pointerInside else { return }
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) { return }
        setExpanded(false)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            collapse?.cancel(); collapse = nil; collapseDue = false; pointerInside = false
            motion.settle()
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver); self.focusObserver = nil }
            if let newWindow {
                focusObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didUpdateNotification, object: newWindow, queue: .main
                ) { [weak self, weak newWindow] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.window === newWindow else { return }
                        self.finishDeferredCollapse()
                    }
                }
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

/// The slider stays in the layer tree while its recovered opacity animates,
/// but a collapsed control cannot receive pointer or accessibility input.
@MainActor
private final class MiniPlayerVolumeSlider: NSSlider {
    var allowsInteraction = false
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? {
        allowsInteraction ? super.hitTest(point) : nil
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

@MainActor
private final class MiniPlayerRow: NSView {
    var onHeightChanged: (() -> Void)?
    var onKeyViewsChanged: (() -> Void)?
    var onClose: (() -> Void)?
    var onFocus: (() -> Void)?
    var palette: ThemeChromePalette? { didSet { applyPalette() } }
    private var item: MiniPlayerItem?
    private let title = ActionButton()
    private let titleArtwork = MiniPlayerArtwork()
    private let marquee = MiniPlayerMarquee()
    private let close = ActionButton("Close Mini Player", symbol: "xmark")
    private let pip = ActionButton("Open Picture in Picture", symbol: "rectangle.on.rectangle")
    private let play = ActionButton("Play", symbol: "play.fill")
    private let previous = ActionButton("Previous Track", symbol: "backward.end.fill")
    private let next = ActionButton("Next Track", symbol: "forward.end.fill")
    private let volumeButton = ActionButton("Adjust Tab Volume", symbol: "speaker.wave.2.fill")
    private let mute = ActionButton("Mute Tab", symbol: "speaker.slash")
    private let microphone = ActionButton("Microphone", symbol: "mic.fill")
    private let camera = ActionButton("Camera", symbol: "video.fill")
    /// The transport's last button: AirPlay on Safari-identity pages, Cast on
    /// Chrome-identity ones, in one style with the same states.
    private let route = ActionButton("AirPlay", symbol: "airplayvideo")
    private var routeChooserOpen = false
    private let routePulse = ViewDisplayFrameDriver()
    private var routePulseStart: CFTimeInterval = 0
    private let volume = MiniPlayerVolumeSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volumeValue = NSTextField(labelWithString: "100%")
    private let unavailable = NSTextField(labelWithString: "")
    private var volumeExpanded = false
    private var volumePinned = false
    private var volumeHover = false
    private var volumeHoverOff: DispatchWorkItem?
    private var restoringVolumeFocus = false
    private var deckExpanded = true
    private var frontCard = true
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { frontCard }
    override func hitTest(_ point: NSPoint) -> NSView? { frontCard ? super.hitTest(point) : nil }
    var desiredHeight: CGFloat {
        let chrome: CGFloat = deckExpanded ? 33 : 0
        let volumeBand: CGFloat = showsVolumeDrawer ? 33 : 0
        let error: CGFloat = (!unavailable.stringValue.isEmpty && deckExpanded) ? 28 : 0
        return 33 + chrome + volumeBand + error
    }
    private var showsVolumeDrawer: Bool {
        volumeExpanded && deckExpanded && item?.state.canSetVolume == true
    }
    var isCurrent: Bool { item.map { $0.valid() && !$0.page.isClosed && $0.page.mediaState?.identifier == $0.id } ?? false }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.cornerRadius = 8
        layer?.borderWidth = 1; layer?.masksToBounds = true
        setAccessibilityElement(false)
        title.alignment = .left; title.font = .systemFont(ofSize: 12, weight: .medium)
        title.imagePosition = .noImage
        titleArtwork.imageScaling = .scaleProportionallyUpOrDown
        titleArtwork.setAccessibilityHidden(true)
        title.actionBlock = { [weak self] in self?.reveal() }
        close.actionBlock = { [weak self] in self?.onClose?() }
        pip.actionBlock = { [weak self] in self?.perform(.enterPictureInPicture) }
        play.actionBlock = { [weak self] in
            guard let self, let item = self.item else { return }
            self.perform(item.state.playing ? .pause : .play)
        }
        previous.actionBlock = { [weak self] in self?.perform(.previousTrack) }
        next.actionBlock = { [weak self] in self?.perform(.nextTrack) }
        microphone.actionBlock = { [weak self] in self?.perform(.toggleMicrophone) }
        camera.actionBlock = { [weak self] in self?.perform(.toggleCamera) }
        route.actionBlock = { [weak self] in self?.showRouteChooser() }
        mute.actionBlock = { [weak self] in self?.perform(.toggleMuted) }
        volumeButton.actionBlock = { [weak self] in
            guard let self, self.isCurrent, let item = self.item else { return }
            if item.state.muted || NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                self.perform(.toggleMuted)
                return
            }
            self.volumePinned.toggle()
            self.applyVolumeExpansion()
        }
        volumeButton.onHover = { [weak self] hovering in self?.setVolumeHover(hovering) }
        volume.onHover = { [weak self] hovering in self?.setVolumeHover(hovering) }
        updateVolumeAccessibility()
        volume.wantsLayer = true; volumeValue.wantsLayer = true
        volume.target = self; volume.action = #selector(volumeChanged); volume.isContinuous = true
        volume.trackFillColor = .systemBlue
        volume.controlSize = .small
        volume.setAccessibilityLabel("Tab volume")
        volumeValue.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        volumeValue.isHidden = true
        unavailable.font = .systemFont(ofSize: 10); unavailable.lineBreakMode = .byTruncatingTail
        for view in [title, titleArtwork, marquee, pip, close, play, previous, next, volumeButton, route, mute, microphone, camera, volume, volumeValue, unavailable] { addSubview(view) }
        for button in [pip, close, play, previous, next, volumeButton, route, mute, microphone, camera] {
            LiveShortcutToolTip.set(button, button.title)
            SidebarAccessibility.label(button, button.title)
            button.title = ""; button.imagePosition = .imageOnly
            button.focusRingType = .exterior
            button.showsHoverFill = button !== mute
        }
        // Sidebar key-view rings (docs/sidebar-accessibility.md): the row, a
        // stop for Return and Space, draws one around its card; the title is
        // an ActionButton with none by default.
        focusRingType = .exterior; title.focusRingCornerRadius = 5
        applyPalette()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private var keyCapabilities: [Bool] {
        guard let state = item?.state else { return [] }
        return [state.canPlayPause, state.hasPreviousTrack, state.hasNextTrack,
                state.canToggleCamera, state.canToggleMicrophone, state.canSetVolume,
                currentRoute != nil]
    }
    func update(_ item: MiniPlayerItem) {
        let previousCapabilities = keyCapabilities
        self.item = item
        let state = item.state
        let displayTitle = state.title.isEmpty ? (URL(string: state.sourceURL)?.host ?? "Playing media") : state.title
        marquee.text = displayTitle
        titleArtwork.image = item.icon ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        //
        LiveShortcutToolTip.set(title, "Back to Tab")
        SidebarAccessibility.label(title, "Back to Tab — " + displayTitle)
        play.image = NSImage(systemSymbolName: state.playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        name(play, state.playing ? "Pause" : "Play")
        previous.isEnabled = state.hasPreviousTrack; next.isEnabled = state.hasNextTrack
        play.isHidden = !state.canPlayPause; previous.isHidden = !state.canPlayPause; next.isHidden = !state.canPlayPause
        camera.isHidden = !state.canToggleCamera; microphone.isHidden = !state.canToggleMicrophone
        camera.image = NSImage(systemSymbolName: state.cameraOn ? "video.fill" : "video.slash.fill", accessibilityDescription: nil)
        microphone.image = NSImage(systemSymbolName: state.microphoneOn ? "mic.fill" : "mic.slash.fill", accessibilityDescription: nil)
        name(camera, state.cameraOn ? "Turn Camera Off" : "Turn Camera On", tooltip: "Toggle Camera")
        name(microphone, state.microphoneOn ? "Mute Microphone" : "Unmute Microphone", tooltip: "Toggle Microphone")
        volume.doubleValue = state.volume; volume.isEnabled = state.canSetVolume
        volumeValue.stringValue = "\(Int((state.volume * 100).rounded()))%"
        mute.image = NSImage(systemSymbolName: state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityDescription: nil)
        name(mute, state.muted ? "Unmute Tab" : "Mute Tab")
        name(volumeButton, state.muted ? "Unmute Tab" : "Adjust Tab Volume")
        volumeButton.isHidden = !frontCard || !state.canSetVolume
        if !state.canSetVolume && (volumeExpanded || volumePinned || volumeHover) {
            volumePinned = false; volumeHover = false
            applyVolumeExpansion()
        }
        updateVolumeAccessibility()
        updatePresentationVisibility()
        updateRoute()
        needsLayout = true
        if previousCapabilities != keyCapabilities { onKeyViewsChanged?() }
    }
    ///
    /// camera and microphone buttons "Toggle Camera" and "Toggle Microphone".
    private func name(_ button: ActionButton, _ label: String, tooltip: String? = nil) {
        SidebarAccessibility.label(button, label)
        LiveShortcutToolTip.set(button, tooltip ?? label)
    }
    private func updateVolumeAccessibility() {
        volumeButton.setAccessibilityExpanded(showsVolumeDrawer)
        volumeButton.cell?.setAccessibilityExpanded(showsVolumeDrawer)
        // MiniPlayerView gives the volume button HoverableButtonStyle's
        //
        volumeButton.showsSelectedFill = showsVolumeDrawer
    }
    private enum RouteKind { case airPlay, cast }
    private struct RouteStatus { let kind: RouteKind, connecting: Bool, connected: Bool, device: String? }
    private var currentRoute: RouteStatus? {
        guard let state = item?.state else { return nil }
        if state.castState != .unavailable {
            return RouteStatus(kind: .cast, connecting: state.castState == .connecting, connected: state.castState == .connected,
                               device: state.castDeviceName.flatMap { $0.isEmpty ? nil : $0 })
        }
        if state.airPlayState != .unavailable {
            return RouteStatus(kind: .airPlay, connecting: state.airPlayState == .connecting, connected: state.airPlayState == .connected,
                               device: state.airPlayDeviceName.flatMap { $0.isEmpty ? nil : $0 })
        }
        return nil
    }
    private func updateRoute() {
        let status = currentRoute
        let cast = status?.kind == .cast, connected = status?.connected == true, connecting = status?.connecting == true
        let base = cast ? "Cast" : "AirPlay"
        route.image = cast ? Self.castGlyph : Self.airPlayGlyph
        if connected { name(route, status?.device.map { cast ? "Casting to \($0)" : "Playing on \($0)" } ?? base) }
        else if connecting { name(route, status?.device.map { "Connecting to \($0)" } ?? base) }
        else { name(route, base) }
        let value: String? = connected ? "Connected" : connecting ? "Connecting" : nil
        route.setAccessibilityValue(value); route.cell?.setAccessibilityValue(value)
        route.setAccessibilitySelected(connected); route.cell?.setAccessibilitySelected(connected)
        route.showsSelectedFill = routeChooserOpen
        route.contentTintColor = connected || connecting ? routeActiveColor : (palette?.title ?? .labelColor)
        updateRouteMotion()
    }
    private static let airPlayGlyph = NSImage(systemSymbolName: "airplayvideo", accessibilityDescription: nil)
    /// Chromium's Cast icon (media_router_idle), the 24-unit Material "cast"
    /// glyph, as a template in the AirPlay symbol's image, its ink as wide as
    /// AirPlay's (13 points) so the two buttons match.
    private static let castGlyph: NSImage = {
        let size = airPlayGlyph?.size ?? NSSize(width: 17, height: 14)
        let image = NSImage(size: size, flipped: true) { rect in
            let scale: CGFloat = 13 / 22
            let path = NSBezierPath()
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
            path.move(to: p(21, 3)); path.line(to: p(3, 3)); path.curve(to: p(1, 5), controlPoint1: p(1.9, 3), controlPoint2: p(1, 3.9))
            path.line(to: p(1, 8)); path.line(to: p(3, 8)); path.line(to: p(3, 5)); path.line(to: p(21, 5)); path.line(to: p(21, 19))
            path.line(to: p(14, 19)); path.line(to: p(14, 21)); path.line(to: p(21, 21))
            path.curve(to: p(23, 19), controlPoint1: p(22.1, 21), controlPoint2: p(23, 20.1)); path.line(to: p(23, 5))
            path.curve(to: p(21, 3), controlPoint1: p(23, 3.9), controlPoint2: p(22.1, 3)); path.close()
            path.move(to: p(1, 18)); path.line(to: p(1, 21)); path.line(to: p(4, 21))
            path.curve(to: p(1, 18), controlPoint1: p(4, 19.34), controlPoint2: p(2.66, 18)); path.close()
            path.move(to: p(1, 14)); path.line(to: p(1, 16)); path.curve(to: p(6, 21), controlPoint1: p(3.76, 16), controlPoint2: p(6, 18.24))
            path.line(to: p(8, 21)); path.curve(to: p(1, 14), controlPoint1: p(8, 17.13), controlPoint2: p(4.87, 14)); path.close()
            path.move(to: p(1, 10)); path.line(to: p(1, 12)); path.curve(to: p(10, 21), controlPoint1: p(5.97, 12), controlPoint2: p(10, 16.03))
            path.line(to: p(12, 21)); path.curve(to: p(1, 10), controlPoint1: p(12, 14.92), controlPoint2: p(7.08, 10)); path.close()
            var transform = AffineTransform(translationByX: rect.midX - 12 * scale, byY: rect.midY - 12 * scale)
            transform.scale(scale)
            path.transform(using: transform)
            NSColor.black.setFill(); path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
    private var routeActiveColor: NSColor { palette?.airPlayActiveColor ?? .controlAccentColor }
    /// Connecting pulses the glyph alone, drawn by the button's own cell, so
    /// its fill and focus ring stay put. Reduce Motion leaves it at 1, as
    ///
    func updateRouteMotion() {
        let pulses = currentRoute?.connecting == true && window != nil && !route.isHidden
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard pulses else { routePulse.stop(); route.contentAlpha = 1; return }
        guard !routePulse.isRunning else { return }
        routePulseStart = CACurrentMediaTime()
        routePulse.start(in: route) { [weak self] in
            guard let self else { return false }
            self.route.contentAlpha = MiniPlayerMotion.connectingOpacity(at: CACurrentMediaTime() - self.routePulseStart)
            return true
        }
    }
    /// AirPlay opens the system's route list; Cast opens Chromium's media
    /// controls chooser with its devices, or Stop casting while it casts.
    private func showRouteChooser() {
        guard !routeChooserOpen, let kind = currentRoute?.kind else { return }
        guard isCurrent, let item, let host = item.host.window, host === window else { failure(); return }
        routeChooserOpen = true
        updateRoute()
        let closed = { [weak self] in
            guard let self else { return }
            self.routeChooserOpen = false
            self.updateRoute()
        }
        let shown = kind == .cast
            ? item.page.showCastChooser(for: item.state, relativeTo: route.bounds, of: route, in: host, dismissed: closed)
            : item.page.showAirPlayPicker(for: item.state, relativeTo: route.bounds, of: route, in: host, dismissed: closed)
        if !shown {
            routeChooserOpen = false
            updateRoute()
            failure()
        }
    }
    private func setVolumeHover(_ hovering: Bool) {
        volumeHoverOff?.cancel(); volumeHoverOff = nil
        if hovering {
            volumeHover = true
            applyVolumeExpansion()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.volumeHoverOff = nil
            self.volumeHover = false
            self.applyVolumeExpansion()
        }
        volumeHoverOff = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func collapseVolume() {
        volumeHoverOff?.cancel(); volumeHoverOff = nil
        volumePinned = false; volumeHover = false
        applyVolumeExpansion()
    }
    private func applyVolumeExpansion() {
        let next = deckExpanded && item?.state.canSetVolume == true && (volumePinned || volumeHover)
        guard volumeExpanded != next else {
            updateVolumeAccessibility()
            return
        }
        volumeExpanded = next
        updateVolumeAccessibility()
        needsLayout = true
        onHeightChanged?()
    }
    private func perform(_ action: PCNativeMediaAction) {
        guard isCurrent, let item else { failure(); return }
        guard let host = item.host.window, host === window else { failure(); return }
        if !item.page.performMediaAction(action, state: item.state, in: host) { failure() }
        else { refresh() }
    }
    @objc private func volumeChanged() {
        guard showsVolumeDrawer else { return }
        guard isCurrent, let item, let host = item.host.window, host === window,
              item.page.setMediaVolume(volume.doubleValue, state: item.state, in: host) else { failure(); return }
        refresh()
    }
    private func refresh() {
        guard let item, item.valid(), let state = item.page.mediaState, state.identifier == item.id else { failure(); return }
        let oldHeight = desiredHeight; unavailable.stringValue = ""
        update(MiniPlayerItem(page: item.page, state: state, icon: item.icon, host: item.host, valid: item.valid, reveal: item.reveal))
        if oldHeight != desiredHeight { onHeightChanged?() }
    }
    func dismiss() -> Bool {
        guard isCurrent, let item, let host = item.host.window, host === window,
              item.page.dismissMediaState(item.state, in: host) else { failure(); return false }
        return true
    }
    private func reveal() { guard isCurrent, let item else { return }; item.reveal() }
    private func failure() {
        unavailable.stringValue = "This media is no longer available."
        // The collapsed card clips the error. Expand first and let the owning
        // sidebar lay it out before exposing or announcing the message.
        onFocus?()
        needsLayout = true; onHeightChanged?()
        // onFocus / onHeightChanged often already flushed; skip a window-wide
        // layoutSubtree walk when this row and its children are already clean.
        if MiniPlayerLayoutFlushSkip.shouldFlush(
            needsLayout: needsLayout,
            subtreeNeedsLayout: subviews.contains(where: \.needsLayout)
        ) {
            window?.contentView?.layoutSubtreeIfNeeded()
        }
        if window != nil && !unavailable.isHidden && !unavailable.isHiddenOrHasHiddenAncestor {
            NSAccessibility.post(element: unavailable, notification: .valueChanged)
        }
    }
    override func mouseDown(with event: NSEvent) { reveal() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateRouteMotion() }
    override func becomeFirstResponder() -> Bool { if !restoringVolumeFocus { onFocus?() }; return super.becomeFirstResponder() }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { reveal() }
        else if event.keyCode == 49, item?.state.canPlayPause == true { perform(item!.state.playing ? .pause : .play) }
        else { super.keyDown(with: event) }
    }
    func setPresentation(expanded: Bool, front: Bool) {
        guard deckExpanded != expanded || frontCard != front else { return }
        deckExpanded = expanded; frontCard = front
        if !deckExpanded {
            volumeHoverOff?.cancel(); volumeHoverOff = nil
            volumePinned = false; volumeHover = false; volumeExpanded = false
        } else {
            volumeExpanded = item?.state.canSetVolume == true && (volumePinned || volumeHover)
        }
        updatePresentationVisibility()
        updateVolumeAccessibility()
        needsLayout = true
    }
    private func updatePresentationVisibility() {
        guard let state = item?.state else { return }
        title.isHidden = !deckExpanded || !frontCard
        titleArtwork.isHidden = !frontCard
        marquee.isHidden = !deckExpanded || !frontCard
        close.isHidden = !deckExpanded || !frontCard
        pip.isHidden = !deckExpanded || !frontCard
        play.isHidden = !frontCard || !state.canPlayPause
        previous.isHidden = !frontCard || !state.canPlayPause
        next.isHidden = !frontCard || !state.canPlayPause
        microphone.isHidden = !frontCard || !state.canToggleMicrophone
        camera.isHidden = !frontCard || !state.canToggleCamera
        mute.isHidden = true
        volumeButton.isHidden = !frontCard || !state.canSetVolume
        route.isHidden = !frontCard || currentRoute == nil
        marquee.scrollingEnabled = frontCard && deckExpanded
        updateRouteMotion()
    }
    override func layout() {
        super.layout()
        let chrome: CGFloat = deckExpanded ? 33 : 0
        title.frame = NSRect(x: 4, y: 0, width: max(0, bounds.width - 62), height: 33)
        marquee.frame = NSRect(x: 10, y: 7, width: max(0, bounds.width - 68), height: 19)
        pip.frame = NSRect(x: bounds.width - 54, y: 4, width: 23, height: 24)
        close.frame = NSRect(x: bounds.width - 29, y: 4, width: 23, height: 24)
        let transportY = chrome
        let controls = [previous, play, next, microphone, camera, volumeButton, route].filter { !$0.isHidden }
        let slots = CGFloat(controls.count + (titleArtwork.isHidden ? 0 : 1))
        let available = max(0, bounds.width - 8)
        let slot = slots > 0 ? available / slots : 0
        var x: CGFloat = 4
        if !titleArtwork.isHidden {
            titleArtwork.frame = NSRect(x: x + max(0, (slot - 15) / 2), y: transportY + 9, width: 15, height: 15)
            x += slot
        }
        for button in controls {
            button.frame = NSRect(x: x, y: transportY + 3, width: slot, height: 27)
            x += slot
        }
        let showsVolume = showsVolumeDrawer
        if !showsVolume, window?.firstResponder === volume, let window {
            restoringVolumeFocus = true
            if !window.makeFirstResponder(acceptsFirstResponder ? self : nil) {
                _ = window.makeFirstResponder(volumeButton.isHidden || !volumeButton.isEnabled ? nil : volumeButton)
            }
            restoringVolumeFocus = false
        }
        volume.allowsInteraction = showsVolume
        volume.refusesFirstResponder = !showsVolume
        volume.setAccessibilityHidden(!showsVolume)
        volumeValue.setAccessibilityHidden(true)
        volume.alphaValue = showsVolume ? 1 : 0
        volumeValue.alphaValue = 0
        volume.frame = NSRect(x: 14, y: chrome + 38, width: max(0, bounds.width - 28), height: 22)
        volumeValue.frame = NSRect(x: bounds.width - 45, y: chrome + 40, width: 38, height: 18)
        unavailable.frame = NSRect(x: 9, y: desiredHeight - 25, width: max(0, bounds.width - 18), height: 20)
        unavailable.isHidden = !deckExpanded || unavailable.stringValue.isEmpty
    }
    private func applyPalette() {
        layer?.backgroundColor = (palette?.backgroundExtra ?? NSColor.white.withAlphaComponent(0.35)).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        for button in [title, pip, close, play, previous, next, volumeButton, route, mute, microphone, camera] {
            button.contentTintColor = palette?.title ?? .labelColor
        }
        updateRoute()
        marquee.textColor = palette?.title ?? .labelColor
        volumeValue.textColor = palette?.title ?? .labelColor
        unavailable.textColor = palette?.title ?? .secondaryLabelColor
    }
}

/// Text is kept separate from the native button so its accessible name and
/// activation continue to describe the original page while the text scrolls.
@MainActor
private final class MiniPlayerArtwork: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class MiniPlayerMarquee: NSView {
    var text = "" { didSet { if text != oldValue { invalidatePresentation() } } }
    var textColor = NSColor.labelColor { didSet { if textColor != oldValue { invalidatePresentation() } } }
    var scrollingEnabled = false { didSet { if scrollingEnabled != oldValue { invalidatePresentation() } } }
    private let strip = NSView()
    private let first = NSTextField(labelWithString: "")
    private let second = NSTextField(labelWithString: "")
    private var lastSize = NSSize.zero
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.masksToBounds = true
        strip.wantsLayer = true
        for label in [first, second] {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.isSelectable = false
            strip.addSubview(label)
        }
        addSubview(strip)
        setAccessibilityElement(false); setAccessibilityHidden(true)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayOptionsChanged),
            name: UserDefaults.didChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func displayOptionsChanged() {
        DispatchQueue.main.async { [weak self] in self?.invalidatePresentation() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); invalidatePresentation() }
    private func invalidatePresentation() { lastSize = .zero; needsLayout = true }
    override func layout() {
        super.layout()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        strip.layer?.removeAnimation(forKey: "marquee")
        first.stringValue = text; second.stringValue = text
        first.textColor = textColor; second.textColor = textColor
        let width = ceil((text as NSString).size(withAttributes: [.font: first.font ?? NSFont.systemFont(ofSize: 12)]).width)
        let scroll = scrollingEnabled && UserDefaults.standard.bool(forKey: "ParcMiniPlayerMarqueeTitleEnabled")
            && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && width > bounds.width && bounds.width > 0
        let gap: CGFloat = 32
        strip.frame = NSRect(x: 0, y: 0, width: scroll ? 2 * width + gap : bounds.width, height: bounds.height)
        first.lineBreakMode = scroll ? .byClipping : .byTruncatingTail
        first.frame = NSRect(x: 0, y: 0, width: scroll ? width : bounds.width, height: bounds.height)
        second.isHidden = !scroll
        second.frame = NSRect(x: width + gap, y: 0, width: width, height: bounds.height)
        guard scroll else { layer?.mask = nil; return }
        let fade = CAGradientLayer()
        let leftEdge = min(0.5, 4 / bounds.width)
        let rightEdge = min(0.5, 8 / bounds.width)
        fade.frame = bounds
        fade.startPoint = CGPoint(x: 0, y: 0.5); fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, NSNumber(value: Double(leftEdge)), NSNumber(value: Double(1 - rightEdge)), 1]
        layer?.mask = fade
        let distance = width + gap
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0; animation.toValue = -distance
        animation.beginTime = CACurrentMediaTime() + 3
        animation.duration = 20
        animation.repeatCount = .infinity
        strip.layer?.add(animation, forKey: "marquee")
    }
}

extension ThemeChromePalette {
    /// AirPlay's connecting and connected tint, the theme's own hue in the
    /// luminance band farthest from the card: maxContrastColor (0 to 0.1) on
    /// light themes and foregroundSecondary (0.3 to 0.5) on dark ones. Either
    /// stays legible on backgroundExtra and distinct from the title-coloured
    /// neighbours.
    var airPlayActiveColor: NSColor { isDark ? foregroundSecondary : maxContrastColor }

    /// The same tint for the always-dark surfaces of a page's own AirPlay
    /// button and placard, whatever the window's appearance: the theme's
    /// dark-appearance airPlayActiveColor, lightened toward white only as far
    /// as 4.5:1 needs against the placard's black and the controls' scrim at
    /// the button row (mediaControls.css's gradient at 64.7%, alpha 0.741,
    /// over a white frame).
    /// A dynamic colour (a themeless Space's) resolves in the dark appearance,
    /// its alpha laid over black.
    static func airPlayOnDarkSurfaceColor(theme: SpaceTheme) -> NSColor {
        let tint = ThemeChromePalette(theme: theme, isDark: true).airPlayActiveColor
        var resolved: NSColor?
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance { resolved = tint.usingColorSpace(.sRGB) }
        guard let rgb = resolved else { return tint }
        func luminance(_ c: [CGFloat]) -> CGFloat {
            let l = c.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        }
        let scrim = luminance([1 - 0.741, 1 - 0.741, 1 - 0.741])
        let base = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { $0 * rgb.alphaComponent }
        var mix: CGFloat = 0
        var colour = base
        while mix < 1 && (luminance(colour) + 0.05) / (scrim + 0.05) < 4.5 {
            mix = min(1, mix + 0.01)
            colour = base.map { $0 + (1 - $0) * mix }
        }
        return NSColor(srgbRed: colour[0], green: colour[1], blue: colour[2], alpha: 1)
    }
}
