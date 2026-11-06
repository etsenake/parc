import AppKit
import CoreText

///
///
struct SidebarEmojiModel {
    struct Emoji: Equatable {
        let emoji: String
        let description: String
        let keywords: [String]
        let category: Int
        let supportsSkinTones: Bool
    }
    /// `Emojis.Emojis.Category` order; each keeps its Feather glyph from
    ///
    static let categories: [(name: String, glyph: UInt32)] = [
        ("Smileys & People", 0xE9DE), ("Animals & Nature", 0xE9E3), ("Food & Drink", 0xE943), ("Activities", 0xE919),
        ("Travel & Places", 0xE9F6), ("Objects", 0xE971), ("Symbols", 0xE97D), ("Flags", 0xE96B)]
    ///
    private static let categoryNames = ["smileys & emotion": 0, "people & body": 0, "animals & nature": 1,
        "food & drink": 2, "activities": 3, "travel & places": 4, "objects": 5, "symbols": 6, "flags": 7]

    /// Flat grid order: categories in case order, entries in file order
    ///
    let emojis: [Emoji]
    /// The first entry of each of the eight categories, if any remain.
    let categoryStarts: [Int?]

    init(_ entries: [Emoji]) {
        var byCategory = Array(repeating: [Emoji](), count: Self.categories.count)
        var seen = Set<String>()
        for entry in entries where seen.insert(entry.emoji).inserted { byCategory[entry.category].append(entry) }
        var starts: [Int?] = [], flat: [Emoji] = []
        for group in byCategory { starts.append(group.isEmpty ? nil : flat.count); flat += group }
        emojis = flat; categoryStarts = starts
    }

    /// Loaded once. A missing file or any undecodable entry yields an empty
    ///
    static let shared: SidebarEmojiModel = {
        guard let url = SidebarIconCatalog.resourceDirectory?.appendingPathComponent("emojis.json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return SidebarEmojiModel([]) }
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 0, nil)
        var entries: [Emoji] = []
        for item in list {
            guard let emoji = item["emoji"] as? String, emoji.count == 1,
                  let description = item["description"] as? String,
                  let category = (item["category"] as? String).flatMap({ categoryNames[$0.lowercased()] }) else { return SidebarEmojiModel([]) }
            //
            // glyph in Apple Color Emoji; no OS-version table is consulted.
            let units = Array(emoji.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            guard CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) else { continue }
            entries.append(Emoji(emoji: emoji, description: description, keywords: item["tags"] as? [String] ?? [],
                                 category: category, supportsSkinTones: item["skin_tones"] as? Bool ?? false))
        }
        return SidebarEmojiModel(entries)
    }()

    ///
    /// escaped, matched case-insensitively against the description or any
    /// keyword; the query containing the emoji itself also matches. An empty
    /// query keeps everything. Order is preserved.
    func filtered(_ query: String) -> SidebarEmojiModel {
        guard !query.isEmpty else { return self }
        let pattern = ".*" + query.replacingOccurrences(of: " ", with: ".*") + ".*"
        let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        func matches(_ text: String) -> Bool {
            guard let expression else { return false }
            return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        return SidebarEmojiModel(emojis.filter { matches($0.description) || $0.keywords.contains(where: matches) || query.contains($0.emoji) })
    }

    ///
    static let skinToneModifiers = ["", "\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"]
    ///
    /// after the first scalar; anything else returns the base unchanged.
    static func applying(_ modifier: String, to base: String) -> String {
        let scalars = Array(modifier.unicodeScalars)
        guard scalars.count == 1, (0x1F3FB...0x1F3FF).contains(scalars[0].value) else { return base }
        var result = Array(base.unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains($0.value) })
        result.insert(scalars[0], at: min(1, result.count))
        var view = String.UnicodeScalarView(); view.append(contentsOf: result)
        return String(view)
    }
    static func variants(of base: String) -> [String] { skinToneModifiers.map { applying($0, to: base) } }
    ///
    static let skinToneExclusions: Set<String> = ["🧑‍🤝‍🧑", "👭", "👫", "👬", "💏", "👩‍❤️‍💋‍👨", "👨‍❤️‍💋‍👨",
        "👩‍❤️‍💋‍👩", "💑", "👩‍❤️‍👨", "👨‍❤️‍👨", "👩‍❤️‍👩"]

