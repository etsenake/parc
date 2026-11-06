import AppKit
import QuartzCore

///
///
///
///
///
///
/// animated Space selection. See docs/navigation.md "Mouse and trackpad
/// gesture inventory" for the evidence.
///
/// The model is pure value logic so the recovered thresholds stay checkable.
struct SidebarSpacePagingModel {
    /// Changed-phase tracking moves the page position by `-0.5 × scrollingDeltaX`
    ///
    static let trackingFactor: CGFloat = -0.5
    /// A release at or above this position velocity chooses its direction;
    ///
    static let flingVelocity: CGFloat = 5
    ///
    ///
    /// 0.25 s before the next page.
    static let discreteGap: CFTimeInterval = 0.05
    static let discreteThreshold: CGFloat = 1
    static let discreteCooldown: CFTimeInterval = 0.25
    ///
    static let springResponse: CGFloat = 0.4
    ///
    ///
    /// change by the elapsed seconds: page-strip points per second.
    static let velocityWindow: CFTimeInterval = 0.1

    /// Position velocity over the samples still inside the window at `time`;
    /// a release after the fingers paused has no velocity.
    static func velocity(_ samples: [(time: CFTimeInterval, position: CGFloat)], at time: CFTimeInterval) -> CGFloat {
        let recent = samples.filter { time - $0.time <= velocityWindow }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return 0 }
        return (last.position - first.position) / CGFloat(last.time - first.time)
    }

    /// A critically damped spring with the recovered response, from `from`
    /// toward 0 with an initial velocity, after `time` seconds.
    static func springValue(from: CGFloat, velocity: CGFloat, time: CGFloat) -> CGFloat {
        let omega = 2 * CGFloat.pi / springResponse
        return (from + (velocity + omega * from) * time) * exp(-omega * time)
    }

    ///
    static func isGestural(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, precise: Bool) -> Bool {
        (!phase.isEmpty || !momentumPhase.isEmpty) && precise
    }

    ///
    /// `velocity` are in page-strip points (origin i × width); the result stays
    /// within one page of the page under the pointer when the gesture began and
    /// within the strip.
    static func target(position: CGFloat, velocity: CGFloat, width: CGFloat, count: Int, begin: Int) -> Int {
        guard count > 0, width > 0 else { return begin }
        var index: Int
        if abs(velocity) >= flingVelocity {
            index = Int((position / width).rounded(.down)) + (velocity > 0 ? 1 : 0)
        } else {
            index = Int((position / width).rounded())
        }
        index = min(max(index, begin - 1), begin + 1)
        return min(max(index, 0), count - 1)
    }

    ///
    /// previous page and +1 for the next. Positive deltas go back unless the
    /// device direction is inverted.
    static func discreteStep(cumulative: CGFloat, inverted: Bool) -> Int {
        guard cumulative != 0 else { return 0 }
        return (cumulative > 0) != inverted ? -1 : 1
    }

    ///
    static func swipeStep(deltaX: CGFloat) -> Int { deltaX == 0 ? 0 : (deltaX >= 0 ? -1 : 1) }

    ///
    /// pages at the floor and ceiling of the strip's fractional position,
    ///
    ///
    /// strip's offset from the selected page, as `SidebarSpacePager` draws it.
    static func themePages(selected: Int, offset: CGFloat, width: CGFloat, count: Int) -> (left: Int, progress: CGFloat)? {
        let position = CGFloat(selected) - offset / width
        guard count > 1, width > 0, (0..<count).contains(selected), position.isFinite else { return nil }
        let left = min(max(Int(position.rounded(.down)), 0), count - 2)
        return (left, min(1, max(0, position - CGFloat(left))))
    }

    ///
    /// chosen page is dropped before the settle animation.
    static func settleVelocity(_ velocity: CGFloat, position: CGFloat, targetOrigin: CGFloat) -> CGFloat {
        (velocity >= 0) == (targetOrigin < position) ? 0 : velocity
    }

    var cumulative: CGFloat = 0
    var lastEventTime: CFTimeInterval = 0
    var lastTriggerTime: CFTimeInterval = -.infinity

    /// Feeds one non-gestural event; returns the page step it triggers.
    mutating func discrete(deltaX: CGFloat, inverted: Bool, now: CFTimeInterval) -> Int {
        guard now - lastTriggerTime > Self.discreteCooldown else { return 0 }
        if now - lastEventTime > Self.discreteGap { cumulative = 0 }
        lastEventTime = now
        cumulative += deltaX
        guard abs(cumulative) > Self.discreteThreshold else { return 0 }
        let step = Self.discreteStep(cumulative: cumulative, inverted: inverted)
        cumulative = 0; lastTriggerTime = now
        return step
    }
}

