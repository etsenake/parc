import AppKit
import Testing
@testable import Parc

private final class FlippedRow: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
struct SidebarRowActionButtonTests {
    @MainActor private final class Owner {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let button = SidebarRowActionButton("Archive Tab")
        let reset = SidebarRowResetRegion()
        var available = true
        var accepts = true
        var dispatches = 0
        var queries = 0
        var revision = 0
        var menus = 0

        init(attached: Bool = true) {
            window.isReleasedWhenClosed = false
            button.frame = NSRect(x: 10, y: 10, width: 24, height: 25)
            button.prepareAction = { [unowned self] in
                queries += 1
                guard available else { return nil }
                let original = revision
                var used = false
                return { [unowned self] in
                    guard available, accepts, original == revision, !used else { return false }
                    used = true
                    dispatches += 1
                    return true
                }
            }
            reset.frame = NSRect(x: 40, y: 10, width: 30, height: 35)
            reset.prepareAction = button.prepareAction
            if attached {
                window.contentView!.addSubview(button)
                button.refreshAvailability()
            }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func attachReset() {
            window.contentView!.addSubview(reset)
            reset.refreshAvailability()
        }

        func rightMouseDown() -> NSEvent {
            NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
    }

    private func withoutModifiers<T>(_ body: () -> T) -> T {
        InputOverrides.install()
        InputOverrides.modifierFlags = []
        defer { InputOverrides.modifierFlags = nil }
        return body()
    }

    @Test func theActionHasItsExactLabel() {
        #expect(Owner(attached: false).button.accessibilityLabel() == "Archive Tab")
    }

    @Test func theActionKeepsNativeKeyboardFocusTreatment() {
        #expect(Owner(attached: false).button.focusRingType == .exterior)
    }

    @Test func aDetachedButtonNeitherConsultsNorDispatchesToTheOwner() {
        let owner = Owner(attached: false)
        #expect(!owner.button.accessibilityPerformPress())
        #expect(owner.queries == 0)
    }

    @Test func anAttachedOriginalActionIsAvailable() {
        let owner = Owner()
        #expect(owner.button.isEnabled)
        #expect(owner.button.isAccessibilityEnabled())
    }

    @Test func anAccessibilityPressReturnsTheRealAcceptedAction() {
        let owner = Owner()
        #expect(owner.button.accessibilityPerformPress())
        #expect(owner.dispatches == 1)
    }

    @Test func anOwnerRefusalIsNotSuccess() {
        let owner = Owner()
        owner.accepts = false
        #expect(!owner.button.accessibilityPerformPress())
        #expect(owner.dispatches == 0)
    }

    @Test func theOriginalCommandCannotRetargetARevisedOwner() throws {
        let owner = Owner()
        let captured = try #require(owner.button.prepareAction?())
        owner.revision += 1
        #expect(!captured())
        #expect(owner.dispatches == 0)
    }

    @Test func aNewAccessibilityRequestGetsTheCurrentOwner() {
        let owner = Owner()
        owner.revision += 1
        #expect(owner.button.accessibilityPerformPress())
        #expect(owner.dispatches == 1)
    }

    @Test func theNativeTargetActionPathGetsAFreshOwnedCommand() {
        let owner = Owner()
        owner.button.performClick(nil)
        #expect(owner.dispatches == 1)
    }

    @Test func anUnavailableOwnerDisablesTheRealControl() {
        let owner = Owner()
        owner.available = false
        owner.button.refreshAvailability()
        #expect(!owner.button.isEnabled)
        #expect(!owner.button.isAccessibilityEnabled())
    }

    @Test func anUnavailableAccessibilityPressDoesNotDispatch() {
        let owner = Owner()
        owner.available = false
        owner.button.refreshAvailability()
        #expect(!owner.button.accessibilityPerformPress())
        #expect(owner.dispatches == 0)
    }

    @Test func availabilityCanReturnWithoutRebuildingTheRow() {
        let owner = Owner()
        owner.available = false
        owner.button.refreshAvailability()
        owner.available = true
        owner.button.refreshAvailability()
        #expect(owner.button.isEnabled)
    }

    @Test func aHiddenPointerControlCannotDispatch() {
        let owner = Owner()
        owner.button.isHidden = true
        #expect(!owner.button.accessibilityPerformPress())
        #expect(owner.dispatches == 0)
    }

    @Test func aHiddenControlIsNotAccessibilityEnabled() {
        let owner = Owner()
        owner.button.isHidden = true
        #expect(!owner.button.isAccessibilityEnabled())
    }

    @Test func hidingCancelsAnyPresentationTransform() {
        let owner = Owner()
        owner.button.highlight(true)
        owner.button.isHidden = true
        #expect(CATransform3DIsIdentity(owner.button.layer!.transform))
    }

    @Test func hidingCancelsTheSpring() {
        let owner = Owner()
        owner.button.highlight(true)
        owner.button.isHidden = true
        #expect(owner.button.layer!.animation(forKey: "rowActionPress") == nil)
    }

    @Test func aDisabledControlClearsThePressedTransform() {
        let owner = Owner()
        owner.button.layer!.transform = CATransform3DMakeScale(0.95, 0.95, 1)
        owner.button.isEnabled = false
        #expect(CATransform3DIsIdentity(owner.button.layer!.transform))
    }

    @Test func theControlContextKeepsTheRowsMenuProvider() {
        let owner = Owner()
        owner.button.makeMenu = { owner.menus += 1; return NSMenu(title: "Original row") }
        #expect(owner.button.menu(for: owner.rightMouseDown())?.title == "Original row")
        #expect(owner.menus == 1)
    }

    @Test func detachmentCancelsThePressedTransform() {
        let owner = Owner()
        owner.button.layer!.transform = CATransform3DMakeScale(0.95, 0.95, 1)
        owner.button.removeFromSuperview()
        #expect(CATransform3DIsIdentity(owner.button.layer!.transform))
    }

    @Test func aDetachedOldControlCannotAct() {
        let owner = Owner()
        owner.button.removeFromSuperview()
        #expect(!owner.button.accessibilityPerformPress())
    }

    @Test func aDetachedControlCannotRequestAContext() {
        let owner = Owner()
        owner.button.makeMenu = { owner.menus += 1; return NSMenu(title: "Original row") }
        owner.button.removeFromSuperview()
        #expect(owner.button.menu(for: owner.rightMouseDown()) == nil)
        #expect(owner.menus == 0)
    }

    @Test func theProductionCloseRendererDrawsANativeBitmap() throws {
        let owner = Owner()
        let bitmap = try #require(owner.button.bitmapImageRepForCachingDisplay(in: owner.button.bounds))
        owner.button.cacheDisplay(in: owner.button.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        #expect(bitmap.pixelsHigh > 0)
    }

    @Test func drawingNeverChangesHitGeometry() throws {
        let owner = Owner()
        let frame = owner.button.frame
        let bitmap = try #require(owner.button.bitmapImageRepForCachingDisplay(in: owner.button.bounds))
        owner.button.cacheDisplay(in: owner.button.bounds, to: bitmap)
        #expect(owner.button.frame == frame)
    }

    private func closeInk(_ button: SidebarRowActionButton, dark: Bool) -> (alpha: CGFloat, white: CGFloat, centre: CGFloat) {
        button.dark = dark
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = button.bounds.size
        button.cacheDisplay(in: button.bounds, to: rep)
        var best = (alpha: CGFloat(0), white: CGFloat(0))
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let color = rep.colorAt(x: x, y: y)!
                if color.alphaComponent > best.alpha { best = (color.alphaComponent, color.redComponent / max(color.alphaComponent, 0.001)) }
            }
        }
        return (best.alpha, best.white, rep.colorAt(x: 24, y: 25)!.alphaComponent)
    }

