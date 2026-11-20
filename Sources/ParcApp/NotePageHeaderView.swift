import AppKit
import Combine

@MainActor
final class NotePageHeaderView: NSView, NoteCanvasHeader {
    private struct Arrangement {
        var cover: NSRect?
        var icon: NSRect?
        var affordances: NSRect?
        var title: NSRect
        var properties: NSRect?
        var height: CGFloat
    }

    static let iconSide: CGFloat = 80
    static let affordanceHeight: CGFloat = NoteTheme.chipHeight

    unowned let editor: NotePageEditor
    let file: NoteFileSession?
    var onTitleChange: ((String) -> Void)?
    var onTitleCommit: ((String) -> Void)?
    let titleView = NotePageTitleView()
    let coverView: NotePageCoverView
    let iconView: NotePageIconView
    let properties: NotePropertiesView
    let addIcon = NoteChip("Add icon", icon: .featherSmile, style: .ghost)
    let addCover = NoteChip("Add cover", icon: .featherImage, style: .ghost)
    let addProperties = NoteChip("Add properties", icon: .symbol("list.bullet.rectangle"), style: .ghost)
    let lockChip = NoteChip("Locked", icon: .symbol("lock.fill"), style: .filled)
    private let affordances = NSView()
    private var applied: NotePageSettings?
    private var subscriptions: Set<AnyCancellable> = []
    private var hoverArea: NSTrackingArea?
    private var isHovered = false
    private var lastHeight: CGFloat = 0
    private var committedTitle: String
    private var commitTimer: Timer?
    private var iconPopover: NotePagePopover?
    private var coverPopover: NotePagePopover?

