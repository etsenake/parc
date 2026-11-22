import Foundation
import Testing
@testable import ParcCore
@testable import ParcLibrary

struct DownloadRowSubtitleTests {
    private func item(_ name: String = "photo.png", status: BrowserDownloadStatus = .completed) -> BrowserDownload {
        var item = BrowserDownload(id: "subtitle", name: name, path: "", receivedBytes: 1_000_000, totalBytes: 2_000_000,
                                   status: status)
        item.sourceURL = "https://files.example.co.uk/photo.png"
        item.sourceDomain = "example.co.uk"
        return item
    }

    private func bytes() -> ByteCountFormatter {
        let format = ByteCountFormatter()
        format.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        format.includesUnit = true
        format.isAdaptive = true
        format.allowsNonnumericFormatting = true
        format.zeroPadsFractionDigits = true
        return format
    }

    @MainActor @Test func aCompletedImageNamesItsTypeAndTheDeclaredSourceDomain() {
        #expect(DownloadRowSubtitle.text(for: item()) == "Image from example.co.uk")
    }

    @MainActor @Test(arguments: [("dmg", "Disk Image"), ("pdf", "PDF"), ("mov", "Movie"), ("mp3", "Audio"),
                                 ("zip", "Zip Archive"), ("tar", "Archive"), ("unknown-parc", "Download")])
    func eachFileExtensionNamesItsCategory(_ ext: String, _ title: String) {
        #expect(DownloadRowSubtitle.kind(for: item("original." + ext)) == title)
    }

    @MainActor @Test func aMimeTypeNamesTheCategoryWhenTheFileHasNoExtension() {
        var original = item("original")
        original.mimeType = "image/png"
        #expect(DownloadRowSubtitle.kind(for: original) == "Image")
    }

    @MainActor @Test(arguments: [(BrowserDownloadStatus.paused, "Paused · from example.co.uk"),
                                 (.cancelled, "Cancelled · from example.co.uk")])
    func anInterruptedTransferKeepsItsSourceInsteadOfABytecount(_ status: BrowserDownloadStatus, _ text: String) {
        #expect(DownloadRowSubtitle.text(for: item(status: status)) == text)
    }

    @MainActor @Test func anOrdinaryFailureUsesTheReferenceLabel() {
        var original = item(status: .failed)
        original.statusText = "Network connection interrupted"
        #expect(DownloadRowSubtitle.text(for: original) == "Failed to Download")
    }

    @MainActor @Test func aMissingCompletedFileHasTheExplicitSubtitle() {
        var original = item()
        original.fileMissing = true
        #expect(DownloadRowSubtitle.text(for: original) == "File deleted or moved")
    }

    @MainActor @Test func theSecurityTextOverridesTheOrdinaryPresentation() {
        var original = item()
        original.requiresReview = true
        original.statusText = "This file may be dangerous"
        #expect(DownloadRowSubtitle.text(for: original) == "This file may be dangerous")
    }

    @MainActor @Test func openingWhenFinishedShowsTheTruncatedPercentage() {
        var original = item(status: .downloading)
        original.openWhenComplete = true
        original.receivedBytes = 1_299_999
        #expect(DownloadRowSubtitle.text(for: original) == "Opening… (64%)")
    }

    @MainActor @Test func anUnknownTotalInventsNoOpeningPercentage() {
        var original = item(status: .downloading)
        original.openWhenComplete = true
        original.totalBytes = 0
        #expect(DownloadRowSubtitle.text(for: original).isEmpty)
    }

    @MainActor @Test func progressElidesOnlyTheDuplicatedMatchingUnit() throws {
        let format = bytes()
        let received = format.string(fromByteCount: 1_000_000)
        let space = try #require(received.lastIndex(where: { $0.isWhitespace }))
        let head = received.prefix(upTo: space)
        let original = item(status: .downloading)
        #expect(DownloadRowSubtitle.text(for: original) == String(head) + "/" + format.string(fromByteCount: 2_000_000))
    }

