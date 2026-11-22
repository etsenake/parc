import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeNoteStepInterleavingTests {
    private struct History {
        let visit: TabNoteVisit
        let a: TabNoteVisit.PageEntry
        let b: TabNoteVisit.PageEntry
        let c: TabNoteVisit.PageEntry
        let board: TabNoteVisit.Entry
        let guide: TabNoteVisit.Entry
        let steps: [TabNoteVisit.Step]
    }

    private func history() -> History {
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let a = TabNoteVisit.PageEntry(id: "a", url: "https://example.com/a", title: "A")
        let b = TabNoteVisit.PageEntry(id: "b", url: "https://example.com/b", title: "B")
        let c = TabNoteVisit.PageEntry(id: "c", url: "https://example.com/c", title: "C")
        let board = TabNoteVisit.Entry(url: "parc://easel/0F7E0B6C-4C5B-4E62-9C4B-6B1E2C2A0D11", title: "Board")
        let guide = TabNoteVisit.Entry(url: "parc://note/file/Notes/Guide.md", title: "Guide")
        var visit = TabNoteVisit.page(a.url, title: a.title, history: .init(entries: [a], current: 0))
        visit.push(note); visit.push(board)
        _ = visit.leave()
        _ = visit.sync(.init(entries: [a, b], current: 1))
        visit.push(guide)
        _ = visit.leave()
        _ = visit.sync(.init(entries: [a, b, c], current: 2))
        let interleaved: [TabNoteVisit.Step] = [.page(a), .document(note), .document(board), .page(b), .document(guide), .page(c)]
        return History(visit: visit, a: a, b: b, c: c, board: board, guide: guide, steps: interleaved)
    }

    private func showingBoard(_ history: History) -> TabNoteVisit {
        var visit = history.visit
        _ = visit.move(by: HistorySwipeNoteStep.visitOffset(toward: .back, distance: 3))
        return visit
    }

    @Test func leavingTheBoardAndCommittingThePageAddsThePageToHistory() {
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let a = TabNoteVisit.PageEntry(id: "a", url: "https://example.com/a", title: "A")
        let b = TabNoteVisit.PageEntry(id: "b", url: "https://example.com/b", title: "B")
        let board = TabNoteVisit.Entry(url: "parc://easel/0F7E0B6C-4C5B-4E62-9C4B-6B1E2C2A0D11", title: "Board")
        var visit = TabNoteVisit.page(a.url, title: a.title, history: .init(entries: [a], current: 0))
        visit.push(note); visit.push(board)
        let leftDocument = visit.leave()
        #expect(leftDocument)
        let syncedHistory = visit.sync(.init(entries: [a, b], current: 1))
        #expect(syncedHistory)
    }

    @Test func leavingTheSecondNoteAndCommittingThePageAddsThePageToHistory() {
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let a = TabNoteVisit.PageEntry(id: "a", url: "https://example.com/a", title: "A")
        let b = TabNoteVisit.PageEntry(id: "b", url: "https://example.com/b", title: "B")
        let c = TabNoteVisit.PageEntry(id: "c", url: "https://example.com/c", title: "C")
        let board = TabNoteVisit.Entry(url: "parc://easel/0F7E0B6C-4C5B-4E62-9C4B-6B1E2C2A0D11", title: "Board")
        let guide = TabNoteVisit.Entry(url: "parc://note/file/Notes/Guide.md", title: "Guide")
        var visit = TabNoteVisit.page(a.url, title: a.title, history: .init(entries: [a], current: 0))
        visit.push(note); visit.push(board)
        _ = visit.leave()
        _ = visit.sync(.init(entries: [a, b], current: 1))
        visit.push(guide)
        let leftDocument = visit.leave()
        #expect(leftDocument)
        let syncedHistory = visit.sync(.init(entries: [a, b, c], current: 2))
        #expect(syncedHistory)
    }

    @Test func historyRecordsInterleavedPagesAndDocumentsInOrder() {
        let history = history()
        #expect(history.visit.steps == history.steps && history.visit.shownPage == history.c, "web A → note → Easel → web B → note → web C")
    }

    @Test func backListsInterleavedStepsInReverse() {
        let history = history()
        #expect(HistorySwipeNoteStep.steps(toward: .back, visit: history.visit, pageEntries: 2)
            == history.steps.dropLast().reversed().map(HistorySwipeNoteStep.visit), "a swipe on the page walks every step behind it, documents and pages alike")
    }

    @Test func theLastInterleavedPageHasNoForwardEntries() {
        let history = history()
        #expect(HistorySwipeNoteStep.entries(toward: .forward, visit: history.visit, pageEntries: 0) == 0)
    }

    @Test func backCanSelectAnEarlierInterleavedDocument() {
        let history = history()
        #expect(HistorySwipeNoteStep.step(toward: .back, distance: 3, visit: history.visit, pageEntries: 0) == .visit(.document(history.board)))
    }

    @Test func aSwipeOffsetMovesTheVisitToTheSelectedDocument() {
        let history = history()
        var middle = history.visit
        #expect(middle.move(by: HistorySwipeNoteStep.visitOffset(toward: .back, distance: 3)) && middle.current == history.board)
    }

    @Test func forwardFromTheBoardListsTheLaterPagesAndDocuments() {
        let history = history()
        let middle = showingBoard(history)
        #expect(HistorySwipeNoteStep.steps(toward: .forward, visit: middle, pageEntries: 0)
            == [.visit(.page(history.b)), .visit(.document(history.guide)), .visit(.page(history.c))])
    }

    @Test func anInterleavedStepResolvesThePageItWasOpenedOver() {
        let history = history()
        let middle = showingBoard(history)
        #expect(middle.anchor(afterMovingBy: 1) == history.b && middle.anchor(afterMovingBy: -2) == history.a)
    }

    @Test func aBackJumpToTheFirstPageLeavesNoEarlierStep() {
        let history = history()
        var landed = showingBoard(history)
        #expect(landed.move(by: -2) && landed.shownPage == history.a && landed.step(-1) == nil)
    }

    @Test func theFirstPageLeavesBackToItsOwnHistory() {
        let history = history()
        var landed = showingBoard(history)
        _ = landed.move(by: -2)
        #expect(HistorySwipeNoteStep.entries(toward: .back, visit: landed, pageEntries: 0) == 0, "nothing behind the first page leaves the swipe to the page's own history")
    }
}
