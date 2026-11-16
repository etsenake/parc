import AppKit
import Carbon.HIToolbox
import SwiftUI

extension NSView {
    var parcTooltip: TooltipConfiguration? {
        get { TooltipTracker.attached(to: self)?.configuration }
        set { TooltipController.setConfiguration(newValue, of: self) }
    }
}

extension View {
    func parcTooltip(_ configuration: TooltipConfiguration?) -> some View {
        overlay {
            if let configuration { TooltipAnchor(configuration: configuration).accessibilityHidden(true) }
        }
    }
}

private struct TooltipAnchor: NSViewRepresentable {
    let configuration: TooltipConfiguration
    func makeNSView(context: Context) -> TooltipAnchorView {
        let view = TooltipAnchorView()
        view.parcTooltip = configuration
        return view
    }
    func updateNSView(_ view: TooltipAnchorView, context: Context) { view.parcTooltip = configuration }
}

final class TooltipAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window, TooltipController.controller(for: window).hitTestingView === self else { return nil }
        return super.hitTest(point)
    }
}

@MainActor enum LiveShortcutToolTip {
    static let didChange = Notification.Name("Parc.LiveShortcutDiscoveryDidChange")
    static var binder: ((NSView, String, String?, Bool) -> Void)?
    static var resolver: ((String, String?) -> String)?
    static func text(_ title: String, commandID: String?) -> String { resolver?(title, commandID) ?? title }
    static func set(_ view: NSView, _ title: String, commandID: String? = nil, requiresBinding: Bool = false,
                    anchor: TooltipConfiguration.Anchor = .bottomTrailing,
                    behavior: TooltipConfiguration.Behavior = .onMouseIdle(delay: 0.45)) {
        view.parcTooltip = TooltipConfiguration(title, shortcut: commandID.map { .command($0) }, anchor: anchor,
                                                behavior: behavior, requiresShortcut: requiresBinding)
        help(view, title, commandID: commandID, requiresBinding: requiresBinding)
    }
    static func help(_ view: NSView, _ title: String, commandID: String?, requiresBinding: Bool = false) {
        if let binder { binder(view, title, commandID, requiresBinding); return }
        let text = requiresBinding ? nil : title
        view.setAccessibilityHelp(text); (view as? NSControl)?.cell?.setAccessibilityHelp(text)
    }
}

@MainActor final class TooltipController {
    static var commandShortcut: ((String) -> KeyboardShortcut?)?
    static var eventChord: ((NSEvent) -> KeyboardShortcut?)?

    private typealias State = TooltipPresentationState<ObjectIdentifier>

    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private static let controllerKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    static func setConfiguration(_ configuration: TooltipConfiguration?, of view: NSView) {
        let tracker = TooltipTracker.attached(to: view)
        guard tracker?.configuration != configuration else { return }
        if let configuration {
            view.toolTip = nil
            if let tracker { tracker.configuration = configuration } else { TooltipTracker.attach(configuration, to: view) }
        } else {
            tracker?.detach()
        }
        if let window = view.window { existingController(for: window)?.configurationDidChange(for: view) }
    }

