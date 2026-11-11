import AppKit

@main struct CommandBarSearchPrivacyBannerTests {
    @MainActor static func main() {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); assertions += 1
        }
        _ = NSApplication.shared

        let suite = "parc.tests.command-bar-privacy.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let policy = CommandBarSearchPrivacyPolicy(defaults: defaults)
        check(!policy.hasBeenExplicitlyDismissed, "a fresh profile has not dismissed the banner")
        policy.dismiss()
        check(CommandBarSearchPrivacyPolicy(defaults: defaults).hasBeenExplicitlyDismissed, "Dismiss persists across bar sessions")
        check(defaults.bool(forKey: "commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed"), "the key name is used")
        defaults.removePersistentDomain(forName: suite)

        func info(dismissed: Bool = false, visible: Bool = false, scoped: Bool = false, offer: Bool = false,
                  results: Bool = true, sidebar: Bool = false) -> Bool {
            CommandBarSearchPrivacyPolicy.showsInfoAccessory(dismissed: dismissed, bannerVisible: visible, scoped: scoped,
                offeringSiteSearch: offer, hasResults: results, sidebarSession: sidebar)
        }
        check(info(), "an unscoped bar with results offers the info accessory")
        check(!info(dismissed: true), "a dismissed notice has no info accessory")
        check(!info(visible: true), "the accessory hides while the banner shows")
        check(!info(scoped: true), "a scope has no info accessory")
        check(!info(offer: true), "the site-search hint takes the trailing slot first")
        check(!info(results: false), "no results, no accessory")
        check(!info(sidebar: true), "the sidebar search session has no banner surface")

        let infoButton = CommandBarPrivacyInfoButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        check(infoButton.image != nil && infoButton.imagePosition == .imageOnly, "the accessory is the info symbol alone")
        check(infoButton.shadow?.shadowBlurRadius == 8, "the 8-point accessory shadow")
        check(infoButton.accessibilityLabel() == "Search suggestions privacy", "the accessory is labelled for VoiceOver")
        check(infoButton.refusesFirstResponder, "clicking the accessory leaves the command field focused")

        let banner = CommandBarSearchPrivacyBanner(frame: NSRect(x: 0, y: 0, width: 765, height: 60))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 765, height: 60), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = banner
        banner.layoutSubtreeIfNeeded()
        check(banner.title.stringValue == "We talk to your search engine to help us suggest results.", "the title")
        check(banner.title.font == NSFont.boldSystemFont(ofSize: 13), "the title is bold body text")
        check(banner.settingsButton.title == "Search Settings…" && banner.dismissButton.title == "Dismiss", "the button titles")
        check(banner.icon.image != nil, "the info.circle symbol resolves")
        check(!banner.isCondensed(forWidth: 765) && banner.preferredHeight(forWidth: 765) == 60, "a full-width bar uses the 60-point row")
        check(banner.icon.frame.minX == 16, "16-point leading inset")
        check(abs(banner.dismissButton.frame.maxX - (765 - 10)) < 0.5, "10-point trailing inset")
        check(abs(banner.settingsButton.frame.maxX + 10 - banner.dismissButton.frame.minX) < 0.5, "buttons sit 10 apart")
        check(abs(banner.title.frame.minX - (banner.icon.frame.maxX + 14)) < 0.5, "the title sits 14 after the icon")
        check(banner.title.frame.maxX <= banner.settingsButton.frame.minX - 14 + 0.5, "the title never runs under the buttons")
        check(abs(banner.icon.frame.midY - 30) < 0.5 && abs(banner.dismissButton.frame.minY + 18 - 30) < 0.5,
              "the icon and the buttons' 36-point bodies are vertically centred")
        check(banner.dismissButton.intrinsicContentSize.height == 39, "a 36-point body, its 2-point lip and the half-point stroke inset")
        let narrowest = CommandBarSearchPrivacyBanner(frame: .zero)
        let singleRow = (300...1000).map(CGFloat.init).first { !narrowest.isCondensed(forWidth: $0) } ?? 0
        narrowest.frame = NSRect(x: 0, y: 0, width: singleRow, height: 60); narrowest.layout()
        let titleLine = narrowest.title.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 100)).width ?? .infinity
        check(titleLine <= narrowest.title.frame.width, "the narrowest single-row banner does not truncate its title")
        var title = NSColor.clear, icon = NSColor.clear
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            title = CommandBarSearchPrivacyBanner.titleColor.usingColorSpace(.sRGB)!
            icon = CommandBarSearchPrivacyBanner.iconColor.usingColorSpace(.sRGB)!
        }
        check(abs(title.redComponent - 0.93) < 0.005 && abs(icon.redComponent - 0.494) < 0.005, "dark Gray12 title and Gray10 icon")
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            title = CommandBarSearchPrivacyBanner.titleColor.usingColorSpace(.sRGB)!
            icon = CommandBarSearchPrivacyBanner.iconColor.usingColorSpace(.sRGB)!
        }
        check(abs(title.redComponent - 0.09) < 0.005 && abs(icon.redComponent - 0.523) < 0.005, "light Gray12 title and Gray10 icon")

        let narrow: CGFloat = 300
        check(banner.isCondensed(forWidth: narrow) && banner.preferredHeight(forWidth: narrow) == 133,
              "a bar too narrow for one row uses the 133-point condensed layout")
        banner.frame = NSRect(x: 0, y: 0, width: narrow, height: 133); banner.layoutSubtreeIfNeeded()
        check(banner.settingsButton.frame.minY >= banner.title.frame.maxY + 14 - 0.5, "condensed buttons sit under the text")
        check(banner.dismissButton.frame.maxX <= narrow - 10 + 0.5, "condensed buttons stay inside the trailing inset")
        banner.frame = NSRect(x: 0, y: 0, width: 260, height: 133); banner.layoutSubtreeIfNeeded()
        check(banner.settingsButton.frame.minX == 16 && banner.dismissButton.frame.maxX <= 260 - 10 + 0.5,
              "the narrowest 260-point bar (a 300-point popup window) fits both buttons from the leading inset")

        var settings = 0, dismissals = 0
        banner.onSearchSettings = { settings += 1 }
        banner.onDismiss = { dismissals += 1 }
        banner.settingsButton.performClick(nil)
        check(settings == 1 && dismissals == 0, "Search Settings… asks the owner for search settings")
        banner.dismissButton.performClick(nil)
        check(dismissals == 1 && settings == 1, "Dismiss asks the owner to hide and remember")
        check(banner.accessibilityLabel() == "Search suggestions privacy", "the group names the notice; its title text is read once, by itself")
        check(banner.settingsButton.refusesFirstResponder && banner.dismissButton.refusesFirstResponder,
              "the banner's buttons leave the command field focused, even with Full Keyboard Access")
        check(banner.dismissButton.accessibilityLabel() == "Dismiss", "the Dismiss control is labelled")

        check(SidebarTablistBackground.press(clickCount: 1, modifiers: []) == .dragWindow, "a first press drags the window")
        check(SidebarTablistBackground.press(clickCount: 1, modifiers: [.command, .option, .shift]) == .dragWindow,
              "other modifiers still drag checks only Control")
        check(SidebarTablistBackground.press(clickCount: 2, modifiers: []) == .waitForRelease,
              "the second press of a double-click doesn't drag; its release opens the bar")
        check(SidebarTablistBackground.press(clickCount: 3, modifiers: []) == .waitForRelease, "later presses don't drag")
        check(SidebarTablistBackground.press(clickCount: 1, modifiers: [.control]) == .passThrough,
              "Control-press reaches the surface's secondary click")
        check(SidebarTablistBackground.opensCommandBar(clickCount: 2, modifiers: [], y: 400, lastRowMaxY: 320),
              "a double-click under the last row opens the bar")
        check(SidebarTablistBackground.opensCommandBar(clickCount: 2, modifiers: [], y: 320, lastRowMaxY: 320),
              "the last row's bottom edge counts as empty space compares")
        check(!SidebarTablistBackground.opensCommandBar(clickCount: 2, modifiers: [], y: 200, lastRowMaxY: 320),
              "a gap among rows does not open it")
        check(!SidebarTablistBackground.opensCommandBar(clickCount: 1, modifiers: [], y: 400, lastRowMaxY: 320),
              "a single click does not open it")
        check(!SidebarTablistBackground.opensCommandBar(clickCount: 2, modifiers: [.control], y: 400, lastRowMaxY: 320),
              "Control keeps the secondary click")
        check(SidebarTablistBackground.opensCommandBar(clickCount: 2, modifiers: [.command], y: 0, lastRowMaxY: nil),
              "an empty list opens it anywhere")
        final class Recorder: NSView {
            var downs: [Int] = [], ups: [Int] = []
            override func mouseDown(with event: NSEvent) { downs.append(event.clickCount) }
            override func mouseUp(with event: NSEvent) { ups.append(event.clickCount) }
        }
        let host = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 400), styleMask: [.borderless],
                            backing: .buffered, defer: false)
        let recorder = Recorder(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        let tablistScroll = NSScrollView(frame: recorder.bounds)
        let tablist = NSStackView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        tablistScroll.documentView = tablist
        recorder.addSubview(tablistScroll); host.contentView = recorder
        func mouse(_ type: NSEvent.EventType, clicks: Int) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 300), modifierFlags: [], timestamp: 0,
                               windowNumber: host.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        tablist.mouseDown(with: mouse(.leftMouseDown, clicks: 1))
        tablistScroll.contentView.mouseDown(with: mouse(.leftMouseDown, clicks: 2))
        tablistScroll.contentView.mouseUp(with: mouse(.leftMouseUp, clicks: 2))
        check(recorder.downs == [1, 2] && recorder.ups == [2], "list and clip presses reach the sidebar")
        print("\(assertions) command bar privacy banner and sidebar background assertions passed")
    }
}
