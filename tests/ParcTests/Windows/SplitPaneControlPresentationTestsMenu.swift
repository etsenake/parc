import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcKit

@MainActor
struct SplitPaneControlPresentationTestsMenu {
    private typealias TrackingEvent = SplitPaneControlPresentationTestsSupport.TrackingEvent
    private typealias ControlFixture = SplitPaneControlPresentationTestsSupport.ControlFixture

    private static func near(_ value: CGFloat?, _ expected: CGFloat) -> Bool { abs((value ?? -1) - expected) < 0.00001 }
    private static func near(_ value: Float, _ expected: Float) -> Bool { abs(value - expected) < 0.00001 }

    @Test func theTopBarSharesItsParentDimensions() {
        #expect(PaneTopBarLayout.height == 32)
        #expect(PaneTopBarLayout.horizontalInset == 5)
    }

    @Test func aSymbolIsCentredIndependentlyOfTheContentInset() {
        #expect(PaneTopBarLayout.frame(x: 15, width: 32, height: 24) == NSRect(x: 15, y: 4, width: 32, height: 24))
    }

    @Test func aTitleCentresInTheSameParentRow() {
        #expect(PaneTopBarLayout.frame(x: 13, width: 100, height: 26).midY == 16)
    }

    @Test func theMenuControlHasTheOriginalSymbolSurface() {
        let fixture = ControlFixture()
        #expect(fixture.control.intrinsicContentSize == NSSize(width: 32, height: 24))
    }

    @Test func theBackgroundIsContinuousAndRounded() {
        let fixture = ControlFixture()
        #expect(fixture.background.frame == fixture.control.bounds)
        #expect(fixture.background.cornerRadius == 6)
        #expect(fixture.background.cornerCurve == .continuous)
    }

    @Test func theFocusRingFollowsTheSymbolSurface() {
        let fixture = ControlFixture()
        #expect(fixture.control.focusRingMaskBounds == fixture.control.bounds)
    }

    @Test func theMenuControlKeepsItsIdentityTooltipAndHelp() {
        let control = ControlFixture().control
        #expect(control.accessibilityLabel() == "Split View Menu")
        #expect(control.parcTooltip == TooltipConfiguration("Split View Options"))
        #expect(control.toolTip == nil)
        #expect(control.accessibilityHelp() == "Split View Options")
        #expect(control.accessibilityRole() == .button)
    }

    @Test func theGlyphTakesNoInputAndHasNoAccessibilityIdentity() {
        let fixture = ControlFixture()
        #expect(fixture.glyph.hitTest(.zero) == nil)
        #expect(!fixture.glyph.isAccessibilityElement())
    }

    @Test func theButtonOwnsTheGlyphHit() {
        let fixture = ControlFixture()
        #expect(fixture.control.hitTest(NSPoint(x: 30, y: 30)) === fixture.control)
    }

    @Test func theSystemCellAddsNoUnrelatedPressFill() {
        #expect((ControlFixture().control.cell as? NSButtonCell)?.highlightsBy == [])
    }

    @Test func oneDecorationTrackingAreaSitsAlongsideAppKitsOwn() {
        #expect(ControlFixture().ownedAreas.count == 1)
    }

    @Test func aRetiredTrackingEventCannotStartHover() {
        let fixture = ControlFixture()
        let old = fixture.hoverEvent
        fixture.control.updateTrackingAreas()
        fixture.control.mouseEntered(with: old)
        #expect(!fixture.control.isHovered)
    }

    @Test func restInLightIsSoftInkWithNoSurface() {
        let fixture = ControlFixture()
        #expect(Self.near(fixture.glyph.contentTintColor?.alphaComponent, 0.55))
        #expect(fixture.background.opacity == 0)
    }

