import Foundation

@main
struct EaselShapeGeometryTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func close(_ a: EaselRect?, _ b: EaselRect, _ tolerance: Double = 1e-6) -> Bool {
        guard let a else { return false }
        return close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance)
            && close(a.width, b.width, tolerance) && close(a.height, b.height, tolerance)
    }

    static func shapeItem(_ shape: EaselShape, _ frame: EaselRect) -> EaselItem {
        var item = EaselItem(kind: shape == .ellipse ? .circle : .rectangle, frame: frame)
        if shape != .ellipse { item.shape = shape }
        return item
    }

    static func main() {
        checkPaths()
        checkEveryShape()
        checkTransforms()
        checkHits()
        checkMarquee()
        checkEdges()
        print("EaselShapeGeometryTests passed")
    }

    static func checkPaths() {
        let oval = EaselPath.ellipse(in: EaselRect(x: 10, y: 20, width: 200, height: 100))
        expect(close(oval.bounds, EaselRect(x: 10, y: 20, width: 200, height: 100)), "An ellipse's bounds are its rectangle")
        expect(oval.contains(EaselPoint(x: 110, y: 70)) && !oval.contains(EaselPoint(x: 12, y: 22)),
               "An ellipse holds its centre but not its rectangle's corner")
        for index in 0..<36 {
            let angle = Double(index) * .pi / 18
            let point = EaselPoint(x: 110 + 100 * cos(angle), y: 70 + 50 * sin(angle))
            expect(oval.distance(to: point) < 0.3, "Ellipse curves stay on the true ellipse at \(index * 10) degrees")
        }
        let stadium = EaselPath.roundedRect(EaselRect(x: 0, y: 0, width: 40, height: 20), radius: 100)
        expect(close(stadium.bounds, EaselRect(x: 0, y: 0, width: 40, height: 20)), "Oversized corner radii clamp to the rectangle")
        expect(!stadium.contains(EaselPoint(x: 0.5, y: 0.5)) && stadium.contains(EaselPoint(x: 20, y: 10)),
               "A fully rounded rectangle trims its corners")

        var ring = EaselPath.ellipse(in: EaselRect(x: 0, y: 0, width: 100, height: 100))
        ring.append(.ellipse(in: EaselRect(x: 25, y: 25, width: 50, height: 50)))
        expect(ring.contains(EaselPoint(x: 50, y: 50), rule: .nonZero) && !ring.contains(EaselPoint(x: 50, y: 50), rule: .evenOdd),
               "Even-odd filling punches the inner ring while non-zero filling keeps it")
        expect(ring.contains(EaselPoint(x: 10, y: 50), rule: .evenOdd), "The band between rings is inside for even-odd filling")

        var open = EaselPath()
        open.move(to: EaselPoint(x: 0, y: 0)); open.line(to: EaselPoint(x: 100, y: 0)); open.line(to: EaselPoint(x: 100, y: 100))
        expect(close(open.distance(to: EaselPoint(x: 50, y: 50)), 50), "Open paths measure distance without a closing edge")
        open.close()
        expect(close(open.distance(to: EaselPoint(x: 0, y: 50)), 35.35533905932738, 1e-6), "Closed paths measure their closing edge")

        var curve = EaselPath()
        curve.move(to: EaselPoint(x: 0, y: 0))
        curve.quad(to: EaselPoint(x: 100, y: 0), control: EaselPoint(x: 50, y: 100))
        expect(close(curve.bounds, EaselRect(x: 0, y: 0, width: 100, height: 50)), "Quadratic bounds include the curve's peak, not its control point")
        expect(curve.svgPathData == "M0 0 Q50 100 100 0", "Quadratic SVG data is compact: \(curve.svgPathData)")

        expect(EaselPath.svgNumber(1.5) == "1.5" && EaselPath.svgNumber(2) == "2" && EaselPath.svgNumber(-0.0001) == "0"
               && EaselPath.svgNumber(1.0 / 3) == "0.333" && EaselPath.svgNumber(-12.25) == "-12.25" && EaselPath.svgNumber(.nan) == "0",
               "SVG numbers are short, finite and never negative zero")
        expect(EaselPath().bounds == nil && EaselPath().subpaths().isEmpty && !EaselPath().contains(EaselPoint(x: 0, y: 0)),
               "An empty path has no bounds, subpaths or inside")

        var arc = EaselPath()
        arc.arc(center: EaselPoint(x: 0, y: 0), radiusX: 50, radiusY: 50, from: 0, to: 2 * .pi)
        for subpath in arc.subpaths(tolerance: 0.05) {
            for point in subpath.points {
                expect(abs((point.x * point.x + point.y * point.y).squareRoot() - 50) < 0.05, "Arcs follow their circle")
            }
        }
    }

    static func checkEveryShape() {
        let frames = [EaselRect(x: 0, y: 0, width: 200, height: 120), EaselRect(x: 37, y: -12, width: 120, height: 200),
                      EaselRect(x: 400, y: 300, width: 160, height: 160), EaselRect(x: 5, y: 5, width: 40, height: 300),
                      EaselRect(x: -20, y: 80, width: 1000, height: 30), EaselRect(x: 0, y: 0, width: 12, height: 9)]
        var names = Set<String>()
        for shape in EaselShape.allCases {
            let name = EaselShapeGeometry.displayName(shape)
            expect(!name.isEmpty && names.insert(name).inserted, "\(shape) has its own display name")
            let size = EaselShapeGeometry.defaultSize(shape)
            expect(size.width >= 60 && size.height >= 60 && size.width <= 240 && size.height <= 240,
                   "\(shape) arrives at a friendly default size")
            for frame in frames {
                let outline = EaselShapeGeometry.outline(shape, in: frame)
                expect(close(outline.bounds, frame, 1e-6), "\(shape) fills its whole frame \(frame): \(String(describing: outline.bounds))")
                let center = EaselShapeGeometry.center(of: frame)
                expect(outline.contains(center), "\(shape) holds its centre in \(frame)")
                expect(!outline.contains(EaselPoint(x: frame.x - 10, y: frame.y - 10))
                       && !outline.contains(EaselPoint(x: frame.x + frame.width + 10, y: frame.y + frame.height / 2)),
                       "\(shape) stays inside its frame \(frame)")
                let text = EaselShapeGeometry.textRect(shape, in: frame)
                expect(text.width > 0 && text.height > 0, "\(shape) leaves room for text in \(frame)")
                for column in 0...4 {
                    for row in 0...4 {
                        let point = EaselPoint(x: text.x + text.width * Double(column) / 4, y: text.y + text.height * Double(row) / 4)
                        expect(outline.contains(point), "\(shape)'s text area stays inside the outline at \(point) in \(frame)")
                    }
                }
                let data = outline.svgPathData
                expect(data.hasPrefix("M") && data.hasSuffix("Z") && !data.contains("nan") && !data.contains("inf"),
                       "\(shape) writes closed, finite SVG data")
                let commands = data.filter { "MLQCZ".contains($0) }.count
                expect(commands == outline.elements.count, "\(shape)'s SVG data has one command per path element")
                let details = EaselShapeGeometry.details(shape, in: frame)
                if let bounds = details.bounds {
                    expect(bounds.x >= frame.x - 1e-6 && bounds.y >= frame.y - 1e-6
                           && bounds.x + bounds.width <= frame.x + frame.width + 1e-6
                           && bounds.y + bounds.height <= frame.y + frame.height + 1e-6,
                           "\(shape)'s inner lines stay inside its frame")
                }
            }
        }
        let wide = EaselRect(x: 0, y: 0, width: 200, height: 120)
        expect(EaselShapeGeometry.textRect(.ellipse, in: wide).width < EaselShapeGeometry.textRect(.rectangle, in: wide).width
               && EaselShapeGeometry.textRect(.diamond, in: wide).width < EaselShapeGeometry.textRect(.ellipse, in: wide).width
               && EaselShapeGeometry.textRect(.star, in: wide).height < EaselShapeGeometry.textRect(.diamond, in: wide).height,
               "Rounder and pointier shapes keep their text further in")
        expect(EaselShapeGeometry.textRect(.triangle, in: wide).y > 60 && EaselShapeGeometry.textRect(.triangleDown, in: wide).y < 6,
               "Triangles put their text in the wide half")
        for shape in [EaselShape.cylinder, .cylinderHorizontal, .file, .documents, .predefinedProcess, .internalStorage, .or, .summingJunction] {
            expect(!EaselShapeGeometry.details(shape, in: wide).isEmpty, "\(shape) draws its inner lines")
        }
        expect(EaselShapeGeometry.details(.rectangle, in: wide).isEmpty, "Plain shapes have no inner lines")
        expect(EaselShapeGeometry.cornerRadius(.rectangle, in: wide) == 5, "Rectangles keep the original five-point corners")
        expect(EaselShapeGeometry.cornerRadius(.roundedRectangle, in: wide) == 24
               && EaselShapeGeometry.cornerRadius(.roundedRectangle, in: EaselRect(x: 0, y: 0, width: 600, height: 400)) == 36
               && EaselShapeGeometry.cornerRadius(.roundedRectangle, in: EaselRect(x: 0, y: 0, width: 10, height: 10)) == 5,
               "Rounded rectangles scale their corners within sensible limits")
    }

    static func checkTransforms() {
        let frame = EaselRect(x: 0, y: 0, width: 200, height: 100)
        expect(close(EaselShapeGeometry.rotatedBounds(frame, degrees: 90), EaselRect(x: 50, y: -50, width: 100, height: 200), 1e-9),
               "A quarter turn swaps a frame's width and height around its centre")
        expect(EaselShapeGeometry.rotatedBounds(frame, degrees: 360) == frame, "A full turn is no turn")
        let turned = EaselTransform.rotation(degrees: 90, around: EaselPoint(x: 0, y: 0)).apply(EaselPoint(x: 10, y: 0))
        expect(close(turned.x, 0, 1e-9) && close(turned.y, 10, 1e-9), "Positive rotation turns clockwise on the flipped canvas")

        var item = shapeItem(.arrowRight, EaselRect(x: 30, y: 40, width: 200, height: 100))
        for degrees in [0.0, 15, 90, 137, -45, 359] {
            for flips in [(false, false), (true, false), (false, true), (true, true)] {
                item.rotation = degrees; item.flipHorizontal = flips.0; item.flipVertical = flips.1
                let transform = EaselShapeGeometry.transform(for: item)
                for point in [EaselPoint(x: 0, y: 0), EaselPoint(x: 31, y: -7), EaselPoint(x: 230, y: 140)] {
                    let back = EaselShapeGeometry.localPoint(transform.apply(point), in: item)
                    expect(close(back.x, point.x, 1e-9) && close(back.y, point.y, 1e-9),
                           "Canvas and local points round-trip at \(degrees) degrees with flips \(flips)")
                }
            }
        }
        item.rotation = 90; item.flipHorizontal = nil; item.flipVertical = nil
        expect(close(EaselShapeGeometry.outline(for: item)?.bounds, EaselRect(x: 80, y: -10, width: 100, height: 200), 1e-6),
               "A rotated shape's outline turns with it")
        let tip = EaselShapeGeometry.edgePoint(of: item, toward: EaselPoint(x: 130, y: 1000))
        expect(tip.map { close($0.x, 130, 1e-6) && close($0.y, 190, 1e-6) } == true,
               "A right arrow turned a quarter clockwise points down")

        var triangle = shapeItem(.triangle, EaselRect(x: 0, y: 0, width: 200, height: 120))
        expect(EaselShapeGeometry.outline(for: triangle)?.contains(EaselPoint(x: 5, y: 5)) == false, "An upright triangle leaves its top corners empty")
        triangle.flipVertical = true
        expect(EaselShapeGeometry.outline(for: triangle)?.contains(EaselPoint(x: 5, y: 5)) == true, "A flipped triangle fills its top corners")
        expect((EaselShapeGeometry.textRect(for: triangle)?.y ?? 100) < 10, "A flipped triangle moves its text to the wide top half")
        var bubble = shapeItem(.speechBubble, EaselRect(x: 0, y: 0, width: 200, height: 150))
        expect(EaselShapeGeometry.outline(for: bubble)?.contains(EaselPoint(x: 36, y: 140)) == true, "Speech bubble tails start bottom left")
        bubble.flipHorizontal = true
        expect(EaselShapeGeometry.outline(for: bubble)?.contains(EaselPoint(x: 164, y: 140)) == true
               && EaselShapeGeometry.outline(for: bubble)?.contains(EaselPoint(x: 36, y: 140)) == false,
               "A mirrored speech bubble moves its tail to the right")
        expect(close(EaselShapeGeometry.textRect(for: bubble), EaselShapeGeometry.textRect(.speechBubble, in: bubble.frame)),
               "Mirroring a symmetric text area leaves it in place, so text stays readable")
        let rotated = EaselTransform.rotation(degrees: 30, around: EaselPoint(x: 5, y: 5))
        let mirror = EaselTransform.mirror(horizontally: true, vertically: false, around: EaselPoint(x: 5, y: 5))
        let both = mirror.concatenating(rotated), sample = EaselPoint(x: 17, y: -3)
        let stepwise = rotated.apply(mirror.apply(sample)), combined = both.apply(sample)
        expect(close(stepwise.x, combined.x, 1e-9) && close(stepwise.y, combined.y, 1e-9), "Concatenated transforms apply in order")
    }

    static func checkHits() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 120)
        var plain = shapeItem(.rectangle, frame)
        plain.fillOpacity = 0
        expect(!EaselShapeGeometry.hits(EaselPoint(x: 200, y: 160), item: plain, selected: false, scale: 1),
               "An unfilled shape lets clicks through its middle")
        expect(EaselShapeGeometry.hits(EaselPoint(x: 101, y: 160), item: plain, selected: false, scale: 1)
               && EaselShapeGeometry.hits(EaselPoint(x: 90, y: 160), item: plain, selected: false, scale: 1),
               "An unfilled shape is grabbed on and just outside its outline")
        expect(!EaselShapeGeometry.hits(EaselPoint(x: 80, y: 160), item: plain, selected: false, scale: 1),
               "Clicks well clear of an unfilled outline miss")
        expect(!EaselShapeGeometry.hits(EaselPoint(x: 90, y: 160), item: plain, selected: false, scale: 4),
               "Zooming in tightens the outline band to the same screen distance")
        expect(EaselShapeGeometry.hits(EaselPoint(x: 200, y: 160), item: plain, selected: true, scale: 1),
               "A selected unfilled shape can be dragged from its middle")
        plain.text = "Label"
        expect(EaselShapeGeometry.hits(EaselPoint(x: 200, y: 160), item: plain, selected: false, scale: 1),
               "An unfilled shape with text is solid")
        plain.text = ""; plain.strokeWidth = 50
        expect(EaselShapeGeometry.hits(EaselPoint(x: 78, y: 160), item: plain, selected: false, scale: 1),
               "Thick outlines widen their hit band")

        let star = shapeItem(.star, EaselRect(x: 0, y: 0, width: 200, height: 200))
        expect(EaselShapeGeometry.hits(EaselPoint(x: 100, y: 110), item: star, selected: false, scale: 1), "A filled star is hit at its heart")
        expect(!EaselShapeGeometry.hits(EaselPoint(x: 12, y: 12), item: star, selected: false, scale: 1), "A star's empty corners miss")
        let tiny = shapeItem(.diamond, EaselRect(x: 0, y: 0, width: 12, height: 12))
        expect(EaselShapeGeometry.hits(EaselPoint(x: -8, y: -8), item: tiny, selected: false, scale: 1),
               "Tiny shapes keep the 30-point minimum target")
        var thin = shapeItem(.rectangle, EaselRect(x: 0, y: 0, width: 200, height: 20))
        thin.rotation = 90
        expect(EaselShapeGeometry.hits(EaselPoint(x: 100, y: -60), item: thin, selected: false, scale: 1)
               && !EaselShapeGeometry.hits(EaselPoint(x: 180, y: 10), item: thin, selected: false, scale: 1),
               "Rotated shapes are hit where they are drawn")
        expect(EaselShapeGeometry.usesOriginalLook(EaselItem(kind: .rectangle, frame: frame))
               && EaselShapeGeometry.usesOriginalLook(EaselItem(kind: .circle, frame: frame))
               && !EaselShapeGeometry.usesOriginalLook(shapeItem(.rectangle, frame)) && !EaselShapeGeometry.usesOriginalLook(thin),
               "Only untouched saved shapes keep the original look and hit rules")
        expect(EaselShapeGeometry.strokeWidth(of: EaselItem(kind: .rectangle, frame: frame)) == 2.5
               && EaselShapeGeometry.hasVisibleFill(EaselItem(kind: .rectangle, frame: frame)),
               "Saved shapes keep their 2.5-point outline and wash")
    }

    static func checkMarquee() {
        var hollow = shapeItem(.ellipse, EaselRect(x: 0, y: 0, width: 400, height: 400))
        hollow.fillOpacity = 0
        let inside = EaselRect(x: 150, y: 150, width: 100, height: 100)
        let crossing = EaselRect(x: -20, y: 180, width: 60, height: 40)
        expect(!EaselShapeGeometry.intersects(inside, item: hollow, selected: false),
               "A marquee inside an unfilled shape picks what's inside, not the shape")
        expect(EaselShapeGeometry.intersects(crossing, item: hollow, selected: false), "A marquee crossing an outline picks the shape")
        expect(EaselShapeGeometry.intersects(inside, item: hollow, selected: true), "Already selected shapes stay in a marquee over them")
        let solid = shapeItem(.ellipse, EaselRect(x: 0, y: 0, width: 400, height: 400))
        expect(EaselShapeGeometry.intersects(inside, item: solid, selected: false), "A marquee inside a filled shape picks it")
        expect(!EaselShapeGeometry.intersects(EaselRect(x: 0, y: 0, width: 20, height: 20), item: solid, selected: false),
               "A marquee in a circle's empty corner misses it")
        var turned = shapeItem(.rectangle, EaselRect(x: 0, y: 0, width: 200, height: 20))
        turned.rotation = 90
        expect(EaselShapeGeometry.intersects(EaselRect(x: 95, y: -80, width: 10, height: 10), item: turned, selected: false)
               && !EaselShapeGeometry.intersects(EaselRect(x: 160, y: 0, width: 20, height: 20), item: turned, selected: false),
               "Marquees follow rotated outlines")
    }

    static func checkEdges() {
        let box = shapeItem(.rectangle, EaselRect(x: 0, y: 0, width: 200, height: 100))
        let right = EaselShapeGeometry.edgePoint(of: box, toward: EaselPoint(x: 1000, y: 50))
        expect(right.map { close($0.x, 200, 1e-6) && close($0.y, 50, 1e-6) } == true, "Edge points land on the outline")
        let circle = shapeItem(.ellipse, EaselRect(x: 0, y: 0, width: 200, height: 100))
        if let point = EaselShapeGeometry.edgePoint(of: circle, toward: EaselPoint(x: 300, y: 150)) {
            let value = pow((point.x - 100) / 100, 2) + pow((point.y - 50) / 50, 2)
            expect(abs(value - 1) < 0.01, "Edge points land on curved outlines")
        } else { expect(false, "Ellipses have edge points") }
        var turned = box
        turned.rotation = 90
        let top = EaselShapeGeometry.anchorPoint(of: turned, side: .top)
        expect(top.map { close($0.x, 150, 1e-6) && close($0.y, 50, 1e-6) } == true,
               "A rotated shape's top anchor turns with it: \(String(describing: top))")
        expect(EaselShapeGeometry.edgePoint(of: box, toward: EaselPoint(x: 100, y: 50)) == nil, "The centre has no direction")
        expect(EaselShapeGeometry.edgePoint(of: EaselItem(kind: .text, frame: box.frame), toward: EaselPoint(x: 0, y: 0)) == nil,
               "Only shapes have outlines")
    }
}
