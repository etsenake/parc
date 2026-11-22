import Foundation

package enum HistorySwipeDirection: Equatable {
    case back
    case forward
}

package struct HistorySwipePoint: Equatable {
    package var x: Double
    package var y: Double

    package init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

package enum HistorySwipeEventPhase: Equatable {
    case none
    case mayBegin
    case began
    case stationary
    case changed
    case ended
    case cancelled
}

package enum HistorySwipeTouchPhase: Equatable {
    case began
    case moved
    case ended
    case cancelled
}

package struct HistorySwipeScroll: Equatable {
    package var phase: HistorySwipeEventPhase
    package var momentumPhase: HistorySwipeEventPhase = .none
    package var deltaX = 0.0
    package var deltaY = 0.0
    package var directionInverted: Bool

    package init(phase: HistorySwipeEventPhase, momentumPhase: HistorySwipeEventPhase = .none, deltaX: Double = 0.0, deltaY: Double = 0.0, directionInverted: Bool) {
        self.phase = phase
        self.momentumPhase = momentumPhase
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.directionInverted = directionInverted
    }
}

package enum HistorySwipePageScroll: Equatable {
    case began(synthetic: Bool, momentum: Bool)
    case updated(consumed: Bool)
}

package struct HistorySwipeTrackedUpdate: Equatable {
    package var generation: Int
    package var amount: Double
    package var phase: HistorySwipeEventPhase
    package var isComplete = false

    package init(generation: Int, amount: Double, phase: HistorySwipeEventPhase, isComplete: Bool = false) {
        self.generation = generation
        self.amount = amount
        self.phase = phase
        self.isComplete = isComplete
    }
}

package enum HistorySwipeInput: Equatable {
    case touches(HistorySwipeTouchPhase, [HistorySwipePoint], time: TimeInterval)
    case scroll(HistorySwipeScroll)
    case pageScroll(HistorySwipePageScroll)
    case overscroll(propagatesX: Bool)
    case trackedSwipe(HistorySwipeTrackedUpdate)
    case clock(TimeInterval)
    case cancel
}

package struct HistorySwipeProgress: Equatable {
    package var fraction: Double
    package var stretch: Double
}

package enum HistorySwipeCommit: Equatable {
    case adjacent(HistorySwipeDirection)
    case entry(HistorySwipeDirection, distance: Int)
    case dismiss
}

package enum HistorySwipeOutput: Equatable {
    case begin(HistorySwipeDirection)
    case beginDismissal
    case progress(HistorySwipeProgress)
    case armed(Bool)
    case hold
    case selection(Int)
    case rowRemainder(Double)
    case detent
    case release(velocity: Double)
    case commit(HistorySwipeCommit)
    case cancel
}

package struct HistorySwipeTrackingRequest: Equatable {
    package var direction: HistorySwipeDirection
    package var generation: Int

    package init(direction: HistorySwipeDirection, generation: Int) {
        self.direction = direction
        self.generation = generation
    }
}

package struct HistorySwipeStep: Equatable {
    package var consumesEvent = false
    var outputs: [HistorySwipeOutput] = []
    package var startsTracking: HistorySwipeTrackingRequest?
    package var stopsTracking = false
    package var preloadsBack = false
    package var clockDeadline: TimeInterval?

    package init(consumesEvent: Bool = false, outputs: [HistorySwipeOutput] = [], startsTracking: HistorySwipeTrackingRequest? = nil, stopsTracking: Bool = false, preloadsBack: Bool = false, clockDeadline: TimeInterval? = nil) {
        self.consumesEvent = consumesEvent
        self.outputs = outputs
        self.startsTracking = startsTracking
        self.stopsTracking = stopsTracking
        self.preloadsBack = preloadsBack
        self.clockDeadline = clockDeadline
    }
}

package protocol HistorySwipeEnvironment {
    var swipesBetweenPages: Bool { get }
    var allowsHistorySwipe: Bool { get }
    func historyEntries(toward direction: HistorySwipeDirection) -> Int
    func dismisses(toward direction: HistorySwipeDirection) -> Bool
}

extension HistorySwipeEnvironment {
    package func dismisses(toward direction: HistorySwipeDirection) -> Bool { false }
}

package protocol HistorySwipeShell: AnyObject {
    func historySwipe(_ output: HistorySwipeOutput)
}

package final class HistorySwipeController {
    package private(set) var recognizer: HistorySwipeRecognizer
    private weak var shell: (any HistorySwipeShell)?

    package init(shell: any HistorySwipeShell, parameters: HistorySwipeParameters = .dia) {
        recognizer = HistorySwipeRecognizer(parameters: parameters)
        self.shell = shell
    }

    package func receive(_ input: HistorySwipeInput, in environment: any HistorySwipeEnvironment) -> HistorySwipeStep {
        let step = recognizer.receive(input, in: environment)
        for output in step.outputs { shell?.historySwipe(output) }
        return step
    }
}
