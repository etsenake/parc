import Foundation
import Testing
@testable import ParcCore

struct EaselMermaidFlowchartTests {
    private func subgraphs() throws -> EaselMermaidDiagram {
        try EaselMermaidTestsSupport.diagram("""
        flowchart TB
            c1-->a2
            subgraph one
            a1-->a2
            end
            subgraph two [The Second]
            direction LR
            b1-->b2
            subgraph inner
            b3
            end
            end
            subgraph "Spaced title"
            d1
            end
            one --> two
            three --> two
            subgraph three
            c2
            end
        """)
    }

    private func labelledGraph() throws -> EaselMermaidDiagram {
        try EaselMermaidTestsSupport.diagram("""
        flowchart TD
        A -->|Yes| B
        A -- No --> C
        C -. maybe .-> D
        D == sure ==> E
        E ---|plain| F
        F -- "quoted -- text" --> G
        G e1@--> H
        e1@{ animate: true }
        H -->|"`**bold** move`"| I
        """)
    }

    private struct DirectionCase: Sendable, CustomTestStringConvertible {
        let header: String
        let expected: EaselMermaidDirection
        var testDescription: String { header }
    }

    @Test(arguments: [
        DirectionCase(header: "flowchart TD", expected: .down),
        DirectionCase(header: "graph LR", expected: .right),
        DirectionCase(header: "flowchart BT", expected: .up),
        DirectionCase(header: "flowchart RL", expected: .left),
        DirectionCase(header: "flowchart", expected: .down),
    ])
    private func flowchartHeadersSetTheDirection(_ testCase: DirectionCase) throws {
        #expect(try EaselMermaidTestsSupport.diagram(testCase.header + "\nA-->B").direction == testCase.expected)
    }

    @Test
    func semicolonsSplitStatementsOnTheHeaderLine() throws {
        #expect(try EaselMermaidTestsSupport.diagram("graph TB;A-->B;B-->C").edges.count == 2, "Semicolons split statements on the header line")
    }

    @Test
    func aMermaidFenceIsUnwrapped() throws {
        #expect(try EaselMermaidTestsSupport.diagram("```mermaid\nflowchart LR\n  A --> B\n```").edges.count == 1, "A mermaid fence is unwrapped")
    }

    @Test
    func anUnlabelledFenceIsUnwrapped() throws {
        #expect(try EaselMermaidTestsSupport.diagram("```\ngraph TD\nA-->B\n```\n").nodes.count == 2, "A plain fence is unwrapped")
    }

    @Test
    func commentsAndDirectivesBeforeTheHeaderAreSkipped() throws {
        #expect(try EaselMermaidTestsSupport.diagram("  \n%% notes first\n%%{init: {\"theme\": \"dark\"}}%%\ngraph TD\nA-->B").edges.count == 1, "Comments and directives before the header are skipped")
    }

    @Test
    func frontMatterBeforeTheHeaderIsSkipped() throws {
        #expect(try EaselMermaidTestsSupport.diagram("---\ntitle: Hello\n---\nflowchart LR\nA-->B").direction == .right, "Front matter is skipped")
    }

    @Test
    func multilineDirectivesAreSkipped() throws {
        #expect(try EaselMermaidTestsSupport.diagram("%%{\n init: {}\n}%%\nflowchart TD\nA").nodes.count == 1, "Multi-line directives are skipped")
    }

    @Test
    func aFenceForAnotherLanguageIsRefused() {
        #expect(EaselMermaidTestsSupport.refusal("```swift\nlet a = 1\n```") == .notMermaid, "Other fenced languages aren't Mermaid")
    }

    @Test
    func proseAndEmptyInputAreRefused() {
        #expect(EaselMermaidTestsSupport.refusal("Hello there, this is a note") == .notMermaid, "Prose isn't Mermaid")
        #expect(EaselMermaidTestsSupport.refusal("") == .notMermaid, "Empty text isn't Mermaid")
    }

