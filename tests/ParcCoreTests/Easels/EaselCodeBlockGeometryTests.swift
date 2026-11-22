import Foundation
import Testing
@testable import ParcCore

struct EaselCodeBlockGeometryTests {
    @Test
    func aTypedCodeBlockStartsInTheMiddleOfTheView() {
        let visible = EaselRect(x: 100, y: 200, width: 800, height: 600)
        let origin = EaselCodeBlock.placedOrigin(in: visible, width: 440, height: 136, occupied: [])
        #expect(origin.x == 280 && origin.y == 320, "a typed code block lands in the middle of the view")
    }

    @Test
    func aSecondCodeBlockCascadesPastTheFirst() {
        let visible = EaselRect(x: 100, y: 200, width: 800, height: 600)
        let cascaded = EaselCodeBlock.placedOrigin(in: visible, width: 440, height: 136,
                                                   occupied: [.init(x: 280, y: 320, width: 440, height: 136)])
        #expect(cascaded.x == 304 && cascaded.y == 344, "a second block cascades instead of hiding the first")
    }

    @Test
    func aFollowingCodeBlockSitsBelowItsSource() {
        let source = EaselRect(x: 50, y: 60, width: 300, height: 100)
        let below = EaselCodeBlock.originBelow(source, height: 136, occupied: [source])
        #expect(below.x == 50 && below.y == 184, "the next block sits just below")
    }

    @Test
    func aFollowingCodeBlockSkipsPastOccupiedSpace() {
        let source = EaselRect(x: 50, y: 60, width: 300, height: 100)
        let blocker = EaselRect(x: 80, y: 190, width: 100, height: 50)
        let skipped = EaselCodeBlock.originBelow(source, height: 136, occupied: [source, blocker])
        #expect(skipped.y == 264, "the next block skips past anything already below")
    }

    @Test
    func resizingKeepsTheTopAndFitsTheLines() {
        let original = EaselRect(x: 100, y: 100, width: 400, height: 136)
        let wider = EaselCodeBlock.settledFrame(.init(x: 100, y: 90, width: 500, height: 300), original: original, lines: 5, keepsTop: true)
        #expect(wider == EaselRect(x: 100, y: 100, width: 500, height: EaselCodeBlock.height(lines: 5)), "height follows the lines and the top stays put")
    }

    @Test
    func narrowingFromTheLeftKeepsTheRightEdge() {
        let original = EaselRect(x: 100, y: 100, width: 400, height: 136)
        let narrow = EaselCodeBlock.settledFrame(.init(x: 450, y: 100, width: 50, height: 136), original: original, lines: 9, keepsTop: true)
        #expect(narrow.x == 340 && narrow.width == EaselCodeBlock.minimumWidth, "narrowing from the left keeps the right edge at the minimum width")
    }

    @Test
    func groupTransformsKeepTheCodeBlocksPlacement() {
        let original = EaselRect(x: 100, y: 100, width: 400, height: 136)
        let moved = EaselCodeBlock.settledFrame(.init(x: 140, y: 160, width: 400, height: 136), original: original, lines: 4, keepsTop: false)
        #expect(moved.y == 160 && moved.x == 140, "group transforms keep their placement")
    }
}
