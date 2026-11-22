import AppKit
import Testing
import ParcCore

extension SpaceThemeColorPadTestsSupport {
    @MainActor
    struct SpaceThemeColorPadBackgroundDragTests {
        private func interior(_ f: SpaceThemeControlTests.Fixture) -> NSPoint { NSPoint(x: f.pad.bounds.midX - 30, y: f.pad.bounds.midY + 20) }

        private var corner: NSPoint { NSPoint(x: 4, y: 4) }

        @Test func aBackgroundPressLeavesTheCursorAlone() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.press(f.pad, background)
            #expect(f.cursor.current == .iBeam)
        }

        @Test func aBackgroundDragBringsThePrimaryKnobToThePointer() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.press(f.pad, background)
            try f.drag(f.pad, interior(f))
            #expect(SpaceThemeControlTests.distance(try f.drawn(try f.knobs()[0]), interior(f)) < 0.001)
        }

        @Test func theKnobArrivingUnderABackgroundDragShowsTheOpenHandAndGrows() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.press(f.pad, background)
            try f.drag(f.pad, interior(f))
            #expect(f.cursor.current == .openHand)
            #expect(try f.knobs()[0].transform.m11 > 1)
        }

        @Test func aCursorUpdateDuringABackgroundDragChangesNothing() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.press(f.pad, background)
            try f.drag(f.pad, interior(f))
            f.cursor.current = .iBeam
            try f.cursorUpdate(f.pad, corner)
            #expect(f.cursor.current == .iBeam)
        }

        @Test func pastTheRimABackgroundDragLeavesTheKnobBehindUnderTheArrow() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.press(f.pad, background)
            try f.drag(f.pad, interior(f))
            try f.drag(f.pad, corner)
            #expect(f.cursor.current == .arrow)
            #expect(try f.knobs()[0].transform.m11 == 1)
        }

        @Test func aBackgroundReleaseLeavesTheCursorAlone() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.press(f.pad, background)
            try f.drag(f.pad, interior(f))
            try f.drag(f.pad, corner)
            f.cursor.current = .iBeam
            try f.release(f.pad, corner)
            #expect(f.cursor.current == .iBeam)
        }

        @Test func finishingEditingDuringABackgroundDragDropsTheGrowthAndShowsTheArrow() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.press(f.pad, background)
            try f.drag(f.pad, interior(f))
            f.view.finishEditing()
            #expect(try f.knobs()[0].transform.m11 == 1)
            #expect(f.cursor.current == .arrow)
        }

        @Test func outsideAKeyWindowAPlainClickLeavesTheKnobItMovesUnhoveredAndTheCursorAlone() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let spot = try emptySpot(f)
            try f.click(f.pad, spot)
            #expect(SpaceThemeControlTests.distance(try f.drawn(try f.knobs()[0]), spot) < 0.001)
            #expect(try f.knobs()[0].transform.m11 == 1)
            #expect(f.cursor.current == .iBeam)
        }

        @Test func outsideThePadABackgroundDragShowsNoGrowthAndTheArrow() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.press(f.pad, background)
            try f.drag(f.pad, interior(f))
            try f.drag(f.pad, NSPoint(x: -10, y: f.pad.bounds.midY))
            #expect(try f.knobs()[0].transform.m11 == 1)
            #expect(f.cursor.current == .arrow)
        }

        @Test func grabbingACompanionGrowsThePrimaryThatTakesItsPlace() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let knobs = try f.knobs()
            let companion = try f.drawn(knobs[1])
            try f.move(f.pad, companion)
            try f.press(f.pad, companion)
            #expect(SpaceThemeControlTests.distance(try f.drawn(knobs[0]), companion) < 0.5)
            #expect(knobs[0].transform.m11 > 1)
            #expect(knobs[1].transform.m11 == 1 && knobs[2].transform.m11 == 1)
        }

        @Test func aBackgroundDragOverAddShowsItsPointingHand() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let add = try f.button("Add color")
            try f.press(f.pad, background)
            try f.drag(f.pad, f.pad.convert(f.center(add), from: add))
            #expect(f.cursor.current == .pointingHand)
        }
    }
}
