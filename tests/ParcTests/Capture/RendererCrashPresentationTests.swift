import AppKit
import Testing
@testable import Parc
@testable import ParcKit

struct RendererCrashPresentationTests {
    @MainActor private final class VisibilityWindow: NSWindow {
        var simulatedVisible = true
        override var isVisible: Bool { simulatedVisible }
        override var canBecomeKey: Bool { true }
    }

    @MainActor private struct Fixture {
        let window: VisibilityWindow
        let page = NSView(frame: CGRect(x: 0, y: 0, width: 640, height: 375))
        let failure: PageFailureView
        let first = RendererCrashPresentation(pageIdentifier: "original", identity: NSObject(), terminationStatus: 1, errorCode: 42)
        let replacement = RendererCrashPresentation(pageIdentifier: "original", identity: NSObject(), terminationStatus: 1, errorCode: 7)
        let rendererArtwork: NSImage
        let navigationArtwork: NSImage

        init() throws {
            _ = NSApplication.shared
            window = VisibilityWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 420),
                                      styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let root = try #require(window.contentView)
            rendererArtwork = try #require(SadTabContent.templateImage(
                in: Bundle.module.url(forResource: "SadTab", withExtension: nil, subdirectory: "CaptureFixtures"), named: "SadTab"))
            navigationArtwork = try #require(SadTabContent.templateImage(
                in: Bundle.module.url(forResource: "PageFailure", withExtension: nil, subdirectory: "CaptureFixtures"), named: "PageFailure"))
            failure = PageFailureView(frame: page.frame, rendererArtwork: { [rendererArtwork] in rendererArtwork },
                                      navigationArtwork: { [navigationArtwork] in navigationArtwork })
            root.addSubview(page)
            root.addSubview(failure)
            failure.pageView = page
        }

        func showFirst() {
            failure.showRendererFailure(first)
            failure.layoutSubtreeIfNeeded()
        }

        func paint() throws {
            let context = try #require(CGContext(data: nil, width: 640, height: 375, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            failure.draw(failure.bounds)
        }

        func click(at point: NSPoint) throws {
            let location = failure.sentence.convert(point, to: nil)
            let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            failure.sentence.mouseDown(with: down)
            failure.sentence.mouseUp(with: up)
        }
    }

    @MainActor @Test func theBracketedWordIsTheOnlyReloadLink() {
        typealias Segment = SadTabContent.Segment
        #expect(SadTabContent.segments(SadTabContent.message) == [
            Segment(text: "Tab crashed. Maybe ", isLink: false),
            Segment(text: "reload", isLink: true),
            Segment(text: " the page?", isLink: false),
        ])
    }

    @MainActor @Test(arguments: [("[reload]", "reload"), ("No brackets", "No brackets")])
    func aStandaloneMessageFormsOneLink(_ message: String, _ text: String) {
        #expect(SadTabContent.segments(message) == [.init(text: text, isLink: true)])
    }

    @MainActor @Test func crashArtworkLoadsAsATemplateWithBothBackingScales() throws {
        let fixture = try Fixture()
        let image = fixture.rendererArtwork
        #expect(image.isTemplate && image.size == NSSize(width: 96, height: 103))
        #expect(image.representations.compactMap { ($0 as? NSBitmapImageRep)?.pixelsWide }.sorted() == [96, 192])
    }

    @MainActor @Test func navigationArtworkLoadsAsATemplate() throws {
        let fixture = try Fixture()
        #expect(fixture.navigationArtwork.isTemplate)
    }

    @MainActor @Test func aNavigationFailureShowsItsOwnArtworkAndRetry() throws {
        let fixture = try Fixture()
        fixture.failure.showNavigationFailure("Could not connect")
        fixture.failure.layoutSubtreeIfNeeded()
        #expect(fixture.failure.artwork.image === fixture.navigationArtwork)
        #expect(fixture.failure.artwork.frame.size == NSSize(width: 96, height: 96))
        #expect(fixture.failure.sentence.text == "This page couldn’t open. Try again")
        #expect(fixture.failure.corner.text == "Could not connect")
    }

    @MainActor @Test func aCrashReplacesNavigationErrorWithItsOwnSnapshot() throws {
        let fixture = try Fixture()
        fixture.failure.showNavigationFailure("Could not connect")
        fixture.showFirst()
        #expect(fixture.failure.presentation == .renderer(fixture.first))
        #expect(fixture.failure.artwork.image === fixture.rendererArtwork)
        #expect(fixture.failure.sentence.text == SadTabContent.plainMessage)
        #expect(fixture.failure.corner.text == "Error code: 42")
    }

    @MainActor @Test func aCrashedPageStaysInItsOriginalHierarchyButCannotReceiveInput() throws {
        let fixture = try Fixture()
        let root = fixture.page.superview
        fixture.showFirst()
        #expect(fixture.page.isHidden && fixture.page.superview === root && fixture.page.window === fixture.window)
        #expect(fixture.page.hitTest(CGPoint(x: 30, y: 30)) == nil)
        #expect(fixture.page.isAccessibilityHidden())
    }

    @MainActor @Test func theCrashMessageIsCenteredBelowTheArtwork() throws {
        let fixture = try Fixture()
        fixture.showFirst()
        let view = fixture.failure, art = view.artwork.frame, message = view.sentence.frame
        #expect(abs(art.midX - view.bounds.midX) < 1)
        #expect(abs(message.midX - view.bounds.midX) < 1)
        #expect(abs(message.minY - art.maxY - 64) < 1)
    }

    @MainActor @Test func theCrashCodeSitsInTheBottomTrailingCorner() throws {
        let fixture = try Fixture()
        fixture.showFirst()
        let view = fixture.failure, code = view.corner.frame
        #expect(abs(code.maxX - view.bounds.maxX + 20) < 1)
        #expect(abs(code.maxY - view.bounds.maxY + 20) < 1)
    }

    @MainActor @Test func aNarrowPaneWrapsTheReloadMessage() throws {
        let fixture = try Fixture()
        fixture.showFirst()
        let fit = fixture.failure.sentence.fittingSize(width: 120)
        #expect(fit.width <= 120 && fit.height > SadTabContent.lineHeight)
    }

    @MainActor @Test func onlyTheLinkedWordTakesPointerHits() throws {
        let fixture = try Fixture()
        fixture.showFirst()
        let sentence = fixture.failure.sentence
        let link = sentence.linkRect
        #expect(sentence.hitTest(sentence.convert(CGPoint(x: link.midX, y: link.midY), to: fixture.failure)) === sentence)
        #expect(sentence.hitTest(sentence.convert(CGPoint(x: 0, y: link.midY), to: fixture.failure)) == nil)
    }

    @MainActor @Test func voiceOverExposesReloadAsALinkAndTheCodeAsText() throws {
        let fixture = try Fixture()
        fixture.showFirst()
        #expect(fixture.failure.sentence.accessibilityRole() == .link)
        #expect(fixture.failure.sentence.accessibilityLabel() == SadTabContent.plainMessage)
        #expect(fixture.failure.corner.accessibilityRole() == .staticText)
        #expect(!fixture.failure.sentence.canBecomeKeyView)
    }

    @MainActor @Test func anUnpaintedCrashCannotRetry() throws {
        let fixture = try Fixture()
        var retries: [RendererCrashPresentation] = []
        fixture.failure.onRetryRenderer = { retries.append($0) }
        fixture.showFirst()
        fixture.failure.sentence.performClick(nil)
        #expect(retries.isEmpty)
    }

    @MainActor @Test func anInvisibleOwnerCannotAcknowledgeOrFocusACrash() throws {
        let fixture = try Fixture()
        fixture.window.simulatedVisible = false
        var paints: [RendererCrashPresentation] = []
        fixture.failure.onRendererPresented = { paints.append($0); return true }
        fixture.showFirst()
        try fixture.paint()
        #expect(paints.isEmpty)
        #expect(!fixture.failure.focusRendererAction(fixture.first))
    }

    @MainActor @Test func repaintingAnAcknowledgedCrashDoesNotRepeatItsAcknowledgment() throws {
        let fixture = try Fixture()
        var paints: [RendererCrashPresentation] = []
        fixture.failure.onRendererPresented = { paints.append($0); return true }
        fixture.showFirst()
        try fixture.paint()
        try fixture.paint()
        #expect(paints == [fixture.first])
    }

    @MainActor @Test(arguments: [false, true])
    func clickingTheMessageRetriesOnlyWhenThePointerHitsReload(_ hitLink: Bool) throws {
        let fixture = try Fixture()
        var retries: [RendererCrashPresentation] = []
        fixture.failure.onRendererPresented = { _ in true }
        fixture.failure.onRetryRenderer = { retries.append($0) }
        fixture.showFirst()
        try fixture.paint()
        let link = fixture.failure.sentence.linkRect
        try fixture.click(at: CGPoint(x: hitLink ? link.midX : link.maxX + 20, y: link.midY))
        #expect(retries == (hitLink ? [fixture.first] : []))
        #expect(fixture.window.firstResponder !== fixture.failure.sentence)
    }

    @MainActor @Test func retryKeepsTheCrashedPageUntilNativeRecovery() throws {
        let fixture = try Fixture()
        fixture.failure.onRendererPresented = { _ in true }
        fixture.showFirst()
        try fixture.paint()
        fixture.failure.sentence.performClick(nil)
        #expect(fixture.failure.presentation == .renderer(fixture.first) && fixture.page.isHidden)
    }

    @MainActor @Test func explicitCrashFocusLetsSpaceRetryThatSnapshot() throws {
        let fixture = try Fixture()
        var retries: [RendererCrashPresentation] = []
        fixture.failure.onRendererPresented = { _ in true }
        fixture.failure.onRetryRenderer = { retries.append($0) }
        fixture.showFirst()
        try fixture.paint()
        try #require(fixture.failure.focusRendererAction(fixture.first))
        #expect(fixture.failure.ownsFirstResponder)
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ",
            isARepeat: false, keyCode: 49))
        fixture.failure.sentence.keyDown(with: key)
        #expect(retries == [fixture.first])
    }

    @MainActor @Test func accessibilityPressRetriesTheAcknowledgedCrash() throws {
        let fixture = try Fixture()
        var retries: [RendererCrashPresentation] = []
        fixture.failure.onRendererPresented = { _ in true }
        fixture.failure.onRetryRenderer = { retries.append($0) }
        fixture.showFirst()
        try fixture.paint()
        #expect(fixture.failure.sentence.accessibilityPerformPress())
        #expect(retries == [fixture.first])
    }

    @MainActor @Test func repeatedCrashMetadataDoesNotStealAddressFocus() throws {
        let fixture = try Fixture()
        let address = NSTextField(string: "https://example.test")
        fixture.window.contentView?.addSubview(address)
        try #require(fixture.window.makeFirstResponder(address))
        let responder = fixture.window.firstResponder
        fixture.showFirst()
        try fixture.paint()
        fixture.showFirst()
        try fixture.paint()
        #expect(fixture.window.firstResponder === responder)
    }

    @MainActor @Test func clearingTheCrashRestoresTheSamePageAndDisablesReload() throws {
        let fixture = try Fixture()
        fixture.showFirst()
        fixture.failure.clear()
        #expect(!fixture.page.isHidden && !fixture.page.isAccessibilityHidden())
        #expect(fixture.page.window === fixture.window)
        #expect(!fixture.failure.sentence.accessibilityPerformPress())
    }

    @MainActor @Test func ordinaryNavigationRetryHasItsOwnAction() throws {
        let fixture = try Fixture()
        var navigationRetries = 0
        fixture.failure.onReload = { navigationRetries += 1 }
        fixture.failure.showNavigationFailure("Could not connect")
        fixture.failure.sentence.performClick(nil)
        #expect(navigationRetries == 1)
    }

    @MainActor @Test func aReentrantReplacementRequiresItsOwnDrawingBeforeRetry() throws {
        let fixture = try Fixture()
        var acknowledged: [RendererCrashPresentation] = []
        var retries: [RendererCrashPresentation] = []
        fixture.failure.onRetryRenderer = { retries.append($0) }
        fixture.failure.onRendererPresented = { [weak failure = fixture.failure] crash in
            acknowledged.append(crash)
            if crash == fixture.first { failure?.showRendererFailure(fixture.replacement) }
            return true
        }
        defer { fixture.failure.onRendererPresented = nil }
        fixture.showFirst()
        try fixture.paint()
        #expect(!fixture.failure.focusRendererAction(fixture.first))
        fixture.failure.sentence.performClick(nil)
        #expect(retries.isEmpty)
        try fixture.paint()
        fixture.failure.sentence.performClick(nil)
        #expect(acknowledged == [fixture.first, fixture.replacement] && retries == [fixture.replacement])
    }

    @MainActor @Test func recoveryDuringAcknowledgmentDoesNotAuthorizeRetry() throws {
        let fixture = try Fixture()
        fixture.failure.onRendererPresented = { [weak failure = fixture.failure] _ in failure?.clear(); return true }
        var retries: [RendererCrashPresentation] = []
        fixture.failure.onRetryRenderer = { retries.append($0) }
        fixture.showFirst()
        try fixture.paint()
        fixture.failure.sentence.performClick(nil)
        #expect(fixture.failure.presentation == nil && !fixture.page.isHidden && retries.isEmpty)
    }

    @MainActor @Test func recoveryPreservesAnIndependentlyHiddenAccessibilityTree() throws {
        let fixture = try Fixture()
        fixture.page.setAccessibilityHidden(true)
        fixture.showFirst()
        fixture.failure.clear()
        #expect(fixture.page.isAccessibilityHidden())
    }

    @MainActor @Test func replacingThePageChangesWhichHierarchyTheCrashHides() throws {
        let fixture = try Fixture()
        fixture.showFirst()
        let replacement = NSView(frame: fixture.page.frame)
        fixture.window.contentView?.addSubview(replacement)
        fixture.failure.pageView = replacement
        #expect(!fixture.page.isHidden && !fixture.page.isAccessibilityHidden())
        #expect(replacement.isHidden && replacement.isAccessibilityHidden())
    }

    @MainActor @Test(arguments: [(false, 1.0), (true, 0.0)])
    func theFailureBackingRemainsOpaqueInBothAppearances(_ dark: Bool, _ white: Double) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var components: [Double] = []
        appearance.performAsCurrentDrawingAppearance {
            if let rgb = SadTabContent.backing.usingColorSpace(.sRGB) {
                components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent].map(Double.init)
            }
        }
        #expect(components == [white, white, white, 1])
    }
}