    init(editor: NotePageEditor, file: NoteFileSession?, title: String? = nil) {
        self.editor = editor
        self.file = file
        coverView = NotePageCoverView(environment: editor.environment)
        iconView = NotePageIconView(environment: editor.environment)
        properties = NotePropertiesView(editor: editor)
        committedTitle = title ?? file?.title ?? ""
        super.init(frame: NSRect(x: 0, y: 0, width: 720, height: 160))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Page Header")
        affordances.wantsLayer = true
        for chip in [addIcon, addCover, addProperties] { affordances.addSubview(chip) }
        affordances.layer?.opacity = 0
        addSubview(coverView)
        addSubview(affordances)
        addSubview(lockChip)
        addSubview(titleView)
        addSubview(properties)
        addSubview(iconView)
        configureTitle()
        configureActions()
        apply(editor.session.page.settings, animated: false)
        subscriptions.insert(editor.session.changes.sink { [weak self] change in
            guard let self, change.kind != .selection, change.kind != .text else { return }
            self.apply(self.editor.session.page.settings, animated: true)
        })
        if let file {
            subscriptions.insert(file.urlChanges.sink { [weak self] url in
                self?.fileDidMove(to: url)
            })
            NotePageHistory.track(file)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var isPlainText: Bool { editor.environment.isPlainText }

    var isEditable: Bool { !editor.isReadOnly }

    var title: String {
        get { titleView.string }
        set {
            committedTitle = newValue
            guard titleView.string != newValue, !titleView.hasMarkedText() else { return }
            titleView.string = newValue
            titleView.needsDisplay = true
            relayoutIfHeightChanged()
        }
    }

    func focusTitle(selectAll: Bool = false) {
        guard let window else { return }
        window.makeFirstResponder(titleView)
        if selectAll { titleView.selectAll(nil) } else { titleView.setSelectedRange(NSRange(location: (titleView.string as NSString).length, length: 0)) }
    }

    func canvasHeaderHeight(width: CGFloat, column: NSRect) -> CGFloat {
        arrangement(width: width, column: column).height
    }

    override var fittingSize: NSSize {
        let column = editor.canvas.contentRect
        let width = bounds.width > 0 ? bounds.width : editor.canvas.bounds.width
        return NSSize(width: width, height: arrangement(width: width, column: column).height)
    }

    private var viewportHeight: CGFloat {
        let height = editor.canvas.enclosingScrollView?.contentSize.height ?? 0
        return height > 0 ? height : 760
    }

    private var settings: NotePageSettings { editor.session.page.settings }

    private var hasCover: Bool { !isPlainText && settings.cover != nil }
    private var hasIcon: Bool { !isPlainText && !(settings.icon ?? "").isEmpty }
    private var showsProperties: Bool { !isPlainText && (!settings.properties.isEmpty || properties.isRevealed) }

    func coverHeight() -> CGFloat {
        min(max((viewportHeight * 0.3).rounded(), 150), 300)
    }

    private func arrangement(width: CGFloat, column rawColumn: NSRect) -> Arrangement {
        let column = rawColumn.width > 0 ? rawColumn : NSRect(x: 0, y: 0, width: width, height: 0)
        var result = Arrangement(title: .zero, height: 0)
        var y: CGFloat = 0
        if hasCover {
            let height = coverHeight()
            result.cover = NSRect(x: 0, y: 0, width: width, height: height)
            y = height
        }
        if isPlainText {
            y += 56
        } else if hasIcon {
            let top = hasCover ? y - Self.iconSide * 0.55 : 52
            result.icon = NSRect(x: column.minX - 6, y: top, width: Self.iconSide, height: Self.iconSide)
            y = top + Self.iconSide + 4
        } else {
            y += hasCover ? 14 : 44
        }
        if !isPlainText {
            result.affordances = NSRect(x: column.minX, y: y, width: column.width, height: Self.affordanceHeight)
            y += Self.affordanceHeight + 6
        }
        let titleHeight = titleView.height(forWidth: column.width)
        result.title = NSRect(x: column.minX, y: y, width: column.width, height: titleHeight)
        y += titleHeight
        if showsProperties {
            y += 8
            let height = properties.preferredHeight(width: column.width + NotePropertiesView.gutter)
            result.properties = NSRect(x: column.minX - NotePropertiesView.gutter, y: y, width: column.width + NotePropertiesView.gutter, height: height)
            y += height
        }
        result.height = ceil(y + 14)
        return result
    }

    override func layout() {
        super.layout()
        let column = convert(editor.canvas.contentRect, from: editor.canvas)
        let layout = arrangement(width: bounds.width, column: column)
        NoteAnimation.withoutAnimation {
            coverView.isHidden = layout.cover == nil
            if let cover = layout.cover {
                coverView.frame = cover
                coverView.controlsInset = max(16, bounds.width - column.maxX)
            }
            iconView.isHidden = layout.icon == nil
            if let icon = layout.icon { iconView.frame = icon }
            affordances.isHidden = layout.affordances == nil
            if let row = layout.affordances {
                affordances.frame = row
                var x: CGFloat = -8
                let editable = isEditable
                for chip in [addIcon, addCover, addProperties] {
                    let visible = editable && chipVisible(chip)
                    chip.isHidden = !visible
                    guard visible else { continue }
                    let size = chip.intrinsicContentSize
                    chip.frame = NSRect(x: x, y: 0, width: size.width, height: size.height)
                    x += size.width + 2
                }
                let lockSize = lockChip.intrinsicContentSize
                lockChip.isHidden = !settings.locked
                lockChip.frame = NSRect(x: settings.locked ? row.minX : row.maxX - lockSize.width, y: row.minY,
                                        width: lockSize.width, height: lockSize.height)
            } else {
                lockChip.isHidden = true
            }
            titleView.frame = layout.title
            properties.isHidden = layout.properties == nil
            if let frame = layout.properties { properties.frame = frame }
        }
        lastHeight = layout.height
    }

    private func chipVisible(_ chip: NoteChip) -> Bool {
        if chip === addIcon { return !hasIcon }
        if chip === addCover { return !hasCover }
        return !showsProperties
    }

    func relayoutIfHeightChanged() {
        let height = canvasHeaderHeight(width: bounds.width, column: convert(editor.canvas.contentRect, from: editor.canvas))
        needsLayout = true
        guard abs(height - lastHeight) > 0.5 else { return }
        lastHeight = height
        editor.canvas.invalidateCanvasLayout(animated: !NoteAnimation.reduceMotion && window != nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    private func setHovered(_ value: Bool) {
        guard value != isHovered else { return }
        isHovered = value
        refreshAffordanceVisibility()
    }

    private func refreshAffordanceVisibility() {
        let visible = isHovered && isEditable
        guard let layer = affordances.layer else { return }
        NoteAnimation.fade(layer, to: visible ? 1 : 0, duration: NoteAnimation.hoverDuration)
    }

    private func configureTitle() {
        titleView.string = committedTitle
        titleView.onEdit = { [weak self] text in
            guard let self else { return }
            self.relayoutIfHeightChanged()
            self.onTitleChange?(text)
            self.scheduleCommit()
        }
        titleView.onEndEditing = { [weak self] in self?.commitTitle(ending: true) }
        titleView.onReturn = { [weak self] in self?.splitIntoBody() }
        titleView.onMoveDown = { [weak self] in self?.moveIntoBody(offset: 0) }
    }

    private func configureActions() {
        addIcon.setToolTip("Add icon")
        addCover.setToolTip("Add cover")
        addProperties.setToolTip("Add properties")
        lockChip.setToolTip("Locked. Click to unlock")
        addIcon.onPress = { [weak self] in self?.addRandomIcon() }
        addCover.onPress = { [weak self] in self?.addRandomCover() }
        addProperties.onPress = { [weak self] in self?.revealProperties() }
        lockChip.onPress = { [weak self] in
            self?.editor.session.updateSettings(name: "Unlock Page") { $0.locked = false }
        }
        iconView.onPress = { [weak self] in self?.presentIconPicker() }
        coverView.onChange = { [weak self] in
            guard let self else { return }
            self.presentCoverPicker(from: self.coverView.changeChip)
        }
        coverView.onRemove = { [weak self] in
            self?.editor.session.updateSettings(name: "Remove Cover") { $0.cover = nil }
        }
        coverView.onSavePosition = { [weak self] position in
            self?.editor.session.updateSettings(name: "Reposition Cover") { settings in
                settings.cover?.position = position
            }
        }
        properties.onHeightChange = { [weak self] in self?.relayoutIfHeightChanged() }
    }

    func apply(_ next: NotePageSettings, animated: Bool) {
        let previous = applied
        applied = next
        let font = NoteTheme.titleFont(next.font, small: next.smallText)
        if titleView.font != font {
            titleView.font = font
            titleView.typingAttributes[.font] = font
        }
        let editable = !editor.isReadOnly
        titleView.isEditable = editable
        titleView.isSelectable = true
        coverView.isEditable = editable
        iconView.isEditable = editable
        if previous?.cover?.source != next.cover?.source || previous == nil {
            coverView.show(next.cover, animated: animated && previous?.cover != nil)
            if animated, previous?.cover == nil, next.cover != nil { coverView.revealAnimated() }
        } else if let cover = next.cover, previous?.cover?.position != cover.position {
            coverView.setPosition(cover.position)
        }
        if previous?.icon != next.icon {
            iconView.icon = isPlainText ? nil : next.icon
            if animated, next.icon != nil { NoteAnimation.pop(iconView, from: NoteAnimation.checkPopScale, spring: .pop) }
        }
        properties.isEditable = editable
        properties.reload(next.properties)
        if previous?.locked != next.locked {
            refreshAffordanceVisibility()
            if animated, next.locked, let layer = lockChip.layer { NoteAnimation.pop(layer, from: 0.9, spring: .pill) }
        }
        relayoutIfHeightChanged()
    }

    private func fileDidMove(to url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        committedTitle = name
        guard window?.firstResponder !== titleView, titleView.string != name else { return }
        titleView.string = name
        relayoutIfHeightChanged()
    }

    private func scheduleCommit() {
        commitTimer?.invalidate()
        commitTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitTitle() }
        }
    }

    func commitTitle() {
        commitTitle(ending: window?.firstResponder !== titleView)
    }

    private func commitTitle(ending: Bool) {
        commitTimer?.invalidate()
        commitTimer = nil
        guard !titleView.hasMarkedText() else { return }
        let value = titleView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            if ending { showCommittedTitle() }
            return
        }
        if value != committedTitle {
            let previous = committedTitle
            committedTitle = value
            if let onTitleCommit {
                onTitleCommit(value)
            } else if let file {
                do {
                    _ = try file.rename(to: value)
                } catch {
                    committedTitle = previous
                    editor.onError?(error)
                }
            }
            if let file { committedTitle = file.title }
        }
        if ending { showCommittedTitle() }
    }

    private func showCommittedTitle() {
        guard titleView.string != committedTitle else { return }
        titleView.string = committedTitle
        titleView.needsDisplay = true
        relayoutIfHeightChanged()
    }

    private func splitIntoBody() {
        guard isEditable else { return }
        let text = titleView.string as NSString
        let caret = titleView.selectedRange()
        let tail = caret.location < text.length ? text.substring(from: caret.location + caret.length) : ""
        if !tail.isEmpty {
            let head = text.substring(to: caret.location)
            titleView.string = head
            titleView.didChangeText()
            let block = NoteBlock.paragraph(NoteText(tail.trimmingCharacters(in: .whitespaces)))
            editor.session.insertBlocks([block], .top(0), select: .caret(NotePosition(block.id, 0)))
            commitTitle()
            editor.focus(NotePosition(block.id, 0))
            return
        }
        commitTitle()
        if let first = editor.session.page.blocks.first, first.kind == .paragraph, first.text.isEmpty, first.children.isEmpty {
            editor.focus(NotePosition(first.id, 0))
            return
        }
        let block = NoteBlock.paragraph()
        editor.session.insertBlocks([block], .top(0), select: .caret(NotePosition(block.id, 0)))
        editor.focus(NotePosition(block.id, 0))
    }

    private func moveIntoBody(offset: Int) {
        commitTitle()
        let page = editor.session.page
        if let first = page.visibleTextOrder().first, page.flattened().first?.id == first || page.blocks.first?.id == first {
            editor.session.setSelection(.caret(NotePosition(first, offset)))
            editor.focus(NotePosition(first, offset))
            return
        }
        guard isEditable else { return }
        let block = NoteBlock.paragraph()
        editor.session.insertBlocks([block], .top(0), select: .caret(NotePosition(block.id, 0)))
        editor.focus(NotePosition(block.id, 0))
    }

    func addRandomIcon() {
        guard isEditable, let emoji = NoteEmojiCatalog.shared.random() else { return }
        let character = NoteEmojiCatalog.shared.character(for: emoji)
        NoteEmojiCatalog.shared.recordUse(character)
        editor.session.updateSettings(name: "Add Icon") { $0.icon = character }
    }

    func addRandomCover() {
        guard isEditable else { return }
        let style = NoteCoverGallery.randomStyle()
        NoteCoverPicker.importGalleryCover(style, environment: editor.environment) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let source):
                self.editor.session.updateSettings(name: "Add Cover") { $0.cover = NoteCover(source: source, position: 0.5) }
            case .failure(let error):
                self.editor.onError?(error)
            }
        }
    }

    func revealProperties() {
        guard isEditable else { return }
        properties.isRevealed = true
        relayoutIfHeightChanged()
        layoutSubtreeIfNeeded()
        properties.beginAdding()
    }

    func presentIconPicker() {
        guard isEditable, !isPlainText else { return }
        iconPopover?.close(animated: false)
        let picker = NotePageIconPicker(environment: editor.environment, current: settings.icon)
        let popover = NotePagePopover(content: picker)
        popover.exempt(iconView)
        picker.onPick = { [weak self, weak popover] icon in
            NoteEmojiCatalog.shared.recordUse(icon)
            self?.editor.session.updateSettings(name: "Change Icon") { $0.icon = icon }
            popover?.close()
        }
        picker.onImage = { [weak self, weak popover] source in
            self?.editor.session.updateSettings(name: "Change Icon") { $0.icon = source }
            popover?.close()
        }
        picker.onRemove = { [weak self, weak popover] in
            self?.editor.session.updateSettings(name: "Remove Icon") { $0.icon = nil }
            popover?.close()
        }
        picker.onCancel = { [weak popover] in popover?.close() }
        picker.onError = { [weak self] error in self?.editor.onError?(error) }
        popover.onClose = { [weak self] in self?.iconPopover = nil }
        iconPopover = popover
        let overlay = editor.canvas.overlayView
        popover.present(in: overlay, anchor: overlay.convert(iconView.bounds, from: iconView), edge: .below)
        picker.focus()
    }

    func presentCoverPicker(from anchorView: NSView) {
        guard isEditable, !isPlainText else { return }
        coverPopover?.close(animated: false)
        let picker = NoteCoverPicker(environment: editor.environment, hasCover: settings.cover != nil)
        let popover = NotePagePopover(content: picker)
        popover.exempt(anchorView)
        picker.onChoose = { [weak self, weak popover] source in
            self?.editor.session.updateSettings(name: "Change Cover") { $0.cover = NoteCover(source: source, position: 0.5) }
            popover?.close()
        }
        picker.onRemove = { [weak self, weak popover] in
            self?.editor.session.updateSettings(name: "Remove Cover") { $0.cover = nil }
            popover?.close()
        }
        picker.onError = { [weak self] error in self?.editor.onError?(error) }
        popover.onClose = { [weak self] in
            self?.coverPopover = nil
            self?.coverView.controlsPinned = false
        }
        coverPopover = popover
        coverView.controlsPinned = true
        let overlay = editor.canvas.overlayView
        popover.present(in: overlay, anchor: overlay.convert(anchorView.bounds, from: anchorView), edge: .below, alignment: .trailing)
    }
}

