import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct ArcSidebarImportStoreTests {
    private typealias Support = ArcSidebarImportTestsSupport

    @MainActor @Test func aFailedSessionWriteLeavesNothingBehind() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try Support.loadArc()
            let store = try BrowserStore(directory: directory, now: { Support.importedAt })
            let standardID = store.state.profiles[0].id
            _ = store.createProfile(name: "WORK PROFILE")
            try store.save()
            let before = store.state
            let session = directory.appendingPathComponent("session.json")
            let backup = directory.appendingPathComponent("prior-session.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) {
                try store.importArcSidebar(arc, profiles: Support.allProfiles, standardProfileID: standardID)
            }
            #expect(store.state == before)
        }
    }

    @MainActor
    @Test func importDoesNotChangeTheActiveSpaceAndAddsTwoProfiles() throws {
        try Support.withImport { imported, _ in
            #expect(imported.store.activeSpaceID == imported.activeBefore)
            #expect(imported.state.profiles.count == imported.profilesBefore + 2)
            #expect(imported.state.profiles.first { $0.id == imported.standardID }?.name == "Default")
        }
    }

    @MainActor
    @Test func everyArcSpaceBecomesANewSpaceInArcsOrder() throws {
        try Support.withImport { imported, _ in
            let sideProjects = try #require(imported.state.profiles.first { $0.name == "Side Projects" })
            let empty = try #require(imported.state.profiles.first { $0.name == "Empty" })
            let created = imported.created
            #expect(created.map(\.title) == ["Work", nil, "Side", "Plain", "Odd", "Side Projects", "Empty"])
            #expect(created.map(\.profileID) == [imported.standardID, imported.standardID, imported.existingID,
                                                 imported.standardID, imported.standardID, sideProjects.id, empty.id])
        }
    }

    @MainActor
    @Test func untitledSpaceTakesItsPositionalNameAndImportedSpacesUseTheDefaultSymbol() throws {
        try Support.withImport { imported, _ in
            #expect(imported.created[1].name == "Space \(imported.spacesBefore + 2)")
            #expect(imported.created.allSatisfy { $0.symbol == "circle.fill" })
        }
    }

    @MainActor
    @Test func iconAndThemeAreAppliedAndUnreadableThemeBecomesTheDefault() throws {
        try Support.withImport { imported, _ in
            let created = imported.created
            #expect(created[0].customIcon == .icon(.planet) && created[0].theme == imported.arc.spaces[0].theme)
            #expect(created[4].theme == BrowserSpace(id: UUID(), name: "", symbol: "", color: "B9B5D4",
                                                     profileID: imported.standardID).theme)
        }
    }

    @MainActor
    @Test func eachArcProfilesDestinationIsTheFirstSpaceCreatedForIt() throws {
        try Support.withImport { imported, _ in
            let sideProjects = try #require(imported.state.profiles.first { $0.name == "Side Projects" })
            let empty = try #require(imported.state.profiles.first { $0.name == "Empty" })
            let created = imported.created
            let result = imported.result
            #expect(result[.standard] == .init(spaceID: created[0].id, profileID: imported.standardID))
            #expect(result[Support.profileOne] == .init(spaceID: created[2].id, profileID: imported.existingID))
            #expect(result[Support.profileTwo] == .init(spaceID: created[5].id, profileID: sideProjects.id))
            #expect(result[Support.profileThree] == .init(spaceID: created[6].id, profileID: empty.id))
            #expect(result.values.allSatisfy { $0.isCurrent(in: imported.state) })
        }
    }

    @MainActor
    @Test func pinnedRootOrderIsArcsOrderAndTheSplitSurvivesReconciliation() throws {
        try Support.withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let root = SidebarHierarchy.children(in: .init(spaceID: workID, folderID: nil, section: .pinned), state: state)
            let workTabs = state.tabs.filter { $0.spaceID == workID && $0.kind == .pinned }
            func tab(_ url: String) -> BrowserTab? { workTabs.first { $0.savedURL == url } }
            let projects = try #require(state.folders.first { $0.spaceID == workID && $0.parentID == nil })
            let groups = SidebarSplitItems.groups(in: state, spaceID: workID)
                .filter { !SidebarSplitItems.isFavorite($0, in: state, profileID: imported.standardID) }
            #expect(groups.count == 1 && groups[0].orientation == .vertical && groups[0].customTitle == "Compare"
                    && groups[0].customIcon == .emoji("\u{1F9EA}"))
            let alpha = try #require(tab("https://docs.example.test/a"))
            let settings = try #require(tab("parc://settings"))
            #expect(root == [.tab(alpha.id), .folder(projects.id), .split(groups[0].id), .tab(settings.id)])
        }
    }

    @MainActor
    @Test func aTabKeepsItsTitleRenameAndMute() throws {
        try Support.withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let alpha = try #require(state.tabs.first {
                $0.spaceID == workID && $0.kind == .pinned && $0.savedURL == "https://docs.example.test/a"
            })
            #expect(alpha.title == "Alpha docs" && alpha.customTitle == "Renamed alpha" && alpha.isMuted
                    && alpha.profileID == imported.standardID && alpha.createdAt == Support.importedAt)
        }
    }

    @MainActor
    @Test func foldersKeepNameIconNestingAndOrder() throws {
        try Support.withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let workTabs = state.tabs.filter { $0.spaceID == workID && $0.kind == .pinned }
            func tab(_ url: String) -> BrowserTab? { workTabs.first { $0.savedURL == url } }
            let projects = try #require(state.folders.first { $0.spaceID == workID && $0.parentID == nil })
            #expect(projects.name == "Projects" && projects.customIcon == .icon(.star))
            let inner = try #require(state.folders.first { $0.parentID == projects.id })
            #expect(inner.name == "Imported folder" && tab("https://example.test/c")?.folderID == inner.id)
            let beta = try #require(tab("https://example.test/b"))
            #expect(SidebarHierarchy.children(in: .init(spaceID: workID, folderID: projects.id, section: .pinned), state: state)
                    == [.tab(beta.id), .folder(inner.id)])
        }
    }

    @MainActor
    @Test func todayTabsComeInArcsOrderAndStartTheirArchiveClockAtTheImport() throws {
        try Support.withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let today = SidebarHierarchy.children(in: .init(spaceID: workID, folderID: nil, section: .today), state: state)
            let newer = try #require(state.tabs.first { $0.savedURL == "https://example.test/newer-today" })
            let older = try #require(state.tabs.first { $0.savedURL == "https://example.test/today" })
            #expect(today == [.tab(newer.id), .tab(older.id)] && newer.kind == .today && older.kind == .today
                    && older.spaceID == workID && older.folderID == nil)
            #expect(older.lastAccessed == Support.importedAt)
        }
    }

    @MainActor
    @Test func eachImportedSpaceRemembersItsArcSpace() throws {
        try Support.withImport { imported, _ in
            #expect(imported.state.arcImportedSpaces["734FF6CE-5A92-54B8-8106-4F9A92236F11"] == imported.created[0].id)
        }
    }

    @MainActor
    @Test func favoritesStopAtParcsLimitKeepArcsOrderAndSkipDuplicates() throws {
        try Support.withImport { imported, _ in
            let state = imported.state
            let workID = imported.created[0].id
            let location = SidebarContainerLocation(spaceID: workID, folderID: nil, section: .favorite,
                                                    profileID: imported.standardID)
            let favorites = SidebarHierarchy.children(in: location, state: state)
            let favoriteTabs = state.tabs.filter { $0.kind == .favorite && $0.profileID == imported.standardID }
            #expect(favorites.count == 12)
            let mail = try #require(favoriteTabs.first { $0.savedURL == "https://mail.example.test/" })
            #expect(favorites.first == .tab(mail.id))
            #expect(!favoriteTabs.contains { $0.savedURL == "https://www.mail.example.test" })
            #expect(!favoriteTabs.contains { $0.savedURL == "https://f12.example.test/" })
        }
    }

    @MainActor
    @Test func aFavoritesSplitSurvivesTheImport() throws {
        try Support.withImport { imported, _ in
            let state = imported.state
            let location = SidebarContainerLocation(spaceID: imported.created[0].id, folderID: nil, section: .favorite,
                                                    profileID: imported.standardID)
            let favorites = SidebarHierarchy.children(in: location, state: state)
            guard case .split(let id) = favorites[1] else {
                Issue.record("The second Favorite is a split")
                return
            }
            #expect(state.splitLayouts.first { $0.id == id }?.tabIDs.count == 2)
        }
    }

    @MainActor
    @Test func aFavoritesOnlyProfileGetsItsFavorites() throws {
        try Support.withImport { imported, _ in
            let sideProjects = try #require(imported.state.profiles.first { $0.name == "Side Projects" })
            #expect(imported.state.tabs.filter { $0.kind == .favorite && $0.profileID == sideProjects.id }.map(\.savedURL)
                    == ["https://calendar.example.test/"])
        }
    }

    @MainActor
    @Test func theImportIsDurable() throws {
        try Support.withImport { imported, directory in
            let state = imported.state
            let reloaded = try BrowserStore(directory: directory)
            #expect(reloaded.state.spaces == state.spaces && reloaded.state.profiles == state.profiles
                    && reloaded.state.tabs == state.tabs && reloaded.state.folders == state.folders
                    && reloaded.state.splitLayouts == state.splitLayouts
                    && reloaded.state.sidebarItemOrder == state.sidebarItemOrder
                    && reloaded.state.arcImportedSpaces == state.arcImportedSpaces)
        }
    }

    @MainActor
    @Test func importingTheSameSpacesAgainAddsNoCopies() throws {
        try Support.withImport { imported, _ in
            let again = try imported.store.importArcSidebar(imported.arc, profiles: [(.standard, "Personal")],
                                                            standardProfileID: imported.standardID)
            let standardSpaces = imported.arc.spaces.filter { $0.profile == .standard }
            #expect(standardSpaces.count == 4 && imported.store.state.spaces.count == imported.state.spaces.count
                    && imported.store.state.tabs.count == imported.state.tabs.count)
            #expect(again[.standard] == imported.result[.standard])
        }
    }

    @MainActor
    @Test func aLaterImportReusesTheSameParcProfileAndAnExistingSpace() throws {
        try Support.withImport { imported, _ in
            let spacesBeforeReuse = imported.store.state.spaces.count
            let secondReuse = try imported.store.importArcSidebar(
                imported.arc, profiles: [(Support.profileOne, "work profile"), (Support.profileTwo, "Side Projects")],
                standardProfileID: imported.standardID)
            #expect(secondReuse[Support.profileOne]?.profileID == imported.existingID)
            #expect(imported.store.state.spaces.count == spacesBeforeReuse && secondReuse[Support.profileTwo]?.spaceID
                    == imported.state.spaces.first { $0.title == "Side Projects" }?.id)
        }
    }
}
