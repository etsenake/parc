import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

enum StartPageMarkGestureTestsSupport {
    struct Pointer {
        var recognizer = StartPageMarkGestureRecognizer(clickInterval: 0.5)
        var session = StartPageMarkSession()
        var canAnimate = true
        var reduceMotion = false

        mutating func send(_ cues: [StartPageMarkCue]) -> [StartPageMarkSession.Effect] {
            var effects: [StartPageMarkSession.Effect] = []
            for cue in cues {
                let produced = session.handle(cue, canAnimate: canAnimate, reduceMotion: reduceMotion)
                if produced.contains(.reset) { recognizer.reset() }
                effects += produced
            }
            return effects
        }
        mutating func down(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            send(recognizer.pointerDown(at: point, time: time, idle: session.isIdle))
        }
        mutating func drag(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            send(recognizer.pointerDragged(to: point, time: time))
        }
        mutating func up(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            send(recognizer.pointerUp(at: point, time: time))
        }
        mutating func hold(_ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            send(recognizer.holdElapsed(at: time))
        }
        mutating func click(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            down(point, time) + up(point, time + 0.08)
        }
    }

    static func isCancel(_ cue: StartPageMarkCue) -> Bool {
        if case .cancel = cue { return true }
        return false
    }

    static func isTrack(_ cue: StartPageMarkCue) -> Bool {
        if case .track = cue { return true }
        return false
    }

    static func isRelax(_ effect: StartPageMarkSession.Effect) -> Bool {
        if case .play(.relax) = effect { return true }
        return false
    }
}
