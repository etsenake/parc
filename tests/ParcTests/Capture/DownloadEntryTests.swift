import AppKit
import Testing
@testable import ParcCore
@testable import ParcLibrary

private struct DownloadActivityFixture {
    let profile = UUID()
    var profiles: Set<UUID> { [profile] }

    func item(_ name: String = "sample", _ status: BrowserDownloadStatus = .downloading,
              started: TimeInterval = 10, received: Int64 = 60, total: Int64 = 100, identity: String? = "current") -> BrowserDownload {
        var item = BrowserDownload(id: name, name: name, path: "", receivedBytes: received, totalBytes: total, status: status)
        item.profileID = profile
        item.nativeID = name
        item.nativeIdentity = identity
        item.startedAt = Date(timeIntervalSince1970: started)
        return item
    }
}

struct DownloadActivityTests {
    private let fixture = DownloadActivityFixture()

    @Test func theNewestEligibleDownloadSuppliesTheBadgeProgress() {
        let old = fixture.item("older", started: 10, received: 30)
        let newest = fixture.item("newest", started: 20)
        let paused = fixture.item("paused", .paused, started: 30)
        let active = DownloadActivity.active(in: [paused, old, newest], profiles: fixture.profiles)
        #expect(active?.name == "newest" && active?.progress == 0.6)
    }

    @Test(arguments: [false, true])
    func equalDatesKeepTheManagersOrder(_ reversed: Bool) {
        let one = fixture.item("one"), two = fixture.item("two")
        let downloads = reversed ? [two, one] : [one, two]
        #expect(DownloadActivity.active(in: downloads, profiles: fixture.profiles)?.name == downloads[0].name)
    }

    @Test func persistedMetadataCannotAnimateAsLiveActivity() {
        #expect(DownloadActivity.active(in: [fixture.item(identity: nil)], profiles: fixture.profiles) == nil)
    }

    @Test func aRetiredProfileSuppliesNoBadgeActivity() {
        #expect(DownloadActivity.active(in: [fixture.item()], profiles: []) == nil)
    }

    @Test(arguments: [(Int64(200), Int64(100), 1.0 as Double?), (30, 0, nil)])
    func progressIsClampedAndUnknownLengthStaysUnknown(_ received: Int64, _ total: Int64, _ progress: Double?) {
        #expect(DownloadActivity.active(in: [fixture.item(received: received, total: total)], profiles: fixture.profiles)?.progress == progress)
    }

    @Test func theFlyoutProgressExcludesPendingAndPausedTransfers() {
        let pending = fixture.item("pending", .pending, started: 100)
        let paused = fixture.item("paused", .paused, started: 110)
        let active = fixture.item("active")
        #expect(DownloadActivity.inFlight(in: [active, pending, paused], profiles: fixture.profiles)?.name == "active")
        #expect(DownloadActivity.active(in: [active, pending, paused], profiles: fixture.profiles)?.name == "pending")
    }

    @Test func aLiveTransferCompletesOnlyThroughItsOriginalIdentity() {
        var state = DownloadActivityState()
        _ = state.update([fixture.item()], profiles: fixture.profiles, now: 10)
        let result = state.update([fixture.item("sample", .completed)], profiles: fixture.profiles, now: 11)
        #expect(result?.completed == true && result?.progress == 1)
    }

    @Test func repeatedCompletionDoesNotExtendItsDeadline() {
        var state = DownloadActivityState()
        let complete = fixture.item("sample", .completed)
        _ = state.update([fixture.item()], profiles: fixture.profiles, now: 10)
        _ = state.update([complete], profiles: fixture.profiles, now: 11)
        let before = state.update([complete], profiles: fixture.profiles, now: 12)
        let after = state.update([complete], profiles: fixture.profiles, now: 12.46)
        #expect(before?.completed == true && after == nil)
    }

    @Test func aRestoredCompletedRowDoesNotReplayCompletion() {
        var state = DownloadActivityState()
        let result = state.update([fixture.item("sample", .completed)], profiles: fixture.profiles, now: 10)
        #expect(result == nil)
    }

    @Test func remainingActiveWorkTakesPriorityOverCompletion() {
        var state = DownloadActivityState()
        _ = state.update([fixture.item()], profiles: fixture.profiles, now: 10)
        let result = state.update([fixture.item("sample", .completed), fixture.item("older", started: 1)],
                                  profiles: fixture.profiles, now: 11)
        #expect(result?.name == "older" && result?.completed == false)
    }

    @Test(arguments: [(BrowserDownloadStatus.failed, "current"), (.completed, "replacement")])
    func anIncorrectCompletionNeverShowsAsSuccess(_ status: BrowserDownloadStatus, _ identity: String) {
        var state = DownloadActivityState()
        _ = state.update([fixture.item()], profiles: fixture.profiles, now: 10)
        let result = state.update([fixture.item("sample", status, identity: identity)], profiles: fixture.profiles, now: 11)
        #expect(result == nil)
    }
}

struct DownloadActivityBadgeTests {
    @MainActor private final class Fixture {
        let window: NSWindow
        let badge = DownloadActivityBadge(frame: CGRect(x: 0, y: 0, width: 40, height: 56))
        let downloads = DownloadActivityFixture()
        var jobs: [(delay: TimeInterval, job: @MainActor () -> Void)] = []

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: badge.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(badge)
            badge.after = { [weak self] delay, job in self?.jobs.append((delay, job)) }
        }

