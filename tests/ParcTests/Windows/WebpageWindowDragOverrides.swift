import AppKit
import ObjectiveC

enum WebpageWindowDragOverrides {
    nonisolated(unsafe) static var currentEvent: NSEvent?
    nonisolated(unsafe) static var cursor: NSCursor?
    nonisolated(unsafe) static var cursorReads = 0
    nonisolated(unsafe) static var windowDrag: ((NSWindow, NSEvent) -> Void)?
    nonisolated(unsafe) private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        swap(NSApplication.self, #selector(getter: NSApplication.currentEvent), #selector(getter: NSApplication.webpageDragObservedCurrentEvent))
        swap(NSWindow.self, #selector(NSWindow.performDrag(with:)), #selector(NSWindow.webpageDragObservedPerformDrag(with:)))
        guard let current = class_getClassMethod(NSCursor.self, #selector(getter: NSCursor.current)),
              let replacement = class_getClassMethod(NSCursor.self, #selector(getter: NSCursor.webpageDragObservedCurrent)) else {
            preconditionFailure("missing +[NSCursor currentCursor]")
        }
        method_exchangeImplementations(current, replacement)
    }

    static func reset() {
        currentEvent = nil
        cursor = nil
        cursorReads = 0
        windowDrag = nil
    }

    private static func swap(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(type, original),
              let replacementMethod = class_getInstanceMethod(type, replacement) else {
            preconditionFailure("missing \(original)")
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

extension NSApplication {
    @objc dynamic nonisolated var webpageDragObservedCurrentEvent: NSEvent? {
        WebpageWindowDragOverrides.currentEvent ?? self.webpageDragObservedCurrentEvent
    }
}

extension NSCursor {
    @objc dynamic nonisolated class var webpageDragObservedCurrent: NSCursor {
        guard let cursor = WebpageWindowDragOverrides.cursor else { return self.webpageDragObservedCurrent }
        WebpageWindowDragOverrides.cursorReads += 1
        return cursor
    }
}

extension NSWindow {
    @objc dynamic nonisolated func webpageDragObservedPerformDrag(with event: NSEvent) {
        guard let windowDrag = WebpageWindowDragOverrides.windowDrag else { return webpageDragObservedPerformDrag(with: event) }
        windowDrag(self, event)
    }
}
