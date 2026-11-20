import Foundation

@main
struct HistorySwipeNoteStepTests {
    static func main() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let showing = TabNoteVisit(page: page, note: note, showsNote: true)
        let ahead = TabNoteVisit(page: page, note: note, showsNote: false)

        precondition(HistorySwipeNoteStep.entries(toward: .back, visit: nil, pageEntries: 3) == 3)
        precondition(HistorySwipeNoteStep.entries(toward: .forward, visit: nil, pageEntries: 2) == 2)
        precondition(HistorySwipeNoteStep.entries(toward: .back, visit: showing, pageEntries: 2) == 3)
        precondition(HistorySwipeNoteStep.entries(toward: .forward, visit: showing, pageEntries: 4) == 0)
        precondition(HistorySwipeNoteStep.entries(toward: .forward, visit: ahead, pageEntries: 0) == 1)
        precondition(HistorySwipeNoteStep.entries(toward: .back, visit: ahead, pageEntries: 2) == 2)

        precondition(HistorySwipeNoteStep.steps(toward: .back, visit: showing, pageEntries: 2)
            == [.pageUnderNote(page), .page(distance: 1), .page(distance: 2)])
        precondition(HistorySwipeNoteStep.steps(toward: .forward, visit: ahead, pageEntries: 1)
            == [.note(note), .page(distance: 1)])
        precondition(HistorySwipeNoteStep.steps(toward: .forward, visit: showing, pageEntries: 1).isEmpty)
        precondition(HistorySwipeNoteStep.steps(toward: .back, visit: ahead, pageEntries: 1) == [.page(distance: 1)])
        precondition(HistorySwipeNoteStep.steps(toward: .back, visit: nil, pageEntries: -1).isEmpty)

        precondition(HistorySwipeNoteStep.step(toward: .forward, distance: 1, visit: ahead, pageEntries: 2) == .note(note))
        precondition(HistorySwipeNoteStep.step(toward: .forward, distance: 3, visit: ahead, pageEntries: 2) == .page(distance: 2))
        precondition(HistorySwipeNoteStep.step(toward: .back, distance: 1, visit: showing, pageEntries: 0) == .pageUnderNote(page))
        precondition(HistorySwipeNoteStep.step(toward: .back, distance: 2, visit: showing, pageEntries: 0) == nil)
        precondition(HistorySwipeNoteStep.step(toward: .forward, distance: 0, visit: ahead, pageEntries: 2) == nil)
        print("HistorySwipeNoteStepTests passed")
    }
}