    @Test func lightCloseIsBlackAtItsLightAlphaNotTheThemeTitle() {
        let light = closeInk(Owner().button, dark: false)
        #expect(abs(light.alpha - 0.565) < 0.01)
        #expect(light.white < 0.02)
    }

    @Test func darkCloseIsWhiteAtItsDarkAlpha() {
        let dark = closeInk(Owner().button, dark: true)
        #expect(abs(dark.alpha - 0.592) < 0.01)
        #expect(dark.white > 0.98)
    }

    @Test(arguments: [(false, 0.565), (true, 0.592)])
    func theBarsCrossingIsNoDarkerThanABar(dark: Bool, alpha: Double) {
        #expect(abs(closeInk(Owner().button, dark: dark).centre - alpha) < 0.01)
    }

    @Test func aDisabledCloseKeepsTheThirtyFivePercentDimming() {
        let owner = Owner()
        owner.button.isEnabled = false
        #expect(abs(closeInk(owner.button, dark: false).alpha - 0.565 * 0.35) < 0.01)
    }

    @Test func aDetachedResetRegionDoesNotConsultTheOwner() {
        let owner = Owner()
        let before = owner.queries
        #expect(!owner.reset.accessibilityPerformPress())
        #expect(owner.queries == before)
    }

    @Test func theResetRegionKeepsTheResetCommandLabel() {
        let owner = Owner()
        owner.attachReset()
        #expect(owner.reset.accessibilityLabel() == "Reset Tab to Original URL")
    }

