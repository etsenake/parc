import Foundation

struct HistorySwipeParameters: Equatable {
    var commitDistance = 0.08
    var consumeDistance = 0.01
    var directionDistance = 0.001
    var verticalCancelDistance = 0.24
    var verticalDriftDistance = 0.01
    var verticalDominance = 2.0
    var verticalExcess = 1.3
    var trackedArmAmount = 0.3
    var rubberBand = 0.15
    var holdDelay: TimeInterval = 0.3
    var rowStep = 0.08
    var edgeZone = 0.15
    var edgeStepInterval: TimeInterval = 0.1

    static let dia = HistorySwipeParameters()
}

struct HistorySwipeRecognizer {
    enum State: Equatable {
        case waitingForPage
        case possible
        case tracking
        case armed
        case holding
        case completed
        case cancelled
    }

    enum Source: Equatable {
        case touches
        case trackedSwipe
    }

    let parameters: HistorySwipeParameters
    private(set) var state = State.waitingForPage
    private(set) var direction: HistorySwipeDirection?
    private(set) var source: Source?
    private(set) var selection: Int?
    private(set) var holdDeadline: TimeInterval?
    private(set) var entries = 0
    private var inverted = false
    private var announced = false
    private var receivingTouches = false
    private var start = HistorySwipePoint(x: 0, y: 0)
    private var current = HistorySwipePoint(x: 0, y: 0)
    private var totalY = 0.0
    private var armedY = 0.0
    private var armedTotalY = 0.0
    private var rowAnchor = 0.0
    private var edgeDeadline: TimeInterval?
    private var edgeBlocked = 0
    private var firstScrollUnconsumed = false
    private var overscrollPropagatesX = false
    private var awaitingFirstScroll = false
    private var mouseScrollX = 0.0
    private var mouseScrollY = 0.0
    private var trackingGeneration = 0
    private var liveTracking: Int?
    private var lastProgress: HistorySwipeProgress?

    init(parameters: HistorySwipeParameters = .dia) {
        self.parameters = parameters
    }

    var isLive: Bool {
        switch state {
        case .possible, .tracking, .armed, .holding: true
        case .waitingForPage, .completed, .cancelled: false
        }
    }

    mutating func receive(_ input: HistorySwipeInput, in environment: any HistorySwipeEnvironment) -> HistorySwipeStep {
        var step = HistorySwipeStep()
        if isLive && !environment.allowsHistorySwipe { cancel(&step) }
        switch input {
        case let .touches(phase, points, time):
            touches(phase, points, time: time, &step)
        case let .scroll(event):
            scroll(event, environment, &step)
        case let .pageScroll(answer):
            switch answer {
            case let .began(synthetic, momentum):
                if !synthetic && !momentum { awaitingFirstScroll = true }
            case let .updated(consumed):
                if awaitingFirstScroll { firstScrollUnconsumed = !consumed }
                awaitingFirstScroll = false
            }
        case let .overscroll(propagatesX):
            overscrollPropagatesX = propagatesX
        case let .trackedSwipe(update):
            tracked(update, &step)
        case let .clock(time):
            holdIfDue(time, &step)
            edgeStepIfDue(time, &step)
        case .cancel:
            cancel(&step)
        }
        step.clockDeadline = holdDeadline ?? edgeDeadline
        return step
    }

    private mutating func touches(_ phase: HistorySwipeTouchPhase, _ points: [HistorySwipePoint],
                                  time: TimeInterval, _ step: inout HistorySwipeStep) {
        switch phase {
        case .began:
            if isLive { cancel(&step) }
            receivingTouches = true
            start = Self.average(points)
            current = start
            totalY = 0
            firstScrollUnconsumed = false
            overscrollPropagatesX = false
            awaitingFirstScroll = false
        case .moved:
            _ = follow(points, time: time, &step)
        case .cancelled:
            receivingTouches = false
            if follow(points, time: time, &step) { cancel(&step) }
        case .ended:
            receivingTouches = false
            if follow(points, time: time, &step) { finish(&step) }
        }
    }

    private mutating func follow(_ points: [HistorySwipePoint], time: TimeInterval,
                                 _ step: inout HistorySwipeStep) -> Bool {
        guard state != .completed, state != .cancelled, source != .trackedSwipe else { return false }
        let point = Self.average(points)
        if state == .armed && holdDeadline != nil {
            totalY = armedTotalY + abs(point.y - armedY)
        } else {
            totalY += abs(point.y - current.y)
        }
        current = point
        if state == .holding {
            guard touchProgress > 0 else {
                cancel(&step)
                return false
            }
            emitProgress(touchProgress, &step)
            stepRows(&step)
            followEdge(time: time, &step)
            return true
        }
        if driftsVertically {
            cancel(&step)
            return false
        }
        guard state != .waitingForPage else { return false }
        if state == .possible && (abs(current.x - start.x) > parameters.consumeDistance || touchProgress >= 1) {
            state = .tracking
            if direction == .back { step.preloadsBack = true }
        }
        advance(touchProgress, time: time, &step)
        return true
    }

