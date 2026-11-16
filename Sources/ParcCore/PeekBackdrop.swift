import Foundation

enum PeekBackdrop: Equatable {
    case webPage(tabID: UUID)
    case document(tabID: UUID)
    case startPage(spaceID: UUID)
    case unavailable

    enum ArchivePreviewRoute: Equatable {
        case fromPage
        case overWindow(hostID: UUID)
    }

    init(currentTabID: UUID?, tabIsOpen: Bool, isDocument: Bool, hasPageWrapper: Bool, hasLivePage: Bool,
         showsStartPage: Bool, activeSpaceID: UUID) {
        guard let id = currentTabID else {
            self = showsStartPage ? .startPage(spaceID: activeSpaceID) : .unavailable
            return
        }
        if !tabIsOpen { self = .unavailable }
        else if isDocument { self = hasPageWrapper ? .unavailable : .document(tabID: id) }
        else { self = hasLivePage ? .webPage(tabID: id) : .unavailable }
    }

    static func hostID(currentTabID: UUID?, showsStartPage: Bool, activeSpaceID: UUID) -> UUID? {
        currentTabID ?? (showsStartPage ? activeSpaceID : nil)
    }

    var archivePreviewRoute: ArchivePreviewRoute? {
        switch self {
        case .webPage: return .fromPage
        case .document(let id), .startPage(let id): return .overWindow(hostID: id)
        case .unavailable: return nil
        }
    }
}
