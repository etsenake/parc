import Foundation

package enum NoteEmbedPointerDecision: Equatable {
    case activate(UUID)
    case finish
    case none

    package static func decide(pageUnderPointer: UUID?, active: UUID?, insideActive: Bool) -> NoteEmbedPointerDecision {
        if let page = pageUnderPointer, page != active { return .activate(page) }
        if active != nil, !insideActive { return .finish }
        return .none
    }
}

package struct NoteEmbedScrollLatch: Equatable {
    package enum Phase: Equatable { case began, changed, ended, momentum, momentumEnded, discrete }
    package enum Target: Equatable { case page(UUID), note }
    package enum Route: Equatable { case native, page, note }

    package static let discreteRunGap: TimeInterval = 0.5

    package private(set) var target: Target?
    package private(set) var handedOver = false
    private var awaitingPageBegin = false
    private var lastDiscrete: TimeInterval?
    private var verticalBias: Double = 0

    package var latchedPage: UUID? {
        if case .page(let id) = target { return id }
        return nil
    }

    package var awaitsPageAcknowledgement: Bool { latchedPage != nil && !handedOver }

    package init(target: Target? = nil, handedOver: Bool = false) {
        self.target = target
        self.handedOver = handedOver
    }

    package func startsGesture(_ phase: Phase, time: TimeInterval) -> Bool {
        switch phase {
        case .began: return true
        case .discrete: return target == nil || lastDiscrete.map { time - $0 > Self.discreteRunGap } ?? true
        default: return false
        }
    }

    package mutating func receive(_ phase: Phase, deltaX: Double, deltaY: Double, time: TimeInterval,
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

    package mutating func pageScrollBegan(momentum: Bool) {
        if !momentum { awaitingPageBegin = false }
    }

    @discardableResult
    package mutating func pageScrollUpdated(consumed: Bool) -> Bool {
        guard awaitsPageAcknowledgement, !awaitingPageBegin, !consumed, verticalBias > 0 else { return false }
        handedOver = true
        return true
    }

    package static func noteOffset(_ offset: Double, delta: Double, flipped: Bool) -> Double {
        guard delta.isFinite else { return offset }
        return flipped ? offset - delta : offset + delta
    }
}

package struct NoteEmbedEscapeConfirmation: Equatable {
    package static let window: TimeInterval = 1

    package private(set) var armedAt: TimeInterval?

    package init(armedAt: TimeInterval? = nil) {
        self.armedAt = armedAt
    }

    package mutating func receive(prefersConfirmation: Bool, now: TimeInterval) -> Bool {
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
