import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct NoteFormatBarModelTestsPlacement {
    private let visible = NSRect(x: 0, y: 100, width: 800, height: 600)

    private let size = NSSize(width: 300, height: 34)

    private func place(_ rects: [NSRect], in area: NSRect? = nil) -> NoteFormatBarPlacement? {
        NoteFormatBarPlacement.compute(lineRects: rects, size: size, visible: area ?? visible)
    }

    @Test func aSelectionWithRoomAboveGetsTheBarAboveIt() {
        let above = place([NSRect(x: 200, y: 400, width: 120, height: 22)])
        #expect(above?.edge == .above)
        #expect(above?.frame.maxY == 400 - NoteFormatBarPlacement.gap)
    }

    @Test func theBarCentresOnTheSelectionsTopLine() {
        #expect(place([NSRect(x: 200, y: 400, width: 120, height: 22)])?.frame.midX == 260)
    }

    @Test func aWrappedSelectionCentresOnItsFirstLineNotTheWholeBlock() {
        let paragraph = [NSRect(x: 300, y: 400, width: 400, height: 22), NSRect(x: 40, y: 422, width: 660, height: 22),
                         NSRect(x: 40, y: 444, width: 80, height: 22)]
        #expect(place(paragraph)?.frame.midX == 500)
    }

    private let nearTop = [NSRect(x: 200, y: 120, width: 120, height: 22), NSRect(x: 40, y: 142, width: 200, height: 22)]

    @Test func noRoomAboveFlipsTheBarBelow() {
        #expect(place(nearTop)?.edge == .below)
    }

    @Test func theFlippedBarHangsBelowTheLastLine() {
        #expect(place(nearTop)?.frame.minY == 164 + NoteFormatBarPlacement.gap)
    }

    @Test func theFlippedBarCentresOnTheLastLineClamped() {
        let flipped = place(nearTop)
        #expect(flipped?.frame.midX == 150 || flipped?.frame.minX == NoteFormatBarPlacement.margin)
    }

    @Test func aSelectionTallerThanTheViewPinsTheBarToTheTop() {
        let pinned = place([NSRect(x: 100, y: 50, width: 500, height: 22), NSRect(x: 100, y: 900, width: 500, height: 22)])
        #expect(pinned?.edge == .pinned)
        #expect(pinned?.frame.minY == 108)
    }

    @Test func theBarNeverPokesPastTheLeftEdge() {
        #expect(place([NSRect(x: 2, y: 400, width: 30, height: 22)])?.frame.minX == NoteFormatBarPlacement.margin)
    }

    @Test func theBarNeverPokesPastTheRightEdge() {
        #expect(place([NSRect(x: 770, y: 400, width: 28, height: 22)])?.frame.maxX == 800 - NoteFormatBarPlacement.margin)
    }

    @Test func aSelectionScrolledOutOfViewHidesTheBar() {
        #expect(place([NSRect(x: 100, y: 1200, width: 50, height: 22)]) == nil)
    }

    @Test func noRectsNoBar() {
        #expect(place([]) == nil)
    }

    @Test func aBarWiderThanTheViewHugsTheLeadingEdge() {
        let squeezed = place([NSRect(x: 50, y: 200, width: 40, height: 20)], in: NSRect(x: 0, y: 0, width: 200, height: 400))
        #expect(squeezed?.frame.minX == NoteFormatBarPlacement.margin)
    }

    private func dropdown(anchor: NSRect, size: NSSize = NSSize(width: 240, height: 300)) -> NoteFormatBarPlacement {
        NoteFormatBarPlacement.dropdown(anchor: anchor, size: size, visible: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func dropdownsOpenBelowTheirButton() {
        let below = dropdown(anchor: NSRect(x: 100, y: 100, width: 80, height: 28))
        #expect(below.edge == .below)
        #expect(below.frame.minY == 134)
        #expect(below.frame.minX == 100)
    }

    @Test func dropdownsFlipAboveWhenTheBottomIsTight() {
        let above = dropdown(anchor: NSRect(x: 100, y: 500, width: 80, height: 28))
        #expect(above.edge == .above)
        #expect(above.frame.maxY == 494)
    }

    @Test func dropdownsStayInsideTheRightEdge() {
        #expect(dropdown(anchor: NSRect(x: 700, y: 100, width: 80, height: 28)).frame.maxX == 792)
    }

    @Test func aDropdownTooTallForEitherSideStaysOnScreen() {
        let cramped = dropdown(anchor: NSRect(x: 100, y: 280, width: 80, height: 28), size: NSSize(width: 240, height: 500))
        #expect(cramped.frame.minY >= 8 && cramped.frame.maxY <= 600 || cramped.frame.minY == 8)
    }
}
