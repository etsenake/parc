import Foundation
import CoreGraphics

public protocol Lerpable {
    static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self
}

extension Double: Lerpable {
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

public struct Vec3: Lerpable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vec3(0, 0, 0)
    public static func lerp(_ a: Vec3, _ b: Vec3, _ t: Double) -> Vec3 {
        Vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }
    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
}

public enum Ease: Sendable {
    case linear
    case hold
    case bezier(Double, Double, Double, Double)
    case spring(response: Double, damping: Double)

    public static let standard = Ease.bezier(0.25, 0.1, 0.25, 1)
    public static let inOut = Ease.bezier(0.65, 0, 0.35, 1)
    public static let out = Ease.bezier(0.16, 1, 0.3, 1)
    public static let gentle = Ease.bezier(0.4, 0, 0.2, 1)
    public static let accelerate = Ease.bezier(0.5, 0, 0.9, 0.3)
    public static let critical = Ease.spring(response: 0.9, damping: 1)

    public func progress(elapsed: Double, duration: Double) -> Double {
        switch self {
        case .linear:
            return duration <= 0 ? 1 : min(max(elapsed / duration, 0), 1)
        case .hold:
            return elapsed >= duration ? 1 : 0
        case let .bezier(x1, y1, x2, y2):
            let u = duration <= 0 ? 1 : min(max(elapsed / duration, 0), 1)
            return Ease.solveBezier(u, x1, y1, x2, y2)
        case let .spring(response, damping):
            return Ease.spring(elapsed, response: response, damping: damping)
        }
    }

    static func spring(_ t: Double, response: Double, damping: Double) -> Double {
        if t <= 0 { return 0 }
        let w = 2 * Double.pi / response
        if damping >= 1 {
            return 1 - (1 + w * t) * exp(-w * t)
        }
        let wd = w * sqrt(1 - damping * damping)
        return 1 - exp(-damping * w * t) * (cos(wd * t) + damping * w / wd * sin(wd * t))
    }

    static func solveBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        func sx(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        func dsx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }
        var t = x
        for _ in 0..<8 {
            let e = sx(t) - x
            let d = dsx(t)
            if abs(e) < 1e-7 { break }
            if abs(d) < 1e-6 { break }
            t -= e / d
        }
        if t < 0 || t > 1 || abs(sx(t) - x) > 1e-5 {
            var lo = 0.0, hi = 1.0
            t = x
            for _ in 0..<40 {
                let v = sx(t)
                if abs(v - x) < 1e-7 { break }
                if v < x { lo = t } else { hi = t }
                t = (lo + hi) / 2
            }
        }
        return ((ay * t + by) * t + cy) * t
    }
}

public struct Key<V: Lerpable> {
    public var time: Double
    public var value: V
    public var ease: Ease
}

public struct Track<V: Lerpable> {
    public private(set) var keys: [Key<V>]

    public init(_ value: V) { keys = [Key(time: 0, value: value, ease: .hold)] }

    @discardableResult
    public mutating func key(_ time: Double, _ value: V, _ ease: Ease = .inOut) -> Track<V> {
        keys.removeAll { $0.time == time }
        keys.append(Key(time: time, value: value, ease: ease))
        keys.sort { $0.time < $1.time }
        return self
    }

    public func keyed(_ time: Double, _ value: V, _ ease: Ease = .inOut) -> Track<V> {
        var c = self
        c.key(time, value, ease)
        return c
    }

    public func holding(until time: Double) -> Track<V> {
        guard let last = keys.last, time > last.time else { return self }
        return keyed(time, last.value, .hold)
    }

    public func value(at t: Double) -> V {
        guard let first = keys.first else { fatalError("empty track") }
        if t <= first.time { return first.value }
        var prev = first
        for k in keys.dropFirst() {
            if t < k.time {
                let p = k.ease.progress(elapsed: t - prev.time, duration: k.time - prev.time)
                return V.lerp(prev.value, k.value, p)
            }
            prev = k
        }
        return prev.value
    }
}

