import AppKit
import SwiftUI
import Testing
@testable import Parc

@MainActor
struct SidebarHeaderGlyphTestsRevealTests {
    private typealias Support = SidebarHeaderGlyphTestsSupport
    @Test func thePillHasTwelvePointCorners() {
        #expect(SidebarAddressPillView.cornerRadius == 12)
    }

    @Test func thePillHoverLastsOneHundredTwentyMilliseconds() {
        #expect(SidebarAddressPillView.hoverDuration == 0.12)
    }

    private func p3(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let c = color.usingColorSpace(.displayP3)!
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    @Test func sidebarItemBackgroundLightAndItsHoveredAlpha() {
        let rest = p3(SidebarAddressPillView.fill(dark: false, hovered: false))
        #expect(Support.near(rest.0, 0.055) && Support.near(rest.1, 0.059) && Support.near(rest.2, 0.063) && Support.near(rest.3, 0.05))
        #expect(Support.near(p3(SidebarAddressPillView.fill(dark: false, hovered: true)).3, 0.1))
    }

    @Test func sidebarItemBackgroundDarkAndItsHoveredAlpha() {
        let rest = p3(SidebarAddressPillView.fill(dark: true, hovered: false))
        #expect(Support.near(rest.0, 0.98) && Support.near(rest.2, 1) && Support.near(rest.3, 0.1))
        #expect(Support.near(p3(SidebarAddressPillView.fill(dark: true, hovered: true)).3, 0.15))
    }

    @Test func thePillIsAContinuousTwelvePointMask() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        #expect(pill.layer?.cornerRadius == 12)
        #expect(pill.layer?.cornerCurve == .continuous)
        #expect(pill.layer?.masksToBounds == true)
    }

    struct PillFill: CustomTestStringConvertible {
        let testDescription: String
        let hovered: Bool
        let dark: Bool
    }