    @Test func lightHoverRaisesTheSurfaceToFivePercent() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        #expect(fixture.control.isHovered)
        #expect(Self.near(fixture.background.opacity, 0.05))
    }

    @Test(arguments: [false, true])
    func hoverFadesOnlyWhenMotionIsAllowed(reduceMotion: Bool) {
        let fixture = ControlFixture(reduceMotion: reduceMotion)
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        #expect(fixture.background.animation(forKey: "split-control-opacity")?.duration == (reduceMotion ? nil : 0.18))
    }

    @Test func aNativePressTakesPrecedenceOverHover() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.press(true)
        #expect(fixture.control.isPressed)
        #expect(Self.near(fixture.background.opacity, 0.09))
    }

    @Test(arguments: [false, true])
    func pressingFadesOnlyWhenMotionIsAllowed(reduceMotion: Bool) {
        let fixture = ControlFixture(reduceMotion: reduceMotion)
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.press(true)
        #expect(fixture.background.animation(forKey: "split-control-opacity")?.duration == (reduceMotion ? nil : 0.16))
    }

    @Test func darkEnabledPressRaisesInkAndSurface() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.press(true)
        fixture.setDark(true)
        #expect(Self.near(fixture.glyph.contentTintColor?.alphaComponent, 0.675))
        #expect(Self.near(fixture.background.opacity, 0.13))
    }

    @Test func darkInkIsWhite() {
        let fixture = ControlFixture()
        fixture.setDark(true)
        #expect(NSColor(cgColor: fixture.background.backgroundColor!)?.usingColorSpace(.sRGB)?.redComponent == 1)
    }

    @Test func aNativeReleaseReturnsToDarkHover() {
        let fixture = ControlFixture()
        fixture.setDark(true)
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.press(true)
        fixture.press(false)
        #expect(!fixture.control.isPressed)
        #expect(Self.near(fixture.background.opacity, 0.09))
    }

    @Test func aRetiredExitCannotClearCurrentHover() {
        let fixture = ControlFixture()
        let old = fixture.hoverEvent
        fixture.control.updateTrackingAreas()
        let current = fixture.hoverEvent
        fixture.control.mouseEntered(with: current)
        fixture.control.mouseExited(with: old)
        #expect(fixture.control.isHovered)
    }

    @Test func theCurrentExitReturnsToRest() {
        let fixture = ControlFixture()
        let hover = fixture.hoverEvent
        fixture.control.mouseEntered(with: hover)
        fixture.control.mouseExited(with: hover)
        #expect(!fixture.control.isHovered)
        #expect(fixture.background.opacity == 0)
    }

    @Test func aClickReachesTheCallback() {
        let fixture = ControlFixture()
        fixture.control.sendClick()
        #expect(fixture.actions == 1)
    }

    @Test func aDisabledControlRefusesClicks() {
        let fixture = ControlFixture()
        fixture.control.isEnabled = false
        fixture.control.sendClick()
        #expect(fixture.actions == 0)
    }

    @Test func aDisabledControlRefusesHoverDecoration() {
        let fixture = ControlFixture()
        fixture.control.isEnabled = false
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        #expect(!fixture.control.isHovered && !fixture.control.isPressed)
        #expect(fixture.background.opacity == 0)
    }

    @Test func aDisabledControlUsesTheDisabledInk() {
        let fixture = ControlFixture()
        fixture.control.isEnabled = false
        #expect(fixture.glyph.contentTintColor?.alphaComponent == 0.25)
    }

    @Test func aControlInAnInactiveWindowRefusesClicks() {
        let fixture = ControlFixture()
        let hover = fixture.hoverEvent
        fixture.control.mouseEntered(with: hover)
        fixture.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        fixture.control.sendClick()
        #expect(fixture.actions == 0)
    }

    @Test func losingKeyClearsHoverDecoration() {
        let fixture = ControlFixture()
        let hover = fixture.hoverEvent
        fixture.control.mouseEntered(with: hover)
        fixture.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        fixture.control.mouseEntered(with: hover)
        #expect(!fixture.control.isHovered)
        #expect(fixture.background.animationKeys()?.isEmpty != false)
    }

    @Test func aHiddenControlCannotInvoke() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.control.isHidden = true
        fixture.control.viewDidHide()
        fixture.control.sendClick()
        #expect(fixture.actions == 0)
    }

    @Test func hidingTheControlClearsItsInteractionState() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.control.isHidden = true
        fixture.control.viewDidHide()
        #expect(!fixture.control.isHovered && !fixture.control.isPressed)
    }

    @Test func anAppearanceOptionsChangeRetiresInFlightMotion() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(fixture.background.animationKeys()?.isEmpty != false)
    }

    @Test func detachingTheControlRevokesClickAdmission() {
        let fixture = ControlFixture()
        let hover = fixture.hoverEvent
        fixture.control.mouseEntered(with: hover)
        fixture.control.removeFromSuperview()
        fixture.control.sendClick()
        #expect(fixture.actions == 0)
    }

    @Test func detachingTheControlRetiresItsTracking() {
        let fixture = ControlFixture()
        let hover = fixture.hoverEvent
        fixture.control.mouseEntered(with: hover)
        fixture.control.removeFromSuperview()
        fixture.control.mouseEntered(with: hover)
        #expect(!fixture.control.isHovered)
        #expect(fixture.ownedAreas.isEmpty)
    }

    @Test func anEventWithoutAnAttributedAreaCannotStartDecoration() {
        let fixture = ControlFixture()
        fixture.control.removeFromSuperview()
        fixture.host.addSubview(fixture.control)
        fixture.control.mouseEntered(with: TrackingEvent())
        #expect(!fixture.control.isHovered)
    }

    @Test func oldWindowTrackingDoesNotReviveAfterAttach() {
        let fixture = ControlFixture()
        let old = fixture.hoverEvent
        fixture.control.removeFromSuperview()
        fixture.host.addSubview(fixture.control)
        fixture.control.updateTrackingAreas()
        fixture.control.mouseEntered(with: old)
        #expect(!fixture.control.isHovered)
    }

    @Test func theCloseControlSharesStyleWithADistinctActionIdentity() {
        let fixture = ControlFixture()
        let close = SplitPaneControl(.close)
        #expect(close.accessibilityLabel() == "Close Split View Pane")
        #expect(close.parcTooltip?.label == "Remove Tab from Split View")
        #expect(close.intrinsicContentSize == fixture.control.intrinsicContentSize)
    }

    @Test(arguments: [0, 1])
    func eachSplitPanesCloseRetiresThatPage(_ index: Int) {
        let panes = [UUID(), UUID()]
        #expect(SplitPaneCloseAdmission.accepts(tabID: panes[index], selected: panes))
    }

    @Test func closeCannotRetireAPageOutsideTheSplit() {
        #expect(!SplitPaneCloseAdmission.accepts(tabID: UUID(), selected: [UUID(), UUID()]))
    }

    @Test func closeCannotRetireASinglePage() {
        let pane = UUID()
        #expect(!SplitPaneCloseAdmission.accepts(tabID: pane, selected: [pane]))
    }

    @Test func closeCannotRetireAPeek() {
        let panes = [UUID(), UUID()]
        #expect(!SplitPaneCloseAdmission.accepts(tabID: panes[0], selected: panes, isPeek: true))
    }

    @Test func releasedControlsAreNotRetainedByObserversOrLayers() {
        let fixture = ControlFixture()
        weak var retired: SplitPaneControl?
        autoreleasepool {
            let temporary = SplitPaneControl(.menu)
            retired = temporary
            fixture.host.addSubview(temporary)
            temporary.removeFromSuperview()
        }
        #expect(retired == nil)
    }
}
