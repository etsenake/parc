import Foundation

@main
struct HistorySwipeNoteStepTests {
    static func main() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let under = TabNoteVisit.Step.page(.init(id: "", url: page.url, title: page.title))
        let showing = TabNoteVisit(page: page, note: note, showsNote: true)
        let ahead = TabNoteVisit(page: page, note: note, showsNote: false)

        precondition(HistorySwipeNoteStep.entries(toward: .back, visit: nil, pageEntries: 3) == 3)
        precondition(HistorySwipeNoteStep.entries(toward: .forward, visit: nil, pageEntries: 2) == 2)
        precondition(HistorySwipeNoteStep.entries(toward: .back, visit: showing, pageEntries: 0) == 1)
        precondition(HistorySwipeNoteStep.entries(toward: .forward, visit: showing, pageEntries: 4) == 0)
        precondition(HistorySwipeNoteStep.entries(toward: .forward, visit: ahead, pageEntries: 0) == 1)
        precondition(HistorySwipeNoteStep.entries(toward: .back, visit: ahead, pageEntries: 2) == 2)

        precondition(HistorySwipeNoteStep.steps(toward: .back, visit: showing, pageEntries: 0) == [.visit(under)])
        precondition(HistorySwipeNoteStep.steps(toward: .forward, visit: ahead, pageEntries: 1)
            == [.visit(.document(note)), .page(distance: 1)], "an older engine's page entries follow the documents ahead")
        precondition(HistorySwipeNoteStep.steps(toward: .forward, visit: showing, pageEntries: 1).isEmpty)
        precondition(HistorySwipeNoteStep.steps(toward: .back, visit: ahead, pageEntries: 1) == [.page(distance: 1)])
        precondition(HistorySwipeNoteStep.steps(toward: .back, visit: nil, pageEntries: -1).isEmpty)
        precondition(HistorySwipeNoteStep.step(toward: .forward, distance: 1, visit: ahead, pageEntries: 2) == .visit(.document(note)))
        precondition(HistorySwipeNoteStep.step(toward: .forward, distance: 3, visit: ahead, pageEntries: 2) == .page(distance: 2))
        precondition(HistorySwipeNoteStep.step(toward: .back, distance: 1, visit: showing, pageEntries: 0) == .visit(under))
        precondition(HistorySwipeNoteStep.step(toward: .back, distance: 2, visit: showing, pageEntries: 0) == nil)
        precondition(HistorySwipeNoteStep.step(toward: .forward, distance: 0, visit: ahead, pageEntries: 2) == nil)

        let a = TabNoteVisit.PageEntry(id: "a", url: "https://example.com/a", title: "A")
        let b = TabNoteVisit.PageEntry(id: "b", url: "https://example.com/b", title: "B")
        let c = TabNoteVisit.PageEntry(id: "c", url: "https://example.com/c", title: "C")
        let board = TabNoteVisit.Entry(url: "parc://easel/0F7E0B6C-4C5B-4E62-9C4B-6B1E2C2A0D11", title: "Board")
        let guide = TabNoteVisit.Entry(url: "parc://note/file/Notes/Guide.md", title: "Guide")
        var visit = TabNoteVisit.page(a.url, title: a.title, history: .init(entries: [a], current: 0))
        visit.push(note); visit.push(board)
        precondition(visit.leave())
        precondition(visit.sync(.init(entries: [a, b], current: 1)))
        visit.push(guide)
        precondition(visit.leave())
        precondition(visit.sync(.init(entries: [a, b, c], current: 2)))
        let interleaved: [TabNoteVisit.Step] = [.page(a), .document(note), .document(board), .page(b), .document(guide), .page(c)]
        precondition(visit.steps == interleaved && visit.shownPage == c, "web A → note → Easel → web B → note → web C")
        precondition(HistorySwipeNoteStep.steps(toward: .back, visit: visit, pageEntries: 2)
            == interleaved.dropLast().reversed().map(HistorySwipeNoteStep.visit),
            "a swipe on the page walks every step behind it, documents and pages alike")
        precondition(HistorySwipeNoteStep.entries(toward: .forward, visit: visit, pageEntries: 0) == 0)
        precondition(HistorySwipeNoteStep.step(toward: .back, distance: 3, visit: visit, pageEntries: 0) == .visit(.document(board)))
        var middle = visit
        precondition(middle.move(by: HistorySwipeNoteStep.visitOffset(toward: .back, distance: 3)) && middle.current == board)
        precondition(HistorySwipeNoteStep.steps(toward: .forward, visit: middle, pageEntries: 0)
            == [.visit(.page(b)), .visit(.document(guide)), .visit(.page(c))])
        precondition(middle.anchor(afterMovingBy: 1) == b && middle.anchor(afterMovingBy: -2) == a)
        var landed = middle
        precondition(landed.move(by: -2) && landed.shownPage == a && landed.step(-1) == nil)
        precondition(HistorySwipeNoteStep.entries(toward: .back, visit: landed, pageEntries: 0) == 0,
                     "nothing behind the first page leaves the swipe to the page's own history")
        precondition(HistorySwipeNoteStep.visitOffset(toward: .back, distance: 3) == -3)
        precondition(HistorySwipeNoteStep.visitOffset(toward: .forward, distance: 2) == 2)
        print("HistorySwipeNoteStepTests passed")
    }
}
