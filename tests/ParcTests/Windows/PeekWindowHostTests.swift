import AppKit
import QuartzCore
import Testing
@testable import Parc

struct PeekWindowHostTests {
    private static let window = CGRect(x: 0, y: 0, width: 1280, height: 800)
    private static let sidebarWidth: CGFloat = 228

    private static func page(thickness t: CGFloat, docked: Bool = true) -> CGRect {
        let left = docked ? sidebarWidth : t
        return CGRect(x: left, y: t, width: window.width - left - t, height: window.height - 2 * t)
    }

    private static func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

    struct Frame: Sendable, CustomTestStringConvertible {
        let thickness: CGFloat
        let docked: Bool
        var testDescription: String { "frame \(thickness), docked \(docked)" }
        static let all = [CGFloat(3), 10, 13].flatMap { t in [true, false].map { Frame(thickness: t, docked: $0) } }
        var page: CGRect { PeekWindowHostTests.page(thickness: thickness, docked: docked) }
        var card: CGRect { PeekWindowLayout(bounds: PeekWindowHostTests.window, page: page, stepsBack: true).card }
    }

    @Test(arguments: Frame.all)
    func theCardSitsTwelvePointsFromTheWindowsTopAndBottom(_ f: Frame) {
        #expect(f.card.minY == 12)
        #expect(f.card.maxY == Self.window.maxY - 12)
    }

    @Test(arguments: Frame.all)
    func theCardKeepsEightyPercentOfThePageWidth(_ f: Frame) {
        #expect(f.card.width == (f.page.width * 0.8).rounded(.down))
    }

    @Test(arguments: Frame.all)
    func theCardStaysCentredOnThePage(_ f: Frame) {
        #expect(abs(f.card.midX - f.page.midX) <= 1)
    }

    @Test func withTheClassicFrameTheCardMovesTenPointsCloserToEachWindowEdge() {
        let classic = Self.page(thickness: 10)
        let today = classic.minY + 12
        #expect(today - PeekWindowLayout(bounds: Self.window, page: classic, stepsBack: true).card.minY == 10)
    }

    private static let tight = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func aNarrowPageKeepsRoomForTheRoundControls() {
        let narrow = PeekWindowLayout(bounds: Self.tight, page: Self.tight, stepsBack: true)
        #expect(narrow.card.minX >= PeekWindowLayout.controlGap + PeekWindowLayout.controlSize)
    }

    @Test func theControlsSitThirteenPointsRightOfTheCardAndSevenBelowItsTop() {
        let narrow = PeekWindowLayout(bounds: Self.tight, page: Self.tight, stepsBack: true)
        let controls = narrow.controls(closeWidth: PeekWindowLayout.controlSize)
        #expect(controls.minX == narrow.card.maxX + 13)
        #expect(controls.minY == narrow.card.minY + 7)
    }

    @Test func aWidenedCloseStaysInsideThePageClearOfTheSplitGrip() {
        let classic = Self.page(thickness: 10)
        let wide = PeekWindowLayout(bounds: Self.window, page: classic, stepsBack: true).controls(closeWidth: 400)
        #expect(wide.maxX <= classic.maxX - 4)
    }