    @Test func theResetRegionKeepsNativeKeyboardFocusTreatment() {
        #expect(Owner().reset.focusRingType == .exterior)
    }

    @Test func resetUsesTheSameExactCommandOwnerProtocol() {
        let owner = Owner()
        owner.attachReset()
        #expect(owner.reset.accessibilityPerformPress())
        #expect(owner.dispatches == 1)
    }

    @Test func theResetTargetActionPathGetsAFreshOwnedCommand() {
        let owner = Owner()
        owner.attachReset()
        owner.reset.performClick(nil)
        #expect(owner.dispatches == 1)
    }

    @Test func anIdleResetRegionIsClear() {
        let owner = Owner()
        owner.attachReset()
        #expect(owner.reset.layer!.backgroundColor == nil)
    }

    @Test func regionCornersFollowTheRowBackground() {
        let owner = Owner()
        owner.attachReset()
        let layer = owner.reset.layer!
        #expect(layer.cornerRadius == 12)
        #expect(layer.cornerCurve == .continuous)
    }

    @Test func enteringTheIconRegionReportsHover() {
        let owner = Owner()
        owner.attachReset()
        var changes = 0
        owner.reset.onHoverChange = { changes += 1 }
        owner.reset.mouseEntered(with: owner.rightMouseDown())
        #expect(owner.reset.hovered)
        #expect(changes == 1)
    }

    @Test func hoverIsTheResetSubtitleWithoutCommand() {
        let owner = Owner()
        owner.attachReset()
        withoutModifiers { owner.reset.mouseEntered(with: owner.rightMouseDown()) }
        #expect(owner.reset.hoverSubtitle == .reset)
    }

    private func hovered(_ owner: Owner) {
        owner.attachReset()
        withoutModifiers { owner.reset.mouseEntered(with: owner.rightMouseDown()) }
    }

    @Test func holdingCommandSwitchesToSeparateWithoutPointerMotion() {
        let owner = Owner()
        hovered(owner)
        #expect(owner.reset.updateHoverSubtitle(.command))
        #expect(owner.reset.hoverSubtitle == .resetAndSeparate)
    }

    @Test func otherModifiersKeepTheSeparateState() {
        let owner = Owner()
        hovered(owner)
        _ = owner.reset.updateHoverSubtitle(.command)
        #expect(!owner.reset.updateHoverSubtitle([.command, .shift]))
        #expect(owner.reset.hoverSubtitle == .resetAndSeparate)
    }

    @Test func releasingCommandRestoresReset() {
        let owner = Owner()
        hovered(owner)
        _ = owner.reset.updateHoverSubtitle(.command)
        #expect(owner.reset.updateHoverSubtitle([]))
        #expect(owner.reset.hoverSubtitle == .reset)
    }

    @Test func theHoverSubtitleStringsAreTheRecoveredOnes() {
        #expect(SidebarRowHoverSubtitle.reset.text == "Back to Pinned URL")
        #expect(SidebarRowHoverSubtitle.resetAndSeparate.text == "Separate From Pinned Tab")
    }

    private func components(_ cg: CGColor?) -> [CGFloat] {
        let c = NSColor(cgColor: cg!)!.usingColorSpace(.displayP3)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
    }

    @Test func aHoveredRegionUsesTheSidebarItemBackground() {
        let owner = Owner()
        hovered(owner)
        #expect(components(owner.reset.layer!.backgroundColor) == [0.055, 0.059, 0.063, 0.05])
    }

    @Test func eachRegionHasItsOwnCornerMask() {
        let owner = Owner()
        owner.attachReset()
        owner.reset.corners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        #expect(owner.reset.layer!.maskedCorners == [.layerMinXMinYCorner, .layerMinXMaxYCorner])
    }

    @Test func leavingClearsHoverAndTheSubtitleState() {
        let owner = Owner()
        hovered(owner)
        owner.reset.mouseExited(with: owner.rightMouseDown())
        #expect(!owner.reset.hovered)
        #expect(owner.reset.hoverSubtitle == nil)
        #expect(owner.reset.layer!.backgroundColor == nil)
    }

