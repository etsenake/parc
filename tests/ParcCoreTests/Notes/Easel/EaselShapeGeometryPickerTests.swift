import Foundation
import Testing
@testable import ParcCore

@MainActor struct EaselShapeGeometryPickerTests {
    @Test
    func newCirclesKeepTheLegacyCircleKind() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        let circle = EaselShapeStyle.newItem(.ellipse, frame: frame, ink: "#252525", zIndex: 3)
        #expect(circle.kind == .circle && circle.shape == nil && circle.resolvedShape == .ellipse && circle.zIndex == 3, "New circles stay circle objects so older Parc versions still draw them round")
    }

    @Test
    func newShapesStartWithAnExplicitBlueStyle() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        let star = EaselShapeStyle.newItem(.star, frame: frame, ink: "#252525", zIndex: 1)
        #expect(star.kind == .rectangle && star.shape == .star && star.fill != nil && star.fillOpacity == 1
               && star.strokeWidth == EaselPaintRules.shapeWidth, "New shapes save explicit modern styles")
        #expect(star.color == EaselPalette.hex(.note(.blue), role: .ink) && star.fill == EaselPalette.hex(.note(.blue), role: .fill), "With the default ink, new shapes come in the friendly blue pair")
    }

    @Test
    func paletteInkBringsItsMatchingFill() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        if let redInk = EaselPalette.hex(.note(.red), role: .ink) {
            let red = EaselShapeStyle.newItem(.hexagon, frame: frame, ink: redInk, zIndex: 1)
            #expect(red.color == redInk && red.fill == EaselPalette.hex(.note(.red), role: .fill), "A chosen palette ink brings its matching fill")
        } else { Issue.record("The palette has a red ink") }
    }

    @Test
    func customInkGetsNeutralFill() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        let custom = EaselShapeStyle.newItem(.cylinder, frame: frame, ink: "#123456", zIndex: 1)
        #expect(custom.color == "#123456" && custom.fill == EaselPalette.hex(.neutral, role: .fill), "Custom inks get a neutral fill")
    }

    @Test
    func everyNewShapeCanBeSaved() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        let document = EaselDocument(id: UUID(), title: "Shapes", createdAt: Date(), modifiedAt: Date(),
                                     items: EaselShape.allCases.enumerated().map { index, shape in
                                         EaselShapeStyle.newItem(shape, frame: frame, ink: "#252525", zIndex: index)
                                     })
        do { _ = try EaselSession(inMemory: document, assets: [:]) } catch { Issue.record("Every new shape saves as a valid Easel: \(error)") }
    }

    @Test
    func changingShapeKeepsTheFrameTextStyleAndIdentity() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        var legacy = EaselItem(kind: .circle, frame: frame, text: "Keep me")
        legacy.fill = "#FFFFFF"
        let changed = EaselShapeGeometry.reshaped(legacy, to: .star)
        #expect(changed.kind == .rectangle && changed.shape == .star && changed.frame == frame && changed.text == "Keep me"
               && changed.fill == "#FFFFFF" && changed.id == legacy.id, "Changing a shape keeps its frame, text and style")
    }

    @Test
    func changingToACircleRestoresTheCircleKind() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        var legacy = EaselItem(kind: .circle, frame: frame, text: "Keep me")
        legacy.fill = "#FFFFFF"
        let changed = EaselShapeGeometry.reshaped(legacy, to: .star)
        let back = EaselShapeGeometry.reshaped(changed, to: .ellipse)
        #expect(back.kind == .circle && back.shape == nil, "Changing to a circle makes a circle object again")
    }

    @Test
    func onlyShapesCanChangeShape() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        let text = EaselItem(kind: .text, frame: frame, text: "Hi")
        #expect(EaselShapeGeometry.reshaped(text, to: .star) == text, "Only shapes change shape")
    }

    @Test
    func newShapesExportTheirDrawnOutline() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        let star = EaselShapeStyle.newItem(.star, frame: frame, ink: "#252525", zIndex: 1)
        var dashed = star
        dashed.strokeDash = .dashed
        let svg = EaselVectorExport.element(dashed, art: .init())
        #expect(svg.hasPrefix("<path d=\"" + EaselShapeGeometry.outline(.star, in: frame).svgPathData + "\"")
               && svg.contains("stroke-dasharray") && !svg.contains("fill:none"), "HTML export draws new shapes from the same outline")
    }

    @Test
    func anUnfilledShapeExportsItsInnerLinesWithoutFill() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        var hollow = EaselShapeStyle.newItem(.cylinder, frame: frame, ink: "#252525", zIndex: 1)
        hollow.fillOpacity = 0
        let cylinder = EaselVectorExport.element(hollow, art: .init())
        #expect(cylinder.contains("fill:none") && cylinder.components(separatedBy: "<path").count == 3, "Unfilled shapes export without fill and keep their inner lines")
    }

    @Test
    func savedShapesKeepTheirOriginalSVG() {
        let frame = EaselRect(x: 10, y: 10, width: 200, height: 120)
        #expect(EaselVectorExport.element(EaselItem(kind: .rectangle, frame: frame), art: .init()).hasPrefix("<rect"), "Saved shapes export exactly as before")
    }

    @Test func thePickerListsEveryShapeExactlyOnce() {
        let listed = EaselShapeCatalog.families.flatMap(\.shapes)
        #expect(listed.count == EaselShape.allCases.count && Set(listed) == Set(EaselShape.allCases), "The picker lists every shape exactly once")
        for shape in EaselShape.allCases {
            #expect(EaselShapeCatalog.slot(of: shape).flatMap(EaselShapeCatalog.shape(at:)) == shape, "\(shape) has a picker slot")
        }
        typealias Slot = EaselShapeCatalog.Slot
        #expect(EaselShapeCatalog.move(from: nil, dx: 1, dy: 0) == Slot(family: 0, index: 0), "Keyboard picking starts at the first shape")
        #expect(EaselShapeCatalog.move(from: Slot(family: 0, index: 0), dx: -1, dy: 0) == Slot(family: 1, index: EaselShapeCatalog.families[1].shapes.count - 1), "Left from the first shape wraps to the last")
        let lastBasic = EaselShapeCatalog.families[0].shapes.count - 1
        #expect(EaselShapeCatalog.move(from: Slot(family: 0, index: lastBasic), dx: 1, dy: 0) == Slot(family: 1, index: 0), "Right from the last basic shape continues into the flowchart shapes")
        #expect(EaselShapeCatalog.move(from: Slot(family: 0, index: 1), dx: 0, dy: 1) == Slot(family: 0, index: 1 + EaselShapeCatalog.columns), "Down moves one row in the same column")
        let bottomBasic = Slot(family: 0, index: (lastBasic / EaselShapeCatalog.columns) * EaselShapeCatalog.columns + 2)
        #expect(EaselShapeCatalog.move(from: bottomBasic, dx: 0, dy: 1) == Slot(family: 1, index: 2), "Down from the last basic row lands in the flowchart's first row")
        #expect(EaselShapeCatalog.move(from: Slot(family: 1, index: 5), dx: 0, dy: -1).family == 0, "Up from the flowchart's first row returns to the basics")
        for family in EaselShapeCatalog.families.indices {
            for index in EaselShapeCatalog.families[family].shapes.indices {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let next = EaselShapeCatalog.move(from: Slot(family: family, index: index), dx: dx, dy: dy)
                    #expect(EaselShapeCatalog.shape(at: next) != nil, "Every keyboard move lands on a real shape")
                }
            }
        }
    }
}
