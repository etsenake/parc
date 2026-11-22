import AppKit
import Testing
import ParcCore
@testable import Parc

extension SpaceThemeColorPadTestsSupport {
    @MainActor
    struct SpaceThemeColorPadEditingTests {
        private func padRight(_ f: SpaceThemeControlTests.Fixture) -> NSPoint { NSPoint(x: f.pad.bounds.width * 0.995, y: f.pad.bounds.midY) }

        private func padDown(_ f: SpaceThemeControlTests.Fixture) -> NSPoint { NSPoint(x: f.pad.bounds.midX, y: f.pad.bounds.height * 0.995) }

        private func completedPadDrag(_ f: SpaceThemeControlTests.Fixture) throws {
            try f.press(f.pad, padRight(f))
            try f.drag(f.pad, padDown(f))
            try f.drag(f.pad, NSPoint(x: -500, y: -500))
            try f.release(f.pad, padDown(f))
        }

        private func linkedTheme() throws -> SpaceTheme {
            let primary = try #require(ThemeColor.hsl(hue: 0, saturation: 0.7, lightness: 0.5, colorSpace: .displayP3))
            var theme = SpaceTheme.singleColor(primary)
            theme.colorCount = 2
            theme.wheel = .complimentary
            return theme
        }

        private func grabLinkedHandle(_ f: SpaceThemeControlTests.Fixture, _ theme: SpaceTheme) throws -> NSPoint {
            let position = SpaceThemeEditorState(theme: theme).normalizedPosition(for: theme.colors[1])
            let pointer = NSPoint(x: (position.x + 1) * f.pad.bounds.midX + 3, y: (position.y + 1) * f.pad.bounds.midY + 2)
            try f.press(f.pad, pointer)
            return pointer
        }

        @Test func aPadPressPreviewsWithoutCommitting() throws {
            let f = try SpaceThemeControlTests.Fixture()
            try f.press(f.pad, padRight(f))
            #expect(f.previews == 1)
            #expect(f.commits == 0)
        }

        @Test func aPadDragBeyondThePadClampsToTheRim() throws {
            let f = try SpaceThemeControlTests.Fixture()
            try f.press(f.pad, padRight(f))
            try f.drag(f.pad, NSPoint(x: -500, y: -500))
            let primary = try #require(f.view.theme.primaryColor)
            #expect(SpaceThemeControlTests.near(primary.hsl.lightness, 0.97))
        }

        @Test func aDuplicatePadReleaseCannotCommitAgain() throws {
            let f = try SpaceThemeControlTests.Fixture()
            try completedPadDrag(f)
            let final = f.view.theme
            try f.release(f.pad, padDown(f))
            #expect(f.commits == 1)
            #expect(f.view.theme == final)
        }

        @Test func oneUndoRestoresTheWholePadDrag() throws {
            let f = try SpaceThemeControlTests.Fixture()
            try completedPadDrag(f)
            f.view.undo(nil)
            #expect(f.view.theme == SpaceTheme())
        }

        @Test func aRetiredPadPointerCannotEditAfterUndo() throws {
            let f = try SpaceThemeControlTests.Fixture()
            try completedPadDrag(f)
            f.view.undo(nil)
            try f.drag(f.pad, padRight(f))
            #expect(f.view.theme == SpaceTheme())
        }

        @Test func aStalePadPointerLeavesRedoIntact() throws {
            let f = try SpaceThemeControlTests.Fixture()
            try completedPadDrag(f)
            let final = f.view.theme
            f.view.undo(nil)
            try f.drag(f.pad, padRight(f))
            f.view.redo(nil)
            #expect(f.view.theme == final)
        }

        @Test func grabbingALinkedHandlePromotesItsColorWithoutAJump() throws {
            let theme = try linkedTheme()
            let f = try SpaceThemeControlTests.Fixture(theme)
            _ = try grabLinkedHandle(f, theme)
            let primary = try #require(f.view.theme.primaryColor)
            #expect(SpaceThemeControlTests.near(primary.hsl.hue, 0.5))
            #expect(SpaceThemeControlTests.near(primary.hsl.lightness, 0.5))
        }

