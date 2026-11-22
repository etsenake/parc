import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcLibrary
@testable import ParcNotes

struct CaptureLensMotionTests {
    private let first = CGRect(x: 10, y: 20, width: 200, height: 100)
    private let second = CGRect(x: 300, y: 200, width: 100, height: 80)
    private let latest = CGRect(x: 100, y: 40, width: 400, height: 200)

    private func pendingMotion() -> CaptureLensMotion {
        var motion = CaptureLensMotion()
        motion.target(first, at: 0, animated: true)
        motion.target(second, at: 0.01, animated: true)
        return motion
    }

    @Test func theFirstTargetSnapsIntoPlaceWithoutAnimating() {
        var motion = CaptureLensMotion()
        motion.target(first, at: 0, animated: true)
        #expect(motion.rect == first && !motion.isAnimating)
    }

    @Test func aThrottledTargetKeepsTheCurrentPresentationUntilItCanMove() {
        var motion = pendingMotion()
        #expect(motion.isAnimating)
        motion.tick(at: 0.08)
        #expect(motion.rect == first)
    }

    @Test func theLatestThrottledTargetReplacesTheIntermediateTarget() {
        var motion = pendingMotion()
        motion.target(latest, at: 0.02, animated: true)
        motion.tick(at: 0.10)
        motion.settle(at: 0.11)
        #expect(motion.rect == latest)
    }

    @Test func retargetingDuringASpringKeepsItsCurrentPresentation() {
        var motion = pendingMotion()
        motion.tick(at: 0.1)
        let presented = motion.rect
        motion.target(latest, at: 0.2, animated: true)
        #expect(motion.rect == presented)
    }

    @Test func aRetargetedSpringSettlesOnTheFinalRectangle() {
        var motion = pendingMotion()
        motion.tick(at: 0.1)
        motion.target(latest, at: 0.2, animated: true)
        for frame in 21...300 { motion.tick(at: Double(frame) / 100) }
        #expect(motion.rect == latest && !motion.isAnimating)
    }

    @Test func clearingTheLensDiscardsItsPendingTarget() {
        var motion = pendingMotion()
        motion.clear()
        motion.tick(at: 1)
        #expect(motion.rect == nil && !motion.isAnimating)
    }

    @Test func settlingTheLensUsesTheLatestPendingRectangle() {
        var motion = pendingMotion()
        motion.settle(at: 0.02)
        #expect(motion.rect == second && !motion.isAnimating)
    }
}

struct CaptureFocusReturnTests {
    @MainActor private final class InertWindow: NSWindow {
        var key = true
        override var isKeyWindow: Bool { key }
        override var canBecomeKey: Bool { true }
    }

    @MainActor fileprivate static func searchWindow() throws -> NSWindow {
        _ = NSApplication.shared
        let window = InertWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
                                 styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        try #require(window.contentView != nil)
        return window
    }

    @MainActor private struct Fixture {
        let window: InertWindow
        let first = NSButton(title: "First", target: nil, action: nil)
        let target = NSButton(title: "Second", target: nil, action: nil)

        init() throws {
            _ = NSApplication.shared
            window = InertWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                                 styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let content = try #require(window.contentView)
            content.addSubview(first)
            content.addSubview(target)
            try #require(window.makeFirstResponder(first))
        }

        func bookmark(valid: @escaping () -> Bool = { true }) -> CaptureFocusReturn {
            CaptureFocusReturn(window: window, target: target, valid: valid)
        }
    }

    @MainActor @Test func focusReturnLeavesTheBackgroundWindowAlone() throws {
        let fixture = try Fixture()
        fixture.window.key = false
        fixture.bookmark().restore()
        #expect(fixture.window.firstResponder === fixture.first)
    }

