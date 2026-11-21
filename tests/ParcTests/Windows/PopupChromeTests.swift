import AppKit
import Testing
@testable import Parc

@MainActor private final class Chrome {
    let view = PopupChromeView(frame: NSRect(x: 0, y: 0, width: 400, height: 47))
    let buttons: [NSButton]
    let back: NSButton, copy: SidebarRowActionButton, extensions: SidebarRowActionButton
    let address: ActionButton
    let label: PopupAddressLabel
    let background: PopupAddressBackground

    init() {
        _ = NSApplication.shared
        buttons = view.subviews.compactMap { $0 as? NSButton }
        back = buttons.first { $0.title == "Back" }!
        address = view.subviews.compactMap { $0 as? ActionButton }.first!
        label = view.subviews.compactMap { $0 as? PopupAddressLabel }.first!
        copy = buttons.first { $0.accessibilityLabel() == "Copy URL" } as! SidebarRowActionButton
        extensions = buttons.first { $0.accessibilityLabel() == "Extensions" } as! SidebarRowActionButton
        background = view.subviews.compactMap { $0 as? PopupAddressBackground }.first!
    }

    func idle() {
        view.update(url: nil, canGoBack: false, loading: false)
        view.layoutSubtreeIfNeeded()
    }

    func loaded() {
        view.appearance = NSAppearance(named: .aqua)
        view.update(url: URL(string: "https://example.com"), canGoBack: true, loading: true)
        view.updateExtensions(available: true)
        view.layoutSubtreeIfNeeded()
    }

    var pointer: NSPoint { NSPoint(x: address.frame.minX + 1, y: address.frame.midY) }
    var backgroundAlpha: CGFloat { NSColor(cgColor: background.layer!.backgroundColor!)!.alphaComponent }
}

struct PopupChromeTests {
    @MainActor @Test func aPopupHasNoForwardOrRefreshButton() {
        let c = Chrome()
        let names = c.buttons.flatMap { [$0.title, $0.accessibilityLabel() ?? ""] }
        #expect(!names.contains("Forward"))
        #expect(!names.contains("Refresh the Page"))
    }

    @MainActor @Test func copyAndExtensionsTooltipsAnchorBelow() {
        let c = Chrome()
        #expect(c.copy.parcTooltip?.label == "Copy URL")
        #expect(c.copy.parcTooltip?.anchor == .bottom)
        #expect(c.extensions.parcTooltip?.label == "Extensions")
        #expect(c.extensions.parcTooltip?.anchor == .bottom)
    }

    @MainActor @Test func theBackIconIsSixteenPoints() {
        let c = Chrome()
        #expect(c.back.image?.size == NSSize(width: 16, height: 16))
    }

    @MainActor @Test func withNoPageTheBackCopyAndExtensionsControlsAreHidden() {
        let c = Chrome()
        c.idle()
        #expect(c.back.isHidden)
        #expect(c.copy.isHidden)
        #expect(c.extensions.isHidden)
    }

    @MainActor @Test func withNoPageTheAddressStartsAtSeventyThreeInThirteenPointText() {
        let c = Chrome()
        c.idle()
        #expect(c.address.frame.minX == 73)
        #expect(c.label.font?.pointSize == 13)
    }

    @MainActor @Test func theAddressBackgroundMatchesTheAddressAndPassesClicksThrough() {
        let c = Chrome()
        c.idle()
        #expect(c.background.frame == c.address.frame)
        #expect(c.background.hitTest(NSPoint(x: 1, y: 1)) == nil)
        #expect(c.background.layer?.cornerRadius == 5)
        #expect(c.background.layer?.cornerCurve == .continuous)
    }

    @MainActor @Test func theLightBackgroundColor() {
        let c = Chrome()
        c.background.update(dark: false, hovered: false)
        let light = NSColor(cgColor: c.background.layer!.backgroundColor!)!.usingColorSpace(.displayP3)!
        #expect(abs(light.redComponent - 0.055) < 0.001)
        #expect(abs(light.alphaComponent - 0.06) < 0.001)
    }

