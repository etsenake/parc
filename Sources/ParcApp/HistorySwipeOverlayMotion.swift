import CoreGraphics
import Foundation

enum HistorySwipeOverlayMetrics {
    static let restingDiameter: CGFloat = 72
    static let armedDiameter: CGFloat = 82
    static let edgeInset: CGFloat = 14
    static let restingChevron: CGFloat = 28
    static let armedChevron: CGFloat = 34
    static let chevronPointSize: CGFloat = 28
    static let restingChevronOpacity = 0.5
    static let cardWidth: CGFloat = 200
    static let rowHeight: CGFloat = 38
    static let cardInset: CGFloat = 8
    static let cardRadius: CGFloat = 18
    static let highlightRadius: CGFloat = 10
    static let faviconSize: CGFloat = 16
    static let faviconRadius: CGFloat = 4
    static let titleSize: CGFloat = 13
    static let titleGap: CGFloat = 8
    static let listMargin: CGFloat = 14
    static let rowLean = 0.1
    static let ringWidth: CGFloat = 1
    static let shadowRadius: CGFloat = 8
    static let shadowDrop: CGFloat = 2
    static let reducedAppearance = 0.2
}

enum HistorySwipeOverlayTiming {
    static let arm = HistorySwipeSpring.Shape(damping: 0.70, response: 0.18)
    static let morph = HistorySwipeSpring.Shape(damping: 0.77, response: 0.22)
    static let selection = HistorySwipeSpring.Shape(damping: 0.9, response: 0.27)
    static let fade: TimeInterval = 0.18
    static let swap: TimeInterval = 0.22
    static let swapScale = 0.9
    static let blur = 10.0
    static let collapse: TimeInterval = 0.2
    static let collapseScale = 0.01
    static let reducedFade: TimeInterval = 0.12
    static let reducedSwap: TimeInterval = 0.15
    static let reducedCollapse: TimeInterval = 0.15
}

struct HistorySwipeCurve: Equatable {
    let x1: Double, y1: Double, x2: Double, y2: Double

    static let linear = HistorySwipeCurve(x1: 0, y1: 0, x2: 1, y2: 1)
    static let easeOut = HistorySwipeCurve(x1: 0.25, y1: 0.46, x2: 0.45, y2: 0.94)
    static let easeIn = HistorySwipeCurve(x1: 0.42, y1: 0, x2: 1, y2: 1)

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        if self == .linear { return x }
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            let slope = (3 * ax * t + 2 * bx) * t + cx
            if abs(error) < 1e-9 || abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        if abs(sampleX(t) - x) > 1e-7 {
            var low = 0.0, high = 1.0
            t = x
            for _ in 0..<60 {
                if sampleX(t) < x { low = t } else { high = t }
                t = (low + high) / 2
            }
        }
        return ((ay * t + by) * t + cy) * t
    }
}

struct HistorySwipeSpring: Equatable {
    struct Shape: Equatable {
        var damping: Double
        var response: Double
    }

    var value: Double
    var velocity = 0.0
    let shape: Shape
    let tolerance: Double

    init(_ value: Double, _ shape: Shape, tolerance: Double) {
        self.value = value
        self.shape = shape
        self.tolerance = tolerance
    }

    mutating func snap(_ target: Double) {
        value = target
        velocity = 0
    }

    mutating func advance(toward target: Double, by interval: TimeInterval) {
        guard interval > 0, !isSettled(at: target) else {
            if isSettled(at: target) { snap(target) }
            return
        }
        let omega = 2 * Double.pi / shape.response, zeta = shape.damping
        let start = value - target, speed = velocity, t = interval
        if abs(zeta - 1) < 1e-6 {
            let decay = exp(-omega * t), lead = speed + omega * start
            value = target + (start + lead * t) * decay
            velocity = (speed - omega * lead * t) * decay
        } else if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot(), decay = exp(-zeta * omega * t)
            let cosine = cos(damped * t), sine = sin(damped * t)
            value = target + decay * (start * cosine + (speed + zeta * omega * start) / damped * sine)
            velocity = decay * (speed * cosine - (zeta * omega * speed + omega * omega * start) / damped * sine)
        } else {
            let root = (zeta * zeta - 1).squareRoot()
            let fast = -omega * (zeta + root), slow = -omega * (zeta - root)
            let a = (speed - fast * start) / (slow - fast), b = start - a
            value = target + a * exp(slow * t) + b * exp(fast * t)
            velocity = a * slow * exp(slow * t) + b * fast * exp(fast * t)
        }
        if isSettled(at: target) { snap(target) }
    }

    func isSettled(at target: Double) -> Bool {
        abs(value - target) <= tolerance && abs(velocity) <= tolerance * 10
    }
}

struct HistorySwipeTween: Equatable {
    var from: Double
    var to: Double
    var start: TimeInterval = 0
    var duration: TimeInterval = 0
    var curve = HistorySwipeCurve.linear

