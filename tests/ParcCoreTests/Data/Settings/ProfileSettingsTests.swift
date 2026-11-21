import Foundation
import Testing
@testable import ParcCore

@MainActor
struct ProfileSettingsTests {
    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-Profile-Settings-" + UUID().uuidString)
        let store: BrowserStore
        let original: BrowserState
        let id: UUID
        var stateFile: URL { directory.appendingPathComponent("session.json") }

        init() throws {
            store = try BrowserStore(directory: directory)
            original = store.state
            id = original.profiles[0].id
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func renamed() throws {
            try store.saveProfileName(id, expectedName: "Default", name: "  Personal — 夜空  ")
        }

        func refuseWrites() throws {
            try FileManager.default.removeItem(at: stateFile)
            try FileManager.default.createDirectory(at: stateFile, withIntermediateDirectories: false)
        }
    }

    @Test func renameTrimsOnlyOuterWhitespace() throws {
        let fixture = try Fixture()
        try fixture.renamed()
        #expect(fixture.store.state.profiles[0].name == "Personal — 夜空")
    }

    @Test func renamePreservesEverySpaceAndTab() throws {
        let fixture = try Fixture()
        try fixture.renamed()
        #expect(fixture.store.state.spaces == fixture.original.spaces && fixture.store.state.tabs == fixture.original.tabs)
    }

    @Test func renamePreservesNativeIdentity() throws {
        let fixture = try Fixture()
        let nativePath = fixture.store.independentEngineProfilePath(for: fixture.id)
        try fixture.renamed()
        #expect(fixture.store.independentEngineProfilePath(for: fixture.id) == nativePath)
    }

    @Test func rejectedEditsDoNotPublishAChangedModelOrTouchTheSavedSession() throws {
        let fixture = try Fixture()
        let store = fixture.store
        try fixture.renamed()
        let saved = try Data(contentsOf: fixture.stateFile)
        let afterRename = store.state
        #expect(throws: (any Error).self) { try store.saveProfileName(fixture.id, expectedName: "Default", name: "Stale overwrite") }
        #expect(throws: (any Error).self) { try store.saveProfileName(fixture.id, expectedName: "Personal — 夜空", name: " \n ") }
        #expect(throws: (any Error).self) { try store.saveProfileName(UUID(), expectedName: "Missing", name: "New") }
        #expect(store.state == afterRename)
        let actual1 = try Data(contentsOf: fixture.stateFile)
        #expect(actual1 == saved)
    }

    @Test func paneAndIndependentProfileSelectionSurviveANewStoreWithoutReassigningSpaces() throws {
        let fixture = try Fixture()
        try fixture.store.saveSettingsSelection(pane: "Profiles", profileID: fixture.id)
        let restarted = try BrowserStore(directory: fixture.directory)
        #expect(restarted.state.settings.settingsPane == "Profiles" && restarted.state.settings.settingsProfileID == fixture.id)
        #expect(restarted.state.spaces == fixture.original.spaces)
    }

    @Test func aSelectionForAnUnknownProfileIsRejected() throws {
        let fixture = try Fixture()
        #expect(throws: (any Error).self) { try fixture.store.saveSettingsSelection(pane: "Profiles", profileID: UUID()) }
    }

    @Test func explicitGeneralAndSidebarControlsPersistBeforeReturning() throws {
        let fixture = try Fixture()
        try fixture.store.saveRestoreSession(false)
        try fixture.store.saveSidebarWidth(310)
        let restored = try BrowserStore(directory: fixture.directory)
        #expect(!restored.state.settings.restoreSession && restored.state.settings.sidebarWidth == 310)
    }

    @Test func theSidebarPreferenceKeepsTheProductionBoundsAndInvalidWidthsNeverContaminateState() throws {
        let fixture = try Fixture()
        try fixture.store.saveSidebarWidth(900)
        #expect(fixture.store.state.settings.sidebarWidth == 500)
        #expect(throws: (any Error).self) { try fixture.store.saveSidebarWidth(.nan) }
        #expect(fixture.store.state.settings.sidebarWidth == 500)
    }

    @Test func profileCommandsPreferTheirOriginalSpace() throws {
        let fixture = try Fixture()
        let space = fixture.original.spaces[0]
        #expect(fixture.store.settingsPageSpace(profileID: fixture.id, originatingSpaceID: space.id)?.id == space.id)
    }

    @Test func anUnassignedEditingProfileCannotBorrowTheCurrentProfilesPage() throws {
        let fixture = try Fixture()
        let other = fixture.store.createProfile(name: "Other")
        #expect(fixture.store.settingsPageSpace(profileID: other, originatingSpaceID: fixture.original.spaces[0].id) == nil)
    }

