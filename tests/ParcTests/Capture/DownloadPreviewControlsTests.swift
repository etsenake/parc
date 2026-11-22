import AppKit
import Testing
@testable import Parc

struct DownloadPreviewControlsTests {
    @MainActor final class Fixture {
        let parent: NSWindow
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-fixture.png")
        let artwork = NSImage(size: NSSize(width: 32, height: 16))
        var reduced: Bool
        var source: NSRect? = NSRect(x: 20, y: 40, width: 32, height: 16)
        var moved: [Bool] = []
        var opened = 0
        var closed = 0
        lazy var preview = DownloadLibraryPreview(reduceMotion: { [weak self] in self?.reduced == true },
            presentWindow: { _, _ in }, isPresented: { _ in true })

        init(reduced: Bool, menu: Bool = true) {
            _ = NSApplication.shared
            self.reduced = reduced
            parent = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 1000, height: 700), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
            parent.isReleasedWhenClosed = false
            preview.onMove = { [weak self] in self?.moved.append($0) }
            preview.onOpen = { [weak self] in self?.opened += 1 }
            preview.onClosed = { [weak self] in self?.closed += 1 }
            if menu { preview.onMenu = { NSMenu(title: "Original fixture") } }
            preview.sourceRect = { [weak self] in self?.source }
            preview.sourceImage = artwork
        }

        func update(title: String = "Original downloaded file.png", ordinal: Int = 1, count: Int = 2, canOpen: Bool = true,
                    previous: Bool = false, next: Bool = true) {
            preview.update(url: url, title: title, ordinal: ordinal, count: count, canOpen: canOpen,
                           canMovePrevious: previous, canMoveNext: next)
        }

        func present() { preview.present(on: parent) }

