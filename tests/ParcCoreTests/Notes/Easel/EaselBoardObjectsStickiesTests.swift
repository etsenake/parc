import Foundation
import Testing
@testable import ParcCore

struct EaselBoardObjectsStickiesTests {
    @MainActor @Test func stickiesKeepATextScaleAndSectionsCanHide() {
        var sticky = EaselBoardObjectsTestsSupport.item(.sticky, 10, 10, 220, 220)
        sticky.textStyle = EaselTextStyle(textScale: 2)
        var section = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 640, 480, text: "Section")
        section.contentsHidden = true
        #expect(EaselBoardObjectsTestsSupport.accepts([sticky, section]), "Stickies keep a text scale and sections can hide their contents")
        for edge in [0.25, 8.0] {
            var bounded = sticky
            bounded.textStyle = EaselTextStyle(textScale: edge)
            #expect(EaselBoardObjectsTestsSupport.accepts([bounded]), "A text scale of exactly \(edge) is allowed")
        }
        var towering = sticky
        towering.frame.height = EaselBoardObjects.stickyHeight(sticky, textHeight: 1e12)
        #expect(EaselBoardObjectsTestsSupport.accepts([towering]), "The tallest sticky still saves")
        for bad in [0.1, 9.0, Double.nan, Double.infinity] {
            var broken = sticky
            broken.textStyle = EaselTextStyle(textScale: bad)
            #expect(!EaselBoardObjectsTestsSupport.accepts([broken]), "A text scale of \(bad) is refused")
        }
        var scaledText = EaselBoardObjectsTestsSupport.item(.text, 0, 0, 280, 28, text: "Hi")
        scaledText.textStyle = EaselTextStyle(textScale: 2)
        #expect(!EaselBoardObjectsTestsSupport.accepts([scaledText]), "Only stickies carry a text scale")
        var hiddenSticky = EaselBoardObjectsTestsSupport.item(.sticky, 0, 0, 220, 220)
        hiddenSticky.contentsHidden = true
        #expect(!EaselBoardObjectsTestsSupport.accepts([hiddenSticky]), "Only sections hide contents")
        let plain = EaselBoardObjectsTestsSupport.document([EaselBoardObjectsTestsSupport.item(.sticky, 0, 0, 220, 220), EaselBoardObjectsTestsSupport.item(.section, 0, 0, 640, 480)])
        let encoded = (try? JSONEncoder().encode(plain)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(!encoded.contains("textScale") && !encoded.contains("contentsHidden"), "Unused fields stay out of the file")
        let decoded = (try? JSONEncoder().encode(EaselBoardObjectsTestsSupport.document([sticky, section])))
            .flatMap { try? JSONDecoder().decode(EaselDocument.self, from: $0) }
        #expect(decoded?.items.first?.textStyle?.textScale == 2 && decoded?.items.last?.contentsHidden == true, "Text scale and hidden contents survive a save")
    }

