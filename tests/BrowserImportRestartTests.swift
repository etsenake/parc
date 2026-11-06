import Foundation

@main struct BrowserImportRestartTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let destination = BrowserImportDestination(spaceID: store.activeSpace.id,
                                                   profileID: store.activeSpace.profileID)
        let intent = BrowserImportRestartIntent(destination: destination, onboarding: true,
                                                sourceBundleID: "com.google.Chrome")
        let absent0 = try BrowserImportRestartIntent.take(from: directory)
        precondition(absent0 == nil)
        try intent.save(in: directory)
        let restored = try BrowserImportRestartIntent.take(from: directory)
        precondition(restored == intent && restored?.destination == destination
                         && restored?.sourceBundleID == "com.google.Chrome")
        try Data("{\"spaceID\":\"\(destination.spaceID.uuidString)\",\"profileID\":\"\(destination.profileID.uuidString)\",\"onboarding\":true}".utf8)
            .write(to: directory.appendingPathComponent("PendingBrowserImportRestart.json"))
        let legacy = try BrowserImportRestartIntent.take(from: directory)
        precondition(legacy?.sourceBundleID == "com.apple.Safari", "Old Safari-only intents keep Safari")
        let absent1 = try BrowserImportRestartIntent.take(from: directory)
        precondition(absent1 == nil)
        try intent.save(in: directory)
        BrowserImportRestartIntent.remove(from: directory)
        let absent2 = try BrowserImportRestartIntent.take(from: directory)
        precondition(absent2 == nil)
        let invalid = directory.appendingPathComponent("PendingBrowserImportRestart.json")
        try Data("invalid".utf8).write(to: invalid)
        do { _ = try BrowserImportRestartIntent.take(from: directory); preconditionFailure("Corrupt intent must fail") }
        catch { precondition(!FileManager.default.fileExists(atPath: invalid.path)) }
        print("Browser import restart persistence: 6 checks passed")
    }
}
