import AppKit
import ParcCore

@MainActor
package enum EmbeddedPageSearchRows {
    package typealias Search = (query: String, category: EaselWebNavigation.Category)

    static func address(_ text: String) -> URL? {
        if case .address(let url) = EaselWebNavigation.entry(text) { return url }
        return nil
    }

    package static func items(for text: String) -> [NoteMenuList.Item] {
        guard case .search = EaselWebNavigation.entry(text) else { return [] }
        return EaselWebNavigation.Category.allCases.map { category in
            var item = NoteMenuList.Item(id: category.rawValue, title: category.title, icon: .symbol(symbol(for: category)),
                                         section: "Search DuckDuckGo")
            item.accessibilityLabel = category == .all ? "Search DuckDuckGo" : "Search DuckDuckGo for " + category.title.lowercased()
            return item
        }
    }

    package static func search(for item: NoteMenuList.Item, text: String) -> (url: URL, search: Search)? {
        guard let category = EaselWebNavigation.Category(rawValue: item.id),
              case .search(let query) = EaselWebNavigation.entry(text),
              let url = EaselWebNavigation.destination(.init(mode: .search, text: query, category: category)) else { return nil }
        return (url, (query, category))
    }

    package static func configure(_ entry: NoteLinkEntryView) {
        entry.parseLink = { address($0) }
        entry.setPlaceholder("Paste a link or search the web…")
        entry.setFieldLabel("Webpage address or search")
    }

    private static func symbol(for category: EaselWebNavigation.Category) -> String {
        switch category {
        case .all: return "magnifyingglass"
        case .images: return "photo"
        case .video: return "play.rectangle"
        case .news: return "newspaper"
        case .maps: return "map"
        case .shopping: return "bag"
        }
    }
}

@MainActor
final class EmbeddedPageAddressEditor: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 440
    static let padding: CGFloat = 8

    var preferredSizeDidChange: (() -> Void)?
    var onSubmit: ((URL, EmbeddedPageSearchRows.Search?) -> Bool)?
    var onCancel: (() -> Void)?
    let entry = NoteLinkEntryView(style: .embed)
    let list = NoteMenuList()
    private var category: EaselWebNavigation.Category

    init(text: String, category: EaselWebNavigation.Category) {
        self.category = category
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: NoteLinkEntryView.defaultHeight + Self.padding * 2))
        wantsLayer = true
        EmbeddedPageSearchRows.configure(entry)
        entry.text = text
        entry.onSubmit = { [weak self] url in self?.submit(url, search: nil) }
        entry.onUnrecognized = { [weak self] _ in self?.list.activateHighlighted() ?? false }
        entry.onTextChange = { [weak self] _ in self?.refresh() }
        entry.onCommand = { [weak self] selector in self?.command(selector) ?? false }
        addSubview(entry)
        list.fixedWidth = Self.width
        list.maximumHeight = 280
        list.prepare(origin: .keyboard)
        list.onActivate = { [weak self] item in self?.activate(item) }
        list.onCancel = { [weak self] in self?.onCancel?() }
        list.setAccessibilityLabel("Search results")
        addSubview(list)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Edit address or search")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var listHeight: CGFloat { list.items.isEmpty ? 0 : list.fittingSize.height }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: Self.padding * 2 + NoteLinkEntryView.defaultHeight + (listHeight > 0 ? 4 + listHeight : 0))
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            entry.frame = NSRect(x: Self.padding, y: Self.padding, width: bounds.width - Self.padding * 2, height: NoteLinkEntryView.defaultHeight)
            list.isHidden = list.items.isEmpty
            list.frame = NSRect(x: 0, y: entry.frame.maxY + 4, width: bounds.width, height: listHeight)
        }
    }

    func focus() { _ = entry.beginEditing(selectingAll: true) }

    private func refresh() {
        list.setItems(EmbeddedPageSearchRows.items(for: entry.text), keepingHighlight: true)
        if list.highlightedItem == nil, !list.items.isEmpty { list.highlight(id: category.rawValue, animated: false) }
        invalidateIntrinsicContentSize()
        needsLayout = true
        preferredSizeDidChange?()
    }

    private func activate(_ item: NoteMenuList.Item) {
        guard let found = EmbeddedPageSearchRows.search(for: item, text: entry.text) else { return }
        category = found.search.category
        submit(found.url, search: found.search)
    }

    private func submit(_ url: URL, search: EmbeddedPageSearchRows.Search?) {
        guard onSubmit?(url, search) == true else {
            entry.refuse("Can’t go there just now. Try again?")
            return
        }
    }

    private func command(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            return list.items.isEmpty ? false : list.handle(command: selector)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return list.items.isEmpty ? false : list.activateHighlighted()
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }
}
