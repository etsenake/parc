import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

private struct Layers {
    let body: CALayer, shimmer: CALayer, host: CALayer, page: CALayer

    init() {
        page = CALayer()
        page.isGeometryFlipped = true
        page.bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        body = CALayer()
        body.bounds = CGRect(x: 0, y: 0, width: 65, height: 96)
        body.anchorPoint = .zero
        body.position = CGPoint(x: 368, y: 200)
        page.addSublayer(body)
        host = CALayer()
        host.frame = page.bounds
        page.addSublayer(host)
        shimmer = CALayer()
    }
}

private let colors = [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
                      CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)]

private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-6) -> Bool { abs(a - b) <= tolerance }
private func near(_ a: CATransform3D, _ b: CATransform3D, _ tolerance: CGFloat = 1e-6) -> Bool {
    [(a.m11, b.m11), (a.m12, b.m12), (a.m21, b.m21), (a.m22, b.m22), (a.m41, b.m41), (a.m42, b.m42),
     (a.m33, b.m33), (a.m44, b.m44)].allSatisfy { near($0.0, $0.1, tolerance) }
}
private func apply(_ t: CATransform3D, _ p: CGPoint) -> CGPoint {
    CGPoint(x: p.x * t.m11 + p.y * t.m21 + t.m41, y: p.x * t.m12 + p.y * t.m22 + t.m42)
}

private func stop(_ layer: CALayer, _ key: String, sourceLocation: SourceLocation = #_sourceLocation) {
    guard let animation = layer.animation(forKey: key) else {
        Issue.record("\(key) is running", sourceLocation: sourceLocation)
        return
    }
    animation.delegate?.animationDidStop?(animation, finished: true)
}

@MainActor private func stage(_ layers: Layers) -> StartPageMarkStage {
    let stage = StartPageMarkStage(body: layers.body, shimmer: layers.shimmer)
    stage.colors = colors
    return stage
}

@MainActor struct TaffyAnimatorTests {
    @MainActor private struct Rig {
        let stage = CALayer()
        let flipped = CALayer()
        let animator = TaffyAnimator()
        let pull = CGVector(dx: 12, dy: 30)

        init() {
            stage.bounds = CGRect(x: 0, y: 0, width: 65, height: 96)
            stage.anchorPoint = .zero
            flipped.isGeometryFlipped = true
            flipped.addSublayer(stage)
        }
    }

    @Test func trackingStretchesInAFlippedSuperlayersDownwardSpace() {
        let rig = Rig()
        rig.animator.track(rig.pull, stage: rig.stage)
        #expect(near(rig.stage.transform, TaffyStretch.transform(pull: rig.pull, size: rig.stage.bounds.size, anchor: .zero, yDown: true)))
    }

    @Test func trackingMirrorsThePullInAnUpwardSuperlayer() {
        let rig = Rig()
        let upright = CALayer()
        upright.addSublayer(rig.stage)
        rig.animator.track(rig.pull, stage: rig.stage)
        #expect(near(rig.stage.transform, TaffyStretch.transform(pull: rig.pull, size: rig.stage.bounds.size, anchor: .zero, yDown: false)))
    }

    @Test func theModelIsHomeWhileTheSpringPlaysFromTheReleasedStretch() {
        let rig = Rig()
        rig.animator.track(rig.pull, stage: rig.stage)
        let stretched = rig.stage.transform
        rig.animator.play(from: rig.pull, stage: rig.stage) {}
        #expect(near(rig.stage.transform, CATransform3DIdentity))
        let values = ((rig.stage.animation(forKey: TaffyAnimator.key) as? CAKeyframeAnimation)?.values as? [NSValue])?.map(\.caTransform3DValue) ?? []
        #expect(values.count == TaffySpring.spring.samples().count)
        #expect(values.first.map { near($0, stretched) } == true && values.last.map { near($0, CATransform3DIdentity) } == true)
    }

    @Test func trackingTakesOverFromAPlayingSpring() {
        let rig = Rig()
        rig.animator.play(from: rig.pull, stage: rig.stage) {}
        rig.animator.track(rig.pull, stage: rig.stage)
        #expect(rig.stage.animation(forKey: TaffyAnimator.key) == nil)
    }

    @Test func resetPutsTheMarkHomeAtOnce() {
        let rig = Rig()
        rig.animator.track(rig.pull, stage: rig.stage)
        rig.animator.reset(stage: rig.stage)
        #expect(rig.stage.animation(forKey: TaffyAnimator.key) == nil && near(rig.stage.transform, CATransform3DIdentity))
    }
}

@MainActor struct StartPageMarkSwoopStageTests {
    private let home = CGPoint(x: 400, y: 248)

