import AppKit

@MainActor
final class NoteDateRefresher {
    private weak var editor: NotePageEditor?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var stopped = false

    init(editor: NotePageEditor) {
        self.editor = editor
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }))
        reschedule()
    }

    func stop() {
        stopped = true
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
    }

    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard !stopped, let editor else { return }
        let mentions = Self.mentions(in: editor.session.page)
        guard let next = NoteDateText.nextChange(of: mentions, after: Date(), calendar: .autoupdatingCurrent) else { return }
        let fire = Timer(fire: next.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        fire.tolerance = 1
        RunLoop.main.add(fire, forMode: .common)
        timer = fire
    }

    func refresh() {
        guard !stopped, let editor else { return }
        for view in editor.canvas.materializedViews {
            for host in view.textHosts where Self.hasDate(host.textView.noteText) { host.textView.refreshRendering() }
        }
        reschedule()
    }

    static func hasDate(_ text: NoteText) -> Bool {
        text.spans.contains { span in
            if case .date = span.marks.atom { return true }
            return false
        }
    }

    static func mentions(in page: NotePage) -> [NoteDateMention] {
        var found: [NoteDateMention] = []
        for block in page.allBlocks() {
            var texts: [NoteText] = []
            if block.kind.hasRichText { texts.append(block.text) }
            if !block.props.caption.isEmpty { texts.append(block.props.caption) }
            if let table = block.props.table { texts += table.rows.flatMap { $0 } }
            for text in texts {
                for span in text.spans {
                    if case .date(let mention)? = span.marks.atom { found.append(mention) }
                }
            }
        }
        return found
    }
}