@MainActor
final class NotePageTitleView: NSTextView {
    var onEdit: ((String) -> Void)?
    var onEndEditing: (() -> Void)?
    var onReturn: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var placeholder = "Untitled" { didSet { needsDisplay = true } }
    private let titleUndo = UndoManager()

    convenience init() {
        self.init(usingTextLayoutManager: false)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        isAutomaticQuoteSubstitutionEnabled = true
        isAutomaticDashSubstitutionEnabled = true
        isContinuousSpellCheckingEnabled = true
        usesFindBar = false
        isIncrementalSearchingEnabled = false
        font = NoteTheme.titleFont(.standard)
        textColor = NoteTheme.titleInk
        insertionPointColor = NoteTheme.caret
        selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
        typingAttributes = [.font: NoteTheme.titleFont(.standard), .foregroundColor: NoteTheme.titleInk]
        setAccessibilityLabel("Title")
        setAccessibilityPlaceholderValue(placeholder)
    }

    override var undoManager: UndoManager? { titleUndo }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    func height(forWidth width: CGFloat) -> CGFloat {
        let font = self.font ?? NoteTheme.titleFont(.standard)
        let line = ceil(font.ascender - font.descender + font.leading)
        guard let layoutManager, let textContainer, width > 0 else { return line }
        if abs(textContainer.containerSize.width - width) > 0.5 {
            textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        guard !string.isEmpty else { return max(line, ceil(layoutManager.defaultLineHeight(for: font))) }
        layoutManager.ensureLayout(for: textContainer)
        return max(line, ceil(layoutManager.usedRect(for: textContainer).height))
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let text = string as? String {
            super.insertText(NotePageExport.flattenedTitle(text), replacementRange: replacementRange)
        } else if let text = string as? NSAttributedString {
            super.insertText(NotePageExport.flattenedTitle(text.string), replacementRange: replacementRange)
        } else {
            super.insertText(string, replacementRange: replacementRange)
        }
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let text = pboard.string(forType: .string) else { return false }
        let flat = NotePageExport.flattenedTitle(text)
        insertText(flat, replacementRange: rangeForUserTextChange)
        return true
    }

    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        insertText(NotePageExport.flattenedTitle(text), replacementRange: rangeForUserTextChange)
    }

    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }

    override func pasteAsRichText(_ sender: Any?) { paste(sender) }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)), #selector(insertLineBreak(_:)),
             #selector(insertParagraphSeparator(_:)):
            onReturn?()
        case #selector(insertTab(_:)):
            onMoveDown?()
        case #selector(moveDown(_:)):
            let caret = selectedRange().location
            if isOnLastLine(caret) { onMoveDown?() } else { super.doCommand(by: selector) }
        case #selector(cancelOperation(_:)):
            window?.makeFirstResponder(nil)
        default:
            super.doCommand(by: selector)
        }
    }

    func isOnLastLine(_ offset: Int) -> Bool {
        guard let layoutManager, let textContainer else { return true }
        let length = (string as NSString).length
        guard length > 0 else { return true }
        layoutManager.ensureLayout(for: textContainer)
        let glyph = layoutManager.glyphIndexForCharacter(at: min(offset, length - 1))
        let last = layoutManager.glyphIndexForCharacter(at: length - 1)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let lastLine = layoutManager.lineFragmentRect(forGlyphAt: last, effectiveRange: nil)
        if offset >= length, layoutManager.extraLineFragmentTextContainer != nil { return true }
        return abs(line.minY - lastLine.minY) < 1
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        guard !hasMarkedText() else { return }
        onEdit?(string)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onEndEditing?() }
        return resigned
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        let font = self.font ?? NoteTheme.titleFont(.standard)
        (placeholder as NSString).draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y),
                                       withAttributes: [.font: font, .foregroundColor: NoteTheme.titlePlaceholderInk])
    }
}

