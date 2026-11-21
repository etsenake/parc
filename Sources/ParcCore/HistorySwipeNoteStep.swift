import Foundation

enum HistorySwipeNoteStep: Equatable {
    case note(TabNoteVisit.Entry)
    case pageUnderNote(TabNoteVisit.Entry)
    case page(distance: Int)

    static func entries(toward direction: HistorySwipeDirection, visit: TabNoteVisit?, pageEntries: Int) -> Int {
        steps(toward: direction, visit: visit, pageEntries: pageEntries).count
    }

    static func steps(toward direction: HistorySwipeDirection, visit: TabNoteVisit?, pageEntries: Int) -> [HistorySwipeNoteStep] {
        let pages = (0..<max(0, pageEntries)).map { HistorySwipeNoteStep.page(distance: $0 + 1) }
        guard let visit else { return pages }
        switch direction {
        case .back:
            guard visit.showsNote else { return pages }
            return visit.behind.dropLast().map(HistorySwipeNoteStep.note) + [.pageUnderNote(visit.page)] + pages
        case .forward:
            return visit.ahead.map(HistorySwipeNoteStep.note) + (visit.showsNote ? [] : pages)
        }
    }

    static func step(toward direction: HistorySwipeDirection, distance: Int, visit: TabNoteVisit?,
                     pageEntries: Int) -> HistorySwipeNoteStep? {
        let all = steps(toward: direction, visit: visit, pageEntries: pageEntries)
        return all.indices.contains(distance - 1) ? all[distance - 1] : nil
    }

    static func visitOffset(toward direction: HistorySwipeDirection, distance: Int) -> Int {
        direction == .back ? -distance : distance
    }
}
