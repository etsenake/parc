import AppKit

@MainActor private final class KeyWindow: NSWindow {
    var key = true
    var pointer = NSPoint.zero
    override var isKeyWindow: Bool { key }
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

@main struct FindPresentationTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func result(_ query: String = "find", _ source: String? = "find", _ revision: UInt? = 3,
                    _ count: Int? = nil, _ ordinal: Int? = nil) -> PageFindResultPresentation {
            .resolve(query: query, revision: 3, resultQuery: source, resultRevision: revision, matches: count, ordinal: ordinal)
        }
        check(result() == .pending, "no renderer response is unknown")
        check(result("", "", 3, 0, 0) == .pending, "empty query is not an error")
        check(result("find", "old", 3, 8, 1) == .pending, "old query cannot supply a count")
        check(result("find", "find", 2, 8, 1) == .pending, "old document cannot supply a count")
        check(result("find", "find", nil, 8, 1) == .pending, "missing document is unavailable")
        check(result("find", "find", 3, -1, 0) == .pending, "native unknown count stays unknown")
        check(result("find", "find", 3, 4, -1) == .pending, "native unknown ordinal stays unknown")
        check(result("find", "find", 3, 0, 0) == .notFound, "genuine zero result")
        check(result("find", "find", 3, 4, 2) == .matches(ordinal: 2, total: 4), "actual count and ordinal")
        check(result("find", "find", 3, 4, 0) == .matches(ordinal: 0, total: 4), "counts-only reply has no active match")
        check(result("find", "find", 3, 4, 5) == .pending, "inconsistent interim snapshot")
        check(result("fi\rnd", "find", 3, 4, 2) == .matches(ordinal: 2, total: 4), "native carriage-return normalization")
        check(PageFindResultPresentation.notFound.label == "Not Found", "original error wording")
        check(PageFindResultPresentation.matches(ordinal: 2, total: 4).label == "2/4", "original slash counter")
        check(!PageFindResultPresentation.pending.canAdvance && !PageFindResultPresentation.notFound.canAdvance, "unknown and zero do not expose navigation")
        let page = NSRect(x: 228, y: 9, width: 1000, height: 700)
        let placement = PageFindView.frame(in: page)
        check(placement == NSRect(x: 918, y: 19, width: 300, height: 32), "exact ordinary page overlay")
        check(page == NSRect(x: 228, y: 9, width: 1000, height: 700), "no content geometry mutation")
        let split = PageFindView.frame(in: NSRect(x: 700, y: 45, width: 500, height: 400))
        check(split == NSRect(x: 890, y: 55, width: 300, height: 32), "actual selected split/toolbar origin")
        let narrow = PageFindView.frame(in: NSRect(x: 0, y: 0, width: 250, height: 80))
        check(narrow.width == 230 && narrow.maxX == 240, "narrow pane containment")
        let view = PageFindView(frame: placement)
        view.appearance = NSAppearance(named: .darkAqua)
        view.layoutSubtreeIfNeeded()
        check(view.field.font?.pointSize == 13, "original field font")
        check(view.resultLabel.font?.pointSize == 12, "original counter font")
        check(view.layer?.cornerRadius == 5, "original radius")
        check(view.shadow?.shadowBlurRadius == 5 && view.shadow?.shadowOffset == NSSize(width: 0, height: -3), "original shadow metrics")
        check(view.previous.isHidden && view.next.isHidden && view.resultLabel.isHidden, "empty original panel")
        check(view.field.nextKeyView == nil, "no custom focus trap replaces AppKit traversal")
        check(view.field.accessibilityLabel() == "Find in page", "named native editor")
        check(view.close.accessibilityLabel() == "Close Find", "named close control")
        var previous = 0, next = 0, close = 0
        view.onPrevious = { previous += 1 }; view.onNext = { next += 1 }; view.onClose = { close += 1 }
        view.field.stringValue = "find"
        view.update(result: .matches(ordinal: 2, total: 4), available: true)
        view.layoutSubtreeIfNeeded()
        check(view.field.stringValue == "find", "reply does not replace query")
        check(view.resultLabel.stringValue == "2/4" && !view.previous.isHidden && !view.next.isHidden, "matched result controls")
        check(view.resultLabel.accessibilityValue() == "2/4", "matched count is the AX value")
        check(!view.previous.isAccessibilityHidden() && !view.next.isAccessibilityHidden(), "match controls stay in the AX tree")
        view.previous.performClick(nil); view.next.performClick(nil)
        check(previous == 1 && next == 1, "native control dispatch")
        view.update(result: .matches(ordinal: 3, total: 4), available: false)
        view.previous.performClick(nil); view.next.performClick(nil); view.close.performClick(nil)
        check(previous == 1 && next == 1 && close == 0, "unavailable native buttons cannot dispatch")
        view.update(result: .notFound, available: true); view.layoutSubtreeIfNeeded()
        check(view.resultLabel.stringValue == "Not Found" && view.previous.isHidden && view.next.isHidden, "zero result replaces navigation")
        check(view.resultLabel.accessibilityValue() == "Not Found", "zero result is the AX value")
        check(view.previous.isAccessibilityHidden() && view.next.isAccessibilityHidden(), "hidden match controls leave the AX tree")
        view.close.performClick(nil); check(close == 1, "native close dispatch")
        view.update(result: .pending, available: true)
        check(view.resultLabel.isHidden && view.field.stringValue == "find", "new publication hides stale count without editing")
        check(view.resultLabel.isAccessibilityHidden(), "pending count is hidden from AX")
        check((view.resultLabel.accessibilityValue() ?? "") == "", "pending AX value is empty")
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        window.makeFirstResponder(view.field)
        if let editor = view.field.currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: 1, length: 2))
            view.update(result: .matches(ordinal: 1, total: 7), available: true)
            check(editor.selectedRange() == NSRange(location: 1, length: 2), "async counters preserve selected query")
            editor.setMarkedText("compose", selectedRange: NSRange(location: 7, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            view.cancelOperation(nil)
            check(editor.hasMarkedText() && close == 1, "Escape remains with native IME")
            editor.unmarkText(); view.cancelOperation(nil); check(close == 2, "Escape closes after native composition")
        } else { preconditionFailure("native field editor was not available") }
        view.update(result: .matches(ordinal: 1, total: 7), available: true)
        window.makeFirstResponder(view.next)
        check(window.firstResponder === view.next, "native next button can own keyboard focus")
        view.update(result: .notFound, available: true)
        check(view.field.currentEditor() === window.firstResponder, "hidden match control returns to the same native query editor")
        window.close()
        let hoverWindow = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: .borderless, backing: .buffered, defer: false)
        hoverWindow.isReleasedWhenClosed = false
        let surface = NSView(frame: hoverWindow.contentView!.bounds)
        hoverWindow.contentView = surface
        let control = PageFindButton(frame: NSRect(x: 20, y: 20, width: 26, height: 26))
        surface.addSubview(control)
        func hoverAreas() -> [NSTrackingArea] { control.trackingAreas.filter { !$0.options.contains(.cursorUpdate) } }
        control.updateTrackingAreas()
        check(hoverAreas().count == 1, "one original hover tracking area")
        let options = hoverAreas()[0].options
        check(options.rawValue == 0x223, "recovered key-window visible-rect tracking options")
        control.updateTrackingAreas()
        check(hoverAreas().count == 1, "layout replaces rather than stacks tracking")
        check(control.focusRingMaskBounds == control.bounds, "native focus ring uses original bounds")
        check((control.cell as? NSButtonCell)?.highlightsBy == .contentsCellMask,
              "momentary-change keeps AppKit's native content press feedback")
        let move = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: hoverWindow.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0)!
        hoverWindow.pointer = NSPoint(x: 33, y: 33)
        control.mouseMoved(with: move)
        check(control.isHovered, "actual same-window hit test admits pointer")
        control.appearance = NSAppearance(named: .aqua); control.updateLayer()
        check(control.layer?.cornerRadius == 6 && control.layer?.cornerCurve == .continuous,
              "original hover radius and curve")
        check(abs((control.layer?.backgroundColor?.alpha ?? 0) - 0.071) < 0.00001,
              "light GrayA4 alpha")
        control.appearance = NSAppearance(named: .darkAqua); control.updateLayer()
        check(abs((control.layer?.backgroundColor?.alpha ?? 0) - 0.077) < 0.00001,
              "dark GrayA4 resolves in actual appearance")
        control.isEnabled = false; control.updateLayer()
        check(control.layer?.backgroundColor?.alpha == 0, "disabled control has no hover decoration")
        control.isEnabled = true; control.updateLayer()
        check((control.layer?.backgroundColor?.alpha ?? 0) > 0, "reenabled original pointer state restores decoration")
        let cover = NSView(frame: control.frame)
        surface.addSubview(cover, positioned: .above, relativeTo: control)
        control.mouseMoved(with: move)
        check(!control.isHovered, "overlapping native view wins hit testing")
        cover.removeFromSuperview(); control.mouseMoved(with: move)
        check(control.isHovered, "uncovered original control can hover again")
        hoverWindow.key = false; control.mouseMoved(with: move)
        check(!control.isHovered, "inactive window refuses hover")
        hoverWindow.key = true; control.mouseMoved(with: move)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: hoverWindow)
        check(!control.isHovered, "original key loss clears decoration")
        control.mouseMoved(with: move)
        let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: other)
        check(control.isHovered, "foreign key notification cannot clear original state")
        other.close()
        hoverWindow.pointer = NSPoint(x: 100, y: 80); control.mouseMoved(with: move)
        check(!control.isHovered, "leaving actual bounds clears decoration")
        hoverWindow.pointer = NSPoint(x: 33, y: 33); control.mouseMoved(with: move)
        control.viewDidHide()
        check(!control.isHovered, "native hide lifecycle retires hover")
        control.mouseMoved(with: move)
        control.removeFromSuperview()
        check(!control.isHovered, "detachment clears original state")
        control.mouseMoved(with: move)
        check(!control.isHovered, "detached control cannot regain hover")
        check(view.resultLabel.hitTest(.zero) == nil, "counter does not intercept native input")
        check(view.resultLabel.accessibilityRole() == NSTextField(labelWithString: "2/4").accessibilityRole(), "counter retains the native noneditable label role")
        hoverWindow.close()
        print("\(checks) Find presentation assertions passed")
    }
}
