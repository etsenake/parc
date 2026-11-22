import Foundation
import Testing
@testable import ParcCore

struct SessionBackupStorePolicyTests {
    private typealias Support = SessionBackupTestsSupport

    @Test
    @MainActor
    static func privateStoresNeverWriteBackups() throws {
        try Support.withDirectory { directory in
            let regular = try BrowserStore(directory: directory)
            let incognito = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                         directory: directory, settings: regular.state.settings, now: { Support.base })
            _ = incognito.openResolvedURL(URL(string: "https://private.test/")!)
            try incognito.save()
            incognito.forgetHistory(Support.deletion(["allHistory": true]))
            #expect(!FileManager.default.fileExists(atPath: SessionBackups.folder(in: directory).path), "Private windows never write backups")
        }
    }

    @Test
    @MainActor
    static func plainStoresPruneExistingBackupsWithoutMakingNewOnes() throws {
        try Support.withDirectory { directory in
            let clock = Support.Clock(Support.base)
            let keeping = try Support.backingStore(directory, clock)
            try Support.flush(keeping)
            #expect(SessionBackups.list(in: directory).count == 1, "A kept copy exists")
            let plain = try BrowserStore(directory: directory)
            plain.forgetHistory(Support.deletion(["allHistory": true]))
            #expect(SessionBackups.list(in: directory).isEmpty, "Even a store that writes no backups prunes existing ones")
        }
    }
}
