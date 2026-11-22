import AppKit
import Testing
import ParcCore
@testable import Parc

extension SpaceThemeControlTests {
    private func padRight(_ f: Fixture) -> NSPoint { NSPoint(x: f.pad.bounds.width * 0.995, y: f.pad.bounds.midY) }
    private func padDown(_ f: Fixture) -> NSPoint { NSPoint(x: f.pad.bounds.midX, y: f.pad.bounds.height * 0.995) }

    private func completedPadDrag(_ f: Fixture) throws {
        try f.press(f.pad, padRight(f))
        try f.drag(f.pad, padDown(f))
        try f.drag(f.pad, NSPoint(x: -500, y: -500))
        try f.release(f.pad, padDown(f))
    }

    @Test func aPadPressPreviewsWithoutCommitting() throws {
        let f = try Fixture()
        try f.press(f.pad, padRight(f))
        #expect(f.previews == 1)
        #expect(f.commits == 0)
    }

    @Test func aPadDragBeyondThePadClampsToTheRim() throws {
        let f = try Fixture()
        try f.press(f.pad, padRight(f))
        try f.drag(f.pad, NSPoint(x: -500, y: -500))
        let primary = try #require(f.view.theme.primaryColor)
        #expect(Self.near(primary.hsl.lightness, 0.97))
    }

    @Test func aDuplicatePadReleaseCannotCommitAgain() throws {
        let f = try Fixture()
        try completedPadDrag(f)
        let final = f.view.theme
        try f.release(f.pad, padDown(f))
        #expect(f.commits == 1)
        #expect(f.view.theme == final)
    }

    @Test func oneUndoRestoresTheWholePadDrag() throws {
        let f = try Fixture()
        try completedPadDrag(f)
        f.view.undo(nil)
        #expect(f.view.theme == SpaceTheme())
    }

    @Test func aRetiredPadPointerCannotEditAfterUndo() throws {
        let f = try Fixture()
        try completedPadDrag(f)
        f.view.undo(nil)
        try f.drag(f.pad, padRight(f))
        #expect(f.view.theme == SpaceTheme())
    }

    @Test func aStalePadPointerLeavesRedoIntact() throws {
        let f = try Fixture()
        try completedPadDrag(f)
        let final = f.view.theme
        f.view.undo(nil)
        try f.drag(f.pad, padRight(f))
        f.view.redo(nil)
        #expect(f.view.theme == final)
    }

    private func linkedTheme() throws -> SpaceTheme {
        let primary = try #require(ThemeColor.hsl(hue: 0, saturation: 0.7, lightness: 0.5, colorSpace: .displayP3))
        var theme = SpaceTheme.singleColor(primary)
        theme.colorCount = 2
        theme.wheel = .complimentary
        return theme
    }

    private func grabLinkedHandle(_ f: Fixture, _ theme: SpaceTheme) throws -> NSPoint {
        let position = SpaceThemeEditorState(theme: theme).normalizedPosition(for: theme.colors[1])
        let pointer = NSPoint(x: (position.x + 1) * f.pad.bounds.midX + 3, y: (position.y + 1) * f.pad.bounds.midY + 2)
        try f.press(f.pad, pointer)
        return pointer
    }

    @Test func grabbingALinkedHandlePromotesItsColorWithoutAJump() throws {
        let theme = try linkedTheme()
        let f = try Fixture(theme)
        _ = try grabLinkedHandle(f, theme)
        let primary = try #require(f.view.theme.primaryColor)
        #expect(Self.near(primary.hsl.hue, 0.5))
        #expect(Self.near(primary.hsl.lightness, 0.5))
    }

    @Test func linkedHandlePromotionAndItsDragShareOneUndo() throws {
        let theme = try linkedTheme()
        let f = try Fixture(theme)
        let pointer = try grabLinkedHandle(f, theme)
        let translated = NSPoint(x: pointer.x + 12, y: pointer.y + 20)
        try f.drag(f.pad, translated)
        try f.release(f.pad, translated)
        f.view.undo(nil)
        #expect(f.view.theme == theme)
    }

    @Test func anOffAxisHueIsDrawnRightOfAndBelowTheCentre() throws {
        let f = try Fixture(try Self.offAxisTheme())
        let start = try f.drawn(try f.knobs()[0])
        #expect(start.x > f.pad.bounds.midX)
        #expect(start.y > f.pad.bounds.midY)
    }

