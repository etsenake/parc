import Foundation

///
///
/// layout on every event; the owner persists only the end result.
struct SidebarResizeGesture {
    static let minimumWidth = 164.0
    static let maximumWidth = 500.0
    /// Half the minimum: a live hidden preview below it, a collapse at or below it on release.
    static let collapseThreshold = 82.0
    /// Two 8 pt insets, four 47 pt favorites and three 8 pt gaps.
    static let defaultWidth = 228.0
    static let snapBand = 14.0
    static let snapMaximumVelocity = 50.0
    static let releaseFeedbackHold: TimeInterval = 0.5

    enum Event: Equatable {
        /// Pulse the indicator and perform the generic haptic.
        case snapEngaged
        /// The generic haptic is performed only after a hold longer than 0.5 s.
        case snapReleased(haptic: Bool)
        case previewHiddenChanged(Bool)
        case breakpointChanged(Int)
    }
    enum Completion { case ended, cancelled, failed }
    struct Change: Equatable {
        var width: Double
        var widthChanged: Bool
        var events: [Event]
    }
    struct Commit: Equatable {
        var width: Double
        var collapses: Bool
    }

    let widthOnBegin: Double
    ///
    let locked: Bool
    private let breakpoints: [Double]
    private(set) var canSnap = false
    private(set) var timeOfSnap: TimeInterval?
    private(set) var effectiveWidth: Double
    private(set) var breakpointIndex: Int
    var isSnapped: Bool { timeOfSnap != nil }
    var isPreviewingHidden: Bool { effectiveWidth == 0 }

    init(width: Double, locked: Bool, breakpoints: [Double] = []) {
        let width = width.isFinite ? width : Self.defaultWidth
        widthOnBegin = width; effectiveWidth = width
        self.locked = locked; self.breakpoints = breakpoints
        breakpointIndex = Self.breakpointIndex(for: width, in: breakpoints)
    }

    static func clamped(_ width: Double) -> Double { min(maximumWidth, max(minimumWidth, width)) }
    static func breakpointIndex(for width: Double, in breakpoints: [Double]) -> Int {
        breakpoints.firstIndex { width >= 0 && width < $0 } ?? breakpoints.count
    }
    private func proposedWidth(_ translationX: Double) -> Double {
        (widthOnBegin + translationX).rounded(.toNearestOrAwayFromZero)
    }

    mutating func change(translationX: Double, velocityX: Double,
                         now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Change {
        guard translationX.isFinite, velocityX.isFinite else {
            return Change(width: effectiveWidth, widthChanged: false, events: [])
        }
        var events: [Event] = []
        let rounded = proposedWidth(translationX)
        var proposed = rounded < Self.collapseThreshold ? 0 : Self.clamped(rounded)
        let near = abs(Self.defaultWidth - proposed) < Self.snapBand
        if canSnap, near, isSnapped {
            proposed = Self.defaultWidth
        } else if canSnap, near, abs(velocityX) < Self.snapMaximumVelocity,
                  (proposed > Self.defaultWidth) != (velocityX < 0) {
            timeOfSnap = now; proposed = Self.defaultWidth
            events.append(.snapEngaged)
        } else {
            // The band arms only after the pointer has been outside it once.
            canSnap = canSnap || !near
            if let snapped = timeOfSnap {
                timeOfSnap = nil
                events.append(.snapReleased(haptic: now - snapped > Self.releaseFeedbackHold))
            }
        }
        if (proposed == 0) != (effectiveWidth == 0) { events.append(.previewHiddenChanged(proposed == 0)) }
        let changed = proposed != effectiveWidth
        effectiveWidth = proposed
        let index = Self.breakpointIndex(for: proposed, in: breakpoints)
        if index != breakpointIndex { breakpointIndex = index; events.append(.breakpointChanged(index)) }
        return Change(width: proposed, widthChanged: changed, events: events)
    }

    /// Cancelled and failed gestures restore the starting width. A locked
    /// release at or below the threshold keeps that width and collapses.
    func end(_ completion: Completion, translationX: Double) -> Commit {
        switch completion {
        case .ended:
            if locked, translationX.isFinite, proposedWidth(translationX) <= Self.collapseThreshold {
                return Commit(width: Self.clamped(widthOnBegin), collapses: true)
            }
            return Commit(width: Self.clamped(effectiveWidth), collapses: false)
        case .cancelled, .failed:
            return Commit(width: Self.clamped(widthOnBegin), collapses: false)
        }
    }
}

///
/// PersistedWindowState, CodableWindowData) beside the app-wide
/// `sidebarViewPreferences` {sidebarMode, sidebarWidth} of WindowsState,
/// PersistedWindowsState and StorableWindows (Swift field metadata). Parc's
/// app-wide value is BrowserSettings.sidebarWidth: it seeds each new window,
/// and a window's completed drag or reset updates that window and the
/// app-wide value only. A reopened window takes its own saved width instead
/// (BrowserWindowRecord).
struct SidebarWindowWidth: Equatable {
    /// Posted with the store as object after Parc's Settings slider (an
    ///
    /// then applies to every open window of that store.
    static let settingDidChange = Notification.Name("ParcSidebarWidthSettingDidChange")

    private(set) var width: Double
    init(lastUsed: Double, restored: Double? = nil) { width = SidebarResizeGesture.clamped(restored ?? lastUsed) }
    /// The end of this window's drag; returns the app-wide last-used width to
    ///
    /// sends `sidebarResizeGestureDidComplete` with the start width after a
    ///
    /// untraced, so here no width changes and the last-used value stays.
    mutating func end(_ commit: SidebarResizeGesture.Commit, _ completion: SidebarResizeGesture.Completion) -> Double? {
        width = SidebarResizeGesture.clamped(commit.width)
        return completion == .ended && !commit.collapses ? width : nil
    }
    /// The double-click reset: 228 in this window and as the last-used width.
    mutating func reset() -> Double { width = SidebarResizeGesture.defaultWidth; return width }
    mutating func applySetting(_ value: Double) { width = SidebarResizeGesture.clamped(value) }
}
