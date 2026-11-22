import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerControllerTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace

    private final class Shell: HistorySwipeShell {
        var outputs: [HistorySwipeOutput] = []
        func historySwipe(_ output: HistorySwipeOutput) { outputs.append(output) }
    }

    @Test func theControllerReturnsTheSameStepsAsTheRecognizer() {
        let page = Page()
        let shell = Shell()
        let controller = HistorySwipeController(shell: shell)
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.lift()
        var direct = HistorySwipeRecognizer()
        for input in trace.inputs {
            let step = controller.receive(input, in: page)
            #expect(step == direct.receive(input, in: page), "the controller returns the recognizer's step")
        }
    }

    @Test func theControllerDeliversShellOutputsInOrder() {
        let page = Page()
        let shell = Shell()
        let controller = HistorySwipeController(shell: shell)
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.lift()
        for input in trace.inputs { _ = controller.receive(input, in: page) }
        #expect(shell.outputs.filter { if case .progress = $0 { false } else { true } }
              == [.begin(.back), .armed(true), .commit(.adjacent(.back))], "the shell receives every output in order")
    }

    @Test func theControllerPassesOnConsumeAnswers() {
        let page = Page()
        let shell = Shell()
        let controller = HistorySwipeController(shell: shell)
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.lift()
        let consumed = trace.inputs.map { controller.receive($0, in: page).consumesEvent }
        #expect(consumed.contains(true) && controller.recognizer.state == .completed, "the forwarder gets consume answers")
    }

    @Test func theControllerDoesNotRetainTheShell() {
        weak var released: Shell?
        let controller: HistorySwipeController
        do {
            let gone = Shell()
            released = gone
            controller = HistorySwipeController(shell: gone)
        }
        withExtendedLifetime(controller) {
            #expect(released == nil, "the controller does not keep its shell alive")
        }
    }

    @Test func theControllerStillRecognizesAfterTheShellGoesAway() {
        let page = Page()
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.lift()
        var orphan: HistorySwipeController?
        do {
            let gone = Shell()
            orphan = HistorySwipeController(shell: gone)
        }
        var later: [HistorySwipeStep] = []
        for input in trace.inputs { later.append(orphan!.receive(input, in: page)) }
        #expect(later.flatMap(\.outputs).contains(.commit(.adjacent(.back))), "a controller without a shell still recognizes")
    }
}
