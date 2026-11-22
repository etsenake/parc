import AppKit
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct ExtensionControlsArtworkTests {
    private let canvasSide = NSSize(width: 32, height: 32)

    @MainActor private func artItem(_ image: NSImage?, pinnedArtwork: ExtensionPinnedArtwork? = nil, badgeText: String = "") -> ExtensionControlItem {
        ExtensionControlItem(identifier: "art", name: "Artwork", tooltip: "", accessibilityLabel: "", image: image,
            pinnedIndex: 0, canChangePin: true, execute: { _ in }, showContextMenu: { _ in }, setPinned: { _ in },
            pinnedArtwork: pinnedArtwork, badgeText: badgeText)
    }

    @MainActor private func paddedCanvas() -> NSImage {
        NSImage(size: canvasSide, flipped: true) { _ in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            NSRect(x: 8, y: 8, width: 16, height: 16).fill()
            return true
        }
    }

    private let green = NSColor(srgbRed: 0, green: 0.8, blue: 0, alpha: 1)
    private let red = { (color: NSColor) in color.redComponent > 0.5 && color.greenComponent < 0.3 && color.blueComponent < 0.3 }

    private func button(_ image: NSImage?, style: ExtensionControlStyle, size: NSSize? = nil) -> ExtensionActionButton {
        let button = ExtensionActionButton(item: artItem(image), style: style)
        button.frame = NSRect(origin: .zero, size: size ?? style.surfaceSize)
        return button
    }

    private func badged(_ text: String, style: ExtensionControlStyle, unbadged: NSImage? = nil) -> ExtensionActionButton {
        let artwork = ExtensionPinnedArtwork(unbadged: unbadged ?? paddedCanvas(), badgeText: text, textColor: .white, backgroundColor: green)
        let button = ExtensionActionButton(item: artItem(NSImage(size: canvasSide), pinnedArtwork: artwork, badgeText: text), style: style)
        button.frame = NSRect(origin: .zero, size: style.surfaceSize)
        button.layoutSubtreeIfNeeded()
        return button
    }

    private func topEdgeFrame(_ frame: NSRect?, in button: NSView) -> NSRect? {
        guard var frame else { return nil }
        if !button.isFlipped { frame.origin.y = button.bounds.height - frame.maxY }
        return frame
    }

    private func ink(_ host: NSView, scale: Int, _ match: (NSColor) -> Bool) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * scale,
            pixelsHigh: Int(host.bounds.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        var bounds = (minX: Int.max, maxX: -1, minY: Int.max, maxY: -1)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5, match(color) else { continue }
                bounds = (min(bounds.minX, x), max(bounds.maxX, x), min(bounds.minY, y), max(bounds.maxY, y))
            }
        }
        return bounds
    }

    @Test func theToolbarCellCentersTheCanvasRegardlessOfItsHitSurface() {
        let button = button(NSImage(size: canvasSide), style: .toolbar)
        #expect(button.cell?.imageRect(forBounds: button.bounds) == NSRect(x: 0, y: -4, width: 32, height: 32))
    }

    @Test func theSidebarCanvasCentersTheSixteenPointIcon() {
        let button = button(NSImage(size: canvasSide), style: .sidebar)
        #expect(button.cell?.imageRect(forBounds: button.bounds) == NSRect(x: -2, y: -2, width: 32, height: 32))
    }

    @Test func theBadgeMayOverhangTheToolbarSurface() {
        let button = button(NSImage(size: canvasSide), style: .toolbar)
        let toolbar = ExtensionToolbarView(frame: .zero, style: .toolbar)
        #expect(!button.clipsToBounds)
        #expect(!toolbar.clipsToBounds)
    }

    @Test func anImageThatIsNotTheCanvasKeepsTheCentredSixteenPointRect() {
        let button = button(NSImage(size: NSSize(width: 64, height: 64)), style: .toolbar)
        #expect(button.cell?.imageRect(forBounds: button.bounds) == NSRect(x: 8, y: 4, width: 16, height: 16))
    }

    @Test func theFallbackSymbolKeepsTheCentredSixteenPointRect() {
        let button = ExtensionActionButton(item: ExtensionControlsSupport.controlItem("fallback"))
        button.frame = NSRect(origin: .zero, size: ExtensionControlStyle.sidebar.surfaceSize)
        #expect(button.cell?.imageRect(forBounds: button.bounds) == NSRect(x: 6, y: 6, width: 16, height: 16))
    }

    @Test(arguments: [ExtensionControlStyle.toolbar, .sidebar], [1, 2])
    func aPaddedCanvasRendersSixteenPointsOfIconInk(_ style: ExtensionControlStyle, _ scale: Int) {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
        let rendered = button(paddedCanvas(), style: style)
        rendered.frame.origin = NSPoint(x: 8, y: 8)
        host.addSubview(rendered)
        let icon = ink(host, scale: scale, red)
        #expect(icon.maxX - icon.minX + 1 == 16 * scale)
        #expect(icon.maxY - icon.minY + 1 == 16 * scale)
    }

    struct BadgeCase: Sendable, CustomTestStringConvertible {
        let text: String
        let style: ExtensionControlStyle
        let expected: NSRect
        var testDescription: String { "\(text) on \(style)" }
        static let all = [
            BadgeCase(text: "3", style: .toolbar, expected: NSRect(x: 17, y: 0, width: 11, height: 11)),
            BadgeCase(text: "3", style: .sidebar, expected: NSRect(x: 15, y: 2, width: 11, height: 11)),
            BadgeCase(text: "12", style: .sidebar, expected: NSRect(x: 11, y: 2, width: 15, height: 11)),
            BadgeCase(text: "NEW", style: .toolbar, expected: NSRect(x: 3, y: 0, width: 25, height: 11)),
            BadgeCase(text: "9999", style: .toolbar, expected: NSRect(x: 2, y: 0, width: 26, height: 11)),
            BadgeCase(text: "WWWWWW", style: .sidebar, expected: NSRect(x: 0, y: 2, width: 26, height: 11)),
        ]
    }

    @Test(arguments: BadgeCase.all)
    func aBadgeSitsOnTheIconsTopRightCorner(_ badgeCase: BadgeCase) {
        let button = badged(badgeCase.text, style: badgeCase.style)
        #expect(topEdgeFrame(button.badgeFrame, in: button) == badgeCase.expected)
    }

    @Test(arguments: BadgeCase.all)
    func aBadgedStripShowsTheUnbadgedCanvasUnderItsOwnBadge(_ badgeCase: BadgeCase) {
        let unbadged = paddedCanvas()
        let button = badged(badgeCase.text, style: badgeCase.style, unbadged: unbadged)
        #expect(button.image === unbadged)
    }

    @Test(arguments: BadgeCase.all)
    func voiceOverReadsTheBadgeAsTheActionsValue(_ badgeCase: BadgeCase) {
        #expect(badged(badgeCase.text, style: badgeCase.style).accessibilityValue() as? String == badgeCase.text)
    }

    @Test func theBadgePassesClicksToItsActionButton() throws {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
        let button = badged("3", style: .sidebar)
        host.addSubview(button)
        let frame = try #require(button.badgeFrame)
        let centre = NSPoint(x: frame.midX, y: frame.midY)
        #expect(button.hitTest(button.convert(centre, to: button.superview)) === button)
    }

    @Test(arguments: [ExtensionControlStyle.toolbar, .sidebar])
    func theBadgeRendersAsAnElevenPointCircleOverhangingTheIcon(_ style: ExtensionControlStyle) {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
        let button = badged("3", style: style)
        button.frame.origin = NSPoint(x: 8, y: 8)
        host.addSubview(button)
        let icon = ink(host, scale: 2, red)
        let badge = ink(host, scale: 2) { $0.greenComponent > 0.6 && $0.redComponent < 0.3 && $0.blueComponent < 0.3 }
        #expect(badge.maxX - badge.minX + 1 == 22)
        #expect(badge.maxY - badge.minY + 1 == 22)
        #expect(badge.maxX == icon.maxX + 8)
        #expect(badge.minY == icon.minY - 8)
    }

    @Test func withoutTheUnbadgedCanvasTheBakedCanvasShowsAlone() {
        let artwork = NSImage(size: canvasSide)
        let baked = ExtensionActionButton(item: artItem(artwork, badgeText: "7"), style: .toolbar)
        #expect(baked.image === artwork)
        #expect(baked.badgeFrame == nil)
    }

    @Test func voiceOverReadsAnOlderEnginesBakedBadgeToo() {
        let baked = ExtensionActionButton(item: artItem(NSImage(size: canvasSide), badgeText: "7"), style: .toolbar)
        #expect(baked.accessibilityValue() as? String == "7")
    }

    @Test func anOlderEngineWithoutTheUnbadgedCanvasFallsBackToTheBakedOne() {
        #expect(ExtensionPinnedArtwork(unbadged: nil, badgeText: "3", textColor: .white, backgroundColor: green) == nil)
    }

    @Test func aReportedBadgeWithoutItsColoursFallsBackToTheBakedCanvas() {
        #expect(ExtensionPinnedArtwork(unbadged: paddedCanvas(), badgeText: "3", textColor: nil, backgroundColor: green) == nil)
    }

    @Test func anEmptyBadgeShowsTheUnbadgedCanvasAlone() {
        let canvas = paddedCanvas()
        let plain = ExtensionPinnedArtwork(unbadged: canvas, badgeText: "", textColor: nil, backgroundColor: nil)
        #expect(plain?.image === canvas)
        #expect(plain?.badge == nil)
    }

    @Test func clearingTheBadgeTextHidesTheShellBadgeAndItsValue() {
        let canvas = paddedCanvas()
        let button = badged("3", style: .sidebar, unbadged: canvas)
        let plain = ExtensionPinnedArtwork(unbadged: canvas, badgeText: "", textColor: nil, backgroundColor: nil)
        button.update(artItem(NSImage(size: canvasSide), pinnedArtwork: plain))
        #expect(button.badgeFrame == nil)
        #expect(button.image === canvas)
        #expect(button.accessibilityValue() == nil)
    }

    @Test func presentationPreservesTheSharedImageAndItsDimensions() {
        let artwork = NSImage(size: canvasSide)
        let button = ExtensionActionButton(item: artItem(artwork), style: .toolbar)
        #expect(artwork.size == canvasSide)
        #expect(button.image === artwork)
        #expect(button.imagePosition == .imageOnly)
    }

    @Test func refreshingFallbackArtworkKeepsTheCellImageOnly() {
        let button = ExtensionActionButton(item: artItem(NSImage(size: canvasSide)), style: .toolbar)
        button.update(ExtensionControlsSupport.controlItem("art"))
        #expect(button.imagePosition == .imageOnly)
    }
}
