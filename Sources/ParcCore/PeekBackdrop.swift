import Foundation

enum PeekBackdrop: Equatable {
    case webPage(tabID: UUID)
    case pagelessTab(tabID: UUID)
    case startPage(spaceID: UUID)
    case unavailable

    enum ArchivePreviewRoute: Equatable {
        case fromPage
        case overWindow(hostID: UUID)
    }

    init(currentTabID: UUID?, tabIsOpen: Bool, hasLivePage: Bool, showsStartPage: Bool, activeSpaceID: UUID) {
        guard let id = currentTabID else {
            self = showsStartPage ? .startPage(spaceID: activeSpaceID) : .unavailable
            return
        }
        self = !tabIsOpen ? .unavailable : hasLivePage ? .webPage(tabID: id) : .pagelessTab(tabID: id)
    }

    static func hostID(currentTabID: UUID?, showsStartPage: Bool, activeSpaceID: UUID) -> UUID? {
        currentTabID ?? (showsStartPage ? activeSpaceID : nil)
    }

    static func peekStays(parent: AnyObject?, hostPage: AnyObject?) -> Bool {
        parent == nil || parent === hostPage
    }

    var archivePreviewRoute: ArchivePreviewRoute? {
        switch self {
        case .webPage: return .fromPage
        case .pagelessTab(let id), .startPage(let id): return .overWindow(hostID: id)
        case .unavailable: return nil
        }
    }
}
