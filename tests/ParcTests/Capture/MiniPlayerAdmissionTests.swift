import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore

extension MiniPlayerTestsSupport {
    struct MiniPlayerAdmissionTests {
        @MainActor @Test func aRemainingRowKeepsItsIdentityAcrossReadmission() throws {
            let fixture = try MiniPlayerFixture(["first", "second"])
            let second = try fixture.row("second")
            try fixture.update(["second"])
            try fixture.update(["first", "second"])
            #expect(try fixture.row("second") === second)
        }

        @MainActor @Test func readmittingAnEarlierEntryRestoresItsFrontPosition() throws {
            let fixture = try MiniPlayerFixture(["second"])
            try fixture.update(["first", "second"])
            #expect(try fixture.row("first").frame.minY > fixture.row("second").frame.minY)
        }

        @MainActor @Test func expandedKeyboardOrderFollowsAdmission() throws {
            let fixture = try MiniPlayerFixture(["second"])
            try fixture.update(["first", "second"])
            try fixture.toggleExpansion()
            let first = try fixture.row("first"), second = try fixture.row("second")
            let chain = SidebarAccessibility.keyViews(in: [fixture.deck], space: fixture.deck)
            SidebarAccessibility.link(chain, within: fixture.deck, exit: nil)
            let firstIndex = try #require(chain.firstIndex { $0 === first })
            let secondIndex = try #require(chain.firstIndex { $0 === second })
            try #require(firstIndex < secondIndex)
            #expect(chain[secondIndex - 1].nextKeyView === second)
        }
    }
}
