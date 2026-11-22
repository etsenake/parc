import CoreGraphics
import Foundation
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-6) -> Bool { abs(a - b) <= tolerance }
private func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 1e-6) -> Bool {
    near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance)
}
private func near(_ a: CATransform3D, _ b: CATransform3D, _ tolerance: CGFloat = 1e-6) -> Bool {
    [(a.m11, b.m11), (a.m12, b.m12), (a.m21, b.m21), (a.m22, b.m22), (a.m41, b.m41), (a.m42, b.m42),
     (a.m33, b.m33), (a.m44, b.m44)].allSatisfy { near($0.0, $0.1, tolerance) }
}
private func apply(_ t: CATransform3D, _ p: CGPoint) -> CGPoint {
    CGPoint(x: p.x * t.m11 + p.y * t.m21 + t.m41, y: p.x * t.m12 + p.y * t.m22 + t.m42)
}

struct StartPageMarkPoseTests {
    private let size = CGSize(width: 65, height: 96)
    private var down: StartPageMarkFrame { StartPageMarkFrame(size: size, anchor: .zero, yDown: true) }
    private var up: StartPageMarkFrame { StartPageMarkFrame(size: size, anchor: .zero, yDown: false) }
    private let squash = StartPageMarkPose(scale: CGSize(width: 1.2, height: 0.7), origin: StartPageMarkPose.bottom)

    @Test func theRestingPoseIsTheIdentityInEitherSpace() {
        #expect(near(StartPageMarkPose.identity.transform(in: down), CATransform3DIdentity))
        #expect(near(StartPageMarkPose.identity.transform(in: up), CATransform3DIdentity))
    }

    @Test func aSquashKeepsTheBaseInPlaceAndLowersTheTop() {
        let transform = squash.transform(in: down)
        #expect(near(apply(transform, CGPoint(x: 32.5, y: 96)), CGPoint(x: 32.5, y: 96)))
        #expect(near(apply(transform, CGPoint(x: 32.5, y: 0)).y, 96 * 0.3))
    }

    @Test func anUpwardSpaceKeepsTheBaseAtItsBottom() {
        let transform = squash.transform(in: up)
        #expect(near(apply(transform, CGPoint(x: 32.5, y: 0)), CGPoint(x: 32.5, y: 0)))
        #expect(near(apply(transform, CGPoint(x: 32.5, y: 96)).y, 96 * 0.7))
    }

    @Test func aPositiveRotationTurnsClockwiseOnScreen() {
        let turn = StartPageMarkPose(rotation: .pi / 2).transform(in: down)
        #expect(near(apply(turn, CGPoint(x: 65, y: 48)), CGPoint(x: 32.5, y: 48 + 32.5)))
    }

    @Test func anUpwardLayerSpaceMirrorsThePose() {
        let turn = StartPageMarkPose(rotation: .pi / 2).transform(in: up)
        #expect(near(apply(turn, CGPoint(x: 65, y: 48)), CGPoint(x: 32.5, y: 48 - 32.5)))
    }

    @Test func theOffsetMovesTheMarkUpOnScreenInEitherSpace() {
        let moved = StartPageMarkPose(offset: CGVector(dx: 10, dy: -20))
        #expect(near(apply(moved.transform(in: down), .zero), CGPoint(x: 10, y: -20)))
        #expect(near(apply(moved.transform(in: up), .zero), CGPoint(x: 10, y: 20)))
    }

    @Test func aCentredAnchorKeepsTheBaseInPlace() {
        let centred = StartPageMarkFrame(size: size, anchor: CGPoint(x: 0.5, y: 0.5), yDown: true)
        #expect(near(apply(squash.transform(in: centred), CGPoint(x: 0, y: 48)), CGPoint(x: 0, y: 48)))
    }

    @Test func markRelativeMotionScalesFromTheMockupsMark() {
        #expect(near(down.scale, 96 / 65))
    }
}

struct TaffyStretchTests {
    private let size = CGSize(width: 65, height: 96)

    @Test func noPullNoStretch() {
        #expect(TaffyStretch.elongation(0) == 0)
    }

    @Test func theStretchStartsAtTheRubberBandsResistance() {
        #expect(near(TaffyStretch.elongation(0.001) / 0.001, TaffyStretch.resistance, 1e-3))
    }

