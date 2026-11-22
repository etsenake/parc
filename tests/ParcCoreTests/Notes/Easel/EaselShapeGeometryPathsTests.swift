import Foundation
import Testing
@testable import ParcCore

struct EaselShapeGeometryPathsTests {
    @Test func anEllipseSBoundsAreItsRectangle() {
        let oval = EaselPath.ellipse(in: EaselRect(x: 10, y: 20, width: 200, height: 100))
        #expect(EaselShapeGeometryTestsSupport.close(oval.bounds, EaselRect(x: 10, y: 20, width: 200, height: 100)), "An ellipse's bounds are its rectangle")
        #expect(oval.contains(EaselPoint(x: 110, y: 70)) && !oval.contains(EaselPoint(x: 12, y: 22)), "An ellipse holds its centre but not its rectangle's corner")
        for index in 0..<36 {
            let angle = Double(index) * .pi / 18
            let point = EaselPoint(x: 110 + 100 * cos(angle), y: 70 + 50 * sin(angle))
            #expect(oval.distance(to: point) < 0.3, "Ellipse curves stay on the true ellipse at \(index * 10) degrees")
        }
        let stadium = EaselPath.roundedRect(EaselRect(x: 0, y: 0, width: 40, height: 20), radius: 100)
        #expect(EaselShapeGeometryTestsSupport.close(stadium.bounds, EaselRect(x: 0, y: 0, width: 40, height: 20)), "Oversized corner radii clamp to the rectangle")
        #expect(!stadium.contains(EaselPoint(x: 0.5, y: 0.5)) && stadium.contains(EaselPoint(x: 20, y: 10)), "A fully rounded rectangle trims its corners")
    }

    @Test func evenOddFillingPunchesTheInnerRingWhileNon() {
        var ring = EaselPath.ellipse(in: EaselRect(x: 0, y: 0, width: 100, height: 100))
        ring.append(.ellipse(in: EaselRect(x: 25, y: 25, width: 50, height: 50)))
        #expect(ring.contains(EaselPoint(x: 50, y: 50), rule: .nonZero) && !ring.contains(EaselPoint(x: 50, y: 50), rule: .evenOdd), "Even-odd filling punches the inner ring while non-zero filling keeps it")
        #expect(ring.contains(EaselPoint(x: 10, y: 50), rule: .evenOdd), "The band between rings is inside for even-odd filling")
    }

    @Test func openPathsMeasureDistanceWithoutAClosingEdge() {
        var open = EaselPath()
        open.move(to: EaselPoint(x: 0, y: 0)); open.line(to: EaselPoint(x: 100, y: 0)); open.line(to: EaselPoint(x: 100, y: 100))
        #expect(EaselShapeGeometryTestsSupport.close(open.distance(to: EaselPoint(x: 50, y: 50)), 50), "Open paths measure distance without a closing edge")
        open.close()
        #expect(EaselShapeGeometryTestsSupport.close(open.distance(to: EaselPoint(x: 0, y: 50)), 35.35533905932738, 1e-6), "Closed paths measure their closing edge")
    }

    @Test func quadraticBoundsIncludeTheCurveSPeakNotIts() {
        var curve = EaselPath()
        curve.move(to: EaselPoint(x: 0, y: 0))
        curve.quad(to: EaselPoint(x: 100, y: 0), control: EaselPoint(x: 50, y: 100))
        #expect(EaselShapeGeometryTestsSupport.close(curve.bounds, EaselRect(x: 0, y: 0, width: 100, height: 50)), "Quadratic bounds include the curve's peak, not its control point")
        #expect(curve.svgPathData == "M0 0 Q50 100 100 0", "Quadratic SVG data is compact: \(curve.svgPathData)")
    }