    @Test
    func unsupportedDiagramsAreRefusedByName() {
        #expect(EaselMermaidTestsSupport.refusal("sequenceDiagram\nA->>B: Hi") == .unsupported("Sequence diagrams"), "Sequence diagrams are refused by name")
        #expect(EaselMermaidTestsSupport.refusal("pie title Pets\n\"Dogs\": 3") == .unsupported("Pie charts"), "Pie charts are refused by name")
        #expect(EaselMermaidTestsSupport.refusal("classDiagram\nA <|-- B") == .unsupported("Class diagrams"), "Class diagrams are refused by name")
    }

    @Test
    func aHeaderWithoutStatementsIsEmpty() {
        #expect(EaselMermaidTestsSupport.refusal("flowchart TD\n%% nothing") == .empty, "A header alone is empty")
    }

    @Test
    func unknownDirectionsReportTheHeaderLine() {
        #expect(EaselMermaidTestsSupport.refusal("flowchart XY\nA-->B") == .syntax(line: 1, detail: "the direction should be TB, TD, BT, LR or RL"), "An unknown direction is a syntax error on line one")
    }

    @Test
    func canParseAgreesWithParsing() {
        #expect(EaselMermaid.canParse("graph TD\nA-->B") && !EaselMermaid.canParse("graph TD\nA-->"), "canParse mirrors parse")
    }

    @Test
    func anOverlongFlowchartIsRefused() {
        let big = "flowchart TD\n" + String(repeating: "A --> B\n", count: 60_000)
        #expect(EaselMermaidTestsSupport.refusal(big) == .tooLarge, "Huge sources are refused as too large")
    }

    @Test
    func overlongProseStaysPlainText() {
        #expect(EaselMermaidTestsSupport.refusal(String(repeating: "hello world ", count: 50_000)) == .notMermaid, "Huge prose stays plain text")
    }

    private struct NodeCase: Sendable, CustomTestStringConvertible {
        let source: String
        let shape: EaselMermaidShape
        let label: String
        var testDescription: String { source }

        init(_ source: String, _ shape: EaselMermaidShape, _ label: String) {
            self.source = source
            self.shape = shape
            self.label = label
        }
    }

    @Test(arguments: [
        NodeCase("A", .rectangle, "A"),
        NodeCase("A[Box]", .rectangle, "Box"),
        NodeCase("A(Round)", .rounded, "Round"),
        NodeCase("A([Pill])", .stadium, "Pill"),
        NodeCase("A[[Sub]]", .subroutine, "Sub"),
        NodeCase("A[(Data)]", .cylinder, "Data"),
        NodeCase("A((Dot))", .circle, "Dot"),
        NodeCase("A(((Stop)))", .doubleCircle, "Stop"),
        NodeCase("A>Flag]", .asymmetric, "Flag"),
        NodeCase("A{Ask?}", .diamond, "Ask?"),
        NodeCase("A{{Prep}}", .hexagon, "Prep"),
        NodeCase("A[/In/]", .leanRight, "In"),
        NodeCase("A[\\Out\\]", .leanLeft, "Out"),
        NodeCase("A[/Base\\]", .trapezoid, "Base"),
        NodeCase("A[\\Top/]", .invertedTrapezoid, "Top"),
        NodeCase("A(-Oval-)", .ellipse, "Oval"),
        NodeCase("A@{ shape: doc, label: \"Paper\" }", .document, "Paper"),
        NodeCase("A@{ shape: cyl }", .cylinder, "A"),
        NodeCase("A@{ shape: h-cyl, label: Disk }", .horizontalCylinder, "Disk"),
        NodeCase("A@{ shape: sl-rect, label: Type }", .manualInput, "Type"),
        NodeCase("A@{ shape: notch-rect }", .card, "A"),
        NodeCase("A@{ shape: cross-circ }", .crossedCircle, "A"),
        NodeCase("A@{ shape: mystery }", .rectangle, "A"),
        NodeCase("A@{ shape: text, label: \"Note\" }", .text, "Note"),
        NodeCase("A[/api/path]", .rectangle, "/api/path"),
        NodeCase("A(-1)", .rounded, "-1"),
        NodeCase("A(f(x))", .rounded, "f(x)"),
        NodeCase("A[\"Quoted [brackets]\"]", .rectangle, "Quoted [brackets]"),
    ])
    private func nodeSyntaxKeepsTheShapeAndLabel(_ testCase: NodeCase) throws {
        let value = try EaselMermaidTestsSupport.diagram("flowchart TD\n" + testCase.source)
        #expect(value.nodes.count == 1)
        #expect(value.nodes.first?.shape == testCase.shape)
        #expect(value.nodes.first?.label == testCase.label)
    }

