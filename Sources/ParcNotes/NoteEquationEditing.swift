import AppKit

@MainActor
package final class NoteEquationEditSession {
    let content: NoteEquationEditorView
    let panel: NoteFloatingPanel
    package var onChange: ((String) -> Void)?
    package var onCommit: (() -> Void)?
    package var onCancel: (() -> Void)?
    package var onDismiss: (() -> Void)?
    package var onClickAway: (() -> Void)?
    private weak var host: NSView?
    private var outsideMonitor: Any?
    private let isInsideOwner: (NSEvent) -> Bool

    package init(source: String, host: NSView, isInsideOwner: @escaping (NSEvent) -> Bool) {
        self.host = host
        self.isInsideOwner = isInsideOwner
        content = NoteEquationEditorView(source: source)
        content.frame.size = content.fittingSize
        panel = NoteFloatingPanel(content: content)
        panel.alignment = .center
        content.onChange = { [weak self] text in self?.onChange?(text) }
        content.onCommit = { [weak self] in self?.onCommit?() }
        content.onCancel = { [weak self] in self?.onCancel?() }
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            self.onDismiss?()
        }
    }

    package var textView: NSTextView { content.textView }

    package func present(anchor: NSRect, error: String?, range: NSRange?) {
        guard let host else { return }
        content.setError(error, range: range)
        panel.present(in: host, anchor: anchor, edge: .below)
        host.window?.makeFirstResponder(content.textView)
        let end = (content.textView.string as NSString).length
        content.textView.setSelectedRange(NSRange(location: end, length: 0))
        outsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.panel.window else { return }
                let inPanel = self.panel.bounds.contains(self.panel.convert(event.locationInWindow, from: nil))
                if !inPanel && !self.isInsideOwner(event) { self.onClickAway?() }
            }
            return event
        }
    }

    package func reposition(anchor: NSRect) {
        guard panel.superview != nil else { return }
        panel.reposition(anchor: anchor, edge: .below, animated: false)
    }

    package func setError(_ text: String?, range: NSRange?) {
        content.setError(text, range: range)
    }

    func stopWatching() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }

    package func close(animated: Bool) {
        stopWatching()
        panel.dismiss(animated: animated)
    }
}

extension NoteEquationEditSession: EaselEquationEditing {
    package func contains(_ view: NSView) -> Bool { view === panel || view.isDescendant(of: panel) }
}
