import AppKit
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCommandBar
@testable import ParcSidebar

struct SearchPrivacyBannerTests {
    @Test func dismissalIsRememberedAcrossSessions() throws {
        let defaults = try #require(TestDefaults("Parc.SearchPrivacyBannerTests."))
        CommandBarSearchPrivacyPolicy(defaults: defaults).dismiss()
        #expect(CommandBarSearchPrivacyPolicy(defaults: defaults).hasBeenExplicitlyDismissed)
    }

    @Test(arguments: [
        (false, false, false, false, true, false, true),
        (true, false, false, false, true, false, false),
        (false, true, false, false, true, false, false),
        (false, false, true, false, true, false, false),
        (false, false, false, true, true, false, false),
        (false, false, false, false, false, false, false),
        (false, false, false, false, true, true, false),
    ])
    func theInfoButtonOnlyAppearsOnAnEligiblePalette(dismissed: Bool, visible: Bool, scoped: Bool,
                                                      siteOffer: Bool, results: Bool, sidebar: Bool, expected: Bool) {
        #expect(CommandBarSearchPrivacyPolicy.showsInfoAccessory(dismissed: dismissed, bannerVisible: visible,
            scoped: scoped, offeringSiteSearch: siteOffer, hasResults: results, sidebarSession: sidebar) == expected)
    }

    @MainActor private func banner(width: CGFloat) -> CommandBarSearchPrivacyBanner {
        _ = NSApplication.shared
        let banner = CommandBarSearchPrivacyBanner(frame: .zero)
        banner.frame = NSRect(x: 0, y: 0, width: width, height: banner.preferredHeight(forWidth: width))
        banner.layoutSubtreeIfNeeded()
        return banner
    }

    @Test @MainActor func theInfoButtonKeepsFocusInTheCommandField() {
        let button = CommandBarPrivacyInfoButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        #expect(button.refusesFirstResponder)
        #expect(button.accessibilityLabel() == "Search suggestions privacy")
    }

    @Test(arguments: [260.0, 300.0, 765.0])
    @MainActor func theBannerKeepsItsTextAndButtonsInsideItsWidth(width: Double) {
        let banner = banner(width: width)
        let condensed = banner.isCondensed(forWidth: width)
        #expect(banner.frame.height == (condensed ? 133 : 60))
        #expect(banner.bounds.contains(banner.settingsButton.frame))
        #expect(banner.bounds.contains(banner.dismissButton.frame))
        #expect(!banner.title.frame.intersects(banner.settingsButton.frame))
        #expect(!banner.title.frame.intersects(banner.dismissButton.frame))
    }

    @Test(arguments: [true, false])
    @MainActor func theButtonsDispatchOnlyTheirOwnAction(settings: Bool) {
        let banner = banner(width: 320)
        var actions: [String] = []
        banner.onSearchSettings = { actions.append("settings") }
        banner.onDismiss = { actions.append("dismiss") }
        let button = settings ? banner.settingsButton : banner.dismissButton
        button.sendClick()
        #expect(actions == [settings ? "settings" : "dismiss"])
        #expect(button.refusesFirstResponder)
    }

    @Test(arguments: [
        (1, false, SidebarTablistBackground.Press.dragWindow),
        (2, false, .waitForRelease), (3, false, .waitForRelease), (1, true, .passThrough),
    ])
    func theBackgroundOnlyDragsOnAnOrdinaryFirstPress(clicks: Int, control: Bool, expected: SidebarTablistBackground.Press) {
        #expect(SidebarTablistBackground.press(clickCount: clicks, modifiers: control ? .control : []) == expected)
    }

    @Test(arguments: [
        (2, false, 400.0, 320.0, true), (2, false, 320, 320, true),
        (2, false, 200, 320, false), (1, false, 400, 320, false),
        (2, true, 400, 320, false), (2, false, 0, nil, true),
    ] as [(Int, Bool, Double, Double?, Bool)])
    func onlyEmptyBackgroundDoubleClicksOpenTheBar(clicks: Int, control: Bool, y: Double, lastRow: Double?, expected: Bool) {
        #expect(SidebarTablistBackground.opensCommandBar(clickCount: clicks, modifiers: control ? .control : [],
            y: y, lastRowMaxY: lastRow.map { CGFloat($0) }) == expected)
    }
}

extension SearchPrivacyBannerTests {
    @Test func aFreshProfileHasNotDismissedTheBannerAndDismissalIsStoredUnderItsKey() throws {
        let defaults = try #require(TestDefaults("Parc.SearchPrivacyBannerTests."))
        let policy = CommandBarSearchPrivacyPolicy(defaults: defaults)
        #expect(!policy.hasBeenExplicitlyDismissed)
        policy.dismiss()
        #expect(defaults.bool(forKey: "commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed"))
    }

    @Test @MainActor func theInfoButtonIsTheSymbolAloneWithAShadow() {
        _ = NSApplication.shared
        let button = CommandBarPrivacyInfoButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        #expect(button.image != nil)
        #expect(button.imagePosition == .imageOnly)
        #expect(button.shadow?.shadowBlurRadius == 8)
    }

