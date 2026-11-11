import Foundation

@main @MainActor
struct SoftwareUpdateBannerTests {
    static var count = 0
    static func check(_ value: Bool, _ message: String) throws {
        count += 1; if !value { throw NSError(domain: message, code: 1) }
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = AppVersion(version: "1.8.2", build: "22"), new = AppVersion(version: "1.9.0", build: "23")

        let fresh = SoftwareUpdateBanner()
        fresh.launch(in: directory, existingData: false, current: old)
        try check(fresh.completedUpdate == nil, "a fresh install shows nothing")

        let updated = SoftwareUpdateBanner()
        updated.launch(in: directory, existingData: true, current: new)
        try check(updated.completedUpdate == new, "the first launch of a newer version shows the banner")
        try check(updated.updatedFrom == old && updated.completedUpdateFragment == "from=1.8.2&to=1.9.0",
                  "See What's New opens the page at the update's range")
        let unshown = SoftwareUpdateBanner()
        unshown.launch(in: directory, existingData: true, current: new)
        try check(unshown.completedUpdate == new, "a launch that never showed it carries it on")
        unshown.markCompletedUpdateShown()
        try check(unshown.completedUpdate == new && unshown.updatedFrom == old, "showing it keeps it up for this run")
        unshown.retireCompletedUpdate()
        try check(unshown.completedUpdate == nil && unshown.completedUpdateFragment == nil, "retiring removes it")

        let shown = SoftwareUpdateBanner()
        shown.launch(in: directory, existingData: true, current: new)
        try check(shown.completedUpdate == nil, "once shown, the next launch shows nothing")
        try check(ReleaseNotesLaunch.read(in: directory) == .init(lastLaunched: new, pending: nil, lastShown: new),
                  "the record is retired")
        print("SoftwareUpdateBanner: \(count) checks passed")
    }
}
