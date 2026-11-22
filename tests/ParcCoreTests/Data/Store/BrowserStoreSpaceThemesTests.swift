import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceThemesTests {
    @Test @MainActor static func aValidHexSpaceColorIsNormalized() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSpace = store.activeSpaceID
            store.setSpaceTheme(originalSpace, theme: .singleColor(ThemeColor(hex: "a1b2c3")!))
            #expect(store.activeSpace.theme.primaryColor?.hex == "A1B2C3", "A valid hexadecimal Space color must be normalized")
        }
    }

    @Test @MainActor static func aProfileRenameKeepsItsNameWhenEmptyOrUnknownRequestsArrive() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalProfile = store.activeSpace.profileID
            let otherProfile = store.createProfile(name: "Untouched")
            store.renameProfile(originalProfile, name: "Personal research")
            store.renameProfile(originalProfile, name: "")
            store.renameProfile(UUID(), name: "Unknown")
            #expect(store.state.profiles.first { $0.id == originalProfile }?.name == "Personal research", "Empty or unknown profile rename requests must not erase an existing name")
            #expect(store.state.profiles.first { $0.id == otherProfile }?.name == "Untouched", "Renaming a profile must not change another profile")
        }
    }

    @Test @MainActor static func spaceNamesProfileNamesColorsAndPreferencesSurviveRestart() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSpace = store.activeSpaceID
            let originalProfile = store.activeSpace.profileID
            store.renameSpace(originalSpace, name: "Research — 夜空")
            store.renameProfile(originalProfile, name: "Personal research")
            store.setSpaceTheme(originalSpace, theme: .singleColor(ThemeColor(hex: "a1b2c3")!))
            store.setAutoArchiveInterval(.twentyFourHours, for: originalProfile)
            store.updateSettings {
                $0.sidebarWidth = 265
                $0.searchEngine = "https://www.bing.com/search?q="
                $0.restoreSession = true
                $0.onboardingComplete = true
            }
            try store.save()
            let expected = store.state
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state == expected, "Space names, profile names, colors, and preferences must survive a session restart")
            #expect(reopened.activeSpace.name == "Research — 夜空" && reopened.activeSpace.theme.primaryColor?.hex == "A1B2C3", "Unicode Space names and a valid custom color must remain intact")
        }
    }

    @Test(arguments: ["", "123", "1234567", "#112233", "GG1122", "ＡＡ0000"])
    static func invalidHexCannotEnterTheThemeModel(_ invalid: String) {
        #expect(ThemeColor(hex: invalid) == nil)
    }

    @Test(arguments: ["000000", "FFFFFF", "808080", "0123AB", "F20B85", "B9B5D4"])
    static func hslConversionPreservesTheOriginalColor(_ value: String) throws {
        let color = try #require(ThemeColor(hex: value))
        let hsl = color.hsl
        #expect(ThemeColor.hsl(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)?.hex == value)
    }

    private static func expectColor(_ actual: ThemeColor?, _ expected: (Double, Double, Double), _ message: String) throws {
        guard let actual else { throw BrowserStoreTestsSupport.Failure(description: message + " (no color)") }
        #expect(abs(actual.red - expected.0) < 1e-9 && abs(actual.green - expected.1) < 1e-9
                   && abs(actual.blue - expected.2) < 1e-9, Comment(rawValue: message))
    }

    struct HSLCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let hue: Double
        let saturation: Double
        let lightness: Double
        let rgb: (Double, Double, Double)
    }

    @Test(arguments: [
        HSLCase(testDescription: "Red at zero hue", hue: 0, saturation: 1, lightness: 0.5, rgb: (1, 0, 0)),
        HSLCase(testDescription: "Green at one third", hue: 1.0 / 3, saturation: 1, lightness: 0.5, rgb: (0, 1, 0)),
        HSLCase(testDescription: "Negative hue wraps to blue", hue: -1.0 / 3, saturation: 1, lightness: 0.5, rgb: (0, 0, 1)),
        HSLCase(testDescription: "Muted red below midpoint lightness", hue: 2, saturation: 0.5, lightness: 0.25, rgb: (0.375, 0.125, 0.125)),
        HSLCase(testDescription: "Muted red above midpoint lightness", hue: 0, saturation: 0.5, lightness: 0.75, rgb: (0.875, 0.625, 0.625)),
    ])
    static func hslMatchesReferenceRGB(_ color: HSLCase) throws {
        try expectColor(.hsl(hue: color.hue, saturation: color.saturation, lightness: color.lightness), color.rgb, color.testDescription)
    }

    @Test
    static func nonfiniteHueIsRejected() {
        #expect(ThemeColor.hsl(hue: .nan, saturation: 1, lightness: 0.5) == nil, "Nonfinite hue is rejected")
    }

    @Test
    static func outOfRangeRGBIsRejected() {
        #expect(ThemeColor(red: 1.1, green: 0, blue: 0) == nil, "Out-of-range components are rejected")
    }

    @Test
    static func linkedPalettesKeepNearBlackCompanions() {
        let nearBlack = SpaceTheme(primaryColor: ThemeColor(red: 0.0001, green: 0, blue: 0), colorCount: 3)
        #expect(nearBlack.colors.count == 3, "Floating-point saturation at near-black must not drop linked colors")
    }

    struct Palette: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let count: Int
        let wheel: SpaceTheme.Wheel
        let expected: [(Double, Double, Double)]
    }

    @Test(arguments: [
        Palette(testDescription: "Complementary pair", count: 2, wheel: .complimentary, expected: [(0, 1, 1)]),
        Palette(testDescription: "Complementary trio", count: 3, wheel: .complimentary, expected: [(0, 1, 0.5), (0, 0.5, 1)]),
        Palette(testDescription: "Analogous trio", count: 3, wheel: .analogous, expected: [(1, 2.0 / 3, 0), (1, 0, 2.0 / 3)]),
    ])
    static func theColorWheelSelectsItsCompanionHues(_ palette: Palette) throws {
        let theme = SpaceTheme(primaryColor: ThemeColor(hex: "FF0000"), colorCount: palette.count, wheel: palette.wheel)
        for (index, expected) in palette.expected.enumerated() {
            try expectColor(theme.colors[index + 1], expected, palette.testDescription)
        }
    }

    @Test
    static func linkedPalettesPreserveTheOriginalColorSpaceAndPrecision() {
        let wide = ThemeColor(red: 0.83, green: 0.17, blue: 0.29, colorSpace: .displayP3)!
        let theme = SpaceTheme(primaryColor: wide, colorCount: 3, wheel: .analogous)
        #expect(theme.colors.first == wide && theme.colors.allSatisfy { $0.colorSpace == .displayP3 }, "Linked colors must preserve the primary color space and original component precision")
    }

    struct NoiseCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: Double
        let rotating: Bool
        let expected: Double
    }

    @Test(arguments: [
        NoiseCase(testDescription: "Idle noise quantizes", input: 0.127, rotating: false, expected: 0.15),
        NoiseCase(testDescription: "Dragging keeps precision", input: 0.127, rotating: true, expected: 0.127),
        NoiseCase(testDescription: "Infinity leaves noise alone", input: .infinity, rotating: false, expected: 0.127),
        NoiseCase(testDescription: "Noise is capped at one", input: 3, rotating: false, expected: 1),
    ])
    static func noiseGesturesRespectQuantizationAndBounds(_ input: NoiseCase) {
        var theme = SpaceTheme(primaryColor: ThemeColor(hex: "FF0000"), colorCount: 3)
        theme.setNoise(0.127, rotating: true)
        theme.setNoise(input.input, rotating: input.rotating)
        #expect(theme.noise == input.expected)
    }

    @Test
    static func removingThemeColorsResetsModifiersOnlyAfterTheLastColor() {
        let wide = ThemeColor(red: 0.83, green: 0.17, blue: 0.29, colorSpace: .displayP3)!
        var theme = SpaceTheme(primaryColor: wide, colorCount: 3, wheel: .analogous)
        theme.setNoise(1)
        theme.appearance = .dark; theme.texture = .denim; theme.intensity = 0.2
        theme.removeColor(); theme.removeColor()
        #expect(theme.colorCount == 1 && theme.primaryColor == wide, "Removing companions retains primary color")
        theme.removeColor()
        #expect(theme.isValid && theme.colors.isEmpty && theme.noise == 0 && theme.intensity == 0.8
                   && theme.texture == .grain && theme.appearance == .dark, "Removing the final color resets modifiers but preserves appearance")
    }

    @Test @MainActor static func legacySpaceColorMigratesToTheOnlyPersistedThemeWithoutChangingIdentity() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalID = store.activeSpaceID
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var spaces = object["spaces"] as! [[String: Any]]
            spaces[0].removeValue(forKey: "theme"); spaces[0]["color"] = "a1b2c3"
            object["spaces"] = spaces
            try JSONSerialization.data(withJSONObject: object).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            #expect(migrated.activeSpaceID == originalID && migrated.activeSpace.theme.primaryColor?.hex == "A1B2C3"
                       && migrated.activeSpace.theme.colorCount == 1, "Legacy Space color migrates without changing identity or RGB values")
            try migrated.save()
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let savedSpaces = saved["spaces"] as! [[String: Any]]
            #expect(savedSpaces.allSatisfy { $0["color"] == nil && $0["theme"] != nil }, "Theme is the only persisted source of color state after migration")
        }
    }

    private static let detailedTheme = SpaceTheme(primaryColor: ThemeColor(red: 0.9, green: 0.3, blue: 0.4, colorSpace: .displayP3),
        colorCount: 3, wheel: .analogous, appearance: .dark, noise: 0.35, intensity: 0.63, texture: .tweed)

    @Test @MainActor static func editingAnInactiveSpaceThemeDoesNotSwitchOrRecolorTheActiveSpace() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let migrated = try BrowserStore(directory: directory)
            let target = migrated.activeSpaceID
            let other = migrated.createSpace(name: "Other", color: "aabbcc")
            let untouched = migrated.activeSpace.theme
            #expect(migrated.setSpaceTheme(target, theme: detailedTheme), "Valid theme update targets the captured Space")
            #expect(migrated.activeSpaceID == other && migrated.activeSpace.theme == untouched, "Editing another Space must not switch or recolor the active Space")
        }
    }

    @Test @MainActor static func allThemeComponentsSurviveRestart() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let migrated = try BrowserStore(directory: directory)
            try #require(migrated.setSpaceTheme(migrated.activeSpaceID, theme: detailedTheme))
            try migrated.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state == migrated.state, "All theme components and other Space state survive restart")
        }
    }

    enum ThemeDamage: CaseIterable { case tooManyColors, nonfiniteNoise, missingPrimaryColor, unknownSpace }

    @Test(arguments: ThemeDamage.allCases) @MainActor static func invalidThemeUpdatesDoNotChangeTheSession(_ damage: ThemeDamage) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let original = store.state
            var space = store.activeSpaceID
            var theme = detailedTheme
            switch damage {
            case .tooManyColors: theme.colorCount = 4
            case .nonfiniteNoise: theme.noise = .nan
            case .missingPrimaryColor: theme.primaryColor = nil
            case .unknownSpace: space = UUID()
            }
            #expect(!store.setSpaceTheme(space, theme: theme))
            #expect(store.state == original)
        }
    }

    @Test @MainActor static func invalidPersistedThemesAreRejectedWithoutRewritingTheFile() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try #require(store.setSpaceTheme(store.activeSpaceID, theme: detailedTheme))
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let savedSpaces = saved["spaces"] as! [[String: Any]]
            var broken = saved, brokenSpaces = savedSpaces
            var badTheme = brokenSpaces[0]["theme"] as! [String: Any]
            badTheme["intensity"] = 1.1; brokenSpaces[0]["theme"] = badTheme
            broken["spaces"] = brokenSpaces
            let badData = try JSONSerialization.data(withJSONObject: broken)
            try badData.write(to: file)
            var rejected = false
            do { _ = try BrowserStore(directory: directory) } catch { rejected = true }
            #expect(try rejected && (try Data(contentsOf: file)) == badData, "Invalid persisted themes surface an error and preserve the original session bytes")
        }
    }
}
