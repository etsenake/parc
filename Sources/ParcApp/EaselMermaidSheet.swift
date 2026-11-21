import AppKit

@MainActor
final class EaselMermaidSheet: NSObject, NSTextViewDelegate {
    static let title = "Insert Mermaid Diagram…"
    static let example = "flowchart LR\n    A[Idea] --> B{Worth it?}\n    B -->|Yes| C[Ship it]\n    B -->|No| D[Nap on it]"

    private let panel: NSPanel
    private let source = EaselMermaidSourceView(frame: .zero)
    private let status = NSTextField(labelWithString: "")
    private let insertButton = ParcDialogButton(title: "Insert", primary: true, hint: false)
    private let cancelButton = ParcDialogButton(title: "Cancel", primary: false)
    private weak var canvas: EaselCanvasView?
    private weak var parent: NSWindow?
    private let documentID: UUID
    private var ended = false

    init(canvas: EaselCanvasView, text: String) {
        self.canvas = canvas
        documentID = canvas.session.document.id
        panel = EaselMermaidPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        super.init()
        panel.titlebarAppearsTransparent = true; panel.titleVisibility = .hidden
        panel.isOpaque = false; panel.backgroundColor = ParcDialogStyle.popoverBackground
        panel.isReleasedWhenClosed = false
        (panel as? EaselMermaidPanel)?.onCancel = { [weak self] in self?.cancel(nil) }
        build(text: text)
    }

    private func build(text: String) {
        let width: CGFloat = 540, inset: CGFloat = 38, body = width - 2 * inset
        let root = EaselMermaidSheetView(frame: .zero)
        var y = inset
        let title = ParcDialogStyle.label([("Insert a Mermaid diagram", false)], size: 18, weight: .medium,
                                          color: ParcDialogStyle.popoverTitle, lineSpacing: 4)
        root.addSubview(title)
        y += ParcDialogStyle.place(title, x: inset, y: y, width: body) + 8
        let message = ParcDialogStyle.label([("Paste or type a flowchart or an ER diagram. It lands as shapes, arrows and sections you can keep editing.", false)],
                                            size: 14, weight: .regular, color: ParcDialogStyle.popoverMessage, lineSpacing: 1)
        root.addSubview(message)
        y += ParcDialogStyle.place(message, x: inset, y: y, width: body) + 16

        let card = EaselMermaidFieldCard(frame: NSRect(x: inset, y: y, width: body, height: 220))
        let scroll = NSScrollView(frame: card.bounds.insetBy(dx: 4, dy: 4))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        source.frame = NSRect(origin: .zero, size: scroll.contentSize)
        source.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        source.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        source.isVerticallyResizable = true; source.isHorizontallyResizable = true; source.autoresizingMask = [.width]
        source.textContainer?.widthTracksTextView = false
        source.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        source.font = NoteTheme.codeFont(size: 13); source.textColor = ParcDialogStyle.popoverTitle
        source.insertionPointColor = ParcDialogStyle.popoverTitle
        source.drawsBackground = false; source.isRichText = false; source.importsGraphics = false
        source.allowsUndo = true; source.smartInsertDeleteEnabled = false
        source.isAutomaticQuoteSubstitutionEnabled = false; source.isAutomaticDashSubstitutionEnabled = false
        source.isAutomaticTextReplacementEnabled = false; source.isAutomaticSpellingCorrectionEnabled = false
        source.isContinuousSpellCheckingEnabled = false; source.isGrammarCheckingEnabled = false
        source.isAutomaticLinkDetectionEnabled = false; source.isAutomaticDataDetectionEnabled = false
        source.textContainerInset = NSSize(width: 8, height: 8)
        source.placeholder = Self.example
        source.string = text
        source.delegate = self
        source.setAccessibilityLabel("Mermaid diagram source")
        source.setAccessibilityHelp("Command-Return inserts the diagram")
        scroll.documentView = source
        card.addSubview(scroll); card.field = source
        root.addSubview(card)
        y += card.frame.height + 10

        status.font = .systemFont(ofSize: 12); status.lineBreakMode = .byTruncatingTail
        status.frame = NSRect(x: inset, y: y, width: body, height: 18)
        root.addSubview(status)
        y += 18 + 22

        insertButton.target = self; insertButton.action = #selector(insert(_:))
        insertButton.keyEquivalent = "\r"; insertButton.keyEquivalentModifierMask = [.command]
        insertButton.toolTip = "Insert (⌘↩)"
        cancelButton.target = self; cancelButton.action = #selector(cancel(_:)); cancelButton.keyEquivalent = "\u{1b}"
        var right = width - 28
        for button in [insertButton, cancelButton] {
            button.frame = NSRect(x: right - button.bodyWidth - 0.5, y: y - 0.5, width: button.bodyWidth + 1, height: 38.5)
            root.addSubview(button)
            right -= button.bodyWidth + 8
        }
        y += 36 + 28
        root.frame = NSRect(x: 0, y: 0, width: width, height: y)
        panel.contentView = root
        panel.setContentSize(NSSize(width: width, height: y))
        panel.initialFirstResponder = source
        panel.setAccessibilityDefaultButton(insertButton)
        panel.setAccessibilityLabel("Insert a Mermaid diagram")
        refresh()
    }