    private func started() -> (Layers, StartPageMarkStage, landed: Box, finished: Box) {
        let layers = Layers()
        let stage = stage(layers)
        let landed = Box(), finished = Box()
        stage.swoop(in: layers.host, home: home, pageWidth: 800, landed: { landed.value += 1 }, completion: { finished.value += 1 })
        return (layers, stage, landed, finished)
    }

    private final class Box { var value = 0 }

    @Test func theRibbonLivesInOneEffectsLayerWithOneStripePerThemeColour() {
        let (layers, stage, _, _) = started()
        defer { withExtendedLifetime(stage) {} }
        #expect(layers.host.sublayers?.count == 1)
        let ribbon = layers.host.sublayers?.first
        #expect(ribbon?.sublayers?.count == 3 && ribbon?.sublayers?.allSatisfy { $0 is CAShapeLayer } == true)
        #expect(ribbon?.isGeometryFlipped == !layers.host.contentsAreFlipped())
    }

    @Test func theMarkFliesForTheMockupsDurationUpTheArcInThePagesDownwardSpace() {
        let (layers, stage, _, _) = started()
        defer { withExtendedLifetime(stage) {} }
        let flight = layers.body.animation(forKey: StartPageMarkStage.swoopKey) as? CAKeyframeAnimation
        #expect(flight?.duration == StartPageMarkSwoop.duration)
        let peak = (flight?.values as? [NSValue])?.map(\.caTransform3DValue).map { apply($0, CGPoint(x: 32.5, y: 48)).y }.min() ?? 0
        #expect(near(peak, 48 - 120, 1))
        #expect(StartPageMarkFrame(layer: layers.body).yDown)
    }

    @Test func noLandingTickComesBeforeTheMarkLands() {
        let (_, stage, landed, _) = started()
        defer { withExtendedLifetime(stage) {} }
        #expect(landed.value == 0)
    }

    @Test func theMarkLandsWithASquashAndATick() {
        let (layers, stage, landed, _) = started()
        defer { withExtendedLifetime(stage) {} }
        stop(layers.body, StartPageMarkStage.swoopKey)
        #expect(landed.value == 1 && layers.body.animation(forKey: StartPageMarkStage.landingKey) != nil)
    }

    @Test func theSwoopWaitsForItsRibbonThenRemovesIt() {
        let (layers, stage, _, finished) = started()
        stop(layers.body, StartPageMarkStage.swoopKey)
        stop(layers.body, StartPageMarkStage.landingKey)
        #expect(finished.value == 0)
        if let ribbon = layers.host.sublayers?.first { stop(ribbon, StartPageMarkStage.lifetimeKey) }
        #expect(finished.value == 1 && (layers.host.sublayers ?? []).isEmpty && stage.effects == nil)
    }

    @Test func aSwoopWithoutAnEffectsHostStillFinishes() {
        let bare = StartPageMarkStage(body: Layers().body, shimmer: CALayer())
        var plain = 0
        bare.swoop(in: nil, home: .zero, pageWidth: 800, landed: {}, completion: { plain += 1 })
        stop(bare.body, StartPageMarkStage.swoopKey)
        stop(bare.body, StartPageMarkStage.landingKey)
        #expect(plain == 1)
    }
}

@MainActor struct StartPageMarkChargeStageTests {
    private final class Count { var value = 0 }

    @Test func chargingSquishesTheMarkAndBuzzesOnceFull() {
        let layers = Layers()
        stage(layers).charge(.motion)
        #expect(layers.body.animation(forKey: StartPageMarkStage.holdKey) != nil && layers.body.animation(forKey: StartPageMarkStage.buzzKey) != nil)
        #expect(layers.body.animation(forKey: StartPageMarkStage.holdKey)?.isRemovedOnCompletion == false)
    }

