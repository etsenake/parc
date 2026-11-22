import Foundation
import Testing
@testable import ParcCore

struct EaselMermaidEntityRelationshipTests {
    private func sampleDiagram() throws -> EaselMermaidDiagram {
        try EaselMermaidTestsSupport.diagram("""
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
    }

    @Test
    func theERHeaderReadsItsDirection() throws {
        let value = try sampleDiagram()
        #expect(value.kind == .entityRelationship && value.direction == .right, "erDiagram reads its direction")
    }

    @Test
    func symbolicRelationshipsSetCardinalityLineAndLabel() throws {
        let value = try sampleDiagram()
        let places = EaselMermaidTestsSupport.edge(value, "CUSTOMER", "ORDER")
        #expect(places?.startHead == .exactlyOne && places?.endHead == .zeroOrMore && places?.label == "places" && places?.line == .solid, "||--o{ is exactly one to zero or more")
        #expect(EaselMermaidTestsSupport.edge(value, "ORDER", "LINE-ITEM")?.endHead == .oneOrMore, "|{ is one or more")
        let uses = EaselMermaidTestsSupport.edge(value, "CUSTOMER", "DELIVERY-ADDRESS")
        #expect(uses?.startHead == .oneOrMore && uses?.line == .dotted, "}| is one or more and .. is non-identifying")
    }

    @Test
    func attributeBlocksKeepNamesKeysAndComments() throws {
        let value = try sampleDiagram()
        let customer = value.node("CUSTOMER")
        #expect(customer?.attributes.count == 3 && customer?.attributes[1].keys == ["PK"] && customer?.attributes[1].comment == "The ID", "Attributes keep keys and comments")
        #expect(value.node("ORDER")?.attributes.map(\.name) == ["orderNumber", "deliveryAddress"]
               && value.node("ORDER")?.attributes.first?.keys == ["PK", "FK"], "One-line blocks hold several attributes")
    }

    @Test
    func aliasesProvideTheEntityLabel() throws {
        let value = try sampleDiagram()
        #expect(value.node("p")?.label == "Person" && value.node("p")?.attributes.first?.type == "string(99)", "Aliases label entities")
    }

    @Test
    func wordRelationshipsSetCardinalityLineAndLabel() throws {
        let value = try sampleDiagram()
        let allows = EaselMermaidTestsSupport.edge(value, "CAR", "NAMED-DRIVER")
        #expect(allows?.startHead == .exactlyOne && allows?.endHead == .zeroOrMore && allows?.line == .solid, "Word cardinalities are read")
        let drives = EaselMermaidTestsSupport.edge(value, "PERSON", "CAR")
        #expect(drives?.line == .dotted && drives?.endHead == .oneOrMore && drives?.label == "drives", "optionally to is non-identifying")
    }

    @Test
    func bareEntitiesAreKept() throws {
        let value = try sampleDiagram()
        #expect(value.node("LONELY") != nil && value.nodes.allSatisfy { $0.shape == .entity }, "Bare entities are kept")
    }

    @Test
    func entitiesDisplayAttributesUnderTheirName() throws {
        let value = try sampleDiagram()
        let customer = value.node("CUSTOMER")
        #expect(EaselMermaid.displayText(customer ?? EaselMermaidNode(id: "", label: "")) == "CUSTOMER\nstring name\nstring custNumber PK · The ID\nstring sector", "Entities list their attributes under the name")
    }

    @Test
    func relationshipsCanOmitSpaces() throws {
        #expect(try EaselMermaidTestsSupport.diagram("erDiagram\nA||--o{B : has").edges.count == 1, "Relationships may skip spaces")
    }

    @Test
    func relationshipsRequireASecondEntity() {
        #expect(EaselMermaidTestsSupport.refusal("erDiagram\nA ||--o{ : has") == .syntax(line: 2, detail: "this relationship needs a second entity"), "A missing entity is refused")
    }

    @Test
    func attributesRequireNames() {
        #expect(EaselMermaidTestsSupport.refusal("erDiagram\nA {\n string\n}") == .syntax(line: 2, detail: "the string attribute needs a name"), "Attributes need names")
    }

    @Test
    func attributeBlocksRequireAClosingBrace() {
        #expect(EaselMermaidTestsSupport.refusal("erDiagram\nA {\n string name\n") == .syntax(line: 2, detail: "the { after A needs a closing }"), "Unclosed blocks are refused")
    }

    @Test
    func aCommentOnlyERDiagramIsEmpty() {
        #expect(EaselMermaidTestsSupport.refusal("erDiagram\n%% only a comment") == .empty, "An empty ER diagram is empty")
    }

    @Test func entitiesWithAttributesReadLeftAligned() throws {
        let value = try EaselMermaidTestsSupport.diagram("""
        erDiagram
        CUSTOMER ||--o{ ORDER : places
        CUSTOMER { string name PK }
        ORDER }|..|| INVOICE : billed
        """)
        let drawing = EaselMermaid.drawing(value)
        let customer = drawing.items.first { $0.text.hasPrefix("CUSTOMER") }
        #expect(customer?.kind == .rectangle && customer?.textStyle?.alignment == .left, "Entities with attributes read left aligned")
        #expect(customer?.text == "CUSTOMER\nstring name PK", "Entities show their attributes")
        #expect(drawing.headings == Set([customer?.id].compactMap { $0 }), "Only entities with attributes get a heading line")
        let places = drawing.items.first { $0.kind == .arrow && $0.text == "places" }
        #expect(places?.startHead == .erdExactlyOne && places?.endHead == .erdZeroOrMore, "Crow's feet carry over")
        let billed = drawing.items.first { $0.kind == .arrow && $0.text == "billed" }
        #expect(billed?.startHead == .erdOneOrMore && billed?.endHead == .erdExactlyOne && billed?.strokeDash == .dashed, "Non-identifying relationships are dashed")
    }
}