    init(_ value: Double) {
        from = value
        to = value
    }

    func value(at time: TimeInterval) -> Double {
        guard duration > 0, time < start + duration else { return to }
        guard time > start else { return from }
        return from + (to - from) * curve((time - start) / duration)
    }

    func isRunning(at time: TimeInterval) -> Bool { duration > 0 && time < start + duration && from != to }

    mutating func retarget(_ target: Double, at time: TimeInterval, duration: TimeInterval, curve: HistorySwipeCurve) {
        from = value(at: time)
        to = target
        start = time
        self.duration = duration
        self.curve = curve
    }
}

struct HistorySwipeOverlayLook: Equatable {
    var ringWhite: Double
    var ringAlpha: Double
    var shadowAlpha: Double
    var washAlpha: Double
    var highlightWhite: Double
    var highlightAlpha: Double

    init(dark: Bool) {
        ringWhite = dark ? 1 : 0
        ringAlpha = dark ? 0.15 : 0.125
        shadowAlpha = dark ? 0.25 : 0.2
        washAlpha = dark ? 0 : 0.4
        highlightWhite = dark ? 1 : 0
        highlightAlpha = 0.1
    }
}

enum HistorySwipeOverlayGeometry {
    typealias M = HistorySwipeOverlayMetrics

    static func edgeOffset(stretch: Double, diameter: CGFloat) -> CGFloat {
        CGFloat(max(0, stretch)) * (diameter + M.edgeInset) - diameter
    }

    static func circle(direction: HistorySwipeDirection, stretch: Double, diameter: CGFloat,
                       in size: CGSize, reducesMotion: Bool) -> CGRect {
        let offset = reducesMotion ? M.edgeInset : edgeOffset(stretch: stretch, diameter: diameter)
        let x = direction == .back ? offset : size.width - diameter - offset
        return CGRect(x: x, y: size.height / 2 - diameter / 2, width: diameter, height: diameter)
    }

    static func currentRowCenter(direction: HistorySwipeDirection, rows: Int) -> CGFloat {
        let ahead = direction == .back ? CGFloat(max(0, rows - 1)) : 0
        return M.cardInset + ahead * M.rowHeight + M.rowHeight / 2
    }

    static func contentHeight(rows: Int) -> CGFloat {
        CGFloat(max(0, rows)) * M.rowHeight + 2 * M.cardInset
    }

    static func list(direction: HistorySwipeDirection, rows: Int, offset: CGFloat, circle: CGRect,
                     in size: CGSize) -> (content: CGRect, card: CGRect) {
        let margin = M.listMargin
        let width = min(M.cardWidth, max(0, size.width - 2 * margin))
        var x = direction == .back ? circle.minX : circle.maxX - width
        if size.width >= width + 2 * margin { x = min(max(x, margin), size.width - margin - width) }
        let shift = direction == .back ? -offset : offset
        let top = size.height / 2 - currentRowCenter(direction: direction, rows: rows) - shift
        let content = CGRect(x: x, y: top, width: width, height: contentHeight(rows: rows))
        let visibleTop = max(content.minY, margin), visibleBottom = min(content.maxY, size.height - margin)
        guard visibleBottom > visibleTop else { return (content, content) }
        return (content, CGRect(x: x, y: visibleTop, width: width, height: visibleBottom - visibleTop))
    }

    static func row(_ index: Int, rows: Int, direction: HistorySwipeDirection, content: CGRect) -> CGRect {
        let slot = direction == .back ? rows - 1 - index : index
        return CGRect(x: content.minX + M.cardInset, y: content.minY + M.cardInset + CGFloat(slot) * M.rowHeight,
                      width: max(0, content.width - 2 * M.cardInset), height: M.rowHeight)
    }

    static func lean(remainder: Double) -> CGFloat {
        let pull = 1 - 1 / (abs(remainder) * M.rowLean + 1)
        return CGFloat(remainder < 0 ? -pull : pull) * M.rowHeight
    }

    static func blend(_ from: CGRect, _ to: CGRect, _ amount: Double) -> CGRect {
        let t = CGFloat(amount)
        return CGRect(x: from.minX + (to.minX - from.minX) * t, y: from.minY + (to.minY - from.minY) * t,
                      width: max(0, from.width + (to.width - from.width) * t),
                      height: max(0, from.height + (to.height - from.height) * t))
    }
}

struct HistorySwipeOverlayListFrame: Equatable {
    var direction: HistorySwipeDirection
    var rows: Int
    var selection: Int
    var content: CGRect
    var card: CGRect
    var highlight: CGRect
    var opacity: Double
    var scale: Double
    var blur: Double

    func row(_ index: Int) -> CGRect {
        HistorySwipeOverlayGeometry.row(index, rows: rows, direction: direction, content: content)
    }
}

