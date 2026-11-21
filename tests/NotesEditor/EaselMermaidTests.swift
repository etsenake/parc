import Foundation

@main @MainActor
struct EaselMermaidTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func diagram(_ text: String) -> EaselMermaidDiagram {
        switch EaselMermaid.parse(text) {
        case .success(let value): return value
        case .failure(let refusal): failTest("Expected a diagram but got \(refusal.message) for:\n\(text)")
        }
    }

    static func refusal(_ text: String) -> EaselMermaidRefusal? {
        if case .failure(let value) = EaselMermaid.parse(text) { return value }
        return nil
    }

    static func edge(_ value: EaselMermaidDiagram, _ from: String, _ to: String) -> EaselMermaidEdge? {
        value.edges.first { $0.from == from && $0.to == to }
    }

    static func main() {
        headers()
        nodeShapes()
        links()
        chainsAndGroups()
        subgraphs()
        styles()
        labels()
        failures()
        entityRelationships()
        layoutDirections()
        layoutSeparation()
        layoutSections()
        layoutCycles()
        mapping()
        entityMapping()
        validation()
        hostileInput()
        print("EaselMermaidTests passed")
    }

    static func headers() {
        expect(diagram("flowchart TD\nA-->B").direction == .down, "flowchart TD flows down")
        expect(diagram("graph LR\nA-->B").direction == .right, "graph LR flows right")
        expect(diagram("flowchart BT\nA-->B").direction == .up, "BT flows up")
        expect(diagram("flowchart RL\nA-->B").direction == .left, "RL flows left")
        expect(diagram("graph TB;A-->B;B-->C").edges.count == 2, "Semicolons split statements on the header line")
        expect(diagram("flowchart\nA-->B").direction == .down, "A bare flowchart flows down")
        expect(diagram("```mermaid\nflowchart LR\n  A --> B\n```").edges.count == 1, "A mermaid fence is unwrapped")
        expect(diagram("```\ngraph TD\nA-->B\n```\n").nodes.count == 2, "A plain fence is unwrapped")
        expect(diagram("  \n%% notes first\n%%{init: {\"theme\": \"dark\"}}%%\ngraph TD\nA-->B").edges.count == 1,
               "Comments and directives before the header are skipped")
        expect(diagram("---\ntitle: Hello\n---\nflowchart LR\nA-->B").direction == .right, "Front matter is skipped")
        expect(diagram("%%{\n init: {}\n}%%\nflowchart TD\nA").nodes.count == 1, "Multi-line directives are skipped")
        expect(refusal("```swift\nlet a = 1\n```") == .notMermaid, "Other fenced languages aren't Mermaid")
        expect(refusal("Hello there, this is a note") == .notMermaid, "Prose isn't Mermaid")
        expect(refusal("") == .notMermaid, "Empty text isn't Mermaid")
        expect(refusal("sequenceDiagram\nA->>B: Hi") == .unsupported("Sequence diagrams"), "Sequence diagrams are refused by name")
        expect(refusal("pie title Pets\n\"Dogs\": 3") == .unsupported("Pie charts"), "Pie charts are refused by name")
        expect(refusal("classDiagram\nA <|-- B") == .unsupported("Class diagrams"), "Class diagrams are refused by name")
        expect(refusal("flowchart TD\n%% nothing") == .empty, "A header alone is empty")
        expect(refusal("flowchart XY\nA-->B") == .syntax(line: 1, detail: "the direction should be TB, TD, BT, LR or RL"),
               "An unknown direction is a syntax error on line one")
        expect(EaselMermaid.canParse("graph TD\nA-->B") && !EaselMermaid.canParse("graph TD\nA-->"), "canParse mirrors parse")
        let big = "flowchart TD\n" + String(repeating: "A --> B\n", count: 60_000)
        expect(refusal(big) == .tooLarge, "Huge sources are refused as too large")
        expect(refusal(String(repeating: "hello world ", count: 50_000)) == .notMermaid, "Huge prose stays plain text")
    }

    static func nodeShapes() {
        let cases: [(String, EaselMermaidShape, String)] = [
            ("A", .rectangle, "A"), ("A[Box]", .rectangle, "Box"), ("A(Round)", .rounded, "Round"),
            ("A([Pill])", .stadium, "Pill"), ("A[[Sub]]", .subroutine, "Sub"), ("A[(Data)]", .cylinder, "Data"),
            ("A((Dot))", .circle, "Dot"), ("A(((Stop)))", .doubleCircle, "Stop"), ("A>Flag]", .asymmetric, "Flag"),
            ("A{Ask?}", .diamond, "Ask?"), ("A{{Prep}}", .hexagon, "Prep"), ("A[/In/]", .leanRight, "In"),
            ("A[\\Out\\]", .leanLeft, "Out"), ("A[/Base\\]", .trapezoid, "Base"), ("A[\\Top/]", .invertedTrapezoid, "Top"),
            ("A(-Oval-)", .ellipse, "Oval"), ("A@{ shape: doc, label: \"Paper\" }", .document, "Paper"),
            ("A@{ shape: cyl }", .cylinder, "A"), ("A@{ shape: h-cyl, label: Disk }", .horizontalCylinder, "Disk"),
            ("A@{ shape: sl-rect, label: Type }", .manualInput, "Type"), ("A@{ shape: notch-rect }", .card, "A"),
            ("A@{ shape: cross-circ }", .crossedCircle, "A"), ("A@{ shape: mystery }", .rectangle, "A"),
            ("A@{ shape: text, label: \"Note\" }", .text, "Note"), ("A[/api/path]", .rectangle, "/api/path"),
            ("A(-1)", .rounded, "-1"), ("A(f(x))", .rounded, "f(x)"), ("A[\"Quoted [brackets]\"]", .rectangle, "Quoted [brackets]"),
        ]
        for (source, shape, label) in cases {
            let value = diagram("flowchart TD\n" + source)
            expect(value.nodes.count == 1, "\(source) makes one node")
            expect(value.nodes.first?.shape == shape, "\(source) is a \(shape) not \(String(describing: value.nodes.first?.shape))")
            expect(value.nodes.first?.label == label, "\(source) is labelled \(label) not \(value.nodes.first?.label ?? "-")")
        }
        let redefined = diagram("flowchart TD\nA[One] --> B\nA{Two}")
        expect(redefined.node("A")?.label == "Two" && redefined.node("A")?.shape == .diamond, "The last definition wins")
        expect(diagram("flowchart TD\nmy-node.v2 --> next_one").nodes.map(\.id) == ["my-node.v2", "next_one"],
               "Names may hold dashes, dots and underscores")
        expect(diagram("flowchart TD\nÉtape1 --> 終わり").nodes.map(\.id) == ["Étape1", "終わり"], "Names may be any letters")
    }

    static func links() {
        let value = diagram("""
        flowchart LR
        A --> B
        C --- D
        E -.-> F
        G ==> H
        I ~~~ J
        K --o L
        M --x N
        O <--> P
        Q o--o R
        S x--x T
        U ----> V
        W -.- X
        Y === Z
        AA -..-> AB
        AC --oAD
        """)
        let solid = edge(value, "A", "B")
        expect(solid?.line == .solid && solid?.startHead == EaselMermaidHead.none && solid?.endHead == .arrow, "--> is a solid arrow")
        expect(edge(value, "C", "D")?.endHead == EaselMermaidHead.none, "--- has no head")
        expect(edge(value, "E", "F")?.line == .dotted && edge(value, "E", "F")?.endHead == .arrow, "-.-> is a dotted arrow")
        expect(edge(value, "G", "H")?.line == .thick, "==> is thick")
        expect(edge(value, "I", "J")?.line == .invisible, "~~~ is invisible")
        expect(edge(value, "K", "L")?.endHead == .circle, "--o ends in a circle")
        expect(edge(value, "M", "N")?.endHead == .cross, "--x ends in a cross")
        expect(edge(value, "O", "P")?.startHead == .arrow && edge(value, "O", "P")?.endHead == .arrow, "<--> points both ways")
        expect(edge(value, "Q", "R")?.startHead == .circle && edge(value, "Q", "R")?.endHead == .circle, "o--o has two circles")
        expect(edge(value, "S", "T")?.startHead == .cross && edge(value, "S", "T")?.endHead == .cross, "x--x has two crosses")
        expect(edge(value, "U", "V")?.length == 3, "Extra dashes make a longer link")
        expect(edge(value, "W", "X")?.line == .dotted && edge(value, "W", "X")?.endHead == EaselMermaidHead.none, "-.- is a dotted line")
        expect(edge(value, "Y", "Z")?.line == .thick && edge(value, "Y", "Z")?.endHead == EaselMermaidHead.none, "=== is a thick line")
        expect(edge(value, "AA", "AB")?.length == 2, "Extra dots make a longer dotted link")
        expect(edge(value, "AC", "AD")?.endHead == .circle, "--o sticks to the next name like Mermaid")

        let labelled = diagram("""
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
        expect(edge(labelled, "A", "B")?.label == "Yes", "Pipe labels are read")
        expect(edge(labelled, "A", "C")?.label == "No" && edge(labelled, "A", "C")?.endHead == .arrow, "-- text --> labels are read")
        expect(edge(labelled, "C", "D")?.label == "maybe" && edge(labelled, "C", "D")?.line == .dotted, "Dotted labels are read")
        expect(edge(labelled, "D", "E")?.label == "sure" && edge(labelled, "D", "E")?.line == .thick, "Thick labels are read")
        expect(edge(labelled, "E", "F")?.label == "plain" && edge(labelled, "E", "F")?.endHead == EaselMermaidHead.none, "Open links take labels")
        expect(edge(labelled, "F", "G")?.label == "quoted -- text", "Quoted link text may hold dashes")
        expect(edge(labelled, "G", "H") != nil && labelled.node("e1") == nil, "Edge IDs and their properties don't become nodes")
        expect(edge(labelled, "H", "I")?.label == "bold move", "Markdown link labels are flattened")
        expect(diagram("flowchart LR\nA->B").edges.count == 1, "A single-dash arrow is accepted")
    }

    static func chainsAndGroups() {
        let chain = diagram("flowchart LR\nA --> B --> C -- end --> D")
        expect(chain.edges.map { $0.from + $0.to } == ["AB", "BC", "CD"], "Chains make one link per hop")
        expect(chain.edges.last?.label == "end", "Each hop keeps its own label")
        let groups = diagram("flowchart TD\nA & B --> C & D")
        expect(groups.edges.map { $0.from + $0.to } == ["AC", "AD", "BC", "BD"], "& links every pair in order")
        let declared = diagram("flowchart TD\nA[One] & B(Two)")
        expect(declared.nodes.map(\.shape) == [.rectangle, .rounded] && declared.edges.isEmpty, "& can declare nodes alone")
    }

    static func subgraphs() {
        let value = diagram("""
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
        expect(value.node("a2")?.group == "one", "A node linked inside a subgraph joins it")
        expect(value.node("c1")?.group == nil, "Nodes outside stay outside")
        expect(value.group("two")?.title == "The Second" && value.group("two")?.direction == .right, "Titles and directions are kept")
        expect(value.group("inner")?.parent == "two" && value.node("b3")?.group == "inner", "Subgraphs nest")
        expect(value.groups.contains { $0.title == "Spaced title" && $0.id.hasPrefix("subGraph") }, "Spaced titles get generated IDs")
        expect(value.node("one") == nil && value.node("two") == nil, "Links to subgraphs don't make extra nodes")
        expect(value.node("three") == nil && edge(value, "three", "two") != nil, "Links to later subgraphs resolve to the subgraph")
        expect(refusal("flowchart TD\nA\nend") == .syntax(line: 3, detail: "there's an end without a subgraph to close"),
               "A stray end is reported on its line")
        expect(diagram("flowchart TD\nsubgraph S\nA\n").node("A")?.group == "S", "An unclosed subgraph closes at the end")
    }

    static func styles() {
        let value = diagram("""
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
        expect(value.node("A")?.style.fill == orange, "#f96 becomes the palette's orange fill")
        expect(value.node("A")?.style.stroke == EaselPalette.automaticInk, "A dark grey stroke stays automatic ink")
        expect(value.node("A")?.style.strokeWidth == 4, "stroke-width is read")
        expect(value.node("B")?.style.fill == EaselPalette.hex(.note(.blue), role: .fill) && value.node("B")?.style.dashed == true,
               "Named colours and dashes are read")
        expect(value.node("C")?.style.fill == EaselPalette.hex(.note(.green), role: .fill), "style lines set fills")
        expect(value.node("C")?.style.stroke == EaselPalette.hex(.note(.red), role: .ink), "style lines set strokes")
        expect(value.node("D")?.style.fill == EaselPalette.neutralLight, "classDef default reaches unstyled nodes")
        expect(value.edges[1].style.stroke == EaselPalette.hex(.note(.blue), role: .ink) && value.edges[1].style.strokeWidth == 4,
               "linkStyle picks links by index")
        expect(value.edges[0].style.stroke == EaselPalette.hex(.note(.gray), role: .ink), "linkStyle default reaches the rest")
        expect(EaselMermaidColor.palette("#8B4513", role: .fill) == EaselPalette.hex(.note(.brown), role: .fill), "Saddle brown is brown")
        expect(EaselMermaidColor.palette("rgb(255, 215, 0)", role: .fill) == EaselPalette.hex(.note(.yellow), role: .fill), "Gold is yellow")
        expect(EaselMermaidColor.palette("#9370DB", role: .ink) == EaselPalette.hex(.note(.purple), role: .ink), "Medium purple is purple")
        expect(EaselMermaidColor.palette("#ff69b4", role: .fill) == EaselPalette.hex(.note(.pink), role: .fill), "Hot pink is pink")
        expect(EaselMermaidColor.palette("nonsense", role: .fill) == nil, "Unknown colours are ignored")
    }

    static func labels() {
        let value = diagram("""
        flowchart TD
        A["Line one<br>Line two"]
        B["`The **cat**
          in the _hat_`"]
        C["Say #quot;hi#quot; &amp; wave #9829;"]
        D[fa:fa-car Drive]
        E["<b>Bold</b> move"]
        F[100%% sure]
        """)
        expect(value.node("A")?.label == "Line one\nLine two", "<br> becomes a new line")
        expect(value.node("B")?.label == "The cat\nin the hat", "Markdown strings keep lines and drop emphasis marks")
        expect(value.node("C")?.label == "Say \"hi\" & wave ♥", "Entities are decoded")
        expect(value.node("D")?.label == "Drive", "Font Awesome icons are dropped")
        expect(value.node("E")?.label == "Bold move", "HTML tags are dropped")
        expect(value.node("F")?.label == "100%% sure", "%% inside a label isn't a comment")
        let comments = diagram("flowchart TD\nA --> B %% trailing note\n%% whole line\nB --> C")
        expect(comments.edges.count == 2 && comments.node("note") == nil, "Comments are ignored")
    }

    static func failures() {
        expect(refusal("flowchart TD\nA --> B\nC[Unclosed --> D") == .syntax(line: 3, detail: "the label for C is missing its closing bracket"),
               "Unclosed labels name their line")
        expect(refusal("flowchart TD\nA -- yes B") == .syntax(line: 2, detail: "an arrow label needs the rest of its arrow, like -- yes -->"),
               "Labels without arrows are refused")
        expect(refusal("flowchart TD\nA -->") == .syntax(line: 2, detail: "this arrow needs something on the other end"),
               "Dangling arrows are refused")
        expect(refusal("flowchart TD\nA B") == .syntax(line: 2, detail: "Parc expected an arrow like --> after A"),
               "Two names in a row are refused")
        expect(refusal("flowchart TD\nA -->|open B") == .syntax(line: 2, detail: "an arrow label is missing its closing |"),
               "Unclosed pipes are refused")
        guard case .syntax(let line, _)? = refusal("flowchart TD\nA\nB\n---> C") else { failTest("A leading arrow is refused") }
        expect(line == 4, "The error points at the bad line")
        expect(EaselMermaidRefusal.syntax(line: 4, detail: "oops").message == "Line 4: oops.", "Syntax messages lead with the line")
        expect(EaselMermaidRefusal.unsupported("Gantt charts").message.hasPrefix("Gantt charts can’t"), "Refusals name the diagram type")
        let many = "flowchart TD\n" + (0..<501).map { "N\($0)" }.joined(separator: "\n")
        expect(refusal(many) == .tooLarge, "More than 500 nodes is too large")
    }

    static func entityRelationships() {
        let value = diagram("""
        erDiagram
            direction LR
            CUSTOMER ||--o{ ORDER : places
            ORDER ||--|{ LINE-ITEM : contains
            CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
            CUSTOMER {
                string name
                string custNumber PK "The ID"
                string sector
            }
            ORDER { int orderNumber PK, FK string deliveryAddress }
            p[Person] {
                string(99) firstName
            }
            CAR 1 to zero or more NAMED-DRIVER : allows
            PERSON only one optionally to one or many CAR : "drives"
            LONELY
        """)
        expect(value.kind == .entityRelationship && value.direction == .right, "erDiagram reads its direction")
        let places = edge(value, "CUSTOMER", "ORDER")
        expect(places?.startHead == .exactlyOne && places?.endHead == .zeroOrMore && places?.label == "places" && places?.line == .solid,
               "||--o{ is exactly one to zero or more")
        expect(edge(value, "ORDER", "LINE-ITEM")?.endHead == .oneOrMore, "|{ is one or more")
        let uses = edge(value, "CUSTOMER", "DELIVERY-ADDRESS")
        expect(uses?.startHead == .oneOrMore && uses?.line == .dotted, "}| is one or more and .. is non-identifying")
        let customer = value.node("CUSTOMER")
        expect(customer?.attributes.count == 3 && customer?.attributes[1].keys == ["PK"] && customer?.attributes[1].comment == "The ID",
               "Attributes keep keys and comments")
        expect(value.node("ORDER")?.attributes.map(\.name) == ["orderNumber", "deliveryAddress"]
               && value.node("ORDER")?.attributes.first?.keys == ["PK", "FK"], "One-line blocks hold several attributes")
        expect(value.node("p")?.label == "Person" && value.node("p")?.attributes.first?.type == "string(99)", "Aliases label entities")
        let allows = edge(value, "CAR", "NAMED-DRIVER")
        expect(allows?.startHead == .exactlyOne && allows?.endHead == .zeroOrMore && allows?.line == .solid, "Word cardinalities are read")
        let drives = edge(value, "PERSON", "CAR")
        expect(drives?.line == .dotted && drives?.endHead == .oneOrMore && drives?.label == "drives", "optionally to is non-identifying")
        expect(value.node("LONELY") != nil && value.nodes.allSatisfy { $0.shape == .entity }, "Bare entities are kept")
        expect(EaselMermaid.displayText(customer ?? EaselMermaidNode(id: "", label: "")) == "CUSTOMER\nstring name\nstring custNumber PK · The ID\nstring sector",
               "Entities list their attributes under the name")
        expect(diagram("erDiagram\nA||--o{B : has").edges.count == 1, "Relationships may skip spaces")
        expect(refusal("erDiagram\nA ||--o{ : has") == .syntax(line: 2, detail: "this relationship needs a second entity"),
               "A missing entity is refused")
        expect(refusal("erDiagram\nA {\n string\n}") == .syntax(line: 2, detail: "the string attribute needs a name"),
               "Attributes need names")
        expect(refusal("erDiagram\nA {\n string name\n") == .syntax(line: 2, detail: "the { after A needs a closing }"),
               "Unclosed blocks are refused")
        expect(refusal("erDiagram\n%% only a comment") == .empty, "An empty ER diagram is empty")
    }

    static func frames(_ text: String) -> (EaselMermaidDiagram, EaselMermaidLayout) {
        let value = diagram(text)
        var sizes: [String: EaselMermaidSize] = [:]
        for node in value.nodes { sizes[node.id] = EaselMermaid.frameSize(node.shape, text: EaselMermaid.estimate(node.label, maximumWidth: 220)) }
        return (value, EaselMermaidLayoutEngine.layout(value, nodeSizes: sizes, labelSizes: [:]))
    }

    static func center(_ rect: EaselRect?) -> EaselPoint {
        guard let rect else { return EaselPoint(x: .nan, y: .nan) }
        return EaselPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
    }

    static func overlaps(_ a: EaselRect, _ b: EaselRect, margin: Double = 0) -> Bool {
        a.x < b.x + b.width + margin && b.x < a.x + a.width + margin && a.y < b.y + b.height + margin && b.y < a.y + a.height + margin
    }

    static func layoutDirections() {
        let (_, down) = frames("flowchart TD\nA --> B --> C")
        expect(center(down.nodes["A"]).y < center(down.nodes["B"]).y && center(down.nodes["B"]).y < center(down.nodes["C"]).y, "TD stacks downward")
        expect(abs(center(down.nodes["A"]).x - center(down.nodes["C"]).x) < 1, "A straight chain stays in one column")
        let (_, up) = frames("flowchart BT\nA --> B")
        expect(center(up.nodes["A"]).y > center(up.nodes["B"]).y, "BT stacks upward")
        let (_, right) = frames("flowchart LR\nA --> B")
        expect(center(right.nodes["A"]).x < center(right.nodes["B"]).x, "LR runs right")
        let (_, left) = frames("flowchart RL\nA --> B")
        expect(center(left.nodes["A"]).x > center(left.nodes["B"]).x, "RL runs left")
        let (_, long) = frames("flowchart TD\nA ---> B\nA --> C")
        expect(center(long.nodes["B"]).y > center(long.nodes["C"]).y, "Longer links skip a rank")
        let all = [down, up, right, left]
        for layout in all {
            let rects = Array(layout.nodes.values)
            expect(rects.allSatisfy { $0.x >= -0.001 && $0.y >= -0.001 }, "Layouts start at the origin")
            expect(rects.allSatisfy { $0.x + $0.width <= layout.width + 0.001 && $0.y + $0.height <= layout.height + 0.001 },
                   "Layouts report their whole size")
        }
    }

    static func layoutSeparation() {
        let (value, layout) = frames("""
        flowchart TD
        Start --> A & B & C & D
        A --> E
        B --> E
        C --> F
        D --> F
        E --> G{Done?}
        F --> G
        G -->|no| Start
        G -->|yes| H((End))
        Lonely1
        Lonely2
        """)
        let rects = value.nodes.compactMap { layout.nodes[$0.id] }
        expect(rects.count == value.nodes.count, "Every node gets a frame")
        for (i, a) in rects.enumerated() {
            for b in rects.dropFirst(i + 1) { expect(!overlaps(a, b, margin: 20), "Nodes keep their distance") }
        }
        expect(center(layout.nodes["Start"]).y < center(layout.nodes["A"]).y, "The back edge doesn't flip the flow")
        let middle = ["A", "B", "C", "D"].map { center(layout.nodes[$0]).x }
        expect(middle == middle.sorted(), "Siblings keep their written order when nothing crosses")
        let again = frames("flowchart TD\nStart --> A & B & C & D\nA --> E\nB --> E\nC --> F\nD --> F\nE --> G{Done?}\nF --> G\nG -->|no| Start\nG -->|yes| H((End))\nLonely1\nLonely2").1
        expect(again == layout, "Layout is deterministic")
        let crossing = frames("flowchart TD\nA --> D\nB --> C\nA --> C2\nB --> D2\nsubgraph x\nend").1
        expect(crossing.nodes.count == 6, "Crossing graphs lay out")
        let isotonic = EaselMermaidLayoutEngine.isotonic([0, 0, 0], weights: [1, 1, 1], gaps: [10, 10])
        expect(isotonic == [-10, 0, 10], "Tied targets spread evenly around them")
        let kept = EaselMermaidLayoutEngine.isotonic([0, 50, 100], weights: [1, 1, 1], gaps: [10, 10])
        expect(kept == [0, 50, 100], "Targets far enough apart stay put")
    }

    static func layoutSections() {
        let (value, layout) = frames("""
        flowchart LR
        x --> a1
        subgraph one [First]
          a1 --> a2
          subgraph deep
            a3
          end
          a2 --> a3
        end
        subgraph two
          direction TB
          b1 --> b2
        end
        a3 --> b1
        y
        subgraph empty
        end
        """)
        guard let one = layout.groups["one"], let two = layout.groups["two"], let deep = layout.groups["deep"],
              let empty = layout.groups["empty"] else { failTest("Every subgraph gets a frame") }
        func inside(_ id: String, _ rect: EaselRect) -> Bool { EaselBoardObjects.encloses(rect, layout.nodes[id] ?? EaselRect(x: -9e9, y: 0, width: 1, height: 1)) }
        expect(inside("a1", one) && inside("a2", one) && inside("a3", one), "Sections hold their nodes")
        expect(inside("a3", deep) && EaselBoardObjects.encloses(one, deep), "Nested sections sit inside their parent")
        expect(inside("b1", two) && inside("b2", two), "The second section holds its nodes")
        for node in value.nodes {
            guard let rect = layout.nodes[node.id] else { continue }
            for (id, frame) in layout.groups where !(node.group == id || (id == "one" && node.group == "deep")) {
                expect(!overlaps(rect, frame), "\(node.id) stays out of \(id)")
            }
        }
        expect(!overlaps(one, two) && !overlaps(one, empty) && !overlaps(two, empty), "Sibling sections don't overlap")
        expect(center(layout.nodes["b1"]).y < center(layout.nodes["b2"]).y, "A section can flow its own way")
        expect(empty.width >= EaselMermaidLayoutEngine.minimumSection.width && empty.height >= EaselMermaidLayoutEngine.minimumSection.height,
               "Empty sections keep a usable size")
        expect(center(layout.nodes["a1"]).y - one.y >= EaselMermaidLayoutEngine.sectionTitleBand, "Sections leave room for their title")
    }

    static func layoutCycles() {
        let (_, loop) = frames("flowchart TD\nA --> B --> C --> A\nC --> C")
        expect(loop.nodes.count == 3, "Cycles lay out")
        let ranks = Set(loop.nodes.values.map { ($0.y * 10).rounded() })
        expect(ranks.count == 3, "A three-step cycle uses three ranks")
        let (_, mutual) = frames("flowchart LR\nA --> B\nB --> A")
        expect(center(mutual.nodes["A"]).x < center(mutual.nodes["B"]).x, "A two-way pair keeps the first link's direction")
    }

    static func mapping() {
        let value = diagram("""
        flowchart TD
        A[Start] --> B{Choose}
        B -.->|later| C([Rest])
        B ==> D[(Store)]
        B --- E((Hub))
        D --o F[\\Manual/]
        C <--> G[[Process]]
        G ~~~ A
        classDef warm fill:#fc9
        class C warm
        subgraph S [Storage]
          D
          F
        end
        """)
        let drawing = EaselMermaid.drawing(value, zIndex: 10)
        let kinds = drawing.items.map(\.kind)
        expect(kinds.filter { $0 == .section }.count == 1 && kinds.first == .section, "Sections come first")
        expect(kinds.filter { $0 == .arrow }.count == 6, "Visible links become arrows and invisible ones don't")
        expect(drawing.items.map(\.zIndex) == Array(10..<(10 + drawing.items.count)), "Items stack from the given z index")
        func item(_ text: String) -> EaselItem? { drawing.items.first { $0.kind != .arrow && $0.text == text } }
        expect(item("Start")?.kind == .rectangle && item("Start")?.shape == nil, "Rectangles stay plain rectangles")
        expect(item("Choose")?.shape == .diamond, "Decisions become diamonds")
        expect(item("Rest")?.shape == .roundedRectangle && item("Rest")?.fill == EaselPalette.hex(.note(.orange), role: .fill),
               "Stadiums are rounded and keep their class colour")
        expect(item("Store")?.shape == .cylinder, "Databases are cylinders")
        expect(item("Hub")?.kind == .circle && item("Hub")?.frame.width == item("Hub")?.frame.height, "Circles stay round")
        expect(item("Manual")?.shape == .trapezoid && item("Manual")?.flipVertical == true, "Wide-top trapezoids flip the trapezoid")
        expect(item("Process")?.shape == .predefinedProcess, "Subroutines are predefined processes")
        expect(item("Storage")?.kind == .section, "Subgraphs become titled sections")
        guard let start = item("Start"), let choose = item("Choose"), let store = item("Store") else { failTest("Shapes exist") }
        let arrows = drawing.items.filter { $0.kind == .arrow }
        guard let first = arrows.first(where: { $0.startConnection?.itemID == start.id }) else { failTest("Start has an arrow") }
        expect(first.endConnection?.itemID == choose.id && first.routing == .elbow, "Arrows connect their shapes with elbow routing")
        expect(first.startConnection?.side == .bottom && first.endConnection?.side == .top, "Downward arrows leave the bottom and enter the top")
        expect(first.startHead == nil && first.endHead == nil, "Plain arrows use the default heads")
        guard let start0 = first.points.first, let end0 = first.points.last else { failTest("Arrows have a route") }
        let startPoint = EaselPoint(x: first.frame.x + start0.x, y: first.frame.y + start0.y)
        let endPoint = EaselPoint(x: first.frame.x + end0.x, y: first.frame.y + end0.y)
        expect(abs(startPoint.y - (start.frame.y + start.frame.height)) < 0.5, "The route starts on the shape's bottom edge")
        expect(abs(endPoint.y - choose.frame.y) < 0.5 && abs(endPoint.x - (choose.frame.x + choose.frame.width / 2)) < 0.5,
               "The route ends on the diamond's top point")
        let later = arrows.first { $0.text == "later" }
        expect(later?.strokeDash == .dashed, "Dotted links are dashed")
        let thick = arrows.first { $0.endConnection?.itemID == store.id }
        expect(thick?.strokeWidth == EaselMermaid.thickStroke, "Thick links are thick")
        expect(arrows.first { $0.endConnection?.itemID == item("Hub")?.id }?.endHead == EaselArrowHead.none, "Open links have no head")
        expect(arrows.first { $0.endConnection?.itemID == item("Manual")?.id }?.endHead == .circle, "Circle ends carry over")
        let both = arrows.first { $0.endConnection?.itemID == item("Process")?.id }
        expect(both?.startHead == .arrow && both?.endHead == nil, "Two-way arrows get a start head")
        guard let section = item("Storage") else { failTest("The section exists") }
        expect(EaselBoardObjects.contains(section, store) && !EaselBoardObjects.contains(section, start), "The section holds only its members")

        let moved = drawing.moved(by: 100, 50)
        expect(moved.items[0].frame.x == drawing.items[0].frame.x + 100 && moved.items[0].frame.y == drawing.items[0].frame.y + 50,
               "Moving a drawing shifts every frame")
        let looped = EaselMermaid.drawing(diagram("flowchart TD\nA --> A"))
        let loopArrow = looped.items.first { $0.kind == .arrow }
        expect(loopArrow?.startConnection?.itemID == loopArrow?.endConnection?.itemID && loopArrow?.startConnection?.side == .right,
               "Self links loop from the side to the top")
        let toGroup = EaselMermaid.drawing(diagram("flowchart LR\nA --> S\nsubgraph S\nB\nend"))
        let groupArrow = toGroup.items.first { $0.kind == .arrow }
        let sectionID = toGroup.items.first { $0.kind == .section }?.id
        expect(groupArrow?.endConnection?.itemID == sectionID && groupArrow?.endConnection?.side == .left, "Links can end on a section")
        let sideways = EaselMermaid.drawing(diagram("flowchart TD\nsubgraph S\ndirection LR\nA --> B\nend\nS --> C"))
        let inner = sideways.items.first { $0.kind == .arrow && $0.startConnection?.itemID == sideways.items.first(where: { $0.text == "A" })?.id }
        expect(inner?.startConnection?.side == .right && inner?.endConnection?.side == .left, "Arrows inside a sideways section run sideways")
        let outer = sideways.items.first { $0.kind == .arrow && $0.startConnection?.itemID == sideways.items.first(where: { $0.kind == .section })?.id }
        expect(outer?.startConnection?.side == .bottom && outer?.endConnection?.side == .top, "Arrows between levels follow the outer flow")
        let stretched = diagram("flowchart TD\nA " + String(repeating: "-", count: 5000) + "> B")
        expect(stretched.edges.first?.length == EaselMermaid.maximumLength, "Very long links are capped")
        let stretchedDrawing = EaselMermaid.drawing(stretched)
        expect(stretchedDrawing.height < 2000, "A capped link keeps the layout reasonable")
        let measured = EaselMermaid.drawing(diagram("flowchart TD\nA[Hello]")) { text, _ in EaselMermaidSize(width: Double(text.count) * 30, height: 40) }
        expect((measured.items.first?.frame.width ?? 0) >= 150, "Shapes grow to fit measured text")
        if let shape = measured.items.first, let rect = EaselShapeGeometry.textRect(for: shape) {
            expect(rect.width >= 150 && rect.height >= 40, "The measured text fits the shape's text area")
        }
        let diamond = EaselMermaid.frameSize(.diamond, text: EaselMermaidSize(width: 100, height: 20))
        let room = EaselShapeGeometry.textRect(.diamond, in: EaselRect(x: 0, y: 0, width: diamond.width, height: diamond.height))
        expect(room.width >= 100 && room.height >= 20, "Diamonds grow until their text fits")
        let wrapped = EaselMermaid.estimate("one two three four five six seven eight nine ten eleven twelve", maximumWidth: 100)
        expect(wrapped.width <= 100 && wrapped.height > 20, "Long labels wrap")
        expect(EaselMermaid.estimate("", maximumWidth: 100).height == 20, "Empty labels keep a line")
    }

    static func entityMapping() {
        let value = diagram("""
        erDiagram
        CUSTOMER ||--o{ ORDER : places
        CUSTOMER { string name PK }
        ORDER }|..|| INVOICE : billed
        """)
        let drawing = EaselMermaid.drawing(value)
        let customer = drawing.items.first { $0.text.hasPrefix("CUSTOMER") }
        expect(customer?.kind == .rectangle && customer?.textStyle?.alignment == .left, "Entities with attributes read left aligned")
        expect(customer?.text == "CUSTOMER\nstring name PK", "Entities show their attributes")
        expect(drawing.headings == Set([customer?.id].compactMap { $0 }), "Only entities with attributes get a heading line")
        let places = drawing.items.first { $0.kind == .arrow && $0.text == "places" }
        expect(places?.startHead == .erdExactlyOne && places?.endHead == .erdZeroOrMore, "Crow's feet carry over")
        let billed = drawing.items.first { $0.kind == .arrow && $0.text == "billed" }
        expect(billed?.startHead == .erdOneOrMore && billed?.endHead == .erdExactlyOne && billed?.strokeDash == .dashed,
               "Non-identifying relationships are dashed")
    }

    static func quickly<T>(_ name: String, _ work: () -> T) -> T {
        let start = Date()
        let value = work()
        expect(Date().timeIntervalSince(start) < 10, "\(name) finishes quickly")
        return value
    }

    static func hostileInput() {
        let wide = (0..<1500).map { "a\($0)" }.joined(separator: "&") + " --> " + (0..<1500).map { "b\($0)" }.joined(separator: "&")
        expect(quickly("A huge & product") { refusal("flowchart TD\n" + wide) } == .tooLarge, "Huge & groups are refused")
        let square = (0..<41).map { "a\($0)" }.joined(separator: "&") + " --> " + (0..<41).map { "b\($0)" }.joined(separator: "&")
        expect(quickly("A modest & product") { refusal("flowchart TD\n" + square) } == .tooLarge, "& products past the arrow limit are refused")
        let repeated = "flowchart TD\n" + String(repeating: "subgraph a\nend\n", count: 3000)
        expect(quickly("Repeated subgraphs") { refusal(repeated) } == .tooLarge, "Too many subgraphs are refused early")
        let twins = diagram("flowchart TD\nsubgraph a\nx\nend\nsubgraph a\ny\nend\nsubgraph a\nz\nend")
        expect(twins.groups.map(\.id) == ["a", "a_2", "a_3"], "Repeated subgraph names get numbered")
        let looped = "flowchart TD\n" + Array(repeating: "A(-x)", count: 900).joined(separator: " --> ")
        let loop = quickly("Fallback label scans") { diagram(looped) }
        expect(loop.nodes.count == 1 && loop.node("A")?.label == "-x" && loop.edges.count == 899, "Fallback labels stay cheap and right")
        let ampersands = "flowchart TD\n" + Array(repeating: "A(-x)", count: 12_000).joined(separator: "&")
        expect(quickly("A long & list") { refusal(ampersands) } == .tooLarge, "Endless & lists are refused")
        let chain = "flowchart TD\n" + (0..<5000).map { "n\($0)" }.joined(separator: " --> ")
        expect(quickly("A long chain") { refusal(chain) } == .tooLarge, "Chains past the arrow limit are refused")
        let styled = "flowchart TD\n" + String(repeating: "a --> b\n", count: 900) + String(repeating: "linkStyle default stroke:red\n", count: 4000)
        let restyled = quickly("Repeated linkStyle default") { diagram(styled) }
        expect(restyled.edges.allSatisfy { $0.style.stroke == EaselPalette.hex(.note(.red), role: .ink) }, "Repeated default styles still apply")
        let lines = "flowchart TD\n" + (0..<600).map { "n\($0)" }.joined(separator: "\n")
        expect(quickly("Too many nodes") { refusal(lines) } == .tooLarge, "More nodes than the limit are refused early")
        let entities = "erDiagram\n" + (0..<600).map { "E\($0)" }.joined(separator: "\n")
        expect(quickly("Too many entities") { refusal(entities) } == .tooLarge, "More entities than the limit are refused")
        let attributes = "erDiagram\nA {\n" + String(repeating: "string name\n", count: 150) + "}"
        expect(quickly("Too many attributes") { refusal(attributes) } == .tooLarge, "More attributes than the limit are refused")
        let relationships = "erDiagram\n" + String(repeating: "A ||--o{ B : has\n", count: 1500)
        expect(quickly("Too many relationships") { refusal(relationships) } == .tooLarge, "More relationships than the limit are refused")
        let unclosed = "flowchart TD\nA(-" + String(repeating: "(", count: 100_000)
        expect(quickly("An unclosed label") { refusal(unclosed) }.map { if case .syntax = $0 { return true } else { return false } } == true,
               "Unclosed nesting is a quick syntax error")
        expect(refusal("Graph\nLogin\nDashboard") == .notMermaid && refusal("Flowchart TD\nA-->B") == .notMermaid
               && refusal("ErDiagram\nA") == .notMermaid, "Diagram keywords are case-sensitive like Mermaid's")
        var spine = (0..<400).map { "n\($0)" }.joined(separator: " ---------> ") + "\n"
        spine += String(repeating: "n0 --> n399\n", count: 500)
        let tall = quickly("Long links over a long spine") { EaselMermaid.drawing(diagram("flowchart TD\n" + spine)) }
        expect(tall.height < EaselRect.maximumCoordinate / 2 && tall.items.allSatisfy { $0.frame.y + $0.frame.height < tall.height + 1 },
               "Long links over a long spine stay inside the Easel")
        let dashes = String(repeating: "-", count: 100_000)
        let stretched = quickly("A 100k dash arrow") { diagram("flowchart TD\nA " + dashes + "> B") }
        expect(stretched.edges.count == 1 && stretched.edges[0].length <= EaselMermaid.maximumLength, "Arrow length is clamped")
        let stretchedDrawing = EaselMermaid.drawing(stretched)
        expect(stretchedDrawing.height < EaselRect.maximumCoordinate / 2, "A clamped arrow draws a small layout")
        let heavy = "flowchart LR\n" + (0..<300).map { "n\($0)[\"" + String(repeating: "w ", count: 100) + "\"]" }.joined(separator: "\n")
        let heavyDrawing = quickly("Heavy labels") { EaselMermaid.drawing(diagram(heavy)) }
        expect(heavyDrawing.width.isFinite && heavyDrawing.height.isFinite, "Heavy labels lay out to finite sizes")
        let repeatedParse = "flowchart TD\nA --> B"
        let first = EaselMermaid.parse(repeatedParse), second = EaselMermaid.parse(repeatedParse)
        expect(first == second, "Parsing the same text twice agrees")
        let label = "flowchart TD\nA[\"" + String(repeating: "**a** ", count: 50_000) + "\"]"
        expect(quickly("A giant label") { diagram(label) }.node("A").map { $0.label.count <= EaselMermaidText.maximumLength } == true,
               "Giant labels are cut short")
    }

    static func validation() {
        let sources = [
            "flowchart TD\nA[Start] --> B{Choose}\nB -->|yes| C\nB -->|no| D\nC --> A\nsubgraph S\nC\nD\nend\nS --> E",
            "graph LR\nA((a)) --o B[(b)] -.-x C>c] ==> D{{d}}\nD --> D\nclassDef c fill:#f9f,stroke:#333,stroke-width:9px\nclass A,B c",
            "erDiagram\nA ||--o{ B : has\nB }|..|{ C : uses\nA { int id PK \"key\" }\nA ||--|| A : self",
            "flowchart TD\nA@{ shape: text, label: \"Free text\" } --> B@{ shape: tri }\nB --> C@{ shape: flip-tri }",
        ]
        for source in sources {
            let drawing = EaselMermaid.drawing(diagram(source), zIndex: 3).moved(by: 40, 40)
            let document = EaselDocument(id: UUID(), title: "Diagram", createdAt: Date(), modifiedAt: Date(), items: drawing.items)
            do { _ = try EaselSession(inMemory: document, assets: [:]) }
            catch { failTest("A drawn diagram is a valid Easel: \(error) for\n\(source)") }
            expect(Set(drawing.items.map(\.id)).count == drawing.items.count, "Every drawn object has its own ID")
        }
    }
}