    @Test(arguments: stride(from: CGFloat(5), through: 2000, by: 5))
    func theStretchGrowsWithThePullAndNeverPassesItsReach(distance: CGFloat) {
        let value = TaffyStretch.elongation(distance)
        #expect(value > TaffyStretch.elongation(distance - 5) && value < TaffyStretch.reach)
    }

    @Test func aZeroPullLeavesTheMarkUntouched() {
        #expect(near(TaffyStretch.transform(pull: .zero, size: size, anchor: .zero, yDown: true), CATransform3DIdentity))
    }

    @Test func theFarEdgeFollowsThePointerAndTheNearEdgeStaysPut() {
        let right = TaffyStretch.transform(pull: CGVector(dx: 30, dy: 0), size: size, anchor: .zero, yDown: true)
        let e = TaffyStretch.elongation(30)
        #expect(near(apply(right, CGPoint(x: 65, y: 48)), CGPoint(x: 65 + e, y: 48)))
        #expect(near(apply(right, CGPoint(x: 0, y: 48)), CGPoint(x: 0, y: 48)))
    }

    @Test func theMarkThinsAcrossThePullAndKeepsItsVolume() {
        let right = TaffyStretch.transform(pull: CGVector(dx: 30, dy: 0), size: size, anchor: .zero, yDown: true)
        let e = TaffyStretch.elongation(30)
        let along = 1 + e / size.width, across = 1 / along.squareRoot()
        #expect(near(apply(right, CGPoint(x: 32.5, y: 0)).y, 48 * (1 - across)))
        #expect(near(right.m11 * right.m22 - right.m12 * right.m21, along * across))
    }

    @Test func anUpwardLayerSpaceMirrorsThePointersVerticalDirection() {
        #expect(near(TaffyStretch.transform(pull: CGVector(dx: 20, dy: 20), size: size, anchor: .zero, yDown: false),
                     TaffyStretch.transform(pull: CGVector(dx: 20, dy: -20), size: size, anchor: .zero, yDown: true)))
    }

    @Test func overshootSquashesTheMarkTheOtherWay() {
        let right = TaffyStretch.transform(pull: CGVector(dx: 30, dy: 0), size: size, anchor: .zero, yDown: true)
        let squash = TaffyStretch.blend(right, -0.3)
        #expect(squash.m11 < 1 && squash.m22 > 1 && apply(squash, CGPoint(x: 65, y: 48)).x < 65)
    }
}

struct StartPageMarkSpringTests {
    @Test func stiffnessAndDampingFollowTheSidebarSpringHelpers() {
        let spring = TaffySpring.spring
        #expect(near(CGFloat(spring.stiffness), pow(2 * .pi / TaffySpring.response, 2)))
        #expect(near(CGFloat(spring.damping), 4 * .pi * TaffySpring.dampingRatio / TaffySpring.response))
        #expect(near(CGFloat(spring.displacement(at: 0)), 1))
    }

    @Test(arguments: [0.05, 0.1, 0.2, 0.4])
    func theClosedFormMatchesEachSpringsMotion(target: Double) {
        for candidate in [TaffySpring.spring, StartPageMarkLanding.spring, StartPageMarkCharge.relaxSpring(level: 1)] {
            var x = 1.0, v = 0.0, t = 0.0
            let h = 1e-5
            while t < target - h / 2 {
                v += (-candidate.stiffness * x - candidate.damping * v) * h
                x += v * h
                t += h
            }
            #expect(abs(x - candidate.displacement(at: t)) < 1e-3)
        }
    }

    @Test func theSamplesRunFromTheStretchToHomeWobblingPastIt() {
        let samples = TaffySpring.spring.samples()
        #expect(samples.first == 1 && samples.last == 0)
        #expect((samples.min() ?? 0) < -0.2)
    }

    @Test func theSnapHomeIsShort() {
        let samples = TaffySpring.spring.samples()
        let duration = Double(samples.count - 1) / StartPageMarkSpring.sampleRate
        #expect(duration > 0.6 && duration < 1.2)
    }

