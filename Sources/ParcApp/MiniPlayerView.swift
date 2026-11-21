import AppKit
import ParcCore
import ParcEngine

enum MiniPlayerLayoutFlushSkip {
    static func shouldFlush(
        frameChanged: Bool = false,
        needsLayout: Bool,
        subtreeNeedsLayout: Bool
    ) -> Bool {
        frameChanged || needsLayout || subtreeNeedsLayout
    }
}

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
    private let scroll = SidebarPagingScrollView()
    var offerScroll: (NSEvent) -> Bool {
        get { scroll.offerScroll }
        set { scroll.offerScroll = newValue }
    }
    private let expand = ActionButton("Show All Mini Players", symbol: "chevron.up")
    private let content = LayoutView()
    private var rows: [String: MiniPlayerRow] = [:]
    private var order: [String] = []
    private var dismissed = Set<String>()
    private var expanded = false
    private var tracking: NSTrackingArea?
    var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }
    private var collapseGeneration = 0
    private var collapseDue = false
    private var pointerInside = false
    private var focusObserver: NSObjectProtocol?
    private var motionObserver: NSObjectProtocol?
    override var isFlipped: Bool { true }
    private static let shadowPad: CGFloat = 4
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
        collapseGeneration &+= 1; collapseDue = false; expanded = false
        rows.values.forEach { $0.collapseVolume() }
    }
    private func expandForFocus() {
        guard !expanded else { return }
        expanded = true; resize()
    }
    private func setExpanded(_ value: Bool) {
        collapseGeneration &+= 1; collapseDue = false
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
        let pad = Self.shadowPad
        let scrolls = expanded && order.reduce(0) { $0 + (rows[$1]?.desiredHeight ?? 0) + 5 } - 5 > 276
        let vPad = scrolls ? 0 : pad
        scroll.frame = NSRect(x: -pad, y: header - vPad, width: bounds.width + 2 * pad, height: max(0, bounds.height - header) + 2 * vPad)
        let width = max(0, scroll.contentSize.width - 2 * pad)
        if expanded {
            var y = vPad
            for id in order {
                guard let row = rows[id] else { continue }
                row.setPresentation(expanded: true, front: true)
                row.isHidden = false
                content.addSubview(row, positioned: .above, relativeTo: nil)
                row.alphaValue = 1
                row.frame = NSRect(x: pad, y: y, width: width, height: row.desiredHeight)
                y += row.desiredHeight + 5
            }
            content.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(2 * vPad, y - 5 + vPad))
        } else {
            let height = 33 + CGFloat(max(0, order.count - 1)) * 7
            content.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: height + 2 * pad)
            for (index, id) in order.enumerated().reversed() {
                guard let row = rows[id] else { continue }
                let inset = min(90, CGFloat(index) * 10) / 2
                row.setPresentation(expanded: false, front: index == 0)
                row.isHidden = false
                content.addSubview(row, positioned: .above, relativeTo: nil)
                row.alphaValue = max(0.4, 1 - CGFloat(index) * 0.2)
                row.frame = NSRect(x: pad + inset, y: pad + height - 33 - CGFloat(index) * 7,
                                   width: max(0, width - 2 * inset), height: 33)
            }
        }
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { updateHover((superview ?? self).isTopmost(atWindowPoint: event.locationInWindow)) }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        let inside = (superview ?? self).isTopmost(atWindowPoint: event.locationInWindow)
        if inside != pointerInside { updateHover(inside) }
    }
    override func mouseExited(with event: NSEvent) { updateHover(false) }
    func updateHover(_ inside: Bool) {
        pointerInside = inside
        if inside { setExpanded(true); return }
        collapseGeneration &+= 1; collapseDue = false
        let token = collapseGeneration
        after(MiniPlayerMotion.hoverOffDelay) { [weak self] in
            guard let self, self.collapseGeneration == token else { return }
            self.collapseDue = true
            self.finishDeferredCollapse()
        }
    }
    private func finishDeferredCollapse() {
        guard collapseDue, !pointerInside else { return }
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) { return }
        setExpanded(false)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            collapseGeneration &+= 1; collapseDue = false; pointerInside = false
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

@MainActor
private final class MiniPlayerVolumeSlider: NSSlider {
    var allowsInteraction = false
    override func hitTest(_ point: NSPoint) -> NSView? {
        allowsInteraction ? super.hitTest(point) : nil
    }
}

@MainActor
private final class MiniPlayerSurface: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

