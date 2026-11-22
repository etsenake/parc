import AppKit
import Testing
import ParcCore
@testable import Parc

extension SpaceThemeColorPadTestsSupport {
    @MainActor
    struct SpaceThemeColorPadButtonHoverTests {
        private struct KnobUnderAdd {
            let add: NSButton
            let addCenter: NSPoint
            let knobEdge: NSPoint
        }

        private func parkKnobUnderAdd(_ f: SpaceThemeControlTests.Fixture) throws -> KnobUnderAdd {
            let add = try f.button("Add color")
            let addCenter = f.pad.convert(f.center(add), from: add)
            try f.press(f.pad, background)
            try f.drag(f.pad, addCenter)
            try f.release(f.pad, addCenter)
            return KnobUnderAdd(add: add, addCenter: addCenter, knobEdge: NSPoint(x: add.frame.maxX + 3, y: addCenter.y))
        }

        private func edgeFill(_ button: NSView) throws -> CGFloat {
            let rep = try SpaceThemeControlTests.snapshot(button)
            return try #require(rep.colorAt(x: 2, y: rep.pixelsHigh / 2)).alphaComponent
        }

        private func hoverRemove(_ f: SpaceThemeControlTests.Fixture) throws -> (remove: NSButton, knobEdge: NSPoint) {
            let parked = try parkKnobUnderAdd(f)
            let remove = try f.button("Remove color")
            remove.mouseEntered(with: try SpaceThemeControlTests.edge(.mouseEntered))
            try f.move(f.pad, background)
            return (remove, parked.knobEdge)
        }

        @Test func thePrimaryKnobCanSitBeneathAdd() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let parked = try parkKnobUnderAdd(f)
            #expect(SpaceThemeControlTests.distance(try f.drawn(try f.knobs()[0]), parked.addCenter) < 0.001)
        }

        @Test func aPadButtonWinsOverAKnobBeneathIt() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let parked = try parkKnobUnderAdd(f)
            #expect(try f.padCursor(at: parked.addCenter) == .pointingHand)
            #expect(try f.knobs()[0].transform.m11 == 1)
        }

        @Test func theKnobOutsideTheButtonsFrameShowsTheOpenHandAndGrows() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let parked = try parkKnobUnderAdd(f)
            #expect(SpaceThemeControlTests.distance(parked.knobEdge, try f.drawn(try f.knobs()[0])) < 22)
            #expect(try f.padCursor(at: parked.knobEdge) == .openHand)
            #expect(try f.knobs()[0].transform.m11 > 1)
        }

        @Test func aHoveredRemoveButtonShowsItsHoverFill() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let hovered = try hoverRemove(f)
            #expect(try edgeFill(hovered.remove) > 0.03)
        }

        @Test func aHoveredKnobTurnsOffTheRemoveButtonsHoverStyle() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let hovered = try hoverRemove(f)
            try f.move(f.pad, hovered.knobEdge)
            #expect(try edgeFill(hovered.remove) < 0.01)
        }

        @Test func leavingTheKnobRestoresTheRemoveButtonsHoverStyle() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let hovered = try hoverRemove(f)
            try f.move(f.pad, hovered.knobEdge)
            try f.move(f.pad, background)
            #expect(try edgeFill(hovered.remove) > 0.03)
        }

        @Test func aPressDraggedOffRemoveDropsItsHover() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let hovered = try hoverRemove(f)
            hovered.remove.highlight(true)
            #expect(try edgeFill(hovered.remove) < 0.01)
        }

        @Test func removeIsHoveredAgainWhenThePointerReturns() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let hovered = try hoverRemove(f)
            hovered.remove.highlight(true)
            hovered.remove.highlight(false)
            hovered.remove.mouseEntered(with: try SpaceThemeControlTests.edge(.mouseEntered))
            #expect(try edgeFill(hovered.remove) > 0.03)
        }

        @Test func aDisabledAddButtonTakesTheClickOverTheKnobBeneathIt() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let parked = try parkKnobUnderAdd(f)
            #expect(f.pad.hitTest(f.pad.convert(parked.addCenter, to: f.view)) === parked.add)
        }

        @Test func aPressOnDisabledAddCannotGrabTheKnobBeneathIt() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let parked = try parkKnobUnderAdd(f)
            let before = f.view.theme, previews = f.previews
            try f.press(parked.add, f.center(parked.add))
            let away = NSPoint(x: parked.addCenter.x - 60, y: parked.addCenter.y - 60)
            try f.drag(f.pad, away)
            try f.release(f.pad, away)
            #expect(f.previews == previews)
            #expect(f.view.theme == before)
        }

        @Test func aButtonHoveredBeforeTheEditorLeftItsWindowShowsNoHoverAfterwards() throws {
            let f = try SpaceThemeControlTests.Fixture(try SpaceThemeControlTests.offAxisTheme(colors: 3))
            let hovered = try hoverRemove(f)
            try #require(try edgeFill(hovered.remove) > 0.03)
            let window = NSWindow(contentRect: f.view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = f.view
            window.contentView = nil
            try f.move(f.pad, hovered.knobEdge)
            try f.move(f.pad, background)
            #expect(try edgeFill(hovered.remove) < 0.01)
        }
    }
}