    @MainActor @Test func differentByteMagnitudesKeepBothUnits() {
        var original = item(status: .downloading)
        original.receivedBytes = 1000
        let format = bytes()
        #expect(DownloadRowSubtitle.text(for: original)
            == format.string(fromByteCount: 1000) + "/" + format.string(fromByteCount: 2_000_000))
    }

    @MainActor @Test func aTimeEstimateUsesTheFoundationDuration() throws {
        var original = item(status: .downloading)
        original.timeRemaining = 120
        let remaining = DateComponentsFormatter()
        remaining.unitsStyle = .abbreviated
        remaining.zeroFormattingBehavior = .dropAll
        remaining.allowedUnits = [.day, .hour, .minute, .second]
        #expect(DownloadRowSubtitle.text(for: original).hasSuffix(" · " + (try #require(remaining.string(from: 120)))))
    }

    @MainActor @Test func aNonFiniteEstimateNeverReachesTheFormatter() {
        var original = item(status: .downloading)
        original.timeRemaining = .nan
        #expect(!DownloadRowSubtitle.text(for: original).contains(" · "))
    }

    @MainActor @Test func zeroBytesManufactureNoSize() {
        var original = item(status: .downloading)
        original.receivedBytes = 0
        original.timeRemaining = nil
        #expect(DownloadRowSubtitle.text(for: original).isEmpty)
    }

    private func snapshot(_ overrides: [String: Any] = [:]) -> BrowserDownload {
        var values: [String: Any] = ["name": "photo.png", "status": "downloading", "available": true, "itemIdentity": "source",
                                     "sourceDomain": "example.co.uk", "mimeType": "image/png", "timeRemaining": 120.0]
        values.merge(overrides) { _, new in new }
        return BrowserDownload.snapshot(values, id: "s", nativeID: "s", profileID: UUID())
    }

    @Test func aNativeSnapshotCarriesItsLiveMetadataIntoTheRowModel() {
        let live = snapshot()
        #expect(live.timeRemaining == 120 && live.mimeType == "image/png" && live.sourceDomain == "example.co.uk")
    }

    @Test func aRestoredRecordCannotAdvertiseALiveEstimate() throws {
        let restored = try JSONDecoder().decode(BrowserDownload.self, from: JSONEncoder().encode(snapshot()))
        #expect(restored.timeRemaining == nil && restored.mimeType == nil && restored.sourceDomain == nil)
    }

    @Test(arguments: [-1.0, 0, Double.infinity, Double.nan])
    func anInvalidNativeEstimateIsAbsent(_ invalid: Double) {
        #expect(snapshot(["timeRemaining": invalid]).timeRemaining == nil)
    }

    @Test func aRetiredNativeManagerCannotPublishAnEstimate() {
        #expect(snapshot(["available": false, "timeRemaining": 30]).timeRemaining == nil)
    }
}

struct DownloadSectionHeadingTests {
    @MainActor @Test func todayAndYesterdayFollowCalendarChecksOnTheItemsOwnDate() throws {
        let now = Date()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        #expect(DownloadSectionHeading.title(for: now, now: now) == "Today")
        #expect(DownloadSectionHeading.title(for: yesterday, now: now) == "Yesterday")
    }

    @MainActor @Test func olderDownloadsUseTheRelativeFormatterOnTheirOwnTimestamp() {
        let now = Date()
        let older = now.addingTimeInterval(-3 * 86_400)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let title = DownloadSectionHeading.title(for: older, now: now)
        #expect(title == formatter.localizedString(for: older, relativeTo: now))
        #expect(title != "Today" && title != "Yesterday")
    }

    @MainActor @Test func perTimestampTitlesCanSplitOneCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try #require(calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12)))
        let day = try #require(calendar.date(byAdding: .day, value: -4, to: calendar.startOfDay(for: now)))
        let titles = Set((0..<24).map { DownloadSectionHeading.title(for: day.addingTimeInterval(Double($0) * 3600), now: now) })
        #expect(titles.count > 1)
    }
}

struct DownloadRowTitleDimmingTests {
    @MainActor @Test(arguments: [(BrowserDownloadStatus.failed, true), (.cancelled, true), (.pending, false), (.paused, false),
                                 (.downloading, false)])
    func onlyFailedAndCancelledIncompleteTitlesAreDimmed(_ status: BrowserDownloadStatus, _ dimmed: Bool) {
        var item = BrowserDownload(id: "dimmed", name: "photo.png", path: "/owned/Original Photo.PNG", receivedBytes: 0,
                                   totalBytes: 100, status: status)
        item.fileMissing = false
        item.requiresReview = false
        #expect(DownloadRowArtwork.dimsTitle(item) == dimmed)
    }

    @MainActor @Test func aCompletedAvailableFileOwnsTheImageAndAnOrdinaryTitle() {
        var item = BrowserDownload(id: "ordinary", name: "photo.png", path: "/owned/Original Photo.PNG", receivedBytes: 1,
                                   totalBytes: 1, status: .completed)
        item.fileMissing = false
        #expect(DownloadRowArtwork.kind(for: item) == .file && !DownloadRowArtwork.dimsTitle(item))
    }

    @MainActor @Test func aKnownMissingFileOwnsTheEmptyArtworkAndASecondaryTitle() {
        var item = BrowserDownload(id: "missing", name: "photo.png", path: "/owned/Original Photo.PNG", receivedBytes: 1,
                                   totalBytes: 1, status: .completed)
        item.fileMissing = true
        #expect(DownloadRowArtwork.kind(for: item) == .emptyFavicon && DownloadRowArtwork.dimsTitle(item))
    }
}
