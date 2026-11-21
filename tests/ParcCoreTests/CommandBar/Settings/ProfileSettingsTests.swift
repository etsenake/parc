import Foundation
import Testing
@testable import ParcCore

@MainActor
struct ProfileSettingsTests {
    let directory = CommandBarFixtures.temporaryDirectory("profile-settings")
    let store: BrowserStore
    let original: BrowserState
    let id: UUID

    var sessionFile: URL { directory.appendingPathComponent("session.json") }

    init() throws {
        store = try BrowserStore(directory: directory)
        original = store.state
        id = original.profiles[0].id
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }

    func renamed() throws {
        try store.saveProfileName(id, expectedName: "Default", name: "  Personal — 夜空  ")
    }

    func breakSessionFile() throws {
        try? FileManager.default.removeItem(at: sessionFile)
        try FileManager.default.createDirectory(at: sessionFile, withIntermediateDirectories: false)
    }

    @Test func renameTrimsOnlyOuterWhitespace() throws {
        defer { cleanUp() }
        try renamed()
        #expect(store.state.profiles[0].name == "Personal — 夜空")
    }

    @Test func renamePreservesEverySpaceAndTab() throws {
        defer { cleanUp() }
        try renamed()
        #expect(store.state.spaces == original.spaces)
        #expect(store.state.tabs == original.tabs)
    }

    @Test func renamePreservesNativeIdentity() throws {
        defer { cleanUp() }
        let nativePath = store.independentEngineProfilePath(for: id)
        try renamed()
        #expect(store.independentEngineProfilePath(for: id) == nativePath)
    }

    @Test func rejectedEditsDoNotPublishAChangedModelOrTouchTheSavedSession() throws {
        defer { cleanUp() }
        try renamed()
        let saved = try Data(contentsOf: sessionFile)
        let afterRename = store.state
        #expect(throws: (any Error).self) { try store.saveProfileName(id, expectedName: "Default", name: "Stale overwrite") }
        #expect(throws: (any Error).self) { try store.saveProfileName(id, expectedName: "Personal — 夜空", name: " \n ") }
        #expect(throws: (any Error).self) { try store.saveProfileName(UUID(), expectedName: "Missing", name: "New") }
        #expect(store.state == afterRename)
        #expect(try Data(contentsOf: sessionFile) == saved)
    }

    @Test func paneAndIndependentProfileSelectionSurviveANewStore() throws {
        defer { cleanUp() }
        try store.saveSettingsSelection(pane: "Profiles", profileID: id)
        let restarted = try BrowserStore(directory: directory)
        #expect(restarted.state.settings.settingsPane == "Profiles")
        #expect(restarted.state.settings.settingsProfileID == id)
        #expect(restarted.state.spaces == original.spaces)
    }

    @Test func aSelectionForAnUnknownProfileIsRejected() throws {
        defer { cleanUp() }
        #expect(throws: (any Error).self) { try store.saveSettingsSelection(pane: "Profiles", profileID: UUID()) }
    }

    @Test func explicitGeneralAndSidebarControlsPersistBeforeReturning() throws {
        defer { cleanUp() }
        try store.saveRestoreSession(false)
        try store.saveSidebarWidth(310)
        let restored = try BrowserStore(directory: directory)
        #expect(!restored.state.settings.restoreSession)
        #expect(restored.state.settings.sidebarWidth == 310)
    }

    @Test func theSidebarPreferenceKeepsTheProductionBounds() throws {
        defer { cleanUp() }
        try store.saveSidebarWidth(900)
        #expect(store.state.settings.sidebarWidth == 500)
    }

    @Test func invalidWidthsNeverContaminateDurableState() throws {
        defer { cleanUp() }
        try store.saveSidebarWidth(900)
        #expect(throws: (any Error).self) { try store.saveSidebarWidth(.nan) }
        #expect(store.state.settings.sidebarWidth == 500)
    }

    @Test func profileCommandsPreferTheirOriginalSpace() {
        defer { cleanUp() }
        let originalSpace = original.spaces[0]
        #expect(store.settingsPageSpace(profileID: id, originatingSpaceID: originalSpace.id)?.id == originalSpace.id)
    }

    @Test func anUnassignedEditingProfileCannotBorrowTheCurrentProfilesPage() {
        defer { cleanUp() }
        let other = store.createProfile(name: "Other")
        #expect(store.settingsPageSpace(profileID: other, originatingSpaceID: original.spaces[0].id) == nil)
    }

    @Test func independentProfileSelectionResolvesItsActualSpaceWithoutReassigningTheOriginal() {
        defer { cleanUp() }
        let originalSpace = original.spaces[0]
        let other = store.createProfile(name: "Other")
        let otherSpace = store.createSpace(name: "Other Space")
        store.assignProfile(other, toSpace: otherSpace)
        #expect(store.settingsPageSpace(profileID: other, originatingSpaceID: originalSpace.id)?.id == otherSpace)
        #expect(store.state.spaces.first { $0.id == originalSpace.id }?.profileID == id)
    }

    @Test func removedAndStaleProfilesRefusePageCommands() {
        defer { cleanUp() }
        #expect(store.settingsPageSpace(profileID: UUID(), originatingSpaceID: original.spaces[0].id) == nil)
    }

    @Test func aRetiringProfileNeverAdmitsASettingsPage() throws {
        defer { cleanUp() }
        let unused = store.createProfile(name: "Removing")
        _ = try store.stageProfileRemoval(unused, expectedName: "Removing")
        #expect(store.settingsPageSpace(profileID: unused, originatingSpaceID: nil) == nil)
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

    @Test func aFailedRenameKeepsStateAndReportsTheFailure() throws {
        defer { cleanUp() }
        try renamed()
        try breakSessionFile()
        let before = store.state
        #expect(throws: (any Error).self) { try store.saveProfileName(id, expectedName: "Personal — 夜空", name: "Unsaved") }
        #expect(store.state == before)
        #expect(store.persistenceError != nil)
    }

    @Test func aFailedSelectionDoesNotBecomeTheSavedOrCurrentSelection() throws {
        defer { cleanUp() }
        try breakSessionFile()
        let before = store.state
        #expect(throws: (any Error).self) { try store.saveSettingsSelection(pane: "General", profileID: id) }
        #expect(store.state == before)
    }

    @Test func failedExplicitPreferenceWritesPreserveThePublishedControlValues() throws {
        defer { cleanUp() }
        try breakSessionFile()
        let before = store.state
        #expect(throws: (any Error).self) { try store.saveRestoreSession(false) }
        #expect(throws: (any Error).self) { try store.saveSidebarWidth(220) }
        #expect(store.state == before)
    }

    @Test func failedCommitsCleanTheirTemporaryFile() throws {
        defer { cleanUp() }
        try breakSessionFile()
        #expect(throws: (any Error).self) { try store.saveRestoreSession(false) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["session.json"])
    }

    @Test func aSuccessfulRetryClearsTheWriteErrorAndKeepsPrivatePermissions() throws {
        defer { cleanUp() }
        try renamed()
        try breakSessionFile()
        #expect(throws: (any Error).self) { try store.saveProfileName(id, expectedName: "Personal — 夜空", name: "Unsaved") }
        try FileManager.default.removeItem(at: sessionFile)
        try store.saveProfileName(id, expectedName: "Personal — 夜空", name: "Retry works")
        #expect(store.persistenceError == nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: sessionFile.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
