import CoreGraphics
import Foundation

package enum WindowFrameThickness {
    package static let range: ClosedRange<Int> = 3...13
    package static let standard = 10
    package static let windowCornerRadius: CGFloat = 16
    package static let splitGripMinimum: CGFloat = 6
    private static let names = [3: "Hairline", 4: "Whisker", 5: "Pinstripe", 6: "Ribbon", 7: "Piping", 8: "Snug",
                                9: "Comfy", 10: "Classic", 11: "Roomy", 12: "Salon", 13: "Gallery"]

    package static func clamped(_ value: Int) -> Int { min(range.upperBound, max(range.lowerBound, value)) }
    package static func nearest(_ value: CGFloat) -> Int { clamped(Int(value.rounded())) }
    package static func name(_ value: Int) -> String { names[clamped(value)] ?? "" }
    package static func label(_ value: Int) -> String { "\(clamped(value)) · \(name(value))" }
    package static func spokenValue(_ value: Int) -> String { "\(clamped(value)) points, \(name(value))" }
    package static func cornerRadius(for thickness: CGFloat) -> CGFloat { max(4, min(12, windowCornerRadius - thickness)) }
    package static func showsSplitGrip(_ thickness: CGFloat) -> Bool { thickness >= splitGripMinimum }
    package static func notchPitch(_ value: Int) -> Double { pow(2, Double(clamped(value) - 8) / 12) }
}

package struct WindowFrameCrank: Equatable {
    package enum End: Equatable { case thin, thick }
    package enum Event: Equatable {
        case notch(Int)
        case end(End)
    }

    package static let degreesPerPoint = 120.0
    package static let give = 0.35
    package static let giveSoftness = 0.6
    package static let notchCapture = 0.12
    package static let preciseScrollDegrees = 1.5
    package static let lineScrollDegrees = 40.0

    package let initialValue: Int
    package private(set) var raw: Double
    package private(set) var lastNotch: Int
    package private(set) var endHeld: End?

    package init(value: Int) {
        let start = WindowFrameThickness.clamped(value)
        initialValue = start
        raw = Double(start)
        lastNotch = start
        endHeld = nil
    }

    package var displayed: Double { Self.rubber(raw) }
    package var value: Int { WindowFrameThickness.nearest(CGFloat(displayed)) }
    package var armDegrees: Double { 90 - (displayed - Double(WindowFrameThickness.range.lowerBound)) * Self.degreesPerPoint }
    package var litCount: Int { value - WindowFrameThickness.range.lowerBound + 1 }
    package var strain: Double {
        let low = Double(WindowFrameThickness.range.lowerBound), high = Double(WindowFrameThickness.range.upperBound)
        let excess = raw > high ? raw - high : raw < low ? low - raw : 0
        return min(1, excess / Self.giveSoftness)
    }

    package static func rubber(_ raw: Double) -> Double {
        let low = Double(WindowFrameThickness.range.lowerBound), high = Double(WindowFrameThickness.range.upperBound)
        if raw > high { return high + give * tanh((raw - high) / giveSoftness) }
        if raw < low { return low - give * tanh((low - raw) / giveSoftness) }
        return raw
    }

    package static func scrollDegrees(deltaY: Double, precise: Bool) -> Double {
        deltaY * (precise ? preciseScrollDegrees : lineScrollDegrees)
    }

    package static func dragDegrees(from previous: CGPoint, to next: CGPoint, around hub: CGPoint) -> Double {
        let a = atan2(Double(previous.y - hub.y), Double(previous.x - hub.x))
        let b = atan2(Double(next.y - hub.y), Double(next.x - hub.x))
        var delta = (b - a) * 180 / .pi
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        return -delta
    }

    @discardableResult
    package mutating func turn(degrees: Double) -> [Event] {
        guard degrees.isFinite, degrees != 0 else { return [] }
        let limit = Double(WindowFrameThickness.range.upperBound - WindowFrameThickness.range.lowerBound) + Self.giveSoftness * 3
        raw = min(Double(WindowFrameThickness.range.upperBound) + limit, max(Double(WindowFrameThickness.range.lowerBound) - limit,
            raw + degrees / Self.degreesPerPoint))
        return events()
    }

    @discardableResult
    package mutating func step(points: Int) -> [Event] {
        let target = value + points
        raw = Double(WindowFrameThickness.clamped(target))
        var out = events()
        if !WindowFrameThickness.range.contains(target) {
            out.append(.end(target > WindowFrameThickness.range.upperBound ? .thick : .thin))
        }
        endHeld = nil
        return out
    }

    @discardableResult
    package mutating func release() -> [Event] {
        let settled = value
        raw = Double(settled)
        let out = events()
        endHeld = nil
        return out
    }

    private mutating func events() -> [Event] {
        var out: [Event] = []
        let shown = displayed
        let nearest = Int(shown.rounded())
        if WindowFrameThickness.range.contains(nearest), nearest != lastNotch, abs(shown - Double(nearest)) < Self.notchCapture {
            let from = lastNotch
            let stepDirection = nearest > from ? 1 : -1
            var point = from + stepDirection
            while point != nearest + stepDirection {
                out.append(.notch(point))
                point += stepDirection
            }
            lastNotch = nearest
        }
        let low = Double(WindowFrameThickness.range.lowerBound), high = Double(WindowFrameThickness.range.upperBound)
        let end: End? = raw > high ? .thick : raw < low ? .thin : nil
        if let end, end != endHeld { out.append(.end(end)) }
        endHeld = end
        return out
    }
}

package enum WindowFrameCrankPlacement {
    package static let hubInset: CGFloat = 125
    package static let swingRadius: CGFloat = 87
    package static let lightsRadius: CGFloat = 100
    package static let extent: CGFloat = 116

    package static func hub(in bounds: CGRect, dockedSidebarEdge: CGFloat?) -> CGPoint {
        let preferredX = dockedSidebarEdge.map { max(bounds.minX + hubInset, $0) } ?? bounds.minX + hubInset
        return CGPoint(x: clamp(preferredX, bounds.minX + hubInset, bounds.maxX - hubInset, center: bounds.midX),
                       y: clamp(bounds.minY + hubInset, bounds.minY + hubInset, bounds.maxY - hubInset, center: bounds.midY))
    }

    package static func fits(hub: CGPoint, in bounds: CGRect) -> Bool {
        bounds.insetBy(dx: -0.001, dy: -0.001).contains(CGRect(x: hub.x - extent, y: hub.y - extent, width: 2 * extent, height: 2 * extent))
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat, center: CGFloat) -> CGFloat {
        low > high ? center : min(high, max(low, value))
    }
}
