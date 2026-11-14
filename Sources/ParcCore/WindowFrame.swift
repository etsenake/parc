import CoreGraphics
import Foundation

enum WindowFrameThickness {
    static let range: ClosedRange<Int> = 3...13
    static let standard = 10
    static let windowCornerRadius: CGFloat = 16
    static let splitGripMinimum: CGFloat = 6
    private static let names = [3: "Hairline", 4: "Whisker", 5: "Pinstripe", 6: "Ribbon", 7: "Piping", 8: "Snug",
                                9: "Comfy", 10: "Classic", 11: "Roomy", 12: "Salon", 13: "Gallery"]

    static func clamped(_ value: Int) -> Int { min(range.upperBound, max(range.lowerBound, value)) }
    static func nearest(_ value: CGFloat) -> Int { clamped(Int(value.rounded())) }
    static func name(_ value: Int) -> String { names[clamped(value)] ?? "" }
    static func label(_ value: Int) -> String { "\(clamped(value)) · \(name(value))" }
    static func spokenValue(_ value: Int) -> String { "\(clamped(value)) points, \(name(value))" }
    static func cornerRadius(for thickness: CGFloat) -> CGFloat { max(4, min(12, windowCornerRadius - thickness)) }
    static func showsSplitGrip(_ thickness: CGFloat) -> Bool { thickness >= splitGripMinimum }
    static func notchPitch(_ value: Int) -> Double { pow(2, Double(clamped(value) - 8) / 12) }
}

struct WindowFrameCrank: Equatable {
    enum End: Equatable { case thin, thick }
    enum Event: Equatable {
        case notch(Int)
        case end(End)
    }

    static let degreesPerPoint = 120.0
    static let give = 0.35
    static let giveSoftness = 0.6
    static let notchCapture = 0.12
    static let preciseScrollDegrees = 1.5
    static let lineScrollDegrees = 40.0

    let initialValue: Int
    private(set) var raw: Double
    private(set) var lastNotch: Int
    private(set) var endHeld: End?

    init(value: Int) {
        let start = WindowFrameThickness.clamped(value)
        initialValue = start
        raw = Double(start)
        lastNotch = start
        endHeld = nil
    }

    var displayed: Double { Self.rubber(raw) }
    var value: Int { WindowFrameThickness.nearest(CGFloat(displayed)) }
    var armDegrees: Double { 90 - (displayed - Double(WindowFrameThickness.range.lowerBound)) * Self.degreesPerPoint }
    var litCount: Int { value - WindowFrameThickness.range.lowerBound + 1 }
    var strain: Double {
        let low = Double(WindowFrameThickness.range.lowerBound), high = Double(WindowFrameThickness.range.upperBound)
        let excess = raw > high ? raw - high : raw < low ? low - raw : 0
        return min(1, excess / Self.giveSoftness)
    }

    static func rubber(_ raw: Double) -> Double {
        let low = Double(WindowFrameThickness.range.lowerBound), high = Double(WindowFrameThickness.range.upperBound)
        if raw > high { return high + give * tanh((raw - high) / giveSoftness) }
        if raw < low { return low - give * tanh((low - raw) / giveSoftness) }
        return raw
    }

    static func scrollDegrees(deltaY: Double, precise: Bool) -> Double {
        deltaY * (precise ? preciseScrollDegrees : lineScrollDegrees)
    }

    static func dragDegrees(from previous: CGPoint, to next: CGPoint, around hub: CGPoint) -> Double {
        let a = atan2(Double(previous.y - hub.y), Double(previous.x - hub.x))
        let b = atan2(Double(next.y - hub.y), Double(next.x - hub.x))
        var delta = (b - a) * 180 / .pi
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        return -delta
    }

    @discardableResult
    mutating func turn(degrees: Double) -> [Event] {
        guard degrees.isFinite, degrees != 0 else { return [] }
        let limit = Double(WindowFrameThickness.range.upperBound - WindowFrameThickness.range.lowerBound) + Self.giveSoftness * 3
        raw = min(Double(WindowFrameThickness.range.upperBound) + limit, max(Double(WindowFrameThickness.range.lowerBound) - limit,
            raw + degrees / Self.degreesPerPoint))
        return events()
    }

    @discardableResult
    mutating func step(points: Int) -> [Event] {
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
    mutating func release() -> [Event] {
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

enum WindowFrameCrankPlacement {
    static let hubInset: CGFloat = 125
    static let swingRadius: CGFloat = 87
    static let lightsRadius: CGFloat = 100
    static let extent: CGFloat = 116

    static func hub(in bounds: CGRect, dockedSidebarEdge: CGFloat?) -> CGPoint {
        let preferredX = dockedSidebarEdge.map { max(bounds.minX + hubInset, $0) } ?? bounds.minX + hubInset
        return CGPoint(x: clamp(preferredX, bounds.minX + hubInset, bounds.maxX - hubInset, center: bounds.midX),
                       y: clamp(bounds.minY + hubInset, bounds.minY + hubInset, bounds.maxY - hubInset, center: bounds.midY))
    }

    static func fits(hub: CGPoint, in bounds: CGRect) -> Bool {
        bounds.insetBy(dx: -0.001, dy: -0.001).contains(CGRect(x: hub.x - extent, y: hub.y - extent, width: 2 * extent, height: 2 * extent))
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat, center: CGFloat) -> CGFloat {
        low > high ? center : min(high, max(low, value))
    }
}
