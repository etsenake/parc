import Foundation
import Testing
@testable import ParcCore

struct EaselMermaidLayoutTests {
    private func branchingGraph() throws -> (EaselMermaidDiagram, EaselMermaidLayout) {
        return try EaselMermaidTestsSupport.frames("""
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
    }

    @Test
    func topDownChainsStackInOneColumn() throws {
        let (_, down) = try EaselMermaidTestsSupport.frames("flowchart TD\nA --> B --> C")
        #expect(EaselMermaidTestsSupport.center(down.nodes["A"]).y < EaselMermaidTestsSupport.center(down.nodes["B"]).y && EaselMermaidTestsSupport.center(down.nodes["B"]).y < EaselMermaidTestsSupport.center(down.nodes["C"]).y, "TD stacks downward")
        #expect(abs(EaselMermaidTestsSupport.center(down.nodes["A"]).x - EaselMermaidTestsSupport.center(down.nodes["C"]).x) < 1, "A straight chain stays in one column")
    }

    @Test
    func bottomUpChainsStackUpward() throws {
        let (_, up) = try EaselMermaidTestsSupport.frames("flowchart BT\nA --> B")
        #expect(EaselMermaidTestsSupport.center(up.nodes["A"]).y > EaselMermaidTestsSupport.center(up.nodes["B"]).y, "BT stacks upward")
    }

    @Test
    func leftToRightChainsRunRight() throws {
        let (_, right) = try EaselMermaidTestsSupport.frames("flowchart LR\nA --> B")
        #expect(EaselMermaidTestsSupport.center(right.nodes["A"]).x < EaselMermaidTestsSupport.center(right.nodes["B"]).x, "LR runs right")
    }

    @Test
    func rightToLeftChainsRunLeft() throws {
        let (_, left) = try EaselMermaidTestsSupport.frames("flowchart RL\nA --> B")
        #expect(EaselMermaidTestsSupport.center(left.nodes["A"]).x > EaselMermaidTestsSupport.center(left.nodes["B"]).x, "RL runs left")
    }

    @Test
    func longerLinksSkipARank() throws {
        let (_, long) = try EaselMermaidTestsSupport.frames("flowchart TD\nA ---> B\nA --> C")
        #expect(EaselMermaidTestsSupport.center(long.nodes["B"]).y > EaselMermaidTestsSupport.center(long.nodes["C"]).y, "Longer links skip a rank")
    }

    @Test
    func eachDirectionReportsItsWholeLayoutFromTheOrigin() throws {
        let (_, down) = try EaselMermaidTestsSupport.frames("flowchart TD\nA --> B --> C")
        let (_, up) = try EaselMermaidTestsSupport.frames("flowchart BT\nA --> B")
        let (_, right) = try EaselMermaidTestsSupport.frames("flowchart LR\nA --> B")
        let (_, left) = try EaselMermaidTestsSupport.frames("flowchart RL\nA --> B")
        let all = [down, up, right, left]
        for layout in all {
            let rects = Array(layout.nodes.values)
            #expect(rects.allSatisfy { $0.x >= -0.001 && $0.y >= -0.001 }, "Layouts start at the origin")
            #expect(rects.allSatisfy { $0.x + $0.width <= layout.width + 0.001 && $0.y + $0.height <= layout.height + 0.001 }, "Layouts report their whole size")
        }
    }

    @Test
    func nodesGetFramesWithSpaceBetweenThem() throws {
        let (value, layout) = try branchingGraph()
        let rects = value.nodes.compactMap { layout.nodes[$0.id] }
        #expect(rects.count == value.nodes.count, "Every node gets a frame")
        for (i, a) in rects.enumerated() {
            for b in rects.dropFirst(i + 1) { #expect(!EaselMermaidTestsSupport.overlaps(a, b, margin: 20), "Nodes keep their distance") }
        }
    }

    @Test
    func backEdgesDoNotReverseFlow() throws {
        let (_, layout) = try branchingGraph()
        #expect(EaselMermaidTestsSupport.center(layout.nodes["Start"]).y < EaselMermaidTestsSupport.center(layout.nodes["A"]).y, "The back edge doesn't flip the flow")
    }

    @Test
    func siblingsKeepTheirWrittenOrderWhenPathsDoNotCross() throws {
        let (_, layout) = try branchingGraph()
        let middle = ["A", "B", "C", "D"].map { EaselMermaidTestsSupport.center(layout.nodes[$0]).x }
        #expect(middle == middle.sorted(), "Siblings keep their written order when nothing crosses")
    }

    @Test
    func aLayoutIsDeterministic() throws {
        let (_, layout) = try branchingGraph()
        let again = try EaselMermaidTestsSupport.frames("flowchart TD\nStart --> A & B & C & D\nA --> E\nB --> E\nC --> F\nD --> F\nE --> G{Done?}\nF --> G\nG -->|no| Start\nG -->|yes| H((End))\nLonely1\nLonely2").1
        #expect(again == layout, "Layout is deterministic")
    }

    @Test
    func crossingGraphsGiveEveryNodeAFrame() throws {
        let crossing = try EaselMermaidTestsSupport.frames("flowchart TD\nA --> D\nB --> C\nA --> C2\nB --> D2\nsubgraph x\nend").1
        #expect(crossing.nodes.count == 6, "Crossing graphs lay out")
    }

    @Test
    func tiedIsotonicTargetsSpreadEvenly() {
        let isotonic = EaselMermaidLayoutEngine.isotonic([0, 0, 0], weights: [1, 1, 1], gaps: [10, 10])
        #expect(isotonic == [-10, 0, 10], "Tied targets spread evenly around them")
    }

    @Test
    func spacedIsotonicTargetsStayInPlace() {
        let kept = EaselMermaidLayoutEngine.isotonic([0, 50, 100], weights: [1, 1, 1], gaps: [10, 10])
        #expect(kept == [0, 50, 100], "Targets far enough apart stay put")
    }

    @Test func sectionsHoldTheirNodes() throws {
        let (value, layout) = try EaselMermaidTestsSupport.frames("""
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
              let empty = layout.groups["empty"] else { Issue.record("Every subgraph gets a frame"); return }
        func inside(_ id: String, _ rect: EaselRect) -> Bool { EaselBoardObjects.encloses(rect, layout.nodes[id] ?? EaselRect(x: -9e9, y: 0, width: 1, height: 1)) }
        #expect(inside("a1", one) && inside("a2", one) && inside("a3", one), "Sections hold their nodes")
        #expect(inside("a3", deep) && EaselBoardObjects.encloses(one, deep), "Nested sections sit inside their parent")
        #expect(inside("b1", two) && inside("b2", two), "The second section holds its nodes")
        for node in value.nodes {
            guard let rect = layout.nodes[node.id] else { continue }
            for (id, frame) in layout.groups where !(node.group == id || (id == "one" && node.group == "deep")) {
                #expect(!EaselMermaidTestsSupport.overlaps(rect, frame), "\(node.id) stays out of \(id)")
            }
        }
        #expect(!EaselMermaidTestsSupport.overlaps(one, two) && !EaselMermaidTestsSupport.overlaps(one, empty) && !EaselMermaidTestsSupport.overlaps(two, empty), "Sibling sections don't overlap")
        #expect(EaselMermaidTestsSupport.center(layout.nodes["b1"]).y < EaselMermaidTestsSupport.center(layout.nodes["b2"]).y, "A section can flow its own way")
        #expect(empty.width >= EaselMermaidLayoutEngine.minimumSection.width && empty.height >= EaselMermaidLayoutEngine.minimumSection.height, "Empty sections keep a usable size")
        #expect(EaselMermaidTestsSupport.center(layout.nodes["a1"]).y - one.y >= EaselMermaidLayoutEngine.sectionTitleBand, "Sections leave room for their title")
    }

    @Test func cyclesLayOut() throws {
        let (_, loop) = try EaselMermaidTestsSupport.frames("flowchart TD\nA --> B --> C --> A\nC --> C")
        #expect(loop.nodes.count == 3, "Cycles lay out")
        let ranks = Set(loop.nodes.values.map { ($0.y * 10).rounded() })
        #expect(ranks.count == 3, "A three-step cycle uses three ranks")
        let (_, mutual) = try EaselMermaidTestsSupport.frames("flowchart LR\nA --> B\nB --> A")
        #expect(EaselMermaidTestsSupport.center(mutual.nodes["A"]).x < EaselMermaidTestsSupport.center(mutual.nodes["B"]).x, "A two-way pair keeps the first link's direction")
    }

}