        var overlay: NSWindow { preview.window! }
        var root: NSView { overlay.contentView! }
        var modal: NSView { root.subviews.last! }
        var live: NSView { modal.subviews.first! }
        var snapshot: NSImageView { modal.subviews.compactMap { $0 as? NSImageView }.first! }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func button(_ tip: String) -> NSButton? {
            Self.descendants(modal).compactMap { $0 as? NSButton }.first { $0.toolTip == tip }
        }

        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: overlay.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
    }

    @MainActor @Test func thePreviewKeysRespectDisabledBoundsAndTheOriginalOpenCapability() {
        let fixture = Fixture(reduced: true)
        fixture.update(canOpen: false, previous: true, next: false)
        for code: UInt16 in [126, 125, 36] { fixture.overlay.sendEvent(fixture.key(code)) }
        #expect(fixture.moved == [false] && fixture.opened == 0)
        fixture.preview.close()
    }

    @MainActor @Test func spaceClosesOnePreviewOwnerExactlyOnce() {
        let fixture = Fixture(reduced: true)
        fixture.update()
        fixture.overlay.sendEvent(fixture.key(49))
        fixture.preview.close()
        #expect(fixture.closed == 1)
    }

    @MainActor @Test func reduceMotionImmediatelyShowsTheLiveContentRatherThanTheSnapshot() {
        let fixture = Fixture(reduced: true)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(fixture.live.layer?.opacity == 1 && fixture.modal.subviews.last?.layer?.opacity == 0)
        #expect(fixture.modal.layer?.animationKeys()?.isEmpty != false)
    }

    @MainActor @Test func openingPutsKeyboardFocusOnTheNativeCloseControl() {
        let fixture = Fixture(reduced: true)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(fixture.button("Close preview") === fixture.overlay.firstResponder)
    }

    @MainActor @Test func theToolbarReflectsTheOriginalSelectionEndpoints() {
        let fixture = Fixture(reduced: true)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(fixture.button("Previous download")?.isEnabled == false && fixture.button("Next download")?.isEnabled == true)
    }

    @MainActor @Test func thePreviewExposesTheOriginalItemsMoreMenu() {
        let fixture = Fixture(reduced: true)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(fixture.button("Download actions")?.isHidden == false)
    }

    @MainActor @Test func theToolbarControlsFitTheOriginalModal() {
        let fixture = Fixture(reduced: true)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        let buttons = Fixture.descendants(fixture.modal).compactMap { $0 as? NSButton }
        #expect(buttons.allSatisfy { $0.isHidden || fixture.modal.bounds.contains($0.frame) })
    }

    @MainActor @Test func theFullTitleAndPositionStayAccessible() {
        let fixture = Fixture(reduced: true)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(Fixture.descendants(fixture.modal).compactMap { $0 as? NSTextField }.first?.toolTip == "Original downloaded file.png · 1 of 2")
    }

    @MainActor @Test func dismissingRetiresTheOwnerExactlyOnce() {
        let fixture = Fixture(reduced: true)
        fixture.update()
        fixture.present()
        fixture.preview.dismiss()
        fixture.preview.close()
        #expect(fixture.closed == 1 && fixture.overlay.parent == nil)
    }

    @MainActor @Test func aRetiredParentObserverCannotCloseAnotherPreview() {
        let fixture = Fixture(reduced: true)
        fixture.update()
        fixture.present()
        fixture.preview.dismiss()
        fixture.parent.setFrameOrigin(NSPoint(x: 180, y: 190))
        #expect(fixture.closed == 1)
    }

    @MainActor @Test func aCompetingParentSheetRetiresThePreviewBeforeItsCommandCanOutliveTheOwner() {
        let fixture = Fixture(reduced: true)
        fixture.update(canOpen: false, previous: false, next: false)
        fixture.present()
        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: fixture.parent)
        #expect(fixture.closed == 1 && fixture.overlay.parent == nil)
    }

    @MainActor @Test func aValidOriginalArtworkAdmitsTheRecoveredSpringTransition() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(fixture.modal.layer?.animation(forKey: "transform") is CASpringAnimation)
    }

    @MainActor @Test func thePreviewRetainsTheOriginalRowSnapshotInsteadOfScreenshottingLiveContent() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(fixture.snapshot.image === fixture.artwork)
    }

    @MainActor @Test func theImageKeepsItsAspectCenteredThroughUniformOuterScaling() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(fixture.snapshot.frame.height == fixture.modal.bounds.width / 2)
        #expect(fixture.snapshot.frame.midY == fixture.modal.bounds.midY)
    }

    @MainActor @Test func theSourceImageAndLiveContentCrossfadeIndependently() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(fixture.snapshot.layer?.animation(forKey: "opacity") is CASpringAnimation)
        #expect(fixture.live.layer?.animation(forKey: "opacity") is CASpringAnimation)
    }

    @MainActor @Test func theFinalVisibleLayerIsTheLiveContentAndTheWholeModalDoesNotFade() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        #expect(fixture.snapshot.layer?.opacity == 0 && fixture.live.layer?.opacity == 1)
        #expect(fixture.modal.layer?.animation(forKey: "opacity") == nil)
    }

    @MainActor @Test func theOwnedOuterShadowStaysVisibleOutsideTheClippedContent() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        let layer = fixture.modal.layer
        #expect(layer?.shadowRadius == 5 && layer?.shadowOffset == NSSize(width: 0, height: -3) && layer?.masksToBounds == false)
    }

    @MainActor @Test func changingTheSelectedPreviewKeepsTheInvocationsSourceImage() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        fixture.update(title: "Next preview", ordinal: 2, canOpen: false, previous: true, next: false)
        #expect(fixture.snapshot.image === fixture.artwork)
    }

    @MainActor @Test func closingReversesTheImageAndContentWithoutReplacingTheSource() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        let snapshot = fixture.snapshot, live = fixture.live, modal = fixture.modal
        fixture.preview.dismiss()
        defer { fixture.preview.close() }
        #expect(snapshot.layer?.opacity == 1 && live.layer?.opacity == 0)
        #expect(modal.layer?.shadowOpacity == 0)
    }

    @MainActor @Test func anInterruptedOpeningTransitionsTowardTheSourceWithoutResettingTheVisibleLayer() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        let modal = fixture.modal
        fixture.preview.dismiss()
        defer { fixture.preview.close() }
        #expect(modal.layer?.animation(forKey: "transform")?.isRemovedOnCompletion == false)
    }

    @MainActor @Test func immediateRetirementSupersedesAnActiveCloseAnimationExactlyOnce() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        let snapshot = fixture.snapshot
        fixture.preview.dismiss()
        fixture.preview.close()
        #expect(fixture.closed == 1 && fixture.overlay.parent == nil)
        #expect(fixture.preview.sourceImage == nil && snapshot.image == nil)
    }

    @MainActor @Test func resizingTheParentSettlesBothImageAndContentAnimationsTogether() {
        let fixture = Fixture(reduced: false)
        fixture.update()
        fixture.present()
        defer { fixture.preview.close() }
        let modal = fixture.modal
        fixture.parent.setFrame(NSRect(x: 180, y: 190, width: 750, height: 480), display: false)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: fixture.parent)
        fixture.root.layoutSubtreeIfNeeded()
        #expect(modal.subviews.allSatisfy { $0.layer?.animationKeys()?.isEmpty != false })
    }

    @MainActor @Test func anAbsentOrOffscreenRowDismissesImmediatelyWithoutAnAnimationOwner() {
        let fixture = Fixture(reduced: false)
        fixture.source = nil
        fixture.update()
        fixture.present()
        #expect(fixture.modal.layer?.animationKeys()?.isEmpty != false)
        fixture.preview.dismiss()
        #expect(fixture.closed == 1)
    }
}