    private var driftsVertically: Bool {
        let x = abs(current.x - start.x)
        return totalY > parameters.verticalDominance * x
            || (totalY * parameters.verticalExcess > x && totalY > parameters.verticalDriftDistance)
            || totalY > parameters.verticalCancelDistance
    }

    private var touchProgress: Double {
        var progress = (current.x - start.x) / parameters.commitDistance
        if direction == .back { progress = -progress }
        if inverted { progress = -progress }
        return progress
    }

    private mutating func advance(_ progress: Double, time: TimeInterval?, _ step: inout HistorySwipeStep) {
        emitProgress(progress, &step)
        if progress >= 1 && state == .tracking {
            state = .armed
            step.outputs.append(.armed(true))
            armedY = current.y
            armedTotalY = totalY
            if source == .touches, parameters.holdDelay.isFinite, let time { holdDeadline = time + parameters.holdDelay }
        } else if progress < 1 && state == .armed {
            state = .tracking
            holdDeadline = nil
            step.outputs.append(.armed(false))
        }
        if let time { holdIfDue(time, &step) }
    }

    private mutating func holdIfDue(_ time: TimeInterval, _ step: inout HistorySwipeStep) {
        guard state == .armed, source == .touches, receivingTouches,
              let deadline = holdDeadline, time >= deadline else { return }
        state = .holding
        holdDeadline = nil
        selection = 1
        rowAnchor = current.y
        edgeBlocked = edge
        edgeDeadline = nil
        step.outputs += [.hold, .selection(1)]
    }

    private var rowSign: Double { direction == .forward ? -1 : 1 }

    private var edge: Int {
        guard parameters.edgeZone > 0 else { return 0 }
        let top = current.y >= 1 - parameters.edgeZone, bottom = current.y <= parameters.edgeZone
        guard top != bottom else { return 0 }
        return (top ? 1 : -1) * (direction == .forward ? -1 : 1)
    }

    private func canStep(_ way: Int) -> Bool {
        guard let selection else { return false }
        return way > 0 ? selection < entries : selection > 0
    }

    private mutating func moveRow(_ way: Int, _ step: inout HistorySwipeStep) -> Bool {
        guard canStep(way), let row = selection else { return false }
        selection = row + way
        step.outputs += [.selection(row + way), .detent]
        return true
    }

    private mutating func stepRows(_ step: inout HistorySwipeStep) {
        guard selection != nil, parameters.rowStep > 0 else { return }
        let sign = rowSign
        while (current.y - rowAnchor) * sign >= parameters.rowStep {
            guard moveRow(1, &step) else {
                rowAnchor = current.y
                break
            }
            rowAnchor += parameters.rowStep * sign
        }
        while (rowAnchor - current.y) * sign >= parameters.rowStep {
            guard moveRow(-1, &step) else {
                rowAnchor = current.y
                break
            }
            rowAnchor -= parameters.rowStep * sign
        }
    }

    private mutating func followEdge(time: TimeInterval, _ step: inout HistorySwipeStep) {
        let way = edge
        if way != edgeBlocked { edgeBlocked = 0 }
        guard way != 0, way != edgeBlocked, parameters.edgeStepInterval > 0, canStep(way) else {
            edgeDeadline = nil
            return
        }
        guard edgeDeadline != nil else {
            edgeDeadline = time + parameters.edgeStepInterval
            return
        }
        edgeStepIfDue(time, &step)
    }

    private mutating func edgeStepIfDue(_ time: TimeInterval, _ step: inout HistorySwipeStep) {
        guard state == .holding, receivingTouches, let deadline = edgeDeadline, time >= deadline else { return }
        let way = edge
        guard way != 0, way != edgeBlocked, moveRow(way, &step) else {
            edgeDeadline = nil
            return
        }
        rowAnchor = current.y
        let next = deadline + parameters.edgeStepInterval
        edgeDeadline = canStep(way) ? (next > time ? next : time + parameters.edgeStepInterval) : nil
    }

    private mutating func finish(_ step: inout HistorySwipeStep) {
        guard let direction, isLive else { return }
        switch state {
        case .armed:
            step.outputs.append(.commit(.adjacent(direction)))
        case .holding:
            if let selection, selection > 0 {
                step.outputs.append(.commit(.entry(direction, distance: selection)))
            } else {
                step.outputs.append(.cancel)
            }
        default:
            step.outputs.append(.cancel)
        }
        state = .completed
        holdDeadline = nil
        edgeDeadline = nil
        selection = nil
    }