@MainActor
final class NotePageImageLoader {
    static let shared = NotePageImageLoader()
    private let cache = NSCache<NSURL, NSImage>()
    private var waiting: [URL: [(NSImage?) -> Void]] = [:]
    nonisolated static let maximumBytes = 40 * 1024 * 1024

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        if let image = cached(url) { completion(image); return }
        if waiting[url] != nil { waiting[url]?.append(completion); return }
        waiting[url] = [completion]
        Task { [weak self] in
            let data = await Self.fetch(url)
            let image = data.flatMap { NSImage(data: $0) }
            guard let self else { return }
            if let image { self.cache.setObject(image, forKey: url as NSURL) }
            let callbacks = self.waiting.removeValue(forKey: url) ?? []
            for callback in callbacks { callback(image) }
        }
    }

    nonisolated private static func fetch(_ url: URL) async -> Data? {
        if url.isFileURL {
            return await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumBytes else { return nil }
                return try? Data(contentsOf: url)
            }.value
        }
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= maximumBytes else { return nil }
        return data
    }

    static func isImageSource(_ value: String) -> Bool { NotePageExport.isImageSource(value) }
}

@MainActor
final class NotePageIconView: NSView {
    let environment: NoteEnvironment
    var onPress: (() -> Void)?
    var isEditable = true { didSet { window?.invalidateCursorRects(for: self); needsDisplay = true } }
    var icon: String? { didSet { if icon != oldValue { reloadImage(); needsDisplay = true; updateAccessibility() } } }
    private var image: NSImage?
    private var isHovered = false
    private var isPressed = false
    private var hoverArea: NSTrackingArea?

