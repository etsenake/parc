import AppKit
import Testing
import ParcCore
@testable import Parc

struct SpaceThemeRenderingTests {
    @Test(arguments: [true, false])
    @MainActor func coloredChromeChoosesReadableTextIndependentlyOfTheBackdrop(darkColor: Bool) throws {
        let color = try #require(ThemeColor(hex: darkColor ? "0A0814" : "FAF7FC"))
        let theme = SpaceTheme.singleColor(color)
        let opposite = try #require(NSAppearance(named: darkColor ? .aqua : .darkAqua))
        let palette = ThemeChromePalette(theme: theme, appearance: opposite)
        #expect(palette.isDark == darkColor)
        #expect(ThemeSurfaceStyle(theme: theme, appearance: opposite).backgroundIsDark != darkColor)
    }

    @Test(arguments: [true, false])
    @MainActor func anUncoloredSpaceKeepsTheInheritedAppearance(dark: Bool) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        let theme = SpaceTheme()
        #expect(ThemeChromePalette(theme: theme, appearance: appearance).contentAppearance === appearance)
        #expect(ThemeSurfaceStyle(theme: theme, appearance: appearance).backgroundIsDark == dark)
    }

    @Test(arguments: [true, false])
    @MainActor func missingColorRenderingUsesANativeBackdropThatMatchesTheChrome(dark: Bool) throws {
        let color = try #require(ThemeColor(hex: dark ? "0A0814" : "FAF7FC"))
        let theme = SpaceTheme.singleColor(color)
        let opposite = try #require(NSAppearance(named: dark ? .aqua : .darkAqua))
        let fallback = ThemeSurfaceStyle(theme: theme, appearance: opposite, colorRenderingAvailable: false)
        #expect(fallback.backgroundIsDark == dark)
    }

    @Test(arguments: [1, 2, 3])
    func onlyAThreeColorThemeAddsASeparateOverlay(count: Int) throws {
        let color = try #require(ThemeColor(hex: "4C6688"))
        let theme = SpaceTheme(primaryColor: color, colorCount: count)
        let config = ThemeGradientUniforms(theme: theme, backgroundIsDark: false, pointSize: CGSize(width: 800, height: 400))
        #expect(config.parameters.y == Float(min(count, 2)))
        #expect(config.parameters.z == (count == 3 ? 2 : 0))
        if count == 3 {
            #expect(config.overlay0.w == 0 && config.overlay1.w == 1)
        }
    }

    @Test func gradientAndChromeAgreeOnTheMidToneUnderlay() throws {
        let theme = SpaceTheme(primaryColor: ThemeColor(hex: "6B5CDB"), colorCount: 2, intensity: 0.5)
        let config = ThemeGradientUniforms(theme: theme, backgroundIsDark: true, pointSize: CGSize(width: 800, height: 400))
        let reading = try #require(ThemeRenderMath.chromeReading(theme: theme, backdropIsDark: true))
        #expect(config.underlay == reading.underlay)
    }

    @Test(arguments: [(SpaceTheme.Texture.grain, Float(0.8)),
                      (.sand, 0.15), (.denim, 0.6), (.tweed, 0.4)])
    func inactiveTexturesUseAQuarterOfTheActiveStrength(example: (SpaceTheme.Texture, Float)) throws {
        var theme = SpaceTheme.singleColor(try #require(ThemeColor(hex: "4C6688")))
        theme.noise = 0.5
        theme.texture = example.0
        let size = CGSize(width: 800, height: 400)
        let crop = SIMD4<Float>(0, 0, 0.3, 1)
        let active = ThemeOutputUniforms(theme: theme, isActive: true, pointSize: size, sampleRect: crop, hasTexture: true)
        let inactive = ThemeOutputUniforms(theme: theme, isActive: false, pointSize: size, sampleRect: crop, hasTexture: true)
        #expect(abs(active.parameters.z - example.1 / 2) < 0.00001)
        #expect(abs(inactive.parameters.z - active.parameters.z / 4) < 0.00001)
    }

    @Test func aFloatingSurfaceSamplesTheSameFullWindowTextureCoordinates() {
        let crop = SIMD4<Float>(0.1, 0.25, 0.3, 0.5)
        let config = ThemeOutputUniforms(theme: SpaceTheme(), isActive: true, pointSize: CGSize(width: 800, height: 400),
                                        sampleRect: crop, hasTexture: false)
        #expect(config.sampleRect == crop)
        #expect(config.parameters.x == 8 && config.parameters.y == 4)
    }

    @Test @MainActor func identicalHandlePositionsDoNotRestartTheirSpring() throws {
        let handle = CALayer()
        handle.position = CGPoint(x: 10, y: 10)
        let target = CGPoint(x: 100, y: 20)
        ThemeColorPadMotion.update(handle, position: target, scale: 1.1, animatePosition: true, allowsMotion: true)
        let first = try #require(handle.animation(forKey: "position") as? CASpringAnimation)
        ThemeColorPadMotion.update(handle, position: target, scale: 1.1, animatePosition: true, allowsMotion: true)
        let current = try #require(handle.animation(forKey: "position") as? CASpringAnimation)
        #expect(first.fromValue as? NSValue == current.fromValue as? NSValue)
        #expect(current.fromValue as? NSValue == NSValue(point: CGPoint(x: 10, y: 10)))
    }

    @Test @MainActor func disablingMotionSettlesTheHandleAtItsNewPosition() {
        let handle = CALayer()
        handle.position = CGPoint(x: 10, y: 10)
        ThemeColorPadMotion.update(handle, position: CGPoint(x: 100, y: 20), scale: 1.1, animatePosition: true, allowsMotion: true)
        let target = CGPoint(x: 30, y: 30)
        ThemeColorPadMotion.update(handle, position: target, scale: 1, animatePosition: true, allowsMotion: false)
        #expect(handle.animationKeys()?.isEmpty != false)
        #expect(handle.position == target)
    }
}

