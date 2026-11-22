import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeOverlaySelectionTests {
    @Test
    func eachHistoryDetentPlaysAnAlignmentHaptic() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(1))
        driver.send(.detent)
        #expect(driver.haptics.last == .alignment)
    }

    @Test
    func theCardSlidesWhileTheHighlightStaysStill() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list).content
        driver.send(.selection(1))
        driver.advance(0.1)
        let moving = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(moving.highlight.midY, HistorySwipeOverlaySupport.pane.height / 2) && moving.content.minY > before.minY
              && moving.content.minY < before.minY + 38)
    }

    @Test
    func theCardFollowsTheSelectionSpring() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list).content
        driver.send(.selection(1))
        driver.advance(0.1)
        let moving = try #require(driver.frame?.list)
        let zeta = 0.9, omega = 2 * Double.pi / 0.27, damped = omega * (1 - zeta * zeta).squareRoot()
        let shift = 38 * (1 - exp(-zeta * omega * 0.1) * (cos(damped * 0.1) + zeta * omega / damped * sin(damped * 0.1)))
        #expect(HistorySwipeOverlaySupport.close(moving.content.minY, before.minY + CGFloat(shift), 1e-6))
    }

    @Test
    func aBackStepSettlesThePreviousPageUnderTheHighlight() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list).content
        driver.send(.selection(1))
        driver.settle()
        let settled = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(settled.content.minY, before.minY + 38) && HistorySwipeOverlaySupport.close(settled.row(1), settled.highlight))
    }

    @Test
    func aForwardStepSlidesTheCardUp() throws {
        var forward = HistorySwipeOverlaySupport.Driver.holding(.forward, forward: 3)
        let top = try #require(forward.frame?.list).content
        forward.send(.selection(3))
        forward.settle()
        let list = try #require(forward.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(list.content.minY, top.minY - 114) && HistorySwipeOverlaySupport.close(list.row(3), list.highlight))
    }

    @Test
    func selectionClampsAtTheLastRow() {
        var forward = HistorySwipeOverlaySupport.Driver.holding(.forward, forward: 3)
        forward.send(.selection(9))
        forward.settle()
        #expect(forward.frame?.list?.selection == 3)
    }

    struct LeanCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let remainder: Double
        let expected: CGFloat

        static let all = [
            Self(testDescription: "at the selected row", remainder: 0, expected: 0),
            Self(testDescription: "toward the next row", remainder: 0.5, expected: 38 * (1 - 1 / 1.05)),
            Self(testDescription: "toward the previous row", remainder: -0.5, expected: -38 * (1 - 1 / 1.05)),
        ]
    }

    @Test(arguments: LeanCase.all)
    func theLeanFollowsASignedRubberBand(_ sample: LeanCase) {
        let remainder = sample.remainder
        let expected = sample.expected
        #expect(HistorySwipeOverlaySupport.close(HistorySwipeOverlaySupport.Geometry.lean(remainder: remainder), expected))
    }

    @Test
    func theLeanOnlyHintsAtTheNextRow() {
        #expect(HistorySwipeOverlaySupport.Geometry.lean(remainder: 0.99) < 3.5 && HistorySwipeOverlaySupport.Geometry.lean(remainder: 20) < 38)
    }

    @Test
    func theLeanRidesTheSelectionSpring() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list)
        driver.send(.rowRemainder(0.5))
        driver.advance(0.1)
        let zeta = 0.9, omega = 2 * Double.pi / 0.27, damped = omega * (1 - zeta * zeta).squareRoot()
        let lean = Double(HistorySwipeOverlaySupport.Geometry.lean(remainder: 0.5))
        let shift = lean * (1 - exp(-zeta * omega * 0.1) * (cos(damped * 0.1) + zeta * omega / damped * sin(damped * 0.1)))
        let current = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(current.content.minY, before.content.minY + CGFloat(shift), 1e-6))
    }

    @Test
    func theListLeansTowardThePreviousRowUnderAFixedHighlight() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list)
        driver.send(.rowRemainder(0.5))
        let lean = Double(HistorySwipeOverlaySupport.Geometry.lean(remainder: 0.5))
        driver.settle()
        let leaning = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(leaning.content.minY, before.content.minY + CGFloat(lean)) && HistorySwipeOverlaySupport.close(leaning.highlight, before.highlight)
              && leaning.highlight.midY < leaning.row(0).midY && leaning.highlight.midY > leaning.row(1).midY)
    }

    @Test
    func aNegativeRemainderLeansTheOtherWay() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list)
        let lean = Double(HistorySwipeOverlaySupport.Geometry.lean(remainder: 0.5))
        driver.send(.rowRemainder(-0.5))
        driver.settle()
        let current = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(current.content.minY, before.content.minY - CGFloat(lean)))
    }

    @Test
    func clearingTheRemainderSettlesSquarelyOnTheNextRow() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list)
        driver.send(.rowRemainder(0.5))
        driver.send(.selection(1))
        driver.send(.rowRemainder(0))
        driver.settle()
        let current = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(current.content.minY, before.content.minY + 38))
        #expect(HistorySwipeOverlaySupport.close(current.row(1), current.highlight))
    }

    @Test
    func theForwardCardLeansTowardNewerEntries() throws {
        let lean = Double(HistorySwipeOverlaySupport.Geometry.lean(remainder: 0.5))
        var forward = HistorySwipeOverlaySupport.Driver.holding(.forward, forward: 3)
        let top = try #require(forward.frame?.list).content
        forward.send(.rowRemainder(0.5))
        forward.settle()
        let current = try #require(forward.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(current.content.minY, top.minY - CGFloat(lean)))
    }

    @Test
    func aClosedListIgnoresRemainder() {
        var closed = HistorySwipeOverlaySupport.Driver.armed()
        closed.send(.rowRemainder(0.5))
        #expect(closed.model.remainder == 0)
    }
}