    init(environment: NoteEnvironment) {
        self.environment = environment
        super.init(frame: NSRect(x: 0, y: 0, width: NotePageHeaderView.iconSide, height: NotePageHeaderView.iconSide))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private func updateAccessibility() {
        let name = icon.flatMap { NoteEmojiCatalog.shared.entry(for: $0)?.displayName }
        setAccessibilityLabel(name.map { "Page icon, \($0)" } ?? (icon == nil ? "Page icon" : "Page icon, image"))
        setAccessibilityHelp("Change icon")
    }

    private func reloadImage() {
        image = nil
        guard let icon, NotePageImageLoader.isImageSource(icon), let url = environment.resolve(icon) else { return }
        if let cached = NotePageImageLoader.shared.cached(url) { image = cached; return }
        NotePageImageLoader.shared.load(url) { [weak self] loaded in
            guard let self, self.icon == icon else { return }
            self.image = loaded
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEditable && (isHovered || isPressed) {
            (isPressed ? NoteTheme.pressedFill : NoteTheme.hoverFill).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
        guard let icon else { return }
        if NotePageImageLoader.isImageSource(icon) {
            let box = bounds.insetBy(dx: 8, dy: 8)
            guard let image, image.size.width > 0, image.size.height > 0 else {
                NoteTheme.mediaPlaceholderFill.setFill()
                NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
                return
            }
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        let font = NSFont(name: "AppleColorEmoji", size: 62) ?? .systemFont(ofSize: 62)
        let text = NSAttributedString(string: icon, attributes: [.font: font])
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func cursorUpdate(with event: NSEvent) {
        if isEditable { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }

    override func resetCursorRects() {
        if isEditable { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditable else { return }
        isPressed = true
        needsDisplay = true
        press(true)
    }

    private func press(_ down: Bool) {
        guard let layer else { return }
        let center = NoteAnimation.layerPoint(NSPoint(x: bounds.midX, y: bounds.midY), in: self)
        let target = down ? NoteAnimation.scaleTransform(NoteAnimation.pressedScale, about: center) : CATransform3DIdentity
        NoteAnimation.animate(layer, "transform", to: NSValue(caTransform3D: target), spring: .press, key: NoteAnimation.keyPrefix + "icon.press")
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        needsDisplay = true
        press(false)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEditable else { return false }
        onPress?()
        return true
    }
}

@MainActor
final class NotePageCoverView: NSView {
    let environment: NoteEnvironment
    var onChange: (() -> Void)?
    var onRemove: (() -> Void)?
    var onSavePosition: ((Double) -> Void)?
    var isEditable = true { didSet { refreshControls(animated: false) } }
    var controlsInset: CGFloat = 16 { didSet { needsLayout = true } }
    var controlsPinned = false { didSet { refreshControls(animated: true) } }
    let changeChip = NoteChip("Change cover", style: .ghost)
    let repositionChip = NoteChip("Reposition", style: .ghost)
    let removeChip = NoteChip("Remove", style: .ghost)
    let saveChip = NoteChip("Save position", style: .ghost)
    let cancelChip = NoteChip("Cancel", style: .ghost)
    private let controls = NotePageChromeGroup()
    private let hint = NotePageChromeGroup()
    private let hintLabel = NSTextField(labelWithString: "Drag image to reposition")
    private let failureLabel = NSTextField(labelWithString: "Can't load this cover")
    private let imageLayer = CALayer()
    private var image: NSImage?
    private var cover: NoteCover?
    private var position: Double = 0.5
    private var isHovered = false
    private var hoverArea: NSTrackingArea?
    private(set) var isRepositioning = false
    private var dragStart: (point: NSPoint, position: Double)?
    private var loadFailed = false

    init(environment: NoteEnvironment) {
        self.environment = environment
        super.init(frame: NSRect(x: 0, y: 0, width: 720, height: 220))
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.needsDisplayOnBoundsChange = false
        layer?.addSublayer(imageLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Page cover")
        hintLabel.font = NoteTheme.chromeFont(12.5)
        hintLabel.textColor = NoteTheme.menuInk
        hint.addSubview(hintLabel)
        hint.isHidden = true
        failureLabel.font = NoteTheme.chromeFont(12.5)
        failureLabel.textColor = NoteTheme.tertiaryInk
        failureLabel.isHidden = true
        addSubview(failureLabel)
        addSubview(controls)
        addSubview(hint)
        controls.wantsLayer = true
        controls.layer?.opacity = 0
        changeChip.onPress = { [weak self] in self?.onChange?() }
        repositionChip.onPress = { [weak self] in self?.beginRepositioning() }
        removeChip.onPress = { [weak self] in self?.onRemove?() }
        saveChip.onPress = { [weak self] in self?.endRepositioning(save: true) }
        cancelChip.onPress = { [weak self] in self?.endRepositioning(save: false) }
        refreshControls(animated: false)
        refreshBackground()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { isRepositioning }

    func show(_ next: NoteCover?, animated: Bool) {
        if isRepositioning { endRepositioning(save: false) }
        cover = next
        position = next?.position ?? 0.5
        loadFailed = false
        failureLabel.isHidden = true
        guard let next, let url = environment.resolve(next.source) else {
            setImage(nil, animated: false)
            loadFailed = next != nil
            failureLabel.isHidden = !loadFailed
            return
        }
        if let cached = NotePageImageLoader.shared.cached(url) {
            setImage(cached, animated: animated)
            return
        }
        NotePageImageLoader.shared.load(url) { [weak self] loaded in
            guard let self, self.cover?.source == next.source else { return }
            self.loadFailed = loaded == nil
            self.failureLabel.isHidden = loaded != nil
            self.setImage(loaded, animated: true)
        }
    }

    func setPosition(_ value: Double) {
        guard !isRepositioning else { return }
        position = min(max(value, 0), 1)
        layoutImage()
    }

    func revealAnimated() {
        guard let layer, !NoteAnimation.reduceMotion else { return }
        NoteAnimation.withoutAnimation { layer.opacity = 0 }
        NoteAnimation.fade(layer, to: 1, duration: NoteAnimation.revealDuration)
    }

    private func setImage(_ next: NSImage?, animated: Bool) {
        image = next
        let contents = next?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if animated, window != nil {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = NoteAnimation.reduceMotion ? NoteAnimation.reducedFadeDuration : NoteAnimation.revealDuration
            imageLayer.add(transition, forKey: NoteAnimation.keyPrefix + "cover.swap")
        }
        NoteAnimation.withoutAnimation { imageLayer.contents = contents }
        layoutImage()
    }

    private func imageFrame(for value: Double) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0, bounds.width > 0 else { return bounds }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let overflow = size.height - bounds.height
        return CGRect(x: (bounds.width - size.width) / 2, y: -overflow * value, width: size.width, height: size.height)
    }

    private var overflow: CGFloat {
        imageFrame(for: 0).height - bounds.height
    }

    private func layoutImage() {
        NoteAnimation.withoutAnimation {
            var frame = imageFrame(for: position)
            if layer?.isGeometryFlipped == false { frame.origin.y = bounds.height - frame.maxY }
            imageLayer.frame = frame
        }
    }

    override func layout() {
        super.layout()
        layoutImage()
        let editing = isRepositioning
        controls.arrange(editing ? [saveChip, cancelChip] : [changeChip, repositionChip, removeChip])
        controls.setFrameOrigin(NSPoint(x: bounds.width - controlsInset - controls.frame.width, y: bounds.height - controls.frame.height - 12))
        let hintSize = hintLabel.intrinsicContentSize
        hint.frame = NSRect(x: (bounds.width - hintSize.width - 24) / 2, y: (bounds.height - 30) / 2, width: hintSize.width + 24, height: 30)
        hintLabel.frame = NSRect(x: 12, y: (30 - hintSize.height) / 2, width: hintSize.width, height: hintSize.height)
        let failure = failureLabel.intrinsicContentSize
        failureLabel.frame = NSRect(x: (bounds.width - failure.width) / 2, y: (bounds.height - failure.height) / 2, width: failure.width, height: failure.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
    }

    private func refreshBackground() {
        NoteAnimation.withoutAnimation { layer?.backgroundColor = NoteTheme.resolved(NoteTheme.mediaPlaceholderFill, in: self) }
    }

    private func refreshControls(animated: Bool) {
        let visible = isEditable && (isHovered || isRepositioning || controlsPinned)
        repositionChip.isEnabled = image != nil && overflow > 1
        guard let layer = controls.layer else { return }
        if animated { NoteAnimation.fade(layer, to: visible ? 1 : 0, duration: NoteAnimation.hoverDuration) }
        else { NoteAnimation.withoutAnimation { layer.opacity = visible ? 1 : 0 } }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshControls(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshControls(animated: true)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit.isDescendant(of: hint) { return self }
        if hit.isDescendant(of: controls), (controls.layer?.opacity ?? 0) < 0.01 { return self }
        return hit
    }

    override func cursorUpdate(with event: NSEvent) {
        if isRepositioning { (dragStart == nil ? NSCursor.openHand : NSCursor.closedHand).set() } else { super.cursorUpdate(with: event) }
    }

    override func resetCursorRects() {
        if isRepositioning { addCursorRect(bounds, cursor: dragStart == nil ? .openHand : .closedHand) }
    }

    func beginRepositioning() {
        guard isEditable, image != nil, overflow > 1 else { return }
        isRepositioning = true
        hint.isHidden = false
        if let layer = hint.layer { NoteAnimation.withoutAnimation { layer.opacity = 0 }; NoteAnimation.fade(layer, to: 1, duration: NoteAnimation.hoverDuration) }
        needsLayout = true
        refreshControls(animated: true)
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
    }

    func endRepositioning(save: Bool) {
        guard isRepositioning else { return }
        isRepositioning = false
        dragStart = nil
        hint.isHidden = true
        if save { onSavePosition?(position) } else {
            position = cover?.position ?? 0.5
            layoutImage()
        }
        needsLayout = true
        refreshControls(animated: true)
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        guard isRepositioning else { super.mouseDown(with: event); return }
        dragStart = (convert(event.locationInWindow, from: nil), position)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isRepositioning, let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        let distance = overflow
        guard distance > 1 else { return }
        let delta = Double((point.y - start.point.y) / distance) * (isFlipped ? 1 : -1)
        position = min(max(start.position - delta, 0), 1)
        layoutImage()
    }

    override func mouseUp(with event: NSEvent) {
        guard isRepositioning else { return }
        dragStart = nil
        NSCursor.openHand.set()
    }

    override func keyDown(with event: NSEvent) {
        guard isRepositioning else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53: endRepositioning(save: false)
        case 36, 76: endRepositioning(save: true)
        case 126: position = max(0, position - 0.05); layoutImage()
        case 125: position = min(1, position + 0.05); layoutImage()
        default: super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRepositioning, dragStart == nil { endRepositioning(save: true) }
        return super.resignFirstResponder()
    }
}
