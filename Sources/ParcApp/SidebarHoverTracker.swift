import AppKit
import QuartzCore

///
///
/// mouse-moved monitor re-tests each region against the screen pointer, so the
/// zones beyond the window frame work. It listens only while the app is active
/// and the window is key. Losing either stops the listener, resets every
///
///
@MainActor final class SidebarHoverTracker {
    weak var view: NSView?
    /// Regions in `view` coordinates for the given states; the edge zones widen while held.
    var regions: ((SidebarHoverInfo) -> [SidebarHoverRegion: NSRect])?
    var onChange: ((SidebarHoverInfo) -> Void)?
    var mouseLocation: () -> NSPoint = { NSEvent.mouseLocation }
    var canListen: (() -> Bool)?
    /// WindowViewController sets shouldTrackUpdates to !isSidebarResizing. Off
    ///
    ///
    /// whose first report waits for the next main-queue turn or an earlier
    /// refresh, so it never lands inside the caller's own transaction (a Parc
    /// ordering choice).
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
    /// A stop belongs to one listener; a linger timer to one tracker, and acts
    ///
    /// inside state), a listener restart does not cancel pending lingers.
    private var listenerGeneration = 0
    private var trackerGeneration = 0
    private var lastMove: CFTimeInterval = 0
    private var refreshPending = false
    ///
    /// on every moved event; only the work item whose time still matches acts.
    /// Parc keeps that 0.08 s-after-lastMove stop and does not enqueue another
    /// item for a lastMove that already has one. It also skips arming when no
    /// region can still promote to hasStopped (ordinary in-page motion).
    private var stopPending = false
    /// Arms of the 0.08 s stop work item; tests assert in-page motion stays at 0.
    private(set) var stopScheduleCount = 0
    /// Converted screen rects for the current hover info and window/view
    ///
    /// tests those; Parc's regions closure previously rebuilt and converted
    /// them on every pass of every event.
    private var screenRects: ScreenRects?
    /// Screen point of the last containment pass. An identical point with valid
    /// cached rects cannot change the hover bit.
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
        // The monitor sees moves beyond the frame only if the window accepts them.
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
    /// Final: no listener, report or refresh can follow.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        stopListening(); trackerGeneration &+= 1
        dropScreenRects()
        onChange = nil; regions = nil
    }
    /// Geometry changed: re-test containment at the current pointer once the layout settles.
    func setNeedsRefresh() {
        guard !isInvalidated else { return }
        dropScreenRects()
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.refresh()
        }
    }
    /// Re-tests the pointer, first starting or stopping the listener for the
    /// current app, key and enabled state.
    func refresh() {
        guard !isInvalidated else { return }
        let wasListening = monitor != nil
        updateListening()
        // A listener that just started has already reported the pointer.
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
        // MouseListener reports the current location once when it starts.
        mouseMoved()
    }
    private func stopListening() {
        listenerGeneration &+= 1
        stopPending = false
        dropScreenRects()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    ///
    /// when the pointer or cached zones can change a hover bit; the 0.08 s stop
    /// arms only while an edge zone can still promote.
    func mouseMoved() {
        evaluate()
        guard tracking.needsStopPromotion else { return }
        lastMove = CACurrentMediaTime()
        scheduleStop()
    }
    private func scheduleStop() {
        guard !stopPending else { return }
        stopPending = true
        stopScheduleCount += 1
        enqueueStop(token: listenerGeneration)
    }
    private func enqueueStop(token: Int) {
        let remaining = max(0, SidebarHoverTracking.stopDelay - (CACurrentMediaTime() - lastMove))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.listenerGeneration == token else { return }
            let leftover = self.lastMove + SidebarHoverTracking.stopDelay - CACurrentMediaTime()
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
        // Identical pointer with live screen rects: enter/leave bits cannot
        // change without a geometry refresh dropping the cache.
        if let lastEvaluatedPoint, lastEvaluatedPoint == point, screenRects != nil {
            return
        }
        var changed = false
        //
        //
        // was not recovered. Parc re-tests until containment settles (at most
        // four passes) and reports once. Later passes run only while info is
        // still changing; converted rects are reused while info and geometry
        // stay the same.
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
        DispatchQueue.main.asyncAfter(deadline: .now() + region.lingerRequirement) { [weak self] in
            guard let self, self.trackerGeneration == token, self.monitor != nil, self.tracking.linger(region) else { return }
            self.onChange?(self.tracking.info)
        }
    }
}