struct HistorySwipeOverlayFrame: Equatable {
    var direction: HistorySwipeDirection
    var circle: CGRect
    var capsule: CGRect
    var cornerRadius: CGFloat
    var opacity: Double
    var scale: Double
    var blur: Double
    var wash: Double
    var chevronCenter: CGPoint
    var chevronSize: CGFloat
    var chevronOpacity: Double
    var chevronScale: Double
    var chevronBlur: Double
    var list: HistorySwipeOverlayListFrame?
}

struct HistorySwipeOverlayModel {
    typealias M = HistorySwipeOverlayMetrics
    typealias T = HistorySwipeOverlayTiming

    enum Haptic: Equatable {
        case levelChange
        case generic
        case alignment
    }

    enum Phase: Equatable {
        case idle
        case live
        case collapsing(since: TimeInterval)
    }

    var prefersReducedMotion = false
    var backRows = 0
    var forwardRows = 0
    private(set) var phase = Phase.idle
    private(set) var direction = HistorySwipeDirection.back
    private(set) var reducesMotion = false
    private(set) var stretch = 0.0
    private(set) var armed = false
    private(set) var listOpen = false
    private(set) var selection = 0
    private(set) var remainder = 0.0
    private(set) var now: TimeInterval = 0
    private var swappedAt: TimeInterval?
    private var snapsSelection = false
    private var diameter = HistorySwipeSpring(Double(M.restingDiameter), T.arm, tolerance: 0.01)
    private var chevron = HistorySwipeSpring(Double(M.restingChevron), T.arm, tolerance: 0.01)
    private var morph = HistorySwipeSpring(0, T.morph, tolerance: 0.0005)
    private var offset = HistorySwipeSpring(0, T.selection, tolerance: 0.01)
    private var armFade = HistorySwipeTween(0)
    private var visibility = HistorySwipeTween(0)
    private var swap = HistorySwipeTween(0)

    var rows: Int { 1 + (direction == .back ? backRows : forwardRows) }

    var shownSelection: Int { min(max(selection, 0), rows - 1) }

    mutating func receive(_ output: HistorySwipeOutput, at time: TimeInterval) -> Haptic? {
        advance(to: time)
        switch output {
        case let .begin(way):
            var fresh = HistorySwipeOverlayModel()
            fresh.prefersReducedMotion = prefersReducedMotion
            fresh.backRows = backRows
            fresh.forwardRows = forwardRows
            fresh.phase = .live
            fresh.direction = way
            fresh.reducesMotion = prefersReducedMotion
            fresh.now = time
            self = fresh
        case let .progress(progress):
            guard phase == .live else { return nil }
            stretch = max(0, progress.stretch)
            updateVisibility(at: time, fade: T.reducedFade)
        case let .armed(on):
            guard phase == .live, on != armed else { return nil }
            armed = on
            armFade.retarget(on ? 1 : 0, at: time, duration: reducesMotion ? T.reducedFade : T.fade,
                             curve: reducesMotion ? .linear : .easeOut)
            if !on && listOpen { closeList(at: time) }
            return on ? .levelChange : nil
        case .hold:
            guard phase == .live, !listOpen else { return nil }
            snapsSelection = !listShowing
            listOpen = true
            swappedAt = time
            remainder = 0
            updateVisibility(at: time, fade: 0)
            swap.retarget(1, at: time, duration: reducesMotion ? T.reducedSwap : T.swap,
                          curve: reducesMotion ? .linear : .easeOut)
            return .generic
        case let .selection(row):
            guard phase == .live else { return nil }
            selection = row
            if snapsSelection || reducesMotion { offset.snap(offsetTarget) }
            snapsSelection = false
        case let .rowRemainder(value):
            guard phase == .live, listOpen else { return nil }
            remainder = value
        case .detent:
            guard phase == .live, listOpen else { return nil }
            return .alignment
        case .commit, .cancel:
            guard phase == .live else { return nil }
            phase = .collapsing(since: time)
        }
        return nil
    }

    mutating func advance(to time: TimeInterval) {
        let interval = time - now
        guard interval > 0 else { return }
        now = time
        if case let .collapsing(since) = phase,
           time - since >= (reducesMotion ? T.reducedCollapse : T.collapse) {
            phase = .idle
            return
        }
        guard phase != .idle else { return }
        diameter.advance(toward: diameterTarget, by: interval)
        chevron.advance(toward: chevronTarget, by: interval)
        if reducesMotion {
            morph.snap(morphTarget)
            offset.snap(offsetTarget)
        } else {
            morph.advance(toward: morphTarget, by: interval)
            offset.advance(toward: offsetTarget, by: interval)
        }
    }

    mutating func reset() {
        phase = .idle
    }

