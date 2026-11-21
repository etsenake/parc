import AppKit
import Testing
@testable import Parc

@MainActor private final class FocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor private final class KeyWindow: NSWindow {
    var reportsKey = true
    override var isKeyWindow: Bool { reportsKey }
}

@MainActor private final class Scene {
    let window = KeyWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 300),
                           styleMask: [.borderless], backing: .buffered, defer: false)
    let root: NSView
    let content: NSView
    let sidebar = FocusView(), page = FocusView(), parked = NSView(), parkedPage = FocusView(), next = FocusView()

    init() {
        _ = NSApplication.shared
        window.isReleasedWhenClosed = false
        root = NSView(frame: window.contentLayoutRect)
        window.contentView = root
        content = NSView(frame: root.bounds)
        root.addSubview(content)
        root.addSubview(sidebar)
        root.addSubview(parked)
        content.addSubview(page)
        content.addSubview(next)
        parked.addSubview(parkedPage)
    }

    func request(attempts: @escaping () -> ContentFocusRequest.Outcome) -> ContentFocusRequest {
        ContentFocusRequest(window: window, content: content, attempt: attempts)
    }
}

struct ContentFocusRequestTests {
    @MainActor @Test func nothingHoldingFocusCountsAsContentFocus() {
        let s = Scene()
        #expect(ContentFocusRequest.holdsContentFocus(nil, window: s.window, content: s.content))
    }

    @MainActor @Test func theWindowHoldingFocusCountsAsContentFocus() {
        let s = Scene()
        #expect(ContentFocusRequest.holdsContentFocus(s.window, window: s.window, content: s.content))
    }

    @MainActor @Test func contentHoldingFocusCounts() {
        let s = Scene()
        #expect(ContentFocusRequest.holdsContentFocus(s.page, window: s.window, content: s.content))
    }

    @MainActor @Test func theSidebarKeepsFocus() {
        let s = Scene()
        #expect(!ContentFocusRequest.holdsContentFocus(s.sidebar, window: s.window, content: s.content))
    }

    @MainActor @Test func aParkedPageGaveFocusUp() {
        let s = Scene()
        s.parked.isHidden = true
        #expect(ContentFocusRequest.holdsContentFocus(s.parkedPage, window: s.window, content: s.content))
    }

    @MainActor @Test func aNonViewResponderKeepsFocus() {
        let s = Scene()
        #expect(!ContentFocusRequest.holdsContentFocus(NSResponder(), window: s.window, content: s.content))
    }

    @MainActor @Test func noResponderWasLost() {
        let s = Scene()
        #expect(ContentFocusRequest.lostByPresentation(nil, window: s.window))
    }

    @MainActor @Test func theWindowHoldingFocusWasLost() {
        let s = Scene()
        #expect(ContentFocusRequest.lostByPresentation(s.window, window: s.window))
    }

    @MainActor @Test func aParkedPanesFocusWasLost() {
        let s = Scene()
        s.parked.isHidden = true
        #expect(ContentFocusRequest.lostByPresentation(s.parkedPage, window: s.window))
    }

    @MainActor @Test func aDisplayedPaneKeepsItsFocus() {
        let s = Scene()
        #expect(!ContentFocusRequest.lostByPresentation(s.page, window: s.window))
    }

    @MainActor @Test func theSidebarKeepsItsFocusAcrossPresentation() {
        let s = Scene()
        #expect(!ContentFocusRequest.lostByPresentation(s.sidebar, window: s.window))
    }

    @MainActor @Test func aNonViewResponderKeepsFocusAcrossPresentation() {
        let s = Scene()
        #expect(!ContentFocusRequest.lostByPresentation(NSResponder(), window: s.window))
    }

    @MainActor @Test func aViewThatLeftTheWindowLostFocus() {
        let s = Scene()
        #expect(ContentFocusRequest.lostByPresentation(FocusView(), window: s.window))
    }

    @MainActor @Test func readyContentTakesFocusOnce() {
        let s = Scene()
        _ = s.window.makeFirstResponder(s.page)
        var attempts = 0
        let request = s.request { attempts += 1; _ = s.window.makeFirstResponder(s.next); return .focused }
        request.start()
        request.step()
        #expect(attempts == 1)
        #expect(s.window.firstResponder === s.next)
    }

    @MainActor @Test func theFirstAttemptWaits() {
        let s = Scene()
        _ = s.window.makeFirstResponder(s.page)
        var attempts = 0
        let request = s.request { attempts += 1; return .waiting }
        request.start()
        #expect(attempts == 1)
        #expect(s.window.firstResponder === s.page)
    }

