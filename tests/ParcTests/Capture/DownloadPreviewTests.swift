import AppKit
import Testing
@testable import Parc

struct DownloadPreviewTests {
    @MainActor private final class Fixture {
        let parent: NSWindow
        let artwork = NSImage(size: CGSize(width: 60, height: 90))
        var presented: NSWindow?
        var reducedMotion: Bool
        var source: CGRect?
        lazy var preview = DownloadLibraryPreview(reduceMotion: { [weak self] in self?.reducedMotion == true },
            presentWindow: { [weak self] _, owner in self?.presented = owner })

        init(reducedMotion: Bool, source: CGRect? = CGRect(x: 20, y: 30, width: 60, height: 90)) {
            _ = NSApplication.shared
            self.reducedMotion = reducedMotion
            self.source = source
            parent = NSWindow(contentRect: CGRect(x: 60, y: 40, width: 460, height: 420),
                              styleMask: .borderless, backing: .buffered, defer: false)
            parent.isReleasedWhenClosed = false
            preview.sourceRect = { [weak self] in self?.source }
            preview.sourceImage = artwork
            preview.present(on: parent)
        }

        func modal() throws -> NSView {
            try #require(preview.window?.contentView?.subviews.last)
        }

        func snapshot() throws -> NSImageView {
            try #require(try modal().subviews.last as? NSImageView)
        }
    }

    @MainActor @Test func previewRequestsPresentationOverItsExactParent() throws {
        let fixture = Fixture(reducedMotion: true)
        defer { fixture.preview.close() }
        let overlay = try #require(fixture.preview.window)
        #expect(fixture.presented === fixture.parent)
        #expect(overlay.frame == fixture.parent.frame && overlay.styleMask == .borderless)
        #expect(!overlay.isOpaque && !overlay.hasShadow)
    }

    @MainActor @Test func thePreviewCentersItsModalInTheParentBounds() throws {
        let fixture = Fixture(reducedMotion: true)
        defer { fixture.preview.close() }
        let root = try #require(fixture.preview.window?.contentView)
        let modal = try fixture.modal()
        #expect(modal.frame == DownloadPreviewGeometry.modalFrame(in: root.bounds))
        #expect(modal.layer?.position == CGPoint(x: modal.frame.midX, y: modal.frame.midY))
    }

    @MainActor @Test(arguments: [false, true])
    func onlyMotionEnabledPreviewsWithAnOriginalSourceStartTheSpring(_ reducedMotion: Bool) throws {
        let fixture = Fixture(reducedMotion: reducedMotion)
        defer { fixture.preview.close() }
        let modal = try fixture.modal()
        #expect((modal.layer?.animation(forKey: "transform") != nil) == !reducedMotion)
    }

    @MainActor @Test func anOffscreenSourceDoesNotInventAPreviewTransition() throws {
        let fixture = Fixture(reducedMotion: false, source: CGRect(x: 2_000, y: 3_000, width: 60, height: 90))
        defer { fixture.preview.close() }
        #expect(try fixture.modal().layer?.animation(forKey: "transform") == nil)
    }

    @MainActor @Test func transitionArtworkRetainsTheOriginalAspectAndCannotTakeInput() throws {
        let fixture = Fixture(reducedMotion: false)
        defer { fixture.preview.close() }
        let snapshot = try fixture.snapshot()
        #expect(snapshot.image === fixture.artwork)
        #expect(abs(snapshot.frame.height / snapshot.frame.width - 1.5) < 0.01)
        #expect(snapshot.hitTest(CGPoint(x: snapshot.frame.midX, y: snapshot.frame.midY)) == nil)
        #expect(snapshot.isAccessibilityHidden())
    }

    @MainActor @Test func aParentResizeSettlesThePreviewToItsLiveContent() throws {
        let fixture = Fixture(reducedMotion: false)
        defer { fixture.preview.close() }
        let target = fixture.parent.frame.insetBy(dx: 20, dy: 20)
        fixture.parent.setFrame(target, display: false)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: fixture.parent)
        let modal = try fixture.modal()
        let snapshot = try fixture.snapshot()
        #expect(fixture.preview.window?.frame == target)
        #expect(modal.layer?.animation(forKey: "transform") == nil)
        #expect(modal.subviews.first?.layer?.opacity == 1 && snapshot.layer?.opacity == 0)
    }

    @MainActor @Test func onlyTheOriginalParentClosingRetiresThePreview() {
        let fixture = Fixture(reducedMotion: true)
        var closes = 0
        fixture.preview.onClosed = { closes += 1 }
        let other = Fixture(reducedMotion: true)
        defer { other.preview.close() }
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: other.parent)
        #expect(closes == 0)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: fixture.parent)
        #expect(closes == 1 && fixture.preview.sourceImage == nil)
    }

    @MainActor @Test func aSmallOwnerClampsTheContentToItsOwnBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 65, height: 80)
        #expect(DownloadPreviewGeometry.modalFrame(in: bounds) == bounds)
    }
}

struct DownloadEmptyContentTests {
    @MainActor private final class Fixture {
        let window: NSWindow
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 280))
        var valid = true
        var reducedMotion = false
        lazy var view = DownloadEmptyContentView(ownerValid: { [weak self] in self?.valid == true },
            reduceMotion: { [weak self] in self?.reducedMotion == true })

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            view.frame = host.bounds
        }

        func attach() { host.addSubview(view) }

        var animation: CAAnimation? { view.layer?.animation(forKey: "empty.translation") }
    }

    @MainActor @Test func anUnattachedEmptyViewDoesNotAnimate() {
        let fixture = Fixture()
        fixture.view.show(.empty)
        #expect(fixture.animation == nil)
    }

    @MainActor @Test func theEmptyStateStartsOnlyOnPresentation() throws {
        let fixture = Fixture()
        fixture.host.isHidden = true
        fixture.attach()
        fixture.view.show(.empty)
        #expect(fixture.animation == nil)
        fixture.host.isHidden = false
        let slide = try #require(fixture.animation as? CASpringAnimation)
        #expect(slide.fromValue as? Int == 16)
        let fade = try #require(fixture.view.layer?.animation(forKey: "empty.opacity") as? CABasicAnimation)
        #expect(fade.fromValue as? Int == 0)
    }

    @MainActor @Test func loadingDoesNotBorrowTheEmptyStateEntrance() {
        let fixture = Fixture()
        fixture.attach()
        fixture.view.show(.status)
        #expect(fixture.animation == nil)
        #expect(!fixture.view.isHidden)
    }

    @MainActor @Test func resizeSettlesTheActiveEntranceWithoutReplayingIt() {
        let fixture = Fixture()
        fixture.attach()
        fixture.view.show(.empty)
        fixture.view.setFrameSize(CGSize(width: 360, height: 280))
        #expect(fixture.animation == nil)
        #expect(fixture.view.layer?.opacity == 1)
    }

    @MainActor @Test func reduceMotionStillShowsTheSuccessfulEmptyState() {
        let fixture = Fixture()
        fixture.reducedMotion = true
        fixture.attach()
        fixture.view.show(.empty)
        #expect(!fixture.view.isHidden && fixture.animation == nil)
    }

    @MainActor @Test func retiringItsWindowBlocksAnotherEntrance() throws {
        let fixture = Fixture()
        fixture.attach()
        fixture.view.show(.empty)
        try #require(fixture.animation != nil)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: fixture.window)
        fixture.view.show(.empty)
        #expect(fixture.animation == nil)
    }
}
