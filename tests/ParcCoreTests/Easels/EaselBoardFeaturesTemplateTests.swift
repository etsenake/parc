import Foundation
import Testing
@testable import ParcCore

struct EaselBoardFeaturesTemplateTests {
    @Test(arguments: EaselTemplate.allCases)
    func templateConnectorsReferenceObjectsInsideTheTemplate(_ template: EaselTemplate) {
        let drawing = EaselTemplates.drawing(template)
        let ids = Set(drawing.items.map(\.id))
        #expect(drawing.items.filter { $0.kind == .arrow }.allSatisfy { arrow in
            [arrow.startConnection?.itemID, arrow.endConnection?.itemID].allSatisfy { $0.map(ids.contains) == true }
        })
    }

    @Test(arguments: EaselTemplate.allCases)
    func templateSectionsCollectTheirContents(_ template: EaselTemplate) {
        let drawing = EaselTemplates.drawing(template)
        #expect(drawing.items.filter { $0.kind == .section }.allSatisfy {
            !EaselBoardObjects.contents(of: $0, in: drawing.items).isEmpty || template == .moodboard
        })
    }

    @MainActor @Test(arguments: EaselTemplate.allCases)
    func aPlacedTemplateFormsAValidBoard(_ template: EaselTemplate) throws {
        let base = EaselTemplates.drawing(template)
        #expect(!base.items.isEmpty && Set(base.items.map(\.id)).count == base.items.count, "\(template.title) has unique objects")
        let visible = EaselRect(x: 2000, y: 3000, width: 1400, height: 900)
        let placed = EaselTemplates.placed(template, centeredAt: EaselPoint(x: 2700, y: 3450), within: visible, firstZIndex: 10)
        let document = EaselDocument(id: UUID(), title: template.title, createdAt: Date(timeIntervalSince1970: 0), modifiedAt: Date(timeIntervalSince1970: 0), items: placed.items)
        _ = try EaselSession(inMemory: document, assets: [:])
    }

    @Test(arguments: EaselTemplate.allCases)
    func aPlacedTemplateLandsInViewAndAboveExistingObjects(_ template: EaselTemplate) {
        let base = EaselTemplates.drawing(template)
        let visible = EaselRect(x: 2000, y: 3000, width: 1400, height: 900)
        let placed = EaselTemplates.placed(template, centeredAt: EaselPoint(x: 2700, y: 3450), within: visible, firstZIndex: 10)
        #expect(placed.items.count == base.items.count && placed.items.map(\.zIndex) == Array(10..<(10 + base.items.count)),
               "\(template.title) lands above everything in its own order")
        #expect(placed.bounds.x >= visible.x && placed.bounds.y >= visible.y, "\(template.title) lands in view")
        let corner = EaselTemplates.placed(template, centeredAt: EaselPoint(x: 0, y: 0), firstZIndex: 0)
        #expect(corner.bounds.x >= EaselTemplates.margin.x && corner.bounds.y >= EaselTemplates.margin.y, "\(template.title) never lands off the board")
    }
}