struct SpaceThemeUndoTests {
    @MainActor private struct ChangeFixture {
        let store: BrowserStore
        let change: SpaceThemeChange
        let history: FolderUndoManager

        init(directory: URL) throws {
            store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            history = FolderUndoManager()
            let space = store.activeSpace
            let goal = SpaceTheme.singleColor(try #require(ThemeColor(hex: "4C6688")))
            let saved = try store.saveSpaceTheme(spaceID: space.id, profileID: space.profileID, previous: space.theme, theme: goal)
            change = try #require(saved)
        }

        func append(available: @escaping () -> Bool = { true }, onApplied: @escaping () -> Void = {}) {
            #expect(history.appendSpaceThemeChange(change, store: store, available: available, onApplied: onApplied,
                                                   onError: { Issue.record("The theme edit failed: \($0)") }))
        }
    }

    @MainActor private func withChange(_ body: (ChangeFixture) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(ChangeFixture(directory: directory))
    }

    @Test @MainActor func undoDurablyRestoresTheOriginalThemeAfterTheEditorIsGone() throws {
        try withChange { fixture in
            fixture.append()
            fixture.history.undo()
            let reopened = try BrowserStore(directory: fixture.store.directory)
            #expect(reopened.state.spaces.first { $0.id == fixture.change.spaceID }?.theme == fixture.change.previousTheme)
            #expect(fixture.history.canRedo)
        }
    }

    @Test @MainActor func redoReappliesTheThemeAndRefreshesItsOwner() throws {
        try withChange { fixture in
            var refreshed = 0
            fixture.append(onApplied: { refreshed += 1 })
            fixture.history.undo()
            fixture.history.redo()
            #expect(fixture.store.activeSpace.theme == fixture.change.theme)
            #expect(refreshed == 2)
        }
    }

    @Test @MainActor func windowUnavailabilityDoesNotDiscardTheInverse() throws {
        try withChange { fixture in
            var canApply = false
            fixture.append(available: { canApply })
            #expect(!fixture.history.canUndo)
            canApply = true
            #expect(fixture.history.canUndo)
        }
    }

    @Test @MainActor func aCompetingThemeEditInvalidatesTheOldInverse() throws {
        try withChange { fixture in
            fixture.append()
            let other = SpaceTheme.singleColor(try #require(ThemeColor(hex: "DDAACC")))
            let change = fixture.change
            _ = try fixture.store.saveSpaceTheme(spaceID: change.spaceID, profileID: change.profileID,
                                                 previous: change.theme, theme: other)
            #expect(!fixture.history.canUndo)
            #expect(fixture.store.activeSpace.theme == other)
        }
    }

    @Test @MainActor func undoFollowsTheOriginalSpaceWithoutChangingTheSelection() throws {
        try withChange { fixture in
            fixture.append()
            fixture.store.renameSpace(fixture.change.spaceID, name: "Renamed Space")
            let destination = fixture.store.createSpace(name: "Other Space")
            fixture.history.undo()
            let changed = try #require(fixture.store.state.spaces.first { $0.id == fixture.change.spaceID })
            #expect(changed.name == "Renamed Space")
            #expect(changed.theme == fixture.change.previousTheme)
            #expect(fixture.store.activeSpace.id == destination)
        }
    }
}

