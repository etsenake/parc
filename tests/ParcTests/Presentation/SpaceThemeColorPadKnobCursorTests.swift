import AppKit
import Testing
import ParcCore
@testable import Parc

extension SpaceThemeColorPadTestsSupport {
    @MainActor
    struct SpaceThemeColorPadKnobCursorTests {
        enum PadSpot: CaseIterable { case background, primary, companion, primaryMirror }

        nonisolated static let cursorButtons = ["Previous color presets", "Next color presets", "Add color", "Remove color", "Light appearance"]

        private func grabAndMove(_ f: SpaceThemeControlTests.Fixture) throws -> NSPoint {
            let primary = try f.drawn(try f.knobs()[0])
            try f.press(f.pad, primary)
            let moved = NSPoint(x: primary.x - 40, y: primary.y - 30)
            f.cursor.current = .arrow
            try f.drag(f.pad, moved)
            return moved
        }

        private func holdKnobOutside(_ f: SpaceThemeControlTests.Fixture) throws -> NSPoint {
            let primary = try f.drawn(try f.knobs()[0])
            let outside = NSPoint(x: -60, y: primary.y)
            try f.press(f.pad, primary)
            try f.drag(f.pad, outside)
            f.pad.mouseExited(with: try SpaceThemeControlTests.edge(.mouseExited, f.pad, outside))
            return outside
        }

        @Test(arguments: PadSpot.allCases)
        func hoveringThePadShowsTheCursorForWhatIsUnderThePointer(spot: PadSpot) throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let knobs = try f.knobs()
            let primary = try f.drawn(knobs[0])
            switch spot {
            case .background: #expect(try f.padCursor(at: NSPoint(x: 12, y: 12)) == .arrow)
            case .primary: #expect(try f.padCursor(at: primary) == .openHand)
            case .companion: #expect(try f.padCursor(at: try f.drawn(knobs[1])) == .openHand)
            case .primaryMirror: #expect(try f.padCursor(at: NSPoint(x: primary.x, y: f.pad.bounds.height - primary.y)) == .arrow)
            }
        }

        @Test(arguments: ["Add color", "Remove color", "Automatic appearance", "Light appearance", "Dark appearance"])
        func aPadButtonShowsThePointingHandFromThePad(name: String) throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let button = try f.control(name)
            let point = f.pad.convert(f.center(button), from: button)
            #expect(try f.padCursor(at: point) == .pointingHand)
        }

        @Test func aFullPaletteDisablesAddColor() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            #expect(!(try f.button("Add color")).isEnabled)
        }

        @Test(arguments: cursorButtons)
        func anEditorButtonRequestsCursorUpdates(name: String) throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let button = try f.control(name)
            button.updateTrackingAreas()
            #expect(button.trackingAreas.contains { $0.options.contains(.cursorUpdate) })
        }

        @Test(arguments: cursorButtons)
        func anEditorButtonShowsThePointingHandEnabledOrNot(name: String) throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let button = try f.control(name)
            try f.cursorUpdate(button, f.center(button))
            #expect(f.cursor.current == .pointingHand)
        }

        @Test func enteringThePadResolvesTheCursorUnderThePointer() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.cursorUpdate(f.pad, try f.drawn(try f.knobs()[0]))
            #expect(f.cursor.current == .openHand)
        }

        @Test func grabbingAKnobShowsTheClosedHand() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            try f.press(f.pad, try f.drawn(try f.knobs()[0]))
            #expect(f.cursor.current == .closedHand)
        }

        @Test func onlyTheGrabbedKnobShowsItsHoverGrowth() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let knobs = try f.knobs()
            try f.press(f.pad, try f.drawn(knobs[0]))
            #expect(knobs[0].transform.m11 > 1)
            #expect(knobs[1].transform.m11 == 1)
        }

        @Test func eachKnobDragChangeRestoresTheClosedHand() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            _ = try grabAndMove(f)
            #expect(f.cursor.current == .closedHand)
        }

        @Test func aCursorUpdateCannotReplaceTheClosedHandMidDrag() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let moved = try grabAndMove(f)
            try f.cursorUpdate(f.pad, moved)
            #expect(f.cursor.current == .closedHand)
        }

        @Test func releasingOnTheKnobShowsTheOpenHand() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let moved = try grabAndMove(f)
            try f.release(f.pad, moved)
            #expect(f.cursor.current == .openHand)
        }

        @Test func aKnobHeldPastThePadsEdgeKeepsItsGrowthAndTheClosedHand() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            _ = try holdKnobOutside(f)
            #expect(try f.knobs()[0].transform.m11 > 1)
            #expect(f.cursor.current == .closedHand)
        }

        @Test func releasingAKnobOutsideThePadRestoresTheArrowAndDropsItsGrowth() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let outside = try holdKnobOutside(f)
            try f.drag(f.pad, outside)
            try f.release(f.pad, outside)
            #expect(f.cursor.current == .arrow)
            #expect(try f.knobs()[0].transform.m11 == 1)
        }
    }
}
