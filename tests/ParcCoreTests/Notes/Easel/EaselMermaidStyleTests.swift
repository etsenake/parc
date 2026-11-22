import Foundation
import Testing
@testable import ParcCore

struct EaselMermaidStyleTests {
    @Test
    func classStylesApplyToTheirAssignedNodes() throws {
        let value = try EaselMermaidTestsSupport.diagram("""
        flowchart TD
        classDef hot fill:#f96,stroke:#333,stroke-width:4px
        classDef cool fill:lightblue,stroke-dasharray: 5 5
        classDef default fill:#fff
        A:::hot --> B
        class B cool
        style C fill:#9f9,stroke:#f00
        C --> D
        linkStyle 1 stroke:#0000ff,stroke-width:4px
        linkStyle default stroke:#aaa
        """)
        let orange = EaselPalette.hex(.note(.orange), role: .fill)
        #expect(value.node("A")?.style.fill == orange, "#f96 becomes the palette's orange fill")
        #expect(value.node("A")?.style.stroke == EaselPalette.automaticInk, "A dark grey stroke stays automatic ink")
        #expect(value.node("A")?.style.strokeWidth == 4, "stroke-width is read")
        #expect(value.node("B")?.style.fill == EaselPalette.hex(.note(.blue), role: .fill) && value.node("B")?.style.dashed == true, "Named colours and dashes are read")
    }

    @Test
    func inlineStylesApplyToTheirNode() throws {
        let value = try EaselMermaidTestsSupport.diagram("""
        flowchart TD
        classDef hot fill:#f96,stroke:#333,stroke-width:4px
        classDef cool fill:lightblue,stroke-dasharray: 5 5
        classDef default fill:#fff
        A:::hot --> B
        class B cool
        style C fill:#9f9,stroke:#f00
        C --> D
        linkStyle 1 stroke:#0000ff,stroke-width:4px
        linkStyle default stroke:#aaa
        """)
        #expect(value.node("C")?.style.fill == EaselPalette.hex(.note(.green), role: .fill), "style lines set fills")
        #expect(value.node("C")?.style.stroke == EaselPalette.hex(.note(.red), role: .ink), "style lines set strokes")
    }

    @Test
    func defaultClassStylesReachUnstyledNodes() throws {
        let value = try EaselMermaidTestsSupport.diagram("""
        flowchart TD
        classDef hot fill:#f96,stroke:#333,stroke-width:4px
        classDef cool fill:lightblue,stroke-dasharray: 5 5
        classDef default fill:#fff
        A:::hot --> B
        class B cool
        style C fill:#9f9,stroke:#f00
        C --> D
        linkStyle 1 stroke:#0000ff,stroke-width:4px
        linkStyle default stroke:#aaa
        """)
        #expect(value.node("D")?.style.fill == EaselPalette.neutralLight, "classDef default reaches unstyled nodes")
    }

    @Test
    func linkStylesApplyByIndexOrDefault() throws {
        let value = try EaselMermaidTestsSupport.diagram("""
        flowchart TD
        classDef hot fill:#f96,stroke:#333,stroke-width:4px
        classDef cool fill:lightblue,stroke-dasharray: 5 5
        classDef default fill:#fff
        A:::hot --> B
        class B cool
        style C fill:#9f9,stroke:#f00
        C --> D
        linkStyle 1 stroke:#0000ff,stroke-width:4px
        linkStyle default stroke:#aaa
        """)
        #expect(value.edges[1].style.stroke == EaselPalette.hex(.note(.blue), role: .ink) && value.edges[1].style.strokeWidth == 4, "linkStyle picks links by index")
        #expect(value.edges[0].style.stroke == EaselPalette.hex(.note(.gray), role: .ink), "linkStyle default reaches the rest")
    }

    private struct ColourCase: Sendable, CustomTestStringConvertible {
        let input: String
        let role: EaselColorRole
        let expected: NoteColor?
        var testDescription: String { input }

        init(_ input: String, _ role: EaselColorRole, _ expected: NoteColor?) {
            self.input = input
            self.role = role
            self.expected = expected
        }
    }

    @Test(arguments: [
        ColourCase("#8B4513", .fill, .brown),
        ColourCase("rgb(255, 215, 0)", .fill, .yellow),
        ColourCase("#9370DB", .ink, .purple),
        ColourCase("#ff69b4", .fill, .pink),
        ColourCase("nonsense", .fill, nil),
    ])
    private func mermaidColoursMapToTheEaselPalette(_ testCase: ColourCase) {
        #expect(EaselMermaidColor.palette(testCase.input, role: testCase.role) ==
                testCase.expected.flatMap { EaselPalette.hex(.note($0), role: testCase.role) })
    }
}
