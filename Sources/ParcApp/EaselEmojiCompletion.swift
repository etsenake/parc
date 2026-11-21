import AppKit

@MainActor
final class EaselEmojiCompletion: EaselTextCompletion {
    private weak var view: EaselStyledTextView?
    private var list: NoteEmojiSuggestionList?
    private var panel: NoteFloatingPanel?
    private var start: Int?
    private var observer: NSObjectProtocol?

    func attach(_ view: EaselStyledTextView) {
        detach()
        self.view = view
        observer = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: view,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(typed: false) }
        }
    }

    func detach() {
        dismiss()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        view = nil
    }

    func textDidChange(in view: EaselStyledTextView) {
        guard view === self.view else { return }
        refresh(typed: true)
    }

    func handle(_ selector: Selector, in view: EaselStyledTextView) -> Bool {
        guard view === self.view, panel?.isPresented == true, let list else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) { dismiss(); return true }
        return list.handle(selector)
    }

    func dismiss() {
        start = nil
        guard let panel, panel.isPresented else { return }
        panel.dismiss(animated: !NoteAnimation.reduceMotion)
    }

    private func refresh(typed: Bool) {
        guard let view, view.isEditable, view.window != nil, !view.hasMarkedText(), view.selectedRanges.count == 1,
              view.selectedRange().length == 0 else { dismiss(); return }
        let text = view.string, caret = view.selectedRange().location
        if typed, let done = NoteTriggerRule.completedShortcode(in: text, caret: caret) {
            dismiss()
            DispatchQueue.main.async { [weak self] in self?.complete(done, expected: text) }
            return
        }
        guard typed || panel?.isPresented == true, let match = NoteTriggerRule.emojiQuery(in: text, caret: caret) else { dismiss(); return }
        show(start: match.start, query: match.query, in: view)
    }

    private func show(start: Int, query: String, in view: EaselStyledTextView) {
        let suggestions = list ?? makeList()
        suggestions.query = query
        guard suggestions.hasResults, let panel, let host = view.enclosingScrollView?.superview ?? view.superview,
              let anchor = anchorRect(at: start, in: view, host: host) else { dismiss(); return }
        self.start = start
        panel.contentSizeDidChange(animated: false)
        if panel.isPresented, panel.superview === host { panel.reposition(anchor: anchor, edge: .below, animated: false) }
        else { panel.present(in: host, anchor: anchor, edge: .below, animated: !NoteAnimation.reduceMotion) }
    }

    private func makeList() -> NoteEmojiSuggestionList {
        let suggestions = NoteEmojiSuggestionList(limit: 8)
        suggestions.onPick = { [weak self] character in self?.insert(character) }
        suggestions.onCancel = { [weak self] in self?.dismiss() }
        let panel = NoteFloatingPanel(content: suggestions)
        panel.maximumHeight = 400
        suggestions.onResultsChange = { [weak panel] _ in panel?.contentSizeDidChange(animated: true) }
        list = suggestions
        self.panel = panel
        return suggestions
    }

    private func anchorRect(at location: Int, in view: EaselStyledTextView, host: NSView) -> NSRect? {
        guard let window = view.window, location <= (view.string as NSString).length else { return nil }
        let screen = view.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        guard screen.origin.x.isFinite, screen.origin.y.isFinite, screen.height > 0 else { return nil }
        return host.convert(window.convertFromScreen(screen), from: nil)
    }

    private func insert(_ character: String) {
        guard let view, let start, view.selectedRanges.count == 1 else { dismiss(); return }
        let caret = view.selectedRange().location
        dismiss()
        guard caret >= start else { return }
        view.insertCompletion(character, replacing: NSRange(location: start, length: caret - start), name: "Emoji")
    }

    private func complete(_ done: (range: Range<Int>, shortcode: String), expected: String) {
        guard let view, view.string == expected, !view.hasMarkedText() else { return }
        let catalog = NoteEmojiCatalog.shared
        guard let emoji = catalog.emoji(forShortcode: done.shortcode) else { return }
        let character = catalog.character(for: emoji)
        catalog.recordUse(character)
        view.insertCompletion(character, replacing: NSRange(location: done.range.lowerBound, length: done.range.count), name: "Emoji")
    }
}