    @Test func theLandingStartsSquashedOntoItsBaseAndBouncesPastHome() {
        let landing = StartPageMarkLanding.poses()
        #expect(near(landing[0].scale.height, 1 - StartPageMarkLanding.squash)
                && near(landing[0].scale.width, 1 + 0.8 * StartPageMarkLanding.squash))
        #expect(landing.last == StartPageMarkLanding.pose(0) && landing.allSatisfy { $0.origin == StartPageMarkPose.bottom })
        #expect(landing.contains { $0.scale.height > 1.05 })
    }

    @Test func theLandingSettlesInUnderASecond() {
        #expect(StartPageMarkLanding.duration > 0.6 && StartPageMarkLanding.duration < 1)
    }
}

struct StartPageMarkSwoopTests {
    private let reach: CGFloat = 870

    @Test func theReachFollowsThePageUpToTheMockupsCap() {
        #expect(near(StartPageMarkSwoop.reach(pageWidth: 600), 870, 1e-9) && StartPageMarkSwoop.reach(pageWidth: 2000) == 1100)
    }

    @Test func theSwoopLeavesAndLandsAtHome() {
        #expect(StartPageMarkSwoop.offset(progress: 0, reach: reach) == CGVector(dx: 0, dy: 0))
        #expect(StartPageMarkSwoop.offset(progress: 1, reach: reach) == CGVector(dx: 0, dy: 0))
    }

    @Test func theArcPeaks120PointsAboveHome() {
        let top = StartPageMarkSwoop.offset(progress: 0.5, reach: reach)
        #expect(near(top.dx, 0) && near(top.dy, -120))
    }

    @Test func theArcNeverDipsBelowHomeAndSweepsAcrossThePageOnBothSides() {
        let samples = stride(from: CGFloat(0), through: 1, by: 0.01).map { StartPageMarkSwoop.offset(progress: $0, reach: reach) }
        #expect(samples.allSatisfy { $0.dy <= 0 })
        #expect(near(samples.map(\.dx).max() ?? 0, 0.2887 * reach, 1) && near(samples.map(\.dx).min() ?? 0, -0.2887 * reach, 1))
    }

    @Test func theMarkTurnsOnceOnTheWayAndStretchesSlightly() {
        let first = StartPageMarkSwoop.pose(at: 0, reach: reach), last = StartPageMarkSwoop.pose(at: StartPageMarkSwoop.duration, reach: reach)
        #expect(near(first.rotation, 0) && near(last.rotation, 2 * .pi))
        #expect(first.scale == CGSize(width: 1, height: StartPageMarkSwoop.stretch))
    }

    @Test func theFlightIsSampledAcrossItsDuration() {
        let flight = StartPageMarkSwoop.flight(reach: reach)
        #expect(flight.times.first == 0 && flight.times.last == StartPageMarkSwoop.duration && flight.poses.count == flight.times.count)
    }

    @Test func theRibbonFollowsTheArcsDirection() {
        let p = StartPageMarkSwoop.progress(at: 0.3), h: CGFloat = 1e-4
        let a = StartPageMarkSwoop.offset(progress: p - h, reach: reach), b = StartPageMarkSwoop.offset(progress: p + h, reach: reach)
        let tangent = StartPageMarkSwoop.tangent(progress: p, reach: reach)
        #expect(near((b.dx - a.dx) / (2 * h), tangent.dx, 1e-2) && near((b.dy - a.dy) / (2 * h), tangent.dy, 1e-2))
    }
}

struct StartPageMarkRibbonTests {
    private let home = CGPoint(x: 400, y: 300), mark = CGSize(width: 65, height: 96), reach: CGFloat = 870

