import Foundation
import Testing
@testable import ParcCore

struct NoteMermaidThemeTests {
    struct PageFont: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let font: NotePageFont
        let expected: String
    }

    private static let pageFonts = [
        PageFont(testDescription: "serif", font: .serif, expected: "\"EB Garamond\""),
        PageFont(testDescription: "mono", font: .mono, expected: "\"Space Mono\""),
        PageFont(testDescription: "wide", font: .wide, expected: "\"ParcWide\""),
    ]

    @Test func lightAndDarkAppearancesUseDifferentInk() {
        let light = NoteMermaidTheme.note(dark: false)
        let dark = NoteMermaidTheme.note(dark: true)
        #expect(light != dark, "light and dark themes differ")
        #expect(light.variables["primaryTextColor"] == "#1F1B2E" && dark.variables["primaryTextColor"] == "#EDEBFA", "labels use Parc's note ink")
    }

    @Test func diagramLabelsUseNunitoByDefault() {
        let light = NoteMermaidTheme.note(dark: false)
        #expect(light.fontFamily.hasPrefix("\"Nunito\"") && light.faces.contains("700 16px \"Nunito\""), "standard pages draw in Nunito")
    }

    @Test(arguments: pageFonts) func diagramLabelsUseThePageFont(_ example: PageFont) {
        #expect(NoteMermaidTheme.note(dark: false, font: example.font).fontFamily.hasPrefix(example.expected))
    }

    @Test func smallTextShrinksDiagramLabels() {
        let light = NoteMermaidTheme.note(dark: false)
        #expect(NoteMermaidTheme.note(dark: false, small: true).fontSize < light.fontSize, "small text shrinks diagram labels")
    }

    @Test func diagramsUseStrictSecurity() {
        let light = NoteMermaidTheme.note(dark: false)
        let configuration = light.configuration(seed: "seed")
        #expect(configuration["securityLevel"] as? String == "strict", "diagrams run in strict security")
    }

    @Test func theRendererSuppressesMermaidErrorArtwork() {
        let light = NoteMermaidTheme.note(dark: false)
        let configuration = light.configuration(seed: "seed")
        #expect(configuration["suppressErrorRendering"] as? Bool == true, "Mermaid's own error bomb stays hidden")
    }

    @Test func mermaidUsesTheBaseThemeWithDeterministicIdentifiers() {
        let light = NoteMermaidTheme.note(dark: false)
        let configuration = light.configuration(seed: "seed")
        #expect(configuration["theme"] as? String == "base" && configuration["deterministicIDSeed"] as? String == "seed", "the base theme carries Parc's variables with stable ids")
    }

    @Test func themeVariablesCarryAppearanceAndChartPalette() {
        let light = NoteMermaidTheme.note(dark: false)
        let configuration = light.configuration(seed: "seed")
        let variables = configuration["themeVariables"] as? [String: Any]
        #expect(variables?["darkMode"] as? Bool == false && (variables?["xyChart"] as? [String: String])?["plotColorPalette"] != nil, "theme variables include dark mode and the chart palette")
    }

    @Test(arguments: 0..<12) func eachSectionColorIsThemed(_ index: Int) {
        let light = NoteMermaidTheme.note(dark: false)
        let dark = NoteMermaidTheme.note(dark: true)
        #expect(light.variables["cScale\(index)"] != nil && dark.variables["cScale\(index)"] != nil, "section colour \(index) is themed")
    }

    @Test(arguments: 0..<12) func eachPieSliceHasAThemeColor(_ index: Int) {
        let light = NoteMermaidTheme.note(dark: false)
        #expect(light.variables["pie\(index + 1)"] != nil, "pie slice \(index + 1) is themed")
    }

    @Test func requestConfigurationEncodesFontFamilyInJson() {
        let light = NoteMermaidTheme.note(dark: false)
        let parsed = (try? JSONSerialization.jsonObject(with: Data(NoteMermaidRequest(source: "x", theme: light).configurationJSON.utf8))) as? [String: Any]
        #expect(parsed?["fontFamily"] as? String == light.fontFamily, "the configuration is valid JSON")
    }

    @Test func fontFacesEncodeAsAJsonList() {
        let light = NoteMermaidTheme.note(dark: false)
        let faces = (try? JSONSerialization.jsonObject(with: Data(light.facesJSON.utf8))) as? [String]
        #expect(faces == light.faces, "font faces travel as a JSON list")
    }

    @Test func pixelSizesFormatForCss() {
        #expect(NoteMermaidPalette.cssSize(16) == "16px" && NoteMermaidPalette.cssSize(13.5) == "13.5px", "sizes print as CSS")
    }
}
