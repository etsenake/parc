import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcLibrary

struct DownloadThumbnailProviderTests {
    @MainActor private final class Fixture {
        let key: DownloadThumbnailProvider.Key
        let item: BrowserDownload
        let image = NSImage(size: CGSize(width: 24, height: 24))
        let icon = NSImage(size: CGSize(width: 14, height: 14))
        var valid = true
        var cancelled = 0
        var replies: [@MainActor (DownloadThumbnailProvider.Delivery) -> Void] = []
        var deliveries: [NSImage?] = []
        lazy var provider = DownloadThumbnailProvider { [weak self] _, reply in
            self?.replies.append(reply)
            return { [weak self] in self?.cancelled += 1 }
        }

        init() {
            var download = BrowserDownload(id: "original", name: "original.png", path: "/fixture/original.png",
                receivedBytes: 1, totalBytes: 1, status: .completed)
            download.profileID = UUID()
            download.nativeID = "engine"
            download.nativeIdentity = "current"
            download.canCopyFile = true
            item = download
            key = .init(item: DownloadLibraryIdentity(download), url: URL(fileURLWithPath: download.path), bytes: 1)
        }

        @discardableResult func request() -> UUID? {
            provider.request(key, valid: { [weak self] in self?.valid == true },
                completion: { [weak self] in self?.deliveries.append($0) })
        }
    }

    enum RevisionChange: CaseIterable, Sendable { case access, bytes, url, incarnation }

    @MainActor @Test func aThumbnailAdmitsOnlyItsOriginalFileAndByteRevision() {
        let fixture = Fixture()
        #expect(fixture.key.admits(fixture.item, url: fixture.key.url))
    }

    @MainActor @Test(arguments: RevisionChange.allCases)
    func aChangedOriginalCannotPublishThePreviousThumbnail(_ change: RevisionChange) {
        let fixture = Fixture()
        var item = fixture.item, url = fixture.key.url
        switch change {
        case .access: item.canCopyFile = false
        case .bytes: item.receivedBytes += 1
        case .url: url.appendPathExtension("changed")
        case .incarnation: item.nativeIdentity = "replacement"
        }
        #expect(!fixture.key.admits(item, url: url))
    }

    @MainActor @Test func aCancelledThumbnailDoesNotDeliverItsLateImage() throws {
        let fixture = Fixture()
        let token = fixture.request()
        let reply = try #require(fixture.replies.first)
        fixture.provider.cancel(token)
        reply(.finished(fixture.image))
        #expect(fixture.cancelled == 1 && fixture.deliveries.isEmpty)
    }

    @MainActor @Test func anInvalidatedOriginalCannotDeliverItsThumbnail() throws {
        let fixture = Fixture()
        fixture.request()
        fixture.valid = false
        let reply = try #require(fixture.replies.first)
        reply(.finished(fixture.image))
        #expect(fixture.deliveries.isEmpty)
    }

    @MainActor @Test func theSameOriginalReusesItsFinishedImage() throws {
        let fixture = Fixture()
        fixture.request()
        let reply = try #require(fixture.replies.first)
        reply(.finished(fixture.image))
        fixture.request()
        #expect(fixture.deliveries.count == 2 && fixture.replies.count == 1)
        #expect(fixture.deliveries.last.flatMap { $0 } === fixture.image)
    }

    @MainActor @Test func retiringTheLibraryClearsItsThumbnailCache() throws {
        let fixture = Fixture()
        fixture.request()
        let reply = try #require(fixture.replies.first)
        reply(.finished(fixture.image))
        fixture.provider.invalidate()
        fixture.request()
        #expect(fixture.replies.count == 2)
    }

    @MainActor @Test func theProvisionalIconMayAppearButCannotReplaceAFinishedThumbnail() throws {
        let fixture = Fixture()
        fixture.request()
        let reply = try #require(fixture.replies.first)
        reply(.provisional(fixture.icon))
        reply(.finished(fixture.image))
        reply(.provisional(fixture.icon))
        #expect(fixture.deliveries.count == 2)
        #expect(fixture.deliveries.first.flatMap { $0 } === fixture.icon)
        #expect(fixture.deliveries.last.flatMap { $0 } === fixture.image)
    }

    @MainActor @Test func validationReentryCannotCacheTheRetiredImage() throws {
        let fixture = Fixture()
        var validations = 0
        fixture.provider.request(fixture.key, valid: {
            validations += 1
            if validations > 1 { fixture.provider.invalidate() }
            return true
        }, completion: { fixture.deliveries.append($0) })
        let reply = try #require(fixture.replies.first)
        reply(.finished(fixture.image))
        fixture.request()
        #expect(fixture.deliveries.isEmpty && fixture.replies.count == 2)
    }
}

struct DownloadArtworkRequestTests {
    @MainActor private final class Fixture {
        typealias Callback = @MainActor (NSImage?) -> Void

        let image = NSImage(size: CGSize(width: 24, height: 24))
        let icon = NSImage(size: CGSize(width: 14, height: 14))
        var iconReply: Callback?
        var thumbnailReply: Callback?
        var deliveries: [DownloadThumbnailProvider.Delivery] = []
        var cancelled: [String] = []
        lazy var request = DownloadArtworkRequest(url: URL(fileURLWithPath: "/fixture/image.png"),
            iconLoader: { [weak self] _, reply in
                self?.iconReply = reply
                return { [weak self] in self?.cancelled.append("icon") }
            },
            thumbnailLoader: { [weak self] _, reply in
                self?.thumbnailReply = reply
                return { [weak self] in self?.cancelled.append("thumbnail") }
            }, completion: { [weak self] in self?.deliveries.append($0) })
    }

    @MainActor @Test func aFinishedThumbnailSupersedesTheProvisionalIcon() throws {
        let fixture = Fixture()
        fixture.request.start()
        fixture.iconReply?(fixture.icon)
        fixture.thumbnailReply?(fixture.image)
        fixture.iconReply?(fixture.icon)
        try #require(fixture.deliveries.count == 2)
        guard case .provisional(let icon) = fixture.deliveries[0], case .finished(let image) = fixture.deliveries[1] else {
            Issue.record("Expected a provisional icon and a final thumbnail")
            return
        }
        #expect(icon === fixture.icon && image === fixture.image)
    }

    @MainActor @Test func aMissingThumbnailFallsBackToTheOriginalIcon() throws {
        let fixture = Fixture()
        fixture.request.start()
        fixture.thumbnailReply?(nil)
        #expect(fixture.deliveries.isEmpty)
        fixture.iconReply?(fixture.icon)
        try #require(fixture.deliveries.count == 1)
        guard case .finished(let image) = fixture.deliveries[0] else {
            Issue.record("Expected the original icon as the final image")
            return
        }
        #expect(image === fixture.icon)
    }

    @MainActor @Test func aFastThumbnailCancelsThePendingIcon() {
        let fixture = Fixture()
        fixture.request.start()
        fixture.thumbnailReply?(fixture.image)
        fixture.iconReply?(fixture.icon)
        #expect(fixture.cancelled == ["icon"] && fixture.deliveries.count == 1)
    }

    @MainActor @Test func retiringTheRequestCancelsBothImageProducers() {
        let fixture = Fixture()
        fixture.request.start()
        fixture.request.cancel()
        fixture.iconReply?(fixture.icon)
        fixture.thumbnailReply?(fixture.image)
        #expect(fixture.cancelled == ["icon", "thumbnail"] && fixture.deliveries.isEmpty)
    }
}
