import AppKit
import Testing
@testable import Parc

struct SearchPrivacyBannerTests {
    @Test func dismissalIsRememberedAcrossSessions() throws {
        let suite = "Parc.SearchPrivacyBannerTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
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
