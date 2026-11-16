import Foundation

@main struct WindowFramePreferenceTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("WindowFramePreferences: \(message)") }
    }

    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        let suite = "parc.windowFrame.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = WindowFramePreferences(defaults: defaults)
        check(fresh.state.thickness == 10 && !fresh.loadError && fresh.thickness == 10 && !fresh.isAdjusting, "defaults to 10")
        try? fresh.setThickness(6)
        check(fresh.state.thickness == 6, "stores a new value")
        check(WindowFramePreferences(defaults: defaults).state.thickness == 6, "persists across launches")
        try? fresh.setThickness(40)
        check(fresh.state.thickness == 13, "clamps to the range")
        fresh.setPreview(8.4)
        check(fresh.isAdjusting && fresh.thickness == 8.4 && fresh.state.thickness == 13, "a preview does not save")
        fresh.setPreview(20)
        check(fresh.thickness == WindowFramePreferences.previewBounds.upperBound, "previews stay near the range")
        fresh.setPreview(nil)
        check(!fresh.isAdjusting && fresh.thickness == 13, "clearing the preview restores the saved value")

        let futureData = try! JSONEncoder().encode(["version": 2, "thickness": 7])
        defaults.set(futureData, forKey: "parc.windowFrame.v1")
        let future = WindowFramePreferences(defaults: defaults)
        check(future.loadError && future.state.thickness == 10, "a future record falls back to 10")
        check((try? future.setThickness(5)) == nil, "a future record refuses writes")
        check(defaults.data(forKey: "parc.windowFrame.v1") == futureData, "a future record is preserved")

        let outOfRange = try! JSONEncoder().encode(WindowFramePreferences.State(version: 1, thickness: 30))
        defaults.set(outOfRange, forKey: "parc.windowFrame.v1")
        check(WindowFramePreferences(defaults: defaults).loadError, "an out-of-range record is treated as unreadable")
        defaults.set("garbage", forKey: "parc.windowFrame.v1")
        let garbage = WindowFramePreferences(defaults: defaults)
        check(garbage.loadError && defaults.string(forKey: "parc.windowFrame.v1") == "garbage", "a malformed record is preserved")
        print("WindowFrame preferences: \(count) checks passed")
    }
}
