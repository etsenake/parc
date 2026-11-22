import AppKit
import QuartzCore
import Testing
@testable import Parc

@MainActor private final class ControlWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}

private final class SeeThroughView: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

private let canvasSide = NSSize(width: 32, height: 32)

@MainActor private func controlItem(_ id: String, pin: Int? = nil,
                                    execute: @escaping (NSView?) -> Void = { _ in },
                                    context: @escaping (NSView) -> Void = { _ in }) -> ExtensionControlItem {
    ExtensionControlItem(identifier: id, name: "Action " + id, tooltip: "Title " + id,
        accessibilityLabel: "Accessible " + id, image: nil, pinnedIndex: pin,
        canChangePin: true, execute: execute, showContextMenu: context, setPinned: { _ in })
}

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

@MainActor private final class Hosted {
    let window = ControlWindow()
    let button: ExtensionActionButton

    init(style: ExtensionControlStyle = .sidebar) {
        button = ExtensionActionButton(item: controlItem("a"), style: style)
        window.contentView?.addSubview(button)
        button.frame = NSRect(origin: .zero, size: style.surfaceSize)
    }

    func install(execute: @escaping (NSView?) -> Void = { _ in }, context: @escaping (NSView) -> Void = { _ in }) {
        button.update(controlItem("a", execute: execute, context: context))
    }

    func hoverAlpha() -> CGFloat { NSColor(cgColor: button.layer!.backgroundColor!)?.alphaComponent ?? 0 }

    func event(_ type: NSEvent.EventType) -> NSEvent {
        let centre = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        return NSEvent.enterExitEvent(with: type, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    func moveEvent() -> NSEvent {
        let centre = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        return NSEvent.mouseEvent(with: .mouseMoved, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    }
}

@MainActor struct ExtensionActionButtonTests {
    @Test func theDisabledActionFallbackStaysEnabled() {
        let hosted = Hosted()
        #expect(hosted.button.isEnabled)
    }

    @Test func theTooltipReachesTheControlAsAParcTooltip() {
        let hosted = Hosted()
        #expect(hosted.button.parcTooltip?.label == "Title a")
        #expect(hosted.button.toolTip == nil)
    }

    @Test func accessibilityUsesTheActionLabel() {
        #expect(Hosted().button.accessibilityLabel() == "Accessible a")
    }

    @Test func activationDispatchesOnce() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in dispatches += 1 })
        hosted.button.sendClick()
        #expect(dispatches == 1)
    }

