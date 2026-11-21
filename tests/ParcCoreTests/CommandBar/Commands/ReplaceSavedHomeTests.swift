import Foundation
import Testing
@testable import ParcCore

@MainActor
struct ReplaceSavedHomeTests {
    let profile = BrowserProfile(id: UUID(), name: "Original")
    let origin: BrowserSpace
    let pinned: BrowserTab
    let today: BrowserTab
    let atHome: BrowserTab
    let directory = CommandBarFixtures.temporaryDirectory("typed-commands")

    init() throws {
        origin = BrowserSpace(id: UUID(), name: "Origin", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        pinned = Self.tab(.pinned, url: "https://away.test/page", space: origin.id, profile: profile.id)
        today = Self.tab(.today, url: "https://away.test/today", space: origin.id, profile: profile.id)
        atHome = Self.tab(.pinned, url: "https://home.test/", space: origin.id, profile: profile.id)
    }

    static func tab(_ kind: TabKind, url: String, space: UUID, profile: UUID) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: space, profileID: profile, url: url, title: "Current", kind: kind,
                   createdAt: Date(timeIntervalSince1970: 100), lastAccessed: Date(timeIntervalSince1970: 100),
                   savedURL: "https://home.test/", savedTitle: "Home")
    }

    func makeStore(extra: [BrowserTab] = []) throws -> BrowserStore {
        var state = BrowserState(profiles: [profile], spaces: [origin], activeSpaceID: origin.id)
        state.tabs = [pinned, today, atHome] + extra
        state.selectedTabIDs = [pinned.id]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        return try BrowserStore(directory: directory)
    }

    @Test func aTodayTabHasNoPinToReplace() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore()
        #expect(!store.replaceSavedHome(today, url: today.url, title: "Today"))
    }

    @Test func aPinAtItsHomeIsUnchanged() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore()
        #expect(!store.replaceSavedHome(atHome, url: atHome.url, title: "Home"))
    }

    @Test func aLocalDocumentCannotBecomeAWebHome() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore()
        #expect(!store.replaceSavedHome(pinned, url: "parc://note/\(UUID().uuidString)", title: "Note"))
    }

    @Test func anAwayPinTakesItsCurrentPageInPlaceKeepingIdentityAndKind() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore()
        #expect(store.replaceSavedHome(pinned, url: pinned.url, title: "Away Page"))
        let replaced = store.state.tabs.first { $0.id == pinned.id }
        #expect(replaced?.savedURL == pinned.url)
        #expect(replaced?.savedTitle == "Away Page")
        #expect(replaced?.kind == .pinned)
        #expect(replaced?.resetDestination == nil)
    }

    @Test func aStaleExpectedRecordIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try makeStore()
        _ = store.replaceSavedHome(pinned, url: pinned.url, title: "Away Page")
        #expect(!store.replaceSavedHome(pinned, url: pinned.url, title: "Again"))
    }

    @Test func aWebUIPageCanBecomeAPinsHomeUnderItsPublicAddress() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsPin = Self.tab(.pinned, url: "chrome://settings/searchEngines", space: origin.id, profile: profile.id)
        let store = try makeStore(extra: [settingsPin])
        let loaded = try #require(store.state.tabs.first { $0.id == settingsPin.id })
        #expect(store.replaceSavedHome(loaded, url: "chrome://settings/searchEngines", title: "Search engines"))
        #expect(store.state.tabs.first { $0.id == settingsPin.id }?.savedURL == "parc://settings/searchEngines")
    }

    func spaceMoveFixture() throws -> (state: BrowserState, away: BrowserSpace, move: SidebarSpaceMove) {
        let away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        var spaces = BrowserState(profiles: [profile], spaces: [origin, away], activeSpaceID: origin.id)
        spaces.tabs = [today]
        spaces.selectedTabIDs = [today.id]
        let source = try #require(SidebarHierarchySnapshot(state: spaces, spaceID: origin.id, profileID: profile.id))
        let target = try #require(SidebarHierarchySnapshot(state: spaces, spaceID: away.id, profileID: profile.id))
        let move = try #require(SidebarSpaceMove(items: [.tab(today.id)], from: source, to: target, state: spaces))
        return (spaces, away, move)
    }

    @Test func aSidebarDragKeepsItsTodaySection() throws {
        let fixture = try spaceMoveFixture()
        let kept = fixture.move.applying(to: fixture.state)?.tabs.first { $0.id == today.id }
        #expect(kept?.kind == .today)
        #expect(kept?.spaceID == fixture.away.id)
    }

    @Test func pinToSpaceMovesTheTabIntoPinnedWithTheCurrentPageAsItsHome() throws {
        var fixture = try spaceMoveFixture()
        fixture.move.pinsToday = true
        let pinnedState = fixture.move.applying(to: fixture.state)
        let moved = pinnedState?.tabs.first { $0.id == today.id }
        #expect(moved?.kind == .pinned)
        #expect(moved?.spaceID == fixture.away.id)
        #expect(moved?.savedURL == today.url)
        #expect(moved?.savedTitle == today.title)
        let pinnedKey = SidebarContainerLocation(spaceID: fixture.away.id, folderID: nil, section: .pinned).key
        #expect(pinnedState?.sidebarItemOrder[pinnedKey]?.contains(.tab(today.id)) == true)
    }
}
