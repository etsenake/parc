import AppKit
import Testing
@testable import ParcSidebar

@MainActor
struct SidebarFaviconTests {
    private let placeholder = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
    private let red = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.red.setFill(); rect.fill(); return true
    }
    private let blue = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.blue.setFill(); rect.fill(); return true
    }

    private func favicon() -> SidebarFaviconView {
        let view = SidebarFaviconView()
        view.image = placeholder
        view.fallbackTintColor = .gray
        return view
    }

    @Test func fallbackGlyphsPaintWithoutWindowAppearanceVibrancy() {
        #expect(!favicon().allowsVibrancy)
    }

    @Test func theNativeImageKeepsAspectWithoutEnlargement() {
        #expect(favicon().imageScaling == .scaleProportionallyDown)
    }

    @Test func aDecorativeFaviconDoesNotDuplicateTheRowAccessibilityName() {
        #expect(!favicon().isAccessibilityElement())
    }

    @Test func aPendingLookupRetainsTheFallback() {
        let view = favicon()
        view.load { _ in }
        #expect(view.image === placeholder)
        #expect(view.contentTintColor == .gray)
    }

    @Test func anActualBitmapHasNoTemplateTint() {
        let view = favicon()
        var reply: ((NSImage?) -> Void)?
        view.load { reply = $0 }
        reply?(blue)
        #expect(view.image === blue)
        #expect(view.contentTintColor == nil)
    }

    @Test func anOlderRequestCannotReplaceANewerResult() {
        let view = favicon()
        var first: ((NSImage?) -> Void)?
        var second: ((NSImage?) -> Void)?
        view.load { first = $0 }
        view.load { second = $0 }
        second?(blue)
        first?(red)
        #expect(view.image === blue)
    }

    @Test func aThemeChangeDoesNotRecolorActualPageArtwork() {
        let view = favicon()
        view.load { $0(blue) }
        view.fallbackTintColor = .green
        #expect(view.contentTintColor == nil)
    }

    @Test func aMissingIconRestoresTheCurrentThemedFallback() {
        let view = favicon()
        view.load { $0(blue) }
        view.fallbackTintColor = .green
        view.load { $0(nil) }
        #expect(view.image === placeholder)
        #expect(view.contentTintColor == .green)
    }

    @Test func aDetachedRowRejectsADelayedCompletion() {
        let view = favicon()
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        parent.addSubview(view)
        view.frame = NSRect(x: 10, y: 10, width: 15, height: 15)
        var reply: ((NSImage?) -> Void)?
        view.load { reply = $0 }
        view.removeFromSuperview()
        reply?(red)
        #expect(view.image === placeholder)
    }

    @Test func anExplicitNewRequestOnAReusedRowCanSucceed() {
        let view = favicon()
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        parent.addSubview(view)
        var reply: ((NSImage?) -> Void)?
        view.load { reply = $0 }
        view.removeFromSuperview()
        reply?(red)
        parent.addSubview(view)
        view.load { $0(blue) }
        #expect(view.image === blue)
    }

    @Test func aNonNilLoadMarksSettledPageArt() {
        let view = favicon()
        view.load { $0(blue) }
        #expect(view.hasSettledFavicon)
    }

    @Test func adoptingInstallsSettledArtWithoutALoad() {
        let view = favicon()
        view.adoptSettled(red)
        #expect(view.hasSettledFavicon)
        #expect(view.image === red)
    }

    @Test func aReloadAfterAdoptKeepsTheThemedGlyphInterim() {
        let view = favicon()
        view.adoptSettled(red)
        view.load { _ in }
        #expect(!view.hasSettledFavicon)
        #expect(view.image === placeholder)
    }

    @Test func aLoadAfterAdoptCanStillSettleNewBytes() {
        let view = favicon()
        view.adoptSettled(red)
        var reply: ((NSImage?) -> Void)?
        view.load { reply = $0 }
        reply?(blue)
        #expect(view.image === blue)
        #expect(view.hasSettledFavicon)
    }

    @Test func aNewLoadClearsSettledArtUntilTheReply() {
        let view = favicon()
        view.adoptSettled(red)
        view.load { _ in }
        #expect(!view.hasSettledFavicon)
    }

    @Test func adoptingCancelsAnInFlightLoad() {
        let view = favicon()
        var superseded: ((NSImage?) -> Void)?
        view.load { superseded = $0 }
        view.adoptSettled(blue)
        superseded?(red)
        #expect(view.image === blue)
        #expect(view.hasSettledFavicon)
    }

    @Test func theProductionIconDrawsIntoTheNativeImageSlot() throws {
        let view = favicon()
        view.frame = NSRect(x: 10, y: 10, width: 15, height: 15)
        view.load { $0(blue) }
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        #expect(bitmap.pixelsHigh > 0)
    }

    @Test func faviconDrawingDoesNotMoveTheRowHitTargets() throws {
        let view = favicon()
        view.frame = NSRect(x: 10, y: 10, width: 15, height: 15)
        let frame = view.frame
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        #expect(view.frame == frame)
    }

    @Test func anOutstandingLookupNeverRetainsARemovedRow() {
        var late: ((NSImage?) -> Void)?
        weak var released: SidebarFaviconView?
        do {
            let temporary = SidebarFaviconView()
            released = temporary
            temporary.image = placeholder
            temporary.load { late = $0 }
        }
        #expect(released == nil)
        late?(red)
        #expect(released == nil)
    }
}
