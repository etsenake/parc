import Foundation
import CoreGraphics

enum Curve {
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ u: Double) -> Double {
        let u = min(1, max(0, u))
        func bx(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t }
        func by(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t }
        var lo = 0.0, hi = 1.0, t = u
        for _ in 0..<60 { t = (lo + hi) / 2; if bx(t) < u { lo = t } else { hi = t } }
        return by(t)
    }
    static func easeOut(_ u: Double) -> Double { bezier(0, 0, 0.58, 1, u) }
    static func easeIn(_ u: Double) -> Double { bezier(0.42, 0, 1, 1, u) }
    static func easeInOut(_ u: Double) -> Double { bezier(0.42, 0, 0.58, 1, u) }
    static func reveal(_ u: Double) -> Double { bezier(0.215, 0.61, 0.355, 1, u) }
    static func spring(response: Double, damping: Double, _ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let zeta = damping
        let wd = omega * sqrt(1 - zeta * zeta)
        return 1 - exp(-zeta * omega * t) * (cos(wd * t) + zeta * omega / wd * sin(wd * t))
    }
    static func progress(_ t: Double, _ start: Double, _ end: Double) -> Double { min(1, max(0, (t - start) / (end - start))) }
    static func mix(_ a: CGFloat, _ b: CGFloat, _ f: Double) -> CGFloat { a + (b - a) * CGFloat(f) }
    static func mix(_ a: CGPoint, _ b: CGPoint, _ f: Double) -> CGPoint { CGPoint(x: mix(a.x, b.x, f), y: mix(a.y, b.y, f)) }
}

struct PointerPath {
    var keys: [(t: Double, p: CGPoint)]
    func at(_ t: Double) -> CGPoint {
        guard let first = keys.first else { return .zero }
        if t <= first.t { return first.p }
        for i in 1..<keys.count where t <= keys[i].t {
            let a = keys[i - 1], b = keys[i]
            if a.p == b.p { return b.p }
            let f = Curve.easeInOut(Curve.progress(t, a.t, b.t))
            let arc = sin(Double.pi * f) * Double(hypot(b.p.x - a.p.x, b.p.y - a.p.y)) * 0.04
            let nx = -(b.p.y - a.p.y), ny = b.p.x - a.p.x, len = max(1, hypot(nx, ny))
            let base = Curve.mix(a.p, b.p, f)
            return CGPoint(x: base.x + nx / len * CGFloat(arc), y: base.y + ny / len * CGFloat(arc))
        }
        return keys[keys.count - 1].p
    }
}
