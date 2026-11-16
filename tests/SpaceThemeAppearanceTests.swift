import AppKit

@main
struct SpaceThemeAppearanceTests {
    static var assertions = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
        assertions += 1
        guard condition() else { fatalError("Line \(line): \(message)") }
    }
    @MainActor static func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }
    @MainActor static func button(_ label: String, in view: NSView) -> NSButton {
        guard let result = buttons(in: view).first(where: { $0.accessibilityLabel() == label }) else {
            fatalError("Missing production control: \(label)")
        }
        return result
    }
    @MainActor static func expectSelection(_ choice: AppAppearance, in editor: SpaceThemeEditorView) {
        for value in AppAppearance.allCases {
            let selected = button("\(value.title) appearance", in: editor).accessibilityValue() as? Int
            expect(selected == (value == choice ? 1 : 0), "Parent choice selects exactly \(choice.title), including \(value.title)")
        }
    }
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        let originalAppearance = NSApp.appearance
        let suite = "Parc.SpaceThemeAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { NSApp.appearance = originalAppearance; defaults.removePersistentDomain(forName: suite) }

        AppAppearance.apply(.dark, defaults: defaults)
        var theme = SpaceTheme.singleColor(ThemeColor(hex: "4C6688")!)
        theme.appearance = .light
        theme.intensity = 0.3; theme.noise = 0.6; theme.texture = .tweed
        let editor = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
        let other = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        var commits = 0, previews = 0
        var appearanceChanges: [(AppAppearance, AppAppearance)] = []
        editor.onCommit = { _ in commits += 1 }
        editor.onPreview = { _ in previews += 1 }
        editor.onSetAppearance = { value in
            let previous = AppAppearance.current
            if AppAppearance.apply(value, defaults: defaults) { appearanceChanges.append((previous, value)) }
        }
        expectSelection(.dark, in: editor)
        expectSelection(.dark, in: other)
        expect(!button("Previous color presets", in: editor).isEnabled && button("Next color presets", in: editor).isEnabled,
               "An editor without a window page opens on the first preset page")
        var pages: [Int] = []
        editor.onPresetPageChange = { pages.append($0) }
        for _ in 0..<4 { button("Next color presets", in: editor).performClick(nil) }
        expect(!button("Next color presets", in: editor).isEnabled, "Preset page reaches the last page")
        expect(pages == [1, 2, 3, 4], "Each page change goes to the owning window")

        button("Automatic appearance", in: editor).performClick(nil)
        expect(NSApp.appearance == nil && AppAppearance.current == .automatic, "Automatic clears the native app override")
        expect(defaults.string(forKey: "parc.appAppearance.v1") == nil, "Automatic removes the persisted override")
        expect(editor.theme == theme && other.theme == SpaceTheme(), "Automatic preserves both editors' complete themes")
        expect(commits == 0 && previews == 0, "Parent reset never writes or previews a theme")
        expect(appearanceChanges.count == 1 && appearanceChanges[0].0 == .dark && appearanceChanges[0].1 == .automatic,
               "Parent receives the original and new explicit appearance for its Undo owner")
        expectSelection(.automatic, in: editor)
        expectSelection(.automatic, in: other)
        expect(!button("Next color presets", in: editor).isEnabled, "Automatic preserves the open editor's preset page")
        editor.undo(nil)
        expect(editor.theme == theme && commits == 0, "Parent appearance does not create a local theme Undo entry")
        button("Automatic appearance", in: editor).performClick(nil)
        expect(appearanceChanges.count == 1, "Repeated Automatic does not create a second appearance Undo")

        for value in [AppAppearance.light, .dark, .automatic] {
            button("\(value.title) appearance", in: editor).performClick(nil)
            expectSelection(value, in: editor)
            expectSelection(value, in: other)
            expect(editor.theme == theme && commits == 0 && previews == 0, "All sibling appearance delegates preserve the Space palette")
        }
        AppAppearance.apply(.light, defaults: defaults)
        expect(defaults.string(forKey: "parc.appAppearance.v1") == "light", "Explicit choice is persisted")
        NSApp.appearance = nil
        expectSelection(.automatic, in: editor)
        AppAppearance.restore(defaults: defaults)
        expectSelection(.light, in: editor)
        expectSelection(.light, in: other)
        NSApp.appearance = nil
        button("Automatic appearance", in: editor).performClick(nil)
        expect(defaults.string(forKey: "parc.appAppearance.v1") == nil, "Automatic clears stale persistence when native override is already nil")

        button("Add color", in: editor).performClick(nil)
        let edited = editor.theme
        expect(edited.colorCount == 2 && commits == 1, "An actual theme edit retains its local transaction")
        button("Dark appearance", in: editor).performClick(nil)
        button("Automatic appearance", in: editor).performClick(nil)
        expect(editor.theme == edited && commits == 1, "Parent changes preserve an existing theme Undo stack")
        editor.undo(nil)
        expect(editor.theme == theme && commits == 2, "Undo still restores the preceding theme edit")
        expect(AppAppearance.current == .automatic, "Local theme Undo cannot overwrite the parent's current choice")
        editor.redo(nil)
        expect(editor.theme == edited && commits == 3, "Theme Redo survives the parent reset")

        weak var released: SpaceThemeEditorView?
        autoreleasepool {
            let transient = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
            released = transient
            expectSelection(.automatic, in: transient)
        }
        expect(released == nil, "Appearance observation does not retain a retired editor")
        AppAppearance.apply(.dark, defaults: defaults)
        expectSelection(.dark, in: editor)
        AppAppearance.preview(.light)
        expect(AppAppearance.current == .light && defaults.string(forKey: "parc.appAppearance.v1") == "dark",
               "A replay preview shows without being saved, so a crash keeps the saved choice")
        expect(AppAppearance.endPreview(.light, defaults: defaults) && AppAppearance.current == .dark,
               "Closing replay early shows the saved choice again")
        AppAppearance.preview(.light)
        AppAppearance.apply(.automatic, defaults: defaults)
        expect(!AppAppearance.endPreview(.light, defaults: defaults) && AppAppearance.current == .automatic,
               "A choice made elsewhere during replay is not undone by its close")
        AppAppearance.apply(.dark, defaults: defaults)
        presetPageOwnership()
        readableAutomaticText()
        print("Space theme appearance: \(assertions) assertions passed")
    }
    @MainActor static func checkPushed(_ palette: ThemeChromePalette, _ plain: ThemeChromePalette, _ backgrounds: [SIMD4<Float>], _ label: String) {
        func worst(_ color: NSColor) -> Double { ThemeRenderMath.worstContrast(ThemeRenderMath.components(color), over: backgrounds) }
        let target: Float = palette.isDark ? 1 : 0
        for (role, color, unadjusted) in [("text", palette.title, plain.title), ("accent", palette.maxContrastColor, plain.maxContrastColor)] {
            let value = ThemeRenderMath.components(color)
            let extreme = abs(value.x - target) < 0.002 && abs(value.y - target) < 0.002 && abs(value.z - target) < 0.002
            expect(worst(color) >= ThemeChromePalette.textContrast || extreme, "\(label): the \(role) reaches 4.5:1 or goes all the way to white or black")
            expect(worst(color) >= worst(unadjusted) - 1e-9, "\(label): the \(role) never loses contrast")
            expect(worst(unadjusted) < ThemeChromePalette.textContrast || color == unadjusted, "\(label): a \(role) that already reads keeps its color")
        }
        expect(palette.foregroundPrimary == plain.foregroundPrimary
               && palette.foregroundSecondary == plain.foregroundSecondary && palette.foregroundTertiary == plain.foregroundTertiary
               && palette.minContrastColor == plain.minContrastColor && palette.backgroundExtra == plain.backgroundExtra
               && palette.background == plain.background && palette.focus == plain.focus && palette.hover == plain.hover
               && palette.cutoutColor == plain.cutoutColor && palette.subtitle == plain.subtitle && palette.shaded == plain.shaded
               && palette.shadedDark == plain.shadedDark && palette.contentAppearance?.name == plain.contentAppearance?.name,
               "\(label): only the text and accent change; every other role keeps the side's own color")
    }
    @MainActor static func readableAutomaticText() {
        let light = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
        func worst(_ color: NSColor, _ backgrounds: [SIMD4<Float>]) -> Double {
            ThemeRenderMath.worstContrast(ThemeRenderMath.components(color), over: backgrounds)
        }
        let hexes = ["FAED9E", "8CC7F2", "6B5CDB", "E62633", "008C80", "141F59", "FF8C1A", "33BF4D", "0A0814", "FAF7FC"]
        for appearance in [light, dark] {
            let systemDark = appearance === dark
            for hex in hexes {
                for count in 1...3 {
                    for intensity in [0, 0.1, 0.5, 1] {
                        let theme = SpaceTheme(primaryColor: ThemeColor(hex: hex)!, colorCount: count, intensity: intensity)
                        let label = "\(hex) ×\(count) at \(intensity) on a \(systemDark ? "dark" : "light") Mac"
                        let backgrounds = ThemeRenderMath.chromeBackgrounds(theme: theme, backdropIsDark: systemDark)
                        expect(backgrounds.count == 2 * [1, 3, 6][count - 1],
                               "\(label): the sidebar's color layer is sampled across its gradient over both backdrops")
                        let palette = ThemeChromePalette(theme: theme, appearance: appearance)
                        let plain = ThemeChromePalette(theme: theme, isDark: palette.isDark)
                        let otherBest = worst(palette.isDark ? .black : .white, backgrounds)
                        expect(worst(palette.title, backgrounds) >= min(ThemeChromePalette.textContrast, otherBest) - 1e-9,
                               "\(label): Automatic's text reads at least as well as the other side's best could")
                        checkPushed(palette, plain, backgrounds, label)
                        expect(ThemeSurfaceStyle(theme: theme, appearance: appearance).material.rawValue == (systemDark ? 2 : 1),
                               "\(label): the docked material follows the Mac, like the floating blur")
                        for forced in [SpaceTheme.Appearance.light, .dark] {
                            var pinned = theme; pinned.appearance = forced
                            let forcedPalette = ThemeChromePalette(theme: pinned, appearance: appearance)
                            let forcedPlain = ThemeChromePalette(theme: pinned, isDark: forced == .dark)
                            let pinnedBackgrounds = ThemeRenderMath.chromeBackgrounds(theme: pinned, backdropIsDark: forced == .dark)
                            expect(forcedPalette.isDark == (forced == .dark)
                                   && ThemeSurfaceStyle(theme: pinned, appearance: appearance).material.rawValue == (forced == .dark ? 2 : 1),
                                   "\(label): a Space forced \(forced) keeps its side and material")
                            checkPushed(forcedPalette, forcedPlain, pinnedBackgrounds, "\(label), forced \(forced)")
                        }
                    }
                }
            }
        }
        let single = SpaceTheme(primaryColor: ThemeColor(hex: "6B5CDB")!, colorCount: 1, intensity: 0.5)
        let alpha = ThemeRenderMath.layerAlpha(single), color = ThemeRenderMath.srgb(single.primaryColor!)
        let overContent = ThemeRenderMath.over(SIMD4(color.x, color.y, color.z, alpha),
                                               ThemeRenderMath.over(ThemeRenderMath.underlay(alpha: alpha, isDark: true),
                                                                    ThemeRenderMath.materialOverContrastingContent))
        let sampled = ThemeRenderMath.chromeBackgrounds(theme: single, backdropIsDark: true)
        expect(sampled.count == 2 && abs(sampled[1].x - overContent.x) < 0.002 && abs(sampled[1].y - overContent.y) < 0.002
               && abs(sampled[1].z - overContent.z) < 0.002, "the color layer is also judged over contrasting content showing through the material")
        let triple = SpaceTheme(primaryColor: ThemeColor(hex: "6B5CDB")!, colorCount: 3, intensity: 0.5)
        let tripleAlpha = ThemeRenderMath.layerAlpha(triple), tripleColors = triple.colors.map(ThemeRenderMath.srgb)
        func linear(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func encode(_ v: Float) -> Float { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
        let first = SIMD3(linear(tripleColors[0].x), linear(tripleColors[0].y), linear(tripleColors[0].z))
        let third = SIMD3(linear(tripleColors[2].x), linear(tripleColors[2].y), linear(tripleColors[2].z))
        let stacked = tripleAlpha + tripleAlpha * (1 - tripleAlpha)
        let mixed = (third * tripleAlpha + first * tripleAlpha * (1 - tripleAlpha)) / stacked
        let bottom = ThemeRenderMath.over(SIMD4(encode(mixed.x), encode(mixed.y), encode(mixed.z), stacked),
                                          ThemeRenderMath.over(ThemeRenderMath.underlay(alpha: tripleAlpha, isDark: false), ThemeRenderMath.lightMaterial))
        let tripleSamples = ThemeRenderMath.chromeBackgrounds(theme: triple, backdropIsDark: false)
        expect(tripleSamples.count == 12 && abs(tripleSamples[3].x - bottom.x) < 0.002 && abs(tripleSamples[3].y - bottom.y) < 0.002
               && abs(tripleSamples[3].z - bottom.z) < 0.002,
               "a three-colour Space's overlay is blended in linear light, as the renderer does: \(tripleSamples[3]) vs \(bottom)")
        let purple = SpaceTheme(primaryColor: ThemeColor(red: 0.42, green: 0.36, blue: 0.86)!, colorCount: 2, intensity: 0.1)
        let behind = ThemeRenderMath.chromeBackgrounds(theme: purple, backdropIsDark: false)
        let lightText = ThemeChromePalette(theme: purple, isDark: true).title, darkText = ThemeChromePalette(theme: purple, isDark: false).title
        let base = ThemeRenderMath.srgb(purple.primaryColor!)
        let colorOnly = ThemeRenderMath.contrast(ThemeRenderMath.components(lightText), base)
            >= ThemeRenderMath.contrast(ThemeRenderMath.components(darkText), base)
        expect(colorOnly && worst(lightText, behind) < 1.5,
               "control: choosing by the Space's color alone gives the purple Space light text over its light backdrop")
        let purplePalette = ThemeChromePalette(theme: purple, appearance: light)
        expect(!purplePalette.isDark && worst(purplePalette.title, behind) >= ThemeChromePalette.textContrast,
               "the purple Automatic Space on a light Mac gets dark text that reads")
        let red = SpaceTheme(primaryColor: ThemeColor(red: 0.9, green: 0.15, blue: 0.2)!, colorCount: 2, intensity: 0.5)
        expect(ThemeChromePalette(theme: red, appearance: dark).isDark, "a red Automatic Space on a dark Mac gets light text")
        let colorless = ThemeChromePalette(theme: SpaceTheme(), appearance: dark)
        expect(colorless.isDark && colorless.contentAppearance === dark && colorless.title == ThemeChromePalette(theme: SpaceTheme(), isDark: true).title
               && ThemeRenderMath.chromeBackgrounds(theme: SpaceTheme(), backdropIsDark: true).isEmpty,
               "a colorless Automatic Space keeps the Mac's own appearance and system colors")
    }
    @MainActor static func presetPageOwnership() {
        var windowPage = 0
        func open() -> SpaceThemeEditorView {
            let editor = SpaceThemeEditorView(theme: SpaceTheme(), presetPage: windowPage, performHapticFeedback: {})
            editor.onPresetPageChange = { windowPage = $0 }
            return editor
        }
        let first = open()
        button("Next color presets", in: first).performClick(nil)
        button("Next color presets", in: first).performClick(nil)
        button("Previous color presets", in: first).performClick(nil)
        expect(windowPage == 1, "The window holds the page the editor was left on")
        let second = open()
        expect(button("Previous color presets", in: second).isEnabled && button("Next color presets", in: second).isEnabled,
               "The next editor opens on the window's page")
        button("Previous color presets", in: second).performClick(nil)
        expect(windowPage == 0 && !button("Previous color presets", in: second).isEnabled, "The first page disables Previous")
        let last = SpaceThemeEditorView(theme: SpaceTheme(), presetPage: 4, performHapticFeedback: {})
        expect(!button("Next color presets", in: last).isEnabled && button("Previous color presets", in: last).isEnabled,
               "The last page disables Next")
        for page in [-3, 9] {
            let clamped = SpaceThemeEditorView(theme: SpaceTheme(), presetPage: page, performHapticFeedback: {})
            expect(button("Previous color presets", in: clamped).isEnabled == (page > 0)
                   && button("Next color presets", in: clamped).isEnabled == (page < 0), "An out-of-range page \(page) is clamped")
        }
    }
}
