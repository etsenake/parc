import Foundation
import Testing
@testable import ParcCore

struct EaselMermaidLimitsTests {
    @Test
    func aLargePairOfGroupsRefusesTheLinkProduct() {
        let wide = (0..<1500).map { "a\($0)" }.joined(separator: "&") + " --> " + (0..<1500).map { "b\($0)" }.joined(separator: "&")
        #expect(EaselMermaidTestsSupport.refusal("flowchart TD\n" + wide) == .tooLarge, "Huge & groups are refused")
        let square = (0..<41).map { "a\($0)" }.joined(separator: "&") + " --> " + (0..<41).map { "b\($0)" }.joined(separator: "&")
        #expect(EaselMermaidTestsSupport.refusal("flowchart TD\n" + square) == .tooLarge, "& products past the arrow limit are refused")
    }

    @Test
    func aDiagramWithTooManySectionsIsRefused() {
        let repeated = "flowchart TD\n" + String(repeating: "subgraph a\nend\n", count: 3000)
        #expect(EaselMermaidTestsSupport.refusal(repeated) == .tooLarge, "Too many subgraphs are refused early")
    }

    @Test
    func repeatedSectionNamesGetNumbered() throws {
        let twins = try EaselMermaidTestsSupport.diagram("flowchart TD\nsubgraph a\nx\nend\nsubgraph a\ny\nend\nsubgraph a\nz\nend")
        #expect(twins.groups.map(\.id) == ["a", "a_2", "a_3"], "Repeated subgraph names get numbered")
    }

    @Test
    func aChainOfIdenticalLabelsKeepsOneNodeAndEveryEdge() throws {
        let looped = "flowchart TD\n" + Array(repeating: "A(-x)", count: 900).joined(separator: " --> ")
        let loop = try EaselMermaidTestsSupport.diagram(looped)
        #expect(loop.nodes.count == 1 && loop.node("A")?.label == "-x" && loop.edges.count == 899, "Fallback labels stay cheap and right")
    }

    @Test
    func anOverlongGroupListIsRefused() {
        let ampersands = "flowchart TD\n" + Array(repeating: "A(-x)", count: 12_000).joined(separator: "&")
        #expect(EaselMermaidTestsSupport.refusal(ampersands) == .tooLarge, "Endless & lists are refused")
    }

    @Test
    func aChainPastTheEdgeLimitIsRefused() {
        let chain = "flowchart TD\n" + (0..<5000).map { "n\($0)" }.joined(separator: " --> ")
        #expect(EaselMermaidTestsSupport.refusal(chain) == .tooLarge, "Chains past the arrow limit are refused")
    }

    @Test
    func repeatedDefaultStylesStillApplyToEdges() throws {
        let styled = "flowchart TD\n" + String(repeating: "a --> b\n", count: 900) + String(repeating: "linkStyle default stroke:red\n", count: 4000)
        let restyled = try EaselMermaidTestsSupport.diagram(styled)
        #expect(restyled.edges.allSatisfy { $0.style.stroke == EaselPalette.hex(.note(.red), role: .ink) }, "Repeated default styles still apply")
    }

    @Test
    func anOverlargeDiagramRefusesItsNodeOrEntityCount() {
        let lines = "flowchart TD\n" + (0..<600).map { "n\($0)" }.joined(separator: "\n")
        #expect(EaselMermaidTestsSupport.refusal(lines) == .tooLarge, "More nodes than the limit are refused early")
        let entities = "erDiagram\n" + (0..<600).map { "E\($0)" }.joined(separator: "\n")
        #expect(EaselMermaidTestsSupport.refusal(entities) == .tooLarge, "More entities than the limit are refused")
    }

    @Test
    func anEREntityWithTooManyAttributesIsRefused() {
        let attributes = "erDiagram\nA {\n" + String(repeating: "string name\n", count: 150) + "}"
        #expect(EaselMermaidTestsSupport.refusal(attributes) == .tooLarge, "More attributes than the limit are refused")
    }

    @Test
    func anERDiagramWithTooManyRelationshipsIsRefused() {
        let relationships = "erDiagram\n" + String(repeating: "A ||--o{ B : has\n", count: 1500)
        #expect(EaselMermaidTestsSupport.refusal(relationships) == .tooLarge, "More relationships than the limit are refused")
    }

    @Test
    func unclosedNestingReportsASyntaxError() {
        let unclosed = "flowchart TD\nA(-" + String(repeating: "(", count: 100_000)
        #expect(EaselMermaidTestsSupport.refusal(unclosed).map { if case .syntax = $0 { return true } else { return false } } == true, "Unclosed nesting is a quick syntax error")
    }

    @Test
    func diagramKeywordsAreCaseSensitive() {
        #expect(EaselMermaidTestsSupport.refusal("Graph\nLogin\nDashboard") == .notMermaid && EaselMermaidTestsSupport.refusal("Flowchart TD\nA-->B") == .notMermaid
               && EaselMermaidTestsSupport.refusal("ErDiagram\nA") == .notMermaid, "Diagram keywords are case-sensitive like Mermaid's")
    }

    @Test
    func longLinksOverALongSpineStayWithinTheCanvas() throws {
        var spine = (0..<400).map { "n\($0)" }.joined(separator: " ---------> ") + "\n"
        spine += String(repeating: "n0 --> n399\n", count: 500)
        let tall = EaselMermaid.drawing(try EaselMermaidTestsSupport.diagram("flowchart TD\n" + spine))
        #expect(tall.height < EaselRect.maximumCoordinate / 2 && tall.items.allSatisfy { $0.frame.y + $0.frame.height < tall.height + 1 }, "Long links over a long spine stay inside the Easel")
    }

    @Test
    func anExtremelyLongArrowHasBoundedLengthAndLayout() throws {
        let dashes = String(repeating: "-", count: 100_000)
        let stretched = try EaselMermaidTestsSupport.diagram("flowchart TD\nA " + dashes + "> B")
        #expect(stretched.edges.count == 1 && stretched.edges[0].length <= EaselMermaid.maximumLength, "Arrow length is clamped")
        let stretchedDrawing = EaselMermaid.drawing(stretched)
        #expect(stretchedDrawing.height < EaselRect.maximumCoordinate / 2, "A clamped arrow draws a small layout")
    }

    @Test
    func heavyLabelsStillLayOutToFiniteSizes() throws {
        let heavy = "flowchart LR\n" + (0..<300).map { "n\($0)[\"" + String(repeating: "w ", count: 100) + "\"]" }.joined(separator: "\n")
        let heavyDrawing = EaselMermaid.drawing(try EaselMermaidTestsSupport.diagram(heavy))
        #expect(heavyDrawing.width.isFinite && heavyDrawing.height.isFinite, "Heavy labels lay out to finite sizes")
    }

    @Test
    func parsingTheSameInputTwiceAgrees() {
        let repeatedParse = "flowchart TD\nA --> B"
        let first = EaselMermaid.parse(repeatedParse), second = EaselMermaid.parse(repeatedParse)
        #expect(first == second, "Parsing the same text twice agrees")
    }

    @Test
    func giantLabelsAreClipped() throws {
        let label = "flowchart TD\nA[\"" + String(repeating: "**a** ", count: 50_000) + "\"]"
        #expect(try EaselMermaidTestsSupport.diagram(label).node("A").map { $0.label.count <= EaselMermaidText.maximumLength } == true, "Giant labels are cut short")
    }
}
