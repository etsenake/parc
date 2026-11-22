import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsPaginationTests {
    private static let sampleSpans = [
        NotePagePrintSpan(minY: 0, maxY: 300, keepsTogether: true),
        NotePagePrintSpan(minY: 304, maxY: 700, keepsTogether: false),
        NotePagePrintSpan(minY: 310, maxY: 360, keepsTogether: true),
        NotePagePrintSpan(minY: 364, maxY: 980, keepsTogether: true),
        NotePagePrintSpan(minY: 984, maxY: 1100, keepsTogether: true),
    ]

    private static let overlappingSpans = [NotePagePrintSpan(minY: 900, maxY: 1010, keepsTogether: true), NotePagePrintSpan(minY: 850, maxY: 960, keepsTogether: true)]

    struct PageBreak: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let proposed: CGFloat
        let limit: CGFloat
        let spans: [NotePagePrintSpan]
        let expected: CGFloat
    }

    private static let pageBreaks = [
        PageBreak(testDescription: "straddling block", proposed: 1000, limit: 800, spans: sampleSpans, expected: 984),
        PageBreak(testDescription: "between blocks", proposed: 984, limit: 800, spans: sampleSpans, expected: 984),
        PageBreak(testDescription: "block too tall for the slack", proposed: 600, limit: 480, spans: sampleSpans, expected: 600),
        PageBreak(testDescription: "between children in a container", proposed: 340, limit: 200, spans: sampleSpans, expected: 310),
        PageBreak(testDescription: "overlapping blocks", proposed: 1000, limit: 800, spans: overlappingSpans, expected: 850),
        PageBreak(testDescription: "empty page", proposed: 1000, limit: 800, spans: [], expected: 1000),
    ]

    struct Bottom: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let adjusted: CGFloat
        let preferred: CGFloat
        let bottom: CGFloat
        let limit: CGFloat
        let expected: CGFloat
    }

    private static let bottoms = [
        Bottom(testDescription: "moved break", adjusted: 984, preferred: 984, bottom: 1000, limit: 800, expected: 984),
        Bottom(testDescription: "above the limit", adjusted: 700, preferred: 984, bottom: 1000, limit: 800, expected: 800),
        Bottom(testDescription: "past the bottom", adjusted: 1200, preferred: 1000, bottom: 1000, limit: 800, expected: 1000),
        Bottom(testDescription: "short last page", adjusted: 500, preferred: 500, bottom: 500, limit: 800, expected: 500),
    ]

    @Test(arguments: pageBreaks) func pageBreaksRespectBlockBoundaries(_ example: PageBreak) {
        #expect(NotePagePagination.pageBreak(proposed: example.proposed, limit: example.limit, spans: example.spans) == example.expected)
    }

    @Test(arguments: bottoms) func theSettledBreakStaysWithinThePage(_ example: Bottom) {
        #expect(NotePagePagination.settledBottom(adjusted: example.adjusted, preferred: example.preferred, bottom: example.bottom,
                                                 limit: example.limit) == example.expected)
    }
}
