import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore

extension MiniPlayerTestsSupport {
    struct MiniPlayerVolumeDismissalTests {
        @MainActor private func open() throws -> MiniPlayerFixture {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.deck.updateHover(true)
            try fixture.toggleVolume(in: "a")
            return fixture
        }

        @MainActor private func click(in view: NSView, window: NSWindow) throws -> NSEvent {
            let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            return try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }

        @MainActor @Test(arguments: [false, true])
        func aClickOnTheVolumeControlsLeavesDismissalToTheControl(_ slider: Bool) throws {
            let fixture = try open()
            let row = try fixture.row("a")
            let control: NSView = slider ? try fixture.volume(in: "a") : try fixture.button("Adjust Tab Volume")
            var didSchedule = false
            row.scheduleVolumeLayout = { _ in didSchedule = true }
            row.closeVolume(clickedBy: try click(in: control, window: fixture.window))
            #expect(!didSchedule)
            #expect(fixture.deck.desiredHeight == 99)
        }

        @MainActor @Test func clickingAwayKeepsTheVolumeLayoutUntilTheDispatchFinishes() throws {
            let fixture = try open()
            let row = try fixture.row("a")
            let title = try fixture.button("Back to Tab — a")
            var pending: (@MainActor () -> Void)?
            row.scheduleVolumeLayout = { pending = $0 }
            row.closeVolume(clickedBy: try click(in: title, window: fixture.window))
            #expect(fixture.deck.desiredHeight == 99)
            let apply = try #require(pending)
            apply()
            fixture.layout()
            #expect(fixture.deck.desiredHeight == 66)
        }

        @MainActor @Test func escapeClosesTheVolume() throws {
            let fixture = try open()
            let row = try fixture.row("a")
            try #require(fixture.window.makeFirstResponder(row))
            #expect(try row.closeVolume(escape: fixture.key(53, "\u{1b}")))
            fixture.layout()
            #expect(fixture.deck.desiredHeight == 66)
        }
    }
}