extension SpaceThemeRenderingTests {
    @Test(arguments: ["FAED9E", "6B5CDB", "E62633", "008C80", "0A0814", "FAF7FC"], [false, true])
    @MainActor func automaticThemeInkRemainsReadableOverTheActualBackdrop(hex: String, dark: Bool) throws {
        let theme = SpaceTheme(primaryColor: ThemeColor(hex: hex), colorCount: 3, intensity: 0.5)
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        let palette = ThemeChromePalette(theme: theme, appearance: appearance)
        let backgrounds = ThemeRenderMath.chromeBackgrounds(theme: theme, backdropIsDark: dark)
        let alternate = try #require(ThemeRenderMath.sideReading(theme: theme, backdropIsDark: dark, isDark: !palette.isDark))
        let contrast = ThemeRenderMath.worstContrast(ThemeRenderMath.components(palette.title), over: backgrounds)
        #expect(contrast >= min(ThemeChromePalette.textContrast, alternate.contrast) - 0.000001)
    }

    @Test(arguments: [false, true])
    @MainActor func forcedAppearanceControlsBothThePaletteAndTheBackdrop(dark: Bool) throws {
        var theme = SpaceTheme.singleColor(try #require(ThemeColor(hex: "4C6688")))
        theme.appearance = dark ? .dark : .light
        let appearance = try #require(NSAppearance(named: dark ? .aqua : .darkAqua))
        #expect(ThemeChromePalette(theme: theme, appearance: appearance).isDark == dark)
        #expect(ThemeSurfaceStyle(theme: theme, appearance: appearance).backgroundIsDark == dark)
    }
}

extension SpaceThemeUndoTests {
    @Test @MainActor func aFailedInverseStaysAvailableForRetry() throws {
        try withChange { fixture in
            let directory = fixture.store.directory
            var failures = 0
            #expect(fixture.history.appendSpaceThemeChange(fixture.change, store: fixture.store, available: { true },
                                                           onApplied: {}, onError: { _ in failures += 1 }))
            try FileManager.default.removeItem(at: directory)
            try Data().write(to: directory)
            fixture.history.undo()
            #expect(failures == 1)
            #expect(fixture.store.activeSpace.theme == fixture.change.theme)
            #expect(fixture.history.canUndo && !fixture.history.canRedo)
            try FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            fixture.history.undo()
            #expect(fixture.store.activeSpace.theme == fixture.change.previousTheme)
        }
    }

    @Test @MainActor func aNoOpThemeSaveKeepsRedoAvailable() throws {
        try withChange { fixture in
            fixture.append()
            fixture.history.undo()
            let change = fixture.change
            let noOp = try fixture.store.saveSpaceTheme(spaceID: change.spaceID, profileID: change.profileID,
                                                        previous: change.previousTheme, theme: change.previousTheme)
            #expect(noOp == nil)
            #expect(fixture.history.canRedo)
        }
    }
}
