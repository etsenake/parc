import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import Parc

@MainActor @Suite(.serialized)
struct BrowserImportBackgroundTests {
    private let blocker: PCNativeImportExtension
    private let broken: PCNativeImportExtension
    private let first: PCNativeImportProfile

    init() {
        blocker = ImportFixture.extensionItem(OnboardingAdBlocker.uBlockOrigin, "uBlock Origin")
        broken = ImportFixture.extensionItem("broken", "Broken")
        first = ImportFixture.profile("background default", [.bookmarks, .history, .extensions], directory: "Default",
                                      extensions: [blocker, broken])
    }
    private let second = ImportFixture.profile("background second", [.bookmarks, .history], name: "Other")
    private var bookmarked: PCNativeImportResult { ImportFixture.result(.completed, bookmarks: [ImportFixture.bookmark()]) }

    private func readingBoth(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
        let coordinator = scene.started(try scene.impostor(), [first, second], onboarding: true)
        scene.engine.browserCompletions.removeFirst()(bookmarked)
        scene.engine.browserCompletions.removeFirst()(bookmarked)
        return coordinator
    }

    @Test func bookmarksStartFirstAndOtherDestinationsWaitForTheirTurn() throws {
        try BrowserImportScene.run { scene in
            _ = scene.started(try scene.impostor(), [first, second], onboarding: true)
            #expect(scene.engine.browserRequests.first?.categories == [.bookmarks])
            #expect(!scene.store.state.profiles.contains { $0.name == "Other" })
        }
    }

    @Test func everyBookmarkPassPrecedesBackgroundData() throws {
        try BrowserImportScene.run { scene in
            _ = scene.started(try scene.impostor(), [first, second], onboarding: true)
            scene.engine.browserCompletions.removeFirst()(bookmarked)
            #expect(scene.engine.browserRequests.count == 2 && scene.engine.browserRequests.last?.categories == [.bookmarks])
        }
    }