    ///
    /// a toned choice marks its base cell.
    func index(containing selected: String?) -> Int? {
        guard let selected else { return nil }
        return emojis.firstIndex { Self.variants(of: $0.emoji).contains(selected) }
    }
}

///
/// flow-layout grid and a bottom category bar. AppKit owns keyboard and AX.
@MainActor
final class SidebarEmojiPickerView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSSearchFieldDelegate {
    var onEmojiSelected: ((String) -> Void)?
    var selectedEmoji: String? {
        didSet {
            guard selectedEmoji != oldValue else { return }
            refreshCurrent()
            scrollToSelected()
        }
    }
    private(set) var model: SidebarEmojiModel { didSet { currentIndex = model.index(containing: selectedEmoji); collectionView.reloadData() } }
    let searchField = NSSearchField()
    let scrollView = NSScrollView()
    let collectionView = NSCollectionView()
    let categoryBar = SidebarEmojiCategoryBar()
    private(set) var skinTonePopover: (popover: NSPopover, anchorIndex: Int)?
    private var currentIndex: Int?
    private var pendingQuery: String?
    private var lastQuery = ""
    private var debounce: Timer?
    private var liveScrollObserver: NSObjectProtocol?

    init(selectedEmoji: String?) {
        self.selectedEmoji = selectedEmoji
        model = .shared
        super.init(frame: .zero)
        currentIndex = model.index(containing: selectedEmoji)
        //
        // background. No placeholder until the text first changes.
        searchField.font = .systemFont(ofSize: 13)
        searchField.backgroundColor = .clear
        searchField.delegate = self
        //
        // one section, selectable; the scroll view keeps no scroller.
        collectionView.collectionViewLayout = NSCollectionViewFlowLayout()
        collectionView.isSelectable = true
        collectionView.dataSource = self; collectionView.delegate = self
        collectionView.register(SidebarEmojiItem.self, forItemWithIdentifier: SidebarEmojiItem.identifier)
        collectionView.backgroundColors = [.clear]
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        for (index, category) in SidebarEmojiModel.categories.enumerated() {
            let button = SidebarPickerHoverButton(image: SidebarEmojiCategoryBar.glyph(category.glyph), trackingOptions: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect])
            button.contentInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
            button.tag = index; button.target = self; button.action = #selector(scrollToCategory(_:))
            button.setAccessibilityLabel(category.name)
            categoryBar.addArrangedSubview(button)
        }
        for view in [searchField, scrollView, categoryBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
        }
        let searchTrailing = searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7)
        let barTrailing = categoryBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7)
        let barBottom = categoryBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        [searchTrailing, barTrailing, barBottom].forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7), searchTrailing,
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            categoryBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            categoryBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7), barTrailing, barBottom])
        //
        liveScrollObserver = NotificationCenter.default.addObserver(forName: NSScrollView.didLiveScrollNotification, object: scrollView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeSkinToneIfScrolledAway() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let liveScrollObserver { NotificationCenter.default.removeObserver(liveScrollObserver) }
    }

    override var wantsUpdateLayer: Bool { true }
    ///
    override func updateLayer() {
        scrollView.drawsBackground = false
        collectionView.backgroundColors = [.clear]
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scrollToSelected()
    }

    // MARK: Search

    ///
    /// only once the text has been emptied; every change feeds the query.
    func controlTextDidChange(_ notification: Notification) {
        searchField.placeholderString = searchField.stringValue.isEmpty ? "Search" : nil
        submit(searchField.stringValue)
    }
    /// removeDuplicates, then a 0.2-second debounce before filtering
    ///
    func submit(_ query: String) {
        guard query != pendingQuery ?? lastQuery else { return }
        pendingQuery = query
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyQuery() }
        }
    }
    func applyQuery() {
        debounce?.invalidate(); debounce = nil
        guard let query = pendingQuery else { return }
        pendingQuery = nil; lastQuery = query
        model = SidebarEmojiModel.shared.filtered(query)
    }

    // MARK: Grid

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { model.emojis.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: SidebarEmojiItem.identifier, for: indexPath)
        if let item = item as? SidebarEmojiItem, model.emojis.indices.contains(indexPath.item) {
            item.emojiType = model.emojis[indexPath.item].emoji
            item.isCurrent = indexPath.item == currentIndex
        }
        return item
    }
    /// 24 + 4 = 28-point cells, ten-point side insets, line spacing 5 and
    ///
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        NSSize(width: SidebarIconPickerMetrics.emojiDimension + SidebarIconPickerMetrics.horizontalPadding,
               height: SidebarIconPickerMetrics.emojiDimension + SidebarIconPickerMetrics.horizontalPadding)
    }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, insetForSectionAt section: Int) -> NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat { 5 }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat { 2 }

    ///
    /// picker; any other selects at once. The grid's own selection is cleared.
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        closeSkinTone()
        for indexPath in indexPaths where model.emojis.indices.contains(indexPath.item) {
            let entry = model.emojis[indexPath.item]
            if entry.supportsSkinTones && !SidebarEmojiModel.skinToneExclusions.contains(entry.emoji) {
                showSkinTones(for: entry.emoji, at: indexPath.item)
            } else {
                select(entry.emoji, at: indexPath.item)
            }
        }
        collectionView.deselectItems(at: indexPaths)
        collectionView.reloadItems(at: indexPaths)
    }

    ///
    func select(_ emoji: String, at index: Int) {
        selectedEmoji = emoji
        onEmojiSelected?(emoji)
    }

    private func refreshCurrent() {
        let previous = currentIndex
        currentIndex = model.index(containing: selectedEmoji)
        let changed = Set([previous, currentIndex].compactMap { $0 }).filter { $0 < model.emojis.count }
        if !changed.isEmpty { collectionView.reloadItems(at: Set(changed.map { IndexPath(item: $0, section: 0) })) }
    }

    ///
    /// otherwise an offscreen current cell scrolls to the top.
    func scrollToSelected() {
        guard window != nil, let index = currentIndex else { collectionView.deselectAll(nil); return }
        layoutSubtreeIfNeeded()
        let path = IndexPath(item: index, section: 0)
        if !collectionView.indexPathsForVisibleItems().contains(path) {
            collectionView.scrollToItems(at: [path], scrollPosition: .top)
        }
    }

    ///
    @objc func scrollToCategory(_ sender: NSButton) {
        guard model.categoryStarts.indices.contains(sender.tag), let index = model.categoryStarts[sender.tag] else { return }
        collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .top)
    }

    // MARK: Skin tones

    ///
    private func showSkinTones(for emoji: String, at index: Int) {
        let picker = SidebarSkinToneViewController(variants: SidebarEmojiModel.variants(of: emoji))
        picker.onPick = { [weak self] value in
            guard let self, let info = self.skinTonePopover else { return }
            self.closeSkinTone()
            self.select(value, at: info.anchorIndex)
        }
        let popover = NSPopover()
        popover.contentViewController = picker
        popover.contentSize = SidebarSkinToneViewController.size
        popover.behavior = .transient
        popover.animates = false
        collectionView.layoutSubtreeIfNeeded()
        popover.show(relativeTo: collectionView.frameForItem(at: index), of: collectionView, preferredEdge: .minY)
        skinTonePopover = (popover, index)
    }
    func closeSkinTone() {
        skinTonePopover?.popover.close(); skinTonePopover = nil
    }
    private func closeSkinToneIfScrolledAway() {
        guard let info = skinTonePopover else { return }
        if !collectionView.frameForItem(at: info.anchorIndex).intersects(collectionView.visibleRect) { closeSkinTone() }
    }
}

