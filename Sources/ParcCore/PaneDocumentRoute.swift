import Foundation

package enum PaneDocumentRoute: Equatable {
    case newTab
    case overPage
    case replacePane
}

extension PaneDocumentRoute {
    package static func routes(paneCount: Int, paneHoldsWebPage: Bool) -> [PaneDocumentRoute] {
        guard paneCount > 1 else { return [.newTab] }
        return paneHoldsWebPage ? [.overPage, .newTab] : [.replacePane]
    }
}
