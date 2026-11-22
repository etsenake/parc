import CoreGraphics
import Foundation

struct DownloadArrivalSpring {
    static let resolvingEpsilon = 0.01
    private(set) var stiffness = 300.0
    private(set) var damping = 10.0
    var value: SIMD2<Double>
    var toValue: SIMD2<Double>
    private(set) var displacementVelocity = SIMD2<Double>.zero

    init(initialValue: SIMD2<Double> = .zero) { value = initialValue; toValue = initialValue }

    mutating func configure(response: Double, dampingRatio: Double) {
        stiffness = pow(2 * .pi / response, 2); damping = 4 * .pi * dampingRatio / response
    }
    var naturalFrequency: Double { stiffness.squareRoot() }
    var dampingRatio: Double { damping / (2 * naturalFrequency) }

    mutating func setVelocity(_ velocity: SIMD2<Double>) { displacementVelocity = SIMD2<Double>(repeating: 0) - velocity }

    func solve(_ dt: Double, _ x0: SIMD2<Double>, _ v: SIMD2<Double>) -> (SIMD2<Double>, SIMD2<Double>) {
        let w0 = naturalFrequency, zeta = dampingRatio
        if abs(zeta - 1) < 0.001 {
            let e = exp(-w0 * dt)
            return ((x0 + (v + w0 * x0) * dt) * e, e * (v - (v * w0 + x0 * (w0 * w0)) * dt))
        }
        let wD = w0 * (1 - zeta * zeta).squareRoot()
        let e = exp(-zeta * w0 * dt), c = cos(wD * dt), s = sin(wD * dt)
        let a = v + zeta * w0 * x0
        let x = e * (x0 * c + (a / wD) * s)
        return (x, e * (a * c - x0 * wD * s) - zeta * w0 * x)
    }

    mutating func tick(_ dt: Double) {
        let (x, v) = solve(dt, toValue - value, displacementVelocity)
        displacementVelocity = v; value = toValue - x
    }

    var hasResolved: Bool {
        let e = Self.resolvingEpsilon, offset = value - toValue
        return abs(offset.x) < e && abs(offset.y) < e
            && abs(displacementVelocity.x) < e && abs(displacementVelocity.y) < e
    }

    func keyframeValues(framerate: Double = 60) -> [SIMD2<Double>] {
        guard all(value, toValue, displacementVelocity) else { return [] }
        var copy = self, values: [SIMD2<Double>] = []
        repeat { copy.tick(1 / framerate); values.append(copy.value) }
        while !copy.hasResolved && values.count < 6_000
        values.append(toValue)
        return values
    }
    private func all(_ vectors: SIMD2<Double>...) -> Bool { vectors.allSatisfy { $0.x.isFinite && $0.y.isFinite } }
}

struct DownloadArrivalFlight {
    static let iconSize: CGFloat = 30
    static let destinationArgument = CGPoint(x: 70, y: 70)
    static let unbinnedDestination = CGPoint(x: 32, y: 40)
    static let gravity = 2648.7000000000003
    static let frameStep = 0.016666666666666666

    let source: CGPoint
    let destination: CGPoint
    let showsBin: Bool
    let initialVerticalVelocity: Double
    let projectileDuration: Double
    let horizontalVelocity: Double
    let apexTime: Double
    let positions: [CGPoint]
    let scales: [CGPoint]
    let duration: Double

    init(source: CGPoint, destination raw: CGPoint, windowSize: CGSize, showsBin: Bool) {
        self.source = source; self.showsBin = showsBin
        let destination = showsBin ? CGPoint(x: raw.x - 8, y: raw.y) : Self.unbinnedDestination
        self.destination = destination
        let g = Self.gravity
        let vy0 = windowSize.height == 0 ? 1600 : Double(source.y) / Double(windowSize.height) * -1100 + 1600
        let dy = Double(destination.y - source.y)
        let discriminant = vy0 * vy0 + dy * -5297.400000000001
        var duration = 0.0
        if discriminant >= 0 {
            let root = discriminant.squareRoot()
            duration = [(root - vy0) / -2648.7000000000003, (-vy0 - root) / -2648.7000000000003]
                .filter { $0 > 0 }.sorted(by: >).first ?? 0
        }
        let vx = Double(destination.x - source.x) / duration
        let apex = vy0 / g
        initialVerticalVelocity = vy0; projectileDuration = duration; horizontalVelocity = vx; apexTime = apex
        let end = duration + (showsBin ? 0 : 0.13333333333333333)
        let coefficient = showsBin ? -0.9000000000000001 : -1.3
        var positions: [CGPoint] = [], scales: [CGPoint] = [], t = 0.0
        while t < end {
            positions.append(CGPoint(x: Double(source.x) + t * vx, y: Double(source.y) + t * vy0 + t * t * -1324.3500000000001))
            if apex <= t {
                let p = duration == apex ? 1 : 1 - (t - apex) / (duration - apex)
                let s = 1.6 - coefficient * (p - 1)
                scales.append(CGPoint(x: s, y: s))
            } else {
                let q = apex == 0 ? 0 : t / apex + 0
                scales.append(CGPoint(x: 0.8 * q + 0.8, y: 0.40000000000000013 * q + 1.2))
            }
            t += Self.frameStep
        }
        if showsBin, let last = scales.last, !positions.isEmpty {
            var bounce = DownloadArrivalSpring()
            bounce.configure(response: 0.48, dampingRatio: 0.72)
            bounce.value = SIMD2(Double(raw.x), Double(raw.y))
            bounce.toValue = SIMD2(Double(destination.x) + 8, Double(destination.y))
            bounce.setVelocity(SIMD2(vx, vy0 + duration * -2648.7000000000003))
            for value in bounce.keyframeValues() {
                positions.append(CGPoint(x: value.x, y: value.y)); scales.append(last); t += Self.frameStep
            }
        }
        self.positions = positions; self.scales = scales; self.duration = t
    }

    var isRenderable: Bool {
        !positions.isEmpty && duration.isFinite && duration > 0
            && positions.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            && scales.allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }
}
