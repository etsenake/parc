import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeOverlayPaneGeometryTests {
    @Test
    func aNarrowBackPaneNarrowsTheCard() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.size = CGSize(width: 220, height: 500)
        let list = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(list.card.minX, 14) && HistorySwipeOverlaySupport.close(list.card.width, 192))
    }

    @Test
    func aNarrowForwardPaneContainsTheCard() throws {
        var right = HistorySwipeOverlaySupport.Driver.holding(.forward, forward: 3)
        right.size = CGSize(width: 260, height: 500)
        let list = try #require(right.frame?.list)
        #expect(list.card.minX >= 14 && list.card.maxX <= 246)
    }

    @Test
    func aSplitUsesItsOwnPaneBounds() {
        var split = HistorySwipeOverlaySupport.Driver.armed(.forward)
        split.size = CGSize(width: 412, height: 664)
        #expect(split.frame.map { HistorySwipeOverlaySupport.close($0.circle.maxX, 398) } == true)
    }

    struct AppearanceCase: Sendable, CustomTestStringConvertible {
        let dark: Bool
        let ringWhite: Double
        let ring: Double
        let shadow: Double
        let wash: Double
        let highlight: Double
        var testDescription: String { dark ? "dark appearance" : "light appearance" }

        static let all = [
            Self(dark: true, ringWhite: 1, ring: 0.15, shadow: 0.25, wash: 0, highlight: 1),
            Self(dark: false, ringWhite: 0, ring: 0.125, shadow: 0.2, wash: 0.4, highlight: 0),
        ]
    }

    @Test(arguments: AppearanceCase.all)
    func overlayColorsFollowTheAppearance(_ appearance: AppearanceCase) {
        let look = HistorySwipeOverlayLook(dark: appearance.dark)
        #expect(look.ringWhite == appearance.ringWhite)
        #expect(look.ringAlpha == appearance.ring)
        #expect(look.shadowAlpha == appearance.shadow)
        #expect(look.washAlpha == appearance.wash)
        #expect(look.highlightWhite == appearance.highlight)
        #expect(look.highlightAlpha == 0.1)
    }
}
