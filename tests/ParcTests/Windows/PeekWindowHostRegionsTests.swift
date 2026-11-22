import AppKit
import QuartzCore
import Testing
@testable import Parc

struct PeekWindowHostRegionsTests {
    private struct Regions {
        let t: CGFloat = 10
        let page: CGRect
        let layout: PeekWindowLayout
        let controls: CGRect
        let card: CGRect
        let stepped: CGRect

        init() {
            page = PeekWindowHostSupport.page(thickness: t)
            layout = PeekWindowLayout(bounds: PeekWindowHostSupport.window, page: page, stepsBack: true)
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
        #expect(r.region(PeekWindowHostSupport.sidebarWidth / 2, 300) == .frame)
    }

    @Test func withoutTheStepThePagesEdgeStillClosesThePeek() {
        let r = Regions()
        let still = PeekWindowLayout(bounds: PeekWindowHostSupport.window, page: r.page, stepsBack: false)
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
}
