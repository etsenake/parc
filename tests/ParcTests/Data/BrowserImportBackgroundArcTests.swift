import AppKit
@testable import ParcCore
import ParcEngine
import Testing
@testable import Parc

@MainActor
@Suite(.serialized)
struct BrowserImportBackgroundArcTests {
    private let standard = ImportFixture.profile("arc standard", [.history, .bookmarks], name: "Person 1", directory: "Default")

    private let side = ImportFixture.profile("arc side", [.history], name: "Side", directory: "Profile 1")

    private let empty = ImportFixture.profile("arc empty", [], .restricted, name: "Locked", directory: "Profile 3")

    private func preferences(_ scene: BrowserImportScene) throws -> URL {
        let url = scene.directory.appendingPathComponent("ArcPreferences.plist")
        try FileManager.default.createDirectory(at: scene.directory, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["autoArchiveTimeThresholdsPerProfile":
            #"{"thresholds":[{"custom":{"_0":{"directoryBasename":"Profile 1","machineID":"M"}}},"thirtyDays"]}"#],
            format: .binary, options: 0).write(to: url)
        return url
    }

    private func begin(_ scene: BrowserImportScene, sidebar: URL? = nil) throws -> BrowserImportCoordinator {
        scene.chosen(scene.arc(), profiles: ImportFixture.profiles([standard, side, empty],
            constraints: ["Encrypted cookies may require macOS Keychain authorization."]),
            arcSidebar: try sidebar ?? BrowserImportScene.arcSidebar(), arcPreferences: try preferences(scene))
    }

    private func imported(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
        let coordinator = try begin(scene)
        coordinator.continueSourceInline()
        scene.engine.settle()
        return coordinator
    }

    @Test func everyReadableArcProfileImportsAndExplanationsAreNotWarnings() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try begin(scene)
            #expect(coordinator.selectedProfiles == [standard.identifier, side.identifier])
            #expect(coordinator.warnings.isEmpty)
        }
    }

    @Test func nextStartsArcExpectingItsBookmarksPageAndNoPasswordPage() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try begin(scene)
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .importing)
            #expect(coordinator.setupPage == .progress && coordinator.setupPagesAhead == [.bookmarks])
        }
    }

    @Test func stoppingWhileTheSidebarIsReadAddsNothing() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try begin(scene)
            let spaces = scene.store.state.spaces
            coordinator.continueSourceInline()
            coordinator.stopImport()
            scene.engine.settle()
            #expect(coordinator.stage == .finished && scene.store.state.spaces == spaces)
            #expect(scene.engine.browserRequests.isEmpty)
        }
    }

    @Test func theDefaultArcProfileBringsItsSpaceAndTabsIntoTheOpenedProfile() throws {
        try BrowserImportScene.run { scene in
            _ = try imported(scene)
            let work = scene.store.state.spaces.first { $0.title == "Work" }
            #expect(work?.profileID == scene.destination.profileID)
            #expect(scene.store.state.tabs.contains { $0.spaceID == work?.id && $0.kind == .pinned })
            #expect(scene.store.state.tabs.contains { $0.kind == .today && $0.savedURL == "https://example.test/today" })
        }
    }

    @Test func theDefaultArcRequestUsesTheOpenedProfilesPath() throws {
        try BrowserImportScene.run { scene in
            _ = try imported(scene)
            let request = try #require(scene.engine.browserRequests.first)
            #expect(request.profile === standard && request.path == scene.originalPath)
        }
    }

    @Test func anotherArcProfileBecomesAParcProfileWithItsSpacesAndArchiveAge() throws {
        try BrowserImportScene.run { scene in
            _ = try imported(scene)
            let sideProfile = try #require(scene.store.state.profiles.first { $0.name == "Side" })
            #expect(scene.store.state.spaces.contains { $0.title == "Side" && $0.profileID == sideProfile.id })
            #expect(sideProfile.autoArchiveHours == 720)
            #expect(scene.store.state.profiles.first { $0.id == scene.destination.profileID }?.autoArchiveHours
                    == AutoArchiveInterval.twelveHours.rawValue)
        }
    }

    @Test func eachOtherArcProfileImportsIntoItsOwnParcProfile() throws {
        try BrowserImportScene.run { scene in
            _ = try imported(scene)
            scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("arc bookmark", title: "Docs",
                url: "https://example.test/docs")], warnings: ["fixture warning"])
            let sideProfile = try #require(scene.store.state.profiles.first { $0.name == "Side" })
            let requests = scene.engine.browserRequests
            #expect(requests.count == 3 && requests[0].categories == [.bookmarks])
            #expect(requests[1].profile === standard && requests[2].profile === side)
            #expect(requests[2].path == scene.path(sideProfile.id))
        }
    }

    @Test func completedArcBookmarksKeepTheirDestination() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try imported(scene)
            scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("arc bookmark", title: "Docs",
                url: "https://example.test/docs")], warnings: ["fixture warning"])
            scene.engine.finishAllBrowser()
            #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.first?.destination == scene.destination)
        }
    }

    @Test func arcImportWarningsAreNotReportedAsFailedData() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try imported(scene)
            scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("arc bookmark", title: "Docs",
                url: "https://example.test/docs")], warnings: ["fixture warning"])
            scene.engine.finishAllBrowser()
            #expect(coordinator.warnings == ["fixture warning"])
            coordinator.cancel()
            #expect(ImportedBrowserDataFailures.take() == nil)
        }
    }

    @Test func aMissingArcSidebarDoesNotProduceAnImportWarning() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try begin(scene, sidebar: scene.directory.appendingPathComponent("NoArc/StorableSidebar.json"))
            coordinator.continueSourceInline()
            scene.engine.settle()
            #expect(coordinator.warnings.isEmpty)
        }
    }

    @Test func withoutTheArcSidebarBrowserDataStillImportsIntoTheUsualProfiles() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try begin(scene, sidebar: scene.directory.appendingPathComponent("NoArc/StorableSidebar.json"))
            coordinator.continueSourceInline()
            scene.engine.settle()
            #expect(scene.engine.browserRequests.first?.path == scene.originalPath)
            scene.engine.finishBrowser()
            let fallbackSide = try #require(scene.store.state.profiles.first { $0.name == "Side" })
            #expect(scene.engine.browserRequests.last?.path == scene.path(fallbackSide.id))
            scene.engine.finishAllBrowser()
            #expect(coordinator.stage == .finished)
        }
    }

    @Test func oneInstallCoversEveryArcProfilesExtensionsEachIntoItsOwnProfile() throws {
        try BrowserImportScene.run { scene in
            let blocker = ImportFixture.extensionItem(OnboardingAdBlocker.uBlockOrigin, "uBlock Origin")
            let broken = ImportFixture.extensionItem("broken", "Broken")
            let helper = ImportFixture.extensionItem("helper", "Helper")
            let withExtensions = ImportFixture.profile("arc ext standard", [.history, .extensions], name: "Person 1",
                                                       directory: "Default", extensions: [blocker, broken])
            let onlyExtensions = ImportFixture.profile("arc ext side", [.extensions], name: "Side", directory: "Profile 1",
                                                       extensions: [blocker, helper])
            let setup = scene.chosen(scene.arc(), profiles: ImportFixture.profiles([withExtensions, onlyExtensions]),
                onboarding: true, arcSidebar: try BrowserImportScene.arcSidebar(), arcPreferences: try preferences(scene))
            setup.continueSourceInline()
            scene.engine.settle()
            scene.engine.finishBrowser()
            let sideID = try #require(scene.store.state.profiles.first { $0.name == "Side" }?.id)
            #expect(scene.engine.browserRequests.count == 1 && scene.engine.extensionInstalls.count == 1)
            let together = try #require(scene.engine.extensionInstalls.last)
            #expect(together.requests.count == 2)
            #expect(together.requests.map { ImportFixture.requestSource($0) } == [withExtensions, onlyExtensions])
            #expect(together.requests.map(ImportFixture.requestIDs) == [[blocker.identifier, broken.identifier],
                                                                         [blocker.identifier, helper.identifier]])
            #expect(ImportFixture.requestPath(together.requests[1]) == scene.path(sideID))
            #expect(setup.stage == .finished && setup.hasBackgroundWork)
            together.complete(ImportFixture.extensionResult(.partial, installed: [blocker.identifier, helper.identifier]),
                              [ImportFixture.failure(broken.displayName, identifier: broken.identifier, path: scene.originalPath)])
            let home = try #require(scene.store.state.profiles.first { $0.id == scene.destination.profileID }?.name)
            #expect(ImportedExtensionFailures.pending == [.init(name: "Broken", profile: home,
                target: "import " + scene.destination.profileID.uuidString + " " + broken.identifier)])
            #expect(setup.stage == .finished && setup.warnings.contains("Broken couldn’t be added."))
            #expect(setup.importedAdBlockers == [.init(identifier: blocker.identifier, displayName: blocker.displayName,
                                                       profileIDs: [scene.destination.profileID, sideID])])
        }
    }
}