    @Test func chargingGlowsThroughTheThemeColours() {
        let layers = Layers()
        stage(layers).charge(.motion)
        #expect(layers.body.animation(forKey: StartPageMarkStage.glowOpacityKey) != nil
                && layers.body.animation(forKey: StartPageMarkStage.glowColorKey)?.repeatCount == .infinity)
    }

    @Test func theReleaseLetsGoOfTheSquishAndLoopsTheLoop() {
        let layers = Layers()
        let stage = stage(layers)
        stage.charge(.motion)
        stage.loop(in: layers.host, home: CGPoint(x: 400, y: 248), landed: {}, completion: {})
        #expect(layers.body.animation(forKey: StartPageMarkStage.holdKey) == nil && layers.body.animation(forKey: StartPageMarkStage.buzzKey) == nil)
        #expect(layers.body.animation(forKey: StartPageMarkStage.loopKey)?.duration == StartPageMarkCharge.loopDuration)
    }

    @Test func theConfettiIsABoundedSetOfLayers() {
        let layers = Layers()
        let stage = stage(layers)
        stage.charge(.motion)
        stage.loop(in: layers.host, home: CGPoint(x: 400, y: 248), landed: {}, completion: {})
        #expect(layers.host.sublayers?.count == 1 && layers.host.sublayers?.first?.sublayers?.count == StartPageMarkConfetti.count)
    }

    @Test func theGlowStopsCyclingOnceItFades() {
        let layers = Layers()
        let stage = stage(layers)
        stage.charge(.motion)
        stage.loop(in: layers.host, home: CGPoint(x: 400, y: 248), landed: {}, completion: {})
        stop(layers.body, StartPageMarkStage.glowOpacityKey)
        #expect(layers.body.animation(forKey: StartPageMarkStage.glowColorKey) == nil)
    }

    @Test func theLoopLandsWithATickWaitsForItsConfettiThenRemovesIt() {
        let layers = Layers()
        let stage = stage(layers)
        let landed = Count(), finished = Count()
        stage.charge(.motion)
        stage.loop(in: layers.host, home: CGPoint(x: 400, y: 248), landed: { landed.value += 1 }, completion: { finished.value += 1 })
        let confetti = layers.host.sublayers?.first
        stop(layers.body, StartPageMarkStage.loopKey)
        #expect(landed.value == 1)
        stop(layers.body, StartPageMarkStage.landingKey)
        #expect(finished.value == 0)
        if let confetti { stop(confetti, StartPageMarkStage.lifetimeKey) }
        #expect(finished.value == 1 && (layers.host.sublayers ?? []).isEmpty)
    }

    @Test func reduceMotionChargesWithTheGlowAndNoSquish() {
        let quiet = stage(Layers())
        quiet.charge(.shimmer)
        #expect(quiet.body.animation(forKey: StartPageMarkStage.holdKey) == nil
                && quiet.body.animation(forKey: StartPageMarkStage.glowOpacityKey) != nil)
    }

    @Test func anUnderchargedReleaseSpringsBackAndEndsOnceSettled() {
        let relaxing = stage(Layers())
        let relaxed = Count()
        relaxing.charge(.motion)
        relaxing.relax(level: 0.5, style: .motion) { relaxed.value += 1 }
        #expect(relaxing.body.animation(forKey: StartPageMarkStage.relaxKey) != nil && relaxing.body.animation(forKey: StartPageMarkStage.holdKey) == nil)
        stop(relaxing.body, StartPageMarkStage.relaxKey)
        #expect(relaxed.value == 0)
        stop(relaxing.body, StartPageMarkStage.glowOpacityKey)
        #expect(relaxed.value == 1 && relaxing.body.animation(forKey: StartPageMarkStage.glowColorKey) == nil)
    }
}

@MainActor struct StartPageMarkPauseCleanupTests {
    private final class Count { var value = 0 }

    @Test func pausingRemovesTheRibbonAndSendsTheMarkHomeAtOnce() {
        let layers = Layers()
        let stage = stage(layers)
        stage.swoop(in: layers.host, home: CGPoint(x: 400, y: 248), pageWidth: 800, landed: {}, completion: {})
        stage.reset()
        #expect((layers.host.sublayers ?? []).isEmpty && stage.effects == nil)
        #expect(StartPageMarkStage.bodyKeys.allSatisfy { layers.body.animation(forKey: $0) == nil } && near(layers.body.transform, CATransform3DIdentity))
    }

    @Test func aPausedSwoopNeverLandsOrTicksAfterwards() {
        let layers = Layers()
        let stage = stage(layers)
        let landed = Count(), finished = Count()
        stage.swoop(in: layers.host, home: CGPoint(x: 400, y: 248), pageWidth: 800,
                    landed: { landed.value += 1 }, completion: { finished.value += 1 })
        let ribbon = layers.host.sublayers?.first
        let flight = layers.body.animation(forKey: StartPageMarkStage.swoopKey)
        stage.reset()
        if let flight { flight.delegate?.animationDidStop?(flight, finished: false) }
        if let lifetime = ribbon?.animation(forKey: StartPageMarkStage.lifetimeKey) { lifetime.delegate?.animationDidStop?(lifetime, finished: false) }
        #expect(landed.value == 0 && finished.value == 0 && layers.body.animation(forKey: StartPageMarkStage.landingKey) == nil)
    }

    @Test func thereIsOneEffectsLayerAtATimeAndPausingRemovesTheConfettiAndPutsOutTheGlow() {
        let layers = Layers()
        let stage = stage(layers)
        stage.charge(.motion)
        stage.loop(in: layers.host, home: .zero, landed: {}, completion: {})
        #expect(layers.host.sublayers?.count == 1)
        stage.reset()
        #expect((layers.host.sublayers ?? []).isEmpty)
        #expect(layers.body.shadowOpacity == 0 && layers.body.animation(forKey: StartPageMarkStage.glowColorKey) == nil)
    }