    @MainActor @Test func theOriginalKeyWindowConsumesItsDeferredFocusReturn() throws {
        let fixture = try Fixture()
        let bookmark = fixture.bookmark()
        fixture.window.key = false
        bookmark.restore()
        fixture.window.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: fixture.window)
        #expect(fixture.window.firstResponder === fixture.target)
    }

    @MainActor @Test func aConsumedFocusReturnNeverRunsTwice() throws {
        let fixture = try Fixture()
        let bookmark = fixture.bookmark()
        bookmark.restore()
        try #require(fixture.window.makeFirstResponder(fixture.first))
        bookmark.restore()
        #expect(fixture.window.firstResponder === fixture.first)
    }

    @MainActor @Test func aRetiredOwnerCannotRestoreFocus() throws {
        let fixture = try Fixture()
        fixture.bookmark(valid: { false }).restore()
        #expect(fixture.window.firstResponder === fixture.first)
    }

    @MainActor @Test func explicitUserFocusIsKept() throws {
        let fixture = try Fixture()
        let other = NSButton(title: "Other", target: nil, action: nil)
        fixture.window.contentView?.addSubview(other)
        let bookmark = fixture.bookmark()
        try #require(fixture.window.makeFirstResponder(other))
        bookmark.restore()
        #expect(fixture.window.firstResponder === other)
    }

    @MainActor @Test func movingBetweenFieldsInvalidatesTheBookmarkEvenWithASharedEditor() throws {
        let fixture = try Fixture()
        let one = NSTextField(string: "Search")
        let two = NSTextField(string: "Other field")
        fixture.window.contentView?.addSubview(one)
        fixture.window.contentView?.addSubview(two)
        try #require(fixture.window.makeFirstResponder(one))
        let bookmark = CaptureFocusReturn(window: fixture.window, target: one, valid: { true })
        let editor = fixture.window.firstResponder
        try #require(fixture.window.makeFirstResponder(two))
        try #require(fixture.window.firstResponder === editor)
        bookmark.restore()
        #expect(two.currentEditor() === editor && one.currentEditor() == nil)
    }
}

struct CaptureRevealTests {
    @MainActor @Test func revealingTheCaptureUsesTheImageFade() throws {
        let layer = CALayer()
        CaptureMotion.reveal(layer, reduceMotion: false)
        let reveal = try #require(layer.animation(forKey: "captureReveal") as? CABasicAnimation)
        #expect(reveal.duration == 1)
    }

    @MainActor @Test func reduceMotionCancelsAnExistingReveal() {
        let layer = CALayer()
        CaptureMotion.reveal(layer, reduceMotion: false)
        CaptureMotion.reveal(layer, reduceMotion: true)
        #expect(layer.animation(forKey: "captureReveal") == nil)
    }
}

struct CaptureLensFrameTests {
    @MainActor private final class Driver {
        var time: TimeInterval = 0
        var reduceMotion = false
        var frames: [Timer] = []
        lazy var lens = CaptureElementLens(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            now: { [unowned self] in time }, reduceMotion: { [unowned self] in reduceMotion },
            scheduleFrames: { [weak self] in self?.frames.append($0) })
        let first = CGRect(x: 40, y: 50, width: 180, height: 100)
        let second = CGRect(x: 260, y: 140, width: 120, height: 90)

        func animate() {
            lens.setTarget(first, animated: true)
            lens.setTarget(second, animated: true)
        }

        func advanceToRest() {
            for frame in 1...180 {
                time = Double(frame) / 60
                frames.last?.fire()
            }
        }
    }

    @MainActor @Test func theFirstLensTargetNeedsNoFrameSource() {
        let driver = Driver()
        driver.lens.setTarget(driver.first, animated: true)
        #expect(driver.frames.isEmpty)
    }

    @MainActor @Test func repeatingASettledTargetDoesNotStartFrames() {
        let driver = Driver()
        driver.lens.setTarget(driver.first, animated: true)
        driver.lens.setTarget(driver.first, animated: true)
        #expect(driver.frames.isEmpty)
    }

    @MainActor @Test func reduceMotionRetargetsWithoutStartingFrames() {
        let driver = Driver()
        driver.lens.setTarget(driver.first, animated: true)
        driver.reduceMotion = true
        driver.lens.setTarget(driver.second, animated: true)
        #expect(driver.frames.isEmpty)
    }