    var isAnimating: Bool {
        switch phase {
        case .idle: return false
        case .collapsing: return true
        case .live:
            return !diameter.isSettled(at: diameterTarget) || !chevron.isSettled(at: chevronTarget)
                || !morph.isSettled(at: morphTarget) || !offset.isSettled(at: offsetTarget)
                || armFade.isRunning(at: now) || visibility.isRunning(at: now) || swap.isRunning(at: now)
                || reducedSwapFade < 1
        }
    }

    private var listShowing: Bool {
        if reducesMotion { return listOpen }
        return listOpen || swap.value(at: now) > 0.001 || abs(morph.value) > 0.0005
    }

    private var reducedSwapFade: Double {
        guard reducesMotion, let swappedAt else { return 1 }
        return min(max((now - swappedAt) / T.reducedSwap, 0), 1)
    }

    func frame(in size: CGSize) -> HistorySwipeOverlayFrame? {
        if phase == .idle { return nil }
        let reduced = reducesMotion
        let width = reduced ? M.restingDiameter : CGFloat(diameter.value)
        let circle = HistorySwipeOverlayGeometry.circle(direction: direction, stretch: stretch, diameter: width,
                                                        in: size, reducesMotion: reduced)
        let swapIn = swap.value(at: now)
        var opacity = 1.0, scale = 1.0, blur = 0.0
        if reduced { opacity = visibility.value(at: now) * reducedSwapFade }
        if case let .collapsing(since) = phase {
            if reduced {
                opacity *= 1 - min(max((now - since) / T.reducedCollapse, 0), 1)
            } else {
                let amount = HistorySwipeCurve.easeIn((now - since) / T.collapse)
                opacity *= 1 - amount
                scale = 1 - (1 - T.collapseScale) * amount
                blur = T.blur * amount
            }
        }
        var list: HistorySwipeOverlayListFrame?
        var capsule = circle
        var radius = width / 2
        if listShowing {
            let layout = HistorySwipeOverlayGeometry.list(direction: direction, rows: rows,
                                                          offset: CGFloat(offset.value), circle: circle, in: size)
            let blend = reduced ? 1 : morph.value
            capsule = HistorySwipeOverlayGeometry.blend(circle, layout.card, blend)
            radius = width / 2 + (M.cardRadius - width / 2) * CGFloat(blend)
            let highlight = CGRect(x: layout.content.minX + M.cardInset, y: size.height / 2 - M.rowHeight / 2,
                                   width: max(0, layout.content.width - 2 * M.cardInset), height: M.rowHeight)
            list = HistorySwipeOverlayListFrame(
                direction: direction, rows: rows, selection: shownSelection, content: layout.content,
                card: layout.card, highlight: highlight, opacity: swapIn,
                scale: reduced ? 1 : T.swapScale + (1 - T.swapScale) * swapIn,
                blur: reduced ? 0 : T.blur * (1 - swapIn))
        }
        let armedAmount = armFade.value(at: now)
        let opacityRange = 1 - M.restingChevronOpacity
        return HistorySwipeOverlayFrame(
            direction: direction, circle: circle, capsule: capsule, cornerRadius: max(0, radius),
            opacity: opacity, scale: scale, blur: blur, wash: armedAmount,
            chevronCenter: CGPoint(x: circle.midX, y: circle.midY),
            chevronSize: reduced ? M.restingChevron : CGFloat(chevron.value),
            chevronOpacity: (M.restingChevronOpacity + opacityRange * armedAmount) * (1 - swapIn),
            chevronScale: reduced ? 1 : 1 - (1 - T.swapScale) * swapIn,
            chevronBlur: reduced ? 0 : T.blur * swapIn,
            list: list)
    }

    private var diameterTarget: Double {
        Double(armed && !reducesMotion ? M.armedDiameter : M.restingDiameter)
    }

    private var chevronTarget: Double {
        Double(armed && !reducesMotion ? M.armedChevron : M.restingChevron)
    }

    private var morphTarget: Double { listOpen ? 1 : 0 }

    private var offsetTarget: Double {
        let lean = reducesMotion ? 0 : HistorySwipeOverlayGeometry.lean(remainder: remainder)
        return Double(CGFloat(shownSelection) * M.rowHeight + lean)
    }

    private mutating func updateVisibility(at time: TimeInterval, fade: TimeInterval) {
        guard reducesMotion else { return }
        let shown = (listOpen || stretch >= M.reducedAppearance) ? 1.0 : 0
        guard visibility.to != shown else { return }
        visibility.retarget(shown, at: time, duration: fade, curve: .linear)
    }

    private mutating func closeList(at time: TimeInterval) {
        listOpen = false
        swappedAt = time
        swap.retarget(0, at: time, duration: reducesMotion ? T.reducedSwap : T.swap,
                      curve: reducesMotion ? .linear : .easeOut)
        updateVisibility(at: time, fade: 0)
    }
}
