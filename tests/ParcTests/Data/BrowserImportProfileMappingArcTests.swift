import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import Parc

extension BrowserImportProfileMappingTestsSupport {
    @MainActor
    struct BrowserImportProfileMappingArcTests {
        @MainActor private struct ArcProfiles {
            let standard = ImportFixture.profile("mapping arc standard", [.history, .bookmarks], name: "Person 1", directory: "Default")
            let side = ImportFixture.profile("mapping arc side", [.history, .bookmarks], name: "Side", directory: "Profile 1")
            let projects = ImportFixture.profile("mapping arc projects", [.history, .bookmarks], name: "Side Projects",
                                                 directory: "Profile 2")

            @MainActor func choose(in scene: BrowserImportScene) throws -> BrowserImportCoordinator {
                scene.chosen(scene.arc(), profiles: ImportFixture.profiles([standard, side, projects]),
                             onboarding: true, arcSidebar: try BrowserImportScene.arcSidebar())
            }

            @MainActor func start(in scene: BrowserImportScene) throws -> BrowserImportCoordinator {
                let coordinator = try choose(in: scene)
                coordinator.continueSourceInline()
                scene.engine.settle()
                return coordinator
            }

            @MainActor func finishFirstProfile(in scene: BrowserImportScene) {
                scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping arc", title: "Arc", url: "https://example.test/arc")])
            }
        }

        @Test func choosingArcSelectsEveryReadableProfile() throws {
            try BrowserImportScene.run { scene in
                let profiles = ArcProfiles()
                let coordinator = try profiles.choose(in: scene)
                #expect(coordinator.selectedProfiles == [profiles.standard.identifier, profiles.side.identifier, profiles.projects.identifier])
            }
        }

        @Test func theDefaultArcProfileImportsIntoTheOpenedProfileFirst() throws {
            try BrowserImportScene.run { scene in
                let profiles = ArcProfiles()
                let coordinator = try profiles.start(in: scene)
                #expect(coordinator.stage == .importing && scene.engine.browserRequests.count == 1)
                #expect(scene.engine.browserRequests.first?.profile === profiles.standard && scene.engine.browserRequests.first?.path == scene.originalPath)
            }
        }

        @Test func importingArcPlacesSpacesAndFavoritesInTheirOwnProfiles() throws {
            try BrowserImportScene.run { scene in
                let before = scene.store.state.profiles.count
                _ = try ArcProfiles().start(in: scene)
                let side = try #require(scene.store.state.profiles.first { $0.name == "Side" })
                let projects = try #require(scene.store.state.profiles.first { $0.name == "Side Projects" })
                #expect(scene.store.state.spaces.contains { $0.title == "Work" && $0.profileID == scene.destination.profileID })
                #expect(scene.store.state.spaces.contains { $0.title == "Side" && $0.profileID == side.id })
                #expect(scene.store.state.profiles.count == before + 2)
                #expect(scene.store.state.tabs.contains { $0.kind == .favorite && $0.profileID == projects.id })
            }
        }

        @Test func importingArcSendsBothPassesToEachProfilesOwnPath() throws {
            try BrowserImportScene.run { scene in
                let profiles = ArcProfiles()
                _ = try profiles.start(in: scene)
                let side = try #require(scene.store.state.profiles.first { $0.name == "Side" })
                let projects = try #require(scene.store.state.profiles.first { $0.name == "Side Projects" })
                profiles.finishFirstProfile(in: scene)
                #expect(scene.engine.browserRequests.count == 2 && scene.engine.browserRequests[1].profile === profiles.side)
                scene.engine.finishAllBrowser()
                scene.engine.finishAllBrowser()
                #expect(paths(scene, profiles.standard) == [scene.originalPath, scene.originalPath])
                #expect(paths(scene, profiles.side) == [scene.path(side.id), scene.path(side.id)])
                #expect(paths(scene, profiles.projects) == [scene.path(projects.id), scene.path(projects.id)])
            }
        }

        @Test func arcBookmarksAreOfferedForTheOriginalDestination() throws {
            try BrowserImportScene.run { scene in
                let profiles = ArcProfiles()
                let coordinator = try profiles.start(in: scene)
                profiles.finishFirstProfile(in: scene)
                scene.engine.finishAllBrowser()
                scene.engine.finishAllBrowser()
                #expect(coordinator.bookmarkPages.first?.destination == scene.destination)
            }
        }
    }
}
