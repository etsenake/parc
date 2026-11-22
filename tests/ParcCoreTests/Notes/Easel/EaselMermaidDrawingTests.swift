import Foundation
import Testing
@testable import ParcCore

struct EaselMermaidDrawingTests {
    private func item(_ text: String, in drawing: EaselMermaidDrawing) -> EaselItem? {
        drawing.items.first { $0.kind != .arrow && $0.text == text }
    }

    private func sampleDrawing() throws -> EaselMermaidDrawing {
        let value = try EaselMermaidTestsSupport.diagram("""
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
        return EaselMermaid.drawing(value, zIndex: 10)
    }

    @Test
    func sectionsDrawBelowTheirNodesAndConnectors() throws {
        let drawing = try sampleDrawing()
        let kinds = drawing.items.map(\.kind)
        #expect(kinds.filter { $0 == .section }.count == 1 && kinds.first == .section, "Sections come first")
        #expect(kinds.filter { $0 == .arrow }.count == 6, "Visible links become arrows and invisible ones don't")
        #expect(drawing.items.map(\.zIndex) == Array(10..<(10 + drawing.items.count)), "Items stack from the given z index")
    }

    @Test
    func nodesRenderAsTheirCorrespondingShapes() throws {
        let drawing = try sampleDrawing()
        #expect(item("Start", in: drawing)?.kind == .rectangle && item("Start", in: drawing)?.shape == nil, "Rectangles stay plain rectangles")
        #expect(item("Choose", in: drawing)?.shape == .diamond, "Decisions become diamonds")
        #expect(item("Rest", in: drawing)?.shape == .roundedRectangle && item("Rest", in: drawing)?.fill == EaselPalette.hex(.note(.orange), role: .fill), "Stadiums are rounded and keep their class colour")
        #expect(item("Store", in: drawing)?.shape == .cylinder, "Databases are cylinders")
        #expect(item("Hub", in: drawing)?.kind == .circle && item("Hub", in: drawing)?.frame.width == item("Hub", in: drawing)?.frame.height, "Circles stay round")
        #expect(item("Manual", in: drawing)?.shape == .trapezoid && item("Manual", in: drawing)?.flipVertical == true, "Wide-top trapezoids flip the trapezoid")
        #expect(item("Process", in: drawing)?.shape == .predefinedProcess, "Subroutines are predefined processes")
        #expect(item("Storage", in: drawing)?.kind == .section, "Subgraphs become titled sections")
    }

    @Test
    func arrowsUseElbowRoutesBetweenTheShapes() throws {
        let drawing = try sampleDrawing()
        guard let start = item("Start", in: drawing), let choose = item("Choose", in: drawing) else { Issue.record("Shapes exist"); return }
        let arrows = drawing.items.filter { $0.kind == .arrow }
        let first = try #require(arrows.first(where: { $0.startConnection?.itemID == start.id }), "Start has an arrow")
        #expect(first.endConnection?.itemID == choose.id && first.routing == .elbow, "Arrows connect their shapes with elbow routing")
        #expect(first.startConnection?.side == .bottom && first.endConnection?.side == .top, "Downward arrows leave the bottom and enter the top")
        #expect(first.startHead == nil && first.endHead == nil, "Plain arrows use the default heads")
        guard let start0 = first.points.first, let end0 = first.points.last else { Issue.record("Arrows have a route"); return }
        let startPoint = EaselPoint(x: first.frame.x + start0.x, y: first.frame.y + start0.y)
        let endPoint = EaselPoint(x: first.frame.x + end0.x, y: first.frame.y + end0.y)
        #expect(abs(startPoint.y - (start.frame.y + start.frame.height)) < 0.5, "The route starts on the shape's bottom edge")
        #expect(abs(endPoint.y - choose.frame.y) < 0.5 && abs(endPoint.x - (choose.frame.x + choose.frame.width / 2)) < 0.5, "The route ends on the diamond's top point")
    }

    @Test
    func arrowStyleCarriesOverFromVisibleLinks() throws {
        let drawing = try sampleDrawing()
        let store = try #require(item("Store", in: drawing))
        let arrows = drawing.items.filter { $0.kind == .arrow }
        let later = arrows.first { $0.text == "later" }
        #expect(later?.strokeDash == .dashed, "Dotted links are dashed")
        let thick = arrows.first { $0.endConnection?.itemID == store.id }
        #expect(thick?.strokeWidth == EaselMermaid.thickStroke, "Thick links are thick")
        #expect(arrows.first { $0.endConnection?.itemID == item("Hub", in: drawing)?.id }?.endHead == EaselArrowHead.none, "Open links have no head")
        #expect(arrows.first { $0.endConnection?.itemID == item("Manual", in: drawing)?.id }?.endHead == .circle, "Circle ends carry over")
        let both = arrows.first { $0.endConnection?.itemID == item("Process", in: drawing)?.id }
        #expect(both?.startHead == .arrow && both?.endHead == nil, "Two-way arrows get a start head")
    }

    @Test
    func theSectionHoldsOnlyItsMembers() throws {
        let drawing = try sampleDrawing()
        guard let start = item("Start", in: drawing), let store = item("Store", in: drawing) else { Issue.record("Shapes exist"); return }
        let section = try #require(item("Storage", in: drawing), "The section exists")
        #expect(EaselBoardObjects.contains(section, store) && !EaselBoardObjects.contains(section, start), "The section holds only its members")
    }

    @Test
    func movingADrawingShiftsItsFrames() throws {
        let drawing = try sampleDrawing()
        let moved = drawing.moved(by: 100, 50)
        #expect(moved.items[0].frame.x == drawing.items[0].frame.x + 100 && moved.items[0].frame.y == drawing.items[0].frame.y + 50, "Moving a drawing shifts every frame")
    }

    @Test
    func selfLinksRouteFromTheSide() throws {
        let looped = EaselMermaid.drawing(try EaselMermaidTestsSupport.diagram("flowchart TD\nA --> A"))
        let loopArrow = looped.items.first { $0.kind == .arrow }
        #expect(loopArrow?.startConnection?.itemID == loopArrow?.endConnection?.itemID && loopArrow?.startConnection?.side == .right, "Self links loop from the side to the top")
    }

    @Test
    func linksCanEndOnASection() throws {
        let toGroup = EaselMermaid.drawing(try EaselMermaidTestsSupport.diagram("flowchart LR\nA --> S\nsubgraph S\nB\nend"))
        let groupArrow = toGroup.items.first { $0.kind == .arrow }
        let sectionID = toGroup.items.first { $0.kind == .section }?.id
        #expect(groupArrow?.endConnection?.itemID == sectionID && groupArrow?.endConnection?.side == .left, "Links can end on a section")
    }

    @Test
    func innerAndOuterLinksFollowTheirSectionDirection() throws {
        let sideways = EaselMermaid.drawing(try EaselMermaidTestsSupport.diagram("flowchart TD\nsubgraph S\ndirection LR\nA --> B\nend\nS --> C"))
        let inner = sideways.items.first { $0.kind == .arrow && $0.startConnection?.itemID == sideways.items.first(where: { $0.text == "A" })?.id }
        #expect(inner?.startConnection?.side == .right && inner?.endConnection?.side == .left, "Arrows inside a sideways section run sideways")
        let outer = sideways.items.first { $0.kind == .arrow && $0.startConnection?.itemID == sideways.items.first(where: { $0.kind == .section })?.id }
        #expect(outer?.startConnection?.side == .bottom && outer?.endConnection?.side == .top, "Arrows between levels follow the outer flow")
    }

    @Test
    func longLinksAreCappedBeforeLayout() throws {
        let stretched = try EaselMermaidTestsSupport.diagram("flowchart TD\nA " + String(repeating: "-", count: 5000) + "> B")
        #expect(stretched.edges.first?.length == EaselMermaid.maximumLength, "Very long links are capped")
        let stretchedDrawing = EaselMermaid.drawing(stretched)
        #expect(stretchedDrawing.height < 2000, "A capped link keeps the layout reasonable")
    }

    @Test
    func shapeFramesFitMeasuredLabels() throws {
        let measured = EaselMermaid.drawing(try EaselMermaidTestsSupport.diagram("flowchart TD\nA[Hello]")) { text, _ in EaselMermaidSize(width: Double(text.count) * 30, height: 40) }
        #expect((measured.items.first?.frame.width ?? 0) >= 150, "Shapes grow to fit measured text")
        if let shape = measured.items.first, let rect = EaselShapeGeometry.textRect(for: shape) {
            #expect(rect.width >= 150 && rect.height >= 40, "The measured text fits the shape's text area")
        }
    }

    @Test
    func diamondsGrowToFitTheirText() {
        let diamond = EaselMermaid.frameSize(.diamond, text: EaselMermaidSize(width: 100, height: 20))
        let room = EaselShapeGeometry.textRect(.diamond, in: EaselRect(x: 0, y: 0, width: diamond.width, height: diamond.height))
        #expect(room.width >= 100 && room.height >= 20, "Diamonds grow until their text fits")
    }

    @Test
    func labelsWrapAtTheMaximumWidthAndEmptyLabelsKeepALine() {
        let wrapped = EaselMermaid.estimate("one two three four five six seven eight nine ten eleven twelve", maximumWidth: 100)
        #expect(wrapped.width <= 100 && wrapped.height > 20, "Long labels wrap")
        #expect(EaselMermaid.estimate("", maximumWidth: 100).height == 20, "Empty labels keep a line")
    }

    @MainActor @Test(arguments: [
            "flowchart TD\nA[Start] --> B{Choose}\nB -->|yes| C\nB -->|no| D\nC --> A\nsubgraph S\nC\nD\nend\nS --> E",
            "graph LR\nA((a)) --o B[(b)] -.-x C>c] ==> D{{d}}\nD --> D\nclassDef c fill:#f9f,stroke:#333,stroke-width:9px\nclass A,B c",
            "erDiagram\nA ||--o{ B : has\nB }|..|{ C : uses\nA { int id PK \"key\" }\nA ||--|| A : self",
            "flowchart TD\nA@{ shape: text, label: \"Free text\" } --> B@{ shape: tri }\nB --> C@{ shape: flip-tri }",
    ])
    func everyDrawnObjectHasItsOwnID(_ source: String) throws {
        let drawing = EaselMermaid.drawing(try EaselMermaidTestsSupport.diagram(source), zIndex: 3).moved(by: 40, 40)
        let document = EaselDocument(id: UUID(), title: "Diagram", createdAt: Date(), modifiedAt: Date(), items: drawing.items)
        do { _ = try EaselSession(inMemory: document, assets: [:]) }
        catch { Issue.record("A drawn diagram is a valid Easel: \(error) for\n\(source)") }
        #expect(Set(drawing.items.map(\.id)).count == drawing.items.count, "Every drawn object has its own ID")
    }
}
