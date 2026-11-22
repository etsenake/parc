import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SpaceManagerCardTestsClearTests {
    private typealias Cards = SpaceManagerCardTestsSupport.Cards

    @Test func aCardHasNoNewTabRow() {
        let cards = Cards()
        #expect(!sidebarDescendants(cards.sidebar).contains { $0 is SidebarNewTabRow })
    }

    @Test func theCardsClearIsAnArrowAndLabelButton() {
        let clear = Cards().clear
        #expect(clear.title == "Clear")
        #expect(clear.isEnabled)
        #expect(clear.font == NSFont.systemFont(ofSize: 10, weight: .semibold))
        #expect(clear.image != nil)
    }

    @Test func aCardShowsClearWithoutThePointerOverIt() {
        let clear = Cards().clear
        #expect(!clear.isHidden)
        #expect(clear.alphaValue == 1)
    }

    @Test func theCardDividerHasNoSeparateSeparatorRow() {
        let clear = Cards().clear
        #expect(!clear.superview!.subviews.contains { $0 is NSBox })
    }

    @Test func theBorderRunsFromTheCellsInsetToEightBeforeClearOnClearsRow() {
        let cards = Cards()
        let clear = cards.clear
        let section = clear.superview!
        let line = section.subviews.compactMap { $0 as? SidebarHairline }.first!
        let thickness = SidebarChromeLayout.sectionDividerThickness(scale: cards.window.backingScaleFactor)
        #expect(line.frame.height == thickness)
        #expect(abs(line.frame.midY - clear.frame.midY) <= thickness / 2)
        #expect(line.frame.maxX == clear.frame.minX - SidebarChromeLayout.sectionDividerSpacing)
        #expect(line.frame.minX == SidebarChromeLayout.sectionDividerInset)
    }

    @Test func theCardsClearReachesItsOwnSpacesHandler() {
        let cards = Cards()
        let clear = cards.clear
        clear.sendAction(clear.action, to: clear.target)
        #expect(cards.cleared == [cards.first.id])
    }

    private func revealEvent(_ cards: Cards) -> SidebarAreaEvent {
        cards.sidebar.updateTrackingAreas()
        let event = SidebarAreaEvent()
        event.area = cards.sidebar.trackingAreas.first { $0.owner === cards.sidebar && $0.options.contains(.activeInActiveApp) }
        return event
    }

    private func rgba(_ color: NSColor?) -> [CGFloat] {
        let c = color!.usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 100).rounded() / 100 }
    }

    private func resting(_ color: NSColor?) -> Bool {
        let v = rgba(color)
        return v[3] == 0.3 && (v[0] == 0 || v[0] == 1) && v[0] == v[1] && v[1] == v[2]
    }

    private func hovered(_ color: NSColor?) -> Bool { [0.8, 0.9].contains(rgba(color)[3]) }

    @Test func aRestingCardClearIsForegroundTertiary() {
        #expect(resting(Cards().clear.contentTintColor))
    }

    @Test func hoveringACardsClearTintsItForegroundPrimary() {
        let cards = Cards()
        cards.sidebar.mouseEntered(with: revealEvent(cards))
        let clear = cards.clear
        clear.mouseEntered(with: SidebarAreaEvent())
        #expect(clear.hovered)
        #expect(hovered(clear.contentTintColor))
    }

    @Test func leavingRestoresTheRestingTint() {
        let cards = Cards()
        cards.sidebar.mouseEntered(with: revealEvent(cards))
        let clear = cards.clear
        let event = SidebarAreaEvent()
        clear.mouseEntered(with: event)
        clear.mouseExited(with: event)
        #expect(!clear.hovered)
        #expect(resting(clear.contentTintColor))
    }

    @Test func theCardSidebarTracksThePointerEnteringIt() {
        let cards = Cards()
        #expect(revealEvent(cards).area != nil)
    }

    @Test func withNothingToClearTheCardsClearIsDisabled() {
        let cards = Cards()
        let reveal = revealEvent(cards)
        cards.clearable = false
        cards.sidebar.mouseEntered(with: reveal)
        #expect(!cards.clear.isEnabled)
    }

    @Test func anotherTrackingAreasEntryDoesNotRereadClear() {
        let cards = Cards()
        let reveal = revealEvent(cards)
        cards.clearable = false
        cards.sidebar.mouseEntered(with: reveal)
        cards.clearable = true
        cards.sidebar.mouseEntered(with: SidebarAreaEvent())
        #expect(!cards.clear.isEnabled)
    }

    @Test func clearReenablesOnceATodayPageIsClearableAgain() {
        let cards = Cards()
        let reveal = revealEvent(cards)
        cards.clearable = false
        cards.sidebar.mouseEntered(with: reveal)
        cards.clearable = true
        cards.sidebar.mouseEntered(with: reveal)
        #expect(cards.clear.isEnabled)
    }

    private func becomeKey(_ cards: Cards) {
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: cards.window)
    }

    @Test func theWindowBecomingKeyDisablesAClearWithNothingToClear() {
        let cards = Cards()
        cards.clearable = false
        becomeKey(cards)
        #expect(!cards.clear.isEnabled)
    }

    @Test func enteringClearReenablesAndHoversItAtOnce() {
        let cards = Cards()
        cards.clearable = false
        becomeKey(cards)
        cards.clearable = true
        cards.clear.mouseEntered(with: SidebarAreaEvent())
        #expect(cards.clear.isEnabled)
        #expect(cards.clear.hovered)
        #expect(hovered(cards.clear.contentTintColor))
    }

    @Test func disablingAHoveredClearDropsItsForegroundPrimaryTint() {
        let cards = Cards()
        cards.clear.mouseEntered(with: SidebarAreaEvent())
        cards.clearable = false
        becomeKey(cards)
        #expect(!cards.clear.isEnabled)
        #expect(!cards.clear.hovered)
        #expect(resting(cards.clear.contentTintColor))
    }

    @Test func enteringAClearWithNothingToClearShowsNoHover() {
        let cards = Cards()
        cards.clearable = false
        becomeKey(cards)
        cards.clear.mouseEntered(with: SidebarAreaEvent())
        #expect(!cards.clear.isEnabled)
        #expect(!cards.clear.hovered)
    }

    @Test func afterAReleaseTheWindowBecomingKeyReenablesClear() {
        let cards = Cards()
        cards.clearable = false
        becomeKey(cards)
        cards.clearable = true
        becomeKey(cards)
        #expect(cards.clear.isEnabled)
    }

    @Test func aRenderWithNothingClearableStartsDisabled() {
        let cards = Cards()
        let before = cards.clear
        cards.clearable = false
        var grown = cards.state
        grown.tabs.append(cards.tab("grown", .today))
        cards.reload(grown)
        let rendered = cards.clear
        #expect(rendered !== before)
        #expect(!rendered.isEnabled)
    }
}