    @Test func aCallbackThatInvalidatesTheButtonStillCompletes() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in hosted.button.invalidate(); dispatches += 1 })
        hosted.button.sendClick()
        #expect(dispatches == 1)
    }

    @Test func anInvalidatedButtonCannotDispatchAgain() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in hosted.button.invalidate(); dispatches += 1 })
        hosted.button.sendClick()
        hosted.button.sendClick()
        #expect(dispatches == 1)
    }

    @Test func accessibilityShowMenuAndPressReachTheOriginalActions() {
        let hosted = Hosted()
        var dispatches = 0, menus = 0
        hosted.install(execute: { control in dispatches += control === hosted.button ? 1 : 100 },
                       context: { control in menus += control === hosted.button ? 1 : 100 })
        #expect(hosted.button.accessibilityPerformShowMenu())
        #expect(menus == 1)
        #expect(hosted.button.accessibilityPerformPress())
        #expect(dispatches == 1)
    }

    @Test func aHiddenButtonAdvertisesNothingAndDispatchesNothing() {
        let hosted = Hosted()
        var dispatches = 0, menus = 0
        hosted.install(execute: { _ in dispatches += 1 }, context: { _ in menus += 1 })
        hosted.button.isHidden = true
        #expect(!hosted.button.isAccessibilityEnabled())
        #expect(!hosted.button.accessibilityPerformPress())
        #expect(!hosted.button.accessibilityPerformShowMenu())
        hosted.button.sendClick()
        #expect(dispatches == 0)
        #expect(menus == 0)
    }

    @Test func aDisabledButtonRejectsBothAccessibilityActions() {
        let hosted = Hosted()
        hosted.install(execute: { _ in }, context: { _ in })
        hosted.button.isEnabled = false
        #expect(!hosted.button.accessibilityPerformPress())
        #expect(!hosted.button.accessibilityPerformShowMenu())
    }

    @Test func aDetachedButtonCannotDispatch() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in dispatches += 1 })
        hosted.button.removeFromSuperview()
        #expect(!hosted.button.accessibilityPerformPress())
        #expect(!hosted.button.isAccessibilityEnabled())
        #expect(dispatches == 0)
    }

    @Test func theFocusMaskFollowsThePinSurface() {
        let hosted = Hosted()
        #expect(hosted.button.focusRingMaskBounds == hosted.button.bounds)
    }

    @Test func cellTrackingDrivesTheSidebarPressTransform() {
        let hosted = Hosted()
        hosted.button.appearance = NSAppearance(named: .aqua)
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        #expect(abs((hosted.button.layer?.transform.m11 ?? 0) - 0.95) < 0.00001)
    }

    @Test func cellTrackingDrivesThePressedFill() {
        let hosted = Hosted()
        hosted.button.appearance = NSAppearance(named: .aqua)
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        #expect(abs(hosted.hoverAlpha() - 0.09) < 0.00001)
    }

    @Test func releasingTheCellRestoresTheTransformAndClearsTheFill() {
        let hosted = Hosted()
        hosted.button.appearance = NSAppearance(named: .aqua)
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        hosted.button.cell!.highlight(false, withFrame: hosted.button.bounds, in: hosted.button)
        #expect(CATransform3DIsIdentity(hosted.button.layer!.transform))
        #expect(hosted.hoverAlpha() == 0)
    }

    @Test func losingKeyStatusCancelsTheNativePress() {
        let hosted = Hosted()
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        hosted.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: hosted.window)
        #expect(CATransform3DIsIdentity(hosted.button.layer!.transform))
        #expect(hosted.button.layer?.animation(forKey: "extensionPress") == nil)
    }

    @Test func aCommandSurfaceCoveringThePinKeepsTheHoverFillOff() {
        let hosted = Hosted()
        let cover = NSView(frame: hosted.button.frame.insetBy(dx: -4, dy: -4))
        hosted.window.contentView?.addSubview(cover)
        hosted.button.mouseEntered(with: hosted.event(.mouseEntered))
        #expect(hosted.hoverAlpha() == 0)
    }

    @Test func movingOutFromUnderTheCoverRestoresTheHoverFill() {
        let hosted = Hosted()
        let cover = NSView(frame: hosted.button.frame.insetBy(dx: -4, dy: -4))
        hosted.window.contentView?.addSubview(cover)
        hosted.button.mouseEntered(with: hosted.event(.mouseEntered))
        cover.removeFromSuperview()
        hosted.button.mouseMoved(with: hosted.moveEvent())
        #expect(abs(hosted.hoverAlpha() - 0.071) < 0.00001)
    }

    @Test func aSeeThroughOverlayLeavesTheHoverFillAlone() {
        let hosted = Hosted()
        hosted.window.contentView?.addSubview(SeeThroughView(frame: hosted.button.frame.insetBy(dx: -4, dy: -4)))
        hosted.button.mouseEntered(with: hosted.event(.mouseEntered))
        #expect(abs(hosted.hoverAlpha() - 0.071) < 0.00001)
    }

    @Test func theToolbarCellDoesNotAcquireTheSidebarPressSpring() {
        let hosted = Hosted(style: .toolbar)
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        #expect(CATransform3DIsIdentity(hosted.button.layer!.transform))
        #expect(hosted.button.layer?.animation(forKey: "extensionPress") == nil)
        #expect(hosted.hoverAlpha() == 0)
    }

    @Test func appKitAddsNoPressedImageEffect() {
        #expect((Hosted(style: .toolbar).button.cell as? NSButtonCell)?.highlightsBy.isEmpty == true)
    }

    @Test(arguments: [(ExtensionControlStyle.toolbar, 0.13), (.sidebar, 0.103)])
    func aLitPinUsesItsStylesDarkPressFill(_ style: ExtensionControlStyle, _ expected: Double) {
        let hosted = Hosted(style: style)
        hosted.button.appearance = NSAppearance(named: .darkAqua)
        hosted.button.activityFill = 1
        #expect(abs(hosted.hoverAlpha() - expected) < 0.00001)
    }
}

@MainActor struct ExtensionToolbarViewTests {
    private func toolbar(width: CGFloat = 56, style: ExtensionControlStyle = .sidebar) -> ExtensionToolbarView {
        ExtensionToolbarView(frame: NSRect(x: 0, y: 0, width: width, height: style.surfaceSize.height), style: style)
    }

