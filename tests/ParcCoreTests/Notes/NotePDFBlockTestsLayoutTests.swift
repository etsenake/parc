import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NotePDFBlockTestsLayoutTests {
    struct WidthCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let fraction: Double?
        let columnWidth: CGFloat
        let expected: CGFloat

        init(_ label: String, _ fraction: Double?, _ columnWidth: CGFloat, _ expected: CGFloat) {
            testDescription = label
            self.fraction = fraction
            self.columnWidth = columnWidth
            self.expected = expected
        }
    }

    @Test(arguments: [
        WidthCase("a fresh PDF spans the column", nil, 700, 700),
        WidthCase("fractions scale with the column", 0.5, 700, 350),
        WidthCase("PDFs keep a readable minimum", 0.1, 700, NotePDFLayout.minimumWidth),
        WidthCase("narrow columns cap the minimum", 0.1, 150, 150),
        WidthCase("point widths from hand-written files work", 420, 700, 420),
        WidthCase("broken widths fall back to full width", .nan, 700, 700),
    ])
    func thePDFUsesTheExpectedWidthForItsColumn(fixture: WidthCase) {
        #expect(NotePDFLayout.displayWidth(fraction: fixture.fraction, columnWidth: fixture.columnWidth) == fixture.expected)
    }

    @Test
    func theViewerFitsALetterPageAtTheWidth() {
        let letter = NotePDFLayout.viewerHeight(width: 516, aspect: 11 / 8.5)
        #expect(letter == ((516 - 16) * 11 / 8.5 + 16).rounded(), "the viewer fits one page at the width: \(letter)")
    }

    @Test
    func unknownPageAspectsUseLetter() {
        let letter = NotePDFLayout.viewerHeight(width: 516, aspect: 11 / 8.5)
        #expect(NotePDFLayout.viewerHeight(width: 516, aspect: nil) == letter, "unknown pages assume Letter")
    }

    @Test
    func tallViewersCapAtTheMaximum() {
        #expect(NotePDFLayout.viewerHeight(width: 2000, aspect: 1.414) == NotePDFLayout.maximumHeight, "tall viewers cap")
    }

    @Test
    func shortViewersKeepTheirMinimumHeight() {
        #expect(NotePDFLayout.viewerHeight(width: 300, aspect: 0.3) == NotePDFLayout.minimumHeight, "slim slides keep a floor")
    }

    @Test
    func wideSlidesUseAShortViewer() {
        #expect(NotePDFLayout.viewerHeight(width: 600, aspect: 9 / 16) == ((600 - 16) * 9 / 16 + 16).rounded(), "slides make short viewers")
    }

    struct AspectCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let width: CGFloat
        let height: CGFloat
        let rotation: Int
        let expected: CGFloat?

        init(_ label: String, _ width: CGFloat, _ height: CGFloat, _ rotation: Int, _ expected: CGFloat?) {
            testDescription = label
            self.width = width
            self.height = height
            self.rotation = rotation
            self.expected = expected
        }
    }

    @Test(arguments: [
        AspectCase("portrait", 612, 792, 0, 792.0 / 612.0),
        AspectCase("right-angle rotation", 612, 792, 90, 612.0 / 792.0),
        AspectCase("negative rotation normalizes", 612, 792, -270, 612.0 / 792.0),
        AspectCase("empty page", 0, 792, 0, nil),
    ])
    func pageAspectAccountsForRotation(fixture: AspectCase) {
        #expect(NotePDFLayout.pageAspect(width: fixture.width, height: fixture.height, rotation: fixture.rotation) == fixture.expected)
    }

    @Test
    func nearFullWidthSnapsToFull() {
        #expect(NotePDFLayout.storedFraction(width: 697, columnWidth: 700) == nil, "near full width snaps to full")
    }

    @Test
    func aHalfWidthPDFStoresAFraction() {
        #expect(NotePDFLayout.storedFraction(width: 350, columnWidth: 700) == 0.5, "half width stores a fraction")
    }

    @Test
    func aTinyPDFStoresItsMinimumFraction() {
        #expect(NotePDFLayout.storedFraction(width: 10, columnWidth: 700) == Double((NotePDFLayout.minimumWidth / 700 * 1000).rounded() / 1000), "tiny widths settle at the minimum")
    }

    @Test
    func centeredResizingMovesBothEdges() {
        #expect(NotePDFLayout.rawResize(start: 400, dragDelta: 20, leading: false, alignment: .center) == 440, "centred PDFs grow both ways")
    }

    @Test
    func theLeadingHandleShrinksLeftAlignedPDFs() {
        #expect(NotePDFLayout.rawResize(start: 400, dragDelta: 20, leading: true, alignment: .left) == 380, "the leading bar shrinks left PDFs")
    }

    @Test
    func draggingPastTheColumnRubberBands() {
        let banded = NotePDFLayout.rubberBanded(900, columnWidth: 700)
        #expect(banded > 700 && banded < 790, "dragging past the column rubber-bands: \(banded)")
    }

    @Test
    func rightAlignedPDFsHugTheColumnEdge() {
        #expect(NotePDFLayout.originX(width: 300, alignment: .right, columnWidth: 700) == 400, "right alignment hugs the edge")
    }
}
