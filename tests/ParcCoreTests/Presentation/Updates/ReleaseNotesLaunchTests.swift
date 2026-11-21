import Foundation
import Testing
@testable import ParcCore

struct ReleaseNotesLaunchTests {
    let v182 = AppVersion(version: "1.8.2", build: "41")
    let v190 = AppVersion(version: "1.9.0", build: "42")

    @Test(arguments: [("1.9.0", true), ("1.8.2", false), ("1.8.1", false)])
    func newerVersionsOrderAfterOlderOnes(example: (String, Bool)) {
        let version = AppVersion(version: example.0, build: "41")
        #expect(version.isNewer(than: v182) == example.1)
    }

    @Test func versionPartsCompareAsNumbers() {
        #expect(AppVersion(version: "1.10.0", build: "50").isNewer(than: AppVersion(version: "1.9.9", build: "49")))
    }

    @Test func theSameVersionWithALaterBuildIsNewer() {
        #expect(AppVersion(version: "1.8.2", build: "10").isNewer(than: AppVersion(version: "1.8.2", build: "9")))
    }

    @Test func theVersionComesFromTheInfoDictionary() {
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": "1.8.2", "CFBundleVersion": "41"]) == v182)
    }

    @Test func aBundleWithoutBothKeysHasNoVersion() {
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": "1.8.2"]) == nil)
        #expect(AppVersion(infoDictionary: nil) == nil)
    }

    @Test func aFreshInstallShowsNothing() {
        let fresh = ReleaseNotesLaunch.launching(v190, previous: nil, existingData: false)
        #expect(fresh == .init(lastLaunched: v190, pending: nil))
    }

    @Test func dataWithoutARecordWasLastRunByAnOlderParc() {
        let upgraded = ReleaseNotesLaunch.launching(v190, previous: nil, existingData: true)
        #expect(upgraded == .init(lastLaunched: v190, pending: v190))
        #expect(upgraded.updatedFrom == nil)
    }

    @Test func aRelaunchShowsNothing() {
        let ran = ReleaseNotesLaunch(lastLaunched: v182, pending: nil)
        #expect(ReleaseNotesLaunch.launching(v182, previous: ran, existingData: true) == ran)
    }

    @Test func theFirstLaunchAfterAnUpdateShowsTheBannerAndRemembersTheReplacedVersion() {
        let ran = ReleaseNotesLaunch(lastLaunched: v182, pending: nil)
        let updated = ReleaseNotesLaunch.launching(v190, previous: ran, existingData: true)
        #expect(updated == .init(lastLaunched: v190, pending: v190, updatedFrom: v182))
    }

    @Test func anUnretiredBannerComesBackOnTheNextLaunch() {
        let updated = ReleaseNotesLaunch(lastLaunched: v190, pending: v190, updatedFrom: v182)
        #expect(ReleaseNotesLaunch.launching(v190, previous: updated, existingData: true) == updated)
    }

    @Test func showingTheBannerRecordsTheVersion() {
        var shown = ReleaseNotesLaunch(lastLaunched: v190, pending: v190, updatedFrom: v182)
        shown.markShown()
        #expect(shown == .init(lastLaunched: v190, pending: nil, lastShown: v190))
    }

    @Test func aShownBannerStaysRetired() {
        var shown = ReleaseNotesLaunch(lastLaunched: v190, pending: v190, updatedFrom: v182)
        shown.markShown()
        #expect(ReleaseNotesLaunch.launching(v190, previous: shown, existingData: true) == shown)
    }

    @Test func aDowngradeDropsTheNewerVersionsBanner() {
        let ran = ReleaseNotesLaunch(lastLaunched: v182, pending: nil)
        let updated = ReleaseNotesLaunch.launching(v190, previous: ran, existingData: true)
        #expect(ReleaseNotesLaunch.launching(v182, previous: updated, existingData: true) == ran)
    }

    @Test func goingBackAndForwardAgainDoesNotShowTheSameUpdateTwice() {
        let ran = ReleaseNotesLaunch(lastLaunched: v182, pending: nil)
        var shown = ReleaseNotesLaunch.launching(v190, previous: ran, existingData: true)
        shown.markShown()
        let back = ReleaseNotesLaunch.launching(v182, previous: shown, existingData: true)
        #expect(ReleaseNotesLaunch.launching(v190, previous: back, existingData: true).pending == nil)
    }

    @Test func anUpdateOlderThanOneAlreadyShownShowsNothing() {
        var shownLater = ReleaseNotesLaunch(lastLaunched: v190, pending: AppVersion(version: "2.0.0", build: "50"))
        shownLater.markShown()
        let downgraded = ReleaseNotesLaunch.launching(v182, previous: shownLater, existingData: true)
        let olderUpdate = ReleaseNotesLaunch.launching(v190, previous: downgraded, existingData: true)
        #expect(olderUpdate.pending == nil)
    }

    @Test func aLaterUpdateReplacesAnUnretiredOne() {
        let updated = ReleaseNotesLaunch(lastLaunched: v190, pending: v190, updatedFrom: v182)
        let later = AppVersion(version: "1.9.1", build: "43")
        let skipped = ReleaseNotesLaunch.launching(later, previous: updated, existingData: true)
        #expect(skipped.pending == later)
        #expect(skipped.updatedFrom == v182)
    }

    @Test func aShownBannerForgetsTheVersionItUpdatedFrom() {
        let updated = ReleaseNotesLaunch(lastLaunched: v190, pending: v190, updatedFrom: v182)
        var skipped = ReleaseNotesLaunch.launching(AppVersion(version: "1.9.1", build: "43"), previous: updated, existingData: true)
        skipped.markShown()
        #expect(skipped.updatedFrom == nil)
    }

    @Test func thereIsNoRecordBeforeTheFirstLaunch() throws {
        let directory = try PresentationScratch()
        defer { directory.remove() }
        #expect(ReleaseNotesLaunch.read(in: directory.url) == nil)
    }

    @Test func theRecordRoundTrips() throws {
        let directory = try PresentationScratch()
        defer { directory.remove() }
        let updated = ReleaseNotesLaunch(lastLaunched: v190, pending: v190, updatedFrom: v182)
        updated.write(in: directory.url)
        #expect(ReleaseNotesLaunch.read(in: directory.url) == updated)
    }

    @Test func aDamagedRecordReadsAsNone() throws {
        let directory = try PresentationScratch()
        defer { directory.remove() }
        try Data("{".utf8).write(to: ReleaseNotesLaunch.file(in: directory.url))
        #expect(ReleaseNotesLaunch.read(in: directory.url) == nil)
    }
}
