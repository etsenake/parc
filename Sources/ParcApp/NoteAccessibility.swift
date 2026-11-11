import AppKit

@MainActor
enum NoteAccessibility {
    static let loadErrorTitle = "Can't load this note"
    static let titlePlaceholder = "Title"
    static let formatParagraph = "Format Paragraph"
    static let formatSelection = "Format Selection"

    static func label(for item: NoteFormatMenu.Item) -> String { item.title }

    static func nextIndex(from selected: Int?, enabled: [Int], step: Int) -> Int? {
        guard !enabled.isEmpty else { return nil }
        if let selected, let current = enabled.firstIndex(of: selected) {
            return enabled[(current + step + enabled.count) % enabled.count]
        }
        return step > 0 ? enabled.first : enabled.last
    }

    static func reveal(_ range: NSRange, in text: NSTextView) {
        let length = (text.string as NSString).length
        guard range.location != NSNotFound, range.location <= length,
              range.length <= length - range.location else { return }
        text.scrollRangeToVisible(range)
    }

    static func reveal(_ view: NSView) {
        view.scrollToVisible(view.bounds)
    }

    @discardableResult
    static func returnFocus(to text: NSTextView, in window: NSWindow?) -> Bool {
        guard let window, text.window === window, window.attachedSheet == nil else { return false }
        guard window.makeFirstResponder(text), window.firstResponder === text else { return false }
        return true
    }

    static func restoreBodyIfMenuRelinquished(_ text: NSTextView, owned: NSView?) {
        guard let window = text.window, window.firstResponder !== text, let owned else { return }
        let first = window.firstResponder
        if first is NSTextView { return }
        let detached = (first as? NSView)?.window == nil
        if first === owned || (first as? NSView)?.isDescendant(of: owned) == true
            || first === window || first == nil || detached {
            returnFocus(to: text, in: window)
        }
    }

    static func configureTitle(_ view: NSTextView) {
        view.setAccessibilityRole(.textArea)
        view.setAccessibilityLabel(titlePlaceholder)
    }

    static func configureBody(_ view: NSTextView) {
        view.setAccessibilityRole(.textArea)
    }

    static func configureGutter(_ button: NSButton) {
        button.refusesFirstResponder = true
        button.focusRingType = .none
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(formatParagraph)
        button.toolTip = formatParagraph
    }

    static func configureParagraphMenu(_ view: NSView) {
        view.setAccessibilityRole(.menu)
        view.setAccessibilityLabel(formatParagraph)
    }

    static func configureSelectionBar(_ view: NSView) {
        view.setAccessibilityRole(.toolbar)
        view.setAccessibilityLabel(formatSelection)
    }

    static func configureItem(_ button: NSButton, item: NoteFormatMenu.Item) {
        button.setAccessibilityRole(.menuItem)
        button.setAccessibilityLabel(label(for: item))
        button.toolTip = label(for: item)
    }

    static func configureLoadError(_ view: NSView, heading: NSTextField, detail: NSTextField) {
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(loadErrorTitle)
        heading.setAccessibilityRole(.staticText)
        heading.setAccessibilityLabel(loadErrorTitle)
        detail.setAccessibilityRole(.staticText)
        detail.setAccessibilityLabel(detail.stringValue)
    }

    static func configureFormatFallback(_ button: NSButton, selection: Bool) {
        let title = selection ? formatSelection : formatParagraph
        button.title = title
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(title)
        button.toolTip = title
    }

    static func configureFooter(retry: NSButton, discard: NSButton, status: NSTextField) {
        retry.setAccessibilityRole(.button)
        retry.setAccessibilityLabel(retry.title)
        discard.setAccessibilityRole(.button)
        discard.setAccessibilityLabel(discard.title)
        status.setAccessibilityRole(.staticText)
        status.setAccessibilityLabel(status.stringValue)
    }

    static func wireKeyLoop(title: NSView, body: NSView, format: NSButton, retry: NSButton, discard: NSButton) {
        var chain: [NSView] = [title, body]
        if !format.isHidden { chain.append(format) }
        if !retry.isHidden { chain.append(retry) }
        if !discard.isHidden { chain.append(discard) }
        guard chain.count > 1 else { return }
        for index in 0..<(chain.count - 1) {
            chain[index].nextKeyView = chain[index + 1]
        }
        if let last = chain.last, chain.contains(where: { $0 === last.nextKeyView }) {
            last.nextKeyView = nil
        }
    }

    final class PopoverCloseObserver: @unchecked Sendable {
        nonisolated(unsafe) fileprivate var token: NSObjectProtocol?
        nonisolated func invalidate() {
            if let token { NotificationCenter.default.removeObserver(token) }
            self.token = nil
        }
        deinit { invalidate() }
    }

    static func observePopoverClose(positioning: NSView, restore text: NSTextView) -> PopoverCloseObserver {
        let observer = PopoverCloseObserver()
        observer.token = NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: nil, queue: .main) { [weak observer, weak positioning, weak text] notification in
            MainActor.assumeIsolated {
                guard let text, let positioning, positioning.window === text.window,
                      let popover = notification.object as? NSPopover,
                      popover.contentViewController is EaselLinkEditor else { return }
                observer?.invalidate()
                restoreBodyIfMenuRelinquished(text, owned: positioning)
            }
        }
        return observer
    }
}