    @Test func pressingTheDrawnKnobGrabsItWithoutAJump() throws {
        let f = try Fixture(try Self.offAxisTheme())
        let knob = try f.knobs()[0]
        let start = try f.drawn(knob)
        try f.press(f.pad, NSPoint(x: start.x + 9, y: start.y + 6))
        #expect(Self.distance(try f.drawn(knob), start) < 0.001)
    }

    @Test(arguments: [(-30.0, -25.0), (-70.0, -45.0), (-110.0, -20.0), (-150.0, -60.0)])
    func theDrawnKnobKeepsTheGrabOffsetInsideTheRim(delta: (Double, Double)) throws {
        let f = try Fixture(try Self.offAxisTheme())
        let knob = try f.knobs()[0]
        let start = try f.drawn(knob)
        let grab = NSPoint(x: start.x + 9, y: start.y + 6)
        try f.press(f.pad, grab)
        let pointer = NSPoint(x: grab.x + delta.0, y: grab.y + delta.1)
        try f.drag(f.pad, pointer)
        #expect(Self.distance(try f.drawn(knob), NSPoint(x: pointer.x - 9, y: pointer.y - 6)) < 0.001)
    }

    @Test func beyondTheRimTheDrawnKnobKeepsThePointersAngleOnTheRim() throws {
        let f = try Fixture(try Self.offAxisTheme())
        let knob = try f.knobs()[0]
        let start = try f.drawn(knob)
        let grab = NSPoint(x: start.x + 9, y: start.y + 6)
        try f.press(f.pad, grab)
        try f.drag(f.pad, NSPoint(x: grab.x - 400, y: grab.y))
        let center = f.center(f.pad), rim = 0.99 * f.pad.bounds.midX
        let target = NSPoint(x: start.x - 400 - center.x, y: start.y - center.y), length = hypot(target.x, target.y)
        let expected = NSPoint(x: center.x + target.x * rim / length, y: center.y + target.y * rim / length)
        #expect(Self.distance(try f.drawn(knob), expected) < 0.001)
        #expect(Self.near(try #require(f.view.theme.primaryColor).hsl.lightness, 0.97))
    }

    @Test func aVisibleKnobDragCommitsOnce() throws {
        let f = try Fixture(try Self.offAxisTheme())
        let start = try f.drawn(try f.knobs()[0])
        let grab = NSPoint(x: start.x + 9, y: start.y + 6)
        try f.press(f.pad, grab)
        try f.drag(f.pad, NSPoint(x: grab.x - 70, y: grab.y - 45))
        try f.drag(f.pad, NSPoint(x: grab.x - 400, y: grab.y))
        try f.release(f.pad, NSPoint(x: grab.x - 400, y: grab.y))
        #expect(f.commits == 1)
    }

    enum PadSpot: CaseIterable { case background, primary, companion, primaryMirror }

