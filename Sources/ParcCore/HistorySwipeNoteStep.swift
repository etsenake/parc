import Foundation

enum HistorySwipeNoteStep: Equatable {
    case note(TabNoteVisit.Entry)
    case pageUnderNote(TabNoteVisit.Entry)
    case page(distance: Int)

    static func entries(toward direction: HistorySwipeDirection, visit: TabNoteVisit?, pageEntries: Int) -> Int {
        guard let visit else { return pageEntries }
        switch direction {
        case .back: return visit.showsNote ? 1 + pageEntries : pageEntries
        case .forward: return visit.showsNote ? 0 : 1 + pageEntries
        }
    }

    static func steps(toward direction: HistorySwipeDirection, visit: TabNoteVisit?, pageEntries: Int) -> [HistorySwipeNoteStep] {
        let pages = (0..<max(0, pageEntries)).map { HistorySwipeNoteStep.page(distance: $0 + 1) }
        guard let visit else { return pages }
        switch direction {
        case .back: return visit.showsNote ? [.pageUnderNote(visit.page)] + pages : pages
        case .forward: return visit.showsNote ? [] : [.note(visit.note)] + pages
        }
    }

    static func step(toward direction: HistorySwipeDirection, distance: Int, visit: TabNoteVisit?,
                     pageEntries: Int) -> HistorySwipeNoteStep? {
        let all = steps(toward: direction, visit: visit, pageEntries: pageEntries)
        return all.indices.contains(distance - 1) ? all[distance - 1] : nil
    }
}
