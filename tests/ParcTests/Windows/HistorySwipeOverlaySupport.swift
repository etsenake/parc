import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

enum HistorySwipeOverlaySupport {
    static func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }
    static func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-6) -> Bool { abs(a - b) <= tolerance }
    static func close(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 1e-6) -> Bool {
        close(a.minX, b.minX, tolerance) && close(a.minY, b.minY, tolerance)
            && close(a.width, b.width, tolerance) && close(a.height, b.height, tolerance)
    }

    typealias Metrics = HistorySwipeOverlayMetrics
    typealias Timing = HistorySwipeOverlayTiming
    typealias Geometry = HistorySwipeOverlayGeometry
    typealias Haptic = HistorySwipeOverlayModel.Haptic

    static let pane = CGSize(width: 832, height: 664)

    static func band(_ progress: Double, _ resistance: Double = 0.15) -> Double {
        let resisted = (progress - 1) * resistance
        return 1 + resisted / (resisted + 1)
    }

    struct Driver {
        var model = HistorySwipeOverlayModel()
        var time = 10.0
        var haptics: [Haptic] = []
        var size = HistorySwipeOverlaySupport.pane

        init(back: Int = 3, forward: Int = 2, reduced: Bool = false) {
            model.backRows = back
            model.forwardRows = forward
            model.prefersReducedMotion = reduced
        }

        mutating func send(_ output: HistorySwipeOutput, after delay: Double = 0) {
            time += delay
            if let haptic = model.receive(output, at: time) { haptics.append(haptic) }
        }

        mutating func progress(_ value: Double, after delay: Double = 0) {
            send(.progress(HistorySwipeProgress(fraction: min(max(value, 0), 1), stretch: value)), after: delay)
        }

        mutating func advance(_ delay: Double) {
            time += delay
            model.advance(to: time)
        }

        mutating func settle() {
            advance(1.5)
        }

        var frame: HistorySwipeOverlayFrame? { model.frame(in: size) }

        static func armed(_ direction: HistorySwipeDirection = .back, back: Int = 3, forward: Int = 2,
                          reduced: Bool = false, stretch: Double = 1) -> Driver {
            var driver = Driver(back: back, forward: forward, reduced: reduced)
            driver.send(.begin(direction))
            driver.progress(stretch)
            driver.send(.armed(true))
            driver.settle()
            return driver
        }

        static func holding(_ direction: HistorySwipeDirection = .back, back: Int = 3, forward: Int = 2,
                            reduced: Bool = false) -> Driver {
            var driver = armed(direction, back: back, forward: forward, reduced: reduced)
            driver.send(.hold)
            driver.send(.selection(0))
            driver.settle()
            return driver
        }
    }

    struct Environment: HistorySwipeEnvironment {
        var back = 3
        var forward = 0
        var swipesBetweenPages = true
        var allowsHistorySwipe = true
        func historyEntries(toward direction: HistorySwipeDirection) -> Int { direction == .back ? back : forward }
    }

    struct Fingers {
        var recognizer = HistorySwipeRecognizer()
        var overlay = Driver()
        var environment = Environment()
        var time = 10.0
        var x = 0.30
        var y = 0.5
        var lastStep = HistorySwipeStep()
        var outputs: [HistorySwipeOutput] = []

        init(back: Int, reduced: Bool = false) {
            environment.back = back
            overlay = Driver(back: back, forward: 0, reduced: reduced)
        }

        mutating func feed(_ input: HistorySwipeInput) {
            lastStep = recognizer.receive(input, in: environment)
            outputs += lastStep.outputs
            for output in lastStep.outputs { overlay.time = max(overlay.time, time); overlay.send(output) }
        }

        var commits: [HistorySwipeCommit] {
            outputs.compactMap { if case let .commit(commit) = $0 { commit } else { nil } }
        }

        var points: [HistorySwipePoint] { [HistorySwipePoint(x: x - 0.06, y: y), HistorySwipePoint(x: x + 0.06, y: y)] }

        mutating func touch(_ phase: HistorySwipeTouchPhase, _ x: Double, _ y: Double? = nil) {
            time += 0.008
            self.x = x
            if let y { self.y = y }
            feed(.touches(phase, points, time: time))
        }

        mutating func scroll(_ phase: HistorySwipeEventPhase, dx: Double) {
            feed(.scroll(HistorySwipeScroll(phase: phase, deltaX: dx, directionInverted: true)))
        }

        mutating func open() {
            touch(.began, 0.30)
            scroll(.mayBegin, dx: 0)
            touch(.moved, 0.302)
            scroll(.began, dx: 2)
            feed(.pageScroll(.began(synthetic: false, momentum: false)))
            feed(.overscroll(propagatesX: true))
            feed(.pageScroll(.updated(consumed: false)))
            touch(.moved, 0.305)
            scroll(.changed, dx: 3)
        }

        mutating func scrollToHistoryEdge() {
            for _ in 0..<environment.back {
                guard lastStep.clockDeadline != nil else { break }
                clock()
            }
        }

        mutating func clock() {
            guard let deadline = lastStep.clockDeadline else { return }
            time = deadline
            feed(.clock(deadline))
        }
    }
}
