import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NoteImageFramingMaskTests {
    @Test(arguments: NoteImageMask.allCases) func maskPathsFitTheirFrameAndKeepTheCenterVisible(_ mask: NoteImageMask) {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let box = mask.path(in: rect).boundingBoxOfPath
        #expect(!box.isEmpty && rect.insetBy(dx: -0.5, dy: -0.5).contains(box), "\(mask) stays inside its frame: \(box)")
        #expect(mask.path(in: rect).contains(CGPoint(x: rect.midX, y: rect.midY)), "\(mask) keeps the middle visible")
    }

    @Test(arguments: NoteImageMask.allCases) func svgMaskPathsAreClosed(_ mask: NoteImageMask) {
        let svg = mask.svgPathData
        #expect(svg.hasPrefix("M") && svg.hasSuffix("Z"), "\(mask) writes a closed SVG path")
    }

    @Test(arguments: NoteImageMask.allCases) func everyMaskHasAName(_ mask: NoteImageMask) {
        #expect(!mask.title.isEmpty, "\(mask) has a name")
    }

    @Test(arguments: NoteImageMask.allCases) func maskUnitPathsFitTheUnitSquare(_ mask: NoteImageMask) {
        let unit = mask.unitPath.boundingBoxOfPath
        #expect(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.001, dy: -0.001).contains(unit), "\(mask) unit path fits the unit square")
    }

    @Test(arguments: NoteImageMask.allCases) func squareMasksUseImagesExceptForCircles(_ mask: NoteImageMask) {
        #expect(mask.isSquare == (mask.borderRadius(frameAspect: nil) == nil || mask == .circle), "\(mask) square shapes need a mask image except circles")
    }

    @Test func roundedMasksCutCornersAndKeepSides() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        #expect(!NoteImageMask.rounded.path(in: rect).contains(CGPoint(x: rect.minX + 1, y: rect.minY + 1)), "rounded corners are cut")
        #expect(NoteImageMask.rounded.path(in: rect).contains(CGPoint(x: rect.minX + 1, y: rect.midY)), "rounded sides stay")
    }

    @Test func roundedMasksUseATenthOfTheShortSide() {
        #expect(NoteImageMask.roundedRadius(for: CGSize(width: 300, height: 200)) == 20, "rounded radius is a tenth of the short side")
    }

    @Test func anArchTopUsesACircularRadiusAtEitherHeight() {
        #expect(NoteImageMask.archRadius(for: CGSize(width: 300, height: 200)) == 150, "arches are round on top")
        #expect(NoteImageMask.archRadius(for: CGSize(width: 300, height: 100)) == 100, "low arches stay circular like CSS")
    }

    @Test func archesCutTheTopCornersAndKeepTheBottomCorners() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let arch = NoteImageMask.arch.path(in: rect)
        #expect(!arch.contains(CGPoint(x: rect.minX + 2, y: rect.minY + 2)) && arch.contains(CGPoint(x: rect.minX + 2, y: rect.maxY - 2)), "arches cut the top corners and keep the bottom ones")
    }

    @Test func heartMasksPointDown() {
        let heart = NoteImageMask.heart.path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(heart.contains(CGPoint(x: 25, y: 25)) && !heart.contains(CGPoint(x: 10, y: 90)), "hearts point down in top-down space")
    }

    @Test func starMasksPointUp() {
        let star = NoteImageMask.star.path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(star.contains(CGPoint(x: 50, y: 10)) && !star.contains(CGPoint(x: 50, y: 92)), "stars point up in top-down space")
    }

    @Test func roundedCssRadiiFollowTheFrameAspect() {
        #expect(NoteImageMask.rounded.borderRadius(frameAspect: 0.5) == "5%/10%", "rounded CSS radius follows the frame")
        #expect(NoteImageMask.rounded.borderRadius(frameAspect: 2) == "10%/5%", "tall frames swap the radius")
    }

    @Test func theCircleMaskUsesAFiftyPercentRadius() {
        #expect(NoteImageMask.circle.borderRadius(frameAspect: 1) == "50%", "circles are a radius")
    }

    @Test func theArchMaskUsesRoundedTopCorners() {
        #expect(NoteImageMask.arch.borderRadius(frameAspect: nil) == "9999px 9999px 0 0", "arches clamp like the editor")
    }

    @Test func shapesProduceSvgMaskImages() {
        #expect(NoteImageMask.star.maskImageURL.hasPrefix("data:image/svg+xml,%3Csvg"), "shapes become SVG mask images")
    }

    @Test func maskImageUrlsAreCssSafe() {
        #expect(!NoteImageMask.heart.maskImageURL.contains("<") && !NoteImageMask.heart.maskImageURL.contains("\""), "mask URLs are CSS safe")
    }

    @Test func applyingASquareMaskCropsToTheCenterSquare() {
        var props = NoteBlockProps()
        props.crop = NoteImageCrop(x: 0, y: 0, width: 1, height: 0.5)
        let circled = NoteImageFraming.applying(.circle, to: props, natural: CGSize(width: 800, height: 600))
        #expect(circled.mask == .circle, "the mask applies")
        #expect(circled.crop == NoteImageCrop(x: 0.3125, y: 0, width: 0.375, height: 0.5), "square shapes crop to the middle square: \(String(describing: circled.crop))")
    }

    @Test func applyingAFreeShapeLeavesTheCropAlone() {
        var props = NoteBlockProps()
        props.crop = NoteImageCrop(x: 0, y: 0, width: 1, height: 0.5)
        let rounded = NoteImageFraming.applying(.rounded, to: props, natural: CGSize(width: 800, height: 600))
        #expect(rounded.crop == props.crop && rounded.mask == .rounded, "free shapes leave the crop alone")
    }

    @Test func aSquareImageNeedsNoAdditionalCropForASquareMask() {
        let plain = NoteImageFraming.applying(.heart, to: NoteBlockProps(), natural: CGSize(width: 500, height: 500))
        #expect(plain.crop == nil, "square pictures need no crop for square shapes")
    }

    @Test func aMaskAppliesWithUnknownImageDimensions() {
        let unknown = NoteImageFraming.applying(.star, to: NoteBlockProps(), natural: nil)
        #expect(unknown.crop == nil && unknown.mask == .star, "unknown sizes still take the shape")
    }

    @Test func clearingAMaskKeepsTheCrop() {
        var props = NoteBlockProps()
        props.crop = NoteImageCrop(x: 0, y: 0, width: 1, height: 0.5)
        let circled = NoteImageFraming.applying(.circle, to: props, natural: CGSize(width: 800, height: 600))
        let cleared = NoteImageFraming.applying(nil, to: circled, natural: nil)
        #expect(cleared.mask == nil && cleared.crop == circled.crop, "removing the shape keeps the crop")
    }

    @Test func theFrameAspectUsesTheCroppedDimensions() {
        var props = NoteBlockProps()
        props.crop = NoteImageCrop(x: 0, y: 0, width: 1, height: 0.5)
        #expect(NoteImageFraming.frameAspect(crop: props.crop, natural: CGSize(width: 800, height: 600)) == 0.375, "frame aspect")
    }
}