    @Test func hidingCancelsRegionHover() {
        let owner = Owner()
        hovered(owner)
        owner.reset.isHidden = true
        #expect(!owner.reset.hovered)
        #expect(owner.reset.hoverSubtitle == nil)
    }

    private func unavailable(_ owner: Owner) {
        owner.attachReset()
        owner.available = false
        owner.reset.refreshAvailability()
    }

    @Test func anUnavailableResetOwnerDisablesTheRegion() {
        let owner = Owner()
        unavailable(owner)
        #expect(!owner.reset.isEnabled)
        #expect(!owner.reset.isAccessibilityEnabled())
        #expect(!owner.reset.accessibilityPerformPress())
    }

    @Test func anUnavailableResetRegionLeavesTheClickToTheRow() {
        let owner = Owner()
        unavailable(owner)
        #expect(owner.reset.hitTest(NSPoint(x: 50, y: 20)) == nil)
    }

    @Test func aDisabledRegionShowsNoHover() {
        let owner = Owner()
        unavailable(owner)
        owner.reset.mouseEntered(with: owner.rightMouseDown())
        #expect(!owner.reset.hovered)
    }

    @Test func withoutASeparateOwnerCommandLeavesTheClickToTheRow() {
        let owner = Owner()
        owner.attachReset()
        InputOverrides.install()
        InputOverrides.modifierFlags = .command
        defer { InputOverrides.modifierFlags = nil }
        #expect(owner.reset.hitTest(NSPoint(x: 50, y: 20)) == nil)
    }

    @Test func anAvailableResetRegionTakesAPlainClick() {
        let owner = Owner()
        owner.attachReset()
        #expect(withoutModifiers { owner.reset.hitTest(NSPoint(x: 50, y: 20)) } === owner.reset)
    }

    private final class Separations {
        var count = 0
    }

    private func separating(_ owner: Owner) -> Separations {
        let separations = Separations()
        owner.attachReset()
        owner.reset.prepareSeparate = { [unowned owner] in
            guard owner.available else { return nil }
            var used = false
            return { guard !used else { return false }; used = true; separations.count += 1; return true }
        }
        return separations
    }

    @Test func aCommandClickSeparates() {
        let owner = Owner()
        let separations = separating(owner)
        #expect(owner.reset.lease(.command)?() == true)
        #expect(separations.count == 1)
        #expect(owner.dispatches == 0)
    }

    @Test func aCommandShiftClickStillSeparates() {
        let owner = Owner()
        let separations = separating(owner)
        #expect(owner.reset.lease([.command, .shift])?() == true)
        #expect(separations.count == 1)
    }

    @Test func aPlainClickResets() {
        let owner = Owner()
        let separations = separating(owner)
        #expect(owner.reset.lease([])?() == true)
        #expect(owner.dispatches == 1)
        #expect(separations.count == 0)
    }

    @Test func shiftAloneResetsBecauseOnlyCommandIsRead() {
        let owner = Owner()
        _ = separating(owner)
        #expect(owner.reset.lease(.shift)?() == true)
        #expect(owner.dispatches == 1)
    }

    @Test func aSeparationCommandIsOneUse() throws {
        let owner = Owner()
        let separations = separating(owner)
        let separate = try #require(owner.reset.lease(.command))
        #expect(separate())
        #expect(!separate())
        #expect(separations.count == 1)
    }

    @Test func noCommandExistsWhileTheOwnerIsUnavailable() {
        let owner = Owner()
        _ = separating(owner)
        owner.available = false
        #expect(owner.reset.lease(.command) == nil)
        #expect(owner.reset.lease([]) == nil)
    }

    @Test func theResetTooltipCarriesTheRegistryShortcut() {
        let owner = Owner()
        owner.reset.toolTip = "Reset Tab ⌥⌘R"
        #expect(owner.reset.toolTip == "Reset Tab ⌥⌘R")
    }

    @Test func theRegionContextKeepsTheRowsMenuProvider() {
        let owner = Owner()
        owner.attachReset()
        owner.reset.makeMenu = { NSMenu(title: "Original row") }
        #expect(owner.reset.menu(for: owner.rightMouseDown())?.title == "Original row")
    }