    private static func stepped(_ t: CGFloat) -> (page: CGRect, layout: PeekWindowLayout, stepped: CGRect) {
        let page = page(thickness: t)
        let layout = PeekWindowLayout(bounds: window, page: page, stepsBack: true)
        return (page, layout, layout.steppedPage())
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func thePageStepsBackNinePointsAtEachSide(_ t: CGFloat) {
        let s = Self.stepped(t)
        #expect(Self.close(s.stepped.minX - s.page.minX, 9))
        #expect(Self.close(s.page.maxX - s.stepped.maxX, 9))
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func theStepIsAnEvenScaleALittleLessTopAndBottom(_ t: CGFloat) {
        let s = Self.stepped(t)
        let vertical = s.stepped.minY - s.page.minY
        #expect(Self.close(vertical, 9 * s.page.height / s.page.width))
        #expect(vertical > 6 && vertical < 9)
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func thePageShrinksAboutItsCentre(_ t: CGFloat) {
        let s = Self.stepped(t)
        #expect(Self.close(s.stepped.midX, s.page.midX))
        #expect(Self.close(s.stepped.midY, s.page.midY))
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func noProgressMeansNoStep(_ t: CGFloat) {
        let s = Self.stepped(t)
        #expect(s.layout.steppedPage(progress: 0) == s.page)
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func halfProgressIsHalfTheStep(_ t: CGFloat) {
        let s = Self.stepped(t)
        #expect(Self.close(s.layout.steppedPage(progress: 0.5).minX - s.page.minX, 4.5))
    }

    @Test func reduceMotionKeepsThePageWhereItIs() {
        let still = PeekWindowLayout(bounds: Self.window, page: Self.page(thickness: 10), stepsBack: false)
        #expect(still.scale == 1)
        #expect(still.steppedPage() == still.page)
    }

    @Test func aPageTooSmallToStepBackStaysPut() {
        let tiny = PeekWindowLayout(bounds: Self.window, page: CGRect(x: 0, y: 0, width: 30, height: 30), stepsBack: true)
        #expect(tiny.scale == 1)
    }

    private static let anchors = [CGPoint.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0, y: 1)]

    private static func transformed(anchor: CGPoint) -> (left: CGPoint, right: CGPoint, center: CGPoint, originalLeft: CGPoint, originalCenter: CGPoint, bounds: CGRect) {
        let bounds = CGRect(x: 0, y: 0, width: 1042, height: 780)
        let scale = (bounds.width - 18) / bounds.width
        let transform = PeekWindowLayout.stepTransform(bounds: bounds, anchor: anchor, scale: scale)
        let layer = CALayer()
        layer.anchorPoint = anchor
        layer.bounds = bounds
        layer.position = CGPoint(x: 300, y: 200)
        let host = CALayer()
        host.addSublayer(layer)
        layer.transform = transform
        let left = layer.convert(CGPoint(x: bounds.minX, y: bounds.midY), to: host)
        let right = layer.convert(CGPoint(x: bounds.maxX, y: bounds.midY), to: host)
        let center = layer.convert(CGPoint(x: bounds.midX, y: bounds.midY), to: host)
        layer.transform = CATransform3DIdentity
        return (left, right, center, layer.convert(CGPoint(x: bounds.minX, y: bounds.midY), to: host),
                layer.convert(CGPoint(x: bounds.midX, y: bounds.midY), to: host), bounds)
    }

    @Test(arguments: 0..<3)
    func theStepKeepsThePageCentreFixed(_ anchor: Int) {
        let t = Self.transformed(anchor: Self.anchors[anchor])
        #expect(Self.close(t.center.x, t.originalCenter.x))
        #expect(Self.close(t.center.y, t.originalCenter.y))
    }

    @Test(arguments: 0..<3)
    func theStepMovesEachSideNinePointsIn(_ anchor: Int) {
        let t = Self.transformed(anchor: Self.anchors[anchor])
        #expect(Self.close(t.left.x - t.originalLeft.x, 9))
        #expect(Self.close(t.right.x - t.left.x, t.bounds.width - 18))
    }

    @Test func noScaleIsTheIdentity() {
        let bounds = CGRect(x: 0, y: 0, width: 1042, height: 780)
        #expect(CATransform3DIsIdentity(PeekWindowLayout.stepTransform(bounds: bounds, anchor: .zero, scale: 1)))
    }

    private struct Regions {
        let t: CGFloat = 10
        let page: CGRect
        let layout: PeekWindowLayout
        let controls: CGRect
        let card: CGRect
        let stepped: CGRect

        init() {
            page = PeekWindowHostTests.page(thickness: t)
            layout = PeekWindowLayout(bounds: PeekWindowHostTests.window, page: page, stepsBack: true)
            controls = layout.controls(closeWidth: PeekWindowLayout.controlSize)
            card = layout.card
            stepped = layout.steppedPage()
        }

        func region(_ x: CGFloat, _ y: CGFloat) -> PeekWindowLayout.Region { layout.region(at: CGPoint(x: x, y: y), controls: controls) }
    }

    @Test func theTopFrameDragsTheWindow() {
        let r = Regions()
        #expect(r.region(r.page.midX + r.card.width / 2 + 60, 4) == .frame)
    }

    @Test func theTopFrameLeftOfTheCardDragsTheWindow() {
        let r = Regions()
        #expect(r.region(r.page.minX + 20, 4) == .frame)
    }

    @Test func theCardsTopEdgeInTheOldFrameBandIsThePeek() {
        let r = Regions()
        #expect(r.region(r.card.midX, r.card.minY + 2) == .card)
    }

    @Test(arguments: 0..<3)
    func theBandTheStepRevealsActsAsFrame(_ side: Int) {
        let r = Regions()
        let point = [CGPoint(x: r.page.minX + 3, y: r.page.midY), CGPoint(x: r.page.maxX - 3, y: r.page.midY),
                     CGPoint(x: r.page.minX + 40, y: r.page.maxY - 2)][side]
        #expect(r.region(point.x, point.y) == .frame)
    }

    @Test func theFadedPageClosesThePeek() {
        let r = Regions()
        #expect(r.region(r.stepped.minX + 4, r.page.midY) == .page)
    }

    @Test func theFadedPageBesideTheCardClosesThePeek() {
        let r = Regions()
        #expect(r.region(r.card.maxX + 5, r.page.midY) == .page)
    }

    @Test func theCardIsThePeek() {
        let r = Regions()
        #expect(r.region(r.card.midX, r.page.midY) == .card)
    }

    @Test func theRoundButtonsAreThePeeksControls() {
        let r = Regions()
        #expect(r.region(r.controls.midX, r.controls.minY + 4) == .controls)
    }

    @Test func theSplitGripMarginStaysTheGrips() {
        let r = Regions()
        #expect(r.region(r.page.maxX + r.t / 2, r.page.midY) == .frame)
    }

    @Test func theDockedSidebarStaysTheSidebars() {
        let r = Regions()
        #expect(r.region(Self.sidebarWidth / 2, 300) == .frame)
    }

    @Test func withoutTheStepThePagesEdgeStillClosesThePeek() {
        let r = Regions()
        let still = PeekWindowLayout(bounds: Self.window, page: r.page, stepsBack: false)
        #expect(still.region(at: CGPoint(x: r.page.minX + 3, y: r.page.midY), controls: r.controls) == .page)
    }

    private static let steppedBounds = CGRect(x: 0, y: 0, width: 1042, height: 780)
    private static let steppedScale = (1042 - 18) / CGFloat(1042)

    @Test func theParentPageIgnoresClicksInTheBandTheStepReveals() {
        #expect(!PeekWindowLayout.pageAcceptsHit(at: CGPoint(x: 4, y: 390), in: Self.steppedBounds, scale: Self.steppedScale))
    }

    @Test func theParentPageKeepsItsSteppedArea() {
        #expect(PeekWindowLayout.pageAcceptsHit(at: CGPoint(x: 20, y: 390), in: Self.steppedBounds, scale: Self.steppedScale))
    }

    @Test func aPageThatIsNotSteppedBackTakesEveryClick() {
        #expect(PeekWindowLayout.pageAcceptsHit(at: CGPoint(x: 4, y: 390), in: Self.steppedBounds, scale: 1))
    }

    private static func transform(_ value: Any?) -> CATransform3D? { (value as? NSValue)?.caTransform3DValue }

    private static func centreOffset(of transform: CATransform3D, width: CGFloat) -> CGFloat {
        transform.m41 + transform.m11 * width / 2 - width / 2
    }

    private static func midway(_ from: CATransform3D, _ to: CATransform3D, _ fraction: CGFloat) -> CATransform3D {
        var result = to
        result.m41 = from.m41 + (to.m41 - from.m41) * fraction
        result.m42 = from.m42 + (to.m42 - from.m42) * fraction
        return result
    }

    private static let narrow = CGRect(x: 0, y: 0, width: 1042, height: 780)
    private static let wide = CGRect(x: 0, y: 0, width: 1042 + 228, height: 780)
    private static var scale: CGFloat { PeekWindowLayout(bounds: window, page: wide, stepsBack: true).scale }

    @MainActor private static func pageView() -> (NSView, CALayer) {
        let view = NSView(frame: wide)
        view.wantsLayer = true
        return (view, view.layer!)
    }

    @MainActor private static func slidingPage(from start: CGRect, slide: CABasicAnimation) -> (NSView, CALayer) {
        let (view, layer) = pageView()
        slide.fromValue = NSValue(rect: start)
        slide.isRemovedOnCompletion = false
        layer.add(slide, forKey: PeekStepBack.slideKey)
        return (view, layer)
    }

    @MainActor @Test func withoutASlideTheStepSimplyHolds() {
        let (still, layer) = Self.pageView()
        PeekStepBack([still]).set(1, scale: Self.scale)
        let held = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(held.flatMap { Self.transform($0.fromValue) }.map { CATransform3DEqualToTransform($0, Self.transform(held?.toValue)!) } == true)
    }

    @MainActor @Test func aHeldStepIsCentredOnThePage() {
        let (still, layer) = Self.pageView()
        PeekStepBack([still]).set(1, scale: Self.scale)
        let held = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(Self.close(Self.centreOffset(of: Self.transform(held?.toValue)!, width: Self.wide.width), 0))
    }

    @MainActor @Test func aStepHeldForTheFinalWidthSitsOffCentreOnAPageStillSlidingFromTheOldWidth() {
        let (still, layer) = Self.pageView()
        PeekStepBack([still]).set(1, scale: Self.scale)
        let held = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(abs(Self.centreOffset(of: Self.transform(held?.toValue)!, width: Self.narrow.width)) > 1)
    }

    @MainActor private final class Following {
        let slide = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        let view: NSView
        let layer: CALayer
        let step: PeekStepBack

        init() {
            slide.duration = 0.2
            slide.beginTime = 500
            slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            (view, layer) = PeekWindowHostTests.slidingPage(from: PeekWindowHostTests.narrow, slide: slide)
            step = PeekStepBack([view])
            step.set(1, scale: PeekWindowHostTests.scale)
        }

        var follow: CABasicAnimation? { layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation }
    }

    @MainActor @Test func aSlidingPageGetsAnAdditiveTransformStepThatStaysOnceTheSlideEnds() throws {
        let f = Following()
        let follow = try #require(f.follow)
        #expect(follow.keyPath == "transform")
        #expect(follow.isAdditive)
        #expect(!follow.isRemovedOnCompletion)
        #expect(follow.fillMode == .both)
    }

    @MainActor @Test func theStepRidesTheSlidesOwnClockAndCurve() throws {
        let f = Following()
        let follow = try #require(f.follow)
        #expect(follow.duration == f.slide.duration)
        #expect(follow.beginTime == 500)
        #expect(follow.timingFunction == f.slide.timingFunction)
    }

    @MainActor @Test func theStepEndsCentredOnTheFinalPage() throws {
        let f = Following()
        let follow = try #require(f.follow)
        let to = try #require(Self.transform(follow.toValue))
        #expect(CATransform3DEqualToTransform(to, PeekWindowLayout.stepTransform(bounds: Self.wide, anchor: f.layer.anchorPoint, scale: Self.scale)))
    }

    @MainActor @Test(arguments: [CGFloat(0), 0.25, 0.5, 0.75, 1])
    func theStepStaysCentredOnThePageThroughoutTheSlide(_ fraction: CGFloat) throws {
        let f = Following()
        let follow = try #require(f.follow)
        let from = try #require(Self.transform(follow.fromValue)), to = try #require(Self.transform(follow.toValue))
        let width = Self.narrow.width + (Self.wide.width - Self.narrow.width) * fraction
        #expect(Self.close(Self.centreOffset(of: Self.midway(from, to, fraction), width: width), 0))
    }

    @MainActor @Test func aFadeDuringTheSlideKeepsFollowingItFromTheSameStart() {
        let f = Following()
        f.step.set(0.5, scale: Self.scale)
        let fading = f.layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        let factor = 1 - 0.5 * (1 - Self.scale)
        #expect(fading?.beginTime == 500)
        #expect(Self.transform(fading?.fromValue).map {
            CATransform3DEqualToTransform($0, PeekWindowLayout.stepTransform(bounds: Self.narrow, anchor: f.layer.anchorPoint, scale: factor))
        } == true)
    }

    @MainActor private func cutShort(_ f: Following) -> CABasicAnimation? {
        f.layer.removeAnimation(forKey: PeekStepBack.slideKey)
        f.step.refresh()
        return f.follow
    }

    @MainActor @Test func aSlideCutShortSnapsTheStepToTheFinalPageCentred() {
        let f = Following()
        let after = cutShort(f)
        #expect(after.flatMap { Self.transform($0.fromValue) }.map { CATransform3DEqualToTransform($0, Self.transform(after?.toValue)!) } == true)
        #expect(after?.duration == 1)
    }

    @MainActor @Test func aSettledStepIsNotReappliedOnEveryLayout() {
        let f = Following()
        let after = cutShort(f)
        f.step.refresh()
        #expect(f.follow === after)
    }

    @MainActor @Test func aFloatingSidebarsSpringSlideIsFollowedWithTheSameSpring() {
        let (springing, layer) = Self.pageView()
        let spring = CASpringAnimation(keyPath: PeekStepBack.slideKey)
        spring.isAdditive = true
        spring.fromValue = NSValue(rect: CGRect(x: 0, y: 0, width: Self.narrow.width - Self.wide.width, height: 0))
        spring.toValue = NSValue(rect: .zero)
        spring.stiffness = 1218
        spring.damping = 55.8
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: PeekStepBack.slideKey)
        PeekStepBack([springing]).set(1, scale: Self.scale)
        let sprung = layer.animation(forKey: PeekStepBack.key) as? CASpringAnimation
        #expect(sprung?.stiffness == 1218)
        #expect(sprung?.damping == 55.8)
        #expect(Self.transform(sprung?.fromValue).map {
            CATransform3DEqualToTransform($0, PeekWindowLayout.stepTransform(bounds: Self.narrow, anchor: layer.anchorPoint, scale: Self.scale))
        } == true)
    }

    @MainActor @Test func aSlideThatDoesNotChangeThePagesSizeKeepsThePlainHold() {
        let (moving, layer) = Self.pageView()
        let move = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        move.fromValue = NSValue(rect: Self.wide.offsetBy(dx: 40, dy: 0))
        layer.add(move, forKey: PeekStepBack.slideKey)
        PeekStepBack([moving]).set(1, scale: Self.scale)
        let moved = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(moved.flatMap { Self.transform($0.fromValue) }.map { CATransform3DEqualToTransform($0, Self.transform(moved?.toValue)!) } == true)
    }

    private static var finalStep: CATransform3D { PeekWindowLayout.stepTransform(bounds: wide, anchor: .zero, scale: scale) }

    @MainActor @Test func aPeekOpeningWithNoSlideKeepsItsPlainEaseOutStep() {
        let resting = NSView(frame: Self.wide)
        resting.wantsLayer = true
        PeekStepBack([resting]).animateIn(scale: Self.scale)
        let plain = resting.layer?.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(plain?.duration == PeekStepBack.openDuration)
        #expect(plain?.timingFunction == CAMediaTimingFunction(name: .easeOut))
        #expect(Self.transform(plain?.toValue).map { CATransform3DEqualToTransform($0, Self.finalStep) } == true)
    }

    private struct Opening {
        let animation: CAKeyframeAnimation
        let values: [CATransform3D]
        let times: [Double]
    }

    @MainActor private static func opening(riding slide: CABasicAnimation) throws -> Opening {
        let (view, layer) = slidingPage(from: narrow, slide: slide)
        PeekStepBack([view]).animateIn(scale: scale)
        let animation = try #require(layer.animation(forKey: PeekStepBack.key) as? CAKeyframeAnimation)
        let values = try #require(animation.values?.compactMap(transform))
        let times = try #require(animation.keyTimes?.map(\.doubleValue))
        #expect(values.count == times.count)
        #expect(values.count > 2)
        return Opening(animation: animation, values: values, times: times)
    }

    @MainActor private static func libraryOpening() throws -> (slide: CABasicAnimation, opening: Opening) {
        let library = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        library.duration = 0.2
        library.beginTime = CACurrentMediaTime() - 0.05
        return (library, try opening(riding: library))
    }

    @MainActor @Test func theOpeningThatRidesASlideStaysPutOnceItEnds() throws {
        let o = try Self.libraryOpening().opening.animation
        #expect(o.isAdditive)
        #expect(!o.isRemovedOnCompletion)
        #expect(o.fillMode == .both)
        #expect(o.calculationMode == .linear)
    }

    @MainActor @Test func itEndsExactlyOnTheFinalStepAndStartsFromThePageAtRest() throws {
        let o = try Self.libraryOpening().opening
        #expect(CATransform3DEqualToTransform(o.values[o.values.count - 1], Self.finalStep))
        #expect(Self.close(o.values[0].m11, 1))
    }

    @MainActor @Test func theOpeningKeepsItsThreeTenthsOfASecondWhenTheSlideEndsFirst() throws {
        let o = try Self.libraryOpening().opening.animation
        #expect(Self.close(CGFloat(o.duration), CGFloat(PeekStepBack.openDuration), 0.005))
    }

    @MainActor @Test func theOpeningStepStaysCentredOnTheSlidingPage() throws {
        let (library, o) = try Self.libraryOpening()
        for (value, time) in zip(o.values, o.times) {
            let moment = o.animation.beginTime + time * o.animation.duration
            let slid = CGFloat(min(1, max(0, (moment - library.beginTime) / library.duration)))
            let width = Self.narrow.width + (Self.wide.width - Self.narrow.width) * slid
            #expect(Self.close(Self.centreOffset(of: value, width: width), 0))
        }
    }

    @MainActor @Test func thePageOnlyStepsBackWhileOpening() throws {
        let o = try Self.libraryOpening().opening
        #expect(zip(o.values, o.values.dropFirst()).allSatisfy { $1.m11 <= $0.m11 + 1e-9 })
    }

    @MainActor private static func longOpening() throws -> (slide: CABasicAnimation, opening: Opening) {
        let long = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        long.duration = 0.5
        long.beginTime = CACurrentMediaTime()
        return (long, try opening(riding: long))
    }

    @MainActor @Test func theComposedStepLastsUntilALongerSlideEnds() throws {
        let (long, o) = try Self.longOpening()
        #expect(Self.close(CGFloat(o.animation.duration), CGFloat(long.beginTime + long.duration - o.animation.beginTime), 0.001))
    }

    @MainActor @Test func theStepStaysCentredWhileALongSlideRuns() throws {
        let (long, o) = try Self.longOpening()
        for (value, time) in zip(o.values, o.times) {
            let moment = o.animation.beginTime + time * o.animation.duration
            let width = Self.narrow.width + (Self.wide.width - Self.narrow.width) * CGFloat(min(1, (moment - long.beginTime) / long.duration))
            #expect(Self.close(Self.centreOffset(of: value, width: width), 0))
        }
    }

    @MainActor @Test func afterTheOpeningEndsTheStepHoldsItsFinalSize() throws {
        let (_, o) = try Self.longOpening()
        for (value, time) in zip(o.values, o.times) where time * o.animation.duration >= PeekStepBack.openDuration + 0.01 {
            #expect(Self.close(value.m11, Self.finalStep.m11))
        }
    }

    @MainActor @Test func anOpeningAimedOnlyAtTheFinalWidthWouldSitOffCentreDuringTheseSlides() throws {
        let (library, lo) = try Self.libraryOpening()
        let (long, go) = try Self.longOpening()
        func aimed(_ value: CATransform3D, width: CGFloat) -> CGFloat {
            let eased = (1 - value.m11) / (1 - Self.finalStep.m11)
            return abs(eased * Self.finalStep.m41 + (1 + eased * (Self.finalStep.m11 - 1)) * width / 2 - width / 2)
        }
        var worst: CGFloat = 0
        for (value, time) in zip(lo.values, lo.times) {
            let moment = lo.animation.beginTime + time * lo.animation.duration
            let slid = CGFloat(min(1, max(0, (moment - library.beginTime) / library.duration)))
            worst = max(worst, aimed(value, width: Self.narrow.width + (Self.wide.width - Self.narrow.width) * slid))
        }
        for (value, time) in zip(go.values, go.times) {
            let moment = go.animation.beginTime + time * go.animation.duration
            let slid = CGFloat(min(1, (moment - long.beginTime) / long.duration))
            worst = max(worst, aimed(value, width: Self.narrow.width + (Self.wide.width - Self.narrow.width) * slid))
        }
        #expect(worst > 0.5)
    }

    private static func springSlide() -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: PeekStepBack.slideKey)
        spring.stiffness = 1218
        spring.damping = 55.8
        spring.duration = spring.settlingDuration
        return spring
    }

    @MainActor @Test func aSpringSlideIsComposedForAsLongAsTheSpringRuns() throws {
        let spring = Self.springSlide()
        let o = try Self.opening(riding: spring)
        #expect(Self.close(CGFloat(o.animation.duration), CGFloat(max(PeekStepBack.openDuration, spring.duration)), 0.01))
    }

    @MainActor @Test func theOpeningStepStaysCentredOnTheSpringingPage() throws {
        let spring = Self.springSlide()
        let o = try Self.opening(riding: spring)
        func springWidth(at elapsed: Double) -> CGFloat {
            var offset = 1.0, velocity = 0.0, clock = 0.0
            let step = 1e-5, mass = Double(spring.mass), stiffness = Double(spring.stiffness), damping = Double(spring.damping)
            while clock < elapsed {
                velocity += (-stiffness * offset - damping * velocity) / mass * step
                offset += velocity * step
                clock += step
            }
            return Self.narrow.width + (Self.wide.width - Self.narrow.width) * CGFloat(1 - offset)
        }
        var checks = 0
        for (index, (value, time)) in zip(o.values, o.times).enumerated() where index > 0 && index < o.values.count - 1 && index % 4 == 0 {
            checks += 1
            #expect(Self.close(Self.centreOffset(of: value, width: springWidth(at: time * o.animation.duration)), 0, 0.02))
        }
        #expect(checks >= 6)
    }

    private static let midwayRect = CGRect(x: 0, y: 0, width: 1042 + 114, height: 780)

    @MainActor private final class Replaced {
        let first = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        let view: NSView
        let layer: CALayer
        let step: PeekStepBack
        let now = CACurrentMediaTime()

        init() {
            first.duration = 0.2
            first.beginTime = now - 0.1
            (view, layer) = PeekWindowHostTests.slidingPage(from: PeekWindowHostTests.narrow, slide: first)
            step = PeekStepBack([view])
            step.set(1, scale: PeekWindowHostTests.scale)
        }

        func replace() -> (slide: CABasicAnimation, tracking: CABasicAnimation?) {
            let second = CABasicAnimation(keyPath: PeekStepBack.slideKey)
            second.fromValue = NSValue(rect: PeekWindowHostTests.midwayRect)
            second.duration = 0.2
            second.beginTime = now - 0.1
            second.isRemovedOnCompletion = false
            layer.add(second, forKey: PeekStepBack.slideKey)
            step.refresh()
            return (second, layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation)
        }
    }

    @MainActor @Test func theStepFollowsTheFirstSlideFromThePagesOldWidth() {
        let r = Replaced()
        let following = r.layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(following?.beginTime == r.first.beginTime)
        #expect(Self.transform(following?.fromValue).map {
            CATransform3DEqualToTransform($0, PeekWindowLayout.stepTransform(bounds: Self.narrow, anchor: .zero, scale: Self.scale))
        } == true)
    }

    @MainActor @Test func theStepRidesTheReplacementSlidesClockToTheSameFinalStep() throws {
        let r = Replaced()
        let (second, tracking) = r.replace()
        let t = try #require(tracking)
        #expect(t.beginTime == second.beginTime)
        #expect(t.duration == second.duration)
        #expect(CATransform3DEqualToTransform(try #require(Self.transform(t.toValue)), Self.finalStep))
    }

    @MainActor @Test(arguments: [CGFloat(0), 0.25, 0.5, 0.75, 1])
    func theStepStaysCentredOnTheInFlightWidthAtEachPointOfTheReplacementSlide(_ fraction: CGFloat) throws {
        let r = Replaced()
        let t = try #require(r.replace().tracking)
        let from = try #require(Self.transform(t.fromValue)), to = try #require(Self.transform(t.toValue))
        let width = Self.midwayRect.width + (Self.wide.width - Self.midwayRect.width) * fraction
        #expect(Self.close(Self.centreOffset(of: Self.midway(from, to, fraction), width: width), 0))
    }

    @Test func aStepStillFollowingTheFirstSlidesStartWouldSitOffCentreWhenTheReplacementBegins() {
        let stale = PeekWindowLayout.stepTransform(bounds: Self.narrow, anchor: .zero, scale: Self.scale)
        #expect(abs(Self.centreOffset(of: stale, width: Self.midwayRect.width)) > 0.5)
    }

    @MainActor @Test func theReplacementSlideIsFollowedOnceNotOnEveryLayout() {
        let r = Replaced()
        let (_, tracking) = r.replace()
        r.step.refresh()
        #expect(r.layer.animation(forKey: PeekStepBack.key) === tracking)
    }

    @MainActor @Test func aReplacementSlideThatHasNotStartedYetIsRestartedFromTheSlideItReplaced() {
        let r = Replaced()
        let (_, tracking) = r.replace()
        let third = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        third.fromValue = NSValue(rect: Self.midwayRect)
        third.duration = 0.2
        third.isRemovedOnCompletion = false
        r.layer.add(third, forKey: PeekStepBack.slideKey)
        r.step.refresh()
        let restarted = r.layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(restarted !== tracking)
        #expect((restarted?.beginTime ?? 0) > (tracking?.beginTime ?? .infinity))
    }

    @MainActor @Test func aSlideThatOnlyMovesThePageLeavesTheHeldStepAloneOnLaterLayouts() {
        let resting = NSView(frame: Self.wide)
        resting.wantsLayer = true
        let layer = resting.layer!
        let moving = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        moving.fromValue = NSValue(rect: Self.wide.offsetBy(dx: 30, dy: 0))
        moving.isRemovedOnCompletion = false
        layer.add(moving, forKey: PeekStepBack.slideKey)
        let still = PeekStepBack([resting])
        still.set(1, scale: Self.scale)
        let held = layer.animation(forKey: PeekStepBack.key)
        still.refresh()
        #expect(layer.animation(forKey: PeekStepBack.key) === held)
    }

    private final class Flipped: NSView { override var isFlipped: Bool { true } }

    private final class HostedPage: NSView {
        var scale: CGFloat = 1
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview, PeekWindowLayout.pageAcceptsHit(at: convert(point, from: superview), in: bounds, scale: scale) else { return nil }
            return super.hitTest(point)
        }
    }

    @MainActor private final class Tree {
        let t: CGFloat = 10
        let frame: CGRect
        let root: Flipped
        let page: HostedPage
        let pageContent: Flipped
        let grip: Flipped
        let host: PeekHitView
        let layout: PeekWindowLayout
        let cardContent: Flipped
        let close: Flipped
        let sidebar: Flipped

        init() {
            let window = PeekWindowHostTests.window
            frame = PeekWindowHostTests.page(thickness: t)
            let content = Flipped(frame: window)
            root = Flipped(frame: window)
            content.addSubview(root)
            page = HostedPage(frame: frame)
            pageContent = Flipped(frame: page.bounds)
            page.addSubview(pageContent)
            grip = Flipped(frame: CGRect(x: frame.maxX, y: frame.midY - 22, width: t, height: 44))
            let layer = PeekLayerView(frame: window)
            host = PeekHitView(frame: layer.bounds)
            layout = PeekWindowLayout(bounds: host.bounds, page: frame, stepsBack: true)
            host.hitLayout = layout
            let controls = layout.controls(closeWidth: PeekWindowLayout.controlSize)
            host.hitControls = controls
            let card = Flipped(frame: layout.card)
            cardContent = Flipped(frame: card.bounds)
            card.addSubview(cardContent)
            close = Flipped(frame: CGRect(origin: controls.origin, size: CGSize(width: 32, height: 32)))
            host.addSubview(card)
            host.addSubview(close)
            layer.addSubview(host)
            sidebar = Flipped(frame: CGRect(x: 5, y: 5, width: PeekWindowHostTests.sidebarWidth, height: window.height - 10))
            root.addSubview(page)
            root.addSubview(grip)
            root.addSubview(layer)
            root.addSubview(sidebar)
            page.scale = layout.scale
        }

        func hit(_ x: CGFloat, _ y: CGFloat) -> NSView? { root.hitTest(CGPoint(x: x, y: y)) }
    }

    @MainActor @Test func theTopFrameReachesTheWindowSoItDrags() {
        let v = Tree()
        #expect(v.hit(v.frame.midX + v.layout.card.width / 2 + 60, 4) === v.root)
        #expect(v.root.mouseDownCanMoveWindow)
    }

    @MainActor @Test func theRevealedBandReachesTheWindowForTheFrameMenu() {
        let v = Tree()
        #expect(v.hit(v.frame.maxX - 3, v.frame.midY) === v.root)
    }

    @MainActor @Test func theRightFrameReachesTheWindow() {
        let v = Tree()
        #expect(v.hit(v.frame.maxX + 3, 4) === v.root)
    }

    @MainActor @Test func theFadedPageGoesToThePeekWhichClosesIt() {
        let v = Tree()
        #expect(v.hit(v.frame.minX + 30, v.frame.midY) === v.host)
    }

    @MainActor @Test func theCardsPageGetsItsOwnClicks() {
        let v = Tree()
        #expect(v.hit(v.layout.card.midX, v.frame.midY) === v.cardContent)
        #expect(v.hit(v.layout.card.midX, v.layout.card.minY + 2) === v.cardContent)
    }

    @MainActor @Test func closeGetsItsClick() {
        let v = Tree()
        #expect(v.hit(v.close.frame.midX, v.close.frame.midY) === v.close)
    }

    @MainActor @Test func theSplitGripKeepsWorking() {
        let v = Tree()
        #expect(v.hit(v.grip.frame.midX, v.grip.frame.midY) === v.grip)
    }

    @MainActor @Test func theFadedPageAndTheCardCountAsThePeeksForTheWindowsClickWatch() {
        let v = Tree()
        #expect(v.host.claims(CGPoint(x: v.frame.minX + 30, y: v.frame.midY)))
        #expect(v.host.claims(CGPoint(x: v.layout.card.midX, y: 14)))
    }

    @MainActor @Test func theFrameTheRevealedBandAndTheGripAreNotThePeeks() {
        let v = Tree()
        #expect(!v.host.claims(CGPoint(x: v.frame.maxX - 3, y: v.frame.midY)))
        #expect(!v.host.claims(CGPoint(x: 100, y: 4)))
        #expect(!v.host.claims(v.grip.frame.origin))
    }

    @MainActor @Test func theFloatingSidebarStaysAboveThePeek() {
        let v = Tree()
        #expect(v.hit(100, 300) === v.sidebar)
    }

    @MainActor @Test func withTheSidebarAwayItsAreaIsFrameAgain() {
        let v = Tree()
        v.sidebar.removeFromSuperview()
        #expect(v.hit(100, 300) === v.root)
        #expect(v.hit(v.frame.minX + 3, v.frame.midY) === v.root)
    }

    @MainActor @Test func withThePeekHiddenThePageTakesClicksAtItsEdgeAndItsOwn() {
        let v = Tree()
        v.sidebar.removeFromSuperview()
        v.host.isHidden = true
        v.page.scale = 1
        #expect(v.hit(v.frame.minX + 3, v.frame.midY) === v.pageContent)
        #expect(v.hit(v.frame.minX + 30, v.frame.midY) === v.pageContent)
    }
}
