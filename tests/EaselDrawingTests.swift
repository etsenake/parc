import Foundation

@main
struct EaselDrawingTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    @MainActor static func main() {
        taps()
        straightening()
        tape()
        highlight()
        curves()
        print("EaselDrawingTests: \(assertions) assertions passed")
    }

    static func template(_ brush: EaselBrush) -> EaselItem {
        var item = EaselItem(kind: .freehand, frame: .init(x: 0, y: 0, width: 1, height: 1))
        item.brush = brush
        return item
    }

    @MainActor static func taps() {
        let dot = EaselPoint(x: 40, y: 30)
        let tap = EaselDrawing.strokeItem([dot, dot], like: template(.marker), straight: false, strict: false, scale: 1)
        expect(tap?.points.count == 2, "a tap keeps both points so it draws a dot")
        expect(tap?.frame.width == 1 && tap?.frame.height == 1, "a tap has a one point frame")
        let single = EaselDrawing.strokeItem([dot], like: template(.marker), straight: false, strict: false, scale: 1)
        expect(single?.points.count == 2, "a single sample still becomes two points")
        expect(EaselDrawing.strokeItem([dot, dot], like: template(.washi), straight: false, strict: false, scale: 1) == nil,
               "a tap does not lay down washi tape")
    }

    @MainActor static func straightening() {
        let start = EaselPoint(x: 10, y: 10), end = EaselPoint(x: 110, y: 14)
        let wobbly = [start, EaselPoint(x: 50, y: 30), EaselPoint(x: 80, y: 2), end]
        let line = EaselDrawing.strokeItem(wobbly, like: template(.marker), straight: true, strict: false, scale: 1)
        expect(line?.points.count == 2, "Shift keeps only the ends of a stroke")
        expect(line?.frame.height == 1, "a nearly level line snaps level")
        let loose = EaselDrawing.strokeItem([start, EaselPoint(x: 90, y: 60)], like: template(.marker), straight: true, strict: false, scale: 1)
        expect((loose?.frame.height ?? 0) > 1 && (loose?.frame.width ?? 0) > 1, "a clearly slanted line is left alone")
        let strict = EaselDrawing.strokeItem([start, EaselPoint(x: 90, y: 60)], like: template(.washi), straight: false, strict: true, scale: 1)
        expect(strict?.points.count == 2, "washi is always straight")
    }

    @MainActor static func tape() {
        var first = template(.washi)
        first.frame = .init(x: 0, y: 0, width: 120, height: 1)
        first.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 120, y: 0)]
        let id = UUID()
        first.id = id
        let one = EaselVectorExport.element(first, art: .init()), two = EaselVectorExport.element(first, art: .init())
        func ids(_ svg: String) -> Set<String> {
            var found = Set<String>()
            for part in svg.components(separatedBy: "id=\"").dropFirst() { found.insert(String(part.prefix { $0 != "\"" })) }
            return found
        }
        expect(ids(one).count == 2 && ids(two).count == 2, "tape defines a pattern and a clip")
        expect(ids(one).isDisjoint(with: ids(two)), "tape ids stay unique when the same item exports twice")
    }

    @MainActor static func highlight() {
        var marker = template(.highlighter)
        marker.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 60, y: 5)]
        marker.frame = .init(x: 5, y: 5, width: 60, height: 5)
        let svg = EaselVectorExport.element(marker, art: .init())
        expect(svg.contains("mix-blend-mode:var(--easel-highlight-blend,multiply)"), "the highlight path carries its own blend mode")
        expect(svg.contains("stroke-opacity:0.35"), "the highlight path carries its own opacity")
        let styles = EaselVectorExport.drawingStyles([marker])
        expect(styles.contains("--easel-highlight-blend:normal"), "dark mode drops the blend")
        expect(EaselVectorExport.drawingStyles([template(.marker)]).isEmpty, "plain markers add no styles")
    }

    @MainActor static func curves() {
        var item = template(.marker)
        item.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 20, y: 20), EaselPoint(x: 40, y: 0)]
        item.frame = .init(x: 0, y: 0, width: 40, height: 20)
        let path = EaselVectorExport.drawingPath(item) ?? ""
        expect(path.hasPrefix("M0 0") && path.contains("Q20 20"), "brushed strokes export as smooth curves")
        item.brush = nil
        expect(!(EaselVectorExport.drawingPath(item) ?? "").contains("Q"), "legacy pen strokes stay straight segments")
        item.points = []
        expect(EaselVectorExport.drawingPath(item) == nil, "an empty stroke has no path")
    }
}
