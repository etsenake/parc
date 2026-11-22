import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import Parc

@Suite(.serialized)
enum BrowserImportProfileMappingTestsSupport {
    @MainActor struct Fixture {
        let work = ImportFixture.profile("chrome work", [.history, .bookmarks], name: "Work", directory: "Profile 1")
        let main = ImportFixture.profile("chrome main", [.history, .bookmarks], name: "Josh", directory: "Default")
        let side = ImportFixture.profile("chrome side", [.history, .bookmarks], name: "Side", directory: "Profile 2")
        var three: [PCNativeImportProfile] { [work, main, side] }

        func chrome(_ scene: BrowserImportScene) -> PCNativeImportSource {
            ImportFixture.source("Google Chrome", scene.directory.appendingPathComponent("Mapping Chrome.app"))
        }

    }

    @MainActor static func paths(_ scene: BrowserImportScene, _ profile: PCNativeImportProfile) -> [String] {
        scene.engine.browserRequests.filter { $0.profile === profile }.map(\.path)
    }
}