    private func points(_ path: CGPath) -> [CGPoint] {
        var result: [CGPoint] = []
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint { result.append(element.pointee.points[0]) }
        }
        return result
    }

    private func ribbon(at time: TimeInterval, stripes: Int = 3) -> [CGPath] {
        StartPageMarkSwoop.ribbon(at: time, home: home, reach: reach, mark: mark, width: 26, stripes: stripes)
    }

    @Test func thereIsNoRibbonBeforeTheMarkLeaves() {
        let start = ribbon(at: 0)
        #expect(start.count == 3 && start.allSatisfy { points($0).allSatisfy { $0 == home } })
    }

    @Test func everyRibbonFrameHasTheSameShapeForSmoothAnimation() {
        let counts = Set((ribbon(at: 0) + ribbon(at: 0.5)).map { points($0).count })
        #expect(counts == [2 * StartPageMarkSwoop.ribbonPoints])
    }

    @Test func theRibbonStartsBehindTheMark() {
        let n = StartPageMarkSwoop.ribbonPoints
        let center = points(ribbon(at: 0.5)[1])
        let pose = StartPageMarkSwoop.pose(at: 0.5, reach: reach)
        let spine = (0..<n).map { CGPoint(x: (center[$0].x + center[2 * n - 1 - $0].x) / 2, y: (center[$0].y + center[2 * n - 1 - $0].y) / 2) }
        #expect(spine.allSatisfy { !StartPageMarkSwoop.covers($0, home: home, mark: mark, pose: pose) })
    }

    @Test func theRibbonTapersTowardItsTail() {
        let n = StartPageMarkSwoop.ribbonPoints
        let center = points(ribbon(at: 0.5)[1])
        let widths = (0..<n).map { hypot(center[$0].x - center[2 * n - 1 - $0].x, center[$0].y - center[2 * n - 1 - $0].y) }
        #expect(widths.last! > widths.first! && widths.first! < 1)
    }

    @Test func theSpacesColoursRunSideBySideAlongTheRibbon() {
        let n = StartPageMarkSwoop.ribbonPoints
        let middle = ribbon(at: 0.5)
        let center = points(middle[1])
        let widths = (0..<n).map { hypot(center[$0].x - center[2 * n - 1 - $0].x, center[$0].y - center[2 * n - 1 - $0].y) }
        let outer = points(middle[0]), inner = points(middle[2])
        #expect(hypot(outer[n - 1].x - inner[n - 1].x, outer[n - 1].y - inner[n - 1].y) > widths.last!)
    }

    @Test func theRibbonHasAtMostThreeStripes() {
        #expect(ribbon(at: 0.5, stripes: 9).count == StartPageMarkSwoop.maximumStripes)
    }

    @Test func theRibbonIsGoneOnceItsTailLands() {
        let end = ribbon(at: StartPageMarkSwoop.ribbonDuration, stripes: 1)
        #expect(points(end[0]).allSatisfy { near($0, home) })
    }
}

struct StartPageMarkChargeMathTests {
    private let radius: CGFloat = 52

    @Test func theChargeFillsOverTheRampAndStaysFull() {
        #expect(StartPageMarkCharge.level(held: 0) == 0 && StartPageMarkCharge.level(held: StartPageMarkCharge.ramp) == 1
                && StartPageMarkCharge.level(held: 5) == 1)
    }

    @Test func theChargeIsFullOneSecondAfterThePress() {
        #expect(near(StartPageMarkGestureRecognizer.holdDelay + StartPageMarkCharge.ramp, 1.0))
    }

    @Test func aFullChargeSquishesTheMarkOntoItsBase() {
        let full = StartPageMarkCharge.holdPose(level: 1)
        #expect(full.origin == StartPageMarkPose.bottom && near(full.scale.height, 1 - StartPageMarkCharge.squish)
                && near(full.scale.width, 1 + StartPageMarkCharge.spread))
        #expect(StartPageMarkCharge.holdPose(level: 0) == StartPageMarkPose(origin: StartPageMarkPose.bottom))
    }

    @Test func noChargeNoGlowAndAFullChargeGlowsAtTheMockupsStrength() {
        #expect(StartPageMarkCharge.glow(0, scale: 1) == (0, 0))
        let glow = StartPageMarkCharge.glow(1, scale: 1)
        #expect(near(glow.radius, 8.5) && near(CGFloat(glow.opacity), 0.9))
    }

    @Test func theReleaseLaunchesWithAStretch() {
        let launch = StartPageMarkCharge.loopPose(at: 0, radius: radius)
        #expect(launch.offset == CGVector(dx: 0, dy: 0) && near(launch.scale.width, 0.9) && near(launch.scale.height, 1.16))
    }

    @Test func theLoopReachesItsTopUpsideDownAndClimbsToTheRightFirst() {
        let top = StartPageMarkCharge.loopPose(at: StartPageMarkCharge.loopDuration / 2, radius: radius)
        #expect(near(top.offset.dy, -2 * radius) && near(top.offset.dx, 0, 1e-4) && near(top.rotation, -.pi))
        let quarter = StartPageMarkCharge.loopPose(at: StartPageMarkCharge.loopDuration * 0.32, radius: radius)
        #expect(quarter.offset.dx > 0 && quarter.offset.dy < 0)
    }

    @Test func theLoopComesHomeAfterOneFullTurn() {
        let end = StartPageMarkCharge.loopPose(at: StartPageMarkCharge.loopDuration, radius: radius)
        #expect(near(end.offset.dx, 0, 1e-4) && near(end.offset.dy, 0, 1e-4) && near(end.rotation, -2 * .pi)
                && end.scale == CGSize(width: 1, height: 1))
    }

    @Test func theGlowFadesDuringTheLoopAndARelax() {
        #expect(StartPageMarkCharge.loopGlow(at: 0) == 1 && StartPageMarkCharge.loopGlow(at: StartPageMarkCharge.loopGlowFade) == 0)
        #expect(near(CGFloat(StartPageMarkCharge.relaxGlow(at: 0, level: 1)), 1)
                && StartPageMarkCharge.relaxGlow(at: StartPageMarkCharge.relaxGlowDuration, level: 1) == 0)
    }

    @Test func aRelaxStartsFromTheHeldSquish() {
        #expect(StartPageMarkCharge.relaxPose(StartPageMarkCharge.relaxSquish(level: 1)).scale.height == 1 - StartPageMarkCharge.squish)
    }
}

