import AppKit
import Testing
@testable import Parc

@MainActor
struct CommandBarPaletteTests {
    typealias Support = CommandBarTestSupport

    static func pinkTheme() -> SpaceTheme {
        let pink = NSColor(colorSpace: .extendedSRGB, components: [1.0698519945144653, 0.5164691805839539, 0.7590587735176086, 1], count: 4)
            .usingColorSpace(.displayP3)!
        return SpaceTheme.singleColor(ThemeColor(red: Double(pink.redComponent), green: Double(pink.greenComponent),
                                                 blue: Double(pink.blueComponent), colorSpace: .displayP3)!)
    }

    static let neutralDark = SIMD4<Double>(0.356, 0.356, 0.356, 0.8075)
    static let neutralLight = SIMD4<Double>(0.6, 0.6, 0.6, 1)

    var palette: CommandBarPalette { CommandBarPalette(theme: Self.pinkTheme()) }
    var neutral: CommandBarPalette { CommandBarPalette(theme: SpaceTheme()) }

    @Test func theCentredBarFollowsTheApp() {
        #expect(CommandBarPalette.panelAppearance(inlineEmpty: false, space: Support.light, window: nil) == nil)
    }

    @Test func aDarkWindowKeepsItsBarDark() {
        let dark = Support.dark
        #expect(CommandBarPalette.panelAppearance(inlineEmpty: false, space: Support.light, window: dark) === dark)
    }

    @Test func theEmptySidebarBarTakesTheSpacesAppearance() {
        let light = Support.light
        #expect(CommandBarPalette.panelAppearance(inlineEmpty: true, space: light, window: Support.dark) === light)
    }

    @Test func aSpaceWithoutAnAppearanceLeavesTheWindowsOwn() {
        let dark = Support.dark
        #expect(CommandBarPalette.panelAppearance(inlineEmpty: true, space: nil, window: dark) === dark)
    }

    @Test func darkSelectionIsTheThemesSemanticFocus() {
        #expect(Support.near(Support.rgba(palette.selected, in: Support.dark), SIMD4(0.801, 0.080, 0.444, 0.8075)))
    }

    @Test func lightSelectionIsTheLightFocus() {
        #expect(Support.near(Support.rgba(palette.selected, in: Support.light), SIMD4(0.877, 0.428, 0.654, 1)))
    }

    @Test func fieldTextSelectionIsThePaletteSubtitle() {
        #expect(Support.near(Support.rgba(palette.inputSelection, in: Support.dark), SIMD4(1.019 * 0.5, 0.903 * 0.5, 0.951 * 0.5, 1)))
    }

    @Test func theFieldIconIsMaxContrast() {
        #expect(Support.near(Support.rgba(palette.inputIcon, in: Support.dark), SIMD4(1.019, 0.903, 0.951, 1)))
    }

    @Test func thePillsDefaultColourIsFocus() {
        #expect(Support.near(Support.rgba(palette.scopePill, in: Support.dark), Support.rgba(palette.selected, in: Support.dark)))
    }

    @Test func aColourlessSpaceSelectsInTheNeutralGreyPalette() {
        #expect(Support.near(Support.rgba(neutral.selected, in: Support.dark), Self.neutralDark))
        #expect(Support.near(Support.rgba(neutral.selected, in: Support.light), Self.neutralLight))
    }

    @Test(arguments: [true, false])
    func aColourlessSpaceNeverSelectsInTheSystemAccent(dark: Bool) {
        let appearance = dark ? Support.dark : Support.light
        let selected = Support.rgba(neutral.selected, in: appearance)
        let accents = [Support.rgba(.controlAccentColor, in: appearance), Support.rgba(.selectedContentBackgroundColor, in: appearance)]
        #expect(!accents.contains { Support.near($0, selected, 0.05) })
    }

    @Test func neutralFieldSelectionIsGrey() {
        #expect(Support.near(Support.rgba(neutral.inputSelection, in: Support.dark), SIMD4(0.47, 0.47, 0.47, 1)))
        #expect(Support.near(Support.rgba(neutral.inputSelection, in: Support.light), SIMD4(0.68, 0.68, 0.68, 1)))
    }

    @Test func theScopeAndActionsPillsFollowTheNeutralFocus() {
        #expect(Support.near(Support.rgba(neutral.scopePill, in: Support.dark), Self.neutralDark))
    }

    struct Ink: Sendable, CustomTestStringConvertible {
        let name: String
        let color: @Sendable () -> NSColor
        let dark: Bool
        let expected: SIMD4<Double>
        var testDescription: String { name }
    }

    static let inks: [Ink] = [
        Ink(name: "dark hover", color: { CommandBarPalette.rowHover }, dark: true, expected: SIMD4(1, 1, 1, 0.05)),
        Ink(name: "light hover", color: { CommandBarPalette.rowHover }, dark: false, expected: SIMD4(0, 0, 0, 0.05)),
        Ink(name: "dark primary text", color: { CommandBarPalette.textPrimary }, dark: true, expected: SIMD4(1, 1, 1, 0.8)),
        Ink(name: "light secondary text", color: { CommandBarPalette.textSecondary }, dark: false, expected: SIMD4(0, 0, 0, 0.33)),
        Ink(name: "dark accessory ink", color: { CommandBarPalette.accessoryForeground }, dark: true, expected: SIMD4(1, 1, 1, 0.66)),
        Ink(name: "light accessory ink", color: { CommandBarPalette.accessoryForeground }, dark: false, expected: SIMD4(0, 0, 0, 0.5)),
        Ink(name: "accessory tile", color: { CommandBarPalette.accessoryBackground }, dark: true, expected: SIMD4(1, 1, 1, 0.05)),
        Ink(name: "hairline colour", color: { CommandBarPalette.hairline }, dark: true, expected: SIMD4(1, 1, 1, 0.1)),
    ]

    @Test(arguments: inks)
    func fixedInksKeepTheirValues(ink: Ink) {
        #expect(Support.near(Support.rgba(ink.color(), in: ink.dark ? Support.dark : Support.light), ink.expected))
    }

    @Test func popoverInputTextIsMoreOpaqueInDark() {
        #expect(Support.rgba(CommandBarPalette.popoverInputText, in: Support.dark).w > 0.89)
        #expect(Support.rgba(CommandBarPalette.popoverInputText, in: Support.light).w < 0.81)
    }

    @Test func typeSizesAreKept() {
        #expect(CommandBarTypography.label.pointSize == 13)
        #expect(CommandBarTypography.field.pointSize == 18)
    }

    @Test func theLabelIsMediumWeight() {
        #expect(NSFontManager.shared.weight(of: CommandBarTypography.label) == NSFontManager.shared.weight(of: .systemFont(ofSize: 13, weight: .medium)))
    }
}