    @Test func noColoursNoRibbonLayer() {
        let layers = Layers()
        let stage = stage(layers)
        stage.colors = []
        stage.swoop(in: layers.host, home: .zero, pageWidth: 800, landed: {}, completion: {})
        #expect((layers.host.sublayers ?? []).isEmpty)
    }
}

@MainActor struct StartPageMarkShimmerTests {
    private let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    @Test func theShimmerFadesInThroughTheThemeColoursAndOutAgain() {
        let sequence = StartPageMarkShimmer.sequence([red, blue])
        #expect(sequence.map(\.alpha) == [0, StartPageMarkShimmer.peakAlpha, StartPageMarkShimmer.peakAlpha, 0])
    }

    @Test func noColoursNoShimmerAndItFinishesAtOnce() {
        #expect(StartPageMarkShimmer.sequence([]).isEmpty)
        var finished = false
        let layer = CALayer()
        StartPageMarkShimmer.play(on: layer, colors: []) { finished = true }
        #expect(finished && layer.animation(forKey: StartPageMarkShimmer.key) == nil)
    }

    @Test func theShimmerChangesColourInPlaceWithoutMovingTheMarkOrLeavingAColourBehind() {
        let layer = CALayer()
        StartPageMarkShimmer.play(on: layer, colors: StartPageMarkShimmer.sequence([red, blue])) {}
        let animation = layer.animation(forKey: StartPageMarkShimmer.key) as? CAKeyframeAnimation
        #expect(animation?.keyPath == "backgroundColor" && animation?.values?.count == 4)
        #expect(layer.backgroundColor == nil)
    }

    @Test func resetStopsTheShimmer() {
        let layer = CALayer()
        StartPageMarkShimmer.play(on: layer, colors: StartPageMarkShimmer.sequence([red, blue])) {}
        StartPageMarkShimmer.reset(layer)
        #expect(layer.animation(forKey: StartPageMarkShimmer.key) == nil)
    }
}

struct StartPageMarkFillTests {
    @Test(arguments: [false, true], [false, true])
    func theColourMarkIsItsOwnArtwork(incognito: Bool, colored: Bool) {
        #expect(StartPageMarkFill(colorMark: true, themeHasColor: colored, incognito: incognito) == .art)
    }

    @Test func aColouredThemeFillsTheMarkAndAColourlessOneInksIt() {
        #expect(StartPageMarkFill(colorMark: false, themeHasColor: true, incognito: false) == .theme)
        #expect(StartPageMarkFill(colorMark: false, themeHasColor: false, incognito: false) == .ink)
    }

    @Test func aPrivateWindowInksTheMark() {
        #expect(StartPageMarkFill(colorMark: false, themeHasColor: true, incognito: true) == .ink)
    }

    @Test func aSwipeTowardAColouredSpaceShowsItsGradientOnTheMark() {
        #expect(StartPageMarkFill(colorMark: false, themeHasColor: false, pagingHasColor: (false, true), incognito: false) == .theme)
    }

    @Test func aSwipeBetweenColourlessSpacesInksTheMark() {
        #expect(StartPageMarkFill(colorMark: false, themeHasColor: true, pagingHasColor: (false, false), incognito: false) == .ink)
    }

    @Test func aPrivateWindowIgnoresSwipes() {
        #expect(StartPageMarkFill(colorMark: false, themeHasColor: true, pagingHasColor: (true, true), incognito: true) == .ink)
    }
}

struct StartPageMarkTintTests {
    private let tint = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25), label = CGColor(gray: 0.5, alpha: 1)

    private func components(_ color: CGColor) -> [CGFloat] {
        color.converted(to: CGColorSpace(name: CGColorSpace.extendedSRGB)!, intent: .defaultIntent, options: nil)?.components ?? []
    }

    private func matches(_ a: [CGFloat], _ b: [CGFloat]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 1e-4 } }

    @Test func theTintStartsAtTheOutgoingSpace() {
        #expect(matches(components(StartPageMarkTint.blend(tint, label, progress: 0)), components(tint)))
    }

    @Test func theTintEndsAtTheIncomingSpace() {
        #expect(matches(components(StartPageMarkTint.blend(tint, label, progress: 1)), components(label)))
    }

    @Test func theTintBlendsThroughTheSwipe() {
        let half = components(StartPageMarkTint.blend(tint, label, progress: 0.5))
        #expect(abs(half[3] - 0.625) < 1e-4 && abs(half[0] - components(label)[0] / 2) < 1e-4)
    }

    @Test func anOvershootingSwipeHoldsTheIncomingTint() {
        #expect(matches(components(StartPageMarkTint.blend(tint, label, progress: 3)), components(label)))
    }
}