        @Test func linkedHandlePromotionAndItsDragShareOneUndo() throws {
            let theme = try linkedTheme()
            let f = try SpaceThemeControlTests.Fixture(theme)
            let pointer = try grabLinkedHandle(f, theme)
            let translated = NSPoint(x: pointer.x + 12, y: pointer.y + 20)
            try f.drag(f.pad, translated)
            try f.release(f.pad, translated)
            f.view.undo(nil)
            #expect(f.view.theme == theme)
        }

        @Test func anOffAxisHueIsDrawnRightOfAndBelowTheCentre() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme())
            let start = try f.drawn(try f.knobs()[0])
            #expect(start.x > f.pad.bounds.midX)
            #expect(start.y > f.pad.bounds.midY)
        }

        @Test func pressingTheDrawnKnobGrabsItWithoutAJump() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme())
            let knob = try f.knobs()[0]
            let start = try f.drawn(knob)
            try f.press(f.pad, NSPoint(x: start.x + 9, y: start.y + 6))
            #expect(SpaceThemeControlTests.distance(try f.drawn(knob), start) < 0.001)
        }

        struct DragOffset: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let x: Double
            let y: Double

            static let cases: [Self] = [
                .init(testDescription: "30 left and 25 down", x: -30.0, y: -25.0),
                .init(testDescription: "70 left and 45 down", x: -70.0, y: -45.0),
                .init(testDescription: "110 left and 20 down", x: -110.0, y: -20.0),
                .init(testDescription: "150 left and 60 down", x: -150.0, y: -60.0),
            ]
        }

        @Test(arguments: DragOffset.cases)
        func theDrawnKnobKeepsTheGrabOffsetInsideTheRim(_ sample: DragOffset) throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme())
            let knob = try f.knobs()[0]
            let start = try f.drawn(knob)
            let grab = NSPoint(x: start.x + 9, y: start.y + 6)
            try f.press(f.pad, grab)
            let pointer = NSPoint(x: grab.x + sample.x, y: grab.y + sample.y)
            try f.drag(f.pad, pointer)
            #expect(SpaceThemeControlTests.distance(try f.drawn(knob), NSPoint(x: pointer.x - 9, y: pointer.y - 6)) < 0.001)
        }

        @Test func beyondTheRimTheDrawnKnobKeepsThePointersAngleOnTheRim() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme())
            let knob = try f.knobs()[0]
            let start = try f.drawn(knob)
            let grab = NSPoint(x: start.x + 9, y: start.y + 6)
            try f.press(f.pad, grab)
            try f.drag(f.pad, NSPoint(x: grab.x - 400, y: grab.y))
            let center = f.center(f.pad), rim = 0.99 * f.pad.bounds.midX
            let target = NSPoint(x: start.x - 400 - center.x, y: start.y - center.y), length = hypot(target.x, target.y)
            let expected = NSPoint(x: center.x + target.x * rim / length, y: center.y + target.y * rim / length)
            #expect(SpaceThemeControlTests.distance(try f.drawn(knob), expected) < 0.001)
            #expect(SpaceThemeControlTests.near(try #require(f.view.theme.primaryColor).hsl.lightness, 0.97))
        }

        @Test func aVisibleKnobDragCommitsOnce() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme())
            let start = try f.drawn(try f.knobs()[0])
            let grab = NSPoint(x: start.x + 9, y: start.y + 6)
            try f.press(f.pad, grab)
            try f.drag(f.pad, NSPoint(x: grab.x - 70, y: grab.y - 45))
            try f.drag(f.pad, NSPoint(x: grab.x - 400, y: grab.y))
            try f.release(f.pad, NSPoint(x: grab.x - 400, y: grab.y))
            #expect(f.commits == 1)
        }
    }
}
