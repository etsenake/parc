import Foundation

enum PaneDocumentRoute: Equatable {
    case newTab
    case overPage
    case replacePane
}

extension PaneDocumentRoute {
    static func routes(paneCount: Int, paneShowsWebPage: Bool, isNote: Bool) -> [PaneDocumentRoute] {
        guard paneCount > 1 else { return [.newTab] }
        guard paneShowsWebPage, isNote else { return [.replacePane] }
        return [.overPage, .newTab]
    }
}