    @MainActor @Test func aRetryTakesFocusOnceContentIsReady() {
        let s = Scene()
        _ = s.window.makeFirstResponder(s.page)
        var ready = false
        let request = s.request {
            guard ready else { return .waiting }
            _ = s.window.makeFirstResponder(s.next)
            return .focused
        }
        request.start()
        ready = true
        #expect(request.step() == .focused)
        #expect(s.window.firstResponder === s.next)
    }

    @MainActor @Test func aFocusedRequestStopsRetrying() {
        let s = Scene()
        _ = s.window.makeFirstResponder(s.page)
        var attempts = 0
        let request = s.request { attempts += 1; return .focused }
        request.start()
        request.step()
        request.step()
        #expect(attempts == 1)
    }

    @MainActor @Test func aSidebarControlThatTookFocusKeepsIt() {
        let s = Scene()
        _ = s.window.makeFirstResponder(s.page)
        var attempts = 0
        let request = s.request { attempts += 1; return .waiting }
        request.start()
        _ = s.window.makeFirstResponder(s.sidebar)
        request.step()
        #expect(attempts == 1)
        #expect(s.window.firstResponder === s.sidebar)
    }

    @MainActor @Test func aCancelledRequestNeverRetries() {
        let s = Scene()
        _ = s.window.makeFirstResponder(s.page)
        var attempts = 0
        let request = s.request { attempts += 1; return .waiting }
        request.start()
        request.cancel()
        request.step()
        #expect(attempts == 1)
    }

    @MainActor @Test func aWindowThatIsNotKeyIsNeverFocused() {
        let s = Scene()
        _ = s.window.makeFirstResponder(s.page)
        s.window.reportsKey = false
        var attempts = 0
        s.request { attempts += 1; return .focused }.start()
        #expect(attempts == 0)
    }

    @MainActor @Test func theSidebarsFocusIsNeverTaken() {
        let s = Scene()
        _ = s.window.makeFirstResponder(s.sidebar)
        var attempts = 0
        s.request { attempts += 1; return .focused }.start()
        #expect(attempts == 0)
        #expect(s.window.firstResponder === s.sidebar)
    }

    @MainActor @Test func aStaleSelectionChangesNothing() {
        let s = Scene()
        _ = s.window.makeFirstResponder(s.page)
        var attempts = 0
        s.request { attempts += 1; return .cancelled }.start()
        #expect(attempts == 1)
        #expect(s.window.firstResponder === s.page)
    }

    @MainActor @Test func aBlankTabLeavesFocusWithTheWindowOnce() {
        let s = Scene()
        s.parked.isHidden = true
        _ = s.window.makeFirstResponder(s.parkedPage)
        var attempts = 0
        let request = s.request { attempts += 1; _ = s.window.makeFirstResponder(nil); return .focused }
        request.start()
        request.step()
        #expect(attempts == 1)
        #expect(s.window.firstResponder === s.window)
    }

    @MainActor private struct Saved {
        let s = Scene()
        let findHost = NSView(), findField = FocusView(), pageCaret = FocusView()

        init() {
            s.root.addSubview(findHost)
            findHost.addSubview(findField)
            s.page.addSubview(pageCaret)
        }
    }

    @MainActor @Test func theContentsOwnResponderReturns() {
        let v = Saved()
        #expect(ContentFocusRequest.returnsToSaved(v.s.page, find: nil, content: v.s.content))
    }

    @MainActor @Test func aCaretInsideTheContentReturns() {
        let v = Saved()
        #expect(ContentFocusRequest.returnsToSaved(v.pageCaret, find: nil, content: v.s.content))
    }

    @MainActor @Test func aSidebarControlGivesWayToTheContent() {
        let v = Saved()
        #expect(!ContentFocusRequest.returnsToSaved(v.s.sidebar, find: nil, content: v.s.content))
    }

    @MainActor @Test func aParkedPaneGivesWay() {
        let v = Saved()
        #expect(!ContentFocusRequest.returnsToSaved(v.s.parkedPage, find: nil, content: v.s.content))
    }

    @MainActor @Test func theOpenFindKeepsItsField() {
        let v = Saved()
        #expect(ContentFocusRequest.returnsToSaved(v.findField, find: v.findHost, content: v.s.content))
    }

    @MainActor @Test func anOpenFindTakesFocusFromThePage() {
        let v = Saved()
        #expect(!ContentFocusRequest.returnsToSaved(v.s.page, find: v.findHost, content: v.s.content))
    }

    @MainActor @Test func withNoContentTheOwnerDecides() {
        let v = Saved()
        #expect(!ContentFocusRequest.returnsToSaved(v.s.page, find: nil, content: nil))
    }
}
