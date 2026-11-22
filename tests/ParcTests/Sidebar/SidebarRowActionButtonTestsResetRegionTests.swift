import AppKit
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct SidebarRowActionButtonTestsResetRegionTests {
    private typealias Owner = SidebarRowActionButtonTestsSupport.Owner

    private func withoutModifiers<T>(_ owner: Owner, _ body: () -> T) -> T {
        owner.reset.modifierFlags = { [] }
        return body()
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
        owner.reset.sendClick()
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
        withoutModifiers(owner) { owner.reset.mouseEntered(with: owner.rightMouseDown()) }
        #expect(owner.reset.hoverSubtitle == .reset)
    }

    private func hovered(_ owner: Owner) {
        owner.attachReset()
        withoutModifiers(owner) { owner.reset.mouseEntered(with: owner.rightMouseDown()) }
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

    @Test func resetNamesThePinnedURLAction() {
        #expect(SidebarRowHoverSubtitle.reset.text == "Back to Pinned URL")
    }

    @Test func separateNamesThePinnedTabAction() {
        #expect(SidebarRowHoverSubtitle.resetAndSeparate.text == "Separate From Pinned Tab")
    }

    @Test func aHoveredRegionUsesTheSidebarItemBackground() {
        let owner = Owner()
        hovered(owner)
        #expect(SidebarRowActionButtonTestsSupport.components(owner.reset.layer!.backgroundColor) == [0.055, 0.059, 0.063, 0.05])
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
        owner.reset.modifierFlags = { .command }
        #expect(owner.reset.hitTest(NSPoint(x: 50, y: 20)) == nil)
    }

    @Test func anAvailableResetRegionTakesAPlainClick() {
        let owner = Owner()
        owner.attachReset()
        #expect(withoutModifiers(owner) { owner.reset.hitTest(NSPoint(x: 50, y: 20)) } === owner.reset)
    }
}
