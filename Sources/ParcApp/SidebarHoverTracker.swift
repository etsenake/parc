import AppKit
import QuartzCore

@MainActor final class SidebarHoverTracker {
    weak var view: NSView?
    var regions: ((SidebarHoverInfo) -> [SidebarHoverRegion: NSRect])?
    var onChange: ((SidebarHoverInfo) -> Void)?
    var mouseLocation: () -> NSPoint = { NSEvent.mouseLocation }
    var canListen: (() -> Bool)?
    var now: () -> CFTimeInterval = { CACurrentMediaTime() }
    var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }
    var nextTurn: (@escaping @MainActor () -> Void) -> Void = { body in
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue, !isInvalidated else { return }
            if isEnabled { setNeedsRefresh() } else { stopListening(); tracking.reset(); trackerGeneration &+= 1 }
        }
    }
    var info: SidebarHoverInfo { tracking.info }
    var isListening: Bool { monitor != nil }
    private(set) var isInvalidated = false
    private var tracking = SidebarHoverTracking()
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var listenerGeneration = 0
    private var trackerGeneration = 0
    private var lastMove: CFTimeInterval = 0
    private var refreshPending = false
    private var stopPending = false
    private(set) var stopScheduleCount = 0
    private var screenRects: ScreenRects?
    private var lastEvaluatedPoint: NSPoint?

    private struct ScreenRects {
        var info: SidebarHoverInfo
        var windowFrame: NSRect
        var viewBounds: NSRect
        var screenFrame: NSRect
        var menuBarHeight: CGFloat
        var rects: [SidebarHoverRegion: NSRect]
    }

    func attach(to window: NSWindow) {
        guard !isInvalidated else { return }
        window.acceptsMouseMovedEvents = true
        let center = NotificationCenter.default
        for (name, object) in [(NSApplication.didBecomeActiveNotification, nil), (NSApplication.didResignActiveNotification, nil),
                               (NSWindow.didBecomeKeyNotification, window), (NSWindow.didResignKeyNotification, window)] as [(Notification.Name, NSWindow?)] {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateListening() }
            })
        }
        updateListening()
    }
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        stopListening(); trackerGeneration &+= 1
        dropScreenRects()
        onChange = nil; regions = nil
    }
    func setNeedsRefresh() {
        guard !isInvalidated else { return }
        dropScreenRects()
        guard !refreshPending else { return }
        refreshPending = true
        nextTurn { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.refresh()
        }
    }
    func refresh() {
        guard !isInvalidated else { return }
        let wasListening = monitor != nil
        updateListening()
        if wasListening, monitor != nil { evaluate() }
    }

    private func updateListening() {
        guard !isInvalidated else { return }
        let listen = isEnabled && (canListen?() ?? (NSApp.isActive && view?.window?.isKeyWindow == true))
        if !listen {
            guard monitor != nil else { return }
            stopListening()
            let before = tracking.info
            tracking.reset()
            if tracking.info != before { onChange?(tracking.info) }
            return
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.mouseMoved(); return event
        }
        mouseMoved()
    }
    private func stopListening() {
        listenerGeneration &+= 1
        stopPending = false
        dropScreenRects()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    func mouseMoved() {
        evaluate()
        guard tracking.needsStopPromotion else { return }
        lastMove = now()
        scheduleStop()
    }
    private func scheduleStop() {
        guard !stopPending else { return }
        stopPending = true
        stopScheduleCount += 1
        enqueueStop(token: listenerGeneration)
    }
    private func enqueueStop(token: Int) {
        let remaining = max(0, SidebarHoverTracking.stopDelay - (now() - lastMove))
        after(remaining) { [weak self] in
            guard let self, self.listenerGeneration == token else { return }
            let leftover = self.lastMove + SidebarHoverTracking.stopDelay - self.now()
            if leftover > 0 {
                self.enqueueStop(token: token)
                return
            }
            self.stopPending = false
            guard self.tracking.stop() else { return }
            self.onChange?(self.tracking.info)
        }
    }
    private func evaluate() {
        guard let view, let window = view.window, let regions else { return }
        let point = mouseLocation()
        if let lastEvaluatedPoint, lastEvaluatedPoint == point, screenRects != nil {
            return
        }
        var changed = false
        for _ in 0..<4 {
            let rects = convertedRects(view: view, window: window, regions: regions)
            let before = tracking.info
            let entered = tracking.update { region in
                rects[region]?.contains(point) ?? false
            }
            entered.forEach(scheduleLinger)
            guard tracking.info != before else { break }
            changed = true
        }
        lastEvaluatedPoint = point
        if changed { onChange?(tracking.info) }
    }
    private func convertedRects(view: NSView, window: NSWindow,
                                regions: (SidebarHoverInfo) -> [SidebarHoverRegion: NSRect]) -> [SidebarHoverRegion: NSRect] {
        let info = tracking.info, windowFrame = window.frame, viewBounds = view.bounds
        let screenFrame = window.screen?.frame ?? .zero
        let menuBarHeight = NSApp.mainMenu?.menuBarHeight ?? 0
        if let screenRects, screenRects.info == info, screenRects.windowFrame == windowFrame,
           screenRects.viewBounds == viewBounds, screenRects.screenFrame == screenFrame,
           screenRects.menuBarHeight == menuBarHeight {
            return screenRects.rects
        }
        let converted = regions(info).mapValues { window.convertToScreen(view.convert($0, to: nil)) }
        screenRects = ScreenRects(info: info, windowFrame: windowFrame, viewBounds: viewBounds,
                                  screenFrame: screenFrame, menuBarHeight: menuBarHeight, rects: converted)
        return converted
    }
    private func dropScreenRects() {
        screenRects = nil
        lastEvaluatedPoint = nil
    }
    private func scheduleLinger(_ region: SidebarHoverRegion) {
        let token = trackerGeneration
        after(region.lingerRequirement) { [weak self] in
            guard let self, self.trackerGeneration == token, self.monitor != nil, self.tracking.linger(region) else { return }
            self.onChange?(self.tracking.info)
        }
    }
}
