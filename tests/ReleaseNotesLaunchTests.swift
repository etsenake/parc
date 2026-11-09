import Foundation

/// ReleaseNotesLaunch: when a launch is the first after an update, and how
/// long its Update Complete! banner waits.
@main
struct ReleaseNotesLaunchTests {
    static var count = 0
    static func check(_ value: Bool, _ message: String) throws {
        count += 1; if !value { throw NSError(domain: message, code: 1) }
    }

    static func main() throws {
        let v182 = AppVersion(version: "1.8.2", build: "41"), v190 = AppVersion(version: "1.9.0", build: "42")
        try check(v190.isNewer(than: v182) && !v182.isNewer(than: v190) && !v182.isNewer(than: v182), "versions order")
        try check(AppVersion(version: "1.10.0", build: "50").isNewer(than: AppVersion(version: "1.9.9", build: "49")),
                  "version parts compare as numbers")
        try check(AppVersion(version: "1.8.2", build: "10").isNewer(than: AppVersion(version: "1.8.2", build: "9")),
                  "the same version with a later build is newer")
        try check(AppVersion(infoDictionary: ["CFBundleShortVersionString": "1.8.2", "CFBundleVersion": "41"]) == v182,
                  "the version comes from Info.plist")
        try check(AppVersion(infoDictionary: ["CFBundleShortVersionString": "1.8.2"]) == nil
                  && AppVersion(infoDictionary: nil) == nil, "a bundle without both keys has no version")

        let fresh = ReleaseNotesLaunch.launching(v190, previous: nil, existingData: false)
        try check(fresh == .init(lastLaunched: v190, pending: nil), "a fresh install shows nothing")
        let upgradedFromOld = ReleaseNotesLaunch.launching(v190, previous: nil, existingData: true)
        try check(upgradedFromOld == .init(lastLaunched: v190, pending: v190),
                  "data an earlier run started on, without a record, was last run by an older Parc")

        let ran = ReleaseNotesLaunch(lastLaunched: v182, pending: nil)
        try check(ReleaseNotesLaunch.launching(v182, previous: ran, existingData: true) == ran, "a relaunch shows nothing")
        let updated = ReleaseNotesLaunch.launching(v190, previous: ran, existingData: true)
        try check(updated == .init(lastLaunched: v190, pending: v190), "the first launch after an update shows the banner")
        try check(ReleaseNotesLaunch.launching(v190, previous: updated, existingData: true) == updated,
                  "an unretired banner comes back on the next launch")
        var shown = updated; shown.markShown()
        try check(shown == .init(lastLaunched: v190, pending: nil, lastShown: v190), "showing it records the version")
        try check(ReleaseNotesLaunch.launching(v190, previous: shown, existingData: true) == shown,
                  "a shown banner stays retired")
        try check(ReleaseNotesLaunch.launching(v182, previous: updated, existingData: true) == ran,
                  "a downgrade drops the newer version's banner")
        let back = ReleaseNotesLaunch.launching(v182, previous: shown, existingData: true)
        try check(ReleaseNotesLaunch.launching(v190, previous: back, existingData: true).pending == nil,
                  "going back and forward again doesn't show the same update twice")
        var shownLater = ReleaseNotesLaunch(lastLaunched: v190, pending: AppVersion(version: "2.0.0", build: "50")); shownLater.markShown()
        let olderUpdate = ReleaseNotesLaunch.launching(v190, previous: ReleaseNotesLaunch.launching(v182, previous: shownLater, existingData: true),
                                                       existingData: true)
        try check(olderUpdate.pending == nil, "an update older than one already shown shows nothing")
        let skipped = ReleaseNotesLaunch.launching(AppVersion(version: "1.9.1", build: "43"), previous: updated, existingData: true)
        try check(skipped.pending == AppVersion(version: "1.9.1", build: "43"), "a later update replaces an unretired one")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try check(ReleaseNotesLaunch.read(in: directory) == nil, "no record before the first launch")
        updated.write(in: directory)
        try check(ReleaseNotesLaunch.read(in: directory) == updated, "the record round-trips")
        try Data("{".utf8).write(to: ReleaseNotesLaunch.file(in: directory))
        try check(ReleaseNotesLaunch.read(in: directory) == nil, "a damaged record reads as none")
        print("ReleaseNotesLaunch: \(count) checks passed")
    }
}
