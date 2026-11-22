import Foundation

package struct HistorySwipeParameters: Equatable {
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
    var edgeMargin = 0.03
    var edgeStepInterval: TimeInterval = 0.1
    var listCloseProgress = 0.85
    var dismissDistance = 0.3
    var dismissCommitProgress = 0.5
    var dismissDisarmProgress = 0.45
    var flickVelocity = 0.6
    var flickProgress = 0.1
    var velocityWindow: TimeInterval = 0.08

    static let dia = HistorySwipeParameters()
}

struct HistorySwipeRecognizer {
    package enum State: Equatable {
        case waitingForPage
        case possible
        case tracking
        case armed
        case holding
        case completed
        case cancelled
    }

    package enum Source: Equatable {
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
    private(set) var dismissing = false
    private var samples: [(time: TimeInterval, x: Double)] = []
    private var inverted = false
    private var announced = false
    private var receivingTouches = false
    private var listOpened = false
    private var restingSince: TimeInterval?
    private var start = HistorySwipePoint(x: 0, y: 0)
    private var current = HistorySwipePoint(x: 0, y: 0)
    private var totalY = 0.0
    private var armedY = 0.0
    private var armedTotalY = 0.0
    private var rowAnchor = 0.0
    private var lastRemainder = 0.0
    private var edgeDeadline: TimeInterval?
    private var edgeSide = 0
    private var edgeEngaged = false
    private var edgeLow = 0.0
    private var edgeHigh = 0.0
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
            samples = []
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
        holdIfDue(time, &step)
        let point = Self.average(points)
        if state == .armed && holdDeadline != nil {
            totalY = armedTotalY + abs(point.y - armedY)
        } else {
            totalY += abs(point.y - current.y)
        }
        current = point
        record(time)
        if listOpened && touchProgress <= 0 {
            cancel(&step)
            return false
        }
        if state == .holding {
            guard touchProgress < parameters.listCloseProgress else {
                emitProgress(touchProgress, &step)
                stepRows(&step)
                followEdge(time: time, &step)
                emitRemainder(&step)
                return true
            }
            closeList()
        }
        if driftsVertically {
            cancel(&step)
            return false
        }
        guard state != .waitingForPage else { return false }
        if state == .possible && (abs(current.x - start.x) > parameters.consumeDistance || touchProgress >= 1) {
            state = .tracking
            if direction == .back && !dismissing { step.preloadsBack = true }
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

    private var travel: Double {
        var travel = current.x - start.x
        if direction == .back { travel = -travel }
        if inverted { travel = -travel }
        return travel
    }

    private var touchProgress: Double {
        travel / (dismissing ? parameters.dismissDistance * parameters.dismissCommitProgress : parameters.commitDistance)
    }

    private var disarmPoint: Double {
        dismissing ? parameters.dismissDisarmProgress / parameters.dismissCommitProgress : 1
    }

    private mutating func record(_ time: TimeInterval) {
        guard dismissing else { return }
        samples.append((time, travel / parameters.dismissDistance))
        let oldest = time - parameters.velocityWindow
        if let keep = samples.firstIndex(where: { $0.time >= oldest }), keep > 0 { samples.removeFirst(keep) }
    }

    private var velocity: Double {
        guard let last = samples.last else { return 0 }
        var reference = last, sign = 0.0
        for sample in samples.reversed().dropFirst() {
            let way: Double = reference.x > sample.x ? 1 : reference.x < sample.x ? -1 : 0
            if way != 0 && sign != 0 && way != sign { break }
            if way != 0 { sign = way }
            reference = sample
        }
        guard last.time - reference.time > 0.005 else { return 0 }
        return (last.x - reference.x) / (last.time - reference.time)
    }

    private mutating func advance(_ progress: Double, time: TimeInterval?, _ step: inout HistorySwipeStep) {
        emitProgress(progress, &step)
        if progress >= 1 && state == .tracking {
            state = .armed
            step.outputs.append(.armed(true))
            armedY = current.y
            armedTotalY = totalY
            if source == .touches, !dismissing, parameters.holdDelay.isFinite, let time {
                restingSince = time
                holdDeadline = time + parameters.holdDelay
            }
        } else if progress < disarmPoint && state == .armed {
            state = .tracking
            holdDeadline = nil
            restingSince = nil
            step.outputs.append(.armed(false))
        } else if state == .armed && holdDeadline != nil, let time {
            restingSince = time
        }
        if let time { holdIfDue(time, &step) }
    }

    private mutating func holdIfDue(_ time: TimeInterval, _ step: inout HistorySwipeStep) {
        guard state == .armed, source == .touches, receivingTouches,
              let wake = holdDeadline, let rest = restingSince, time >= wake else { return }
        let due = rest + parameters.holdDelay
        guard time >= due else {
            holdDeadline = due
            return
        }
        state = .holding
        holdDeadline = nil
        restingSince = nil
        listOpened = true
        selection = 0
        rowAnchor = current.y
        lastRemainder = 0
        armedTotalY = totalY
        edgeSide = 0
        edgeEngaged = false
        edgeLow = current.y
        edgeHigh = current.y
        edgeDeadline = nil
        trackEdge()
        step.outputs += [.hold, .selection(0)]
    }

    private mutating func closeList() {
        state = .armed
        selection = nil
        edgeDeadline = nil
        totalY = 0
    }

    private var rowSign: Double { direction == .forward ? -1 : 1 }

    private var edge: Int {
        guard edgeEngaged else { return 0 }
        return edgeSide * (direction == .forward ? -1 : 1)
    }

    private mutating func trackEdge() {
        let zone = parameters.edgeZone, margin = parameters.edgeMargin, y = current.y
        let side = edgeSide
        if (edgeSide > 0 && y < 1 - zone - margin) || (edgeSide < 0 && y > zone + margin) { edgeSide = 0 }
        if edgeSide == 0 && zone > 0 {
            let top = y >= 1 - zone, bottom = y <= zone
            if top != bottom { edgeSide = top ? 1 : -1 }
        }
        if edgeSide != side { edgeEngaged = false }
        edgeLow = min(edgeLow, y)
        edgeHigh = max(edgeHigh, y)
        guard edgeSide != 0, !edgeEngaged else { return }
        edgeEngaged = (edgeSide > 0 ? y - edgeLow : edgeHigh - y) >= margin
    }

    private mutating func emitRemainder(_ step: inout HistorySwipeStep) {
        guard parameters.rowStep > 0 else { return }
        var remainder = (current.y - rowAnchor) * rowSign / parameters.rowStep
        if (remainder > 0 && !canStep(1)) || (remainder < 0 && !canStep(-1)) { remainder = 0 }
        guard remainder != lastRemainder else { return }
        lastRemainder = remainder
        step.outputs.append(.rowRemainder(remainder))
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
        trackEdge()
        let way = edge
        guard way != 0, parameters.edgeStepInterval > 0, canStep(way) else {
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
        guard way != 0, moveRow(way, &step) else {
            edgeDeadline = nil
            return
        }
        rowAnchor = current.y
        emitRemainder(&step)
        let next = deadline + parameters.edgeStepInterval
        edgeDeadline = canStep(way) ? (next > time ? next : time + parameters.edgeStepInterval) : nil
    }

    private mutating func finish(_ step: inout HistorySwipeStep) {
        guard let direction, isLive else { return }
        if dismissing {
            let speed = velocity, flick = parameters.flickVelocity / parameters.dismissDistance
            let card = travel / parameters.dismissDistance
            let commits = state != .possible && ((state == .armed && speed > -flick)
                || (speed >= flick && card >= parameters.flickProgress))
            step.outputs += [.release(velocity: speed), commits ? .commit(.dismiss) : .cancel]
        } else {
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
        }
        state = .completed
        holdDeadline = nil
        restingSince = nil
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
        let dismisses = count == 0 && environment.dismisses(toward: way)
        guard count > 0 || dismisses else { return }
        direction = way
        source = .touches
        entries = count
        dismissing = dismisses
        inverted = event.directionInverted
        state = .possible
        announced = true
        lastProgress = HistorySwipeProgress(fraction: 0, stretch: 0)
        samples = []
        step.outputs.append(dismisses ? .beginDismissal : .begin(way))
        step.consumesEvent = consumes(event)
    }

    private mutating func reset() {
        state = .waitingForPage
        direction = nil
        source = nil
        selection = nil
        holdDeadline = nil
        restingSince = nil
        edgeDeadline = nil
        listOpened = false
        entries = 0
        dismissing = false
        samples = []
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
        let dismisses = count == 0 && environment.dismisses(toward: way)
        guard count > 0 || dismisses else { return }
        trackingGeneration += 1
        liveTracking = trackingGeneration
        direction = way
        source = .trackedSwipe
        entries = count
        dismissing = dismisses
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
            step.outputs.append(dismissing ? .beginDismissal : .begin(direction))
        }
        switch update.phase {
        case .began:
            break
        case .ended:
            step.outputs.append(.commit(dismissing ? .dismiss : .adjacent(direction)))
            state = .completed
        case .cancelled:
            step.outputs.append(.cancel)
            state = .cancelled
        default:
            let arm = dismissing ? parameters.dismissCommitProgress : parameters.trackedArmAmount
            advance(abs(update.amount) / arm, time: nil, &step)
        }
    }

    private mutating func emitProgress(_ progress: Double, _ step: inout HistorySwipeStep) {
        let card = min(max(progress * parameters.dismissCommitProgress, 0), 1)
        let value = dismissing ? HistorySwipeProgress(fraction: card, stretch: card)
            : HistorySwipeProgress(fraction: min(max(progress, 0), 1), stretch: stretch(progress))
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
        restingSince = nil
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
