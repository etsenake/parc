import AppKit
import Combine

@MainActor
final class NotePageMath {
    private weak var editor: NotePageEditor?
    private let numberer = NotePageMathNumberer()
    private var computed: (revision: UInt64, numbering: NotePageMathNumbering)?
    private var pendingBroadcast = false
    private var subscription: AnyCancellable?

    init(editor: NotePageEditor) {
        self.editor = editor
        subscription = editor.session.changes.sink { [weak self] change in
            guard change.kind != .selection else { return }
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var numbering: NotePageMathNumbering {
        guard let editor else { return NotePageMathNumbering() }
        if let computed, computed.revision == editor.session.revision { return computed.numbering }
        let next = numberer.numbering(for: editor.session.page)
        if let previous = computed?.numbering, previous != next {
            pendingBroadcast = true
            DispatchQueue.main.async { [weak self] in self?.flush() }
        }
        computed = (editor.session.revision, next)
        return next
    }

    func context(for id: NoteBlockID) -> NoteMathNumberingContext { numbering.context(for: id) }

    var inlineContext: NoteMathNumberingContext { numbering.inlineContext }

    private func refresh() {
        _ = numbering
        flush()
    }

    private func flush() {
        guard pendingBroadcast, let editor else { return }
        pendingBroadcast = false
        for view in editor.canvas.materializedViews {
            (view as? NoteEquationBlockView)?.mathNumberingDidChange()
            for host in view.textHosts { host.textView.mathNumberingDidChange() }
        }
    }

    @discardableResult
    func reveal(label key: String) -> Bool {
        guard let editor, let id = numbering.targets[key] else { return false }
        return editor.reveal(block: id)
    }

    static func missingReferenceTooltip(_ key: String) -> String {
        "No equation is labelled \u{201C}\(key)\u{201D} yet"
    }
}