/// True no-op gate for Space-strip presentation. Spring ticks and `place`
/// that would re-present the same strip offset skip `setOffset`; a changed
/// offset still presents. The 120 Hz timer keeps running while the spring can
/// still move pixels and only idle-stops on settle via `place`.
enum SidebarSpacePagingPresentationSkip {
    static func shouldSkip(previous: CGFloat?, next: CGFloat) -> Bool {
        previous == next
    }
}

/// Drives the paging gesture for one sidebar. The owner supplies its ordered
/// Spaces, the selected one, availability and the genuine selection route,
/// and draws the page strip at a horizontal offset: 0 shows the selected
/// Space's page at rest, a negative offset reveals the next Space's page on
/// the right and a positive one the previous Space's page on the left, as
///
@MainActor final class SidebarSpacePager {
    struct Page: Equatable { let id: UUID; let profileID: UUID }

    var pages: () -> [Page] = { [] }
    var selectedID: () -> UUID? = { nil }
    var pageWidth: () -> CGFloat = { 0 }
    var canBegin: () -> Bool = { false }
    var canSelect: (Page) -> Bool = { _ in false }
    var select: (Page) -> Void = { _ in }
    /// Draws the strip at an offset in points (see the type comment).
    var setOffset: (CGFloat) -> Void = { _ in }
    /// The animation clock; replaceable for isolated checks.
    var now: () -> CFTimeInterval = { CACurrentMediaTime() }

    private var model = SidebarSpacePagingModel()
    private struct Tracking {
        let begin: Int
        var position: CGFloat
        var samples: [(time: CFTimeInterval, position: CGFloat)]
    }
    private var tracking: Tracking?
    /// Momentum after a tracked gesture belongs to that gesture.
    private var ownsMomentum = false
    private(set) var offset: CGFloat = 0
    /// Last strip offset pushed through `setOffset`. Identical re-presents skip.
    private var presentedOffset: CGFloat?
    private var spring: (start: CFTimeInterval, from: CGFloat, velocity: CGFloat)?
    private var timer: Timer?

    var isTracking: Bool { tracking != nil }
    var isAnimating: Bool { spring != nil }
    /// The pager's own selection in flight: the owner renders it
    /// synchronously, and that render is not a switch made elsewhere.
    private var selecting = false
    private func choose(_ page: Page) {
        selecting = true; select(page); selecting = false
    }

    /// A Space chosen another way (keyboard, menu, a dock click) slides in
    ///
    /// runs for every selection with `pagingAnimationSourcePage` as its
    ///
    /// beside the strip. Returns false when the pager owns the change or
    /// can't slide. A switch during a slide continues from where the page
    /// it left is on screen, within the one page the strip can show beside
    /// the selected one.
    @discardableResult
    func slideIn(from previous: Int, to current: Int) -> Bool {
        let all = pages(), width = pageWidth()
        guard previous != current, all.indices.contains(previous), all.indices.contains(current), width > 0,
              tracking == nil, !selecting, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        let base = spring != nil ? offset : 0
        place(min(width, max(-width, base + (current > previous ? width : -width))))
        animate(velocity: 0)
        return true
    }

    /// Returns true when the event was used for paging.
    func scrollWheel(_ event: NSEvent) -> Bool {
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        if SidebarSpacePagingModel.isGestural(phase: event.phase, momentumPhase: event.momentumPhase,
                                             precise: event.hasPreciseScrollingDeltas) {
            return gesture(phase: event.phase, momentum: !event.momentumPhase.isEmpty, dx: dx, dy: dy, time: event.timestamp)
        }
        guard abs(dx) > abs(dy), tracking == nil, canBegin() else { return false }
        let step = model.discrete(deltaX: dx, inverted: event.isDirectionInvertedFromDevice, now: now())
        if step != 0 { page(by: step) }
        return true
    }

    func swipe(_ event: NSEvent) -> Bool { swipe(deltaX: event.deltaX) }

    func swipe(deltaX: CGFloat) -> Bool {
        guard tracking == nil, canBegin() else { return false }
        let step = SidebarSpacePagingModel.swipeStep(deltaX: deltaX)
        guard step != 0 else { return false }
        page(by: step)
        return true
    }