    @Test func svgNumbersAreShortFiniteAndNeverNegativeZero() {
        #expect(EaselPath.svgNumber(1.5) == "1.5" && EaselPath.svgNumber(2) == "2" && EaselPath.svgNumber(-0.0001) == "0"
               && EaselPath.svgNumber(1.0 / 3) == "0.333" && EaselPath.svgNumber(-12.25) == "-12.25" && EaselPath.svgNumber(.nan) == "0", "SVG numbers are short, finite and never negative zero")
        #expect(EaselPath().bounds == nil && EaselPath().subpaths().isEmpty && !EaselPath().contains(EaselPoint(x: 0, y: 0)), "An empty path has no bounds, subpaths or inside")
    }

    @Test func arcsFollowTheirCircle() {
        var arc = EaselPath()
        arc.arc(center: EaselPoint(x: 0, y: 0), radiusX: 50, radiusY: 50, from: 0, to: 2 * .pi)
        for subpath in arc.subpaths(tolerance: 0.05) {
            for point in subpath.points {
                #expect(abs((point.x * point.x + point.y * point.y).squareRoot() - 50) < 0.05, "Arcs follow their circle")
            }
        }
    }

    private static let frames = [EaselRect(x: 0, y: 0, width: 200, height: 120), EaselRect(x: 37, y: -12, width: 120, height: 200),
                      EaselRect(x: 400, y: 300, width: 160, height: 160), EaselRect(x: 5, y: 5, width: 40, height: 300),
                      EaselRect(x: -20, y: 80, width: 1000, height: 30), EaselRect(x: 0, y: 0, width: 12, height: 9),
                      EaselRect(x: 3, y: 4, width: 1, height: 1), EaselRect(x: 0, y: 0, width: 2, height: 2),
                      EaselRect(x: 10, y: 10, width: 400, height: 20), EaselRect(x: 10, y: 10, width: 20, height: 400)]

    @Test
    func shapeDisplayNamesAreNonemptyAndUnique() {
        let names = EaselShape.allCases.map(EaselShapeGeometry.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test(arguments: EaselShape.allCases)
    func eachShapeHasAUsableDefaultSize(_ shape: EaselShape) {
        let size = EaselShapeGeometry.defaultSize(shape)
        #expect(size.width >= 60 && size.height >= 60 && size.width <= 240 && size.height <= 240, "\(shape) arrives at a friendly default size")
    }

    @Test(arguments: EaselShape.allCases, EaselShapeGeometryPathsTests.frames)
    private func shapeOutlinesFillTheirFrameAndContainTheCentre(_ shape: EaselShape, _ frame: EaselRect) {
        let outline = EaselShapeGeometry.outline(shape, in: frame)
        #expect(EaselShapeGeometryTestsSupport.close(outline.bounds, frame, 1e-6), "\(shape) fills its whole frame \(frame): \(String(describing: outline.bounds))")
        let center = EaselShapeGeometry.center(of: frame)
        #expect(outline.contains(center), "\(shape) holds its centre in \(frame)")
        #expect(!outline.contains(EaselPoint(x: frame.x - 10, y: frame.y - 10))
               && !outline.contains(EaselPoint(x: frame.x + frame.width + 10, y: frame.y + frame.height / 2)), "\(shape) stays inside its frame \(frame)")
    }

    @Test(arguments: EaselShape.allCases, EaselShapeGeometryPathsTests.frames)
    private func shapeTextStaysInsideTheOutline(_ shape: EaselShape, _ frame: EaselRect) {
        let outline = EaselShapeGeometry.outline(shape, in: frame)
        let text = EaselShapeGeometry.textRect(shape, in: frame)
        #expect(text.width > 0 && text.height > 0, "\(shape) leaves room for text in \(frame)")
        #expect(text.x >= frame.x && text.y >= frame.y && text.x + text.width <= frame.x + frame.width
               && text.y + text.height <= frame.y + frame.height, "\(shape)'s text area stays in its frame \(frame)")
        for column in 0...4 {
            for row in 0...4 {
                let point = EaselPoint(x: text.x + text.width * Double(column) / 4, y: text.y + text.height * Double(row) / 4)
                #expect(outline.contains(point, tolerance: min(0.2, min(frame.width, frame.height) / 400)), "\(shape)'s text area stays inside the outline at \(point) in \(frame)")
            }
        }
    }

    @Test(arguments: EaselShape.allCases, EaselShapeGeometryPathsTests.frames)
    private func shapeSVGEncodesEachElementInAClosedFinitePath(_ shape: EaselShape, _ frame: EaselRect) {
        let outline = EaselShapeGeometry.outline(shape, in: frame)
        let data = outline.svgPathData
        #expect(data.hasPrefix("M") && data.hasSuffix("Z") && !data.contains("nan") && !data.contains("inf"), "\(shape) writes closed, finite SVG data")
        let commands = data.filter { "MLQCZ".contains($0) }.count
        #expect(commands == outline.elements.count, "\(shape)'s SVG data has one command per path element")
    }

    @Test(arguments: EaselShape.allCases, EaselShapeGeometryPathsTests.frames)
    private func shapeDetailsStayInsideTheirFrame(_ shape: EaselShape, _ frame: EaselRect) {
        let details = EaselShapeGeometry.details(shape, in: frame)
        if let bounds = details.bounds {
            #expect(bounds.x >= frame.x - 1e-6 && bounds.y >= frame.y - 1e-6
                   && bounds.x + bounds.width <= frame.x + frame.width + 1e-6
                   && bounds.y + bounds.height <= frame.y + frame.height + 1e-6, "\(shape)'s inner lines stay inside its frame")
        }
    }

    @Test
    func rounderAndPointierShapesInsetTextFurther() {
        let wide = EaselRect(x: 0, y: 0, width: 200, height: 120)
        #expect(EaselShapeGeometry.textRect(.ellipse, in: wide).width < EaselShapeGeometry.textRect(.rectangle, in: wide).width
               && EaselShapeGeometry.textRect(.diamond, in: wide).width < EaselShapeGeometry.textRect(.ellipse, in: wide).width
               && EaselShapeGeometry.textRect(.star, in: wide).height < EaselShapeGeometry.textRect(.diamond, in: wide).height, "Rounder and pointier shapes keep their text further in")
    }

    @Test
    func trianglesPutTextInTheirWideHalf() {
        let wide = EaselRect(x: 0, y: 0, width: 200, height: 120)
        #expect(EaselShapeGeometry.textRect(.triangle, in: wide).y > 60 && EaselShapeGeometry.textRect(.triangleDown, in: wide).y < 6, "Triangles put their text in the wide half")
    }

    @Test
    func shapesWithInnerLinesDrawThem() {
        let wide = EaselRect(x: 0, y: 0, width: 200, height: 120)
        for shape in [EaselShape.cylinder, .cylinderHorizontal, .file, .documents, .predefinedProcess, .internalStorage, .or, .summingJunction] {
            #expect(!EaselShapeGeometry.details(shape, in: wide).isEmpty, "\(shape) draws its inner lines")
        }
        #expect(EaselShapeGeometry.details(.rectangle, in: wide).isEmpty, "Plain shapes have no inner lines")
    }

    @Test
    func rectangleCornersKeepTheirRadius() {
        let wide = EaselRect(x: 0, y: 0, width: 200, height: 120)
        #expect(EaselShapeGeometry.cornerRadius(.rectangle, in: wide) == 5, "Rectangles keep the original five-point corners")
    }

    @Test
    func shortSpeechBubbleSidesStillRunForwards() {
        for height in [4.0, 9, 12, 15, 16, 30] {
            let frame = EaselRect(x: 0, y: 0, width: 12, height: height)
            let radius = EaselShapeGeometry.cornerRadius(.speechBubble, in: frame)
            #expect(height * 0.78 - radius >= radius - 1e-9, "Short speech bubbles keep their sides running forwards at height \(height)")
            var previous = -Double.infinity
            for subpath in EaselShapeGeometry.outline(.speechBubble, in: frame).subpaths(tolerance: 0.01) {
                for point in subpath.points where point.x == 12 {
                    #expect(point.y >= previous - 1e-9, "The bubble's right side only runs downwards at height \(height)")
                    previous = point.y
                }
            }
        }
    }

    @Test
    func hugeSVGCoordinatesCannotOverflow() {
        #expect(EaselPath.svgNumber(1e306) == "0" && EaselPath.svgNumber(-1e307) == "0", "Huge SVG numbers never overflow into inf")
    }

    @Test
    func roundedRectangleRadiiScaleWithinLimits() {
        let wide = EaselRect(x: 0, y: 0, width: 200, height: 120)
        #expect(EaselShapeGeometry.cornerRadius(.roundedRectangle, in: wide) == 24
               && EaselShapeGeometry.cornerRadius(.roundedRectangle, in: EaselRect(x: 0, y: 0, width: 600, height: 400)) == 36
               && EaselShapeGeometry.cornerRadius(.roundedRectangle, in: EaselRect(x: 0, y: 0, width: 10, height: 10)) == 5, "Rounded rectangles scale their corners within sensible limits")
    }
}
