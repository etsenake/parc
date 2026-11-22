import Testing
@testable import ParcCore
@testable import ParcCommandBar

struct ShortcutTooltipDiscoveryTests {
    private struct Fixture {
        let discovery = ShortcutTooltipDiscovery()
        var dismissals = 0
        var copyTooltip = ""
        var siteControls: [String] = []

        mutating func apply(copy: String, capture: String) {
            let fingerprint = ShortcutTooltipDiscoverySkip.fingerprint(
                copyURLTooltip: "Copy URL " + copy, copyURLShortcut: copy, captureShortcut: capture,
                captureVisiblePageShortcut: "", captureFullPageShortcut: "")
            var receivedDismissal = false
            var refreshedTooltip: String?
            var refreshedCapture: String?
            discovery.apply(fingerprint, dismissToasts: { receivedDismissal = true },
                            refreshCopyTooltip: { refreshedTooltip = "Copy URL " + copy },
                            refreshSiteControlShortcuts: { refreshedCapture = capture })
            if receivedDismissal { dismissals += 1 }
            if let refreshedTooltip { copyTooltip = refreshedTooltip }
            if let refreshedCapture { siteControls.append(refreshedCapture) }
        }
    }

    @Test func identicalBindingsLeaveTheTooltipAndToastsAlone() {
        var fixture = Fixture()
        fixture.apply(copy: "⌘C", capture: "⌘⇧2")
        fixture.apply(copy: "⌘C", capture: "⌘⇧2")
        #expect(fixture.dismissals == 1)
        #expect(fixture.siteControls == ["⌘⇧2"])
    }

    @Test func aNewCopyBindingDismissesTheStaleToastAndRefreshesTheTooltip() {
        var fixture = Fixture()
        fixture.apply(copy: "⌘C", capture: "⌘⇧2")
        fixture.apply(copy: "⌃C", capture: "⌘⇧2")
        #expect(fixture.dismissals == 2)
        #expect(fixture.copyTooltip == "Copy URL ⌃C")
    }

    @Test func aNewCaptureBindingRefreshesSiteControls() {
        var fixture = Fixture()
        fixture.apply(copy: "⌘C", capture: "⌘⇧2")
        fixture.apply(copy: "⌘C", capture: "⌃⇧2")
        #expect(fixture.siteControls == ["⌘⇧2", "⌃⇧2"])
    }
}
