import AppKit
import Combine
import ParcTestSupport
import Testing
import ParcCore
@testable import Parc
@testable import ParcKit
@testable import ParcSettings

struct WebsiteThemeTests {
    private let key = "parc.websiteTheme.v1"

    @MainActor private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try #require(TestDefaults("parc.website-theme."))
        try body(defaults)
    }

    @Test @MainActor func themeSharingDefaultsToOnWithoutWritingAPreference() throws {
        try withDefaults { defaults in
            let preferences = WebsiteThemePreferences(defaults: defaults)
            #expect(preferences.state.isEnabled && !preferences.loadError)
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test(arguments: [false, true])
    @MainActor func changesAreSavedBeforeConsumersReceiveThem(enabled: Bool) throws {
        try withDefaults { defaults in
            let preferences = WebsiteThemePreferences(defaults: defaults)
            try preferences.setEnabled(!enabled)
            var delivered: WebsiteThemePreferences.State?
            var savedAtDelivery: WebsiteThemePreferences.State?
            let observation = preferences.$state.dropFirst().sink { state in
                delivered = state
                savedAtDelivery = defaults.data(forKey: key).flatMap {
                    try? JSONDecoder().decode(WebsiteThemePreferences.State.self, from: $0)
                }
            }
            try preferences.setEnabled(enabled)
            #expect(delivered?.isEnabled == enabled)
            #expect(savedAtDelivery == delivered)
            #expect(WebsiteThemePreferences(defaults: defaults).state == delivered)
            withExtendedLifetime(observation) {}
        }
    }

    @Test @MainActor func repeatingTheSameChoiceDoesNotDeliverAnotherChange() throws {
        try withDefaults { defaults in
            let preferences = WebsiteThemePreferences(defaults: defaults)
            try preferences.setEnabled(false)
            let observation = preferences.$state.dropFirst().sink { _ in Issue.record("Published an unchanged preference") }
            try preferences.setEnabled(false)
            withExtendedLifetime(observation) {}
        }
    }

    @Test @MainActor func aLateConsumerImmediatelyReceivesTheCurrentOptOut() throws {
        try withDefaults { defaults in
            let preferences = WebsiteThemePreferences(defaults: defaults)
            try preferences.setEnabled(false)
            var received: Bool?
            let observation = preferences.$state.sink { received = $0.isEnabled }
            #expect(received == false)
            withExtendedLifetime(observation) {}
        }
    }

    @Test(arguments: ["", "{}", #"{"version":99,"isEnabled":true}"#])
    @MainActor func anUnreadablePreferenceIsPreservedAndWithholdsSharing(saved: String) throws {
        try withDefaults { defaults in
            let bytes = Data(saved.utf8)
            defaults.set(bytes, forKey: key)
            let preferences = WebsiteThemePreferences(defaults: defaults)
            #expect(preferences.loadError && !preferences.state.isEnabled)
            #expect(throws: WebsiteThemePreferences.Failure.unavailable) { try preferences.setEnabled(true) }
            #expect(defaults.data(forKey: key) == bytes)
        }
    }

    @Test(arguments: [(CGFloat(0), "#FF800000"), (0.25, "#FF800040")])
    func displayP3WebsiteColorsPreserveRGBAndRoundAlpha(example: (CGFloat, String)) {
        let color = NSColor(displayP3Red: 1, green: 0.5, blue: 0, alpha: example.0)
        #expect(ThemeChromePalette.websiteColor(color) == example.1)
    }

    @Test(arguments: [false, true])
    @MainActor func theWebsiteStylesheetUsesThePublicSemanticNames(dark: Bool) throws {
        let primary = try #require(ThemeColor(red: 0.8, green: 0.4, blue: 0.2, colorSpace: .displayP3))
        let theme = SpaceTheme.singleColor(primary)
        let css = ThemeChromePalette(theme: theme, isDark: dark).websiteStylesheet(theme: theme)
        let names = ["foregroundPrimary", "foregroundSecondary", "foregroundTertiary", "maxContrastColor",
                     "minContrastColor", "backgroundExtra", "background", "focus", "hover", "cutoutColor", "title", "subtitle"]
        #expect(css.hasPrefix(":root {\n") && css.hasSuffix("\n}"))
        #expect(names.allSatisfy { css.components(separatedBy: "--arc-palette-\($0):").count == 2 })
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func theWebsiteStylesheetOnlyExportsTheSelectedColorLayers(count: Int) throws {
        let primary = try #require(ThemeColor(red: 0.8, green: 0.4, blue: 0.2, colorSpace: .displayP3))
        let theme = SpaceTheme(primaryColor: primary, colorCount: count)
        let css = ThemeChromePalette(theme: theme, isDark: false).websiteStylesheet(theme: theme)
        #expect(css.contains("--arc-background-simple-color: #CC6633FF;") == (count == 1))
        #expect(css.contains("--arc-background-gradient-color0:") == (count >= 2))
        #expect(css.contains("--arc-background-gradient-color1:") == (count >= 2))
        #expect(css.contains("--arc-background-gradient-overlay-color0:") == (count == 3))
        #expect(css.contains("--arc-background-gradient-overlay-color1:") == (count == 3))
        #expect(!css.contains("--arc-background-gradient-color2:"))
    }

    @Test @MainActor func anUncoloredWebsiteThemeUsesTheNativeAppearance() {
        let theme = SpaceTheme()
        let light = ThemeChromePalette(theme: theme, isDark: false).websiteStylesheet(theme: theme)
        let dark = ThemeChromePalette(theme: theme, isDark: true).websiteStylesheet(theme: theme)
        #expect(light != dark)
        #expect([light, dark].allSatisfy { $0.contains("--arc-background-simple-color:") })
    }
}
