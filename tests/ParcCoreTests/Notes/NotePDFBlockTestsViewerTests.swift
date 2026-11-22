import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NotePDFBlockTestsViewerTests {
    @Test
    func zoomingInStepsUpFromFit() {
        let fit: CGFloat = 0.8
        let first = NotePDFZoom.zoomed(current: fit, fit: fit, zoomIn: true)
        #expect(first == .init(scale: fit * 1.25, fitsWidth: false), "zooming in steps up from fit: \(first)")
    }

    @Test
    func zoomingOutReturnsToFitWidth() {
        let fit: CGFloat = 0.8
        let first = NotePDFZoom.zoomed(current: fit, fit: fit, zoomIn: true)
        let back = NotePDFZoom.zoomed(current: first.scale, fit: fit, zoomIn: false)
        #expect(back.fitsWidth && back.scale == fit, "zooming back out lands on fit width")
    }

    @Test
    func zoomingAcrossFitWidthSnapsToIt() {
        let fit: CGFloat = 0.8
        let past = NotePDFZoom.zoomed(current: fit * 1.1, fit: fit, zoomIn: false)
        #expect(past.fitsWidth, "crossing fit width snaps to it")
    }

    @Test
    func zoomStopsAtTheMaximum() {
        let fit: CGFloat = 0.8
        var scale = fit
        for _ in 0..<40 { scale = NotePDFZoom.zoomed(current: scale, fit: fit, zoomIn: true).scale }
        #expect(abs(scale - fit * NotePDFZoom.maximumRatio) < 0.0001, "zoom tops out: \(scale)")
        #expect(!NotePDFZoom.canZoom(current: scale, fit: fit, zoomIn: true), "no more zoom at the top")
    }

    @Test
    func zoomStopsAtTheMinimum() {
        let fit: CGFloat = 0.8
        var scale = fit
        for _ in 0..<40 { scale = NotePDFZoom.zoomed(current: scale, fit: fit, zoomIn: false).scale }
        #expect(abs(scale - fit * NotePDFZoom.minimumRatio) < 0.0001, "zoom bottoms out: \(scale)")
    }

    @Test
    func zoomPercentageIsRelativeToFitWidth() {
        let fit: CGFloat = 0.8
        #expect(NotePDFZoom.percent(current: fit * 1.5, fit: fit) == 150, "percent is relative to fit width")
    }

    @Test
    func anInvalidScaleResetsToFitWidth() {
        let fit: CGFloat = 0.8
        #expect(NotePDFZoom.zoomed(current: .nan, fit: fit, zoomIn: true).fitsWidth, "broken scales reset to fit")
    }

    @Test
    func pageLabelsCountFromOne() {
        #expect(NotePDFPages.label(current: 0, count: 12) == "1 / 12", "pages count from one")
    }

    @Test
    func pageLabelsClampToTheLastPage() {
        #expect(NotePDFPages.label(current: 40, count: 12) == "12 / 12", "page labels clamp")
    }

    @Test
    func aDocumentWithoutPagesShowsADash() {
        #expect(NotePDFPages.label(current: 0, count: 0) == "–", "an empty document says so")
    }

    @Test
    func theSpokenLabelIncludesThePageAndTotal() {
        #expect(NotePDFPages.spokenLabel(current: 2, count: 9) == "Page 3 of 9", "VoiceOver hears the page")
    }

    @Test
    func aSinglePageHasANaturalSpokenLabel() {
        #expect(NotePDFPages.spokenLabel(current: 0, count: 1) == "One page", "single pages read naturally")
    }

    @Test
    func pageSummariesUseSingularAndPlural() {
        #expect(NotePDFPages.summary(count: 1) == "1 page" && NotePDFPages.summary(count: 3) == "3 pages", "page counts read naturally")
    }
}