    static func controller(for window: NSWindow) -> TooltipController {
        if let controller = existingController(for: window) { return controller }
        let controller = TooltipController(window: window)
        objc_setAssociatedObject(window, controllerKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }
    private static func existingController(for window: NSWindow) -> TooltipController? {
        objc_getAssociatedObject(window, controllerKey) as? TooltipController
    }

    var palette: TooltipColorPalette?
    var isSuppressed = false {
        didSet { if isSuppressed && !oldValue { hide(TooltipTiming.exitDuration) } }
    }
    private(set) weak var hitTestingView: NSView?

    private weak var window: NSWindow?
    private var state = State()
    private weak var targetView: NSView?
    private var entered: [WeakView] = []
    private var presentationTimer: Timer?
    private var hitTestTimer: Timer?
    private var stopTimer: Timer?
    private var lastMoveTimestamp: TimeInterval = -1
    private var presenter: TooltipPresenter?
    private var presentedShortcut: KeyboardShortcut?
    private var monitor: Any?
    private var pressedModifiers: NSEvent.ModifierFlags = []
    private var pressedCharacters: String?
    private var observers: [NSObjectProtocol] = []

    private init(window: NSWindow) {
        self.window = window
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(TooltipTiming.exitDuration) }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tearDown() }
        })
    }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let monitor { NSEvent.removeMonitor(monitor) }
        presentationTimer?.invalidate(); hitTestTimer?.invalidate(); stopTimer?.invalidate()
    }

    private var currentView: NSView? {
        guard let target = state.target, let view = targetView, ObjectIdentifier(view) == target else { return nil }
        return view
    }

    fileprivate func mouseEntered(_ view: NSView, event: NSEvent) {
        entered.removeAll { $0.view == nil || $0.view === view }
        entered.append(WeakView(view))
        updateMonitor()
        guard let hit = hitTest(event.locationInWindow, for: view), hit.isDescendant(of: view) else { return }
        schedule(view)
    }

    private func hitTest(_ point: NSPoint, for view: NSView) -> NSView? {
        let previous = hitTestingView
        hitTestingView = view
        defer { hitTestingView = previous }
        return window?.contentView?.hitTest(point)
    }

    fileprivate func mouseExited(_ view: NSView) {
        entered.removeAll { $0.view == nil || $0.view === view }
        pointerLeft()
        updateMonitor()
    }

    fileprivate func mouseMoved(_ event: NSEvent) {
        guard event.timestamp != lastMoveTimestamp else { return }
        lastMoveTimestamp = event.timestamp
        if state.pointerMoved() { syncTimers() }
        if let stopTimer, stopTimer.isValid {
            stopTimer.fireDate = Date(timeIntervalSinceNow: TooltipTiming.pointerStopDelay)
        } else {
            stopTimer = Timer.scheduledTimer(withTimeInterval: TooltipTiming.pointerStopDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerStopped() }
            }
        }
    }

    private func pointerStopped() {
        stopTimer = nil
        guard state.schedulesWhenPointerStops, let view = viewUnderPointer() else { return }
        schedule(view)
    }

    private func isPointer(over view: NSView) -> Bool {
        guard let window = view.window, window === self.window,
              let hit = hitTest(window.mouseLocationOutsideOfEventStream, for: view) else { return false }
        return hit.isDescendant(of: view)
    }

    private func viewUnderPointer() -> NSView? {
        entered.reversed().compactMap(\.view).first { $0.parcTooltip != nil && isPointer(over: $0) }
    }

    private func pointerLeft() {
        guard state.target != nil else { return }
        let current = currentView, next = viewUnderPointer()
        switch state.exit(targetUnderPointer: current.map(isPointer(over:)) ?? false, enclosing: next.map(ObjectIdentifier.init),
                          enclosingAnchor: next?.parcTooltip?.anchor, anchor: current?.parcTooltip?.anchor ?? .bottomTrailing) {
        case .keep: break
        case .handOff: if let next { schedule(next) }
        case .hide(let fade): apply(state.hide(fade, now: Date()))
        }
    }

    private func shortcut(for configuration: TooltipConfiguration) -> KeyboardShortcut? {
        switch configuration.shortcut {
        case .fixed(let fixed)?: return fixed
        case .command(let id)?: return Self.commandShortcut?(id)
        case nil: return nil
        }
    }

    private func isEligible(_ configuration: TooltipConfiguration) -> Bool {
        if isSuppressed { return false }
        if configuration.requiresShortcut && shortcut(for: configuration) == nil { return false }
        return TooltipEligibility.permits(pressedMouseButtons: NSEvent.pressedMouseButtons, modifierFlags: NSEvent.modifierFlags,
                                   allowed: configuration.allowedModifierKeys) { [window] in
            var candidate = window
            while let current = candidate {
                if current.isKeyWindow { return true }
                candidate = current.parent
            }
            return false
        }
    }

    private func schedule(_ view: NSView) {
        guard let configuration = view.parcTooltip, isEligible(configuration) else { return }
        switch state.schedule(ObjectIdentifier(view), anchor: configuration.anchor, behavior: configuration.behavior, now: Date()) {
        case .present?: present(view)
        case .presentAfter(let delay)?:
            targetView = view
            presentationTimer?.invalidate()
            presentationTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self, weak view] _ in
                MainActor.assumeIsolated { if let view { self?.present(view) } }
            }
            updateMonitor()
        case nil: break
        }
    }

    private func present(_ view: NSView) {
        presentationTimer?.invalidate(); presentationTimer = nil
        guard let window, view.window === window, !view.isHiddenOrHasHiddenAncestor,
              let configuration = view.parcTooltip, isEligible(configuration) else {
            state.cancelSchedule(); updateMonitor(); return
        }
        let shortcut = shortcut(for: configuration)
        let content = TooltipView.Content(label: configuration.label, keycaps: shortcut.map(TooltipKeycap.keycaps) ?? [],
                                          corners: TooltipCorners(anchor: configuration.anchor),
                                          palette: configuration.palette ?? palette ?? .neutral,
                                          maxWidth: configuration.maxWidth ?? TooltipConfiguration.defaultMaxWidth,
                                          style: configuration.style)
        let presenter = self.presenter ?? TooltipPresenter(parent: window)
        guard presenter.present(content, anchor: configuration.anchor, from: view, rect: configuration.anchorRect ?? view.bounds) else {
            presenter.close(); self.presenter = nil; presentedShortcut = nil
            state.didFailToPresent(); syncTimers(); updateMonitor()
            return
        }
        if self.presenter == nil { pressedModifiers = NSEvent.modifierFlags.intersection(KeyboardShortcut.modifierMask); pressedCharacters = nil }
        self.presenter = presenter
        presentedShortcut = shortcut
        targetView = view
        state.didPresent(ObjectIdentifier(view))
        presenter.setPressed(modifiers: pressedModifiers, characters: pressedCharacters)
        hitTestTimer?.invalidate()
        hitTestTimer = Timer.scheduledTimer(withTimeInterval: TooltipTiming.hitTestInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.verifyPointer() }
        }
        updateMonitor()
    }

    private func verifyPointer() {
        guard state.isPresented else { return }
        if let view = currentView, isPointer(over: view) { return }
        entered.removeAll { $0.view.map { !holdsPointer($0) } ?? true }
        if currentView == nil { hide(TooltipTiming.exitDuration) } else { pointerLeft() }
        updateMonitor()
    }

    private func holdsPointer(_ view: NSView) -> Bool {
        guard let window = view.window, window === self.window, !view.isHiddenOrHasHiddenAncestor else { return false }
        return view.visibleRect.contains(view.convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func hide(_ duration: TimeInterval) {
        apply(state.hide(State.Fade(duration: duration), now: Date()))
    }

    private func apply(_ fade: State.Fade?) {
        syncTimers()
        guard let fade, let presenter else { updateMonitor(); return }
        presenter.dismiss(duration: fade.duration, delay: fade.delay) { [weak self, weak presenter] in
            guard let self, let presenter, self.presenter === presenter, self.state.fadeDidFinish() else { return }
            self.presenter = nil; self.presentedShortcut = nil
            self.updateMonitor()
        }
    }

    private func syncTimers() {
        if !state.isScheduled { presentationTimer?.invalidate(); presentationTimer = nil }
        if !state.isPresented { hitTestTimer?.invalidate(); hitTestTimer = nil }
    }

    private func configurationDidChange(for view: NSView) {
        guard state.target == ObjectIdentifier(view) else { return }
        if state.isPresented {
            if let configuration = view.parcTooltip, isEligible(configuration), isPointer(over: view) {
                present(view)
            } else {
                hide(TooltipTiming.exitDuration)
            }
        } else if view.parcTooltip == nil {
            state.cancelSchedule(); syncTimers(); updateMonitor()
        }
    }

    private func tearDown() {
        stopTimer?.invalidate(); stopTimer = nil
        presenter?.close(); presenter = nil; presentedShortcut = nil
        state = State(); entered.removeAll()
        syncTimers(); updateMonitor()
    }

    private func updateMonitor() {
        entered.removeAll { $0.view.map { $0.window !== window || $0.isHiddenOrHasHiddenAncestor } ?? true }
        let active = !entered.isEmpty || state.isShowing || state.phase != .tracking
        if active, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown,
                                                                  .scrollWheel, .keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        } else if !active, let monitor {
            NSEvent.removeMonitor(monitor); self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        let now = Date()
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            apply(state.hide(State.Fade(duration: TooltipTiming.interruptionDuration), now: now))
        case .scrollWheel:
            apply(state.hide(State.Fade(duration: TooltipTiming.interruptionDuration), scrolled: true, now: now))
        case .keyDown:
            pressedModifiers = event.modifierFlags.intersection(KeyboardShortcut.modifierMask)
            let chord = KeyboardShortcut.keypadKey(forPhysicalCode: event.keyCode) == nil ? nil : Self.eventChord?(event)
            pressedCharacters = chord?.matchesPhysicalKey == true ? chord?.key : event.charactersIgnoringModifiers
            presenter?.setPressed(modifiers: pressedModifiers, characters: pressedCharacters)
            apply(state.keyDown(escape: event.keyCode == UInt16(kVK_Escape), modifiers: pressedModifiers,
                                characters: pressedCharacters, shortcut: presentedShortcut, now: now))
        case .keyUp:
            pressedCharacters = nil
            presenter?.setPressed(modifiers: pressedModifiers, characters: pressedCharacters)
        case .flagsChanged:
            pressedModifiers = event.modifierFlags.intersection(KeyboardShortcut.modifierMask)
            presenter?.setPressed(modifiers: pressedModifiers, characters: pressedCharacters)
        default: break
        }
        updateMonitor()
    }
}

