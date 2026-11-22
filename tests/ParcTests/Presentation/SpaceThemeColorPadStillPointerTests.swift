import AppKit
import Testing
import ParcCore
@testable import ParcSidebar

extension SpaceThemeColorPadTestsSupport {
    @MainActor
    struct SpaceThemeColorPadStillPointerTests {
        private struct StillPointer {
            let fixture: SpaceThemeControlTests.Fixture
            let window: SpaceThemeControlTests.KeyHostWindow
            let theme: SpaceTheme
            let knob: CALayer
        }

        private func stillPointer() throws -> StillPointer {
            let theme = try SpaceThemeControlTests.offAxisTheme()
            let f = try SpaceThemeControlTests.Fixture(theme)
            let window = SpaceThemeControlTests.KeyHostWindow(contentRect: f.view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
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
}
