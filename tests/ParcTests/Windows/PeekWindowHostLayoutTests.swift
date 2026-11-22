import AppKit
import QuartzCore
import Testing
@testable import Parc

struct PeekWindowHostLayoutTests {
    struct Frame: Sendable, CustomTestStringConvertible {
        let thickness: CGFloat
        let docked: Bool
        var testDescription: String { "frame \(thickness), docked \(docked)" }
        static let all = [CGFloat(3), 10, 13].flatMap { t in [true, false].map { Frame(thickness: t, docked: $0) } }
        var page: CGRect { PeekWindowHostSupport.page(thickness: thickness, docked: docked) }
        var card: CGRect { PeekWindowLayout(bounds: PeekWindowHostSupport.window, page: page, stepsBack: true).card }
    }

    @Test(arguments: Frame.all)
    func theCardSitsTwelvePointsFromTheWindowsTopAndBottom(_ f: Frame) {
        #expect(f.card.minY == 12)
        #expect(f.card.maxY == PeekWindowHostSupport.window.maxY - 12)
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
        let classic = PeekWindowHostSupport.page(thickness: 10)
        let today = classic.minY + 12
        #expect(today - PeekWindowLayout(bounds: PeekWindowHostSupport.window, page: classic, stepsBack: true).card.minY == 10)
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
        let classic = PeekWindowHostSupport.page(thickness: 10)
        let wide = PeekWindowLayout(bounds: PeekWindowHostSupport.window, page: classic, stepsBack: true).controls(closeWidth: 400)
        #expect(wide.maxX <= classic.maxX - 4)
    }

    private static func stepped(_ t: CGFloat) -> (page: CGRect, layout: PeekWindowLayout, stepped: CGRect) {
        let page = PeekWindowHostSupport.page(thickness: t)
        let layout = PeekWindowLayout(bounds: PeekWindowHostSupport.window, page: page, stepsBack: true)
        return (page, layout, layout.steppedPage())
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func thePageStepsBackNinePointsAtEachSide(_ t: CGFloat) {
        let s = Self.stepped(t)
        #expect(PeekWindowHostSupport.close(s.stepped.minX - s.page.minX, 9))
        #expect(PeekWindowHostSupport.close(s.page.maxX - s.stepped.maxX, 9))
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func theStepIsAnEvenScaleALittleLessTopAndBottom(_ t: CGFloat) {
        let s = Self.stepped(t)
        let vertical = s.stepped.minY - s.page.minY
        #expect(PeekWindowHostSupport.close(vertical, 9 * s.page.height / s.page.width))
        #expect(vertical > 6 && vertical < 9)
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func thePageShrinksAboutItsCentre(_ t: CGFloat) {
        let s = Self.stepped(t)
        #expect(PeekWindowHostSupport.close(s.stepped.midX, s.page.midX))
        #expect(PeekWindowHostSupport.close(s.stepped.midY, s.page.midY))
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func noProgressMeansNoStep(_ t: CGFloat) {
        let s = Self.stepped(t)
        #expect(s.layout.steppedPage(progress: 0) == s.page)
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func halfProgressIsHalfTheStep(_ t: CGFloat) {
        let s = Self.stepped(t)
        #expect(PeekWindowHostSupport.close(s.layout.steppedPage(progress: 0.5).minX - s.page.minX, 4.5))
    }

    @Test func reduceMotionKeepsThePageWhereItIs() {
        let still = PeekWindowLayout(bounds: PeekWindowHostSupport.window, page: PeekWindowHostSupport.page(thickness: 10), stepsBack: false)
        #expect(still.scale == 1)
        #expect(still.steppedPage() == still.page)
    }

    @Test func aPageTooSmallToStepBackStaysPut() {
        let tiny = PeekWindowLayout(bounds: PeekWindowHostSupport.window, page: CGRect(x: 0, y: 0, width: 30, height: 30), stepsBack: true)
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
        #expect(PeekWindowHostSupport.close(t.center.x, t.originalCenter.x))
        #expect(PeekWindowHostSupport.close(t.center.y, t.originalCenter.y))
    }

    @Test(arguments: 0..<3)
    func theStepMovesEachSideNinePointsIn(_ anchor: Int) {
        let t = Self.transformed(anchor: Self.anchors[anchor])
        #expect(PeekWindowHostSupport.close(t.left.x - t.originalLeft.x, 9))
        #expect(PeekWindowHostSupport.close(t.right.x - t.left.x, t.bounds.width - 18))
    }

    @Test func noScaleIsTheIdentity() {
        let bounds = CGRect(x: 0, y: 0, width: 1042, height: 780)
        #expect(CATransform3DIsIdentity(PeekWindowLayout.stepTransform(bounds: bounds, anchor: .zero, scale: 1)))
    }
}
