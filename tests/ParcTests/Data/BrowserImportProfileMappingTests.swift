import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import Parc

@MainActor @Suite(.serialized)
struct BrowserImportProfileMappingTests {
    private let work = ImportFixture.profile("chrome work", [.history, .bookmarks], name: "Work", directory: "Profile 1")
    private let main = ImportFixture.profile("chrome main", [.history, .bookmarks], name: "Josh", directory: "Default")
    private let side = ImportFixture.profile("chrome side", [.history, .bookmarks], name: "Side", directory: "Profile 2")
    private var three: [PCNativeImportProfile] { [work, main, side] }

    private func chrome(_ scene: BrowserImportScene) -> PCNativeImportSource {
        ImportFixture.source("Google Chrome", scene.directory.appendingPathComponent("Mapping Chrome.app"))
    }

    private func paths(_ scene: BrowserImportScene, _ profile: PCNativeImportProfile) -> [String] {
        scene.engine.browserRequests.filter { $0.profile === profile }.map(\.path)
    }

    @Test(arguments: [false, true])
    func everyProfileOfTheBrowserImportsWithNothingMoreToChoose(_ onboarding: Bool) throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(chrome(scene), profiles: ImportFixture.profiles(three), onboarding: onboarding)
            #expect(coordinator.selectedProfiles == Set(three.map(\.identifier)))
            #expect(coordinator.stage == .profiles && coordinator.canContinueSourceInline)
        }
    }

    @Test(arguments: [false, true])
    func theDefaultProfileImportsFirstIntoTheOpenedProfileBeforeOthersExist(_ onboarding: Bool) throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(chrome(scene), profiles: ImportFixture.profiles(three), onboarding: onboarding)
            let profiles = scene.store.state.profiles, spaces = scene.store.state.spaces
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .importing && scene.engine.browserRequests.count == 1)
            #expect(scene.engine.browserRequests.first?.profile === main && scene.engine.browserRequests.first?.path == scene.originalPath)
            #expect(scene.store.state.profiles == profiles && scene.store.state.spaces == spaces)
        }
    }

    @Test func theNextProfileGetsANewParcProfileAndSpaceOfItsNameOnItsTurn() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.started(chrome(scene), three)
            let before = scene.store.state.profiles.count
            scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping main", title: "Main", url: "https://example.test/main")])
            let workProfile = try #require(scene.store.state.profiles.first { $0.name == "Work" })
            #expect(scene.engine.browserRequests.count == 2 && scene.engine.browserRequests[1].profile === work)
            #expect(scene.engine.browserRequests[1].path == scene.path(workProfile.id))
            #expect(scene.store.state.spaces.contains { $0.profileID == workProfile.id && $0.title == "Work" })
            #expect(scene.store.state.profiles.count == before + 1)
            coordinator.cancel()
        }
    }

    @Test func anUnusedParcProfileOfTheSameNameInAnyCaseIsReused() throws {
        try BrowserImportScene.run { scene in
            let reused = scene.store.createProfile(name: "SIDE")
            let coordinator = scene.started(chrome(scene), three)
            let before = scene.store.state.profiles.count
            scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping main", title: "Main", url: "https://example.test/main")])
            scene.engine.finishBrowser()
            #expect(scene.engine.browserRequests.count == 3 && scene.engine.browserRequests[2].profile === side)
            #expect(scene.engine.browserRequests[2].path == scene.path(reused))
            #expect(scene.store.state.profiles.count == before + 1 && scene.store.state.spaces.contains { $0.profileID == reused })
            scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping side", title: "Side", url: "https://example.test/side")])
            scene.engine.finishAllBrowser()
            let workProfile = try #require(scene.store.state.profiles.first { $0.name == "Work" })
            #expect(paths(scene, main) == [scene.originalPath, scene.originalPath])
            #expect(paths(scene, work) == Array(repeating: scene.path(workProfile.id), count: 2))
            #expect(paths(scene, side) == [scene.path(reused), scene.path(reused)])
            #expect(coordinator.stage == .bookmarks)
            #expect(coordinator.bookmarkPages.map(\.destination.profileID) == [scene.destination.profileID, reused])
            #expect(coordinator.bookmarkPages.first?.destination == scene.destination)
        }
    }

    @Test func setupGivesEveryOtherProfileItsOwnNewParcProfile() throws {
        try BrowserImportScene.run { scene in
            let before = scene.store.state.profiles.count
            let coordinator = scene.started(chrome(scene), three, onboarding: true)
            scene.engine.finishBrowser()
            let setupWork = try #require(scene.store.state.profiles.first { $0.name == "Work" })
            #expect(scene.engine.browserRequests.count == 2 && scene.engine.browserRequests[1].profile === work)
            #expect(scene.engine.browserRequests[1].path == scene.path(setupWork.id))
            scene.engine.finishAllBrowser()
            scene.engine.finishAllBrowser()
            let setupSide = try #require(scene.store.state.profiles.first { $0.name == "Side" })
            #expect(coordinator.stage == .finished && scene.store.state.profiles.count == before + 2)
            #expect(paths(scene, side).allSatisfy { $0 == scene.path(setupSide.id) })
        }
    }

    @Test func withoutDefaultTheFirstProfileTakesTheOriginalAndOthersGetTheirOwn() throws {
        try BrowserImportScene.run { scene in
            let historyOnly = ImportFixture.profile("chrome side history", [.history], name: "Side", directory: "Profile 2")
            let coordinator = scene.started(chrome(scene), [work, historyOnly])
            #expect(coordinator.stage == .importing && scene.engine.browserRequests.count == 1)
            #expect(scene.engine.browserRequests.first?.profile === work && scene.engine.browserRequests.first?.path == scene.originalPath)
            scene.engine.finishBrowser()
            scene.engine.finishAllBrowser()
            let otherSide = try #require(scene.store.state.profiles.first { $0.name == "Side" })
            #expect(paths(scene, historyOnly) == [scene.path(otherSide.id)])
            #expect(!scene.store.state.profiles.contains { $0.name == "Work" })
            #expect(coordinator.stage == .finished)
        }
    }

    @Test func profilesSharingANameOrTheOpenedProfilesNameEachGetTheirOwn() throws {
        try BrowserImportScene.run { scene in
            let openedName = "Default"
            #expect(scene.store.state.profiles.map(\.name) == [openedName])
            let workAgain = ImportFixture.profile("chrome work again", [.history], name: "work", directory: "Profile 3")
            let namesake = ImportFixture.profile("chrome namesake", [.history], name: openedName, directory: "Profile 4")
            let named = [main, work, workAgain, namesake]
            _ = scene.started(chrome(scene), named)
            scene.engine.finishAllBrowser()
            scene.engine.finishAllBrowser()
            let namedPaths = named.map { Set(paths(scene, $0)) }
            #expect(namedPaths.allSatisfy { $0.count == 1 } && Set(namedPaths.compactMap(\.first)).count == 4)
            #expect(namedPaths[0] == [scene.originalPath])
            #expect(scene.store.state.profiles.filter { $0.name.caseInsensitiveCompare("Work") == .orderedSame }.count == 2)
            #expect(scene.store.state.profiles.filter { $0.name == openedName }.count == 2)
        }
    }

    @Test func everyArcProfileBringsItsSpacesAndFavoritesIntoItsOwnParcProfile() throws {
        try BrowserImportScene.run { scene in
            let standard = ImportFixture.profile("mapping arc standard", [.history, .bookmarks], name: "Person 1", directory: "Default")
            let arcSide = ImportFixture.profile("mapping arc side", [.history, .bookmarks], name: "Side", directory: "Profile 1")
            let projects = ImportFixture.profile("mapping arc projects", [.history, .bookmarks], name: "Side Projects",
                                                 directory: "Profile 2")
            let coordinator = scene.chosen(scene.arc(), profiles: ImportFixture.profiles([standard, arcSide, projects]),
                                           onboarding: true, arcSidebar: try BrowserImportScene.arcSidebar())
            #expect(coordinator.selectedProfiles == [standard.identifier, arcSide.identifier, projects.identifier])
            let before = scene.store.state.profiles.count
            coordinator.continueSourceInline()
            scene.engine.settle()
            #expect(coordinator.stage == .importing && scene.engine.browserRequests.count == 1)
            let sideProfile = try #require(scene.store.state.profiles.first { $0.name == "Side" })
            let projectsProfile = try #require(scene.store.state.profiles.first { $0.name == "Side Projects" })
            #expect(scene.store.state.spaces.contains { $0.title == "Work" && $0.profileID == scene.destination.profileID })
            #expect(scene.store.state.spaces.contains { $0.title == "Side" && $0.profileID == sideProfile.id })
            #expect(scene.store.state.profiles.count == before + 2)
            #expect(scene.store.state.tabs.contains { $0.kind == .favorite && $0.profileID == projectsProfile.id })
            #expect(scene.engine.browserRequests.first?.profile === standard && scene.engine.browserRequests.first?.path == scene.originalPath)
            scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("mapping arc", title: "Arc", url: "https://example.test/arc")])
            #expect(scene.engine.browserRequests.count == 2 && scene.engine.browserRequests[1].profile === arcSide)
            scene.engine.finishAllBrowser()
            scene.engine.finishAllBrowser()
            #expect(paths(scene, standard) == [scene.originalPath, scene.originalPath])
            #expect(paths(scene, arcSide) == [scene.path(sideProfile.id), scene.path(sideProfile.id)])
            #expect(paths(scene, projects) == [scene.path(projectsProfile.id), scene.path(projectsProfile.id)])
            #expect(coordinator.bookmarkPages.first?.destination == scene.destination)
        }
    }

    @Test func everyProfileImportKeepsTheExistingCookiesOfItsParcProfile() throws {
        try BrowserImportScene.run { scene in
            _ = scene.started(chrome(scene), three)
            scene.engine.finishAllBrowser()
            scene.engine.finishAllBrowser()
            #expect(scene.engine.browserRequests.count == 6 && scene.engine.browserRequests.allSatisfy(\.skipExistingCookies))
        }
    }
}
