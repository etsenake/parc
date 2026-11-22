import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NoteImageFramingCropTests {
    private func near(_ lhs: CGFloat, _ rhs: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(lhs - rhs) <= tolerance }

    private func near(_ lhs: CGRect, _ rhs: CGRect, _ tolerance: CGFloat = 0.01) -> Bool {
        near(lhs.minX, rhs.minX, tolerance) && near(lhs.minY, rhs.minY, tolerance)
            && near(lhs.width, rhs.width, tolerance) && near(lhs.height, rhs.height, tolerance)
    }

    struct InvalidCrop: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let attribute: String
    }

    private static let invalidCrops = [
        InvalidCrop(testDescription: "missing component", attribute: "0,0,1"),
        InvalidCrop(testDescription: "nonnumeric components", attribute: "a,b,c,d"),
        InvalidCrop(testDescription: "zero width", attribute: "0,0,0,1"),
        InvalidCrop(testDescription: "NaN width", attribute: "0,0,nan,1"),
    ]

    @Test func cropAttributesParseWithSpaces() {
        let crop = NoteImageCrop(attribute: "0.1, 0.05,0.8,0.9")
        #expect(crop == NoteImageCrop(x: 0.1, y: 0.05, width: 0.8, height: 0.9), "crop attributes parse with spaces")
    }

    @Test func cropAttributesSerializeWithoutTrailingZeros() {
        let crop = NoteImageCrop(attribute: "0.1, 0.05,0.8,0.9")
        #expect(crop?.attribute == "0.1,0.05,0.8,0.9", "crop attributes write without trailing zeros: \(crop?.attribute ?? "nil")")
    }

    @Test func cropsSlideInsideTheImage() {
        #expect(NoteImageCrop(attribute: "0.9,0,0.5,1") == NoteImageCrop(x: 0.5, y: 0, width: 0.5, height: 1), "crops slide back inside the image")
    }

    @Test func oversizedCropsClampToTheFullImage() {
        #expect(NoteImageCrop(attribute: "-1,-1,2,3") == .full, "oversized crops clamp to the whole image")
    }

    @Test func narrowCropsGrowToTheMinimumSide() {
        #expect(NoteImageCrop(attribute: "0,0,0.001,0.5")?.width == NoteImageCrop.minimumSide, "slivers grow to the minimum side")
    }

    @Test(arguments: invalidCrops) func invalidCropAttributesAreIgnored(_ example: InvalidCrop) {
        #expect(NoteImageCrop(attribute: example.attribute) == nil)
    }

    @Test func normalizedCropsRoundTripAtFourDecimalPlaces() {
        let precise = NoteImageCrop(x: 0.333333, y: 0.1, width: 0.666666, height: 0.5).normalized
        #expect(precise.attribute == "0.3333,0.1,0.6667,0.5", "four decimals is plenty: \(precise.attribute)")
        #expect(NoteImageCrop(attribute: precise.attribute) == precise, "normalized crops read back identically")
    }

    @Test func aFullCropIsRecognized() {
        let precise = NoteImageCrop(x: 0.333333, y: 0.1, width: 0.666666, height: 0.5).normalized
        #expect(NoteImageCrop.full.isFull && !precise.isFull, "full crops are recognised")
    }

    @Test func aCropMapsIntoTheDisplayRectangle() {
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 200)
        let rect = NoteImageCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.25).rect(in: bounds)
        #expect(near(rect, CGRect(x: 110, y: 120, width: 200, height: 50)), "crops map into display rects")
    }

    @Test func aDisplayRectangleMapsBackToACrop() {
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 200)
        let rect = NoteImageCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.25).rect(in: bounds)
        #expect(NoteImageCrop(rect, in: bounds) == NoteImageCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.25), "display rects map back to crops")
    }

    @Test func aCropPositionsTheFullImageBehindTheFrame() {
        let full = NoteImageCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.25).fullRect(forFrame: CGRect(x: 0, y: 0, width: 300, height: 100))
        #expect(near(full, CGRect(x: -150, y: -200, width: 600, height: 400)), "the whole picture sits behind the frame: \(full)")
    }

    @Test func aCropScalesTheNaturalImageSize() {
        let size = NoteImageCrop(x: 0, y: 0, width: 0.5, height: 0.25).croppedSize(of: CGSize(width: 800, height: 400))
        #expect(size == CGSize(width: 400, height: 100), "cropped natural size")
    }

    @Test func freeCornersFollowThePointer() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let free = NoteImageCropGeometry.resize(start, handle: .bottomRight, by: CGSize(width: 50, height: 20), within: bounds, minimum: 24, aspect: nil)
        #expect(near(free, CGRect(x: 100, y: 100, width: 250, height: 120)), "free corners follow the pointer")
    }

    @Test func freeCornersStopAtTheImageEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let clamped = NoteImageCropGeometry.resize(start, handle: .topLeft, by: CGSize(width: -500, height: -500), within: bounds, minimum: 24, aspect: nil)
        #expect(near(clamped, CGRect(x: 0, y: 0, width: 300, height: 200)), "corners stop at the image edge")
    }

    @Test func freeEdgesKeepAMinimumWidthWithoutMovingTheOppositeEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let tiny = NoteImageCropGeometry.resize(start, handle: .right, by: CGSize(width: -400, height: 0), within: bounds, minimum: 24, aspect: nil)
        #expect(near(tiny.width, 24) && tiny.minX == 100, "edges keep a grabbable minimum")
    }

    @Test func freeEdgesMoveOnlyOneSide() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let edge = NoteImageCropGeometry.resize(start, handle: .top, by: CGSize(width: 30, height: -40), within: bounds, minimum: 24, aspect: nil)
        #expect(near(edge, CGRect(x: 100, y: 60, width: 200, height: 140)), "edges move one side only")
    }

    @Test func lockedCornersKeepTheirRatioAndOrigin() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let square = NoteImageCropGeometry.resize(start, handle: .bottomRight, by: CGSize(width: 60, height: 10), within: bounds, minimum: 24, aspect: 1)
        #expect(near(square.width, square.height) && near(square.width, 200) && square.origin == start.origin, "locked corners keep the ratio: \(square)")
    }

    @Test func lockedCornersStopAtTheNearestEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let roomy = NoteImageCropGeometry.resize(start, handle: .bottomRight, by: CGSize(width: 400, height: 400), within: bounds, minimum: 24, aspect: 1)
        #expect(near(roomy, CGRect(x: 100, y: 100, width: 200, height: 200)), "locked corners stop at the nearest edge: \(roomy)")
    }

    @Test func lockedEdgesGrowAroundTheMiddle() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let wide = NoteImageCropGeometry.resize(CGRect(x: 100, y: 100, width: 100, height: 100), handle: .right, by: CGSize(width: 100, height: 0),
                                                within: bounds, minimum: 24, aspect: 1)
        #expect(near(wide, CGRect(x: 100, y: 50, width: 200, height: 200)), "locked edges grow around the middle: \(wide)")
    }

    @Test func lockedTopEdgesKeepTheirRatioAndStayInside() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let topEdge = NoteImageCropGeometry.resize(CGRect(x: 100, y: 200, width: 100, height: 100), handle: .top, by: CGSize(width: 0, height: -150),
                                                   within: bounds, minimum: 24, aspect: 2)
        #expect(near(topEdge.width, topEdge.height * 2) && bounds.insetBy(dx: -0.01, dy: -0.01).contains(topEdge), "locked top edges stay inside: \(topEdge)")
    }

    @Test func movingACropStopsAtTheImageEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let moved = NoteImageCropGeometry.move(start, by: CGSize(width: 500, height: -500), within: bounds)
        #expect(near(moved, CGRect(x: 200, y: 0, width: 200, height: 100)), "moving stops at the edges")
    }

    @Test func fittingARatioKeepsAsMuchOfTheImageAsFits() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let fitted = NoteImageCropGeometry.fitted(aspect: 1, around: CGRect(x: 0, y: 0, width: 400, height: 300), within: bounds)
        #expect(near(fitted, CGRect(x: 50, y: 0, width: 300, height: 300)), "a ratio keeps as much picture as fits: \(fitted)")
    }

    @Test func fittingASmallCropKeepsItsAreaAndStaysInside() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let small = NoteImageCropGeometry.fitted(aspect: 2, around: CGRect(x: 300, y: 200, width: 50, height: 50), within: bounds)
        #expect(near(small.width, small.height * 2) && near(small.width * small.height, 2500, 1) && bounds.contains(small), "a ratio on a small crop keeps its size and stays inside: \(small)")
    }

    @Test func theCropMatchesItsAspectRatio() {
        let matches = NoteImageCropGeometry.matches(CGRect(x: 0, y: 0, width: 160, height: 90), aspect: 16.0 / 9.0)
        #expect(matches, "ratios match")
    }

    @Test func aspectPresetsResolveTheirRatios() {
        #expect(NoteImageCropAspect.original.ratio(natural: CGSize(width: 300, height: 200)) == 1.5 && NoteImageCropAspect.free.ratio(natural: nil) == nil, "aspect presets")
    }

    @Test func aspectPresetsHaveUniqueIdentifiers() {
        #expect(Set(NoteImageCropAspect.allCases.map(\.id)).count == NoteImageCropAspect.allCases.count, "aspect ids are unique")
    }

    @Test func cropHandlesIncludeFourCorners() {
        #expect(NoteImageCropHandle.allCases.filter(\.isCorner).count == 4, "four corners")
    }
}
