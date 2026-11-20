import CoreGraphics
import Foundation

enum NotePDFLayout {
    static let minimumWidth: CGFloat = 240
    static let minimumHeight: CGFloat = 200
    static let maximumHeight: CGFloat = 960
    static let pageInset: CGFloat = 8
    static let defaultAspect: CGFloat = 11 / 8.5
    static let snapTolerance: CGFloat = 6
    static let rubberBandDimension: CGFloat = 90

    static func floor(for columnWidth: CGFloat) -> CGFloat { min(minimumWidth, columnWidth) }

    static func displayWidth(fraction: Double?, columnWidth: CGFloat) -> CGFloat {
        guard columnWidth > 0 else { return 0 }
        guard let fraction, fraction.isFinite, fraction > 0 else { return columnWidth }
        let width = fraction <= 1 ? CGFloat(fraction) * columnWidth : CGFloat(fraction)
        return min(columnWidth, max(floor(for: columnWidth), width.rounded()))
    }

    static func aspect(_ value: CGFloat?) -> CGFloat {
        guard let value, value.isFinite, value > 0.05, value < 20 else { return defaultAspect }
        return value
    }

    static func viewerHeight(width: CGFloat, aspect value: CGFloat?) -> CGFloat {
        guard width > 0 else { return minimumHeight }
        let page = max(0, width - pageInset * 2) * aspect(value) + pageInset * 2
        return min(maximumHeight, max(minimumHeight, page.rounded()))
    }

    static func pageAspect(width: CGFloat, height: CGFloat, rotation: Int) -> CGFloat? {
        guard width > 0, height > 0 else { return nil }
        let quarter = ((rotation % 360) + 360) % 360
        return quarter == 90 || quarter == 270 ? width / height : height / width
    }

    static func originX(width: CGFloat, alignment: NoteAlignment, columnWidth: CGFloat) -> CGFloat {
        switch alignment {
        case .left: return 0
        case .center: return ((columnWidth - width) / 2).rounded()
        case .right: return (columnWidth - width).rounded()
        }
    }

    static func rawResize(start: CGFloat, dragDelta: CGFloat, leading: Bool, alignment: NoteAlignment) -> CGFloat {
        let direction: CGFloat = leading ? -1 : 1
        let factor: CGFloat = alignment == .center ? 2 : 1
        return start + dragDelta * direction * factor
    }

    static func rubberBanded(_ width: CGFloat, columnWidth: CGFloat) -> CGFloat {
        let lower = floor(for: columnWidth)
        if width > columnWidth { return columnWidth + rubberBand(width - columnWidth) }
        if width < lower { return lower - rubberBand(lower - width) }
        return width
    }

    static func storedFraction(width: CGFloat, columnWidth: CGFloat) -> Double? {
        guard columnWidth > 0 else { return nil }
        let settled = min(columnWidth, max(floor(for: columnWidth), width))
        if columnWidth - settled <= snapTolerance { return nil }
        return (Double(settled / columnWidth) * 1000).rounded() / 1000
    }

    static func rubberBand(_ excess: CGFloat) -> CGFloat {
        guard excess > 0 else { return 0 }
        return (1 - 1 / (excess * 0.55 / rubberBandDimension + 1)) * rubberBandDimension
    }
}

enum NotePDFPages {
    static func label(current: Int, count: Int) -> String {
        guard count > 0 else { return "–" }
        return String(min(max(current, 0), count - 1) + 1) + " / " + String(count)
    }

    static func spokenLabel(current: Int, count: Int) -> String {
        guard count > 0 else { return "No pages" }
        let page = min(max(current, 0), count - 1) + 1
        return count == 1 ? "One page" : "Page \(page) of \(count)"
    }

    static func summary(count: Int) -> String {
        count == 1 ? "1 page" : "\(count) pages"
    }
}

enum NotePDFZoom {
    static let step: CGFloat = 1.25
    static let minimumRatio: CGFloat = 0.5
    static let maximumRatio: CGFloat = 5
    static let snapRatio: CGFloat = 0.03

    struct Outcome: Equatable {
        var scale: CGFloat
        var fitsWidth: Bool
    }

    static func zoomed(current: CGFloat, fit: CGFloat, zoomIn: Bool) -> Outcome {
        guard fit > 0, current > 0, current.isFinite, fit.isFinite else { return Outcome(scale: max(fit, 0.01), fitsWidth: true) }
        let next = zoomIn ? current * step : current / step
        let clamped = min(fit * maximumRatio, max(fit * minimumRatio, next))
        if abs(clamped / fit - 1) <= snapRatio || (current < fit) != (clamped < fit) && current != fit {
            return Outcome(scale: fit, fitsWidth: true)
        }
        return Outcome(scale: clamped, fitsWidth: false)
    }

    static func canZoom(current: CGFloat, fit: CGFloat, zoomIn: Bool) -> Bool {
        guard fit > 0, current > 0 else { return false }
        return zoomIn ? current < fit * maximumRatio * 0.999 : current > fit * minimumRatio * 1.001
    }

    static func percent(current: CGFloat, fit: CGFloat) -> Int {
        guard fit > 0, current > 0 else { return 100 }
        return Int((current / fit * 100).rounded())
    }
}

struct NotePDFScrollLatch: Equatable {
    enum Phase: Equatable { case began, changed, ended, momentum, momentumEnded, discrete }
    enum Route: Equatable { case pdf, note, noteHandedOver }

    struct Room: Equatable {
        var up = false
        var down = false
        var left = false
        var right = false

        func allows(deltaX: Double, deltaY: Double) -> Bool? {
            guard deltaX.isFinite, deltaY.isFinite, deltaX != 0 || deltaY != 0 else { return nil }
            if abs(deltaY) >= abs(deltaX) { return deltaY > 0 ? up : down }
            return deltaX > 0 ? left : right
        }
    }

    enum Target: Equatable { case pdf, note, handedOver }

    static let discreteRunGap: TimeInterval = 0.5

    private(set) var target: Target?
    private var lastDiscrete: TimeInterval?

    func startsGesture(_ phase: Phase, time: TimeInterval) -> Bool {
        switch phase {
        case .began: return true
        case .discrete: return target == nil || lastDiscrete.map { time - $0 > Self.discreteRunGap } ?? true
        default: return false
        }
    }

    mutating func receive(_ phase: Phase, deltaX: Double, deltaY: Double, time: TimeInterval, room: Room) -> Route {
        if startsGesture(phase, time: time) { target = nil }
        lastDiscrete = phase == .discrete ? time : nil
        let allows = room.allows(deltaX: deltaX, deltaY: deltaY)
        switch target {
        case nil:
            if let allows { target = allows ? .pdf : .note }
            return allows == false ? .note : .pdf
        case .pdf?:
            guard phase != .ended, phase != .momentumEnded, allows == false else { return .pdf }
            target = .handedOver
            return .noteHandedOver
        case .note?:
            return .note
        case .handedOver?:
            return .noteHandedOver
        }
    }

    mutating func reset() {
        target = nil
        lastDiscrete = nil
    }
}
