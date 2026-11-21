import Foundation

package enum HistorySwipeNoteStep: Equatable {
    case visit(TabNoteVisit.Step)
    case page(distance: Int)

    package static func entries(toward direction: HistorySwipeDirection, visit: TabNoteVisit?, pageEntries: Int) -> Int {
        steps(toward: direction, visit: visit, pageEntries: pageEntries).count
    }

    package static func steps(toward direction: HistorySwipeDirection, visit: TabNoteVisit?, pageEntries: Int) -> [HistorySwipeNoteStep] {
        let pages = (0..<max(0, pageEntries)).map { HistorySwipeNoteStep.page(distance: $0 + 1) }
        guard let visit, visit.hasDocument(towardBack: direction == .back) else { return pages }
        let steps = (direction == .back ? visit.behind : visit.ahead).map(HistorySwipeNoteStep.visit)
        return visit.tracksPageHistory || visit.showsNote || direction == .back ? steps : steps + pages
    }

    package static func step(toward direction: HistorySwipeDirection, distance: Int, visit: TabNoteVisit?,
                     pageEntries: Int) -> HistorySwipeNoteStep? {
        let all = steps(toward: direction, visit: visit, pageEntries: pageEntries)
        return all.indices.contains(distance - 1) ? all[distance - 1] : nil
    }

    package static func visitOffset(toward direction: HistorySwipeDirection, distance: Int) -> Int {
        direction == .back ? -distance : distance
    }
}
