import Foundation
import Testing
@testable import ParcCore

enum HistorySwipeRecognizerTestsSupport {
    final class Page: HistorySwipeEnvironment {
        var swipesBetweenPages = true
        var allowsHistorySwipe = true
        var back: Int
        var forward: Int
        var peekFirstPage = false

        init(back: Int = 3, forward: Int = 2, peekFirstPage: Bool = false) {
            self.back = back
            self.forward = forward
            self.peekFirstPage = peekFirstPage
        }

        func historyEntries(toward direction: HistorySwipeDirection) -> Int {
            direction == .back ? back : forward
        }

        func dismisses(toward direction: HistorySwipeDirection) -> Bool {
            peekFirstPage && direction == .back
        }

        static var peek: Page { Page(back: 0, forward: 0, peekFirstPage: true) }
    }

    struct Trace {
        var inputs: [HistorySwipeInput] = []
        var time = 100.0
        var natural = true
        var x = 0.5
        var y = 0.5

        var fingers: [HistorySwipePoint] {
            [HistorySwipePoint(x: x - 0.06, y: y), HistorySwipePoint(x: x + 0.06, y: y)]
        }

        mutating func land(_ x: Double, _ y: Double = 0.5) {
            self.x = x
            self.y = y
            inputs.append(.touches(.began, fingers, time: time))
        }

        mutating func rest(_ duration: Double = 0.2) {
            move(x + 0.0005, after: duration)
        }

        mutating func move(_ x: Double, _ y: Double? = nil, after delay: Double = 0.008) {
            time += delay
            self.x = x
            if let y { self.y = y }
            inputs.append(.touches(.moved, fingers, time: time))
        }

        mutating func lift() {
            time += 0.008
            inputs.append(.touches(.ended, fingers, time: time))
        }

        mutating func scroll(_ phase: HistorySwipeEventPhase, dx: Double = 0, dy: Double = 0,
                             momentum: HistorySwipeEventPhase = .none) {
            inputs.append(.scroll(HistorySwipeScroll(phase: phase, momentumPhase: momentum, deltaX: dx, deltaY: dy,
                                                     directionInverted: natural)))
        }

        mutating func pageAnswers(consumed: Bool = false, propagatesX: Bool? = true) {
            inputs.append(.pageScroll(.began(synthetic: false, momentum: false)))
            if let propagatesX { inputs.append(.overscroll(propagatesX: propagatesX)) }
            inputs.append(.pageScroll(.updated(consumed: consumed)))
        }

        mutating func tracked(_ amount: Double, _ phase: HistorySwipeEventPhase, generation: Int = 1,
                              complete: Bool = false) {
            inputs.append(.trackedSwipe(HistorySwipeTrackedUpdate(generation: generation, amount: amount, phase: phase,
                                                                  isComplete: complete)))
        }

        mutating func clock(_ time: Double) {
            inputs.append(.clock(time))
        }

        static func opening(from x: Double, toward sign: Double, natural: Bool = true, consumed: Bool = false,
                            propagatesX: Bool? = true, y: Double = 0.5) -> Trace {
            var trace = Trace(natural: natural)
            let content = natural ? sign : -sign
            trace.land(x, y)
            trace.scroll(.mayBegin)
            trace.move(x + sign * 0.002)
            trace.scroll(.began, dx: content * 2)
            trace.pageAnswers(consumed: consumed, propagatesX: propagatesX)
            trace.move(x + sign * 0.005)
            trace.scroll(.changed, dx: content * 3)
            return trace
        }

        static func wheel(natural: Bool = true, dx: Double, dy: Double = 0, consumed: Bool = false) -> Trace {
            var trace = Trace(natural: natural)
            trace.scroll(.mayBegin)
            trace.scroll(.began, dx: dx / 2, dy: dy / 2)
            trace.pageAnswers(consumed: consumed)
            trace.scroll(.changed, dx: dx, dy: dy)
            return trace
        }
    }

    struct Run {
        static func gestures(in step: HistorySwipeStep) -> [HistorySwipeOutput] {
            step.outputs.filter {
                switch $0 {
                case .progress, .rowRemainder: false
                default: true
                }
            }
        }

        var recognizer: HistorySwipeRecognizer
        var steps: [HistorySwipeStep] = []
        var inputs: [HistorySwipeInput] = []

        init(_ trace: Trace, _ page: Page = Page(), parameters: HistorySwipeParameters = .dia) {
            recognizer = HistorySwipeRecognizer(parameters: parameters)
            play(trace.inputs, page)
        }

        mutating func play(_ more: [HistorySwipeInput], _ page: Page) {
            for input in more {
                steps.append(recognizer.receive(input, in: page))
                inputs.append(input)
            }
        }

        var outputs: [HistorySwipeOutput] { steps.flatMap(\.outputs) }

        var gestures: [HistorySwipeOutput] { steps.flatMap(Self.gestures(in:)) }

        var shape: [HistorySwipeOutput] {
            gestures.map { if case .release = $0 { .release(velocity: 0) } else { $0 } }
        }

        var releases: [Double] {
            outputs.compactMap { if case let .release(velocity) = $0 { velocity } else { nil } }
        }

        var remainders: [Double] {
            outputs.compactMap { if case let .rowRemainder(value) = $0 { value } else { nil } }
        }

        var fractions: [Double] {
            outputs.compactMap { if case let .progress(value) = $0 { value.fraction } else { nil } }
        }

        var stretches: [Double] {
            outputs.compactMap { if case let .progress(value) = $0 { value.stretch } else { nil } }
        }

        var scrollConsumes: [Bool] {
            zip(inputs, steps).compactMap { input, step in
                if case .scroll = input { step.consumesEvent } else { nil }
            }
        }

        func steps(after count: Int) -> [HistorySwipeStep] { Array(steps.dropFirst(count)) }

        var selections: [Int] {
            outputs.compactMap { if case let .selection(row) = $0 { row } else { nil } }
        }

        var detents: Int { outputs.filter { $0 == .detent }.count }

        mutating func tickUntilQuiet(_ page: Page, limit: Int = 200) -> [TimeInterval] {
            var deadlines: [TimeInterval] = []
            while deadlines.count < limit, let deadline = steps.last?.clockDeadline {
                deadlines.append(deadline)
                play([.clock(deadline)], page)
            }
            return deadlines
        }
    }

    static func near(_ values: [Double], _ expected: [Double]) -> Bool {
        values.count == expected.count && zip(values, expected).allSatisfy { abs($0 - $1) < 1e-9 }
    }
}