    @Test
    func theLastNodeDefinitionWins() throws {
        let redefined = try EaselMermaidTestsSupport.diagram("flowchart TD\nA[One] --> B\nA{Two}")
        #expect(redefined.node("A")?.label == "Two" && redefined.node("A")?.shape == .diamond, "The last definition wins")
    }

    @Test
    func nodeNamesAllowPunctuationAndNonASCIICharacters() throws {
        #expect(try EaselMermaidTestsSupport.diagram("flowchart TD\nmy-node.v2 --> next_one").nodes.map(\.id) == ["my-node.v2", "next_one"], "Names may hold dashes, dots and underscores")
        #expect(try EaselMermaidTestsSupport.diagram("flowchart TD\nÉtape1 --> 終わり").nodes.map(\.id) == ["Étape1", "終わり"], "Names may be any letters")
    }

    private struct EdgeCase: Sendable, CustomTestStringConvertible {
        let source: String
        let from: String
        let to: String
        let line: EaselMermaidLine?
        let start: EaselMermaidHead?
        let end: EaselMermaidHead?
        let length: Int?
        var testDescription: String { source }

        init(_ source: String, from: String, to: String, line: EaselMermaidLine? = nil,
             start: EaselMermaidHead? = nil, end: EaselMermaidHead? = nil, length: Int? = nil) {
            self.source = source
            self.from = from
            self.to = to
            self.line = line
            self.start = start
            self.end = end
            self.length = length
        }
    }

