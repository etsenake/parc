import Foundation
import Testing
@testable import ParcCore

struct ProfileSettingsTests {
    @MainActor private final class Fixture {
        let directory = CommandBarFixtures.temporaryDirectory("profile-settings")
        let store: BrowserStore
        let original: BrowserState
        let id: UUID

        var sessionFile: URL { directory.appendingPathComponent("session.json") }

        init() throws {
            store = try BrowserStore(directory: directory)
            store.scheduleDeferredSave = { _, _ in }
            original = store.state
            id = original.profiles[0].id
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func renamed() throws {
            try store.saveProfileName(id, expectedName: "Default", name: "  Personal — 夜空  ")
        }

        func breakSessionFile() throws {
            try? FileManager.default.removeItem(at: sessionFile)
            try FileManager.default.createDirectory(at: sessionFile, withIntermediateDirectories: false)
        }
    }

    @Test @MainActor func renameTrimsOnlyOuterWhitespace() throws {
        let fixture = try Fixture()
        try fixture.renamed()
        #expect(fixture.store.state.profiles[0].name == "Personal — 夜空")
    }

    @Test @MainActor func renamePreservesEverySpaceAndTab() throws {
        let fixture = try Fixture()
        try fixture.renamed()
        #expect(fixture.store.state.spaces == fixture.original.spaces)
        #expect(fixture.store.state.tabs == fixture.original.tabs)
    }

    @Test @MainActor func renamePreservesNativeIdentity() throws {
        let fixture = try Fixture()
        let nativePath = fixture.store.independentEngineProfilePath(for: fixture.id)
        try fixture.renamed()
        #expect(fixture.store.independentEngineProfilePath(for: fixture.id) == nativePath)
    }

    enum RejectedEdit: CaseIterable { case stale, blank, missing }

    @Test(arguments: RejectedEdit.allCases)
    @MainActor func rejectedEditsKeepThePublishedAndSavedSession(edit: RejectedEdit) throws {
        let fixture = try Fixture()
        try fixture.renamed()
        let saved = try Data(contentsOf: fixture.sessionFile)
        let afterRename = fixture.store.state
        let id = edit == .missing ? UUID() : fixture.id
        let expected = edit == .stale ? "Default" : "Personal — 夜空"
        let name = edit == .blank ? " \n " : "New"
        #expect(throws: (any Error).self) { try fixture.store.saveProfileName(id, expectedName: expected, name: name) }
        #expect(fixture.store.state == afterRename)
        #expect(try Data(contentsOf: fixture.sessionFile) == saved)
    }

    @Test @MainActor func paneAndIndependentProfileSelectionSurviveANewStore() throws {
        let fixture = try Fixture()
        try fixture.store.saveSettingsSelection(pane: "Profiles", profileID: fixture.id)
        let restarted = try BrowserStore(directory: fixture.directory)
        #expect(restarted.state.settings.settingsPane == "Profiles")
        #expect(restarted.state.settings.settingsProfileID == fixture.id)
        #expect(restarted.state.spaces == fixture.original.spaces)
    }

    @Test @MainActor func aSelectionForAnUnknownProfileIsRejected() throws {
        let fixture = try Fixture()
        #expect(throws: (any Error).self) { try fixture.store.saveSettingsSelection(pane: "Profiles", profileID: UUID()) }
    }

    @Test @MainActor func theSessionRestorePreferencePersistsBeforeReturning() throws {
        let fixture = try Fixture()
        try fixture.store.saveRestoreSession(false)
        let restored = try BrowserStore(directory: fixture.directory)
        #expect(!restored.state.settings.restoreSession)
    }

    @Test @MainActor func theSidebarWidthPreferencePersistsBeforeReturning() throws {
        let fixture = try Fixture()
        try fixture.store.saveSidebarWidth(310)
        let restored = try BrowserStore(directory: fixture.directory)
        #expect(restored.state.settings.sidebarWidth == 310)
    }

    @Test @MainActor func theSidebarPreferenceKeepsTheProductionBounds() throws {
        let fixture = try Fixture()
        try fixture.store.saveSidebarWidth(900)
        #expect(fixture.store.state.settings.sidebarWidth == 500)
    }

    @Test @MainActor func invalidWidthsNeverContaminateDurableState() throws {
        let fixture = try Fixture()
        try fixture.store.saveSidebarWidth(900)
        #expect(throws: (any Error).self) { try fixture.store.saveSidebarWidth(.nan) }
        #expect(fixture.store.state.settings.sidebarWidth == 500)
    }

    @Test @MainActor func profileCommandsPreferTheirOriginalSpace() throws {
        let fixture = try Fixture()
        let originalSpace = fixture.original.spaces[0]
        #expect(fixture.store.settingsPageSpace(profileID: fixture.id, originatingSpaceID: originalSpace.id)?.id == originalSpace.id)
    }

    @Test @MainActor func anUnassignedEditingProfileCannotBorrowTheCurrentProfilesPage() throws {
        let fixture = try Fixture()
        let other = fixture.store.createProfile(name: "Other")
        #expect(fixture.store.settingsPageSpace(profileID: other, originatingSpaceID: fixture.original.spaces[0].id) == nil)
    }

