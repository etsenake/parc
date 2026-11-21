import Foundation

package struct SidebarResizeGesture {
    package static let minimumWidth = 164.0
    package static let maximumWidth = 500.0
    package static let collapseThreshold = 82.0
    package static let defaultWidth = 228.0
    package static let snapBand = 14.0
    package static let snapMaximumVelocity = 50.0
    package static let releaseFeedbackHold: TimeInterval = 0.5

    package enum Event: Equatable {
        case snapEngaged
        case snapReleased(haptic: Bool)
        case previewHiddenChanged(Bool)
        case breakpointChanged(Int)
    }
    package enum Completion { case ended, cancelled, failed }
    package struct Change: Equatable {
        package var width: Double
        package var widthChanged: Bool
        package var events: [Event]

        package init(width: Double, widthChanged: Bool, events: [Event]) {
            self.width = width
            self.widthChanged = widthChanged
            self.events = events
        }
    }
    package struct Commit: Equatable {
        package var width: Double
        package var collapses: Bool
    }

    package let widthOnBegin: Double
    package let locked: Bool
    private let breakpoints: [Double]
    package private(set) var canSnap = false
    package private(set) var timeOfSnap: TimeInterval?
    package private(set) var effectiveWidth: Double
    package private(set) var breakpointIndex: Int
    package var isSnapped: Bool { timeOfSnap != nil }
    package var isPreviewingHidden: Bool { effectiveWidth == 0 }

    package init(width: Double, locked: Bool, breakpoints: [Double] = []) {
        let width = width.isFinite ? width : Self.defaultWidth
        widthOnBegin = width; effectiveWidth = width
        self.locked = locked; self.breakpoints = breakpoints
        breakpointIndex = Self.breakpointIndex(for: width, in: breakpoints)
    }

    package static func clamped(_ width: Double) -> Double { min(maximumWidth, max(minimumWidth, width)) }
    package static func breakpointIndex(for width: Double, in breakpoints: [Double]) -> Int {
        breakpoints.firstIndex { width >= 0 && width < $0 } ?? breakpoints.count
    }
    private func proposedWidth(_ translationX: Double) -> Double {
        (widthOnBegin + translationX).rounded(.toNearestOrAwayFromZero)
    }

    package mutating func change(translationX: Double, velocityX: Double,
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

    package func end(_ completion: Completion, translationX: Double) -> Commit {
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

package struct SidebarWindowWidth: Equatable {
    package static let settingDidChange = Notification.Name("ParcSidebarWidthSettingDidChange")

    package private(set) var width: Double
    package init(lastUsed: Double, restored: Double? = nil) { width = SidebarResizeGesture.clamped(restored ?? lastUsed) }
    package mutating func end(_ commit: SidebarResizeGesture.Commit, _ completion: SidebarResizeGesture.Completion) -> Double? {
        width = SidebarResizeGesture.clamped(commit.width)
        return completion == .ended && !commit.collapses ? width : nil
    }
    package mutating func reset() -> Double { width = SidebarResizeGesture.defaultWidth; return width }
    package mutating func applySetting(_ value: Double) { width = SidebarResizeGesture.clamped(value) }
}
