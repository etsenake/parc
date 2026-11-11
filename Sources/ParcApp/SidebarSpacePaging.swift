import AppKit
import QuartzCore

struct SidebarSpacePagingModel {
    static let trackingFactor: CGFloat = -0.5
    static let flingVelocity: CGFloat = 5
    static let discreteGap: CFTimeInterval = 0.05
    static let discreteThreshold: CGFloat = 1
    static let discreteCooldown: CFTimeInterval = 0.25
    static let springResponse: CGFloat = 0.4
    static let velocityWindow: CFTimeInterval = 0.1

    static func velocity(_ samples: [(time: CFTimeInterval, position: CGFloat)], at time: CFTimeInterval) -> CGFloat {
        let recent = samples.filter { time - $0.time <= velocityWindow }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return 0 }
        return (last.position - first.position) / CGFloat(last.time - first.time)
    }

    static func springValue(from: CGFloat, velocity: CGFloat, time: CGFloat) -> CGFloat {
        SidebarSpring.displacement(from: from, velocity: velocity, time: time, response: springResponse, damping: 1).x
    }

    static func isGestural(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, precise: Bool) -> Bool {
        (!phase.isEmpty || !momentumPhase.isEmpty) && precise
    }

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

    static func discreteStep(cumulative: CGFloat, inverted: Bool) -> Int {
        guard cumulative != 0 else { return 0 }
        return (cumulative > 0) != inverted ? -1 : 1
    }

    static func swipeStep(deltaX: CGFloat) -> Int { deltaX == 0 ? 0 : (deltaX >= 0 ? -1 : 1) }

    static func themePages(selected: Int, offset: CGFloat, width: CGFloat, count: Int) -> (left: Int, progress: CGFloat)? {
        let position = CGFloat(selected) - offset / width
        guard count > 1, width > 0, (0..<count).contains(selected), position.isFinite else { return nil }
        let left = min(max(Int(position.rounded(.down)), 0), count - 2)
        return (left, min(1, max(0, position - CGFloat(left))))
    }

    static func settleVelocity(_ velocity: CGFloat, position: CGFloat, targetOrigin: CGFloat) -> CGFloat {
        (velocity >= 0) == (targetOrigin < position) ? 0 : velocity
    }

    var cumulative: CGFloat = 0
    var lastEventTime: CFTimeInterval = 0
    var lastTriggerTime: CFTimeInterval = -.infinity

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

struct SidebarSpaceCreationGesture {
    static let presentationDistance: CGFloat = 15
    static let progressDistance: CGFloat = 22.5
    static let hold: CFTimeInterval = 0.1

    static func overscroll(selected: Int, offset: CGFloat, width: CGFloat, count: Int) -> CGFloat {
        CGFloat(selected - (count - 1)) * width - offset
    }
    static func presentation(_ overscroll: CGFloat) -> CGFloat { min(1, max(0, overscroll / presentationDistance)) }
    static func progress(_ overscroll: CGFloat) -> CGFloat { min(1, max(0, overscroll / progressDistance)) }

    private(set) var isActivated = false
    private var activatedAt: CFTimeInterval?

    mutating func update(progress: CGFloat, now: CFTimeInterval) -> Bool {
        let full = progress >= 1
        if !full { activatedAt = nil } else if activatedAt == nil { activatedAt = now }
        defer { isActivated = full }
        return full != isActivated
    }

    mutating func release(now: CFTimeInterval) -> Bool {
        defer { activatedAt = nil }
        guard let activatedAt else { return false }
        return now - activatedAt > Self.hold
    }
}

final class SidebarPagingScrollView: NSScrollView {
    var offerScroll: (NSEvent) -> Bool = { _ in false }
    override func scrollWheel(with event: NSEvent) {
        if !offerScroll(event) { super.scrollWheel(with: event) }
    }
}

struct SidebarSpring {
    let response: CGFloat
    let damping: CGFloat
    private var start: CFTimeInterval = 0
    private var from: CGFloat = 0
    private var velocity: CGFloat = 0
    private var target: CGFloat = 0

    init(response: CGFloat, damping: CGFloat) {
        precondition(damping > 0 && damping <= 1, "an overdamped spring is not modelled")
        self.response = response; self.damping = damping
    }

    mutating func place(_ value: CGFloat) {
        from = value; target = value; velocity = 0
    }

    mutating func retarget(_ value: CGFloat, now: CFTimeInterval) {
        let current = self.value(at: now), speed = self.speed(at: now)
        start = now; from = current; velocity = speed; target = value
    }

    func value(at now: CFTimeInterval) -> CGFloat { target + displacement(at: now).x }
    func speed(at now: CFTimeInterval) -> CGFloat { displacement(at: now).v }

    func isSettled(at now: CFTimeInterval) -> Bool {
        let d = displacement(at: now)
        return abs(d.x) < 0.001 && abs(d.v) < 0.01
    }

