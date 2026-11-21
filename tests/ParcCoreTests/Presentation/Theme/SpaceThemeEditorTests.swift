import Testing
@testable import ParcCore

struct SpaceThemeEditorTests {
    func near(_ a: Double, _ b: Double, _ message: Comment, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a - b) < 0.000001, message, sourceLocation: sourceLocation)
    }

    @Test func aBlankEditorDisablesCountActions() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        #expect(!editor.canAddColor && !editor.canRemoveColor)
        #expect(!editor.addColor() && !editor.removeColor())
    }

    @Test func invalidCoordinatesAreRejectedWithoutUndoHistory() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        #expect(!editor.moveColor(x: .nan, y: 0))
        #expect(!editor.moveColor(x: 0, y: .infinity))
        #expect(!editor.canUndo)
    }

    @Test func aBlankDragEstablishesOneDisplayP3Color() throws {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.beginGesture(); editor.moveColor(x: 0.99, y: 0); editor.finishGesture()
        #expect(editor.theme.colorCount == 1)
        let primary = try #require(editor.theme.primaryColor)
        #expect(primary.colorSpace == .displayP3)
        near(primary.hsl.lightness, 0.97, "outer edge has maximum lightness")
    }

    @Test func aThemeHoldsAtMostThreeColors() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.beginGesture(); editor.moveColor(x: 0.99, y: 0); editor.finishGesture()
        #expect(editor.addColor() && editor.addColor())
        #expect(editor.theme.colors.count == 3 && !editor.canAddColor)
        #expect(!editor.addColor())
    }

    @Test func removingDownToOneColorResetsTheHarmony() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.beginGesture(); editor.moveColor(x: 0.99, y: 0); editor.finishGesture()
        editor.addColor(); editor.addColor()
        editor.removeColor(); editor.removeColor()
        #expect(editor.theme.wheel == .complimentary)
    }

    @Test func removingTheLastColorResetsModifiersAndRange() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.beginGesture(); editor.moveColor(x: 0.99, y: 0); editor.finishGesture()
        editor.setNoise(0.5, gesture: .slider); editor.setIntensity(0.3); editor.cycleTexture()
        #expect(editor.removeColor())
        #expect(editor.theme == SpaceTheme())
        near(editor.lightnessRange.lowerBound, 0.01, "last removal resets lower range")
        near(editor.lightnessRange.upperBound, 0.97, "last removal resets upper range")
    }

    @Test func undoingTheLastRemovalRestoresTheCompleteSnapshot() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.beginGesture(); editor.moveColor(x: 0.99, y: 0); editor.finishGesture()
        editor.setNoise(0.5, gesture: .slider)
        editor.removeColor()
        editor.undo()
        #expect(editor.theme.colorCount == 1 && editor.theme.noise == 0.5)
    }

    @Test func aWholeDragIsOneUndoStepAndRedoRestoresIt() {
        let initial = SpaceTheme.singleColor(ThemeColor(hex: "B9D4E8")!)
        let editor = SpaceThemeEditorState(theme: initial)
        editor.beginGesture(); editor.beginGesture()
        for index in 0...20 { editor.moveColor(x: Double(index) / 30, y: 0.2) }
        #expect(!editor.canUndo)
        let final = editor.theme
        #expect(editor.finishGesture())
        #expect(!editor.finishGesture())
        #expect(editor.undo())
        #expect(editor.theme == initial && !editor.canUndo)
        #expect(editor.redo() && editor.theme == final)
    }

    @Test func aNewEditAfterUndoClearsRedo() {
        let initial = SpaceTheme.singleColor(ThemeColor(hex: "B9D4E8")!)
        let editor = SpaceThemeEditorState(theme: initial)
        editor.beginGesture(); editor.moveColor(x: 0.2, y: 0.2); editor.finishGesture()
        editor.undo(); editor.addColor()
        #expect(!editor.canRedo)
    }

    @Test func aNoChangeGestureCreatesNoTransaction() {
        let initial = SpaceTheme.singleColor(ThemeColor(hex: "B9D4E8")!)
        let editor = SpaceThemeEditorState(theme: initial)
        editor.beginGesture(); editor.moveColor(x: 0.2, y: 0.2); editor.finishGesture()
        editor.undo(); editor.addColor()
        let before = editor.theme
        editor.beginGesture(); editor.setIntensity(before.intensity)
        #expect(!editor.finishGesture())
        editor.undo()
        #expect(editor.theme == initial)
    }

    @Test func undoFirstFlushesAnActiveGesture() {
        let initial = SpaceTheme.singleColor(ThemeColor(hex: "B9D4E8")!)
        let editor = SpaceThemeEditorState(theme: initial)
        editor.beginGesture(); editor.setNoise(0.4, gesture: .rotation)
        #expect(editor.undo())
        #expect(editor.theme == initial)
    }

    @Test func openingTheEditorNeverChangesAStoredColorAndExpandsAForcedLightRange() {
        let outside = ThemeColor.hsl(hue: 0.25, saturation: 0.8, lightness: 0.2, colorSpace: .displayP3)!
        var theme = SpaceTheme.singleColor(outside); theme.appearance = .light
        let forced = SpaceThemeEditorState(theme: theme)
        #expect(forced.theme == theme)
        near(forced.lightnessRange.lowerBound, 0.2, "forced range expands to include darker existing color")
        near(forced.lightnessRange.upperBound, 0.97, "forced light maximum")
    }

    @Test func aLegacyPersistedDarkModeIsPreservedWithoutMigration() {
        let outside = ThemeColor.hsl(hue: 0.25, saturation: 0.8, lightness: 0.2, colorSpace: .displayP3)!
        var theme = SpaceTheme.singleColor(outside); theme.appearance = .dark
        let dark = SpaceThemeEditorState(theme: theme)
        #expect(dark.theme == theme)
        near(dark.lightnessRange.lowerBound, 0.01, "persisted dark minimum")
        near(dark.lightnessRange.upperBound, 0.425, "persisted dark maximum")
    }

    @Test func aGradientPresetCarriesItsNativeCountHarmonyAndPrecision() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        let preset = ThemeColor(red: 0.82399999, green: 0.46100002, blue: 0.64, colorSpace: .displayP3)!
        editor.selectPreset(preset, colorCount: 3, wheel: .analogous)
        #expect(editor.theme.primaryColor == preset)
        #expect(editor.theme.colorCount == 3 && editor.theme.wheel == .analogous)
    }

    @Test func thePadInverseRoundTripsAPreset() throws {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        let preset = ThemeColor(red: 0.82399999, green: 0.46100002, blue: 0.64, colorSpace: .displayP3)!
        editor.selectPreset(preset, colorCount: 3, wheel: .analogous)
        let pos = editor.normalizedPosition(for: preset)
        editor.beginGesture(); editor.moveColor(x: pos.x, y: pos.y); editor.finishGesture()
        let primary = try #require(editor.theme.primaryColor)
        near(primary.red, preset.red, "pad inverse round trip red")
        near(primary.green, preset.green, "pad inverse round trip green")
        near(primary.blue, preset.blue, "pad inverse round trip blue")
    }

    @Test func anInvalidPresetCountIsRejected() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        let preset = ThemeColor(red: 0.82399999, green: 0.46100002, blue: 0.64, colorSpace: .displayP3)!
        #expect(!editor.selectPreset(preset, colorCount: 4, wheel: .complimentary))
    }

    @Test func deletingAllColorsCanBeUndone() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        let preset = ThemeColor(red: 0.82399999, green: 0.46100002, blue: 0.64, colorSpace: .displayP3)!
        editor.selectPreset(preset, colorCount: 3, wheel: .analogous)
        let before = editor.theme
        editor.removeAllColors()
        #expect(editor.theme.primaryColor == nil && editor.theme.colorCount == 0)
        editor.undo()
        #expect(editor.theme == before)
    }

    @Test func aWhitePresetIsNotClippedAndAnOutsideDragClampsRadialLightness() throws {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        let white = ThemeColor(hex: "FFFFFF")!
        editor.selectPreset(white, colorCount: 1, wheel: .complimentary)
        #expect(editor.theme.primaryColor == white)
        editor.beginGesture(); editor.moveColor(x: 100, y: -100); editor.finishGesture()
        let primary = try #require(editor.theme.primaryColor)
        #expect(primary.hsl.lightness <= 0.9700001)
    }

    @Test func aZeroNoiseClickEnablesTheCurrentTexture() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.cycleTexture()
        #expect(editor.theme.texture == .grain && editor.theme.noise == 0.8)
    }

    @Test func texturesCycleInOrderThenTurnOff() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.cycleTexture()
        for texture in [SpaceTheme.Texture.sand, .denim, .tweed] {
            editor.cycleTexture()
            #expect(editor.theme.texture == texture && editor.theme.noise == 0.8)
        }
        editor.cycleTexture()
        #expect(editor.theme.texture == .grain && editor.theme.noise == 0)
    }

    @Test func noiseQuantizesToTwentiethsExceptWhileRotating() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.setNoise(0.126, gesture: .slider)
        near(editor.theme.noise, 0.15, "nonrotation quantizes twentieths")
        editor.setNoise(0.126, gesture: .rotation)
        near(editor.theme.noise, 0.126, "rotation remains continuous")
    }

    @Test func noiseClampsToZeroAndOne() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.setNoise(-2, gesture: .rotation)
        near(editor.theme.noise, 0, "noise low clamp")
        editor.setNoise(4, gesture: .slider)
        near(editor.theme.noise, 1, "noise high clamp")
    }

    @Test func invalidModifiersAreRejectedAndLeaveStateIntact() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.setNoise(0.5, gesture: .slider)
        let before = editor.theme
        #expect(!editor.setNoise(.infinity, gesture: .rotation))
        #expect(!editor.setIntensity(.nan))
        #expect(editor.theme == before)
    }

    @Test func intensityIsContinuousAndClamped() {
        let editor = SpaceThemeEditorState(theme: SpaceTheme())
        editor.setIntensity(0.123456)
        near(editor.theme.intensity, 0.123456, "intensity is continuous")
        editor.setIntensity(-1)
        near(editor.theme.intensity, 0, "intensity low clamp")
        editor.setIntensity(2)
        near(editor.theme.intensity, 1, "intensity high clamp")
        #expect(editor.theme.isValid)
    }
}