/// `EmojiStackView`: equal-width category buttons along the bottom with a
/// hairline top border.
@MainActor
final class SidebarEmojiCategoryBar: NSStackView {
    private let topBorder = CALayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        //
        orientation = .horizontal; spacing = 2
        edgeInsets = NSEdgeInsets(top: 5, left: 2, bottom: 0, right: 2)
        alignment = .bottom; distribution = .fillEqually
        wantsLayer = true
        topBorder.borderWidth = 1; topBorder.masksToBounds = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    ///
    /// at 0.25 (sRGB black or white at 0.25).
    override func updateLayer() {
        let height = 1 / (window?.backingScaleFactor ?? 1)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        CATransaction.begin(); CATransaction.setDisableActions(true)
        topBorder.frame = NSRect(x: 0, y: isFlipped ? 0 : bounds.height - height, width: bounds.width, height: height)
        topBorder.borderColor = NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0, alpha: 0.25).cgColor
        if topBorder.superlayer == nil { layer?.addSublayer(topBorder) }
        CATransaction.commit()
    }
    override func layout() { super.layout(); needsDisplay = true }

    ///
    /// ForegroundSecondary for the application's appearance (`.sourceIn`).
    static func glyph(_ code: UInt32) -> NSImage {
        let glyph = SidebarIconCatalog.featherImage(code, size: 14)
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let color = SidebarIconCatalog.foregroundSecondary(dark: dark)
        return NSImage(size: glyph.size, flipped: false) { rect in
            glyph.draw(in: rect)
            color.set(); rect.fill(using: .sourceIn)
            return true
        }
    }
}

