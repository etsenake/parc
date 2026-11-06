import AppKit

/// The native field editor owns selection, composition, undo and ordinary keys.
/// An edit completes once; Escape and owner removal never publish a name.
final class SidebarTitleField: NSTextField, NSTextFieldDelegate {
    var onFinish: ((String?) -> Void)?
    private(set) var editingTitle = false
    private var editGeneration: UInt64 = 0

    init() {
        super.init(frame: .zero)
        isBordered = false; drawsBackground = false; focusRingType = .none
        isEditable = true; isSelectable = true; usesSingleLineMode = true
        delegate = self; isHidden = true
        setAccessibilityLabel("Tab name")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @discardableResult func begin(title: String, placeholder: String? = nil) -> Bool {
        guard let window, window.isKeyWindow, !editingTitle else { return false }
        stringValue = title; placeholderString = placeholder ?? title
        editGeneration &+= 1
        isHidden = false; editingTitle = true
        guard window.makeFirstResponder(self) else {
            editingTitle = false; isHidden = true; return false
        }
        currentEditor()?.selectAll(nil)
        return true
    }

    func cancel() { finish(nil) }
    private func finish(_ value: String?) {
        guard editingTitle else { return }
        editingTitle = false
        // Hide before ending AppKit editing so its end notification cannot
        // recursively commit or target a newly rebuilt row.
        isHidden = true
        abortEditing()
        onFinish?(value)
    }
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancel(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finish(stringValue); return true
        }
        return false
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard editingTitle, notification.object as? NSTextField === self else { return }
        let value = stringValue, generation = editGeneration
        // AppKit sends didEndEditing before willMove during removal. Let that
        // ownership change cancel first, while preserving ordinary click-away
        // completion from the same native field/editor session.
        DispatchQueue.main.async { [weak self, weak originalWindow = window] in
            guard let self, self.editingTitle, self.editGeneration == generation else { return }
            guard let originalWindow, self.window === originalWindow,
                  self.superview != nil, !self.isHiddenOrHasHiddenAncestor else {
                self.cancel(); return
            }
            self.finish(value)
        }
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { cancel() }
        super.viewWillMove(toSuperview: newSuperview)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancel() }
        super.viewWillMove(toWindow: newWindow)
    }
}
