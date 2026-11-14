import Combine
import Foundation

@main @MainActor struct SpaceHeaderSettingTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        count += 1
        guard try value() else { fatalError("SidebarChrome Space header setting: \(message)") }
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-space-header-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")

        let store = try BrowserStore(directory: directory)
        check(store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == nil, "a new session takes the default, off")
        var published = 0
        let subscription = store.statePublisher.dropFirst().sink { _ in published += 1 }
        store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        check(store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true && published > 0, "the toggle turns it on and publishes")
        store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        check(store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == false, "a second toggle turns it off")
        store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        subscription.cancel()
        try store.save()

        let relaunched = try BrowserStore(directory: directory)
        check(relaunched.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true, "the setting survives a relaunch")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var settings = json["settings"] as! [String: Any]
        check(settings["showSpaceHeaderOnSingleUnnamedSpaces"] as? Bool == true, "the session stores the showSpaceHeaderOnSingleUnnamedSpaces key")
        settings.removeValue(forKey: "showSpaceHeaderOnSingleUnnamedSpaces")
        json["settings"] = settings
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let older = try BrowserStore(directory: directory)
        check(older.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == nil, "an older session decodes without it")
        older.toggleSpaceHeaderOnSingleUnnamedSpaces()
        check(older.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true, "toggling the unset default turns it on")
        print("SidebarChrome Space header setting: \(count) assertions passed")
    }
}