    @Test @MainActor func theBannerNamesItselfAndItsButtons() {
        let banner = banner(width: 765)
        #expect(banner.title.stringValue == "We talk to your search engine to help us suggest results.")
        #expect(banner.title.font == NSFont.boldSystemFont(ofSize: 13))
        #expect(banner.settingsButton.title == "Search Settings…")
        #expect(banner.dismissButton.title == "Dismiss")
        #expect(banner.icon.image != nil)
        #expect(banner.accessibilityLabel() == "Search suggestions privacy")
        #expect(banner.dismissButton.accessibilityLabel() == "Dismiss")
        #expect(banner.settingsButton.refusesFirstResponder)
        #expect(banner.dismissButton.refusesFirstResponder)
    }

    @Test @MainActor func aFullWidthBannerLaysItsRowOutFromTheEdges() {
        let banner = banner(width: 765)
        #expect(!banner.isCondensed(forWidth: 765))
        #expect(banner.preferredHeight(forWidth: 765) == 60)
        #expect(banner.icon.frame.minX == 16)
        #expect(abs(banner.dismissButton.frame.maxX - (765 - 10)) < 0.5)
        #expect(abs(banner.settingsButton.frame.maxX + 10 - banner.dismissButton.frame.minX) < 0.5)
        #expect(abs(banner.title.frame.minX - (banner.icon.frame.maxX + 14)) < 0.5)
        #expect(banner.title.frame.maxX <= banner.settingsButton.frame.minX - 14 + 0.5)
    }

    @Test @MainActor func theIconAndButtonBodiesShareTheRowsCentre() {
        let banner = banner(width: 765)
        #expect(abs(banner.icon.frame.midY - 30) < 0.5)
        #expect(abs(banner.dismissButton.frame.minY + 18 - 30) < 0.5)
        #expect(banner.dismissButton.intrinsicContentSize.height == 39)
    }

    @Test @MainActor func theNarrowestSingleRowBannerKeepsItsWholeTitle() throws {
        _ = NSApplication.shared
        let banner = CommandBarSearchPrivacyBanner(frame: .zero)
        let width = try #require((300...1000).map(CGFloat.init).first { !banner.isCondensed(forWidth: $0) })
        banner.frame = NSRect(x: 0, y: 0, width: width, height: 60)
        banner.layout()
        let line = try #require(banner.title.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 100)).width)
        #expect(line <= banner.title.frame.width)
    }

    @Test(arguments: [
        (NSAppearance.Name.darkAqua, 0.93, 0.494), (NSAppearance.Name.aqua, 0.09, 0.523),
    ])
    @MainActor func theTitleAndIconColoursFollowTheAppearance(name: NSAppearance.Name, title: Double, icon: Double) throws {
        _ = NSApplication.shared
        let appearance = try #require(NSAppearance(named: name))
        var resolved: (title: NSColor, icon: NSColor)?
        appearance.performAsCurrentDrawingAppearance {
            resolved = (CommandBarSearchPrivacyBanner.titleColor.usingColorSpace(.sRGB)!,
                        CommandBarSearchPrivacyBanner.iconColor.usingColorSpace(.sRGB)!)
        }
        let colors = try #require(resolved)
        #expect(abs(colors.title.redComponent - title) < 0.005)
        #expect(abs(colors.icon.redComponent - icon) < 0.005)
    }

    @Test @MainActor func aNarrowBannerStacksItsButtonsUnderTheText() {
        let banner = banner(width: 300)
        #expect(banner.isCondensed(forWidth: 300))
        #expect(banner.preferredHeight(forWidth: 300) == 133)
        #expect(banner.settingsButton.frame.minY >= banner.title.frame.maxY + 14 - 0.5)
        #expect(banner.dismissButton.frame.maxX <= 300 - 10 + 0.5)
    }

    @Test @MainActor func theNarrowestBannerStartsItsButtonsAtTheLeadingInset() {
        let banner = banner(width: 260)
        #expect(banner.settingsButton.frame.minX == 16)
        #expect(banner.dismissButton.frame.maxX <= 260 - 10 + 0.5)
    }

    @Test(arguments: [
        (1, NSEvent.ModifierFlags([.command, .option, .shift]), SidebarTablistBackground.Press.dragWindow),
        (1, NSEvent.ModifierFlags([.shift]), .dragWindow),
    ])
    func otherModifiersStillDragTheWindow(clicks: Int, modifiers: NSEvent.ModifierFlags, expected: SidebarTablistBackground.Press) {
        #expect(SidebarTablistBackground.press(clickCount: clicks, modifiers: modifiers) == expected)
    }

    @Test func otherModifiersDoNotStopAnEmptyListDoubleClick() {
        #expect(SidebarTablistBackground.opensCommandBar(clickCount: 2, modifiers: [.command], y: 0, lastRowMaxY: nil))
    }
}
