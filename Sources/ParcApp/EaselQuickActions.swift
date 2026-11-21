import AppKit

@MainActor
final class EaselQuickActionsView: NSView, NoteFloatingPanelContent {
    var preferredSizeDidChange: (() -> Void)?
    let field = NoteSearchField(placeholder: "Add or do anything…")
    let list = NoteMenuList()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.textField.setAccessibilityLabel("Quick actions")
        list.minimumWidth = 300
        list.maximumWidth = 340
        list.maximumHeight = 360
        list.noResultsTitle = "Nothing by that name. Try “sticky” or “zoom”?"
        list.preferredSizeDidChange = { [weak self] in self?.preferredSizeDidChange?() }
        addSubview(field)
        addSubview(list)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let menu = list.intrinsicContentSize
        return NSSize(width: max(300, menu.width), height: NoteTheme.menuInset * 2 + NoteTheme.fieldHeight + menu.height)
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    override func layout() {
        super.layout()
        let inset = NoteTheme.menuInset
        field.frame = NSRect(x: inset * 2, y: inset * 2, width: max(0, bounds.width - inset * 4), height: NoteTheme.fieldHeight)
        list.frame = NSRect(x: 0, y: field.frame.maxY, width: bounds.width, height: max(0, bounds.height - field.frame.maxY))
    }
}

@MainActor
final class EaselQuickActions {
    struct Action {
        let id: String
        let title: String
        let icon: NoteIcon
        let shortcut: String?
        let keywords: [String]
        let section: String
        var isEnabled = true
        let run: () -> Void
    }

    private static var recentIDs: [String] = []
    private static let recentPrefix = "recent:"
    private var popover: NotePagePopover?
    var isOpen: Bool { popover?.isOpen == true }

    func toggle(in host: NSView, anchor: NSRect, actions: [Action], onClose: @escaping () -> Void) {
        if isOpen { popover?.close(); return }
        let view = EaselQuickActionsView(frame: .zero)
        let recents = Self.recentIDs.compactMap { id in actions.first { $0.id == id && $0.isEnabled } }
        let all = actions.map { Self.item(for: $0, id: $0.id, section: $0.section) }
        let withRecents = recents.map { Self.item(for: $0, id: Self.recentPrefix + $0.id, section: "Recent") } + all
        view.list.items = withRecents
        view.field.onChange = { [weak view] text in
            guard let view else { return }
            let filtering = !text.trimmingCharacters(in: .whitespaces).isEmpty
            view.list.setItems(filtering ? all : withRecents, keepingHighlight: false)
            view.list.filterText = text
            view.list.prepare(origin: .keyboard)
        }
        view.field.onCommand = { [weak view] selector in view?.list.handle(command: selector) ?? false }
        view.list.onActivate = { [weak self] item in
            let id = item.id.hasPrefix(Self.recentPrefix) ? String(item.id.dropFirst(Self.recentPrefix.count)) : item.id
            guard let action = actions.first(where: { $0.id == id }), action.isEnabled else { return }
            self?.popover?.close()
            Self.recentIDs.removeAll { $0 == id }
            Self.recentIDs.insert(id, at: 0)
            if Self.recentIDs.count > 3 { Self.recentIDs.removeLast(Self.recentIDs.count - 3) }
            action.run()
        }
        view.list.onCancel = { [weak self] in self?.popover?.close() }
        let next = NotePagePopover(content: view)
        next.panel.maximumHeight = 420
        next.onClose = { [weak self, weak next] in
            guard let self, self.popover === next else { return }
            self.popover = nil
            onClose()
        }
        popover = next
        next.present(in: host, anchor: anchor, edge: .below, alignment: .center)
        view.list.prepare(origin: .keyboard)
        view.field.focus()
    }

    func close() { popover?.close() }

    private static func item(for action: Action, id: String, section: String) -> NoteMenuList.Item {
        var item = NoteMenuList.Item(id: id, title: action.title, icon: action.icon, shortcut: action.shortcut, section: section,
                                     isEnabled: action.isEnabled)
        item.keywords = action.keywords
        return item
    }
}