    @MainActor @Test func retargetingStopsFramesOnceTheSpringSettles() throws {
        let driver = Driver()
        driver.animate()
        let frame = try #require(driver.frames.first)
        try #require(frame.isValid)
        driver.advanceToRest()
        #expect(!frame.isValid)
    }

    @MainActor @Test func repeatingTheRetargetedRectangleDoesNotRestartFrames() {
        let driver = Driver()
        driver.animate()
        driver.advanceToRest()
        let scheduled = driver.frames.count
        driver.lens.setTarget(driver.second, animated: true)
        #expect(driver.frames.count == scheduled)
    }

    @MainActor @Test func clearingTheLensStopsItsFrameSource() throws {
        let driver = Driver()
        driver.animate()
        let frame = try #require(driver.frames.first)
        try #require(frame.isValid)
        driver.lens.setTarget(nil, animated: false)
        #expect(!frame.isValid)
    }
}

struct CaptureOverlayPaletteTests {
    @MainActor private func preview() throws -> PageCaptureOverlay {
        let view = PageCaptureOverlay(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let context = try #require(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        view.showPreview(try #require(context.makeImage()), sourceRect: CGRect(x: 100, y: 100, width: 200, height: 100))
        view.layoutSubtreeIfNeeded()
        return view
    }

    @MainActor private final class MarkedEditor: NSTextView {
        override func hasMarkedText() -> Bool { true }
    }

    @MainActor @Test func thePaletteIsAVisibleCardInsideTheOverlay() throws {
        let overlay = try preview()
        let card = overlay.palette.card
        #expect(overlay.palette.isPresented && card.superview === overlay && overlay.bounds.contains(card.frame))
    }

    @MainActor @Test func thePaletteStaysBesideTheCapture() throws {
        let overlay = try preview()
        #expect(!overlay.palette.card.frame.intersects(overlay.imageRect))
    }

    @MainActor @Test func openingThePaletteHighlightsSaveToLibrary() throws {
        let overlay = try preview()
        #expect(overlay.palette.highlightedRow?.id == "library")
    }

    @MainActor @Test func destinationRefreshDoesNotMoveTheDefaultHighlight() throws {
        let overlay = try preview()
        overlay.setEaselDestinations([CaptureEaselDestination(id: UUID(), title: "Moodboard", lastActive: nil)])
        #expect(overlay.palette.highlightedRow?.id == "library")
    }

    @MainActor @Test func savingKeepsTheLibraryRowHighlightedAndChecked() throws {
        let overlay = try preview()
        overlay.setLibrarySaved(true)
        #expect(overlay.palette.highlightedRow?.id == "library")
        #expect(overlay.palette.highlightedRow?.isChecked == true)
    }

    @MainActor @Test func tabStaysInThePaletteInsteadOfEnteringTheRowKeyLoop() throws {
        let overlay = try preview()
        #expect(overlay.nextKeyView == nil)
        #expect(overlay.palette.perform(#selector(NSResponder.insertTab(_:)), in: .main, editor: nil))
    }

    @MainActor @Test func compositionDoesNotDispatchOnReturn() throws {
        let overlay = try preview()
        var outputs: [CapturePaletteAction] = []
        overlay.onAction = { outputs.append($0) }
        let handled = overlay.palette.perform(#selector(NSResponder.insertNewline(_:)), in: .main, editor: MarkedEditor())
        #expect(!handled && outputs.isEmpty)
    }

    @MainActor @Test func thePreviewStartsWithTheNativeSearchFieldFocused() throws {
        let focus = try CaptureFocusReturnTests.searchWindow()
        let overlay = try preview()
        focus.contentView?.addSubview(overlay)
        overlay.focusPreferredControl()
        let editor = try #require(overlay.palette.view.search.textField.currentEditor())
        #expect(focus.firstResponder === editor)
    }

    @MainActor @Test func arrowsMoveThePaletteHighlightWithoutDispatching() throws {
        let overlay = try preview()
        let palette = overlay.palette
        var actions: [CapturePaletteAction] = []
        overlay.onAction = { actions.append($0) }
        let down = palette.perform(#selector(NSResponder.moveDown(_:)), in: .main, editor: nil)
        #expect(down && palette.highlightedRow?.id != "library")
        let up = palette.perform(#selector(NSResponder.moveUp(_:)), in: .main, editor: nil)
        #expect(up && palette.highlightedRow?.id == "library" && actions.isEmpty)
    }

    @MainActor @Test func escapeFromTheEaselSubmenuReturnsToMainSearch() throws {
        let window = try CaptureFocusReturnTests.searchWindow()
        let overlay = try preview()
        window.contentView?.addSubview(overlay)
        overlay.focusPreferredControl()
        overlay.setEaselDestinations([CaptureEaselDestination(id: UUID(), title: "Moodboard", lastActive: nil)])
        let palette = overlay.palette
        let index = try #require(palette.view.list.items.firstIndex { $0.id == "easels" })
        palette.view.list.highlightedIndex = index
        let opened = palette.perform(#selector(NSResponder.moveRight(_:)), in: .main, editor: nil)
        try #require(opened && palette.hasSubmenu)
        let closed = palette.perform(#selector(NSResponder.cancelOperation(_:)), in: .submenu(.easels), editor: nil)
        #expect(closed && !palette.hasSubmenu)
        let editor = try #require(palette.view.search.textField.currentEditor())
        #expect(window.firstResponder === editor)
    }

    @MainActor @Test func unavailableLibraryAndEaselsLeaveOnlyThePermittedOutputs() throws {
        let overlay = try preview()
        overlay.setDestinationAvailability(library: false, easels: false)
        let rows = overlay.palette.rows.map(\.id)
        #expect(rows.contains("copy") && rows.contains("save"))
        #expect(!rows.contains("library") && !rows.contains("easels"))
    }

    @MainActor @Test func aBusyComposerDisablesThePaletteRows() throws {
        let overlay = try preview()
        overlay.setOutputBusy(true)
        #expect(overlay.palette.rows.allSatisfy { !$0.isEnabled })
        #expect(overlay.palette.view.statusText == "Finish or cancel in Messages.")
    }

    @MainActor @Test func returningToSelectionRestoresTheCaptureControls() throws {
        let overlay = try preview()
        overlay.showSelection()
        overlay.layoutSubtreeIfNeeded()
        #expect(!overlay.palette.isPresented)
        #expect(overlay.nextKeyView?.isHidden == false)
    }
}

struct DownloadPreviewMotionTests {
    @MainActor private final class Fixture {
        var reduceMotion = false
        lazy var preview = DownloadLibraryPreview(reduceMotion: { [weak self] in self?.reduceMotion == true })
        var layers: [CALayer] { get throws {
            let root = try #require(preview.window?.contentView)
            let backdrop = try #require(root.subviews.first)
            let modal = try #require(root.subviews.last)
            return try ([backdrop, modal] + modal.subviews).map { view in try #require(view.layer) }
        }}

        func switchToReducedMotion() {
            reduceMotion = true
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        }
    }

    @MainActor @Test func enablingReducedMotionClearsEveryPreviewTransition() throws {
        let fixture = Fixture()
        let layers = try fixture.layers
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 5
        layers.forEach { $0.add(animation, forKey: "inertActiveTransition") }
        fixture.switchToReducedMotion()
        #expect(layers.allSatisfy { $0.animationKeys()?.isEmpty != false })
    }

    @MainActor @Test func aSettledPreviewShowsTheLiveContent() throws {
        let fixture = Fixture()
        let layers = try fixture.layers
        let live = try #require(layers.dropLast().last)
        let snapshot = try #require(layers.last)
        live.opacity = 0
        snapshot.opacity = 1
        fixture.switchToReducedMotion()
        #expect(live.opacity == 1 && snapshot.opacity == 0)
    }

    @MainActor @Test func aClosedPreviewCannotConsumeCloseTwice() {
        let fixture = Fixture()
        var closed = 0
        fixture.preview.onClosed = { closed += 1 }
        fixture.preview.close()
        fixture.switchToReducedMotion()
        #expect(closed == 1)
    }
}
