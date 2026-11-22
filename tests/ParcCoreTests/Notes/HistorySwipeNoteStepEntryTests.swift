import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeNoteStepEntryTests {
    struct EntryCount: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let direction: HistorySwipeDirection
        let showsNote: Bool?
        let pageEntries: Int
        let expected: Int
    }

    private static let entryCounts = [
        EntryCount(testDescription: "page back without a visit", direction: .back, showsNote: nil, pageEntries: 3, expected: 3),
        EntryCount(testDescription: "page forward without a visit", direction: .forward, showsNote: nil, pageEntries: 2, expected: 2),
        EntryCount(testDescription: "back from a shown note", direction: .back, showsNote: true, pageEntries: 0, expected: 1),
        EntryCount(testDescription: "forward from a shown note", direction: .forward, showsNote: true, pageEntries: 4, expected: 0),
        EntryCount(testDescription: "forward with a note ahead", direction: .forward, showsNote: false, pageEntries: 0, expected: 1),
        EntryCount(testDescription: "page back with a note ahead", direction: .back, showsNote: false, pageEntries: 2, expected: 2),
    ]

    @Test(arguments: entryCounts) func swipeCountsCombinePageHistoryWithTheDocumentVisit(_ example: EntryCount) {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let visit = example.showsNote.map { TabNoteVisit(page: page, note: note, showsNote: $0) }
        #expect(HistorySwipeNoteStep.entries(toward: example.direction, visit: visit, pageEntries: example.pageEntries) == example.expected)
    }

    @Test func backFromANoteLeadsToThePageUnderIt() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let under = TabNoteVisit.Step.page(.init(id: "", url: page.url, title: page.title))
        let showing = TabNoteVisit(page: page, note: note, showsNote: true)
        #expect(HistorySwipeNoteStep.steps(toward: .back, visit: showing, pageEntries: 0) == [.visit(under)])
    }

    @Test func forwardListsDocumentsBeforeOlderEnginePageEntries() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let ahead = TabNoteVisit(page: page, note: note, showsNote: false)
        #expect(HistorySwipeNoteStep.steps(toward: .forward, visit: ahead, pageEntries: 1)
            == [.visit(.document(note)), .page(distance: 1)], "an older engine's page entries follow the documents ahead")
    }

    @Test func aShownNoteHasNoForwardSteps() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let showing = TabNoteVisit(page: page, note: note, showsNote: true)
        #expect(HistorySwipeNoteStep.steps(toward: .forward, visit: showing, pageEntries: 1).isEmpty)
    }

    @Test func backWithANoteAheadUsesThePageHistory() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let ahead = TabNoteVisit(page: page, note: note, showsNote: false)
        #expect(HistorySwipeNoteStep.steps(toward: .back, visit: ahead, pageEntries: 1) == [.page(distance: 1)])
    }

    @Test func negativePageHistoryCountsYieldNoSteps() {
        #expect(HistorySwipeNoteStep.steps(toward: .back, visit: nil, pageEntries: -1).isEmpty)
    }

    @Test func theFirstForwardStepCanBeADocument() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let ahead = TabNoteVisit(page: page, note: note, showsNote: false)
        #expect(HistorySwipeNoteStep.step(toward: .forward, distance: 1, visit: ahead, pageEntries: 2) == .visit(.document(note)))
    }

    @Test func aStepPastTheDocumentsUsesItsPageDistance() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let ahead = TabNoteVisit(page: page, note: note, showsNote: false)
        #expect(HistorySwipeNoteStep.step(toward: .forward, distance: 3, visit: ahead, pageEntries: 2) == .page(distance: 2))
    }

    @Test func theFirstBackStepCanBeThePageUnderTheNote() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let under = TabNoteVisit.Step.page(.init(id: "", url: page.url, title: page.title))
        let showing = TabNoteVisit(page: page, note: note, showsNote: true)
        #expect(HistorySwipeNoteStep.step(toward: .back, distance: 1, visit: showing, pageEntries: 0) == .visit(under))
    }

    @Test func aBackStepPastTheAvailableEntriesIsUnavailable() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let showing = TabNoteVisit(page: page, note: note, showsNote: true)
        #expect(HistorySwipeNoteStep.step(toward: .back, distance: 2, visit: showing, pageEntries: 0) == nil)
    }

    @Test func aSwipeDistanceOfZeroHasNoStep() {
        let page = TabNoteVisit.Entry(url: "https://example.com/readme", title: "Readme")
        let note = TabNoteVisit.Entry(url: "parc://note/file/Notes/Plan.md", title: "Plan")
        let ahead = TabNoteVisit(page: page, note: note, showsNote: false)
        #expect(HistorySwipeNoteStep.step(toward: .forward, distance: 0, visit: ahead, pageEntries: 2) == nil)
    }

    @Test func backOffsetsAreNegative() {
        #expect(HistorySwipeNoteStep.visitOffset(toward: .back, distance: 3) == -3)
    }

    @Test func forwardOffsetsArePositive() {
        #expect(HistorySwipeNoteStep.visitOffset(toward: .forward, distance: 2) == 2)
    }
}
