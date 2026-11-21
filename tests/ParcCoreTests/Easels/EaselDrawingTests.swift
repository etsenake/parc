import Foundation
import Testing
@testable import ParcCore

struct EaselDrawingTests {
    static func template(_ brush: EaselBrush) -> EaselItem {
        var item = EaselItem(kind: .freehand, frame: .init(x: 0, y: 0, width: 1, height: 1))
        item.brush = brush
        return item
    }

    static func ids(_ svg: String) -> Set<String> {
        var found = Set<String>()
        for part in svg.components(separatedBy: "id=\"").dropFirst() { found.insert(String(part.prefix { $0 != "\"" })) }
        return found
    }

    static func highlighter() -> EaselItem {
        var marker = template(.highlighter)
        marker.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 60, y: 5)]
        marker.frame = .init(x: 5, y: 5, width: 60, height: 5)
        return marker
    }

    static let start = EaselPoint(x: 10, y: 10)
    static let dot = EaselPoint(x: 40, y: 30)

    @Test func aTapKeepsBothPointsSoItDrawsADot() {
        let tap = EaselDrawing.strokeItem([Self.dot, Self.dot], like: Self.template(.marker), straight: false, strict: false, scale: 1)
        #expect(tap?.points.count == 2)
    }

    @Test func aTapHasAOnePointFrame() {
        let tap = EaselDrawing.strokeItem([Self.dot, Self.dot], like: Self.template(.marker), straight: false, strict: false, scale: 1)
        #expect(tap?.frame.width == 1 && tap?.frame.height == 1)
    }

    @Test func aSingleSampleStillBecomesTwoPoints() {
        let single = EaselDrawing.strokeItem([Self.dot], like: Self.template(.marker), straight: false, strict: false, scale: 1)
        #expect(single?.points.count == 2)
    }

    @Test func aTapDoesNotLayDownWashiTape() {
        #expect(EaselDrawing.strokeItem([Self.dot, Self.dot], like: Self.template(.washi), straight: false, strict: false, scale: 1) == nil)
    }

    @Test func shiftKeepsOnlyTheEndsOfAStroke() {
        let wobbly = [Self.start, EaselPoint(x: 50, y: 30), EaselPoint(x: 80, y: 2), EaselPoint(x: 110, y: 14)]
        let line = EaselDrawing.strokeItem(wobbly, like: Self.template(.marker), straight: true, strict: false, scale: 1)
        #expect(line?.points.count == 2)
    }

    @Test func aNearlyLevelLineSnapsLevel() {
        let wobbly = [Self.start, EaselPoint(x: 50, y: 30), EaselPoint(x: 80, y: 2), EaselPoint(x: 110, y: 14)]
        let line = EaselDrawing.strokeItem(wobbly, like: Self.template(.marker), straight: true, strict: false, scale: 1)
        #expect(line?.frame.height == 1)
    }

    @Test func aClearlySlantedLineIsLeftAlone() {
        let loose = EaselDrawing.strokeItem([Self.start, EaselPoint(x: 90, y: 60)], like: Self.template(.marker), straight: true, strict: false, scale: 1)
        #expect((loose?.frame.height ?? 0) > 1 && (loose?.frame.width ?? 0) > 1)
    }

    @Test func washiIsAlwaysStraight() {
        let strict = EaselDrawing.strokeItem([Self.start, EaselPoint(x: 90, y: 60)], like: Self.template(.washi), straight: false, strict: true, scale: 1)
        #expect(strict?.points.count == 2)
    }

    @Test func tapeDefinesAPatternAndAClip() {
        var first = Self.template(.washi)
        first.frame = .init(x: 0, y: 0, width: 120, height: 1)
        first.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 120, y: 0)]
        first.id = UUID()
        #expect(Self.ids(EaselVectorExport.element(first, art: .init())).count == 2)
    }

    @Test func tapeIdsStayUniqueWhenTheSameItemExportsTwice() {
        var first = Self.template(.washi)
        first.frame = .init(x: 0, y: 0, width: 120, height: 1)
        first.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 120, y: 0)]
        first.id = UUID()
        let one = EaselVectorExport.element(first, art: .init()), two = EaselVectorExport.element(first, art: .init())
        #expect(Self.ids(two).count == 2)
        #expect(Self.ids(one).isDisjoint(with: Self.ids(two)))
    }

    @Test func theHighlightPathCarriesItsOwnBlendModeAndOpacity() {
        let svg = EaselVectorExport.element(Self.highlighter(), art: .init())
        #expect(svg.contains("mix-blend-mode:var(--easel-highlight-blend,multiply)"))
        #expect(svg.contains("stroke-opacity:0.35"))
    }

    @Test func darkModeDropsTheHighlightBlend() {
        #expect(EaselVectorExport.drawingStyles([Self.highlighter()]).contains("--easel-highlight-blend:normal"))
    }

    @Test func plainMarkersAddNoStyles() {
        #expect(EaselVectorExport.drawingStyles([Self.template(.marker)]).isEmpty)
    }

    @Test func brushedStrokesExportAsSmoothCurves() {
        var item = Self.template(.marker)
        item.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 20, y: 20), EaselPoint(x: 40, y: 0)]
        item.frame = .init(x: 0, y: 0, width: 40, height: 20)
        let path = EaselVectorExport.drawingPath(item) ?? ""
        #expect(path.hasPrefix("M0 0") && path.contains("Q20 20"))
    }

    @Test func legacyPenStrokesStayStraightSegments() {
        var item = Self.template(.marker)
        item.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 20, y: 20), EaselPoint(x: 40, y: 0)]
        item.frame = .init(x: 0, y: 0, width: 40, height: 20)
        item.brush = nil
        #expect(!(EaselVectorExport.drawingPath(item) ?? "").contains("Q"))
    }

    @Test func anEmptyStrokeHasNoPath() {
        var item = Self.template(.marker)
        item.points = []
        #expect(EaselVectorExport.drawingPath(item) == nil)
    }

    @Test(arguments: [false, true])
    func theEraserOnlyTakesAnUnlockedStrokeItTouches(_ locked: Bool) {
        var touched = Self.template(.marker)
        touched.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 60, y: 0)]
        touched.frame = .init(x: 0, y: 0, width: 60, height: 1)
        touched.locked = locked
        var distant = touched
        distant.id = UUID()
        distant.frame.y = 500
        distant.locked = false
        let hits = EaselDrawing.erased([touched, distant], from: EaselPoint(x: 10, y: 0),
                                       to: EaselPoint(x: 20, y: 0), scale: 1)
        #expect(hits == (locked ? [] : [touched.id]))
    }

    @Test func strokesAlreadyErasedAreSkipped() {
        var item = Self.template(.marker)
        item.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 60, y: 0)]
        item.frame = .init(x: 0, y: 0, width: 60, height: 1)
        let skipped = EaselDrawing.erased([item], from: EaselPoint(x: 10, y: 0), to: EaselPoint(x: 20, y: 0), scale: 1, skipping: [item.id])
        #expect(skipped.isEmpty)
    }

    @Test func oneHelperRecognisesHighlighters() {
        #expect(EaselPaintRules.isHighlighter(Self.template(.highlighter)) && !EaselPaintRules.isHighlighter(Self.template(.marker)))
    }

    @Test func strokesWithNoBrushAreNotHighlighters() {
        var legacy = Self.template(.marker)
        legacy.brush = nil
        #expect(!EaselPaintRules.isHighlighter(legacy))
    }

    @Test func highlightersAddTheBlendStyle() {
        #expect(EaselVectorExport.drawingStyles([Self.template(.highlighter)]).contains("easel-highlight"))
    }
}
