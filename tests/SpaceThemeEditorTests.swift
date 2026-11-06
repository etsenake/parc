import Foundation

@main
struct SpaceThemeEditorTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
        assertions += 1
        guard condition() else { fatalError("Line \(line): \(message)") }
    }
    static func near(_ a: Double, _ b: Double, _ message: String, line: Int = #line) {
        expect(abs(a - b) < 0.000001, message, line: line)
    }
    static func main() {
        blankPadAndLimits()
        gesturesAndUndo()
        loadedColorsAndAppearance()
        presetsAndCoordinates()
        textureAndValueControls()
        print("Space theme editor: \(assertions) assertions passed")
    }
    static func blankPadAndLimits() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        expect(!editor.canAddColor && !editor.canRemoveColor, "blank editor disables count actions")
        expect(!editor.addColor() && !editor.removeColor(), "blank count action is a no-op")
        expect(!editor.moveColor(x: .nan, y: 0), "invalid coordinate rejected")
        expect(!editor.moveColor(x: 0, y: .infinity), "infinite coordinate rejected")
        expect(!editor.canUndo, "rejected operations do not create undo history")
        editor.beginGesture(); editor.moveColor(x: 0.99, y: 0); editor.finishGesture()
        expect(editor.theme.colorCount == 1, "blank drag establishes one color")
        expect(editor.theme.primaryColor?.colorSpace == .displayP3, "pad constructs Display P3")
        near(editor.theme.primaryColor!.hsl.lightness, 0.97, "outer edge has maximum lightness")
        expect(editor.addColor() && editor.addColor(), "two additional linked colors")
        expect(editor.theme.colors.count == 3 && !editor.canAddColor, "three-color limit")
        expect(!editor.addColor(), "cannot exceed three colors")
        editor.removeColor(); editor.removeColor()
        expect(editor.theme.wheel == .complimentary, "one-color removal resets harmony")
        editor.setNoise(0.5, gesture: .slider); editor.setIntensity(0.3); editor.cycleTexture()
        expect(editor.removeColor(), "last color removed")
        expect(editor.theme == SpaceTheme(), "last removal resets modifiers and primary")
        near(editor.lightnessRange.lowerBound, 0.01, "last removal resets lower range")
        near(editor.lightnessRange.upperBound, 0.97, "last removal resets upper range")
        editor.undo()
        expect(editor.theme.colorCount == 1 && editor.theme.noise == 0.5, "undo last removal restores complete snapshot")
    }
    static func gesturesAndUndo() {
        let initial = SpaceTheme.singleColor(ThemeColor(hex: "B9D4E8")!)
        let editor = SpaceThemeEditorState(theme: initial)
        editor.beginGesture(); editor.beginGesture()
        for index in 0...20 { editor.moveColor(x: Double(index) / 30, y: 0.2) }
        expect(!editor.canUndo, "drag previews have not registered independent undo steps")
        let final = editor.theme
        expect(editor.finishGesture(), "changed gesture commits once")
        expect(!editor.finishGesture(), "finish twice cannot create duplicate undo")
        expect(editor.undo(), "undo changed gesture")
        expect(editor.theme == initial && !editor.canUndo, "whole drag restores initial theme in one step")
        expect(editor.redo() && editor.theme == final, "redo restores final drag")
        editor.undo(); editor.addColor()
        expect(!editor.canRedo, "new branch clears redo")
        let before = editor.theme
        editor.beginGesture(); editor.setIntensity(before.intensity)
        expect(!editor.finishGesture(), "no-change gesture creates no transaction")
        editor.undo()
        expect(editor.theme == initial, "no-change finish does not obscure preceding undo")
        editor.beginGesture(); editor.setNoise(0.4, gesture: .rotation)
        expect(editor.undo(), "undo first flushes an active gesture")
        expect(editor.theme == initial, "undo active gesture restores baseline")
    }
    static func loadedColorsAndAppearance() {
        let outside = ThemeColor.hsl(hue: 0.25, saturation: 0.8, lightness: 0.2, colorSpace: .displayP3)!
        var theme = SpaceTheme.singleColor(outside); theme.appearance = .light
        let forced = SpaceThemeEditorState(theme: theme)
        expect(forced.theme == theme, "opening editor never changes stored color")
        near(forced.lightnessRange.lowerBound, 0.2, "forced range expands to include darker existing color")
        near(forced.lightnessRange.upperBound, 0.97, "forced light maximum")
        theme.appearance = .dark
        let dark = SpaceThemeEditorState(theme: theme)
        expect(dark.theme == theme, "legacy persisted dark mode is preserved without migration")
        near(dark.lightnessRange.lowerBound, 0.01, "persisted dark minimum")
        near(dark.lightnessRange.upperBound, 0.425, "persisted dark maximum")
    }
    static func presetsAndCoordinates() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        let preset = ThemeColor(red: 0.82399999, green: 0.46100002, blue: 0.64, colorSpace: .displayP3)!
        editor.selectPreset(preset, colorCount: 3, wheel: .analogous)
        expect(editor.theme.primaryColor == preset, "preset retains component precision")
        expect(editor.theme.colorCount == 3 && editor.theme.wheel == .analogous, "gradient preset carries native count and harmony")
        let pos = editor.normalizedPosition(for: preset)
        editor.beginGesture(); editor.moveColor(x: pos.x, y: pos.y); editor.finishGesture()
        near(editor.theme.primaryColor!.red, preset.red, "pad inverse round trip red")
        near(editor.theme.primaryColor!.green, preset.green, "pad inverse round trip green")
        near(editor.theme.primaryColor!.blue, preset.blue, "pad inverse round trip blue")
        expect(!editor.selectPreset(preset, colorCount: 4, wheel: .complimentary), "invalid preset count rejected")
        let before = editor.theme
        editor.removeAllColors()
        expect(editor.theme.primaryColor == nil && editor.theme.colorCount == 0, "delete all colors")
        editor.undo(); expect(editor.theme == before, "delete all undo restores gradient")
        let white = ThemeColor(hex: "FFFFFF")!
        editor.selectPreset(white, colorCount: 1, wheel: .complimentary)
        expect(editor.theme.primaryColor == white, "white preset is not silently clipped to pad maximum")
        editor.beginGesture(); editor.moveColor(x: 100, y: -100); editor.finishGesture()
        expect(editor.theme.primaryColor!.hsl.lightness <= 0.9700001, "outside drag clamps radial lightness")
    }
    static func textureAndValueControls() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.cycleTexture()
        expect(editor.theme.texture == .grain && editor.theme.noise == 0.8, "zero-noise click enables current texture at .8")
        for texture in [SpaceTheme.Texture.sand, .denim, .tweed] {
            editor.cycleTexture(); expect(editor.theme.texture == texture && editor.theme.noise == 0.8, "texture sequence")
        }
        editor.cycleTexture()
        expect(editor.theme.texture == .grain && editor.theme.noise == 0, "last texture cycles to off")
        editor.setNoise(0.126, gesture: .slider); near(editor.theme.noise, 0.15, "nonrotation quantizes twentieths")
        editor.setNoise(0.126, gesture: .rotation); near(editor.theme.noise, 0.126, "rotation remains continuous")
        editor.setNoise(-2, gesture: .rotation); near(editor.theme.noise, 0, "noise low clamp")
        editor.setNoise(4, gesture: .slider); near(editor.theme.noise, 1, "noise high clamp")
        let before = editor.theme
        expect(!editor.setNoise(.infinity, gesture: .rotation), "invalid noise rejected")
        expect(!editor.setIntensity(.nan), "invalid intensity rejected")
        expect(editor.theme == before, "invalid modifiers leave state intact")
        editor.setIntensity(0.123456); near(editor.theme.intensity, 0.123456, "intensity is continuous")
        editor.setIntensity(-1); near(editor.theme.intensity, 0, "intensity low clamp")
        editor.setIntensity(2); near(editor.theme.intensity, 1, "intensity high clamp")
        expect(editor.theme.isValid, "edited theme remains valid")
    }
}
