import Foundation

@main
@MainActor
struct AppWidePreferencesTests {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !value() { throw Failure(message: message) }
    }

    static func profile(guidSuffix: String, default keyword: String? = "duckduckgo.com", suggestions: Bool = true,
                        directory: String = "/Users/test/Downloads", prompt: Bool = false) -> AppWideProfileState {
        AppWideProfileState(
            engines: [
                AppWideSearchEngine(identifier: "g-" + guidSuffix, keyword: "google.com", canMakeDefault: true),
                AppWideSearchEngine(identifier: "d-" + guidSuffix, keyword: "duckduckgo.com", canMakeDefault: true),
                AppWideSearchEngine(identifier: "x-" + guidSuffix, keyword: "locked.example", canMakeDefault: false),
            ],
            defaultKeyword: keyword, defaultEditable: true, suggestionsEnabled: suggestions, suggestionsEditable: true,
            downloadDirectory: directory, directoryEditable: true, promptForDownload: prompt, promptEditable: true)
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-App-Wide-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        try expect(store.state.settings.appWidePreferences == nil, "A fresh store has no app-wide values yet")

        let first = AppWidePreferences.recorded(from: profile(guidSuffix: "a", default: "google.com", suggestions: false,
                                                              directory: "/Users/test/Incoming", prompt: true))
        try store.recordAppWidePreferencesIfMissing(first)
        try expect(store.state.settings.appWidePreferences == first, "The first Space's values are recorded")
        let other = AppWidePreferences.recorded(from: profile(guidSuffix: "b"))
        try store.recordAppWidePreferencesIfMissing(other)
        try expect(store.state.settings.appWidePreferences == first, "Recording never overwrites an existing value")
        try store.saveAppWidePreferences(other)
        try expect(store.state.settings.appWidePreferences == other, "A General change replaces the app-wide values")
        let reloaded = try BrowserStore(directory: directory)
        try expect(reloaded.state.settings.appWidePreferences == other, "App-wide values survive a restart")

        let legacy = try JSONEncoder().encode(BrowserSettings())
        var object = try JSONSerialization.jsonObject(with: legacy) as! [String: Any]
        object.removeValue(forKey: "appWidePreferences")
        let decoded = try JSONDecoder().decode(BrowserSettings.self, from: JSONSerialization.data(withJSONObject: object))
        try expect(decoded.appWidePreferences == nil, "Settings saved before this change still load")

        let engines = profile(guidSuffix: "z").engines
        try expect(AppWidePreferences.engineIdentifier(forKeyword: "DuckDuckGo.com ", among: engines) == "d-z",
                   "Engines match by keyword, ignoring case and spaces")
        try expect(AppWidePreferences.engineIdentifier(forKeyword: "locked.example", among: engines) == nil,
                   "An engine that cannot be the default never matches")
        try expect(AppWidePreferences.engineIdentifier(forKeyword: "bing.com", among: engines) == nil,
                   "A missing keyword matches nothing")
        try expect(AppWidePreferences.engineIdentifier(forKeyword: "  ", among: engines) == nil, "A blank keyword matches nothing")

        let wanted = AppWidePreferences(searchKeyword: "google.com", searchSuggestions: false,
                                        downloadDirectory: "/Users/test/Incoming", promptForDownload: true)
        let changes = wanted.changes(for: profile(guidSuffix: "q"))
        try expect(changes == AppWideChanges(engineIdentifier: "g-q", suggestions: false,
                                             downloadDirectory: "/Users/test/Incoming", promptForDownload: true),
                   "Each profile gets its own GUID for the shared keyword")
        let same = wanted.changes(for: profile(guidSuffix: "q", default: "Google.com", suggestions: false,
                                               directory: "/Users/test/Incoming/", prompt: true))
        try expect(same.isEmpty, "A profile already matching needs no writes")

        var locked = profile(guidSuffix: "q")
        locked.defaultEditable = false; locked.suggestionsEditable = false
        locked.directoryEditable = false; locked.promptEditable = false
        try expect(wanted.changes(for: locked).isEmpty, "Managed or extension-controlled values are left alone")
        try expect(AppWidePreferences.recorded(from: locked) == AppWidePreferences(),
                   "Locked values are never recorded as the app-wide choice")

        var missing = profile(guidSuffix: "q")
        missing.engines = [AppWideSearchEngine(identifier: "d", keyword: "duckduckgo.com", canMakeDefault: true)]
        try expect(wanted.changes(for: missing).engineIdentifier == nil, "A profile without the engine keeps its own")
        try expect(AppWidePreferences().changes(for: profile(guidSuffix: "q")).isEmpty, "Unset values change nothing")

        let chosen = AppWidePreferences(searchKeyword: "google.com", searchSuggestions: true,
                                        downloadDirectory: "/Users/test/Downloads", promptForDownload: false)
        let pickedInSpace = chosen.adoptingSearch(from: profile(guidSuffix: "s", default: "DuckDuckGo.com ", suggestions: false))
        try expect(pickedInSpace == AppWidePreferences(searchKeyword: "DuckDuckGo.com ", searchSuggestions: false,
                                                       downloadDirectory: "/Users/test/Downloads", promptForDownload: false),
                   "A default engine or suggestions picked on a Space's own search page becomes the app-wide choice; downloads stay")
        try expect(chosen.adoptingSearch(from: profile(guidSuffix: "s", default: " GOOGLE.com")) == chosen,
                   "The same engine under different spacing or case is not a change")
        try expect(chosen.adoptingSearch(from: locked) == chosen, "A managed or extension-controlled default is never adopted")

        print("App-wide preferences: \(assertions) assertions passed")
    }
}