    @Test @MainActor func independentProfileSelectionResolvesItsActualSpaceWithoutReassigningTheOriginal() throws {
        let fixture = try Fixture()
        let originalSpace = fixture.original.spaces[0]
        let other = fixture.store.createProfile(name: "Other")
        let otherSpace = fixture.store.createSpace(name: "Other Space")
        fixture.store.assignProfile(other, toSpace: otherSpace)
        #expect(fixture.store.settingsPageSpace(profileID: other, originatingSpaceID: originalSpace.id)?.id == otherSpace)
        #expect(fixture.store.state.spaces.first { $0.id == originalSpace.id }?.profileID == fixture.id)
    }

    @Test @MainActor func removedAndStaleProfilesRefusePageCommands() throws {
        let fixture = try Fixture()
        #expect(fixture.store.settingsPageSpace(profileID: UUID(), originatingSpaceID: fixture.original.spaces[0].id) == nil)
    }

    @Test @MainActor func aRetiringProfileNeverAdmitsASettingsPage() throws {
        let fixture = try Fixture()
        let unused = fixture.store.createProfile(name: "Removing")
        _ = try fixture.store.stageProfileRemoval(unused, expectedName: "Removing")
        #expect(fixture.store.settingsPageSpace(profileID: unused, originatingSpaceID: nil) == nil)
    }

    @Test func credentialDetailEditsStayWithTheOriginalPasswordManagerPage() {
        #expect(ProfileSettingsPage.passwords.canReuse("chrome://password-manager/passwords/credential"))
    }

    @Test func aProfileCommandMustNotOverwriteADifferentSettingsSubpage() {
        #expect(!ProfileSettingsPage.privacy.canReuse("parc://settings/searchEngines"))
    }

    @Test func nativeAndPublicAddressesIdentifyTheSameExactSubpage() {
        #expect(ProfileSettingsPage.notifications.canReuse("chrome://settings/content/notifications"))
    }

    @Test(arguments: ["https://settings/privacy", "parc://user@settings/privacy", "parc://settings:10/privacy",
                      "parc://settings/privacy?search=unfinished"])
    func foreignAndModifiedDestinationsCannotBeReusedAsExactSettingsCommands(address: String) {
        #expect(!ProfileSettingsPage.privacy.canReuse(address))
    }

    @Test func clearBrowsingDataOpensChromiumsRealConfirmationWithoutDeletingDirectly() {
        #expect(ProfileSettingsPage.clearBrowsingData.address == "parc://settings/clearBrowserData")
    }

    @Test func existingSessionsNeedNoMigration() throws {
        let legacyData = Data("{\"sidebarWidth\":240,\"searchEngine\":\"https://example.org/?q=\",\"restoreSession\":true,\"onboardingComplete\":false}".utf8)
        let legacy = try JSONDecoder().decode(BrowserSettings.self, from: legacyData)
        #expect(legacy.settingsPane == nil)
        #expect(legacy.settingsProfileID == nil)
    }

    @Test @MainActor func aFailedRenameKeepsStateAndReportsTheFailure() throws {
        let fixture = try Fixture()
        try fixture.renamed()
        try fixture.breakSessionFile()
        let before = fixture.store.state
        #expect(throws: (any Error).self) { try fixture.store.saveProfileName(fixture.id, expectedName: "Personal — 夜空", name: "Unsaved") }
        #expect(fixture.store.state == before)
        #expect(fixture.store.persistenceError != nil)
    }

    @Test @MainActor func aFailedSelectionDoesNotBecomeTheSavedOrCurrentSelection() throws {
        let fixture = try Fixture()
        try fixture.breakSessionFile()
        let before = fixture.store.state
        #expect(throws: (any Error).self) { try fixture.store.saveSettingsSelection(pane: "General", profileID: fixture.id) }
        #expect(fixture.store.state == before)
    }

    @Test @MainActor func failedExplicitPreferenceWritesPreserveThePublishedControlValues() throws {
        let fixture = try Fixture()
        try fixture.breakSessionFile()
        let before = fixture.store.state
        #expect(throws: (any Error).self) { try fixture.store.saveRestoreSession(false) }
        #expect(throws: (any Error).self) { try fixture.store.saveSidebarWidth(220) }
        #expect(fixture.store.state == before)
    }

    @Test @MainActor func failedCommitsCleanTheirTemporaryFile() throws {
        let fixture = try Fixture()
        try fixture.breakSessionFile()
        #expect(throws: (any Error).self) { try fixture.store.saveRestoreSession(false) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["session.json"])
    }

    @Test @MainActor func aSuccessfulRetryClearsTheWriteErrorAndKeepsPrivatePermissions() throws {
        let fixture = try Fixture()
        try fixture.renamed()
        try fixture.breakSessionFile()
        #expect(throws: (any Error).self) { try fixture.store.saveProfileName(fixture.id, expectedName: "Personal — 夜空", name: "Unsaved") }
        try FileManager.default.removeItem(at: fixture.sessionFile)
        try fixture.store.saveProfileName(fixture.id, expectedName: "Personal — 夜空", name: "Retry works")
        #expect(fixture.store.persistenceError == nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.sessionFile.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
