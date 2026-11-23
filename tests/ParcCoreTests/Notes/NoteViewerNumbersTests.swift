import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NoteViewerNumbersTests {
    @Test func theZoomPercentOfAnInfiniteScaleIsTheDefault() {
        #expect(NotePDFZoom.percent(current: .infinity, fit: 1) == 100)
        #expect(NotePDFZoom.percent(current: 1, fit: .infinity) == 100)
        #expect(NotePDFZoom.percent(current: .nan, fit: 1) == 100)
    }

    @Test func theZoomPercentOfAnOverflowingRatioIsCappedInsteadOfCrashing() {
        let tiny = CGFloat.leastNonzeroMagnitude
        #expect(NotePDFZoom.percent(current: .greatestFiniteMagnitude, fit: tiny) == 100)
        #expect(NotePDFZoom.percent(current: 1e30, fit: 1) == 1_000_000)
    }

    @Test func theZoomPercentOfOrdinaryScalesIsUnchanged() {
        #expect(NotePDFZoom.percent(current: 2, fit: 1) == 200)
        #expect(NotePDFZoom.percent(current: 0.5, fit: 1) == 50)
    }

    @Test(arguments: [0, -3])
    func aDiagramProblemPointingBeforeTheFirstLineHighlightsTheFirstLine(_ line: Int) {
        var problem = NoteMermaidProblem(message: "Parse error")
        problem.line = line
        #expect(problem.range(in: "graph TD\nA-->B") == 0..<8)
    }
}
