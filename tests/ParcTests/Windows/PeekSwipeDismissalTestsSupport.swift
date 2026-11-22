import Foundation
import Testing
@testable import Parc
@testable import ParcCore

enum PeekSwipeDismissalTestsSupport {
    typealias Effect = PeekCloseTransition.Effect

    struct Pad: HistorySwipeEnvironment {
        var swipesBetweenPages = true
        var allowsHistorySwipe = true
        var back = 0
        func historyEntries(toward direction: HistorySwipeDirection) -> Int { direction == .back ? back : 0 }
        func dismisses(toward direction: HistorySwipeDirection) -> Bool { back == 0 && direction == .back }
    }

    @MainActor final class Peek {
        var transition = PeekCloseTransition()
        let confirmation = PeekDismissalConfirmation()
        var recognizer = HistorySwipeRecognizer()
        var pad = Pad()
        var visible = true
        var call = false
        var effects: [Effect] = []
        var closeRequests = 0
        var hangUp = false
        var time = 100.0
        var x = 0.3
        var y = 0.5

        func apply(_ list: [Effect]) {
            effects += list
            for effect in list where effect == .requestClose && !transition.holdForParent(visible: visible) { closeRequests += 1 }
        }

        func cancelled() {
            if !transition.holdForParent(visible: visible) { apply(transition.refused(visible: visible)) }
        }

        var reappeared: Bool { effects.contains(.reappear) }

        func requestDismiss(_ mechanism: PeekDismissalConfirmation.Dismissal) {
            guard transition.phase == .resting || transition.phase == .dragging else { return }
            if let reason = confirmation.request(mechanism, mediaInput: call, onExpiry: {}) {
                hangUp = reason == .mediaInput
                return
            }
            apply(transition.close(visible: visible, exit: mechanism == .swipe ? .slide : .fade))
        }

        func commit() {
            guard transition.phase == .dragging else { return }
            requestDismiss(.swipe)
            if transition.phase == .dragging { apply(transition.springBack()) }
        }

        func feed(_ input: HistorySwipeInput) {
            let step = recognizer.receive(input, in: pad)
            for output in step.outputs {
                switch output {
                case .beginDismissal:
                    let began = transition.beginDrag()
                    #expect(began)
                case .commit(.dismiss):
                    commit()
                default:
                    apply(transition.drag(output))
                }
            }
        }

        var fingers: [HistorySwipePoint] { [HistorySwipePoint(x: x - 0.06, y: y), HistorySwipePoint(x: x + 0.06, y: y)] }

        func open() {
            feed(.touches(.began, fingers, time: time))
            feed(.scroll(HistorySwipeScroll(phase: .began, deltaX: 2, directionInverted: true)))
            feed(.pageScroll(.began(synthetic: false, momentum: false)))
            feed(.overscroll(propagatesX: true))
            feed(.pageScroll(.updated(consumed: false)))
            move(0.305)
            feed(.scroll(HistorySwipeScroll(phase: .changed, deltaX: 3, directionInverted: true)))
        }

        func move(_ to: Double, _ toY: Double? = nil, after delay: Double = 0.008) {
            time += delay
            x = to
            if let toY { y = toY }
            feed(.touches(.moved, fingers, time: time))
        }

        func lift(rested: Bool = true) {
            if rested { move(x + 0.0005, after: 0.2) }
            time += 0.008
            feed(.touches(.ended, fingers, time: time))
        }

        var haptics: Int { effects.filter { $0 == .haptic }.count }
        var follows: [Double] { effects.compactMap { if case let .follow(value) = $0 { value } else { nil } } }
        var lastExit: (PeekCloseTransition.Exit, Double, Double, Int)? {
            for effect in effects.reversed() {
                if case let .exit(kind, from, velocity, generation) = effect { return (kind, from, velocity, generation) }
            }
            return nil
        }
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func isSpringBack(_ effect: Effect?) -> Bool {
        if case .springBack? = effect { return true }
        return false
    }

    @MainActor static func swiped() -> Peek {
        let peek = Peek()
        peek.open()
        for x in [0.36, 0.42, 0.47, 0.5] { peek.move(x) }
        peek.lift()
        return peek
    }

    @MainActor static func exitedAndHandedOver() -> Peek {
        let peek = Peek()
        peek.open()
        for x in [0.42, 0.5] { peek.move(x) }
        peek.lift()
        peek.apply(peek.transition.exitFinished(peek.lastExit?.3 ?? 0))
        return peek
    }

    @MainActor static func closingParent(_ mechanism: PeekDismissalConfirmation.Dismissal = .closeButton) -> Peek {
        let peek = Peek()
        peek.requestDismiss(mechanism)
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        return peek
    }

    @MainActor static func takenOver() -> Peek {
        let peek = Peek()
        peek.requestDismiss(.escape(prefersConfirmation: false))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.cancelled()
        return peek
    }

    static let geometry = PeekDismissalMotion.Geometry(paneWidth: 508, cardMinX: 53)

    static func dragging() -> PeekDismissalMotion {
        var m = PeekDismissalMotion(geometry: geometry)
        m.begin(reducesMotion: false)
        return m
    }

    static func midExit() -> PeekCloseTransition {
        var transition = PeekCloseTransition()
        _ = transition.beginDrag()
        _ = transition.drag(.progress(HistorySwipeProgress(fraction: 0.6, stretch: 0.6)))
        _ = transition.close(visible: true, exit: .slide)
        return transition
    }
}
