import AppKit
import ParcCore

protocol HistorySwipeTarget: AnyObject {
    var swipesBetweenPages: Bool { get }
    var allowsHistorySwipe: Bool { get }
    func historyEntries(toward direction: HistorySwipeDirection) -> Int
    func dismisses(toward direction: HistorySwipeDirection) -> Bool
    func beginSwipe(_ direction: HistorySwipeDirection) -> Bool
    func beginDismissal() -> Bool
    func navigate(_ commit: HistorySwipeCommit) -> Bool
    func endSwipe()
    func preloadBack()
}

protocol HistorySwipePresenter: AnyObject {
    func present(_ output: HistorySwipeOutput)
}

protocol HistorySwipeClock: AnyObject {
    var now: TimeInterval { get }
    func schedule(at deadline: TimeInterval, _ tick: @escaping () -> Void)
}

final class HistorySwipeDriver: HistorySwipeShell {
    private struct Environment: HistorySwipeEnvironment {
        let target: any HistorySwipeTarget
        var swipesBetweenPages: Bool { target.swipesBetweenPages }
        var allowsHistorySwipe: Bool { target.allowsHistorySwipe }
        func historyEntries(toward direction: HistorySwipeDirection) -> Int {
            target.historyEntries(toward: direction)
        }
        func dismisses(toward direction: HistorySwipeDirection) -> Bool {
            target.dismisses(toward: direction)
        }
    }

    private weak var target: (any HistorySwipeTarget)?
    private weak var presenter: (any HistorySwipePresenter)?
    private let clock: any HistorySwipeClock
    private lazy var controller = HistorySwipeController(shell: self)
    private(set) var isActive = false
    private var refused = false
    private var deadline: TimeInterval?
    private var tick = 0

    init(target: any HistorySwipeTarget, presenter: any HistorySwipePresenter, clock: any HistorySwipeClock) {
        self.target = target
        self.presenter = presenter
        self.clock = clock
    }

    @discardableResult
    func receive(_ input: HistorySwipeInput) -> HistorySwipeStep {
        guard let target else { return HistorySwipeStep(stopsTracking: true) }
        let environment = Environment(target: target)
        refused = false
        var step = controller.receive(input, in: environment)
        if refused {
            refused = false
            let cancel = controller.receive(.cancel, in: environment)
            step.startsTracking = nil
            step.stopsTracking = true
            step.preloadsBack = false
            step.clockDeadline = cancel.clockDeadline
        }
        if step.preloadsBack { target.preloadBack() }
        schedule(step.clockDeadline)
        return step
    }

    func tracked(_ update: HistorySwipeTrackedUpdate) -> Bool {
        !receive(.trackedSwipe(update)).stopsTracking
    }

    func cancel() {
        guard isActive else { return }
        receive(.cancel)
        guard isActive else { return }
        finish(.cancel)
    }

    func historySwipe(_ output: HistorySwipeOutput) {
        switch output {
        case let .begin(direction):
            guard target?.beginSwipe(direction) == true else {
                refused = true
                return
            }
            isActive = true
            presenter?.present(output)
        case .beginDismissal:
            guard target?.beginDismissal() == true else {
                refused = true
                return
            }
            isActive = true
            presenter?.present(output)
        case let .commit(commit):
            guard isActive else { return }
            isActive = false
            let landed = target?.navigate(commit) == true
            finish(landed ? output : .cancel)
        case .cancel:
            guard isActive else { return }
            finish(output)
        default:
            if isActive { presenter?.present(output) }
        }
    }

    private func finish(_ output: HistorySwipeOutput) {
        isActive = false
        target?.endSwipe()
        presenter?.present(output)
    }

    private func schedule(_ next: TimeInterval?) {
        guard next != deadline else { return }
        deadline = next
        tick += 1
        guard let next else { return }
        let token = tick
        clock.schedule(at: next) { [weak self] in
            guard let self, self.tick == token, let due = self.deadline else { return }
            self.deadline = nil
            self.receive(.clock(max(self.clock.now, due)))
        }
    }
}

enum HistorySwipeEvents {
    static func phase(_ phase: NSEvent.Phase) -> HistorySwipeEventPhase {
        switch phase {
        case .mayBegin: .mayBegin
        case .began: .began
        case .stationary: .stationary
        case .changed: .changed
        case .ended: .ended
        case .cancelled: .cancelled
        default: .none
        }
    }

    static func scroll(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, deltaX: Double, deltaY: Double,
                       directionInverted: Bool) -> HistorySwipeInput {
        .scroll(HistorySwipeScroll(phase: self.phase(phase), momentumPhase: self.phase(momentumPhase),
                                   deltaX: deltaX, deltaY: deltaY, directionInverted: directionInverted))
    }

    static func points(_ positions: [CGPoint]) -> [HistorySwipePoint] {
        positions.map { HistorySwipePoint(x: Double($0.x), y: Double($0.y)) }
    }
}

struct HistorySwipeRows<Row> {
    var current: Row?
    var back: [Row]
    var forward: [Row]

    init(entries: [Row], currentIndex: Int) {
        guard entries.indices.contains(currentIndex) else {
            self.init(current: nil, back: [], forward: [])
            return
        }
        self.init(current: entries[currentIndex], back: Array(entries[..<currentIndex].reversed()),
                  forward: Array(entries[(currentIndex + 1)...]))
    }

    init(current: Row?, back: [Row], forward: [Row]) {
        self.current = current
        self.back = back
        self.forward = forward
    }
}
