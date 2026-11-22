import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import ParcCore
@testable import ParcSidebar

extension MiniPlayerTestsSupport {
    struct MiniPlayerFocusTests {
        @MainActor @Test func onlyTheFrontCollapsedCardTakesKeyboardFocus() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            #expect(try fixture.row("a").acceptsFirstResponder)
            #expect(try !fixture.row("b").acceptsFirstResponder)
            #expect(try !fixture.row("b").isHidden)
        }

        @MainActor @Test func focusingTheFrontCardMakesEveryExpandedRowReachable() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            let first = try fixture.row("a"), second = try fixture.row("b")
            try #require(fixture.window.makeFirstResponder(first))
            let chain = SidebarAccessibility.keyViews(in: [fixture.deck], space: fixture.deck)
            #expect(try chain.first === fixture.button("Collapse Mini Players"))
            #expect(chain.contains { $0 === second })
        }

        @MainActor @Test func returnOnTheFocusedRowRevealsItsOriginalTab() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            let row = try fixture.row("a")
            try #require(fixture.window.makeFirstResponder(row))
            row.keyDown(with: try fixture.key(36, "\r"))
            #expect(fixture.revealed == ["a"])
        }

        @MainActor @Test func spaceOnTheFocusedRowPausesItsOriginalMedia() throws {
            let fixture = try MiniPlayerFixture(["a", "b"])
            let row = try fixture.row("a")
            try #require(fixture.window.makeFirstResponder(row))
            row.keyDown(with: try fixture.key(49, " "))
            #expect(fixture.engine("a").actions.map(\.intValue) == [Int(PCNativeMediaAction.pause.rawValue)])
        }

        @MainActor @Test func clickingACardRevealsTheTabWithoutTakingKeyboardFocus() throws {
            let fixture = try MiniPlayerFixture(["a"])
            let row = try fixture.row("a")
            row.initiatingEventType = { .leftMouseDown }
            let former = fixture.window.firstResponder
            let accepted = row.becomeFirstResponder()
            #expect(!accepted)
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            row.mouseDown(with: event)
            #expect(fixture.revealed == ["a"] && fixture.window.firstResponder === former)
        }

        @MainActor @Test func tabCanFocusACard() throws {
            let fixture = try MiniPlayerFixture(["a"])
            let row = try fixture.row("a")
            row.initiatingEventType = { .keyDown }
            #expect(fixture.window.makeFirstResponder(row))
            #expect(fixture.window.firstResponder === row)
        }

        @MainActor @Test func losingTheCameraHandsFocusToTheNextVisibleControl() throws {
            let fixture = try MiniPlayerFixture(["a"])
            fixture.engine("a").canToggleCamera = true
            try fixture.update(["a"])
            let camera = try fixture.button("Turn Camera On")
            try #require(fixture.window.makeFirstResponder(camera))
            fixture.engine("a").canToggleCamera = false
            try fixture.update(["a"])
            #expect(try fixture.window.firstResponder === fixture.button("Adjust Tab Volume"))
        }

        @MainActor @Test func theLastHiddenControlReturnsFocusToTheCard() throws {
            let fixture = try MiniPlayerFixture(["a"])
            let button = try fixture.button("Adjust Tab Volume")
            try #require(fixture.window.makeFirstResponder(button))
            fixture.engine("a").canSetVolume = false
            try fixture.update(["a"])
            #expect(try fixture.window.firstResponder === fixture.row("a"))
        }
    }
}