    @Test func independentProfileSelectionResolvesItsActualSpaceWithoutReassigningTheOriginal() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let originalSpace = fixture.original.spaces[0]
        let other = store.createProfile(name: "Other")
        let otherSpace = store.createSpace(name: "Other Space")
        store.assignProfile(other, toSpace: otherSpace)
        #expect(store.settingsPageSpace(profileID: other, originatingSpaceID: originalSpace.id)?.id == otherSpace)
        #expect(store.state.spaces.first { $0.id == originalSpace.id }?.profileID == fixture.id)
    }

    @Test func removedAndStaleProfilesRefusePageCommands() throws {
        let fixture = try Fixture()
        #expect(fixture.store.settingsPageSpace(profileID: UUID(), originatingSpaceID: fixture.original.spaces[0].id) == nil)
    }

    @Test func aRetiringProfileNeverAdmitsASettingsPage() throws {
        let fixture = try Fixture()
        let unused = fixture.store.createProfile(name: "Removing")
        _ = try fixture.store.stageProfileRemoval(unused, expectedName: "Removing")
        #expect(fixture.store.settingsPageSpace(profileID: unused, originatingSpaceID: nil) == nil)
    }

    @Test func credentialDetailEditsStayWithTheOriginalPasswordManagerPage() {
        #expect(ProfileSettingsPage.passwords.canReuse("chrome://password-manager/passwords/credential"))
    }

    @Test func aProfileCommandDoesNotOverwriteADifferentSettingsSubpage() {
        #expect(!ProfileSettingsPage.privacy.canReuse("parc://settings/searchEngines"))
    }

    @Test func nativeAndPublicAddressesIdentifyTheSameExactSubpage() {
        #expect(ProfileSettingsPage.notifications.canReuse("chrome://settings/content/notifications"))
    }

    @Test func foreignAndModifiedDestinationsCannotBeReusedAsExactSettingsCommands() {
        #expect(!ProfileSettingsPage.privacy.canReuse("https://settings/privacy"))
        #expect(!ProfileSettingsPage.privacy.canReuse("parc://user@settings/privacy"))
        #expect(!ProfileSettingsPage.privacy.canReuse("parc://settings:10/privacy"))
        #expect(!ProfileSettingsPage.privacy.canReuse("parc://settings/privacy?search=unfinished"))
    }

    @Test func clearBrowsingDataOpensChromiumsRealConfirmation() {
        #expect(ProfileSettingsPage.clearBrowsingData.address == "parc://settings/clearBrowserData")
    }

    @Test func existingSessionsNeedNoSettingsMigration() throws {
        let legacyData = Data("{\"sidebarWidth\":240,\"searchEngine\":\"https://example.org/?q=\",\"restoreSession\":true,\"onboardingComplete\":false}".utf8)
        let legacy = try JSONDecoder().decode(BrowserSettings.self, from: legacyData)
        #expect(legacy.settingsPane == nil && legacy.settingsProfileID == nil)
    }

    @Test func aFailedRenameKeepsStateAndReportsTheFailure() throws {
        let fixture = try Fixture()
        try fixture.renamed()
        try fixture.refuseWrites()
        let before = fixture.store.state
        #expect(throws: (any Error).self) { try fixture.store.saveProfileName(fixture.id, expectedName: "Personal — 夜空", name: "Unsaved") }
        #expect(fixture.store.state == before && fixture.store.persistenceError != nil)
    }

    @Test func failedSelectionAndPreferenceWritesPreserveThePublishedValuesAndCleanTheirTemporaryFile() throws {
        let fixture = try Fixture()
        try fixture.store.saveRestoreSession(false)
        try fixture.refuseWrites()
        let before = fixture.store.state
        #expect(throws: (any Error).self) { try fixture.store.saveSettingsSelection(pane: "General", profileID: fixture.id) }
        #expect(fixture.store.state == before)
        #expect(throws: (any Error).self) { try fixture.store.saveRestoreSession(true) }
        #expect(throws: (any Error).self) { try fixture.store.saveSidebarWidth(220) }
        #expect(fixture.store.state == before)
        let actual2 = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
        #expect(actual2 == ["session.json"])
    }

    @Test func aSuccessfulRetryClearsTheWriteErrorAndKeepsPrivateFilePermissions() throws {
        let fixture = try Fixture()
        try fixture.renamed()
        try fixture.refuseWrites()
        #expect(throws: (any Error).self) { try fixture.store.saveProfileName(fixture.id, expectedName: "Personal — 夜空", name: "Unsaved") }
        try FileManager.default.removeItem(at: fixture.stateFile)
        try fixture.store.saveProfileName(fixture.id, expectedName: "Personal — 夜空", name: "Retry works")
        #expect(fixture.store.persistenceError == nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.stateFile.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