    private func button(_ view: ExtensionToolbarView, _ id: String) -> NSView? {
        view.subviews.first { $0.accessibilityIdentifier() == "extension-action-" + id }
    }

    @Test func onlyPinnedActionsReserveToolbarWidth() {
        let view = toolbar()
        view.update([controlItem("a", pin: 1), controlItem("b", pin: 0), controlItem("c")])
        view.layoutSubtreeIfNeeded()
        #expect(view.desiredWidth == 56)
    }

    @Test func unpinnedActionsStayOutOfTheToolbar() {
        let view = toolbar()
        view.update([controlItem("a", pin: 1), controlItem("b", pin: 0), controlItem("c")])
        #expect(view.subviews.count == 2)
    }

    @Test func pinPositionsOverrideModelOrder() throws {
        let view = toolbar()
        view.update([controlItem("a", pin: 1), controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        let a = try #require(button(view, "a")), b = try #require(button(view, "b"))
        #expect(b.frame.minX < a.frame.minX)
    }

    @Test func ordinaryUpdatesPreserveButtonIdentityAndDoNotRelayout() throws {
        let view = toolbar()
        var widths = 0
        view.onWidthChange = { widths += 1 }
        view.update([controlItem("a", pin: 1), controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        let a = try #require(button(view, "a"))
        view.update([controlItem("a", pin: 1), controlItem("b", pin: 0)])
        #expect(view.subviews.contains { $0 === a })
        #expect(widths == 1)
    }

    @Test func compressionHidesTheLaterPin() throws {
        let view = toolbar()
        view.update([controlItem("a", pin: 1), controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        view.frame.size.width = 28
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        #expect(try #require(button(view, "a")).isHidden)
        #expect(try !#require(button(view, "b")).isHidden)
    }

    @Test func aRemovedPinIsDetachedAndDisabled() throws {
        let view = toolbar()
        view.update([controlItem("a", pin: 1), controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        let a = try #require(button(view, "a") as? NSButton)
        view.update([controlItem("b", pin: 0)])
        #expect(a.superview == nil)
        #expect(!a.isEnabled)
    }

    @Test func clearingReleasesEveryPin() {
        let view = toolbar()
        view.update([controlItem("a", pin: 1), controlItem("b", pin: 0)])
        view.update([])
        #expect(view.desiredWidth == 0)
        #expect(view.subviews.isEmpty)
    }

    @Test func aSixtyThreePointToolbarHoldsOneCompleteAction() {
        let view = toolbar(width: 63, style: .toolbar)
        view.update([controlItem("first", pin: 0), controlItem("second", pin: 1)])
        view.layoutSubtreeIfNeeded()
        let buttons = view.orderedButtons
        #expect(view.desiredWidth == 64)
        #expect(!buttons[0].isHidden)
        #expect(buttons[1].isHidden)
    }

    @Test func bothToolbarPinsFitAtSixtyFourPointsWithAdjoiningSurfaces() {
        let view = toolbar(width: 63, style: .toolbar)
        view.update([controlItem("first", pin: 0), controlItem("second", pin: 1)])
        view.frame.size.width = 64
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let buttons = view.orderedButtons
        #expect(!buttons[1].isHidden)
        #expect(buttons[0].frame.maxX == buttons[1].frame.minX)
    }

    @Test func theTopBarKeepsItsShortRadiusSixSurface() {
        let view = toolbar(width: 64, style: .toolbar)
        view.update([controlItem("first", pin: 0), controlItem("second", pin: 1)])
        view.layoutSubtreeIfNeeded()
        #expect(view.orderedButtons.allSatisfy { $0.frame.height == 24 && $0.layer?.cornerRadius == 6 })
    }

    @Test func sidebarPinsKeepTheirSquareRadiusNineSurface() throws {
        let view = toolbar()
        view.update([controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        let b = try #require(button(view, "b"))
        #expect(b.frame.size == NSSize(width: 28, height: 28))
        #expect(b.layer?.cornerRadius == 9)
    }
}

@MainActor struct ExtensionActionArtworkTests {
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
        let button = ExtensionActionButton(item: controlItem("fallback"))
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
        button.update(controlItem("art"))
        #expect(button.imagePosition == .imageOnly)
    }
}