    @Test(arguments: PadSpot.allCases)
    func hoveringThePadShowsTheCursorForWhatIsUnderThePointer(spot: PadSpot) throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
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
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let button = try f.control(name)
        let point = f.pad.convert(f.center(button), from: button)
        #expect(try f.padCursor(at: point) == .pointingHand)
    }

    @Test func aFullPaletteDisablesAddColor() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        #expect(!(try f.button("Add color")).isEnabled)
    }

    nonisolated static let cursorButtons = ["Previous color presets", "Next color presets", "Add color", "Remove color", "Light appearance"]

    @Test(arguments: cursorButtons)
    func anEditorButtonRequestsCursorUpdates(name: String) throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let button = try f.control(name)
        button.updateTrackingAreas()
        #expect(button.trackingAreas.contains { $0.options.contains(.cursorUpdate) })
    }

    @Test(arguments: cursorButtons)
    func anEditorButtonShowsThePointingHandEnabledOrNot(name: String) throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let button = try f.control(name)
        try f.cursorUpdate(button, f.center(button))
        #expect(f.cursor.current == .pointingHand)
    }

    @Test func enteringThePadResolvesTheCursorUnderThePointer() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.cursorUpdate(f.pad, try f.drawn(try f.knobs()[0]))
        #expect(f.cursor.current == .openHand)
    }

    @Test func grabbingAKnobShowsTheClosedHand() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.press(f.pad, try f.drawn(try f.knobs()[0]))
        #expect(f.cursor.current == .closedHand)
    }

    @Test func onlyTheGrabbedKnobShowsItsHoverGrowth() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let knobs = try f.knobs()
        try f.press(f.pad, try f.drawn(knobs[0]))
        #expect(knobs[0].transform.m11 > 1)
        #expect(knobs[1].transform.m11 == 1)
    }

    private func grabAndMove(_ f: Fixture) throws -> NSPoint {
        let primary = try f.drawn(try f.knobs()[0])
        try f.press(f.pad, primary)
        let moved = NSPoint(x: primary.x - 40, y: primary.y - 30)
        f.cursor.current = .arrow
        try f.drag(f.pad, moved)
        return moved
    }

    @Test func eachKnobDragChangeRestoresTheClosedHand() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        _ = try grabAndMove(f)
        #expect(f.cursor.current == .closedHand)
    }

    @Test func aCursorUpdateCannotReplaceTheClosedHandMidDrag() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let moved = try grabAndMove(f)
        try f.cursorUpdate(f.pad, moved)
        #expect(f.cursor.current == .closedHand)
    }

    @Test func releasingOnTheKnobShowsTheOpenHand() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let moved = try grabAndMove(f)
        try f.release(f.pad, moved)
        #expect(f.cursor.current == .openHand)
    }

    private func holdKnobOutside(_ f: Fixture) throws -> NSPoint {
        let primary = try f.drawn(try f.knobs()[0])
        let outside = NSPoint(x: -60, y: primary.y)
        try f.press(f.pad, primary)
        try f.drag(f.pad, outside)
        f.pad.mouseExited(with: try Self.edge(.mouseExited, f.pad, outside))
        return outside
    }

    @Test func aKnobHeldPastThePadsEdgeKeepsItsGrowthAndTheClosedHand() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        _ = try holdKnobOutside(f)
        #expect(try f.knobs()[0].transform.m11 > 1)
        #expect(f.cursor.current == .closedHand)
    }

    @Test func releasingAKnobOutsideThePadRestoresTheArrowAndDropsItsGrowth() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let outside = try holdKnobOutside(f)
        try f.drag(f.pad, outside)
        try f.release(f.pad, outside)
        #expect(f.cursor.current == .arrow)
        #expect(try f.knobs()[0].transform.m11 == 1)
    }

    private var background: NSPoint { NSPoint(x: 12, y: 12) }
    private func interior(_ f: Fixture) -> NSPoint { NSPoint(x: f.pad.bounds.midX - 30, y: f.pad.bounds.midY + 20) }
    private var corner: NSPoint { NSPoint(x: 4, y: 4) }

    @Test func aBackgroundPressLeavesTheCursorAlone() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.press(f.pad, background)
        #expect(f.cursor.current == .iBeam)
    }

    @Test func aBackgroundDragBringsThePrimaryKnobToThePointer() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.press(f.pad, background)
        try f.drag(f.pad, interior(f))
        #expect(Self.distance(try f.drawn(try f.knobs()[0]), interior(f)) < 0.001)
    }

    @Test func theKnobArrivingUnderABackgroundDragShowsTheOpenHandAndGrows() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.press(f.pad, background)
        try f.drag(f.pad, interior(f))
        #expect(f.cursor.current == .openHand)
        #expect(try f.knobs()[0].transform.m11 > 1)
    }

    @Test func aCursorUpdateDuringABackgroundDragChangesNothing() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.press(f.pad, background)
        try f.drag(f.pad, interior(f))
        f.cursor.current = .iBeam
        try f.cursorUpdate(f.pad, corner)
        #expect(f.cursor.current == .iBeam)
    }

    @Test func pastTheRimABackgroundDragLeavesTheKnobBehindUnderTheArrow() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.press(f.pad, background)
        try f.drag(f.pad, interior(f))
        try f.drag(f.pad, corner)
        #expect(f.cursor.current == .arrow)
        #expect(try f.knobs()[0].transform.m11 == 1)
    }

    @Test func aBackgroundReleaseLeavesTheCursorAlone() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.press(f.pad, background)
        try f.drag(f.pad, interior(f))
        try f.drag(f.pad, corner)
        f.cursor.current = .iBeam
        try f.release(f.pad, corner)
        #expect(f.cursor.current == .iBeam)
    }

    @Test func finishingEditingDuringABackgroundDragDropsTheGrowthAndShowsTheArrow() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.press(f.pad, background)
        try f.drag(f.pad, interior(f))
        f.view.finishEditing()
        #expect(try f.knobs()[0].transform.m11 == 1)
        #expect(f.cursor.current == .arrow)
    }

    private func emptySpot(_ f: Fixture) throws -> NSPoint {
        let knobs = try f.knobs().map { try f.drawn($0) }
        let candidates = stride(from: 60.0, through: f.pad.bounds.width - 60, by: 20).flatMap { x in
            stride(from: 80.0, through: f.pad.bounds.height - 80, by: 20).map { NSPoint(x: x, y: $0) }
        }
        return try #require(candidates.first { point in knobs.allSatisfy { Self.distance($0, point) > 60 } })
    }

    @Test func outsideAKeyWindowAPlainClickLeavesTheKnobItMovesUnhoveredAndTheCursorAlone() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let spot = try emptySpot(f)
        try f.click(f.pad, spot)
        #expect(Self.distance(try f.drawn(try f.knobs()[0]), spot) < 0.001)
        #expect(try f.knobs()[0].transform.m11 == 1)
        #expect(f.cursor.current == .iBeam)
    }

    @Test func outsideThePadABackgroundDragShowsNoGrowthAndTheArrow() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        try f.press(f.pad, background)
        try f.drag(f.pad, interior(f))
        try f.drag(f.pad, NSPoint(x: -10, y: f.pad.bounds.midY))
        #expect(try f.knobs()[0].transform.m11 == 1)
        #expect(f.cursor.current == .arrow)
    }

    @Test func grabbingACompanionGrowsThePrimaryThatTakesItsPlace() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let knobs = try f.knobs()
        let companion = try f.drawn(knobs[1])
        try f.move(f.pad, companion)
        try f.press(f.pad, companion)
        #expect(Self.distance(try f.drawn(knobs[0]), companion) < 0.5)
        #expect(knobs[0].transform.m11 > 1)
        #expect(knobs[1].transform.m11 == 1 && knobs[2].transform.m11 == 1)
    }

    @Test func aBackgroundDragOverAddShowsItsPointingHand() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let add = try f.button("Add color")
        try f.press(f.pad, background)
        try f.drag(f.pad, f.pad.convert(f.center(add), from: add))
        #expect(f.cursor.current == .pointingHand)
    }

    private struct KnobUnderAdd {
        let add: NSButton
        let addCenter: NSPoint
        let knobEdge: NSPoint
    }

    private func parkKnobUnderAdd(_ f: Fixture) throws -> KnobUnderAdd {
        let add = try f.button("Add color")
        let addCenter = f.pad.convert(f.center(add), from: add)
        try f.press(f.pad, background)
        try f.drag(f.pad, addCenter)
        try f.release(f.pad, addCenter)
        return KnobUnderAdd(add: add, addCenter: addCenter, knobEdge: NSPoint(x: add.frame.maxX + 3, y: addCenter.y))
    }

    @Test func thePrimaryKnobCanSitBeneathAdd() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let parked = try parkKnobUnderAdd(f)
        #expect(Self.distance(try f.drawn(try f.knobs()[0]), parked.addCenter) < 0.001)
    }

    @Test func aPadButtonWinsOverAKnobBeneathIt() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let parked = try parkKnobUnderAdd(f)
        #expect(try f.padCursor(at: parked.addCenter) == .pointingHand)
        #expect(try f.knobs()[0].transform.m11 == 1)
    }

    @Test func theKnobOutsideTheButtonsFrameShowsTheOpenHandAndGrows() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let parked = try parkKnobUnderAdd(f)
        #expect(Self.distance(parked.knobEdge, try f.drawn(try f.knobs()[0])) < 22)
        #expect(try f.padCursor(at: parked.knobEdge) == .openHand)
        #expect(try f.knobs()[0].transform.m11 > 1)
    }

    private func edgeFill(_ button: NSView) throws -> CGFloat {
        let rep = try Self.snapshot(button)
        return try #require(rep.colorAt(x: 2, y: rep.pixelsHigh / 2)).alphaComponent
    }

    private func hoverRemove(_ f: Fixture) throws -> (remove: NSButton, knobEdge: NSPoint) {
        let parked = try parkKnobUnderAdd(f)
        let remove = try f.button("Remove color")
        remove.mouseEntered(with: try Self.edge(.mouseEntered))
        try f.move(f.pad, background)
        return (remove, parked.knobEdge)
    }

    @Test func aHoveredRemoveButtonShowsItsHoverFill() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let hovered = try hoverRemove(f)
        #expect(try edgeFill(hovered.remove) > 0.03)
    }

    @Test func aHoveredKnobTurnsOffTheRemoveButtonsHoverStyle() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let hovered = try hoverRemove(f)
        try f.move(f.pad, hovered.knobEdge)
        #expect(try edgeFill(hovered.remove) < 0.01)
    }

    @Test func leavingTheKnobRestoresTheRemoveButtonsHoverStyle() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let hovered = try hoverRemove(f)
        try f.move(f.pad, hovered.knobEdge)
        try f.move(f.pad, background)
        #expect(try edgeFill(hovered.remove) > 0.03)
    }

    @Test func aPressDraggedOffRemoveDropsItsHover() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let hovered = try hoverRemove(f)
        hovered.remove.highlight(true)
        #expect(try edgeFill(hovered.remove) < 0.01)
    }

    @Test func removeIsHoveredAgainWhenThePointerReturns() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let hovered = try hoverRemove(f)
        hovered.remove.highlight(true)
        hovered.remove.highlight(false)
        hovered.remove.mouseEntered(with: try Self.edge(.mouseEntered))
        #expect(try edgeFill(hovered.remove) > 0.03)
    }

    @Test func aDisabledAddButtonTakesTheClickOverTheKnobBeneathIt() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
        let parked = try parkKnobUnderAdd(f)
        #expect(f.pad.hitTest(f.pad.convert(parked.addCenter, to: f.view)) === parked.add)
    }

    @Test func aPressOnDisabledAddCannotGrabTheKnobBeneathIt() throws {
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
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
        let f = try Fixture(try Self.offAxisTheme(colors: 3))
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

    private struct StillPointer {
        let fixture: Fixture
        let window: KeyHostWindow
        let theme: SpaceTheme
        let knob: CALayer
    }

    private func stillPointer() throws -> StillPointer {
        let theme = try Self.offAxisTheme()
        let f = try Fixture(theme)
        let window = KeyHostWindow(contentRect: f.view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        f.host(window)
        let knob = try f.knobs()[0]
        let start = try f.drawn(knob)
        window.pointer = f.pad.convert(start, to: nil)
        try f.move(f.pad, start)
        return StillPointer(fixture: f, window: window, theme: theme, knob: knob)
    }

    private func nudgeTowardCentre(_ still: StillPointer) throws {
        let f = still.fixture
        let start = try f.drawn(still.knob)
        let key: UInt16 = start.x > f.pad.bounds.midX ? 123 : 124
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0, windowNumber: 0,
                                                  context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                                  keyCode: key))
        f.pad.keyDown(with: event)
    }

    @Test func theKnobUnderAStillPointerGrowsAndShowsTheOpenHand() throws {
        let still = try stillPointer()
        defer { still.window.contentView = nil }
        #expect(still.knob.transform.m11 > 1)
        #expect(still.fixture.cursor.current == .openHand)
    }

    @Test func arrowKeyNudgesThatCarryTheKnobFromAStillPointerDropItsGrowthAndTheOpenHand() throws {
        let still = try stillPointer()
        defer { still.window.contentView = nil }
        try nudgeTowardCentre(still)
        try nudgeTowardCentre(still)
        #expect(still.knob.transform.m11 == 1)
        #expect(still.fixture.cursor.current == .arrow)
    }

    @Test func aThemeSyncThatBringsTheKnobBackUnderAStillPointerRestoresBoth() throws {
        let still = try stillPointer()
        defer { still.window.contentView = nil }
        try nudgeTowardCentre(still)
        try nudgeTowardCentre(still)
        still.fixture.view.synchronizeTheme(still.theme)
        #expect(still.knob.transform.m11 > 1)
        #expect(still.fixture.cursor.current == .openHand)
    }

    @Test func aThemeSyncThatMovesTheKnobAwayFromAStillPointerDropsBoth() throws {
        let still = try stillPointer()
        defer { still.window.contentView = nil }
        try nudgeTowardCentre(still)
        try nudgeTowardCentre(still)
        let nudged = still.fixture.view.theme
        still.fixture.view.synchronizeTheme(still.theme)
        still.fixture.view.synchronizeTheme(nudged)
        #expect(still.knob.transform.m11 == 1)
        #expect(still.fixture.cursor.current == .arrow)
    }

    @Test func inAKeyWindowAPlainClickShowsTheKnobItBringsUnderTheStillPointer() throws {
        let still = try stillPointer()
        defer { still.window.contentView = nil }
        let f = still.fixture
        let spot = try emptySpot(f)
        still.window.pointer = f.pad.convert(spot, to: nil)
        try f.move(f.pad, spot)
        try f.click(f.pad, spot)
        #expect(still.knob.transform.m11 > 1)
        #expect(f.cursor.current == .openHand)
    }
}