struct StartPageMarkConfettiTests {
    private func pieces(colors: Int = 3) -> [StartPageMarkConfettiPiece] {
        var generator = SeededGenerator(state: 7)
        return StartPageMarkConfetti.pieces(colors: colors, using: &generator)
    }

    private let piece = StartPageMarkConfettiPiece(velocity: CGVector(dx: 200, dy: -500), rotation: 0, spin: 4,
                                                   size: CGSize(width: 6, height: 4), life: 2, color: 0)

    @Test func theBurstThrowsTheMockupsNinetyPieces() {
        #expect(pieces().count == StartPageMarkConfetti.count)
    }

    @Test func thePiecesTakeTurnsThroughTheThemeColours() {
        #expect(pieces().enumerated().allSatisfy { $0.element.color == $0.offset % 3 })
    }

    @Test func theBurstFansUpward() {
        #expect(pieces().allSatisfy {
            let speed = hypot($0.velocity.dx, $0.velocity.dy)
            let angle = atan2($0.velocity.dy, $0.velocity.dx) * 180 / .pi
            return speed >= 240 - 1e-6 && speed <= 600 + 1e-6 && angle >= -170 - 1e-6 && angle <= -10 + 1e-6
        })
    }

    @Test func eachPieceHasABoundedSizeAndLife() {
        #expect(pieces().allSatisfy { StartPageMarkConfetti.lives.contains($0.life) && StartPageMarkConfetti.widths.contains($0.size.width) })
    }

    @Test func noColoursNoConfetti() {
        #expect(pieces(colors: 0).isEmpty)
    }

    @Test func confettiFollowsTheMockupsDragAndGravity() {
        var x: CGFloat = 0, y: CGFloat = 0, vx: CGFloat = 200, vy: CGFloat = -500, t = 0.0
        let h = 1e-4
        while t < 1 - h / 2 {
            vx *= CGFloat(pow(0.35, h))
            vy = vy * CGFloat(pow(0.35, h)) + 900 * CGFloat(h)
            x += vx * CGFloat(h)
            y += vy * CGFloat(h)
            t += h
        }
        let closed = piece.offset(at: 1)
        #expect(near(closed.dx, x, 0.5) && near(closed.dy, y, 0.5))
        #expect(piece.offset(at: 2).dy > piece.offset(at: 0.5).dy)
    }

    @Test func confettiFadesOverItsLastThirtyPercent() {
        #expect(piece.opacity(at: 1.3) == 1 && near(CGFloat(piece.opacity(at: 1.7)), 0.5) && piece.opacity(at: 2) == 0)
    }

    @Test func confettiFlutters() {
        #expect(piece.flutter(at: 0) == (4 + 0.6) / 4 && near(CGFloat(piece.flutter(at: .pi / 2 / 1.7 / 4)), 0.6 / 4))
    }

    @Test func eachPieceAnimatesOnceForItsLife() {
        let group = StartPageMarkConfetti.animation(for: piece, from: CGPoint(x: 10, y: 10))
        #expect(group.duration == 2 && group.animations?.count == 3)
    }
}
