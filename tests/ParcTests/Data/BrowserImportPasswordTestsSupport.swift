import AppKit
import ParcCore
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import ParcOnboarding

@Suite(.serialized)
enum BrowserImportPasswordTestsSupport {
    @MainActor struct PasswordFixture {
        let file = URL(fileURLWithPath: "/fixture/Passwords.csv")

        let profile = ImportFixture.profile("Safari", [.history], .complete)

        func passwords(_ scene: BrowserImportScene, source: PCNativeImportSource? = nil) throws -> BrowserImportCoordinator {
            scene.started(try source ?? scene.safari(), [profile])
        }

        func submitted(_ scene: BrowserImportScene) throws
            -> (BrowserImportCoordinator, BrowserImportEngineFake.PasswordRequest) {
            let coordinator = try passwords(scene)
            coordinator.importPasswordFile(file)
            return (coordinator, scene.engine.passwordRequests.removeFirst())
        }

        func confirmed(_ scene: BrowserImportScene) throws
            -> (BrowserImportCoordinator, BrowserImportEngineFake.PasswordRequest) {
            let (coordinator, request) = try submitted(scene)
            request.complete(ImportFixture.password(.completed, imported: 3, existing: 2, canRemove: true))
            return (coordinator, request)
        }
    }

    @MainActor struct SetupFixture {
        let selected = ImportFixture.bookmark("selected", title: "Keep", url: "https://example.org/setup-keep")

        let omitted = ImportFixture.bookmark("omitted", title: "Leave", url: "https://example.org/setup-leave")

        let file = URL(fileURLWithPath: "/fixture/Passwords.csv")

        func start(_ scene: BrowserImportScene, onboarding: Bool = true, iCloud: Bool = false) throws -> BrowserImportCoordinator {
            let profile = ImportFixture.profile("Safari setup", [.history, .bookmarks])
            return scene.started(try scene.safari(), [profile], onboarding: onboarding, iCloud: iCloud)
        }

        func read(_ scene: BrowserImportScene, _ bookmarks: [PCNativeImportedBookmark],
                          outcome: PCNativeImportOutcome = .completed) {
            scene.engine.finishBrowser(outcome, bookmarks: bookmarks)
            scene.engine.finishAllBrowser()
        }

        func tabs(_ scene: BrowserImportScene, _ bookmark: PCNativeImportedBookmark) -> [BrowserTab] {
            scene.store.state.tabs.filter { $0.url == bookmark.url?.absoluteString }
        }

        func readAndSkipped(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
            let coordinator = try start(scene)
            read(scene, [selected, omitted])
            coordinator.skipInSetup()
            return coordinator
        }

        func addedWithPasswords(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
            let coordinator = try readAndSkipped(scene)
            coordinator.goBackInSetup()
            coordinator.commitBookmarks()
            coordinator.importPasswordFile(file)
            scene.engine.passwordRequests.removeFirst().complete(ImportFixture.password(.completed, imported: 2))
            coordinator.goBackInSetup()
            return coordinator
        }
    }
}