    private mutating func scroll(_ event: HistorySwipeScroll, _ environment: any HistorySwipeEnvironment,
                                 _ step: inout HistorySwipeStep) {
        if event.phase == .began {
            if isLive { cancel(&step) }
            reset()
        }
        guard event.phase == .changed || event.momentumPhase == .changed else { return }
        guard state == .waitingForPage else {
            step.consumesEvent = consumes(event)
            return
        }
        guard event.momentumPhase == .none, environment.swipesBetweenPages, environment.allowsHistorySwipe,
              firstScrollUnconsumed, overscrollPropagatesX else { return }
        guard receivingTouches else {
            trackSwipe(event, environment, &step)
            return
        }
        let deltaX = current.x - start.x
        guard abs(deltaX) >= parameters.directionDistance else { return }
        let rightward = (deltaX > 0) != event.directionInverted
        let way: HistorySwipeDirection = rightward ? .forward : .back
        let count = environment.historyEntries(toward: way)
        guard count > 0 else { return }
        direction = way
        source = .touches
        entries = count
        inverted = event.directionInverted
        state = .possible
        announced = true
        lastProgress = HistorySwipeProgress(fraction: 0, stretch: 0)
        step.outputs.append(.begin(way))
        step.consumesEvent = consumes(event)
    }

    private mutating func reset() {
        state = .waitingForPage
        direction = nil
        source = nil
        selection = nil
        holdDeadline = nil
        edgeDeadline = nil
        entries = 0
        announced = false
        lastProgress = nil
        mouseScrollX = 0
        mouseScrollY = 0
        firstScrollUnconsumed = false
        overscrollPropagatesX = false
        awaitingFirstScroll = false
        liveTracking = nil
    }

    private func consumes(_ event: HistorySwipeScroll) -> Bool {
        switch state {
        case .waitingForPage, .cancelled: false
        case .tracking, .armed, .holding, .completed: true
        case .possible: event.deltaY == 0
        }
    }

    private mutating func trackSwipe(_ event: HistorySwipeScroll, _ environment: any HistorySwipeEnvironment,
                                     _ step: inout HistorySwipeStep) {
        guard event.phase != .none else { return }
        mouseScrollX += event.deltaX
        mouseScrollY += event.deltaY
        guard abs(mouseScrollX) > abs(mouseScrollY) else { return }
        let way: HistorySwipeDirection = event.deltaX < 0 ? .forward : .back
        let count = environment.historyEntries(toward: way)
        guard count > 0 else { return }
        trackingGeneration += 1
        liveTracking = trackingGeneration
        direction = way
        source = .trackedSwipe
        entries = count
        state = .possible
        step.startsTracking = HistorySwipeTrackingRequest(direction: way, generation: trackingGeneration)
        step.consumesEvent = true
    }

    private mutating func tracked(_ update: HistorySwipeTrackedUpdate, _ step: inout HistorySwipeStep) {
        guard let live = liveTracking, update.generation == live, source == .trackedSwipe,
              let direction else {
            step.stopsTracking = true
            return
        }
        if update.isComplete { liveTracking = nil }
        guard isLive else { return }
        if state == .possible {
            state = .tracking
            announced = true
            lastProgress = HistorySwipeProgress(fraction: 0, stretch: 0)
            step.outputs.append(.begin(direction))
        }
        switch update.phase {
        case .began:
            break
        case .ended:
            step.outputs.append(.commit(.adjacent(direction)))
            state = .completed
        case .cancelled:
            step.outputs.append(.cancel)
            state = .cancelled
        default:
            advance(abs(update.amount) / parameters.trackedArmAmount, time: nil, &step)
        }
    }

    private mutating func emitProgress(_ progress: Double, _ step: inout HistorySwipeStep) {
        let value = HistorySwipeProgress(fraction: min(max(progress, 0), 1), stretch: stretch(progress))
        guard value != lastProgress else { return }
        lastProgress = value
        step.outputs.append(.progress(value))
    }

    private func stretch(_ progress: Double) -> Double {
        guard progress > 0 else { return 0 }
        guard progress > 1, parameters.rubberBand > 0 else { return min(progress, 1) }
        let resisted = (progress - 1) * parameters.rubberBand
        return 1 + resisted / (resisted + 1)
    }

    private mutating func cancel(_ step: inout HistorySwipeStep) {
        guard state != .completed else { return }
        if announced && isLive { step.outputs.append(.cancel) }
        state = .cancelled
        holdDeadline = nil
        edgeDeadline = nil
        selection = nil
        liveTracking = nil
    }

    private static func average(_ points: [HistorySwipePoint]) -> HistorySwipePoint {
        var sum = HistorySwipePoint(x: 0, y: 0)
        for point in points {
            sum.x += point.x
            sum.y += point.y
        }
        guard points.count > 1 else { return sum }
        return HistorySwipePoint(x: sum.x / Double(points.count), y: sum.y / Double(points.count))
    }
}
