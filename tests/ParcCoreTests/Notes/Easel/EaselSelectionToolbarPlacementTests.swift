import Foundation
import Testing
@testable import ParcCore

struct EaselSelectionToolbarPlacementTests {
    func place(_ selection: EaselRect, visible: EaselRect = EaselRect(x: 0, y: 0, width: 800, height: 600)) -> EaselSelectionToolbarPlacement? {
        EaselSelectionToolbarPlacement.place(selection: selection, width: 200, height: 36, visible: visible)
    }

    func clear(_ placement: EaselSelectionToolbarPlacement?, of selection: EaselRect) -> Bool {
        guard let frame = placement?.frame else { return false }
        return frame.x + frame.width <= selection.x || frame.x >= selection.x + selection.width
            || frame.y + frame.height <= selection.y || frame.y >= selection.y + selection.height
    }

    @Test
    func roomAbovePutsTheToolbarEightPointsOver() {
        let middle = EaselRect(x: 300, y: 200, width: 200, height: 100)
        let above = place(middle)
        #expect(above?.edge == .above && above?.frame.y == 156 && above?.frame.x == 300, "Room above puts the toolbar eight points over the selection, centred")
    }

    @Test
    func theToolbarMovesBelowWhenThereIsNoRoomAbove() {
        let top = EaselRect(x: 300, y: 20, width: 200, height: 100)
        let below = place(top)
        #expect(below?.edge == .below && below?.frame.y == 128, "No room above drops the toolbar eight points below")
    }

    @Test
    func theToolbarStaysInsideTheViewHorizontally() {
        let left = place(EaselRect(x: -150, y: 200, width: 200, height: 100))
        #expect(left?.frame.x == 8, "The toolbar stays inside the visible area when the selection runs off its edge")
    }

    @Test
    func aTallSelectionGetsTheToolbarBesideIt() {
        let tall = EaselRect(x: 100, y: -50, width: 200, height: 700)
        let beside = place(tall)
        #expect(beside?.edge == .inside && clear(beside, of: tall), "A selection taller than the view gets the toolbar beside it, not on top of it")
    }

    @Test
    func aWideSelectionGetsTheToolbarInTheFreeStrip() {
        let wide = EaselRect(x: -50, y: -48, width: 900, height: 600)
        let strip = place(wide)
        #expect(strip?.edge == .inside && clear(strip, of: wide) && strip?.frame.y == 556, "A selection filling the width keeps the toolbar in the free strip under it")
    }

    @Test
    func aSelectionCoveringTheViewPinsItsToolbarAtTheTop() {
        let full = EaselRect(x: -100, y: -100, width: 1000, height: 800)
        let pinned = place(full)
        #expect(pinned?.edge == .inside && pinned?.frame.y == 8 && pinned?.frame.x == 300, "A selection covering the whole view pins the toolbar to the top centre")
    }

    @Test
    func aSelectionOutsideTheViewHasNoToolbar() {
        #expect(place(EaselRect(x: 900, y: 900, width: 50, height: 50)) == nil, "A selection scrolled out of view parks the toolbar")
    }

    @Test
    func anEmptyToolbarNeverPlaces() {
        let middle = EaselRect(x: 300, y: 200, width: 200, height: 100)
        #expect(EaselSelectionToolbarPlacement.place(selection: middle, width: 0, height: 36,
                                                     visible: EaselRect(x: 0, y: 0, width: 800, height: 600)) == nil, "An empty toolbar never places")
    }
}