    func begin(for window: NSWindow) -> Bool {
        guard !ended, parent == nil, window.attachedSheet == nil, canvasIsCurrent(in: window) else { return false }
        parent = window
        window.beginSheet(panel) { [self] _ in
            ended = true
            if let canvas, canvas.window === window { window.makeFirstResponder(canvas) }
        }
        panel.makeFirstResponder(source)
        source.selectAll(nil)
        return true
    }

    private func canvasIsCurrent(in window: NSWindow?) -> Bool {
        guard let canvas, let window, canvas.window === window, canvas.acceptsMermaid,
              canvas.session.document.id == documentID, !canvas.isHiddenOrHasHiddenAncestor else { return false }
        return true
    }

    private func refresh() {
        let text = source.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status.stringValue = "Tip: paste a mermaid code block, fences and all."
            status.textColor = ParcDialogStyle.popoverMessage
            insertButton.isEnabled = false
            return
        }
        switch EaselMermaid.parse(text) {
        case .success(let diagram):
            status.stringValue = diagram.summary
            status.textColor = ParcDialogStyle.popoverMessage
            insertButton.isEnabled = true
        case .failure(let refusal):
            status.stringValue = refusal.message
            status.textColor = EaselAppearance.error
            insertButton.isEnabled = false
        }
        status.toolTip = status.stringValue
    }

    func textDidChange(_ notification: Notification) { refresh() }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancel(nil); return true }
        if commandSelector == #selector(NSResponder.insertTab(_:)) { textView.insertText("    ", replacementRange: textView.selectedRange()); return true }
        return false
    }

    @objc private func insert(_ sender: Any?) {
        guard !ended, !source.hasMarkedText() else { return }
        guard canvasIsCurrent(in: parent), let canvas else { finish(); return }
        refresh()
        guard insertButton.isEnabled else {
            NSSound.beep()
            NSAccessibility.post(element: status, notification: .announcementRequested,
                                 userInfo: [.announcement: status.stringValue, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            return
        }
        guard canvas.insertMermaid(source.string) else {
            status.stringValue = "That diagram couldn't be added here. Try again."
            status.textColor = EaselAppearance.error
            return
        }
        finish()
    }

    @objc private func cancel(_ sender: Any?) {
        guard !ended else { return }
        finish()
    }

    private func finish() {
        guard !ended else { return }
        ended = true
        if let parent { parent.endSheet(panel) } else { panel.orderOut(nil) }
    }
}

@MainActor
private final class EaselMermaidPanel: NSPanel {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if (firstResponder as? NSTextView)?.hasMarkedText() == true,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class EaselMermaidSheetView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { ParcDialogStyle.popoverBackground.setFill(); dirtyRect.fill() }
}

@MainActor
private final class EaselMermaidFieldCard: NSView {
    weak var field: NSView?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        ParcDialogStyle.fieldFill.setFill()
        ParcDialogStyle.continuousRect(bounds, radius: 8).fill()
    }
    override func mouseDown(with event: NSEvent) {
        if let field { window?.makeFirstResponder(field) } else { super.mouseDown(with: event) }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
final class EaselMermaidSourceView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5), y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [.font: font ?? NoteTheme.codeFont(size: 13),
                                                                     .foregroundColor: ParcDialogStyle.popoverArrowIcon])
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
