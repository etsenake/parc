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
        let board = TabNoteVisit.Entry(url: "parc://easel/0F7E0B6C-4C5B-4E62-9C4B-6B1E2C2A0D11", title: "Board")
        let guide = TabNoteVisit.Entry(url: "parc://note/file/Notes/Guide.md", title: "Guide")
        let top = TabNoteVisit(page: page, documents: [note, board, guide], position: 2)
        let middle = TabNoteVisit(page: page, documents: [note, board, guide], position: 1)
        let below = TabNoteVisit(page: page, documents: [note, board, guide], position: nil)
        precondition(HistorySwipeNoteStep.steps(toward: .back, visit: top, pageEntries: 1)
            == [.note(board), .note(note), .pageUnderNote(page), .page(distance: 1)])
        precondition(HistorySwipeNoteStep.entries(toward: .forward, visit: top, pageEntries: 3) == 0)
        precondition(HistorySwipeNoteStep.steps(toward: .back, visit: middle, pageEntries: 0) == [.note(note), .pageUnderNote(page)])
        precondition(HistorySwipeNoteStep.steps(toward: .forward, visit: middle, pageEntries: 2) == [.note(guide)])
        precondition(HistorySwipeNoteStep.steps(toward: .forward, visit: below, pageEntries: 1)
            == [.note(note), .note(board), .note(guide), .page(distance: 1)])
        precondition(HistorySwipeNoteStep.step(toward: .back, distance: 2, visit: top, pageEntries: 0) == .note(note))
        precondition(HistorySwipeNoteStep.step(toward: .back, distance: 3, visit: top, pageEntries: 0) == .pageUnderNote(page))
        precondition(HistorySwipeNoteStep.step(toward: .forward, distance: 4, visit: below, pageEntries: 2) == .page(distance: 1))
        precondition(HistorySwipeNoteStep.visitOffset(toward: .back, distance: 3) == -3)
        precondition(HistorySwipeNoteStep.visitOffset(toward: .forward, distance: 2) == 2)
        var swiped = top
        precondition(swiped.move(by: HistorySwipeNoteStep.visitOffset(toward: .back, distance: 2)) && swiped.shown == note)
        precondition(swiped.move(by: HistorySwipeNoteStep.visitOffset(toward: .back, distance: 1)) && swiped.shown == page)
        precondition(!swiped.move(by: -1))
        print("HistorySwipeNoteStepTests passed")
    }
}