@MainActor private final class TooltipTracker: NSResponder {
    private static let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    private weak var view: NSView?
    var configuration: TooltipConfiguration
    private weak var trackingArea: NSTrackingArea?

    private init(view: NSView, configuration: TooltipConfiguration) {
        self.view = view; self.configuration = configuration
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func attached(to view: NSView) -> TooltipTracker? { objc_getAssociatedObject(view, key) as? TooltipTracker }

    static func attach(_ configuration: TooltipConfiguration, to view: NSView) {
        let tracker = TooltipTracker(view: view, configuration: configuration)
        objc_setAssociatedObject(view, key, tracker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: tracker, userInfo: nil)
        view.addTrackingArea(area)
        tracker.trackingArea = area
    }

    func detach() {
        guard let view else { return }
        if let trackingArea { view.removeTrackingArea(trackingArea) }
        objc_setAssociatedObject(view, Self.key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let view, let window = view.window else { return }
        TooltipController.controller(for: window).mouseEntered(view, event: event)
    }
    override func mouseExited(with event: NSEvent) {
        guard let view, let window = view.window else { return }
        TooltipController.controller(for: window).mouseExited(view)
    }
    override func mouseMoved(with event: NSEvent) {
        guard let window = event.window else { return }
        TooltipController.controller(for: window).mouseMoved(event)
    }
}

@MainActor final class TooltipPresenter {
    private weak var parent: NSWindow?
    private let window: NSWindow
    private let view = TooltipView(content: TooltipView.Content(label: "", keycaps: [], corners: TooltipCorners(anchor: .bottomTrailing),
                                                                palette: .neutral, maxWidth: TooltipConfiguration.defaultMaxWidth))
    private var animation: UUID?

    init(parent: NSWindow) {
        self.parent = parent
        window = TooltipWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = view
    }

    func present(_ content: TooltipView.Content, anchor: TooltipConfiguration.Anchor, from anchorView: NSView, rect: NSRect) -> Bool {
        guard let parent, anchorView.window === parent else {
            NSLog("Cannot present tooltip. View or window hierarchy is unexpected."); return false
        }
        let frame = parent.frame
        let anchorRect = anchorView.convert(rect, to: nil)
        let screens = NSScreen.screens
        let index = TooltipPlacement.screenIndex(containing: parent.convertToScreen(anchorRect), screens: screens.map(\.frame))
        guard let screen = index.map({ screens[$0] }) ?? parent.screen else {
            NSLog("Cannot present tooltip. View or window hierarchy is unexpected."); return false
        }
        view.backingScale = screen.backingScaleFactor
        view.content = content
        let mouse = parent.mouseLocationOutsideOfEventStream
        guard let placed = TooltipPlacement.screenFrame(
            preferred: anchor, size: view.contentLayout.size,
            anchorRect: CGRect(x: anchorRect.minX, y: frame.height - anchorRect.maxY, width: anchorRect.width, height: anchorRect.height),
            mouse: CGPoint(x: mouse.x, y: frame.height - mouse.y), windowFrame: frame, screenFrame: screen.frame) else {
            NSLog("Could not find a viable frame to present tooltip."); return false
        }
        if window.parent == nil { parent.addChildWindow(window, ordered: .above) }
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        let margin = TooltipView.margin(scale: screen.backingScaleFactor)
        window.setFrame(placed.insetBy(dx: -margin, dy: -margin), display: true)
        animateOpacity(to: 1, duration: TooltipTiming.presentDuration)
        return true
    }

    func setPressed(modifiers: NSEvent.ModifierFlags, characters: String?) {
        view.setPressed(modifiers: modifiers, characters: characters)
    }

    func dismiss(duration: TimeInterval, delay: TimeInterval, completion: @escaping () -> Void) {
        animateOpacity(to: 0, duration: duration, delay: delay) { [weak self] in
            self?.close()
            completion()
        }
    }

    func close() {
        animation = nil
        view.layer?.removeAnimation(forKey: "alpha_animation")
        parent?.removeChildWindow(window)
        window.close()
    }

    private func animateOpacity(to target: Float, duration: CFTimeInterval, delay: CFTimeInterval = 0,
                                completion: (() -> Void)? = nil) {
        let token = UUID()
        animation = token
        guard let layer = view.layer else { completion?(); return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = target
        fade.duration = duration
        fade.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .both
        CATransaction.begin()
        if let completion {
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.animation == token else { return }
                    completion()
                }
            }
        }
        layer.add(fade, forKey: "alpha_animation")
        layer.opacity = target
        CATransaction.commit()
    }
}

private final class TooltipWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func isAccessibilityElement() -> Bool { false }
}
