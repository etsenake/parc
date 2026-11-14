import Foundation

enum HistorySwipeDirection: Equatable {
    case back
    case forward
}

struct HistorySwipePoint: Equatable {
    var x: Double
    var y: Double
}

enum HistorySwipeEventPhase: Equatable {
    case none
    case mayBegin
    case began
    case stationary
    case changed
    case ended
    case cancelled
}

enum HistorySwipeTouchPhase: Equatable {
    case began
    case moved
    case ended
    case cancelled
}

struct HistorySwipeScroll: Equatable {
    var phase: HistorySwipeEventPhase
    var momentumPhase: HistorySwipeEventPhase = .none
    var deltaX = 0.0
    var deltaY = 0.0
    var directionInverted: Bool
}

enum HistorySwipePageScroll: Equatable {
    case began(synthetic: Bool, momentum: Bool)
    case updated(consumed: Bool)
}

struct HistorySwipeTrackedUpdate: Equatable {
    var generation: Int
    var amount: Double
    var phase: HistorySwipeEventPhase
    var isComplete = false
}

enum HistorySwipeInput: Equatable {
    case touches(HistorySwipeTouchPhase, [HistorySwipePoint], time: TimeInterval)
    case scroll(HistorySwipeScroll)
    case pageScroll(HistorySwipePageScroll)
    case overscroll(propagatesX: Bool)
    case trackedSwipe(HistorySwipeTrackedUpdate)
    case clock(TimeInterval)
    case cancel
}

struct HistorySwipeProgress: Equatable {
    var fraction: Double
    var stretch: Double
}

enum HistorySwipeCommit: Equatable {
    case adjacent(HistorySwipeDirection)
    case entry(HistorySwipeDirection, distance: Int)
}

enum HistorySwipeOutput: Equatable {
    case begin(HistorySwipeDirection)
    case progress(HistorySwipeProgress)
    case armed(Bool)
    case hold
    case selection(Int)
    case detent
    case commit(HistorySwipeCommit)
    case cancel
}

struct HistorySwipeTrackingRequest: Equatable {
    var direction: HistorySwipeDirection
    var generation: Int
}

struct HistorySwipeStep: Equatable {
    var consumesEvent = false
    var outputs: [HistorySwipeOutput] = []
    var startsTracking: HistorySwipeTrackingRequest?
    var stopsTracking = false
    var preloadsBack = false
    var clockDeadline: TimeInterval?
}

protocol HistorySwipeEnvironment {
    var swipesBetweenPages: Bool { get }
    var allowsHistorySwipe: Bool { get }
    func historyEntries(toward direction: HistorySwipeDirection) -> Int
}

protocol HistorySwipeShell: AnyObject {
    func historySwipe(_ output: HistorySwipeOutput)
}

final class HistorySwipeController {
    private(set) var recognizer: HistorySwipeRecognizer
    private weak var shell: (any HistorySwipeShell)?

    init(shell: any HistorySwipeShell, parameters: HistorySwipeParameters = .chromium) {
        recognizer = HistorySwipeRecognizer(parameters: parameters)
        self.shell = shell
    }

    func receive(_ input: HistorySwipeInput, in environment: any HistorySwipeEnvironment) -> HistorySwipeStep {
        let step = recognizer.receive(input, in: environment)
        for output in step.outputs { shell?.historySwipe(output) }
        return step
    }
}
