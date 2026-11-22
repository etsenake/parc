import AppKit
import Testing
@testable import ParcSidebar

@MainActor
struct SidebarRowActionButtonTestsCloseTests {
    private typealias Owner = SidebarRowActionButtonTestsSupport.Owner

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
        owner.button.sendClick()
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

    struct CloseAppearance: CustomTestStringConvertible {
        let testDescription: String
        let dark: Bool
        let alpha: Double
    }

    @Test(arguments: [
        CloseAppearance(testDescription: "Light appearance", dark: false, alpha: 0.565),
        CloseAppearance(testDescription: "Dark appearance", dark: true, alpha: 0.592),
    ])
    func theBarsCrossingIsNoDarkerThanABar(_ sample: CloseAppearance) {
        let dark = sample.dark
        let alpha = sample.alpha
        #expect(abs(closeInk(Owner().button, dark: dark).centre - alpha) < 0.01)
    }

    @Test func aDisabledCloseKeepsTheThirtyFivePercentDimming() {
        let owner = Owner()
        owner.button.isEnabled = false
        #expect(abs(closeInk(owner.button, dark: false).alpha - 0.565 * 0.35) < 0.01)
    }
}
