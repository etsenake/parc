import AppKit
import Combine

@MainActor
final class NotePageMath {
    static let draftDelay: TimeInterval = 0.25

    private weak var editor: NotePageEditor?
    private let numberer = NotePageMathNumberer()
    private var computed: (revision: UInt64, drafts: Int, numbering: NotePageMathNumbering)?
    private var drafts: [NoteBlockID: String] = [:]
    private var draftGeneration = 0
    private var draftToken = 0
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
        if let computed, computed.revision == editor.session.revision, computed.drafts == draftGeneration { return computed.numbering }
        let next = numberer.numbering(for: editor.session.page, drafts: drafts)
        if let previous = computed?.numbering, previous != next {
            pendingBroadcast = true
            DispatchQueue.main.async { [weak self] in self?.flush() }
        }
        computed = (editor.session.revision, draftGeneration, next)
        return next
    }

    func draftDidChange(_ source: String, for id: NoteBlockID) {
        draftToken &+= 1
        let token = draftToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.draftDelay) { [weak self] in
            guard let self, self.draftToken == token else { return }
            self.setDraft(source, for: id)
        }
    }

    func endDraft(for id: NoteBlockID) {
        draftToken &+= 1
        setDraft(nil, for: id)
    }

    private func setDraft(_ source: String?, for id: NoteBlockID) {
        guard drafts[id] != source else { return }
        drafts[id] = source
        draftGeneration &+= 1
        refresh()
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

    @discardableResult
    func follow(_ link: NoteMathLinkMark) -> Bool {
        guard let target = link.url else { return reveal(label: link.key) }
        guard let editor else { return false }
        let url = target.contains("://") || target.hasPrefix("mailto:") ? URL(string: target) : editor.environment.resolveNoteLink(target)
        guard let url else { return false }
        editor.open(url)
        return true
    }

    static func missingReferenceTooltip(_ key: String) -> String {
        "No equation is labelled \u{201C}\(key)\u{201D} yet"
    }
}