    @Test(arguments: [
        PillFill(testDescription: "Light idle", hovered: false, dark: false),
        PillFill(testDescription: "Light hovered", hovered: true, dark: false),
        PillFill(testDescription: "Dark hovered", hovered: true, dark: true),
    ])
    func thePillFillsRestHoverAndDark(_ sample: PillFill) {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        if sample.hovered { pill.setHovered(true) }
        if sample.dark { pill.dark = true }
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: sample.dark, hovered: sample.hovered).cgColor)
    }

    @Test func theSurfaceTakesNoClicks() {
        #expect(SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36)).hitTest(NSPoint(x: 10, y: 10)) == nil)
    }

    struct RevealState: CustomTestStringConvertible {
        let testDescription: String
        let hovered: Bool
        let menu: Bool
        let anchored: Bool
        let voiceOver: Bool
    }

    @Test(arguments: [
        RevealState(testDescription: "Pointer away, no menu, unanchored, VoiceOver off", hovered: false, menu: false, anchored: false, voiceOver: false),
        RevealState(testDescription: "Pointer away, no menu, unanchored, VoiceOver on", hovered: false, menu: false, anchored: false, voiceOver: true),
        RevealState(testDescription: "Pointer away, no menu, anchored, VoiceOver off", hovered: false, menu: false, anchored: true, voiceOver: false),
        RevealState(testDescription: "Pointer away, no menu, anchored, VoiceOver on", hovered: false, menu: false, anchored: true, voiceOver: true),
        RevealState(testDescription: "Pointer away, menu open, unanchored, VoiceOver off", hovered: false, menu: true, anchored: false, voiceOver: false),
        RevealState(testDescription: "Pointer away, menu open, unanchored, VoiceOver on", hovered: false, menu: true, anchored: false, voiceOver: true),
        RevealState(testDescription: "Pointer away, menu open, anchored, VoiceOver off", hovered: false, menu: true, anchored: true, voiceOver: false),
        RevealState(testDescription: "Pointer away, menu open, anchored, VoiceOver on", hovered: false, menu: true, anchored: true, voiceOver: true),
        RevealState(testDescription: "Hovered, no menu, unanchored, VoiceOver off", hovered: true, menu: false, anchored: false, voiceOver: false),
        RevealState(testDescription: "Hovered, no menu, unanchored, VoiceOver on", hovered: true, menu: false, anchored: false, voiceOver: true),
        RevealState(testDescription: "Hovered, no menu, anchored, VoiceOver off", hovered: true, menu: false, anchored: true, voiceOver: false),
        RevealState(testDescription: "Hovered, no menu, anchored, VoiceOver on", hovered: true, menu: false, anchored: true, voiceOver: true),
        RevealState(testDescription: "Hovered, menu open, unanchored, VoiceOver off", hovered: true, menu: true, anchored: false, voiceOver: false),
        RevealState(testDescription: "Hovered, menu open, unanchored, VoiceOver on", hovered: true, menu: true, anchored: false, voiceOver: true),
        RevealState(testDescription: "Hovered, menu open, anchored, VoiceOver off", hovered: true, menu: true, anchored: true, voiceOver: false),
        RevealState(testDescription: "Hovered, menu open, anchored, VoiceOver on", hovered: true, menu: true, anchored: true, voiceOver: true),
    ])
    func theRevealPredicateShowsTheButtonsForHoverMenuUnanchoredOrVoiceOver(_ sample: RevealState) {
        let hovered = sample.hovered
        let menu = sample.menu
        let anchored = sample.anchored
        let voiceOver = sample.voiceOver
        #expect(SidebarAddressButtonsReveal.revealed(sidebarHovered: hovered, showingMenu: menu, anchored: anchored, voiceOverRunning: voiceOver)
                == (hovered || menu || !anchored || voiceOver))
    }

    struct PopupLoading: CustomTestStringConvertible {
        let testDescription: String
        let attached: Bool
        let visible: Bool
        let showsPage: Bool
        let loading: Bool
    }

    @Test(arguments: [
        PopupLoading(testDescription: "Unattached hidden page", attached: false, visible: false, showsPage: true, loading: true),
        PopupLoading(testDescription: "Attached page", attached: true, visible: false, showsPage: true, loading: false),
        PopupLoading(testDescription: "Visible page", attached: false, visible: true, showsPage: true, loading: false),
        PopupLoading(testDescription: "No page", attached: false, visible: false, showsPage: false, loading: false),
    ])
    func anExtensionPopupLoadingIsOnlyAnUnattachedUnseenWindowShowingItsPage(_ sample: PopupLoading) {
        let attached = sample.attached
        let visible = sample.visible
        let showsPage = sample.showsPage
        let loading = sample.loading
        #expect(SidebarAddressButtonsReveal.extensionPopupLoading(attached: attached, visible: visible, showsPage: showsPage) == loading)
    }

    struct SiteControlVisibility: CustomTestStringConvertible {
        let testDescription: String
        let revealed: Bool
        let quote: Bool
        let shows: Bool
    }

    @Test(arguments: [
        SiteControlVisibility(testDescription: "Concealed", revealed: false, quote: false, shows: false),
        SiteControlVisibility(testDescription: "Quote link", revealed: false, quote: true, shows: true),
        SiteControlVisibility(testDescription: "Revealed", revealed: true, quote: false, shows: true),
    ])
    func siteControlCenterShowsWhenRevealedOrAQuoteLinkKeepsIt(_ sample: SiteControlVisibility) {
        let revealed = sample.revealed
        let quote = sample.quote
        let shows = sample.shows
        #expect(SidebarAddressButtonsReveal.showsSiteControlCenter(revealed: revealed, copyQuoteLink: quote) == shows)
    }

    @Test func theFadeIsFifteenHundredthsOfASecond() {
        #expect(SidebarAddressButtonsReveal.fadeDuration == 0.15)
    }

    @Test func hidingAWindowlessButtonClearsItsOpacityImmediately() {
        let button = NSView(frame: NSRect(x: 0, y: 0, width: 25, height: 28))
        SidebarAddressButtonsReveal.apply(false, to: button, animated: true)
        #expect(button.alphaValue == 0)
    }

    @Test func hidingAWindowlessButtonKeepsItInTheTree() {
        let button = NSView(frame: NSRect(x: 0, y: 0, width: 25, height: 28))
        SidebarAddressButtonsReveal.apply(false, to: button, animated: true)
        #expect(!button.isHidden)
    }

    @Test func revealRestoresFullOpacity() {
        let button = NSView(frame: NSRect(x: 0, y: 0, width: 25, height: 28))
        SidebarAddressButtonsReveal.apply(false, to: button, animated: true)
        SidebarAddressButtonsReveal.apply(true, to: button, animated: true)
        #expect(button.alphaValue == 1)
    }
}