    /// Ends any gesture and returns the strip to rest without animation, for
    /// a sidebar that leaves or a Space creation.
    func cancel() {
        tracking = nil; ownsMomentum = false
        place(0)
    }

    ///
    /// the recovered tracking can be checked without synthesized events.
    func gesture(phase: NSEvent.Phase, momentum: Bool, dx: CGFloat, dy: CGFloat, time: CFTimeInterval) -> Bool {
        if momentum { return ownsMomentum }
        if phase.contains(.mayBegin) || phase.contains(.began) {
            if phase.contains(.began), var armed = tracking {
                // A began event after may-begin must still be horizontal-dominant.
                guard abs(dx) >= abs(dy) else { tracking = nil; settle(to: armed.begin, from: armed, velocity: 0); return false }
                armed.samples = [(time, armed.position)]; tracking = armed
                return true
            }
            ownsMomentum = false
            //
            // |dx| ≥ |dy| that the owner accepts starts tracking from the
            // strip's current position.
            guard abs(dx) >= abs(dy), canBegin(), let index = selectedIndex, pages().count > 1 else { return false }
            let start = CGFloat(index) * pageWidth() - offset
            tracking = Tracking(begin: index, position: start, samples: [(time, start)])
            place(offset)
            return true
        }
        guard var current = tracking else { return false }
        if phase.contains(.changed) {
            current.position += SidebarSpacePagingModel.trackingFactor * dx
            current.samples.append((time, current.position))
            current.samples.removeAll { time - $0.time > SidebarSpacePagingModel.velocityWindow }
            tracking = current
            place(CGFloat(current.begin) * pageWidth() - current.position)
            return true
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            tracking = nil; ownsMomentum = true
            let velocity = phase.contains(.cancelled) ? 0
                : SidebarSpacePagingModel.velocity(current.samples, at: time)
            let target = phase.contains(.cancelled) ? current.begin
                : SidebarSpacePagingModel.target(position: current.position, velocity: velocity, width: pageWidth(),
                                                 count: pages().count, begin: current.begin)
            settle(to: target, from: current, velocity: velocity)
            return true
        }
        return true
    }

    ///
    /// refused or failed switch springs back to the original page from where
    /// the strip is.
    private func settle(to target: Int, from state: Tracking, velocity: CGFloat) {
        let width = pageWidth(), all = pages()
        var landed = state.begin
        if target != state.begin, all.indices.contains(target), canSelect(all[target]) {
            choose(all[target])
            if selectedID() == all[target].id { landed = target }
        }
        let origin = CGFloat(landed) * width
        let settle = SidebarSpacePagingModel.settleVelocity(velocity, position: state.position, targetOrigin: origin)
        // The selected page is now `landed`; keep the strip where it is.
        place(origin - state.position)
        animate(velocity: -settle)
    }

    private func page(by delta: Int) {
        let all = pages()
        guard let index = selectedIndex, all.indices.contains(index + delta), canSelect(all[index + delta]) else { return }
        let start = CGFloat(index) * pageWidth() - offset
        choose(all[index + delta])
        guard selectedID() == all[index + delta].id else { return }
        //
        place(CGFloat(index + delta) * pageWidth() - start)
        animate(velocity: 0)
    }

    private var selectedIndex: Int? {
        guard let id = selectedID() else { return nil }
        return pages().firstIndex { $0.id == id }
    }

    private func place(_ value: CGFloat) {
        spring = nil; timer?.invalidate(); timer = nil
        present(value)
    }

    /// Updates the model offset and pushes presentation only when the strip
    /// fingerprint changed. Identical values are a true no-op for layout.
    private func present(_ value: CGFloat) {
        offset = value
        guard !SidebarSpacePagingPresentationSkip.shouldSkip(previous: presentedOffset, next: value) else { return }
        presentedOffset = value
        setOffset(value)
    }

    /// The recovered animator: a critically damped spring with response
    ///
    /// strip and page the theme together. Reduce Motion places the
    /// strip at rest at once.
    private func animate(velocity: CGFloat) {
        guard offset != 0 else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { place(0); return }
        spring = (now(), offset, velocity)
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Advances the spring; exposed for isolated checks. Identical spring
    /// samples skip `setOffset` but leave the timer running until settle.
    func tick() {
        guard let spring else { return }
        let t = CGFloat(now() - spring.start)
        let value = SidebarSpacePagingModel.springValue(from: spring.from, velocity: spring.velocity, time: t)
        if abs(value) < 0.25 && t > 0.05 { place(0); return }
        present(value)
    }
}
