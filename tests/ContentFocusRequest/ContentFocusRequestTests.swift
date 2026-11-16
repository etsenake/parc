import AppKit

@MainActor private final class FocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor private final class KeyWindow: NSWindow {
    var reportsKey = true
    override var isKeyWindow: Bool { reportsKey }
}

@main struct ContentFocusRequestTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let window = KeyWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 300),
                               styleMask: [.titled], backing: .buffered, defer: false)
        let root = NSView(frame: window.contentLayoutRect)
        window.contentView = root
        let content = NSView(frame: root.bounds), sidebar = FocusView(), page = FocusView(), parked = NSView()
        let parkedPage = FocusView(), next = FocusView()
        root.addSubview(content); root.addSubview(sidebar); root.addSubview(parked)
        content.addSubview(page); content.addSubview(next); parked.addSubview(parkedPage)

        expect(ContentFocusRequest.holdsContentFocus(nil, window: window, content: content), "nothing holds focus")
        expect(ContentFocusRequest.holdsContentFocus(window, window: window, content: content), "the window holds focus")
        expect(ContentFocusRequest.holdsContentFocus(page, window: window, content: content), "content holds focus")
        expect(!ContentFocusRequest.holdsContentFocus(sidebar, window: window, content: content), "the sidebar keeps focus")
        parked.isHidden = true
        expect(ContentFocusRequest.holdsContentFocus(parkedPage, window: window, content: content), "a parked page gave it up")
        expect(!ContentFocusRequest.holdsContentFocus(NSResponder(), window: window, content: content), "a non-view responder keeps it")

        expect(ContentFocusRequest.lostByPresentation(nil, window: window), "no responder was lost")
        expect(ContentFocusRequest.lostByPresentation(window, window: window), "the window holding focus was lost")
        expect(ContentFocusRequest.lostByPresentation(parkedPage, window: window), "a parked pane's focus was lost")
        expect(!ContentFocusRequest.lostByPresentation(page, window: window), "a displayed pane keeps its focus")
        expect(!ContentFocusRequest.lostByPresentation(sidebar, window: window), "the sidebar keeps its focus")
        expect(!ContentFocusRequest.lostByPresentation(NSResponder(), window: window), "a non-view responder keeps focus")
        let detached = FocusView()
        expect(ContentFocusRequest.lostByPresentation(detached, window: window), "a view that left the window lost focus")

        _ = window.makeFirstResponder(page)
        var attempts = 0
        let immediate = ContentFocusRequest(window: window, content: content) {
            attempts += 1; _ = window.makeFirstResponder(next); return .focused
        }
        immediate.start(); spin()
        expect(attempts == 1 && window.firstResponder === next, "ready content takes focus once")

        _ = window.makeFirstResponder(page)
        attempts = 0
        var ready = false
        let waiting = ContentFocusRequest(window: window, content: content) {
            attempts += 1
            guard ready else { return .waiting }
            _ = window.makeFirstResponder(next); return .focused
        }
        waiting.start()
        expect(attempts == 1 && window.firstResponder === page, "the first attempt waits")
        ready = true; spin()
        let settled = attempts
        expect(settled >= 2 && window.firstResponder === next, "an idle run loop retries the waiting request")
        spin()
        expect(attempts == settled, "a focused request stops retrying")

        _ = window.makeFirstResponder(page)
        attempts = 0
        let claimed = ContentFocusRequest(window: window, content: content) { attempts += 1; return .waiting }
        claimed.start()
        _ = window.makeFirstResponder(sidebar); spin()
        expect(attempts == 1 && window.firstResponder === sidebar, "a sidebar control that took focus keeps it")

        _ = window.makeFirstResponder(page)
        attempts = 0
        let cancelled = ContentFocusRequest(window: window, content: content) { attempts += 1; return .waiting }
        cancelled.start(); cancelled.cancel(); spin()
        expect(attempts == 1, "a cancelled request never retries")
        window.reportsKey = false
        let background = ContentFocusRequest(window: window, content: content) { attempts += 1; return .focused }
        background.start(); spin()
        expect(attempts == 1, "a window that is not key is never focused")
        window.reportsKey = true
        _ = window.makeFirstResponder(sidebar)
        let sidebarFocus = ContentFocusRequest(window: window, content: content) { attempts += 1; return .focused }
        sidebarFocus.start(); spin()
        expect(attempts == 1 && window.firstResponder === sidebar, "the sidebar's focus is never taken")

        _ = window.makeFirstResponder(page)
        attempts = 0
        let stale = ContentFocusRequest(window: window, content: content) { attempts += 1; return .cancelled }
        stale.start(); spin()
        expect(attempts == 1 && window.firstResponder === page, "a stale selection changes nothing")

        parked.isHidden = true
        _ = window.makeFirstResponder(parkedPage)
        attempts = 0
        let blank = ContentFocusRequest(window: window, content: content) {
            attempts += 1; window.makeFirstResponder(nil); return .focused
        }
        blank.start(); spin(); spin()
        expect(attempts == 1 && window.firstResponder === window, "a blank tab leaves focus with the window, once")
        parked.isHidden = false
        let findHost = NSView(), findField = FocusView(), pageCaret = FocusView()
        root.addSubview(findHost); findHost.addSubview(findField); page.addSubview(pageCaret)
        expect(ContentFocusRequest.returnsToSaved(page, find: nil, content: content), "the content's own responder returns")
        expect(ContentFocusRequest.returnsToSaved(pageCaret, find: nil, content: content), "a caret inside the content returns")
        expect(!ContentFocusRequest.returnsToSaved(sidebar, find: nil, content: content), "a sidebar control gives way to the content")
        expect(!ContentFocusRequest.returnsToSaved(parkedPage, find: nil, content: content), "a parked pane gives way")
        expect(ContentFocusRequest.returnsToSaved(findField, find: findHost, content: content), "the open Find keeps its field")
        expect(!ContentFocusRequest.returnsToSaved(page, find: findHost, content: content), "an open Find takes focus from the page")
        expect(!ContentFocusRequest.returnsToSaved(page, find: nil, content: nil), "no content: the owner decides")
        print("ContentFocusRequest: \(checks) checks passed")
    }
}
