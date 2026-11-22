import Foundation
import CoreGraphics
import Testing
@testable import ParcCore

struct EaselImageFramingGeometryTests {
    @Test(arguments: 0...3) func quarterTurnsRoundTripACrop(_ turns: Int) {
        let crop = EaselRect(x: 0.1, y: 0.2, width: 0.3, height: 0.5)
        let turned = EaselImageFraming.turnedCrop(crop, turns: turns)
        #expect(EaselImageFramingTestsSupport.close(EaselImageFraming.sourceCrop(turned, turns: turns), crop))
    }

    @Test func quarterTurnsRotateACropAndSwapTheSides() {
        let crop = EaselRect(x: 0.1, y: 0.2, width: 0.3, height: 0.5)
        let quarter = EaselImageFraming.turnedCrop(crop, turns: 1)
        #expect(abs(quarter.x - 0.3) < 0.0001 && abs(quarter.y - 0.1) < 0.0001 && abs(quarter.width - 0.5) < 0.0001 && abs(quarter.height - 0.3) < 0.0001,
               "a clockwise turn moves the source's left edge to the top")
        #expect(EaselImageFraming.turnedSize(CGSize(width: 40, height: 10), turns: 3) == CGSize(width: 10, height: 40), "odd turns swap width and height")
        #expect(EaselImageFraming.turns(-1) == 3 && EaselImageFraming.turns(5) == 1, "turns wrap around")
        #expect(EaselImageFraming.sourceCrop(.full, turns: 2) == nil, "a whole picture has no crop")
        let aspect = EaselImageFraming.displayAspect(natural: CGSize(width: 400, height: 200), crop: EaselRect(x: 0, y: 0, width: 0.5, height: 1), turns: 1)
        #expect(aspect.map { EaselImageFramingTestsSupport.close($0, 1) } == true, "a half-width crop of a 2:1 picture turned once is square")
    }

    @Test func aCroppedPictureDrawsItsWholeSourceRotatedAboutTheCentre() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let picture = EaselImageFraming.pictureRect(frame: frame, crop: EaselRect(x: 0.25, y: 0, width: 0.5, height: 1), turns: 0)
        #expect(EaselImageFramingTestsSupport.close(picture, CGRect(x: 0, y: 100, width: 400, height: 100)), "the whole picture extends beyond a cropped frame")
        let source = EaselImageFraming.sourceRect(picture: CGRect(x: 0, y: 0, width: 100, height: 40), turns: 1)
        #expect(EaselImageFramingTestsSupport.close(source, CGRect(x: 30, y: -30, width: 40, height: 100)), "a turned picture draws its source rotated about the centre")
        let rotated = EaselImageFraming.rotatedClockwise(CGRect(x: 0, y: 0, width: 100, height: 40), around: CGPoint(x: 50, y: 20))
        #expect(EaselImageFramingTestsSupport.close(rotated, CGRect(x: 30, y: -30, width: 40, height: 100)), "rotating a rect clockwise swaps its sides about the pivot")
    }

    @Test
    func anUncroppedDraftStartsWholeAtActualSize() {
        let draft = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        #expect(draft.isWhole && EaselImageFramingTestsSupport.close(draft.zoom, 1) && draft.picture == draft.frame, "an uncropped image starts whole at zoom 1")
    }

    @Test
    func zoomingScalesThePictureAroundTheFixedFramesCentre() {
        var draft = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        draft.setZoom(2)
        #expect(EaselImageFramingTestsSupport.close(draft.zoom, 2) && EaselImageFramingTestsSupport.close(draft.frame, CGRect(x: 100, y: 100, width: 200, height: 100)), "zooming scales the picture under a fixed frame")
        #expect(EaselImageFramingTestsSupport.close(draft.picture, CGRect(x: 0, y: 50, width: 400, height: 200)), "zoom scales about the frame's centre")
        #expect(EaselImageFramingTestsSupport.close(draft.result.crop, EaselRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)), "a 2× zoom keeps the middle half")
    }

    @Test
    func panningStopsBeforeItUncoversTheFrame() {
        var draft = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        draft.setZoom(2)
        draft.move(by: CGSize(width: 500, height: -500))
        #expect(EaselImageFramingTestsSupport.close(draft.picture.minX, 100) && EaselImageFramingTestsSupport.close(draft.picture.maxY, 200), "panning stops before the picture uncovers the frame")
    }

    @Test
    func draftZoomStaysWithinItsLimits() {
        var draft = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        draft.setZoom(100)
        #expect(EaselImageFramingTestsSupport.close(draft.zoom, EaselImageCropDraft.maximumZoom), "zoom stops at its maximum")
        draft.setZoom(0.1)
        #expect(EaselImageFramingTestsSupport.close(draft.zoom, 1), "zoom never goes below a covering picture")
    }

    @Test
    func draggingTheLeftHandleTrimsTheLeftEdge() {
        var resized = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        resized.resize(.left, from: resized.frame, by: CGSize(width: 50, height: 0), lockingAspect: false)
        #expect(EaselImageFramingTestsSupport.close(resized.frame, CGRect(x: 150, y: 100, width: 150, height: 100)), "the left handle trims the left edge")
        #expect(EaselImageFramingTestsSupport.close(resized.result.crop, EaselRect(x: 0.25, y: 0, width: 0.75, height: 1)), "trimming becomes a normalised crop")
    }

    @Test
    func aCropHandleCannotPullPastThePicture() {
        var resized = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        resized.resize(.left, from: resized.frame, by: CGSize(width: 50, height: 0), lockingAspect: false)
        resized.resize(.left, from: resized.frame, by: CGSize(width: -500, height: 0), lockingAspect: false)
        #expect(EaselImageFramingTestsSupport.close(resized.frame.minX, 100), "a handle can't pull the frame past the picture")
    }

    @Test
    func cropFramesKeepAGrabbableMinimumSize() {
        var resized = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        resized.resize(.bottomRight, from: resized.frame, by: CGSize(width: -1000, height: -1000), lockingAspect: false)
        #expect(resized.frame.width >= EaselImageCropDraft.minimumSide - 0.01 && resized.frame.height >= EaselImageCropDraft.minimumSide - 0.01,
               "the frame keeps a grabbable minimum size")
    }

    @Test
    func lockingAspectKeepsTheCropRatio() {
        var locked = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        locked.resize(.bottomRight, from: locked.frame, by: CGSize(width: -100, height: 0), lockingAspect: true)
        #expect(EaselImageFramingTestsSupport.close(locked.frame.width / locked.frame.height, 2), "Shift keeps the frame's ratio")
    }

    @Test
    func resettingACropShowsTheWholePicture() {
        var reset = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        reset.setZoom(3)
        reset.resize(.top, from: reset.frame, by: CGSize(width: 0, height: 40), lockingAspect: false)
        reset.reset()
        #expect(reset.isWhole && EaselImageFramingTestsSupport.close(reset.zoom, 1), "reset shows the whole picture again")
    }

    @Test
    func anUntouchedCropDraftAppliesWithoutChanges() {
        var item = EaselImageFramingTestsSupport.image()
        item.crop = EaselRect(x: 0.25, y: 0, width: 0.5, height: 1)
        let cropped = EaselImageCropDraft(item: item, natural: CGSize(width: 400, height: 100))
        #expect(EaselImageFramingTestsSupport.close(cropped.picture, CGRect(x: 0, y: 100, width: 400, height: 100)), "an existing crop opens showing the whole picture")
        #expect(cropped.applying(to: item) == item, "saving an untouched draft changes nothing")
    }

    @Test
    func aTightCropReopensAtItsActualZoom() {
        var tight = EaselImageFramingTestsSupport.image()
        tight.crop = EaselRect(x: 0.48, y: 0.48, width: 0.04, height: 0.04)
        tight.frame = EaselRect(x: 0, y: 0, width: 100, height: 100)
        let zoomed = EaselImageCropDraft(item: tight, natural: CGSize(width: 1000, height: 1000))
        #expect(EaselImageFramingTestsSupport.close(zoomed.zoom, 25) && zoomed.zoomLimit >= 25, "a tight saved crop reopens at its real zoom")
    }

    @Test
    func aTightCropZoomsByStepsFromItsActualZoom() {
        var tight = EaselImageFramingTestsSupport.image()
        tight.crop = EaselRect(x: 0.48, y: 0.48, width: 0.04, height: 0.04)
        tight.frame = EaselRect(x: 0, y: 0, width: 100, height: 100)
        var zoomed = EaselImageCropDraft(item: tight, natural: CGSize(width: 1000, height: 1000))
        let before = zoomed.picture.width
        zoomed.setZoom(zoomed.zoom * 1.25)
        #expect(zoomed.picture.width >= before - 0.01, "zooming in on a tight crop never zooms out")
        zoomed.setZoom(zoomed.zoom / 1.25)
        #expect(zoomed.picture.width < before + 0.01 && zoomed.picture.width > before * 0.7, "zooming back out steps down from the real zoom")
    }

    @Test func rotatingAnImageTurnsItsFrameAndKeepsItsCrop() {
        var draft = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        draft.rotate()
        #expect(draft.turns == 1 && EaselImageFramingTestsSupport.close(draft.frame, CGRect(x: 150, y: 50, width: 100, height: 200)), "rotating turns the frame about its centre")
        #expect(draft.result.turns == 1 && draft.result.crop == nil, "a turned whole picture stores a turn and no crop")
        draft.setAspect(.square)
        let square = draft.result
        draft.rotate(); draft.rotate(); draft.rotate()
        #expect(draft.turns == 0 && draft.result.turns == nil, "four turns come back to the start")
        #expect(EaselImageFramingTestsSupport.close(draft.frame.width, CGFloat(square.frame.width)) && EaselImageFramingTestsSupport.close(draft.frame.height, CGFloat(square.frame.height)), "a square crop stays square while turning")
        var wide = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        wide.setAspect(.wide169)
        wide.rotate()
        #expect(wide.aspect == .tall916, "a 16:9 crop becomes 9:16 when turned")
        var item = EaselImageFramingTestsSupport.image()
        item.quarterTurns = 1
        item.frame = EaselRect(x: 0, y: 0, width: 100, height: 200)
        var turned = EaselImageCropDraft(item: item, natural: CGSize(width: 400, height: 200))
        turned.resize(.top, from: turned.frame, by: CGSize(width: 0, height: 100), lockingAspect: false)
        let applied = turned.applying(to: item)
        #expect(applied.quarterTurns == 1 && EaselImageFramingTestsSupport.close(applied.crop, EaselRect(x: 0.5, y: 0, width: 0.5, height: 1)),
               "a crop made on a turned picture is stored against the original image")
    }

    @Test
    func ratioPresetsKeepTheFrameWithinThePicture() {
        var draft = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        draft.setAspect(.square)
        #expect(EaselImageFramingTestsSupport.close(draft.frame.width, draft.frame.height) && draft.picture.contains(draft.frame), "square fits inside the picture")
        draft.setAspect(.original)
        #expect(EaselImageFramingTestsSupport.close(draft.frame.width / draft.frame.height, 2), "original uses the picture's own ratio")
    }

    @Test
    func roundMasksUseASquareCropUntilRemoved() {
        var draft = EaselImageCropDraft(item: EaselImageFramingTestsSupport.image(), natural: CGSize(width: 400, height: 200))
        draft.setAspect(.square)
        draft.setAspect(.original)
        draft.setAspect(.free)
        draft.setMask(.circle)
        #expect(draft.mask == .circle && draft.aspect == .square && EaselImageFramingTestsSupport.close(draft.frame.width, draft.frame.height), "a circle mask squares the crop")
        draft.setMask(.rounded)
        #expect(draft.aspect == .free, "leaving a square mask frees the ratio again")
        #expect(draft.result.mask == .rounded, "the mask is saved with the crop")
    }

    @Test
    func replacingAnImageKeepsItsFrameAndMask() {
        var item = EaselImageFramingTestsSupport.image()
        item.mask = .heart
        item.quarterTurns = 2
        item.altText = "A dog"
        item.crop = EaselRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let replaced = EaselImageFraming.replacing(item, natural: CGSize(width: 100, height: 100))
        #expect(replaced.frame == item.frame, "a replaced image keeps its size and spot")
        #expect(replaced.quarterTurns == nil && replaced.mask == .heart && replaced.altText == nil,
               "replacing keeps the mask and drops the turn and the old picture's description")
        #expect(EaselImageFramingTestsSupport.close(replaced.crop, EaselRect(x: 0, y: 0.25, width: 1, height: 0.5)), "the new picture fills the old frame from its middle")
    }

    @Test
    func replacingWithAnImageOfTheSameRatioNeedsNoCrop() {
        var item = EaselImageFramingTestsSupport.image()
        item.mask = .heart
        item.quarterTurns = 2
        item.altText = "A dog"
        item.crop = EaselRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let sameShape = EaselImageFraming.replacing(item, natural: CGSize(width: 800, height: 400))
        #expect(sameShape.crop == nil, "a picture with the same shape needs no crop")
    }

    @Test
    func aCircleMaskSquaresAWideImageFromTheCentre() {
        let masked = EaselImageFraming.masking(EaselImageFramingTestsSupport.image(), with: .circle)
        #expect(masked.frame == EaselRect(x: 150, y: 100, width: 100, height: 100) && EaselImageFramingTestsSupport.close(masked.crop, EaselRect(x: 0.25, y: 0, width: 0.5, height: 1)),
               "a circle mask squares a wide image from its middle")
    }

    @Test
    func aRoundedMaskKeepsTheOriginalFrame() {
        let rounded = EaselImageFraming.masking(EaselImageFramingTestsSupport.image(), with: .rounded)
        #expect(rounded.frame == EaselImageFramingTestsSupport.image().frame && rounded.crop == nil && rounded.mask == .rounded, "a rounded mask keeps the frame")
    }

    @Test
    func removingAMaskClearsTheSavedMask() {
        let masked = EaselImageFraming.masking(EaselImageFramingTestsSupport.image(), with: .circle)
        #expect(EaselImageFraming.masking(masked, with: nil).mask == nil, "removing a mask keeps the crop")
    }

    @Test
    func everyEaselMaskIsAlsoANotesMask() {
        #expect(EaselImageMask.allCases.allSatisfy { NoteImageMask(rawValue: $0.rawValue) != nil }, "every Easel mask is a Notes mask")
    }
}