    @Test func resultsAppearWhileBothProfilesImportIntoDistinctPaths() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try readingBoth(scene)
            let requests = Array(scene.engine.browserRequests.suffix(2))
            #expect(coordinator.stage == .bookmarks && coordinator.hasBackgroundWork)
            #expect(scene.engine.browserCompletions.count == 2)
            #expect(requests.allSatisfy { $0.categories == [.history] } && requests[0].path != requests[1].path)
        }
    }

    @Test func detachedWorkKeepsItsCoordinatorUntilExtensionsFinishThenReportsEverything() throws {
        try BrowserImportScene.run { scene in
            var window: NSWindow? = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
            var current = true
            var coordinator: BrowserImportCoordinator? = BrowserImportCoordinator(store: scene.store,
                destination: scene.destination, window: window!, onboarding: true, supportsICloudPasswords: false,
                native: scene.engine, ownerIsCurrent: { current })
            weak let retained = coordinator
            let impostor = try scene.impostor()
            scene.discovered(coordinator!, [impostor])
            coordinator!.selectSourceInline(impostor)
            scene.engine.profiles.removeFirst().complete(ImportFixture.profiles([first, second]))
            coordinator!.continueSourceInline()
            scene.engine.browserCompletions.removeFirst()(bookmarked)
            scene.engine.browserCompletions.removeFirst()(bookmarked)
            var changes = 0, delivered: [OnboardingDraft.ImportedAdBlocker] = []
            coordinator!.onChange = { changes += 1 }
            coordinator!.detach { delivered = $0 }
            current = false; window = nil; coordinator = nil
            #expect(retained != nil)
            let firstCompletion = scene.engine.browserCompletions.removeFirst()
            let secondCompletion = scene.engine.browserCompletions.removeFirst()
            secondCompletion(ImportFixture.result(.failed, warnings: ["Some data was unavailable."]))
            #expect(scene.engine.extensionInstalls.isEmpty && retained?.hasBackgroundWork == true)
            firstCompletion(ImportFixture.result(.completed))
            let install = try #require(scene.engine.extensionInstalls.first)
            #expect(retained?.hasBackgroundWork == true && changes == 0)
            #expect(ImportedBrowserDataFailures.pending == nil)
            install.complete(ImportFixture.extensionResult(.partial, installed: [blocker.identifier]),
                             [ImportFixture.failure(broken.displayName, identifier: broken.identifier, path: scene.originalPath)])
            let notice = ImportedExtensionFailures.take()
            #expect(retained == nil)
            #expect(delivered == [.init(identifier: blocker.identifier, displayName: blocker.displayName,
                                        profileIDs: [scene.destination.profileID])])
            #expect(ImportedBrowserDataFailures.take() == .partial)
            #expect(notice?.failures == [.init(name: broken.displayName,
                target: "import " + scene.destination.profileID.uuidString + " " + broken.identifier)])
            #expect(notice?.canRetry == true)
            install.background([ImportFixture.failure(blocker.displayName, identifier: blocker.identifier, path: scene.originalPath)])
            let late = ImportedExtensionFailures.take()
            #expect(late?.failures == [.init(name: blocker.displayName,
                target: "import " + scene.destination.profileID.uuidString + " " + blocker.identifier)])
            #expect(late?.canRetry == true)
        }
    }

    @Test func stoppingAfterAProfileFailedReportsAPartialImportOnce() throws {
        try BrowserImportScene.run { scene in
            let failing = ImportFixture.profile("stop failing", [.bookmarks], directory: "Default")
            let later = ImportFixture.profile("stop later", [.bookmarks], name: "Later")
            let coordinator = scene.started(try scene.impostor(), [failing, later], onboarding: true)
            scene.engine.finishBrowser(.failed)
            #expect(ImportedBrowserDataFailures.pending == nil)
            coordinator.stopImport()
            scene.engine.finishBrowser(.cancelled)
            #expect(coordinator.stage == .finished && ImportedBrowserDataFailures.take() == .partial)
            coordinator.cancel()
            #expect(ImportedBrowserDataFailures.take() == nil)
        }
    }
}

@MainActor @Suite(.serialized)
struct BrowserImportArcTests {
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

    @Test func theDefaultArcProfileBringsItsSpacesPinnedAndTodayTabsIntoTheOpenedProfile() throws {
        try BrowserImportScene.run { scene in
            _ = try imported(scene)
            let work = scene.store.state.spaces.first { $0.title == "Work" }
            #expect(work?.profileID == scene.destination.profileID)
            #expect(scene.store.state.tabs.contains { $0.spaceID == work?.id && $0.kind == .pinned })
            #expect(scene.store.state.tabs.contains { $0.kind == .today && $0.savedURL == "https://example.test/today" })
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

    @Test func eachOtherArcProfileImportsIntoItsOwnParcProfileAndLandsLikeChrome() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try imported(scene)
            scene.engine.finishBrowser(bookmarks: [ImportFixture.bookmark("arc bookmark", title: "Docs",
                url: "https://example.test/docs")], warnings: ["fixture warning"])
            let sideProfile = try #require(scene.store.state.profiles.first { $0.name == "Side" })
            let requests = scene.engine.browserRequests
            #expect(requests.count == 3 && requests[0].categories == [.bookmarks])
            #expect(requests[1].profile === standard && requests[2].profile === side)
            #expect(requests[2].path == scene.path(sideProfile.id))
            scene.engine.finishAllBrowser()
            #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.first?.destination == scene.destination)
            #expect(coordinator.warnings == ["fixture warning"])
            coordinator.cancel()
            #expect(ImportedBrowserDataFailures.take() == nil)
        }
    }

    @Test func withoutTheSidebarBrowserDataStillImportsIntoTheUsualProfiles() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try begin(scene, sidebar: scene.directory.appendingPathComponent("NoArc/StorableSidebar.json"))
            coordinator.continueSourceInline()
            scene.engine.settle()
            #expect(coordinator.warnings.isEmpty)
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