@MainActor
final class MiniPlayerRow: NSView {
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
    private let route = ActionButton("AirPlay", symbol: "airplayvideo")
    private var routeChooserOpen = false
    private let routePulse = ViewDisplayFrameDriver()
    private var routePulseStart: CFTimeInterval = 0
    private let volume = MiniPlayerVolumeSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volumeValue = NSTextField(labelWithString: "100%")
    private let unavailable = NSTextField(labelWithString: "")
    private let surface = MiniPlayerSurface()
    private var volumeExpanded = false
    private var volumeOpen = false
    private var volumeDismissal: [Any] = []
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
    var isCurrent: Bool { current != nil }
    private var current: PCNativeMediaState? {
        guard let item, item.valid(), !item.page.isClosed,
              let state = item.page.mediaState, state.identifier == item.id else { return nil }
        return state
    }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        layer?.shadowRadius = 4; layer?.shadowOffset = .zero; layer?.shadowOpacity = 1
        surface.wantsLayer = true; surface.layer?.cornerRadius = 8; surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true
        addSubview(surface)
        setAccessibilityElement(false)
        title.alignment = .left; title.font = .systemFont(ofSize: 12, weight: .medium)
        title.imagePosition = .noImage
        titleArtwork.imageScaling = .scaleProportionallyUpOrDown
        titleArtwork.setAccessibilityHidden(true)
        title.actionBlock = { [weak self] in self?.reveal() }
        close.actionBlock = { [weak self] in self?.onClose?() }
        pip.actionBlock = { [weak self] in self?.perform(.enterPictureInPicture) }
        play.actionBlock = { [weak self] in
            guard let self, let state = self.current ?? self.item?.state else { return }
            self.perform(state.playing ? .pause : .play)
        }
        previous.actionBlock = { [weak self] in self?.perform(.previousTrack) }
        next.actionBlock = { [weak self] in self?.perform(.nextTrack) }
        microphone.actionBlock = { [weak self] in self?.perform(.toggleMicrophone) }
        camera.actionBlock = { [weak self] in self?.perform(.toggleCamera) }
        route.actionBlock = { [weak self] in self?.showRouteChooser() }
        mute.actionBlock = { [weak self] in self?.perform(.toggleMuted) }
        volumeButton.actionBlock = { [weak self] in
            guard let self, let state = self.current else { return }
            if state.muted || NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                self.perform(.toggleMuted)
                return
            }
            self.setVolumeOpen(!self.volumeOpen)
        }
        updateVolumeAccessibility()
        volume.wantsLayer = true; volumeValue.wantsLayer = true
        volume.target = self; volume.action = #selector(volumeChanged); volume.isContinuous = true
        volume.trackFillColor = .systemBlue
        volume.controlSize = .small
        volume.setAccessibilityLabel("Tab volume")
        volumeValue.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        volumeValue.isHidden = true
        unavailable.font = .systemFont(ofSize: 10); unavailable.lineBreakMode = .byTruncatingTail
        for view in [title, titleArtwork, marquee, pip, close, play, previous, next, volumeButton, route, mute, microphone, camera, volume, volumeValue, unavailable] { surface.addSubview(view) }
        for button in [pip, close, play, previous, next, volumeButton, route, mute, microphone, camera] {
            LiveShortcutToolTip.set(button, button.title)
            SidebarAccessibility.label(button, button.title)
            button.title = ""; button.imagePosition = .imageOnly
            button.focusRingType = .exterior
            button.showsHoverFill = button !== mute
        }
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
        let previousCapabilities = keyCapabilities, focus = focusedControl
        self.item = item
        let state = item.state
        if isCurrent { unavailable.stringValue = "" }
        let displayTitle = state.title.isEmpty ? (URL(string: state.sourceURL)?.host ?? "Playing media") : state.title
        marquee.text = displayTitle
        titleArtwork.image = item.icon ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
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
        if !state.canSetVolume && (volumeExpanded || volumeOpen) { setVolumeOpen(false) }
        updateVolumeAccessibility()
        updatePresentationVisibility()
        updateRoute()
        needsLayout = true
        keepFocusVisible(focus)
        if previousCapabilities != keyCapabilities { onKeyViewsChanged?() }
    }
    private func name(_ button: ActionButton, _ label: String, tooltip: String? = nil) {
        SidebarAccessibility.label(button, label)
        LiveShortcutToolTip.set(button, tooltip ?? label)
    }
    private func updateVolumeAccessibility() {
        volumeButton.setAccessibilityExpanded(showsVolumeDrawer)
        volumeButton.cell?.setAccessibilityExpanded(showsVolumeDrawer)
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
    private func showRouteChooser() {
        guard !routeChooserOpen, let kind = currentRoute?.kind else { return }
        guard let item, let state = current, let host = item.host.window, host === window else { refresh(); return }
        routeChooserOpen = true
        updateRoute()
        let closed = { [weak self] in
            guard let self else { return }
            self.routeChooserOpen = false
            self.updateRoute()
        }
        let shown = kind == .cast
            ? item.page.showCastChooser(for: state, relativeTo: route.bounds, of: route, in: host, dismissed: closed)
            : item.page.showAirPlayPicker(for: state, relativeTo: route.bounds, of: route, in: host, dismissed: closed)
        if !shown { routeChooserOpen = false }
        refresh()
    }
    private func setVolumeOpen(_ open: Bool) {
        volumeOpen = open && deckExpanded && item?.state.canSetVolume == true
        if !volumeOpen { endVolumeDismissal() } else if volumeDismissal.isEmpty { watchVolumeDismissal() }
        applyVolumeExpansion()
    }
    func collapseVolume() { setVolumeOpen(false) }
    private func watchVolumeDismissal() {
        let clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.closeVolume(clickedBy: event) }
            return event
        }
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.closeVolume(escape: event) == true } ? nil : event
        }
        volumeDismissal = [clicks, escape].compactMap { $0 }
    }
    private func endVolumeDismissal() {
        volumeDismissal.forEach(NSEvent.removeMonitor)
        volumeDismissal = []
    }
    var scheduleVolumeLayout: (@escaping @MainActor () -> Void) -> Void = { update in
        RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated { update() } }
    }

    func closeVolume(clickedBy event: NSEvent) {
        if event.window === window, [volumeButton, volume].contains(where: {
            $0.bounds.contains($0.convert(event.locationInWindow, from: nil))
        }) { return }
        volumeOpen = false; endVolumeDismissal()
        scheduleVolumeLayout { [weak self] in self?.applyVolumeExpansion() }
    }
    func closeVolume(escape event: NSEvent) -> Bool {
        guard event.keyCode == 53, event.window === window else { return false }
        let focused = focusedControl != nil || window?.firstResponder === self
        setVolumeOpen(false)
        return focused
    }
    private func applyVolumeExpansion() {
        let next = deckExpanded && item?.state.canSetVolume == true && volumeOpen
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
        if let item, let state = current, let host = item.host.window, host === window {
            _ = item.page.performMediaAction(action, state: state, in: host)
        }
        refresh()
    }
    @objc private func volumeChanged() {
        guard showsVolumeDrawer else { return }
        if let item, let state = current, let host = item.host.window, host === window {
            _ = item.page.setMediaVolume(volume.doubleValue, state: state, in: host)
        }
        refresh()
    }
    private func refresh() {
        guard let item, let state = current else { showUnavailable(); return }
        let oldHeight = desiredHeight
        update(MiniPlayerItem(page: item.page, state: state, icon: item.icon, host: item.host, valid: item.valid, reveal: item.reveal))
        if oldHeight != desiredHeight { onHeightChanged?() }
    }
    func dismiss() -> Bool {
        guard let item, let state = current, let host = item.host.window, host === window,
              item.page.dismissMediaState(state, in: host) else { refresh(); return false }
        return true
    }
    private func reveal() { guard isCurrent, let item else { return }; item.reveal() }
    private func showUnavailable() {
        unavailable.stringValue = "This media is no longer available."
        onFocus?()
        needsLayout = true; onHeightChanged?()
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
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window, volumeOpen {
            volumeOpen = false; volumeExpanded = false; endVolumeDismissal()
            updateVolumeAccessibility(); needsLayout = true
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyPalette() }
    deinit { volumeDismissal.forEach(NSEvent.removeMonitor) }
    var initiatingEventType: () -> NSEvent.EventType? = { NSApp.currentEvent?.type }

    override func becomeFirstResponder() -> Bool {
        if let type = initiatingEventType(), [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) { return false }
        if !restoringVolumeFocus { onFocus?() }
        return super.becomeFirstResponder()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { reveal() }
        else if event.keyCode == 49, let state = current ?? item?.state, state.canPlayPause { perform(state.playing ? .pause : .play) }
        else { super.keyDown(with: event) }
    }
    func setPresentation(expanded: Bool, front: Bool) {
        guard deckExpanded != expanded || frontCard != front else { return }
        let focus = focusedControl
        deckExpanded = expanded; frontCard = front
        if !deckExpanded {
            volumeOpen = false; volumeExpanded = false; endVolumeDismissal()
        } else {
            volumeExpanded = item?.state.canSetVolume == true && volumeOpen
        }
        updatePresentationVisibility()
        updateVolumeAccessibility()
        keepFocusVisible(focus)
        needsLayout = true
    }
    private func updatePresentationVisibility() {
        guard let state = item?.state else { return }
        title.isHidden = !deckExpanded || !frontCard
        titleArtwork.isHidden = !frontCard
        marquee.isHidden = !deckExpanded || !frontCard
        close.isHidden = !deckExpanded || !frontCard
        pip.isHidden = !deckExpanded || !frontCard || !state.canEnterPictureInPicture
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
    private var focusedControl: NSView? {
        (window?.firstResponder as? NSView).flatMap { $0 !== self && $0.isDescendant(of: self) ? $0 : nil }
    }
    private func keepFocusVisible(_ focused: NSView?) {
        guard let window, let focused, focused.isHiddenOrHasHiddenAncestor,
              window.firstResponder === focused || window.firstResponder === window else { return }
        let stops = SidebarAccessibility.keyViews(in: [self], space: self)
        let following = stops.firstIndex { $0 === focused }.map { stops[($0 + 1)...] } ?? []
        if let next = following.first(where: { $0 !== self && !$0.isHiddenOrHasHiddenAncestor && $0.acceptsFirstResponder }),
           window.makeFirstResponder(next) { return }
        if !window.makeFirstResponder(acceptsFirstResponder && !isHiddenOrHasHiddenAncestor ? self : nil) {
            _ = window.makeFirstResponder(nil)
        }
    }
    override func layout() {
        super.layout()
        surface.frame = bounds
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
        let dark = palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        surface.layer?.backgroundColor = palette.map { $0.backgroundExtra.cgColor(in: $0.contentAppearance) } ?? NSColor.white.withAlphaComponent(0.35).cgColor
        surface.layer?.borderWidth = dark ? 0.5 : 0
        surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.2 : 0.08).cgColor
        for button in [title, pip, close, play, previous, next, volumeButton, route, mute, microphone, camera] {
            button.contentTintColor = palette?.title ?? .labelColor
        }
        updateRoute()
        marquee.textColor = palette?.title ?? .labelColor
        volumeValue.textColor = palette?.title ?? .labelColor
        unavailable.textColor = palette?.title ?? .secondaryLabelColor
    }
}

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
    var airPlayActiveColor: NSColor { isDark ? foregroundSecondary : maxContrastColor }

    static func airPlayOnDarkSurfaceColor(theme: SpaceTheme) -> NSColor {
        airPlaySurfaceTint(theme: theme, dark: true)
    }

    static func airPlayOnLightSurfaceColor(theme: SpaceTheme) -> NSColor {
        airPlaySurfaceTint(theme: theme, dark: false)
    }

    private static func airPlaySurfaceTint(theme: SpaceTheme, dark: Bool) -> NSColor {
        let tint = ThemeChromePalette(theme: theme, isDark: dark).airPlayActiveColor
        var resolved: NSColor?
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = tint.usingColorSpace(.sRGB)
        }
        guard let rgb = resolved else { return tint }
        func luminance(_ c: [CGFloat]) -> CGFloat {
            let l = c.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        }
        let surface: CGFloat = dark ? luminance([1 - 0.741, 1 - 0.741, 1 - 0.741]) : 1
        let target: CGFloat = dark ? 1 : 0
        let base = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
            $0 * rgb.alphaComponent + (dark ? 0 : 1 - rgb.alphaComponent)
        }
        func contrast(_ c: [CGFloat]) -> CGFloat {
            let tint = luminance(c)
            return (max(tint, surface) + 0.05) / (min(tint, surface) + 0.05)
        }
        var mix: CGFloat = 0
        var colour = base
        while mix < 1 && contrast(colour) < 4.5 {
            mix = min(1, mix + 0.01)
            colour = base.map { $0 + (target - $0) * mix }
        }
        return NSColor(srgbRed: colour[0], green: colour[1], blue: colour[2], alpha: 1)
    }
}