    @Test func theBodyRegionTakesNoInput() {
        let owner = Owner()
        let body = SidebarRowBodyRegionView(frame: NSRect(x: 70, y: 10, width: 100, height: 35))
        owner.window.contentView!.addSubview(body)
        #expect(body.hitTest(NSPoint(x: 80, y: 20)) == nil)
        #expect(!body.isAccessibilityElement())
    }

    @Test func darkBodyHoverUsesTheSidebarItemBackground() {
        let owner = Owner()
        let body = SidebarRowBodyRegionView(frame: NSRect(x: 70, y: 10, width: 100, height: 35))
        owner.window.contentView!.addSubview(body)
        body.dark = true
        body.hovered = true
        #expect(components(body.layer!.backgroundColor) == [0.98, 0.984, 1, 0.1])
    }

    @Test func theSlashIsDecorative() {
        let slash = SidebarRowSlashView(frame: NSRect(x: 0, y: 0, width: 4, height: 15))
        #expect(slash.hitTest(NSPoint(x: 2, y: 7)) == nil)
        #expect(!slash.isAccessibilityElement())
    }

    @Test func theProductionSlashRenders() throws {
        let slash = SidebarRowSlashView(frame: NSRect(x: 0, y: 0, width: 4, height: 15))
        let bitmap = try #require(slash.bitmapImageRepForCachingDisplay(in: slash.bounds))
        slash.cacheDisplay(in: slash.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
    }

    @Test func theTitleStackLeavesInputToTheRow() {
        let stack = SidebarRowTitleStack(frame: NSRect(x: 38, y: 8, width: 100, height: 32))
        #expect(stack.hitTest(NSPoint(x: 50, y: 10)) == nil)
    }

    @Test func liftRaisesTheTitleSevenPoints() {
        let owner = Owner()
        owner.window.contentView!.wantsLayer = true
        let row = FlippedRow(frame: NSRect(x: 0, y: 0, width: 200, height: 35))
        row.wantsLayer = true
        owner.window.contentView!.addSubview(row)
        let stack = SidebarRowTitleStack(frame: NSRect(x: 38, y: 8, width: 100, height: 32))
        stack.wantsLayer = true
        let title = NSTextField(labelWithString: "Title")
        title.frame = NSRect(x: 0, y: 0, width: 100, height: 18)
        title.wantsLayer = true
        stack.addSubview(title)
        row.addSubview(stack)
        owner.window.contentView!.layoutSubtreeIfNeeded()
        owner.window.displayIfNeeded()
        let root = owner.window.contentView!.layer!
        let resting = title.layer!.convert(CGPoint.zero, to: root)
        stack.layer!.sublayerTransform = CATransform3DMakeTranslation(0, -7, 0)
        let lifted = title.layer!.convert(CGPoint.zero, to: root)
        #expect(root.contentsAreFlipped() == false)
        #expect(lifted.y - resting.y == 7)
    }

    @MainActor private final class Costly {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let button = SidebarRowActionButton("Archive this item")
        var prepares = 0
        var cheap = true
        var dispatches = 0

        init() {
            window.isReleasedWhenClosed = false
            button.frame = NSRect(x: 40, y: 10, width: 24, height: 24)
            button.prepareAction = { [unowned self] in prepares += 1; return { [unowned self] in dispatches += 1; return true } }
            button.isAvailable = { [unowned self] in cheap }
            button.isHidden = true
            window.contentView!.addSubview(button)
            button.refreshAvailability()
        }

        deinit { MainActor.assumeIsolated { window.close() } }
    }

    @Test func aHiddenButtonDoesNotRefresh() {
        #expect(Costly().prepares == 0)
    }

    @Test func showingRefreshesThroughTheCheapCheckWithoutPreparing() {
        let costly = Costly()
        costly.button.isHidden = false
        #expect(costly.button.isEnabled)
        #expect(costly.prepares == 0)
    }

    @Test func theCheapCheckDisablesWithoutPreparing() {
        let costly = Costly()
        costly.button.isHidden = false
        costly.cheap = false
        costly.button.refreshAvailability()
        #expect(!costly.button.isEnabled)
        #expect(!costly.button.isAccessibilityEnabled())
        #expect(costly.prepares == 0)
    }

    @Test func aPressPreparesAndRunsTheActionOnce() {
        let costly = Costly()
        costly.button.isHidden = false
        #expect(costly.button.accessibilityPerformPress())
        #expect(costly.prepares == 1)
        #expect(costly.dispatches == 1)
    }
}