///
/// hovered background (GrayA4 unless overridden), clear otherwise.
@MainActor
final class SidebarPickerHoverButton: NSButton {
    var contentInsets = NSEdgeInsets() { didSet { invalidateIntrinsicContentSize() } }
    var hoveredBackgroundColor: NSColor?
    private(set) var hovered = false { didSet { needsDisplay = true } }
    private let trackingOptions: NSTrackingArea.Options

    init(image: NSImage? = nil, title: String = "", trackingOptions: NSTrackingArea.Options) {
        self.trackingOptions = trackingOptions
        super.init(frame: .zero)
        self.image = image; self.title = title
        imagePosition = image == nil ? .noImage : .imageOnly
        isBordered = false; setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 6; layer?.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + contentInsets.left + contentInsets.right,
                      height: base.height + contentInsets.top + contentInsets.bottom)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: trackingOptions, owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = hovered ? (hoveredBackgroundColor ?? SidebarRowAppearance.controlFill(pressed: false, dark: dark)).cgColor : NSColor.clear.cgColor
    }
}

/// `EmojiCollectionViewItem` with its `EmojiCollectionItemView`.
@MainActor
final class SidebarEmojiItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("EmojiCollectionViewItem")
    private let emojiImageView = FirstMouseImageView()
    var emojiType: String? {
        didSet {
            //
            guard emojiType != oldValue else { return }
            emojiImageView.image = emojiType.map { SidebarIconCatalog.emojiImage($0, size: 17) }
            emojiImageView.setAccessibilityLabel(emojiType)
        }
    }
    var isCurrent = false { didSet { (view as? SidebarEmojiItemView)?.isCurrent = isCurrent } }

    override func loadView() { view = SidebarEmojiItemView() }
    override func viewDidLoad() {
        super.viewDidLoad()
        emojiImageView.wantsLayer = true
        emojiImageView.layer?.masksToBounds = false
        emojiImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emojiImageView)
        NSLayoutConstraint.activate([
            emojiImageView.topAnchor.constraint(equalTo: view.topAnchor), emojiImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emojiImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor), emojiImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
    }
    override func prepareForReuse() { super.prepareForReuse(); emojiType = nil }

    final class FirstMouseImageView: NSImageView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

///
/// SidebarItemBackground while hovered, else clear; radius 5, no animation.
@MainActor
final class SidebarEmojiItemView: NSView {
    var isCurrent = false { didSet { needsDisplay = true } }
    private(set) var isHovered = false { didSet { needsDisplay = true } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Tracking options 0x281: entered/exited, always active, visible rect.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.cornerRadius = 5
        layer?.masksToBounds = false
        layer?.backgroundColor = (isCurrent ? SidebarIconCatalog.customizationBackground(dark: dark)
            : isHovered ? SidebarRowAppearance.color(.hovered, dark: dark) : .clear).cgColor
    }
}

///
/// six 28-point buttons, four points apart, centered.
@MainActor
final class SidebarSkinToneViewController: NSViewController {
    static let size = NSSize(width: 198, height: 38)
    let variants: [String]
    var onPick: ((String) -> Void)?
    init(variants: [String]) { self.variants = variants; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.size))
        let stack = NSStackView(); stack.orientation = .horizontal; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for variant in variants {
            let button = SidebarPickerHoverButton(title: variant, trackingOptions: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect])
            button.font = .systemFont(ofSize: 17)
            button.hoveredBackgroundColor = dark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.08)
            button.target = self; button.action = #selector(picked(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 28), button.heightAnchor.constraint(equalToConstant: 28)])
            stack.addArrangedSubview(button)
        }
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: root.centerXAnchor), stack.centerYAnchor.constraint(equalTo: root.centerYAnchor)])
        view = root
    }
    ///
    override func viewDidAppear() { super.viewDidAppear(); view.window?.makeKeyAndOrderFront(view) }
    @objc private func picked(_ sender: NSButton) { onPick?(sender.title) }
}
