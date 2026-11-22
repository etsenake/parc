import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SidebarSpaceHeaderTestsHoverTests {
    private typealias Support = SidebarSpaceHeaderTestsSupport
    private typealias H = Support.H
    private typealias Header = Support.Header

    @Test func atRestTheEditButtonIsTheLastViewZeroWidthAtTheTrailingInsetAndClear() {
        let header = Header(icon: false)
        header.header.display()
        let rest = H.frames(width: 228, icon: false, titleHeight: header.titleHeight)
        #expect(!header.header.canShowHeaderButtonsIfPossible && header.header.subviews.last === header.button)
        #expect(!header.button.isHidden && header.button.alphaValue == 0)
        #expect(header.button.frame == rest.editButton && header.button.frame == NSRect(x: 214, y: 6, width: 0, height: 24))
        #expect(header.field.frame == rest.title && header.field.frame.maxX == 210)
    }

    @Test func theEditButtonIsABorderlessMomentaryEllipsis() {
        let button = Header().button
        let momentary = NSButton(frame: .zero)
        momentary.setButtonType(.momentaryChange)
        #expect(button.image?.tiffRepresentation != nil && button.image?.tiffRepresentation == Support.ellipsis?.tiffRepresentation)
        #expect(button.title == "" && !button.isBordered && button.alignment == .center)
        #expect(button.alignmentRectInsets.left == 0 && button.alignmentRectInsets.right == 0)
        #expect(button.alignmentRectInsets.top == 0 && button.alignmentRectInsets.bottom == 0)
        #expect((button.cell as? NSButtonCell)?.highlightsBy == (momentary.cell as? NSButtonCell)?.highlightsBy)
        #expect((button.cell as? NSButtonCell)?.showsStateBy == (momentary.cell as? NSButtonCell)?.showsStateBy)
    }

    @Test func theEditButtonIsGrayA11InALightThemeAimedAtItsAction() {
        let header = Header()
        #expect(Support.components(header.button.contentTintColor) == [0, 0, 0, 0.565])
        #expect(header.button.target === header.header && header.button.action == NSSelectorFromString("didClickEditButton:"))
    }

    @Test func theHeaderAndTheButtonTrackOnlyInTheKeyWindow() {
        let header = Header()
        let options = { (view: NSView) in view.trackingAreas.filter { $0.owner === view && !$0.options.contains(.cursorUpdate) }.map(\.options.rawValue) }
        #expect(options(header.header) == [0x223] && options(header.button) == [0x223] && !header.window.isKeyWindow)
    }

    @Test func hoveredWithoutTheGateTheButtonStaysHidden() {
        let header = Header(icon: false)
        header.enter(); header.runScheduled()
        #expect(header.header.isHovered && header.button.frame.width == 0 && header.button.alphaValue == 0)
    }

    @Test func theGateAloneShowsNothing() {
        let header = Header(icon: false)
        header.header.canShowHeaderButtonsIfPossible = true
        #expect(header.button.frame.width == 0 && header.button.alphaValue == 0)
    }

    @Test func hoveringShowsTheButtonATenthOfASecondLaterNotAtOnce() {
        let header = Header(icon: false)
        header.header.canShowHeaderButtonsIfPossible = true
        header.enter()
        #expect(header.header.isHovered && header.button.frame.width == 0 && header.button.alphaValue == 0)
        #expect(header.scheduled.map(\.delay) == [0.1])
        header.runScheduled()
        #expect(header.button.frame.width == 24 && header.button.alphaValue == 1)
    }

    @Test func theShownButtonSitsAtTheTrailingEdgeAndTheNameEndsFourBeforeIt() {
        let header = Header(icon: false)
        header.showButton()
        let shown = H.frames(width: 228, icon: false, titleHeight: header.titleHeight, editButtonWidth: 24)
        #expect(header.button.frame == shown.editButton && header.button.frame == NSRect(x: 190, y: 6, width: 24, height: 24))
        #expect(header.field.frame == shown.title && header.field.frame.maxX == 186 && !header.button.isHidden)
    }

    @Test func theEllipsisDraws() {
        let header = Header(icon: false)
        header.showButton()
        #expect(Support.pixels(header.button).map { !$0.allSatisfy { $0 == 0 } } == true)
    }

    @Test func hoverOutIsDispatchedNotAppliedInTheExitMessage() {
        let header = Header(icon: false)
        header.showButton()
        header.exit()
        #expect(header.button.frame.width == 24 && header.button.alphaValue == 1)
        #expect(header.scheduled.map(\.delay) == [0])
    }

    @Test func withoutACustomIconTheWidthSnapsToZeroAndTheAlphaFadesOut() {
        let header = Header(icon: false)
        header.showButton()
        header.exit(); header.runScheduled()
        #expect(header.button.frame.width == 0 && header.button.alphaValue == 0 && Support.isEditFade(header.opacityFade))
        #expect(!header.button.isHidden && header.field.frame.maxX == 210)
    }

    @Test func aHoverShorterThanATenthNeverShowsTheButton() {
        let header = Header(icon: false)
        header.header.canShowHeaderButtonsIfPossible = true
        header.enter(); header.exit()
        var flashed = false
        header.runScheduled { flashed = flashed || header.button.frame.width > 0 || header.button.alphaValue > 0 }
        #expect(!flashed && !header.header.isHovered)
    }

    @Test func withAnIconTheButtonShowsAtFullAlphaWithItsWidthWhenTheDelayEnds() {
        let header = Header()
        header.showButton()
        #expect(header.button.frame.width == 24 && header.button.alphaValue == 1)
        #expect(header.button.frame == H.frames(width: 228, icon: true, titleHeight: header.titleHeight, editButtonWidth: 24).editButton)
        #expect(header.field.frame.maxX == 186)
    }

    @Test func withAnIconTheButtonHidesWithoutAFade() {
        let header = Header()
        header.showButton()
        header.exit(); header.runScheduled()
        #expect(header.button.frame.width == 0 && header.button.alphaValue == 0 && header.opacityFade == nil)
    }

    @Test func anUnhoveredButtonIsClearWithSixPointContinuousCorners() {
        let header = Header()
        header.showButton()
        #expect(header.fill() == [0, 0, 0, 0])
        #expect(header.button.layer?.cornerRadius == 6 && header.button.layer?.cornerCurve == .continuous && header.button.layer?.borderWidth == 0)
    }

    @Test func aHoveredButtonFillsWithGrayA4AndKeepsItsTint() {
        let header = Header()
        header.showButton()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        #expect(header.button.isHovered && header.header.isHovered && header.fill() == [0, 0, 0, 0.071])
        #expect(Support.components(header.button.contentTintColor) == [0, 0, 0, 0.565])
    }

    @Test func aHoveredButtonInADarkThemeUsesWhite() {
        let header = Header()
        header.showButton()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        header.header.applyStyle(dark: true, tint: nil)
        #expect(header.fill() == [1, 1, 1, 0.077] && Support.components(header.button.contentTintColor) == [1, 1, 1, 0.592])
    }

    @Test func aDisabledButtonKeepsTheClearFill() {
        let header = Header()
        header.showButton()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        header.button.isEnabled = false
        #expect(header.fill() == [0, 0, 0, 0])
    }

    @Test func leavingTheButtonClearsItsFillAndTheHeaderStaysHovered() {
        let header = Header()
        header.showButton()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        header.button.mouseExited(with: header.crossing(.mouseExited))
        #expect(!header.button.isHovered && header.header.isHovered && header.fill() == [0, 0, 0, 0])
    }
}
