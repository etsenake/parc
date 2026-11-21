import AppKit
import ParcCore

@MainActor
final class NoteLinkEditorView: NSView, NoteFloatingPanelContent {
    enum Action: Equatable {
        case apply(String)
        case open(String)
        case remove
        case cancel
    }

    static let width: CGFloat = 340
    static let padding: CGFloat = 8
    static let resultLimit = 6

    var preferredSizeDidChange: (() -> Void)?
    var onAction: ((Action) -> Void)?
    let existingLink: String?
    let field = NoteSearchField(placeholder: "Paste a link or find a note")
    let list = NoteMenuList()
    private let search: (String) -> [NoteReference]
    private let linkTarget: (URL) -> String
    private var results: [NoteReference] = []
    private(set) var normalized: String?

    init(existingLink: String?, search: @escaping (String) -> [NoteReference], linkTarget: @escaping (URL) -> String) {
        self.existingLink = existingLink
        self.search = search
        self.linkTarget = linkTarget
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 60))
        wantsLayer = true
        field.showsIcon = false
        field.text = existingLink.map { NoteLinkInput.isRelative($0) ? ($0.removingPercentEncoding ?? $0) : $0 } ?? ""
        field.onChange = { [weak self] _ in self?.refresh() }
        field.onCommand = { [weak self] selector in self?.command(selector) ?? false }
        field.textField.setAccessibilityLabel("Link or note")
        addSubview(field)
        list.fixedWidth = Self.width
        list.maximumHeight = 300
        list.prepare(origin: .keyboard)
        list.onActivate = { [weak self] item in self?.activate(item) }
        list.onCancel = { [weak self] in self?.onAction?(.cancel) }
        list.preferredSizeDidChange = { [weak self] in self?.contentChanged() }
        addSubview(list)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Link")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: Self.padding + NoteTheme.fieldHeight + 4 + list.fittingSize.height)
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            field.frame = NSRect(x: Self.padding, y: Self.padding, width: bounds.width - Self.padding * 2, height: NoteTheme.fieldHeight)
            let listHeight = list.fittingSize.height
            list.frame = NSRect(x: 0, y: field.frame.maxY + 4, width: bounds.width, height: listHeight)
        }
    }

    func focusField() {
        field.focus()
        field.textField.currentEditor()?.selectAll(nil)
    }

    var query: String { field.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    func refresh() {
        let query = self.query
        normalized = NoteLinkInput.normalize(query)
        var items: [NoteMenuList.Item] = []
        if let normalized {
            var item = NoteMenuList.Item(id: "apply", title: NoteLinkInput.displayText(normalized))
            item.icon = NoteLinkInput.isRelative(normalized) || normalized.hasPrefix("file:") ? .symbol("doc.text") : .symbol("globe")
            item.shortcut = "↩"
            item.section = normalized == existingLink ? "Keep This Link" : "Link To"
            item.accessibilityLabel = "Link to " + NoteLinkInput.displayText(normalized)
            items.append(item)
        }
        let searchable = NoteLinkInput.scheme(of: query) == nil && !query.hasPrefix("#")
        results = searchable && (normalized == nil || !query.contains("/")) ? Array(search(query).prefix(Self.resultLimit)) : []
        for (index, note) in results.enumerated() {
            var item = NoteMenuList.Item(id: "note." + String(index), title: note.title.isEmpty ? "Untitled" : note.title)
            item.icon = NoteIcon.note(note.icon, at: note.url)
            item.section = "Link to Note"
            item.accessibilityLabel = "Link to note " + item.title
            items.append(item)
        }
        if let existingLink {
            var open = NoteMenuList.Item(id: "open", title: "Open Link")
            open.icon = .symbol("arrow.up.right.square")
            open.section = "This Link"
            open.isEnabled = NoteFormatBarController.canOpen(existingLink)
            items.append(open)
            var remove = NoteMenuList.Item(id: "remove", title: "Remove Link")
            remove.icon = .symbol("trash")
            remove.section = "This Link"
            remove.isDestructive = true
            items.append(remove)
        }
        list.noResultsTitle = query.isEmpty ? "Paste a link or find a note" : "That’s not a link, and no notes match."
        list.setItems(items, keepingHighlight: false)
        if let first = items.first(where: \.isEnabled), !query.isEmpty || existingLink == nil {
            list.highlight(id: first.id, animated: false)
        }
        contentChanged()
    }

    private func contentChanged() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        preferredSizeDidChange?()
    }

    private func activate(_ item: NoteMenuList.Item) {
        switch item.id {
        case "apply":
            if let normalized { onAction?(.apply(normalized)) }
        case "open":
            if let existingLink { onAction?(.open(existingLink)) }
        case "remove":
            onAction?(.remove)
        default:
            guard item.id.hasPrefix("note."), let index = Int(item.id.dropFirst(5)), results.indices.contains(index) else { return }
            onAction?(.apply(linkTarget(results[index].url)))
        }
    }

    func submit() -> Bool {
        if list.activateHighlighted() { return true }
        if let first = list.visibleItems.first(where: \.isEnabled) {
            activate(first)
            return true
        }
        refuse()
        return false
    }

    private func refuse() {
        guard let panel = sequence(first: superview, next: { $0?.superview }).compactMap({ $0 as? NoteFloatingPanel }).first else { return }
        NoteAnimation.pop(panel, from: 0.97, spring: .bounce)
    }

    private func command(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            _ = submit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onAction?(.cancel)
            return true
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)),
             #selector(NSResponder.moveToBeginningOfDocument(_:)), #selector(NSResponder.moveToEndOfDocument(_:)):
            return list.handle(command: selector)
        default:
            return false
        }
    }
}