        func publish(_ name: String = "sample", status: BrowserDownloadStatus = .downloading, received: Int64 = 60) {
            badge.update([downloads.item(name, status, received: received)], profiles: downloads.profiles, enabled: true)
        }
    }

    @MainActor @Test func repeatedActivityDoesNotReemitPresentation() {
        let fixture = Fixture()
        var published: [DownloadActivity?] = []
        fixture.badge.onChange = { published.append($0) }
        fixture.publish()
        fixture.publish()
        #expect(published.count == 1 && fixture.badge.activity?.name == "sample")
    }

    @MainActor @Test func downloadingRemainsDecorationOutsidePointerAndAccessibility() throws {
        let fixture = Fixture()
        fixture.publish()
        let renderer = try #require(fixture.badge.subviews.first)
        #expect(fixture.badge.hitTest(CGPoint(x: 20, y: 28)) == nil)
        #expect(!fixture.badge.isAccessibilityElement() && !renderer.isAccessibilityElement())
    }

    @MainActor @Test func progressKeepsTheSameRenderer() throws {
        let fixture = Fixture()
        fixture.publish(received: 60)
        let renderer = try #require(fixture.badge.subviews.first)
        fixture.publish(received: 80)
        #expect(fixture.badge.subviews.first === renderer)
        #expect(fixture.badge.activity?.progress == 0.8)
    }

    @MainActor @Test func theBadgeRendererFollowsItsCellBounds() throws {
        let fixture = Fixture()
        fixture.publish()
        let renderer = try #require(fixture.badge.subviews.first)
        fixture.badge.setFrameSize(CGSize(width: 40, height: 40))
        fixture.badge.layout()
        #expect(renderer.frame == fixture.badge.bounds)
    }

    @MainActor @Test func genuineCompletionRetiresTheBadgeAtItsScheduledDeadline() throws {
        let fixture = Fixture()
        fixture.publish()
        fixture.publish(status: .completed)
        let retirement = try #require(fixture.jobs.first)
        #expect(retirement.delay == 1.45)
        retirement.job()
        #expect(fixture.badge.activity == nil && fixture.badge.subviews.isEmpty && fixture.badge.isHidden)
    }

    @MainActor @Test func aFormerCompletionCallbackCannotClearTheNewTransfer() throws {
        let fixture = Fixture()
        fixture.publish()
        fixture.publish(status: .completed)
        let retirement = try #require(fixture.jobs.first)
        fixture.publish("next")
        retirement.job()
        #expect(fixture.badge.activity?.name == "next" && !fixture.badge.isHidden)
    }

    @MainActor @Test func anAppearanceRefreshReplacesTheRenderTreeWithoutReplayingCompletion() throws {
        let fixture = Fixture()
        fixture.publish()
        fixture.publish(status: .completed)
        let renderer = try #require(fixture.badge.subviews.first)
        let scheduled = fixture.jobs.count
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(fixture.badge.subviews.first !== renderer)
        #expect(fixture.badge.activity?.completed == true && fixture.jobs.count == scheduled)
    }

    @MainActor @Test func retiringDuringPublicationDoesNotRestartTheRenderTree() {
        let fixture = Fixture()
        fixture.publish()
        fixture.badge.onChange = { [weak badge = fixture.badge] value in
            if value?.completed == true { badge?.reset() }
        }
        fixture.publish(status: .completed)
        #expect(fixture.badge.activity == nil && fixture.badge.subviews.isEmpty)
        #expect(fixture.jobs.isEmpty)
    }

    @MainActor @Test func aDetachedBadgeCannotResurrectOldActivity() {
        let fixture = Fixture()
        fixture.publish()
        fixture.badge.removeFromSuperview()
        fixture.publish()
        #expect(fixture.badge.isHidden && fixture.badge.activity == nil)
    }

    @MainActor @Test func closingTheOwnerRevokesLateDownloadUpdates() {
        let fixture = Fixture()
        fixture.publish()
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: fixture.window)
        fixture.publish()
        #expect(fixture.badge.isHidden && fixture.badge.activity == nil)
    }
}

struct DownloadFileDragTests {
    private let file = URL(fileURLWithPath: "/fixture/download.png")

    @MainActor @Test func theProviderAdvertisesOnlyTheOriginalFileURL() throws {
        let provider = try #require(DownloadFileDrag(resolve: { file }))
        #expect(provider.item.types == [.fileURL])
    }

    @MainActor @Test func aWithdrawnFileCannotSupplyItsPasteboardData() throws {
        var admitted: URL? = file
        let provider = try #require(DownloadFileDrag(resolve: { admitted }))
        admitted = nil
        provider.pasteboard(nil, item: provider.item, provideDataForType: .fileURL)
        #expect(provider.item.string(forType: .fileURL) == nil)
    }

    @MainActor @Test func anInvalidatedProviderCannotReacquireTheFile() throws {
        let provider = try #require(DownloadFileDrag(resolve: { file }))
        provider.invalidate()
        provider.pasteboard(nil, item: provider.item, provideDataForType: .fileURL)
        #expect(provider.item.string(forType: .fileURL) == nil)
    }

    @MainActor @Test func aWebAddressIsNeverOfferedAsADownloadedFile() {
        #expect(DownloadFileDrag(resolve: { URL(string: "https://example.test/file") }) == nil)
    }
}