    @MainActor @Test func theDarkHoverBackgroundColor() {
        let c = Chrome()
        c.background.update(dark: true, hovered: true)
        let darkHover = NSColor(cgColor: c.background.layer!.backgroundColor!)!.usingColorSpace(.displayP3)!
        #expect(abs(darkHover.greenComponent - 0.984) < 0.001)
        #expect(abs(darkHover.alphaComponent - 0.15) < 0.001)
    }

    @MainActor @Test func hoveringTheAddressBrightensItsBackground() {
        let c = Chrome()
        c.idle()
        c.view.appearance = NSAppearance(named: .aqua)
        c.view.reconcileAddressHover(pointer: c.pointer, active: true, visible: true)
        #expect(abs(c.backgroundAlpha - 0.10) < 0.001)
    }

    @MainActor @Test func aLoadedPopupShowsBackAndShrinksTheAddressToElevenPointText() {
        let c = Chrome()
        c.loaded()
        #expect(!c.back.isHidden)
        #expect(c.back.isEnabled)
        #expect(c.back.frame == NSRect(x: 70, y: 8, width: 31, height: 31))
        #expect(c.address.frame == NSRect(x: 105, y: 8, width: 291, height: 31))
        #expect(c.label.font?.pointSize == 11)
        #expect(c.label.frame.minX == 167)
        #expect(c.label.frame.maxX == 334)
        #expect(c.label.hitTest(.zero) == nil)
    }

    @MainActor @Test func aLoadedPopupShowsCopyAndExtensionsAtTheirFrames() {
        let c = Chrome()
        c.loaded()
        #expect(!c.copy.isHidden)
        #expect(c.copy.frame == NSRect(x: 369, y: 12, width: 23, height: 23))
        #expect(!c.extensions.isHidden)
        #expect(c.extensions.frame == NSRect(x: 338, y: 12, width: 23, height: 23))
        #expect(c.view.pageControlsAnchor === c.extensions)
    }

    @MainActor @Test func theCopyButtonRunsTheCopyAction() {
        let c = Chrome()
        c.loaded()
        var copied = false
        c.view.prepareCopy = { { copied = true; return true } }
        #expect(c.copy.prepareAction?()?() == true)
        #expect(copied)
    }

    @MainActor @Test func theExtensionsButtonOpensExtensions() {
        let c = Chrome()
        c.loaded()
        var opened = false
        c.view.prepareExtensions = { { opened = true; return true } }
        #expect(c.extensions.prepareAction?()?() == true)
        #expect(opened)
    }

    @MainActor @Test func theAddressOffersASiteControlCenterAccessibilityAction() {
        let c = Chrome()
        c.loaded()
        c.view.prepareSiteControls = { { true } }
        #expect(c.address.accessibilityCustomActions()?.contains { $0.name == "Site Control Center" } == true)
    }

    @MainActor @Test func aPointerTheLayoutLeftBehindNoLongerHoversTheAddress() {
        let c = Chrome()
        c.idle()
        let pointer = c.pointer
        c.loaded()
        c.view.reconcileAddressHover(pointer: pointer, active: true, visible: true)
        #expect(abs(c.backgroundAlpha - 0.06) < 0.001)
    }

    @MainActor @Test func goingBackToNoPageHidesTheControlsAgainAndAnchorsToTheAddress() {
        let c = Chrome()
        c.loaded()
        c.view.update(url: nil, canGoBack: false, loading: false)
        c.view.updateExtensions(available: false)
        c.view.layoutSubtreeIfNeeded()
        #expect(c.back.isHidden)
        #expect(c.copy.isHidden)
        #expect(c.extensions.isHidden)
        #expect(c.address.frame.minX == 73)
        #expect(c.label.font?.pointSize == 13)
        #expect(c.view.pageControlsAnchor === c.address)
    }
}
