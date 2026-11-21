import Foundation

struct EaselVectorSectionTitle: Equatable {
    var text: String
    var width: Double
    var baseline: Double
}

extension EaselVectorExport {
    static func paintedFrame(_ item: EaselItem) -> EaselRect {
        let f = item.frame
        switch item.kind {
        case .sticky:
            let scale = EaselBoardObjects.textScale(item)
            return EaselRect(x: f.x - 3 * scale, y: f.y - 2 * scale, width: f.width + 6 * scale, height: f.height + 20 * scale)
        case .section:
            let reach = EaselBoardObjects.sectionTitleHeight + EaselBoardObjects.sectionTitleGap
            return EaselRect(x: f.x, y: f.y - reach, width: f.width, height: f.height + reach)
        default:
            return f
        }
    }
}
