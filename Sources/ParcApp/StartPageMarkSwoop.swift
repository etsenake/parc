import QuartzCore

enum StartPageMarkSwoop {
    static let duration = 1.15
    static let reachRatio: CGFloat = 1.45
    static let maximumReach: CGFloat = 1100
    static let lift: CGFloat = 160
    static let stretch: CGFloat = 1.06
    static let ribbonWidth: CGFloat = 18
    static let ribbonLife = 0.42
    static let ribbonAlpha: CGFloat = 0.9
    static let ribbonTailTaper = 0.1
    static let ribbonMinimumStripe: CGFloat = 0.5
    static let ribbonStripeBleed: CGFloat = 0.6
    static let ribbonPoints = 24
    static let ribbonSearchSteps = 48
    static let maximumStripes = 3

    static var ribbonDuration: Double { duration + ribbonLife }

    static func reach(pageWidth: CGFloat) -> CGFloat { min(reachRatio * max(0, pageWidth), maximumReach) }

    static func progress(at time: Double) -> CGFloat { StartPageMarkEasing.inOutSine(CGFloat(time / duration)) }

    static func offset(progress p: CGFloat, reach: CGFloat) -> CGVector {
        let q = 1 - p
        return CGVector(dx: 3 * q * p * (q - p) * reach, dy: -3 * q * p * lift)
    }

    static func tangent(progress p: CGFloat, reach: CGFloat) -> CGVector {
        CGVector(dx: 3 * reach * (1 - 6 * p + 6 * p * p), dy: -3 * lift * (1 - 2 * p))
    }

    static func pose(at time: Double, reach: CGFloat) -> StartPageMarkPose {
        StartPageMarkPose(offset: offset(progress: progress(at: time), reach: reach),
                          rotation: 2 * .pi * StartPageMarkEasing.inOutCubic(CGFloat(time / duration)),
                          scale: CGSize(width: 1, height: stretch))
    }

    static func flight(reach: CGFloat) -> (poses: [StartPageMarkPose], times: [Double]) {
        let times = StartPageMarkSampling.times(duration: duration)
        return (times.map { pose(at: $0, reach: reach) }, times)
    }

    static func covers(_ point: CGPoint, home: CGPoint, mark: CGSize, pose: StartPageMarkPose) -> Bool {
        let dx = point.x - home.x - pose.offset.dx, dy = point.y - home.y - pose.offset.dy
        let cosine = cos(pose.rotation), sine = sin(pose.rotation)
        let x = dx * cosine + dy * sine, y = -dx * sine + dy * cosine
        return abs(x) <= mark.width * pose.scale.width / 2 && abs(y) <= mark.height * pose.scale.height / 2
    }

    static func ribbon(at time: Double, home: CGPoint, reach: CGFloat, mark: CGSize, width: CGFloat, stripes: Int) -> [CGPath] {
        let count = max(1, min(maximumStripes, stripes))
        let oldest = max(0, time - ribbonLife), newest = min(time, duration)
        func point(_ emitted: Double) -> CGPoint {
            let offset = offset(progress: progress(at: emitted), reach: reach)
            return CGPoint(x: home.x + offset.dx, y: home.y + offset.dy)
        }
        let markPose = time < duration ? pose(at: time, reach: reach) : .identity
        let head = newest > oldest ? (0...ribbonSearchSteps).lazy
            .map { newest - (newest - oldest) * Double($0) / Double(ribbonSearchSteps) }
            .first { !covers(point($0), home: home, mark: mark, pose: markPose) } : nil
        guard let head, head > oldest else {
            let rest = point(newest)
            let empty = CGMutablePath()
            empty.addLines(between: Array(repeating: rest, count: 2 * ribbonPoints))
            empty.closeSubpath()
            return Array(repeating: empty, count: count)
        }
        let samples = (0..<ribbonPoints).map { index -> (point: CGPoint, normal: CGVector, width: CGFloat) in
            let emitted = oldest + (head - oldest) * Double(index) / Double(ribbonPoints - 1)
            let direction = tangent(progress: progress(at: emitted), reach: reach)
            let length = max(hypot(direction.dx, direction.dy), 1e-6)
            let age = CGFloat((time - emitted) / ribbonLife)
            let tail = min(1, max(0.25, CGFloat((emitted - oldest) / ribbonTailTaper)))
            return (point(emitted), CGVector(dx: -direction.dy / length, dy: direction.dx / length),
                    width * max(0, 1 - age) * tail)
        }
        return (0..<count).map { stripe in
            let edges = samples.map { sample -> (CGPoint, CGPoint) in
                let center = (CGFloat(stripe) - CGFloat(count - 1) / 2) * sample.width / CGFloat(count)
                let half = max(ribbonMinimumStripe, sample.width / CGFloat(count) + ribbonStripeBleed) / 2
                func edge(_ distance: CGFloat) -> CGPoint {
                    CGPoint(x: sample.point.x + sample.normal.dx * distance, y: sample.point.y + sample.normal.dy * distance)
                }
                return (edge(center - half), edge(center + half))
            }
            let path = CGMutablePath()
            path.addLines(between: edges.map(\.0) + edges.reversed().map(\.1))
            path.closeSubpath()
            return path
        }
    }
}
