import CoreGraphics
import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

enum NoteCanvasLayoutTestsSupport {
    static let measure = NoteCanvasMeasure(
        height: { block, _ in
            switch block.kind {
            case .heading: return 40
            case .divider: return 13
            case .callout: return 54
            default: return 26
            }
        },
        childIndent: { block in
            switch block.kind {
            case .callout: return 46
            case .quote: return 17
            default: return 26
            }
        })

    static func layout(_ blocks: [NoteBlock], width: CGFloat = 1000, header: CGFloat = 100, fullWidth: Bool = false,
                overrides: [NoteBlockID: [CGFloat]] = [:]) -> NoteCanvasLayout {
        var metrics = NoteCanvasMetrics()
        metrics.fullWidth = fullWidth
        return NoteCanvasLayout(page: NotePage(blocks: blocks), width: width, headerHeight: header, metrics: metrics,
                                columnFractions: overrides, measure: Self.measure)
    }
}
