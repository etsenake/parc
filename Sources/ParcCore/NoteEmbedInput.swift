import Foundation

enum NoteEmbedPointerDecision: Equatable {
    case activate(UUID)
    case finish
    case none

    static func decide(pageUnderPointer: UUID?, active: UUID?, insideActive: Bool) -> NoteEmbedPointerDecision {
        if let page = pageUnderPointer, page != active { return .activate(page) }
        if active != nil, !insideActive { return .finish }
        return .none
    }
}

struct NoteEmbedScrollLatch: Equatable {
    enum Phase: Equatable { case began, changed, ended, momentum, momentumEnded, discrete }
    enum Target: Equatable { case page(UUID), note }
    enum Route: Equatable { case native, page, note }

    static let discreteRunGap: TimeInterval = 0.5

    private(set) var target: Target?
    private(set) var handedOver = false
    private var awaitingPageBegin = false
    private var lastDiscrete: TimeInterval?
    private var verticalBias: Double = 0

    var latchedPage: UUID? {
        if case .page(let id) = target { return id }
        return nil
    }

    var awaitsPageAcknowledgement: Bool { latchedPage != nil && !handedOver }

    func startsGesture(_ phase: Phase, time: TimeInterval) -> Bool {
        switch phase {
        case .began: return true
        case .discrete: return target == nil || lastDiscrete.map { time - $0 > Self.discreteRunGap } ?? true
        default: return false
        }
    }

    mutating func receive(_ phase: Phase, deltaX: Double, deltaY: Double, time: TimeInterval,
                          pageUnderPointer: UUID?) -> Route {
        if startsGesture(phase, time: time) {
            target = pageUnderPointer.map(Target.page) ?? .note
            handedOver = false
            awaitingPageBegin = phase == .began
            verticalBias = 0
        }
        if phase == .discrete { lastDiscrete = time } else { lastDiscrete = nil }
        if deltaX.isFinite && deltaY.isFinite { verticalBias += abs(deltaY) - abs(deltaX) }
        guard latchedPage != nil else { return .native }
        guard handedOver else { return .page }
        return phase == .ended ? .page : .note
    }

    mutating func pageScrollBegan(momentum: Bool) {
        if !momentum { awaitingPageBegin = false }
    }

    @discardableResult
    mutating func pageScrollUpdated(consumed: Bool) -> Bool {
        guard awaitsPageAcknowledgement, !awaitingPageBegin, !consumed, verticalBias > 0 else { return false }
        handedOver = true
        return true
    }

    static func noteOffset(_ offset: Double, delta: Double, flipped: Bool) -> Double {
        guard delta.isFinite else { return offset }
        return flipped ? offset - delta : offset + delta
    }
}

struct NoteEmbedEscapeConfirmation: Equatable {
    static let window: TimeInterval = 1

    private(set) var armedAt: TimeInterval?

    mutating func receive(prefersConfirmation: Bool, now: TimeInterval) -> Bool {
        if !prefersConfirmation {
            armedAt = nil
            return true
        }
        if let armedAt, now - armedAt >= 0, now - armedAt <= Self.window {
            self.armedAt = nil
            return true
        }
        armedAt = now
        return false
    }
}
