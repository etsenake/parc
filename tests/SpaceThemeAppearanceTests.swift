import AppKit

/// Inert production-view checks: no browser, visible window, engine or real profile.
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
    @MainActor static func main() {
        _ = NSApplication.shared
        let originalAppearance = NSApp.appearance
        let suite = "Parc.SpaceThemeAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { NSApp.appearance = originalAppearance; defaults.removePersistentDomain(forName: suite) }

        AppAppearance.apply(.dark, defaults: defaults)
        var theme = SpaceTheme.singleColor(ThemeColor(hex: "4C6688")!)
        theme.appearance = .light // Preserve old saved themes without using them as the app choice.
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
        // Onboarding replay previews light/dark without saving it until Finish.
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
        print("Space theme appearance: \(assertions) assertions passed")
    }
    ///
    /// so a later editor opens where the last one was left.
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
