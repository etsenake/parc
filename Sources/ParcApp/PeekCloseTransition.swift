import Foundation

struct PeekCloseTransition: Equatable {
    enum Phase: Equatable {
        case resting, dragging, exiting, closing, finished
    }

    enum Exit: Equatable {
        case slide, fade
    }

    enum Effect: Equatable {
        case follow(Double)
        case haptic
        case springBack(velocity: Double)
        case exit(Exit, from: Double, velocity: Double, generation: Int)
        case requestClose
        case vanish
        case reappear
        case settle
    }

    private(set) var phase = Phase.resting
    private(set) var fraction = 0.0
    private(set) var cardHidden = false
    private(set) var generation = 0
    private var velocity = 0.0

    mutating func beginDrag() -> Bool {
        guard phase == .resting, !cardHidden else { return false }
        phase = .dragging
        fraction = 0
        velocity = 0
        return true
    }

    mutating func drag(_ output: HistorySwipeOutput) -> [Effect] {
        guard phase == .dragging else { return [] }
        switch output {
        case let .progress(progress):
            fraction = min(max(progress.fraction, 0), 1)
            return [.follow(fraction)]
        case .armed(true):
            return [.haptic]
        case let .release(speed):
            velocity = speed
            return []
        case .cancel:
            return springBack()
        default:
            return []
        }
    }

    mutating func springBack() -> [Effect] {
        guard phase == .dragging else { return [] }
        let speed = velocity
        phase = .resting
        fraction = 0
        velocity = 0
        return [.springBack(velocity: speed)]
    }

    mutating func close(visible: Bool, exit: Exit) -> [Effect] {
        guard phase == .resting || phase == .dragging, !cardHidden else { return [] }
        let dragged = phase == .dragging
        let from = dragged ? fraction : 0, speed = dragged ? velocity : 0
        fraction = 0
        velocity = 0
        guard visible else {
            phase = .closing
            return dragged ? [.settle, .requestClose] : [.requestClose]
        }
        generation += 1
        phase = .exiting
        return [.exit(dragged ? .slide : exit, from: from, velocity: speed, generation: generation)]
    }

    mutating func exitFinished(_ generation: Int) -> [Effect] {
        guard phase == .exiting, generation == self.generation else { return [] }
        phase = .closing
        cardHidden = true
        return [.requestClose]
    }

    mutating func hide() -> [Effect] {
        switch phase {
        case .dragging:
            phase = .resting
            fraction = 0
            velocity = 0
            return [.settle]
        case .exiting:
            phase = .closing
            cardHidden = true
            return [.vanish, .requestClose]
        case .resting, .closing, .finished:
            return []
        }
    }

    mutating func sheetBegan(visible: Bool) -> [Effect] {
        guard phase == .closing, cardHidden, visible else { return [] }
        cardHidden = false
        return [.reappear]
    }

    mutating func refused(visible: Bool) -> [Effect] {
        guard phase == .closing else { return [] }
        phase = .resting
        guard cardHidden else { return [] }
        cardHidden = false
        return [visible ? .reappear : .settle]
    }

    mutating func finish() -> [Effect] {
        guard phase != .finished else { return [] }
        let moved = phase != .resting || cardHidden
        phase = .finished
        fraction = 0
        velocity = 0
        return moved ? [.vanish] : []
    }
}