    @Test(arguments: [
        EdgeCase("A --> B", from: "A", to: "B", line: .solid, start: EaselMermaidHead.none, end: .arrow),
        EdgeCase("C --- D", from: "C", to: "D", end: EaselMermaidHead.none),
        EdgeCase("E -.-> F", from: "E", to: "F", line: .dotted, end: .arrow),
        EdgeCase("G ==> H", from: "G", to: "H", line: .thick),
        EdgeCase("I ~~~ J", from: "I", to: "J", line: .invisible),
        EdgeCase("K --o L", from: "K", to: "L", end: .circle),
        EdgeCase("M --x N", from: "M", to: "N", end: .cross),
        EdgeCase("O <--> P", from: "O", to: "P", start: .arrow, end: .arrow),
        EdgeCase("Q o--o R", from: "Q", to: "R", start: .circle, end: .circle),
        EdgeCase("S x--x T", from: "S", to: "T", start: .cross, end: .cross),
        EdgeCase("U ----> V", from: "U", to: "V", length: 3),
        EdgeCase("W -.- X", from: "W", to: "X", line: .dotted, end: EaselMermaidHead.none),
        EdgeCase("Y === Z", from: "Y", to: "Z", line: .thick, end: EaselMermaidHead.none),
        EdgeCase("AA -..-> AB", from: "AA", to: "AB", length: 2),
        EdgeCase("AC --oAD", from: "AC", to: "AD", end: .circle),
    ])
    private func edgeSyntaxSetsTheLineHeadsAndLength(_ testCase: EdgeCase) throws {
        let value = try EaselMermaidTestsSupport.diagram("flowchart LR\n" + testCase.source)
        let edge = EaselMermaidTestsSupport.edge(value, testCase.from, testCase.to)
        if let line = testCase.line { #expect(edge?.line == line) }
        if let start = testCase.start { #expect(edge?.startHead == start) }
        if let end = testCase.end { #expect(edge?.endHead == end) }
        if let length = testCase.length { #expect(edge?.length == length) }
    }

    @Test
    func edgeLabelsKeepTheirTextAndLinkStyle() throws {
        let labelled = try labelledGraph()
        #expect(EaselMermaidTestsSupport.edge(labelled, "A", "B")?.label == "Yes", "Pipe labels are read")
        #expect(EaselMermaidTestsSupport.edge(labelled, "A", "C")?.label == "No" && EaselMermaidTestsSupport.edge(labelled, "A", "C")?.endHead == .arrow, "-- text --> labels are read")
        #expect(EaselMermaidTestsSupport.edge(labelled, "C", "D")?.label == "maybe" && EaselMermaidTestsSupport.edge(labelled, "C", "D")?.line == .dotted, "Dotted labels are read")
        #expect(EaselMermaidTestsSupport.edge(labelled, "D", "E")?.label == "sure" && EaselMermaidTestsSupport.edge(labelled, "D", "E")?.line == .thick, "Thick labels are read")
        #expect(EaselMermaidTestsSupport.edge(labelled, "E", "F")?.label == "plain" && EaselMermaidTestsSupport.edge(labelled, "E", "F")?.endHead == EaselMermaidHead.none, "Open links take labels")
        #expect(EaselMermaidTestsSupport.edge(labelled, "F", "G")?.label == "quoted -- text", "Quoted link text may hold dashes")
        #expect(EaselMermaidTestsSupport.edge(labelled, "H", "I")?.label == "bold move", "Markdown link labels are flattened")
    }

    @Test
    func edgePropertiesDoNotCreateExtraNodes() throws {
        let labelled = try labelledGraph()
        #expect(EaselMermaidTestsSupport.edge(labelled, "G", "H") != nil && labelled.node("e1") == nil, "Edge IDs and their properties don't become nodes")
    }

    @Test
    func aSingleDashArrowIsAccepted() throws {
        #expect(try EaselMermaidTestsSupport.diagram("flowchart LR\nA->B").edges.count == 1, "A single-dash arrow is accepted")
    }

    @Test
    func aChainMakesOneLinkPerHopWithItsOwnLabel() throws {
        let chain = try EaselMermaidTestsSupport.diagram("flowchart LR\nA --> B --> C -- end --> D")
        #expect(chain.edges.map { $0.from + $0.to } == ["AB", "BC", "CD"], "Chains make one link per hop")
        #expect(chain.edges.last?.label == "end", "Each hop keeps its own label")
    }

    @Test
    func groupsLinkEveryPairInOrder() throws {
        let groups = try EaselMermaidTestsSupport.diagram("flowchart TD\nA & B --> C & D")
        #expect(groups.edges.map { $0.from + $0.to } == ["AC", "AD", "BC", "BD"], "& links every pair in order")
    }

    @Test
    func ampersandsCanDeclareNodesWithoutEdges() throws {
        let declared = try EaselMermaidTestsSupport.diagram("flowchart TD\nA[One] & B(Two)")
        #expect(declared.nodes.map(\.shape) == [.rectangle, .rounded] && declared.edges.isEmpty, "& can declare nodes alone")
    }

    @Test
    func subgraphsKeepTheirNodesTitlesAndNesting() throws {
        let value = try subgraphs()
        #expect(value.node("a2")?.group == "one", "A node linked inside a subgraph joins it")
        #expect(value.node("c1")?.group == nil, "Nodes outside stay outside")
        #expect(value.group("two")?.title == "The Second" && value.group("two")?.direction == .right, "Titles and directions are kept")
        #expect(value.group("inner")?.parent == "two" && value.node("b3")?.group == "inner", "Subgraphs nest")
        #expect(value.groups.contains { $0.title == "Spaced title" && $0.id.hasPrefix("subGraph") }, "Spaced titles get generated IDs")
    }

    @Test
    func linksToSubgraphsResolveWithoutExtraNodes() throws {
        let value = try subgraphs()
        #expect(value.node("one") == nil && value.node("two") == nil, "Links to subgraphs don't make extra nodes")
        #expect(value.node("three") == nil && EaselMermaidTestsSupport.edge(value, "three", "two") != nil, "Links to later subgraphs resolve to the subgraph")
    }

    @Test
    func aStraySubgraphEndReportsItsLine() {
        #expect(EaselMermaidTestsSupport.refusal("flowchart TD\nA\nend") == .syntax(line: 3, detail: "there’s an end without a subgraph to close"), "A stray end is reported on its line")
    }

    @Test
    func anUnclosedSubgraphClosesAtTheEnd() throws {
        #expect(try EaselMermaidTestsSupport.diagram("flowchart TD\nsubgraph S\nA\n").node("A")?.group == "S", "An unclosed subgraph closes at the end")
    }

    @Test
    func nodeLabelsDecodeLineBreaksMarkdownAndHTMLEntities() throws {
        let value = try EaselMermaidTestsSupport.diagram("""
        flowchart TD
        A["Line one<br>Line two"]
        B["`The **cat**
          in the _hat_`"]
        C["Say #quot;hi#quot; &amp; wave #9829;"]
        D[fa:fa-car Drive]
        E["<b>Bold</b> move"]
        F[100%% sure]
        """)
        #expect(value.node("A")?.label == "Line one\nLine two", "<br> becomes a new line")
        #expect(value.node("B")?.label == "The cat\nin the hat", "Markdown strings keep lines and drop emphasis marks")
        #expect(value.node("C")?.label == "Say \"hi\" & wave ♥", "Entities are decoded")
        #expect(value.node("D")?.label == "Drive", "Font Awesome icons are dropped")
        #expect(value.node("E")?.label == "Bold move", "HTML tags are dropped")
        #expect(value.node("F")?.label == "100%% sure", "%% inside a label isn't a comment")
    }

    @Test
    func lineCommentsDoNotCreateNodesOrEdges() throws {
        let comments = try EaselMermaidTestsSupport.diagram("flowchart TD\nA --> B %% trailing note\n%% whole line\nB --> C")
        #expect(comments.edges.count == 2 && comments.node("note") == nil, "Comments are ignored")
    }

    @Test
    func flowchartSyntaxErrorsIncludeTheBadLine() {
        #expect(EaselMermaidTestsSupport.refusal("flowchart TD\nA --> B\nC[Unclosed --> D") == .syntax(line: 3, detail: "the label for C is missing its closing bracket"), "Unclosed labels name their line")
        #expect(EaselMermaidTestsSupport.refusal("flowchart TD\nA -- yes B") == .syntax(line: 2, detail: "an arrow label needs the rest of its arrow, like -- yes -->"), "Labels without arrows are refused")
        #expect(EaselMermaidTestsSupport.refusal("flowchart TD\nA -->") == .syntax(line: 2, detail: "this arrow needs something on the other end"), "Dangling arrows are refused")
        #expect(EaselMermaidTestsSupport.refusal("flowchart TD\nA B") == .syntax(line: 2, detail: "Parc expected an arrow like --> after A"), "Two names in a row are refused")
        #expect(EaselMermaidTestsSupport.refusal("flowchart TD\nA -->|open B") == .syntax(line: 2, detail: "an arrow label is missing its closing |"), "Unclosed pipes are refused")
        guard case .syntax(let line, _)? = EaselMermaidTestsSupport.refusal("flowchart TD\nA\nB\n---> C") else { Issue.record("A leading arrow is refused"); return }
        #expect(line == 4, "The error points at the bad line")
    }

    @Test
    func syntaxRefusalsDisplayTheirLine() {
        #expect(EaselMermaidRefusal.syntax(line: 4, detail: "oops").message == "Line 4: oops.", "Syntax messages lead with the line")
    }

    @Test
    func unsupportedRefusalsNameTheDiagramType() {
        #expect(EaselMermaidRefusal.unsupported("Gantt charts").message.hasPrefix("Gantt charts can’t"), "Refusals name the diagram type")
    }

    @Test
    func moreThanFiveHundredNodesIsTooLarge() {
        let many = "flowchart TD\n" + (0..<501).map { "N\($0)" }.joined(separator: "\n")
        #expect(EaselMermaidTestsSupport.refusal(many) == .tooLarge, "More than 500 nodes is too large")
    }
}
