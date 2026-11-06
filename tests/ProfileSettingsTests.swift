import Foundation

@main
@MainActor
struct ProfileSettingsTests {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !value() { throw Failure(message: message) }
    }
    static func rejects(_ operation: () throws -> Void) throws {
        do { try operation() } catch { assertions += 1; return }
        throw Failure(message: "Expected the operation to fail")
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-Profile-Settings-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let original = store.state
        let id = original.profiles[0].id
        let nativePath = store.independentEngineProfilePath(for: id)
        try store.saveProfileName(id, expectedName: "Default", name: "  Personal — 夜空  ")
        try expect(store.state.profiles[0].name == "Personal — 夜空", "Rename must trim only outer whitespace")
        try expect(store.state.spaces == original.spaces && store.state.tabs == original.tabs,
                   "Rename must preserve every Space and tab")
        try expect(store.independentEngineProfilePath(for: id) == nativePath, "Rename must preserve native identity")
        let saved = try Data(contentsOf: directory.appendingPathComponent("session.json"))
        let afterRename = store.state
        try rejects { try store.saveProfileName(id, expectedName: "Default", name: "Stale overwrite") }
        try rejects { try store.saveProfileName(id, expectedName: "Personal — 夜空", name: " \n ") }
        try rejects { try store.saveProfileName(UUID(), expectedName: "Missing", name: "New") }
        try expect(store.state == afterRename, "Rejected edits must not publish a changed model")
        try expect(try Data(contentsOf: directory.appendingPathComponent("session.json")) == saved,
                   "Rejected edits must preserve the saved session")
        try store.saveSettingsSelection(pane: "Profiles", profileID: id)
        let restarted = try BrowserStore(directory: directory)
        try expect(restarted.state.settings.settingsPane == "Profiles" && restarted.state.settings.settingsProfileID == id,
                   "Pane and independent profile selection must survive a new store")
        try expect(restarted.state.spaces == original.spaces, "Settings selection must not reassign Spaces")
        try rejects { try store.saveSettingsSelection(pane: "Profiles", profileID: UUID()) }

        try store.saveRestoreSession(false)
        try store.saveSidebarWidth(310)
        let restoredPreferences = try BrowserStore(directory: directory)
        try expect(!restoredPreferences.state.settings.restoreSession && restoredPreferences.state.settings.sidebarWidth == 310,
                   "Explicit General and sidebar controls persist before returning")
        try store.saveSidebarWidth(900)
        try expect(store.state.settings.sidebarWidth == 500, "Explicit sidebar preference keeps the production bounds")
        try rejects { try store.saveSidebarWidth(.nan) }
        try expect(store.state.settings.sidebarWidth == 500, "Invalid widths never contaminate durable state")
        let originalSpace = original.spaces[0]
        try expect(store.settingsPageSpace(profileID: id, originatingSpaceID: originalSpace.id)?.id == originalSpace.id,
                   "Profile commands prefer their original Space")
        let other = store.createProfile(name: "Other")
        try expect(store.settingsPageSpace(profileID: other, originatingSpaceID: originalSpace.id) == nil,
                   "An unassigned editing profile cannot borrow the current profile's page")
        let otherSpace = store.createSpace(name: "Other Space")
        store.assignProfile(other, toSpace: otherSpace)
        try expect(store.settingsPageSpace(profileID: other, originatingSpaceID: originalSpace.id)?.id == otherSpace,
                   "Independent profile selection resolves its actual Space without reassigning the original")
        try expect(store.state.spaces.first { $0.id == originalSpace.id }?.profileID == id,
                   "Opening profile settings does not reassign the originating Space")
        try expect(store.settingsPageSpace(profileID: UUID(), originatingSpaceID: originalSpace.id) == nil,
                   "Removed and stale profiles refuse page commands")
        let unused = store.createProfile(name: "Removing")
        _ = try store.stageProfileRemoval(unused, expectedName: "Removing", confirmation: "Removing")
        try expect(store.settingsPageSpace(profileID: unused, originatingSpaceID: nil) == nil,
                   "A retiring profile never admits a settings page")
        try expect(ProfileSettingsPage.passwords.canReuse("chrome://password-manager/passwords/credential"),
                   "Credential detail edits stay with the original password-manager page")
        try expect(!ProfileSettingsPage.privacy.canReuse("parc://settings/searchEngines"),
                   "A profile command must not overwrite a different settings subpage")
        try expect(ProfileSettingsPage.notifications.canReuse("chrome://settings/content/notifications"),
                   "Native and public addresses identify the same exact subpage")
        try expect(!ProfileSettingsPage.privacy.canReuse("https://settings/privacy")
                   && !ProfileSettingsPage.privacy.canReuse("parc://user@settings/privacy")
                   && !ProfileSettingsPage.privacy.canReuse("parc://settings:10/privacy")
                   && !ProfileSettingsPage.privacy.canReuse("parc://settings/privacy?search=unfinished"),
                   "Foreign and modified destinations cannot be reused as exact settings commands")
        try expect(ProfileSettingsPage.clearBrowsingData.address == "parc://settings/clearBrowserData",
                   "Clear Browsing Data opens Chromium's real confirmation without deleting directly")

        let legacyData = Data("{\"sidebarWidth\":240,\"searchEngine\":\"https://example.org/?q=\",\"restoreSession\":true,\"onboardingComplete\":false}".utf8)
        let legacy = try JSONDecoder().decode(BrowserSettings.self, from: legacyData)
        try expect(legacy.settingsPane == nil && legacy.settingsProfileID == nil, "Existing sessions need no migration")

        // A directory at the final file path forces the atomic rename to fail
        // without relying on permissions that can behave differently as root.
        let stateFile = directory.appendingPathComponent("session.json")
        try FileManager.default.removeItem(at: stateFile)
        try FileManager.default.createDirectory(at: stateFile, withIntermediateDirectories: false)
        let beforeFailure = store.state
        try rejects { try store.saveProfileName(id, expectedName: "Personal — 夜空", name: "Unsaved") }
        try expect(store.state == beforeFailure && store.persistenceError != nil, "Failed rename must keep state and report failure")
        try rejects { try store.saveSettingsSelection(pane: "General", profileID: id) }
        try expect(store.state == beforeFailure, "Failed selection must not become the saved/current selection")
        try rejects { try store.saveRestoreSession(true) }
        try rejects { try store.saveSidebarWidth(220) }
        try expect(store.state == beforeFailure, "Failed explicit preference writes preserve the published controls' values")
        try expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["session.json"],
                   "Failed commits must clean their temporary file")
        try FileManager.default.removeItem(at: stateFile)
        try store.saveProfileName(id, expectedName: "Personal — 夜空", name: "Retry works")
        try expect(store.persistenceError == nil, "Successful retry clears the write error")
        let attributes = try FileManager.default.attributesOfItem(atPath: stateFile.path)
        try expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Committed session must retain private file permissions")
        print("Profile settings: \(assertions) assertions passed")
    }
}