    private func displacement(at now: CFTimeInterval) -> (x: CGFloat, v: CGFloat) {
        Self.displacement(from: from - target, velocity: velocity, time: CGFloat(now - start), response: response, damping: damping)
    }

    static func displacement(from x0: CGFloat, velocity v0: CGFloat, time t: CGFloat,
                             response: CGFloat, damping: CGFloat) -> (x: CGFloat, v: CGFloat) {
        let omega = 2 * .pi / response
        if damping < 1 {
            let decay = damping * omega, wd = omega * (1 - damping * damping).squareRoot()
            let b = (v0 + decay * x0) / wd
            let e = exp(-decay * t), c = cos(wd * t), s = sin(wd * t)
            let x = e * (x0 * c + b * s)
            return (x, -decay * x + e * (-x0 * wd * s + b * wd * c))
        }
        let b = v0 + omega * x0, e = exp(-omega * t)
        let x = (x0 + b * t) * e
        return (x, b * e - omega * x)
    }
}

enum SidebarSpacePagingPresentationSkip {
    static func shouldSkip(previous: CGFloat?, next: CGFloat) -> Bool {
        previous == next
    }
}

@MainActor final class SidebarSpacePager {
    struct Page: Equatable { let id: UUID; let profileID: UUID }

    var pages: () -> [Page] = { [] }
    var selectedID: () -> UUID? = { nil }
    var pageWidth: () -> CGFloat = { 0 }
    var canBegin: () -> Bool = { false }
    var canTrackSinglePageCreation: () -> Bool = { false }
    var canSelect: (Page) -> Bool = { _ in false }
    var select: (Page) -> Void = { _ in }
    var setOffset: (CGFloat) -> Void = { _ in }
    var trackingEnded: () -> Void = {}
    var now: () -> CFTimeInterval = { CACurrentMediaTime() }

    private var model = SidebarSpacePagingModel()
    private struct Tracking {
        let begin: Int
        var position: CGFloat
        var samples: [(time: CFTimeInterval, position: CGFloat)]
    }
    private var tracking: Tracking?
    private var ownsMomentum = false
    private(set) var offset: CGFloat = 0
    private var presentedOffset: CGFloat?
    private var spring: (start: CFTimeInterval, from: CGFloat, velocity: CGFloat)?
    private var timer: Timer?

    var isTracking: Bool { tracking != nil }
    var isAnimating: Bool { spring != nil }
    private var selecting = false
    private func choose(_ page: Page) {
        selecting = true; select(page); selecting = false
    }

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

    func cancel() {
        tracking = nil; ownsMomentum = false
        place(0)
    }

    func gesture(phase: NSEvent.Phase, momentum: Bool, dx: CGFloat, dy: CGFloat, time: CFTimeInterval) -> Bool {
        if momentum { return ownsMomentum }
        if phase.contains(.mayBegin) || phase.contains(.began) {
            if phase.contains(.began), var armed = tracking {
                guard abs(dx) >= abs(dy) else { tracking = nil; settle(to: armed.begin, from: armed, velocity: 0); return false }
                armed.samples = [(time, armed.position)]; tracking = armed
                return true
            }
            ownsMomentum = false
            guard abs(dx) >= abs(dy), canBegin(), let index = selectedIndex,
                  pages().count > 1 || canTrackSinglePageCreation() else { return false }
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
            if !phase.contains(.cancelled) { trackingEnded() }
            return true
        }
        return true
    }

    private func settle(to target: Int, from state: Tracking, velocity: CGFloat) {
        let width = pageWidth(), all = pages()
        var landed = state.begin
        if target != state.begin, all.indices.contains(target), canSelect(all[target]) {
            choose(all[target])
            if selectedID() == all[target].id { landed = target }
        }
        let origin = CGFloat(landed) * width
        let settle = SidebarSpacePagingModel.settleVelocity(velocity, position: state.position, targetOrigin: origin)
        place(origin - state.position)
        animate(velocity: -settle)
    }

    private func page(by delta: Int) {
        let all = pages()
        guard let index = selectedIndex, all.indices.contains(index + delta), canSelect(all[index + delta]) else { return }
        let start = CGFloat(index) * pageWidth() - offset
        choose(all[index + delta])
        guard selectedID() == all[index + delta].id else { return }
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

    private func present(_ value: CGFloat) {
        offset = value
        guard !SidebarSpacePagingPresentationSkip.shouldSkip(previous: presentedOffset, next: value) else { return }
        presentedOffset = value
        setOffset(value)
    }

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

    func tick() {
        guard let spring else { return }
        let t = CGFloat(now() - spring.start)
        let value = SidebarSpacePagingModel.springValue(from: spring.from, velocity: spring.velocity, time: t)
        if abs(value) < 0.25 && t > 0.05 { place(0); return }
        present(value)
    }
}
