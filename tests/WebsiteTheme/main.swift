import AppKit
import Combine

try MainActor.assumeIsolated {
    var checks = 0
    func check(_ value: @autoclosure () -> Bool, _ reason: String) {
        checks += 1; precondition(value(), reason)
    }
    let suite = "Parc.WebsiteTheme.Checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "parc.websiteTheme.v1"
    let preferences = WebsiteThemePreferences(defaults: defaults)
    check(preferences.state.isEnabled && !preferences.loadError, "recovered registered default enables theme sharing")
    check(defaults.object(forKey: key) == nil, "reading does not create a saved preference")
    var delivered: [Bool] = []
    let observation = preferences.$state.sink { delivered.append($0.isEnabled) }
    var secondConsumer: [Bool] = []
    var savedBeforeDelivery = true
    let secondObservation = preferences.$state.sink { state in
        secondConsumer.append(state.isEnabled)
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(WebsiteThemePreferences.State.self, from: data) {
            savedBeforeDelivery = savedBeforeDelivery && saved == state
        }
    }
    try preferences.setEnabled(false)
    check(!WebsiteThemePreferences(defaults: defaults).state.isEnabled, "opt-out survives reopen")
    let saved = defaults.data(forKey: key)!
    try preferences.setEnabled(false)
    check(defaults.data(forKey: key) == saved && delivered == [true, false], "idempotent update")
    try preferences.setEnabled(true)
    check(WebsiteThemePreferences(defaults: defaults).state.isEnabled && delivered == [true, false, true], "reenable is persisted and delivered")
    check(secondConsumer == delivered && savedBeforeDelivery,
          "every live consumer receives the persisted choice, before depending on it")
    try preferences.setEnabled(false)
    var lateConsumer: Bool?
    let lateObservation = preferences.$state.sink { lateConsumer = $0.isEnabled }
    check(lateConsumer == false, "a newly attached consumer immediately receives the current opt-out")
    observation.cancel(); secondObservation.cancel(); lateObservation.cancel()
    let reloaded = WebsiteThemePreferences(defaults: defaults)
    check(!reloaded.state.isEnabled, "closing consumers cannot reset the saved opt-out")
    for malformed: Any in ["bad", Data("{\"version\":99,\"isEnabled\":true}".utf8), Data("{}".utf8)] {
        defaults.set(malformed, forKey: key)
        let original = defaults.object(forKey: key) as! NSObject
        let unreadable = WebsiteThemePreferences(defaults: defaults)
        check(unreadable.loadError && !unreadable.state.isEnabled, "unreadable policy withholds sharing")
        do { try unreadable.setEnabled(true); fatalError("unexpected saved-policy replacement") }
        catch { check((defaults.object(forKey: key) as! NSObject).isEqual(original), "unreadable bytes preserved") }
    }
    let color = NSColor(displayP3Red: 1, green: 0.5, blue: 0, alpha: 0.25)
    check(ThemeChromePalette.websiteColor(color) == "#FF800040", "P3 conversion retains alpha and nearest rounding")
    check(ThemeChromePalette.websiteColor(color.withAlphaComponent(0)) == "#FF800000", "transparent gradient stop retains RGB")
    let primary = ThemeColor(red: 0.8, green: 0.4, blue: 0.2, colorSpace: .displayP3)!
    let single = SpaceTheme.singleColor(primary)
    let two = SpaceTheme(primaryColor: primary, colorCount: 2)
    let three = SpaceTheme(primaryColor: primary, colorCount: 3)
    let names = ["foregroundPrimary", "foregroundSecondary", "foregroundTertiary", "maxContrastColor",
                 "minContrastColor", "backgroundExtra", "background", "focus", "hover", "cutoutColor", "title", "subtitle"]
    for dark in [false, true] {
        let palette = ThemeChromePalette(theme: single, isDark: dark)
        let css = palette.websiteStylesheet(theme: single)
        check(css.hasPrefix(":root {\n") && css.hasSuffix("\n}"), "root-only stylesheet")
        for name in names { check(css.components(separatedBy: "--arc-palette-\(name):").count == 2, "one exact public semantic name") }
        check(css.contains("--arc-background-simple-color: #CC6633FF;"), "original P3 background color")
        check(!css.contains("gradient-"), "single color removes former gradient declarations")
        let pair = palette.websiteStylesheet(theme: two)
        check(pair.contains("--arc-background-gradient-color0:") && pair.contains("--arc-background-gradient-color1:"), "zero-based base gradient stops")
        check(!pair.contains("simple-color") && !pair.contains("overlay-color"), "two colors do not retain former simple or overlay colors")
        let triple = palette.websiteStylesheet(theme: three)
        check(triple.contains("--arc-background-gradient-overlay-color0:") && triple.contains("--arc-background-gradient-overlay-color1:"), "third color exports transparent and opaque overlay stops")
        check(!triple.contains("--arc-background-gradient-color2:"), "third color is an overlay rather than a third base stop")
    }
    let plain = SpaceTheme()
    let light = ThemeChromePalette(theme: plain, isDark: false).websiteStylesheet(theme: plain)
    let dark = ThemeChromePalette(theme: plain, isDark: true).websiteStylesheet(theme: plain)
    check(light != dark, "automatic system colors resolve in the original palette appearance")
    check(light.contains("--arc-background-simple-color:") && dark.contains("--arc-background-simple-color:"), "uncolored background still exports semantic values")
    print("\(checks) website theme preference and color assertions passed")
}
