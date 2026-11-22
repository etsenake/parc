import Foundation
import Testing
@testable import ParcCore

struct OriginalSplitDropFavoritesTests {
    private typealias Fixture = OriginalSplitDropTestsSupport.Fixture

    @MainActor @Test func aStandaloneFavoriteKeepsItsHomeInTheTrayAndRunsLiveInToday() throws {
        let f = try Fixture()
        let moved = try #require(f.propose(f.favoriteTarget()))
        #expect(moved.tabs.first { $0.id == f.a }?.kind == .today)
        #expect(moved.tabs.first { $0.id == f.home }?.kind == .favorite)
    }

    @MainActor @Test func theFavoriteHomeKeepsItsExactTraySlot() throws {
        let f = try Fixture()
        let moved = try #require(f.propose(f.favoriteTarget()))
        #expect(SidebarHierarchy.children(in: f.tray, state: moved) == [.tab(f.home)])
    }

    @MainActor @Test func aWholeFavoriteDestinationKeepsItsGroupAndChildOrder() throws {
        let f = try Fixture()
        let (state, layout) = f.favoriteContainer()
        let inserted = try #require(f.propose(state, layout: layout, homes: [:]))
        #expect(inserted.splitLayouts[0].id == layout.id)
        #expect(inserted.selectedTabIDs == [f.a, f.b, f.c])
    }

    @MainActor @Test func aWholeFavoriteDestinationAdmitsTheChildWithoutReplacingHomes() throws {
        let f = try Fixture()
        let (state, layout) = f.favoriteContainer()
        let inserted = try #require(f.propose(state, layout: layout, homes: [:]))
        #expect(inserted.tabs.count == state.tabs.count)
        #expect(inserted.tabs[f.bIndex].kind == .favorite)
    }

    @MainActor @Test func favoriteReplacementKeepsTheDisplacedOriginalRecord() throws {
        let f = try Fixture()
        let (state, layout) = f.favoriteContainer()
        let replacement = try #require(f.propose(state, target: .replace(0), layout: layout, homes: [:]))
        #expect(replacement.selectedTabIDs == [f.b, f.c])
        #expect(replacement.tabs[f.aIndex] == state.tabs[f.aIndex])
    }

    @MainActor @Test func favoriteReplacementCannotExceedTheTrayRootLimit() throws {
        let f = try Fixture()
        let (state, layout) = f.favoriteContainer()
        var maximum = state
        let template = f.favoriteTarget().tabs[f.aIndex]
        for _ in 0..<11 { var extra = template; extra.id = UUID(); maximum.tabs.append(extra) }
        #expect(f.propose(maximum, target: .replace(0), layout: layout, homes: [:]) == nil)
    }

    @MainActor @Test func anOversizedUnrelatedTrayDoesNotBlockOrdinaryMovement() throws {
        let f = try Fixture()
        var legacyTray = f.pinned()
        let template = f.favoriteTarget().tabs[f.aIndex]
        for _ in 0..<13 { var extra = template; extra.id = UUID(); legacyTray.tabs.append(extra) }
        #expect(f.propose(legacyTray) != nil)
    }
}
