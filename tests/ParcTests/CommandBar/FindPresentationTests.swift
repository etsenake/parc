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
        view.next.sendClick()
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

extension FindPresentationTests {
    @MainActor private final class HoverWindow: NSWindow {
        var key = true
        var pointer = NSPoint(x: 33, y: 33)
        override var isKeyWindow: Bool { key }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    @MainActor private struct HoverFixture {
        let window: HoverWindow
        let surface: NSView
        let control = PageFindButton(frame: NSRect(x: 20, y: 20, width: 26, height: 26))

        init() {
            _ = NSApplication.shared
            let frame = NSRect(x: 0, y: 0, width: 400, height: 100)
            window = HoverWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            surface = NSView(frame: frame)
            window.contentView = surface
            surface.addSubview(control)
        }

        func movePointer() throws {
            let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: window.pointer,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0))
            control.mouseMoved(with: event)
        }
    }

    enum HoverLoss: CaseIterable { case overlappingView, otherKeyWindow, resigned, outside, hidden, detached }

    @Test(arguments: HoverLoss.allCases)
    @MainActor func theFindControlClearsHoverWhenThePointerLosesItsOwner(reason: HoverLoss) throws {
        let fixture = HoverFixture()
        try fixture.movePointer()
        try #require(fixture.control.isHovered)
        switch reason {
        case .overlappingView:
            fixture.surface.addSubview(NSView(frame: fixture.control.frame), positioned: .above, relativeTo: fixture.control)
            try fixture.movePointer()
        case .otherKeyWindow: fixture.window.key = false; try fixture.movePointer()
        case .resigned: NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        case .outside: fixture.window.pointer = NSPoint(x: 100, y: 80); try fixture.movePointer()
        case .hidden: fixture.control.isHidden = true
        case .detached: fixture.control.removeFromSuperview()
        }
        #expect(!fixture.control.isHovered)
    }

    @Test(arguments: [(false, 0.071), (true, 0.077)])
    @MainActor func theHoverDecorationUsesTheWindowAppearance(dark: Bool, alpha: Double) throws {
        let fixture = HoverFixture()
        fixture.control.appearance = dark ? CommandBarTestSupport.dark : CommandBarTestSupport.light
        try fixture.movePointer()
        fixture.control.updateLayer()
        let fill = try #require(fixture.control.layer?.backgroundColor)
        #expect(abs(fill.alpha - alpha) < 0.00001)
        fixture.control.isEnabled = false
        fixture.control.updateLayer()
        #expect(fixture.control.layer?.backgroundColor?.alpha == 0)
    }

    @Test @MainActor func trackingUpdatesDoNotStackFindHoverAreas() {
        let fixture = HoverFixture()
        fixture.control.updateTrackingAreas()
        fixture.control.updateTrackingAreas()
        let areas = fixture.control.trackingAreas.filter { !$0.options.contains(.cursorUpdate) }
        #expect(areas.count == 1)
        #expect(areas.first?.options.contains([.mouseMoved, .activeInKeyWindow, .inVisibleRect]) == true)
    }

    @Test @MainActor func aHiddenNextButtonReturnsFocusToTheQuery() throws {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: 300, height: 32)
        let window = HoverWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = PageFindView(frame: frame)
        window.contentView = view
        view.update(result: .matches(ordinal: 1, total: 7), available: true)
        try #require(window.makeFirstResponder(view.next))
        try #require(window.firstResponder === view.next)
        view.update(result: .notFound, available: true)
        #expect(view.field.currentEditor() === window.firstResponder)
    }
}
