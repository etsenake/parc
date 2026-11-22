import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import Parc

extension BrowserImportProfileMappingTestsSupport {
    @MainActor
    struct BrowserImportProfileMappingChromeTests {
        @Test(arguments: [false, true])
        func everyProfileOfTheBrowserImportsWithNothingMoreToChoose(_ onboarding: Bool) throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                let coordinator = scene.chosen(fixture.chrome(scene), profiles: ImportFixture.profiles(fixture.three), onboarding: onboarding)
                #expect(coordinator.selectedProfiles == Set(fixture.three.map(\.identifier)))
                #expect(coordinator.stage == .profiles && coordinator.canContinueSourceInline)
            }
        }

        @Test(arguments: [false, true])
        func theDefaultProfileImportsFirstIntoTheOpenedProfileBeforeOthersExist(_ onboarding: Bool) throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                let coordinator = scene.chosen(fixture.chrome(scene), profiles: ImportFixture.profiles(fixture.three), onboarding: onboarding)
                let profiles = scene.store.state.profiles, spaces = scene.store.state.spaces
                coordinator.continueSourceInline()
                #expect(coordinator.stage == .importing && scene.engine.browserRequests.count == 1)
                #expect(scene.engine.browserRequests.first?.profile === fixture.main && scene.engine.browserRequests.first?.path == scene.originalPath)
                #expect(scene.store.state.profiles == profiles && scene.store.state.spaces == spaces)
            }
        }

        @Test func theNextProfileGetsANewParcProfileAndSpaceOfItsNameOnItsTurn() throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                let coordinator = scene.started(fixture.chrome(scene), fixture.three)
                let before = scene.store.state.profiles.count
                scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping main", title: "Main", url: "https://example.test/main")])
                let workProfile = try #require(scene.store.state.profiles.first { $0.name == "Work" })
                #expect(scene.engine.browserRequests.count == 2 && scene.engine.browserRequests[1].profile === fixture.work)
                #expect(scene.engine.browserRequests[1].path == scene.path(workProfile.id))
                #expect(scene.store.state.spaces.contains { $0.profileID == workProfile.id && $0.title == "Work" })
                #expect(scene.store.state.profiles.count == before + 1)
                coordinator.cancel()
            }
        }

        @Test func anUnusedParcProfileOfTheSameNameInAnyCaseIsReused() throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                let reused = scene.store.createProfile(name: "SIDE")
                _ = scene.started(fixture.chrome(scene), fixture.three)
                let before = scene.store.state.profiles.count
                scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping main", title: "Main", url: "https://example.test/main")])
                scene.engine.finishBrowser()
                #expect(scene.engine.browserRequests.count == 3 && scene.engine.browserRequests[2].profile === fixture.side)
                #expect(scene.engine.browserRequests[2].path == scene.path(reused))
                #expect(scene.store.state.profiles.count == before + 1 && scene.store.state.spaces.contains { $0.profileID == reused })
            }
        }

        @Test func bothImportPassesUseTheOriginalNewAndReusedProfiles() throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                let reused = scene.store.createProfile(name: "SIDE")
                _ = scene.started(fixture.chrome(scene), fixture.three)
                scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping main", title: "Main", url: "https://example.test/main")])
                scene.engine.finishBrowser()
                scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping side", title: "Side", url: "https://example.test/side")])
                scene.engine.finishAllBrowser()
                let workProfile = try #require(scene.store.state.profiles.first { $0.name == "Work" })
                #expect(paths(scene, fixture.main) == [scene.originalPath, scene.originalPath])
                #expect(paths(scene, fixture.work) == Array(repeating: scene.path(workProfile.id), count: 2))
                #expect(paths(scene, fixture.side) == [scene.path(reused), scene.path(reused)])
            }
        }

        @Test func bookmarkPagesKeepTheirOriginalAndReusedDestinations() throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                let reused = scene.store.createProfile(name: "SIDE")
                let coordinator = scene.started(fixture.chrome(scene), fixture.three)
                scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping main", title: "Main", url: "https://example.test/main")])
                scene.engine.finishBrowser()
                scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping side", title: "Side", url: "https://example.test/side")])
                scene.engine.finishAllBrowser()
                #expect(coordinator.stage == .bookmarks)
                #expect(coordinator.bookmarkPages.map(\.destination.profileID) == [scene.destination.profileID, reused])
                #expect(coordinator.bookmarkPages.first?.destination == scene.destination)
            }
        }

        @Test func setupGivesEveryOtherProfileItsOwnNewParcProfile() throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                let before = scene.store.state.profiles.count
                let coordinator = scene.started(fixture.chrome(scene), fixture.three, onboarding: true)
                scene.engine.finishBrowser()
                let setupWork = try #require(scene.store.state.profiles.first { $0.name == "Work" })
                #expect(scene.engine.browserRequests.count == 2 && scene.engine.browserRequests[1].profile === fixture.work)
                #expect(scene.engine.browserRequests[1].path == scene.path(setupWork.id))
                scene.engine.finishAllBrowser()
                scene.engine.finishAllBrowser()
                let setupSide = try #require(scene.store.state.profiles.first { $0.name == "Side" })
                #expect(coordinator.stage == .finished && scene.store.state.profiles.count == before + 2)
                #expect(paths(scene, fixture.side).allSatisfy { $0 == scene.path(setupSide.id) })
            }
        }

        @Test func withoutDefaultTheFirstProfileTakesTheOriginalAndOthersGetTheirOwn() throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                let historyOnly = ImportFixture.profile("chrome side history", [.history], name: "Side", directory: "Profile 2")
                let coordinator = scene.started(fixture.chrome(scene), [fixture.work, historyOnly])
                #expect(coordinator.stage == .importing && scene.engine.browserRequests.count == 1)
                #expect(scene.engine.browserRequests.first?.profile === fixture.work && scene.engine.browserRequests.first?.path == scene.originalPath)
                scene.engine.finishBrowser()
                scene.engine.finishAllBrowser()
                let otherSide = try #require(scene.store.state.profiles.first { $0.name == "Side" })
                #expect(paths(scene, historyOnly) == [scene.path(otherSide.id)])
                #expect(!scene.store.state.profiles.contains { $0.name == "Work" })
                #expect(coordinator.stage == .finished)
            }
        }

        @Test func profilesSharingANameOrTheOpenedProfilesNameEachGetTheirOwn() throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                let openedName = "Default"
                #expect(scene.store.state.profiles.map(\.name) == [openedName])
                let workAgain = ImportFixture.profile("chrome work again", [.history], name: "work", directory: "Profile 3")
                let namesake = ImportFixture.profile("chrome namesake", [.history], name: openedName, directory: "Profile 4")
                let named = [fixture.main, fixture.work, workAgain, namesake]
                _ = scene.started(fixture.chrome(scene), named)
                scene.engine.finishAllBrowser()
                scene.engine.finishAllBrowser()
                let namedPaths = named.map { Set(paths(scene, $0)) }
                #expect(namedPaths.allSatisfy { $0.count == 1 } && Set(namedPaths.compactMap(\.first)).count == 4)
                #expect(namedPaths[0] == [scene.originalPath])
                #expect(scene.store.state.profiles.filter { $0.name.caseInsensitiveCompare("Work") == .orderedSame }.count == 2)
                #expect(scene.store.state.profiles.filter { $0.name == openedName }.count == 2)
            }
        }

        @Test func everyProfileImportKeepsTheExistingCookiesOfItsParcProfile() throws {
            let fixture = Fixture()
            try BrowserImportScene.run { scene in
                _ = scene.started(fixture.chrome(scene), fixture.three)
                scene.engine.finishAllBrowser()
                scene.engine.finishAllBrowser()
                #expect(scene.engine.browserRequests.count == 6 && scene.engine.browserRequests.allSatisfy(\.skipExistingCookies))
            }
        }
    }
}
