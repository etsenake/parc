import AppKit
import Testing
@testable import Parc

struct FindPresentationTests {
    enum Reply: CaseIterable { case missing, empty, oldQuery, oldDocument, missingDocument, unknownCount, unknownOrdinal, inconsistent }

    @Test(arguments: Reply.allCases)
    func anUnusableReplyLeavesTheCountPending(reply: Reply) {
        let query = reply == .empty ? "" : "find"
        let source = reply == .oldQuery ? "old" : query
        let revision: UInt? = reply == .missingDocument ? nil : reply == .oldDocument ? 2 : 3
        let count: Int? = reply == .missing ? nil : reply == .unknownCount ? -1 : 4
        let ordinal: Int? = reply == .missing ? nil : reply == .unknownOrdinal ? -1 : reply == .inconsistent ? 5 : 2
        #expect(PageFindResultPresentation.resolve(query: query, revision: 3, resultQuery: source,
                                                   resultRevision: revision, matches: count, ordinal: ordinal) == .pending)
    }

    @Test(arguments: [(0, 0, "Not Found"), (4, 2, "2/4"), (4, 0, "0/4")])
    func aCurrentReplyDisplaysItsResult(matches: Int, ordinal: Int, label: String) {
        let result = PageFindResultPresentation.resolve(query: "fi\rnd", revision: 3, resultQuery: "find",
                                                        resultRevision: 3, matches: matches, ordinal: ordinal)
        #expect(result.label == label)
        #expect(result.canAdvance == (matches > 0))
    }

    @Test(arguments: [
        (228.0, 9.0, 1000.0, 918.0, 300.0), (700.0, 45.0, 500.0, 890.0, 300.0), (0.0, 0.0, 250.0, 10.0, 230.0),
    ])
    @MainActor func theFindBarFitsItsOwnPane(x: Double, y: Double, width: Double, left: Double, barWidth: Double) {
        let pane = NSRect(x: x, y: y, width: width, height: 400)
        #expect(PageFindView.frame(in: pane) == NSRect(x: left, y: y + 10, width: barWidth, height: 32))
    }

    enum Result: CaseIterable { case pending, empty, matches }

    @Test(arguments: Result.allCases)
    @MainActor func onlyMatchingResultsShowTheNavigationButtons(result: Result) {
        _ = NSApplication.shared
        let view = PageFindView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        let presentation: PageFindResultPresentation
        switch result {
        case .pending: presentation = .pending
        case .empty: presentation = .notFound
        case .matches: presentation = .matches(ordinal: 2, total: 4)
        }
        view.field.stringValue = "find"
        view.update(result: presentation, available: true)
        #expect(view.field.stringValue == "find")
        #expect(view.previous.isHidden == (result != .matches))
        #expect(view.next.isAccessibilityHidden() == (result != .matches))
        #expect(view.resultLabel.isHidden == (result == .pending))
        #expect(view.resultLabel.stringValue == presentation.label)
    }

    @Test(arguments: [false, true])
    @MainActor func anUnavailableFindOwnerCannotAdvance(available: Bool) {
        _ = NSApplication.shared
        let view = PageFindView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        var requests = 0
        view.onNext = { requests += 1 }
        view.update(result: .matches(ordinal: 1, total: 7), available: available)
        view.next.performClick(nil)
        #expect(requests == (available ? 1 : 0))
    }

    @Test @MainActor func anUpdatedCountPreservesTheQuerySelection() throws {
        let window = CommandBarTestSupport.borderlessWindow()
        let view = PageFindView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        window.contentView = view
        view.field.stringValue = "find"
        try #require(window.makeFirstResponder(view.field))
        let editor = try #require(view.field.currentEditor() as? NSTextView)
        let selection = NSRange(location: 1, length: 2)
        editor.setSelectedRange(selection)
        view.update(result: .matches(ordinal: 1, total: 7), available: true)
        #expect(editor.selectedRange() == selection)
    }

    @Test(arguments: [false, true])
    @MainActor func escapeLeavesMarkedTextWithTheNativeEditor(composing: Bool) throws {
        let window = CommandBarTestSupport.borderlessWindow()
        let view = PageFindView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        window.contentView = view
        var closes = 0
        view.onClose = { closes += 1 }
        try #require(window.makeFirstResponder(view.field))
        let editor = try #require(view.field.currentEditor() as? NSTextView)
        if composing {
            editor.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        view.cancelOperation(nil)
        #expect(editor.hasMarkedText() == composing)
        #expect(closes == (composing ? 0 : 1))
    }
}