    @Test
    func aStickyDropsAsACentredTwoHundredTwentyPointSquare() {
        let square = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 300, y: 300), wide: false, zIndex: 3)
        #expect(square.kind == .sticky && square.frame == EaselRect(x: 190, y: 190, width: 220, height: 220) && square.zIndex == 3, "A sticky drops as a 220 point square centred on the pointer")
    }

    @Test
    func aWideStickyStaysOnTheCanvas() {
        let square = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 300, y: 300), wide: false, zIndex: 3)
        let wide = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 100, y: 50), wide: true, zIndex: 0)
        #expect(wide.frame == EaselRect(x: 0, y: 0, width: 440, height: 220), "A wide sticky is 440 by 220 and stays on the canvas")
        #expect(EaselBoardObjects.isWide(wide) && !EaselBoardObjects.isWide(square), "Wide stickies are told apart from squares")
    }

    @Test
    func stickyHeightFitsTextWithPaddingAndACap() {
        let square = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 300, y: 300), wide: false, zIndex: 3)
        #expect(EaselBoardObjects.stickyHeight(square, textHeight: 80) == 220, "Short text keeps the square height")
        #expect(EaselBoardObjects.stickyHeight(square, textHeight: 300) == 336, "Long text grows the sticky by its padding")
        #expect(EaselBoardObjects.stickyHeight(square, textHeight: .nan) == 220, "Unmeasurable text keeps the minimum")
        for odd in [Double.infinity, 0, -50] {
            #expect(EaselBoardObjects.stickyHeight(square, textHeight: odd) == 220, "A text height of \(odd) keeps the minimum")
        }
        #expect(EaselBoardObjects.stickyHeight(square, textHeight: 1e12) == EaselRect.maximumCoordinate, "Enormous text stops growing the sticky at the largest size the file allows")
    }

    @Test
    func scalingAStickyChangesItsMinimumHeightAndPadding() {
        let square = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 300, y: 300), wide: false, zIndex: 3)
        var scaled = square
        scaled.textStyle = EaselTextStyle(textScale: 2)
        #expect(EaselBoardObjects.stickyMinimumHeight(scaled) == 440 && EaselBoardObjects.stickyInset(scaled) == 36, "Scale grows the minimum height and the padding together")
        #expect(EaselBoardObjects.stickyTextBox(scaled) == EaselRect(x: 226, y: 226, width: 148, height: 148), "Text sits inside the scaled padding")
        #expect(EaselBoardObjects.stickyWidths(scaled) == 440...1760, "Side drags stay between one and four squares wide")
    }

    @Test
    func changingStickyWidthReflowsTextAndKeepsTheCorner() {
        let square = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 300, y: 300), wide: false, zIndex: 3)
        let measure: (EaselItem) -> Double = { 40_000 / $0.frame.width }
        let widened = EaselBoardObjects.widened(square, wide: true, textHeight: measure)
        #expect(widened.frame.width == 440 && widened.frame.height == 220 && widened.frame.x == square.frame.x && widened.frame.y == square.frame.y, "Going wide keeps the top-left corner and rewraps")
        let narrowed = EaselBoardObjects.widened(EaselBoardObjects.widened(square, wide: true, textHeight: { _ in 600 }),
                                                 wide: false, textHeight: { _ in 600 })
        #expect(narrowed.frame.width == 220 && narrowed.frame.height == 636, "Going square rewraps the text taller")
    }

    @Test
    func quickCreateCopiesStickyStyleWithoutItsText() {
        let square = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 300, y: 300), wide: false, zIndex: 3)
        var scaled = square
        scaled.textStyle = EaselTextStyle(textScale: 2)
        let copy = EaselBoardObjects.sticky(origin: EaselPoint(x: 500, y: 40), like: {
            var source = scaled; source.fill = "#AED0E6"; source.frame.width = 600; return source
        }(), zIndex: 9)
        #expect(copy.frame == EaselRect(x: 500, y: 40, width: 600, height: 440) && copy.fill == "#AED0E6"
               && copy.textStyle?.textScale == 2 && copy.text.isEmpty, "Quick create copies the source sticky's colour, width and scale but not its text")
    }

    @Test
    func stickyTextScaleClampsAndOmitsTheDefault() {
        #expect(EaselBoardObjects.scaledStyle(nil, scale: 1) == nil && EaselBoardObjects.scaledStyle(nil, scale: 1.0002) == nil, "Scale one leaves no style behind")
        #expect(EaselBoardObjects.scaledStyle(nil, scale: 20)?.textScale == 8, "Scale is clamped to eight")
    }

    @Test
    func stickiesAndSectionsDoNotRotateOrFlip() {
        #expect(!EaselBoardObjects.transforms(.sticky) && !EaselBoardObjects.transforms(.section) && EaselBoardObjects.transforms(.rectangle), "Stickies and sections never rotate or flip")
    }

    @Test
    func sideDragsClampStickyWidthWithoutScalingText() {
        let original = EaselBoardObjectsTestsSupport.item(.sticky, 100, 100, 220, 220)
        let measure: (EaselItem) -> Double = { 30_000 / $0.frame.width }
        var proposed = original
        proposed.frame = EaselRect(x: 100, y: 100, width: 1200, height: 220)
        let widened = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .right, alone: true, textHeight: measure)
        #expect(widened.frame == EaselRect(x: 100, y: 100, width: 880, height: 220) && widened.textStyle == nil, "A side drag widens up to 880 points without scaling the text")
        proposed.frame = EaselRect(x: 250, y: 100, width: 70, height: 220)
        let narrowed = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .left, alone: true, textHeight: measure)
        #expect(narrowed.frame == EaselRect(x: 100, y: 100, width: 220, height: 220), "A side drag never goes narrower than a square")
    }

    @Test
    func rewrappingAStickyRefitsItsHeight() {
        let original = EaselBoardObjectsTestsSupport.item(.sticky, 100, 100, 220, 220)
        let tall: (EaselItem) -> Double = { 60_000 / $0.frame.width }
        let rewrapped = EaselBoardObjects.resizedSticky(original, proposed: original, handle: .left, alone: true, textHeight: tall)
        #expect(rewrapped.frame.height == 309 && rewrapped.frame.x == 100, "Rewrapping refits the height")
    }

    @Test
    func cornerDragsScaleTheStickyAndItsTextTogether() {
        let original = EaselBoardObjectsTestsSupport.item(.sticky, 100, 100, 220, 220)
        var proposed = original
        proposed.frame = EaselRect(x: 100, y: 100, width: 440, height: 440)
        let scaled = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .bottomRight, alone: true,
                                                     textHeight: { 100 * EaselBoardObjects.textScale($0) })
        #expect(scaled.frame == EaselRect(x: 100, y: 100, width: 440, height: 440) && scaled.textStyle?.textScale == 2, "A corner drag scales the sticky and its text together")
        proposed.frame = EaselRect(x: 210, y: 210, width: 110, height: 110)
        let shrunk = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .topLeft, alone: true,
                                                     textHeight: { 100 * EaselBoardObjects.textScale($0) })
        #expect(shrunk.frame == EaselRect(x: 210, y: 210, width: 110, height: 110) && shrunk.textStyle?.textScale == 0.5, "A top-left corner drag keeps the bottom-right corner fixed")
    }

    @Test
    func cornerScalingStopsAtAQuarterOrEightTimes() {
        let original = EaselBoardObjectsTestsSupport.item(.sticky, 100, 100, 220, 220)
        var proposed = original
        proposed.frame = EaselRect(x: 100, y: 100, width: 1, height: 1)
        let tiny = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .bottomRight, alone: true,
                                                   textHeight: { _ in 0 })
        #expect(tiny.textStyle?.textScale == 0.25 && tiny.frame.width == 55, "Scaling stops at a quarter")
        var big = original
        big.textStyle = EaselTextStyle(textScale: 4)
        big.frame = EaselRect(x: 0, y: 0, width: 880, height: 880)
        proposed.frame = EaselRect(x: 0, y: 0, width: 2640, height: 2640)
        let capped = EaselBoardObjects.resizedSticky(big, proposed: proposed, handle: .bottomRight, alone: true,
                                                     textHeight: { _ in 0 })
        #expect(capped.textStyle?.textScale == 8 && capped.frame.width == 1760 && capped.frame.height == 1760, "Scaling stops at eight times")
    }

    @Test
    func verticalEdgeDragsKeepTheAutomaticHeight() {
        let original = EaselBoardObjectsTestsSupport.item(.sticky, 100, 100, 220, 220)
        let measure: (EaselItem) -> Double = { 30_000 / $0.frame.width }
        var proposed = original
        proposed.frame = EaselRect(x: 100, y: 40, width: 220, height: 280)
        let top = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .top, alone: true, textHeight: measure)
        #expect(top.frame == original.frame, "Top and bottom drags leave the automatic height alone")
    }

    @Test
    func groupResizeKeepsTheStickyAtItsMappedPosition() {
        let original = EaselBoardObjectsTestsSupport.item(.sticky, 100, 100, 220, 220)
        var proposed = original
        proposed.frame = EaselRect(x: 300, y: 260, width: 330, height: 330)
        let grouped = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .bottomRight, alone: false,
                                                      textHeight: { 100 * EaselBoardObjects.textScale($0) })
        #expect(grouped.frame.x == 300 && grouped.frame.y == 260 && grouped.textStyle?.textScale == 1.5, "In a group resize a sticky keeps its mapped place and scales evenly")
    }
}

private extension EaselTextStyle {
    init(textScale: Double) {
        self.init()
        self.textScale = textScale
    }
}
