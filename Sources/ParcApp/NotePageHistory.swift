import AppKit
import Combine

struct NotePageVersion: Hashable {
    var date: Date
    var url: URL
    var isCurrent: Bool
    var computer: String?
}

@MainActor
final class NotePageHistory {
    private static var recorders: [String: NotePageHistory] = [:]
    private static var openPopover: NotePagePopover?

    let file: NoteFileSession
    var policy = NotePageHistoryPolicy()
    private(set) var lastRecordedText: String?
    private(set) var lastRecordedAt: Date?
    private var originalText: String?
    private var originalDate: Date?
    private var originalSaved = false
    private var previousState: NoteFileSaveState = .saved
    private var subscriptions: Set<AnyCancellable> = []
    private var idleTimer: Timer?
    private var isSupported = true

    private init(file: NoteFileSession) {
        self.file = file
        let disk = Self.readText(file.url)
        originalText = disk?.text
        originalDate = disk?.date
        if let latest = Self.versions(of: file.url).first(where: { !$0.isCurrent }) {
            lastRecordedText = Self.readText(latest.url)?.text
            lastRecordedAt = latest.date
        }
        subscriptions.insert(file.$state.sink { [weak self] state in self?.stateDidChange(state) })
        subscriptions.insert(file.urlChanges.sink { url in Self.rekey(file: file, to: url) })
    }

    private static var terminationObserver: NSObjectProtocol?

    @discardableResult
    static func track(_ file: NoteFileSession) -> NotePageHistory {
        observeTermination()
        let key = file.url.standardizedFileURL.path
        if let existing = recorders[key] { return existing }
        let recorder = NotePageHistory(file: file)
        recorders[key] = recorder
        return recorder
    }

    private static func observeTermination() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                                     queue: .main) { _ in
            MainActor.assumeIsolated {
                for recorder in recorders.values { recorder.record(.close) }
            }
        }
    }

    static func recorder(for file: NoteFileSession) -> NotePageHistory? {
        recorders[file.url.standardizedFileURL.path]
    }

    static func fileWillClose(_ file: NoteFileSession) {
        let key = file.url.standardizedFileURL.path
        guard let recorder = recorders.removeValue(forKey: key) else { return }
        recorder.record(.close)
        recorder.stop()
    }

    private static func rekey(file: NoteFileSession, to url: URL) {
        guard let entry = recorders.first(where: { $0.value.file === file }) else { return }
        recorders.removeValue(forKey: entry.key)
        recorders[url.standardizedFileURL.path] = entry.value
    }

    private func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        subscriptions.removeAll()
    }

    private func stateDidChange(_ state: NoteFileSaveState) {
        defer { previousState = state }
        guard state == .saved, previousState == .saving || previousState == .unsaved else { return }
        record(.save)
    }

    func record(_ reason: NotePageHistoryReason) {
        guard isSupported, let current = Self.readText(file.url) else { return }
        preserveOriginal(current: current.text)
        let now = Date()
        guard policy.shouldRecord(reason, current: current.text, lastRecorded: lastRecordedText, lastRecordedAt: lastRecordedAt, now: now) else {
            if reason == .save, let last = lastRecordedText, NotePageHistoryPolicy.isMeaningful(from: last, to: current.text) { scheduleIdle() }
            return
        }
        idleTimer?.invalidate()
        idleTimer = nil
        do {
            try NSFileVersion.addOfItem(at: file.url, withContentsOf: file.url, options: [])
            lastRecordedText = current.text
            lastRecordedAt = now
        } catch {
            isSupported = false
        }
    }

    func recordNow() {
        guard isSupported, let current = Self.readText(file.url) else { return }
        if let last = lastRecordedText, !NotePageHistoryPolicy.isMeaningful(from: last, to: current.text) { return }
        record(.close)
    }

    private func preserveOriginal(current: String) {
        guard !originalSaved, let original = originalText else { return }
        guard NotePageHistoryPolicy.isMeaningful(from: original, to: current) else { return }
        originalSaved = true
        if let last = lastRecordedText, !NotePageHistoryPolicy.isMeaningful(from: last, to: original) { return }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-note-\(UUID().uuidString)")
            .appendingPathExtension(file.url.pathExtension)
        do {
            try Data(original.utf8).write(to: temporary, options: .atomic)
            if let originalDate { try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: temporary.path) }
            try NSFileVersion.addOfItem(at: file.url, withContentsOf: temporary, options: [])
            lastRecordedText = original
            lastRecordedAt = originalDate ?? Date()
        } catch {
            isSupported = (error as NSError).domain != NSCocoaErrorDomain || (error as NSError).code != NSFeatureUnsupportedError
        }
        try? FileManager.default.removeItem(at: temporary)
    }

    private func scheduleIdle() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: policy.idleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.record(.idle) }
        }
    }

    static func readText(_ url: URL) -> (text: String, date: Date?)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (text, date)
    }

    static func versions(of url: URL) -> [NotePageVersion] {
        var result: [NotePageVersion] = []
        if let current = NSFileVersion.currentVersionOfItem(at: url) {
            result.append(NotePageVersion(date: current.modificationDate ?? Date(), url: url, isCurrent: true, computer: nil))
        }
        let others = (NSFileVersion.otherVersionsOfItem(at: url) ?? []).filter { !$0.isConflict }
        for version in others {
            result.append(NotePageVersion(date: version.modificationDate ?? .distantPast, url: version.url, isCurrent: false,
                                          computer: version.localizedNameOfSavingComputer))
        }
        return result.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.date > rhs.date
        }
    }

    static func present(editor: NotePageEditor, file: NoteFileSession) {
        openPopover?.close(animated: false)
        try? file.flush()
        track(file).recordNow()
        let view = NotePageHistoryView(editor: editor, file: file)
        let popover = NotePagePopover(content: view)
        view.onClose = { [weak popover] in popover?.close() }
        popover.onKeyDown = { [weak view] event in view?.handleKeyDown(event) ?? false }
        popover.onClose = { openPopover = nil }
        openPopover = popover
        let overlay = editor.canvas.overlayView
        let clipped = overlay.visibleRect.intersection(overlay.bounds)
        let visible = clipped.isEmpty ? overlay.bounds : clipped
        let anchor = NSRect(x: visible.midX - 1, y: visible.minY + 40, width: 2, height: 0)
        popover.present(in: overlay, anchor: anchor, edge: .below, alignment: .center)
    }

    static func restore(_ version: NotePageVersion, editor: NotePageEditor, file: NoteFileSession?) throws {
        guard !editor.isReadOnly else { return }
        guard let text = readText(version.url)?.text else { throw CocoaError(.fileReadUnknown) }
        if let file { recorder(for: file)?.recordNow() }
        let restored = editor.environment.isPlainText ? NotePlainText.parse(text) : NoteMarkdown.parse(text)
        let page = restored.blocks.isEmpty ? NotePage(settings: restored.settings, blocks: [.paragraph()]) : restored
        editor.session.edit("Restore Version", affected: Set(editor.session.page.documentOrder()).union(page.documentOrder()), selection: NotePageSelection.none) {
            $0 = page
        }
    }
}

@MainActor
enum NotePagePreviewRenderer {
    static func attributed(_ page: NotePage, title: String?, width: CGFloat) -> NSAttributedString {
        let settings = page.settings
        let result = NSMutableAttributedString()
        if let title, !title.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 10
            var heading = title
            if let icon = settings.icon, !NotePageImageLoader.isImageSource(icon) { heading = icon + " " + title }
            result.append(NSAttributedString(string: heading + "\n", attributes: [
                .font: NoteTheme.titleFont(settings.font, small: true), .foregroundColor: NoteTheme.titleInk, .paragraphStyle: paragraph]))
        }
        var numbers: [Int: Int] = [:]
        func walk(_ blocks: [NoteBlock], depth: Int) {
            for block in blocks {
                if block.kind != .numberedItem { numbers[depth] = nil }
                append(block, depth: depth, numbers: &numbers)
                if block.kind == .columns || block.kind == .column {
                    walk(block.children, depth: depth)
                } else {
                    walk(block.children, depth: depth + 1)
                }
            }
        }
        func append(_ block: NoteBlock, depth: Int, numbers: inout [Int: Int]) {
            let paragraph = NSMutableParagraphStyle()
            let indent = CGFloat(depth) * 22
            paragraph.firstLineHeadIndent = indent
            paragraph.headIndent = indent
            paragraph.paragraphSpacing = 6
            paragraph.lineHeightMultiple = 1.15
            var base: [NSAttributedString.Key: Any] = [.font: NoteTheme.bodyFont(settings.font, small: true), .foregroundColor: NoteTheme.ink,
                                                       .paragraphStyle: paragraph]
            var prefix = ""
            switch block.kind {
            case .heading:
                base[.font] = NoteTheme.headingFont(block.props.level, font: settings.font, small: true)
                paragraph.paragraphSpacingBefore = 8
                if block.props.toggleable { prefix = "▸ " }
            case .bulletedItem: prefix = "•  "
            case .numberedItem:
                let value = (numbers[depth] ?? (block.props.listStart ?? 1) - 1) + 1
                numbers[depth] = value
                prefix = "\(value).  "
            case .todo:
                prefix = block.props.checked ? "☑  " : "☐  "
                if block.props.checked {
                    base[.foregroundColor] = NoteTheme.todoDoneInk
                    base[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            case .toggle: prefix = "▸  "
            case .quote:
                paragraph.firstLineHeadIndent = indent + 14
                paragraph.headIndent = indent + 14
                base[.foregroundColor] = NoteTheme.secondaryInk
                prefix = "▎ "
            case .callout: prefix = (block.calloutDisplayIcon ?? "💡") + "  "
            case .code, .equation, .html, .raw:
                base[.font] = NoteTheme.codeFont(size: 12.5)
                base[.backgroundColor] = NoteTheme.codeBackground
                base[.foregroundColor] = NoteTheme.codeInk
            case .divider:
                result.append(NSAttributedString(string: String(repeating: "─", count: 24) + "\n", attributes: [
                    .font: NoteTheme.bodyFont(.standard, small: true), .foregroundColor: NoteTheme.dividerLine, .paragraphStyle: paragraph]))
                return
            case .image, .video, .audio, .file, .bookmark, .embed, .pageLink:
                let name = block.props.caption.plainText.isEmpty
                    ? (block.props.bookmark?.title ?? block.props.target ?? block.props.source.map { ($0 as NSString).lastPathComponent } ?? "")
                    : block.props.caption.plainText
                let symbol: String
                switch block.kind {
                case .image: symbol = "🖼"
                case .video: symbol = "🎬"
                case .audio: symbol = "🎧"
                case .bookmark, .embed: symbol = "🔗"
                case .pageLink: symbol = "📄"
                default: symbol = "📎"
                }
                base[.foregroundColor] = NoteTheme.secondaryInk
                result.append(NSAttributedString(string: symbol + "  " + name + "\n", attributes: base))
                return
            case .table:
                base[.font] = NoteTheme.bodyFont(settings.font, small: true)
                let rows = block.props.table?.rows.map { $0.map(\.plainText).joined(separator: "   ·   ") } ?? []
                result.append(NSAttributedString(string: rows.joined(separator: "\n") + "\n", attributes: base))
                return
            case .tableOfContents:
                base[.foregroundColor] = NoteTheme.tertiaryInk
                result.append(NSAttributedString(string: "Table of contents\n", attributes: base))
                return
            case .columns, .column:
                return
            case .paragraph:
                break
            }
            if let color = block.color {
                base[color.isBackground ? .backgroundColor : .foregroundColor] = NoteTheme.color(color)
            }
            let line = NSMutableAttributedString(string: prefix, attributes: base)
            line.append(styled(block.text, base: base))
            line.append(NSAttributedString(string: "\n", attributes: base))
            result.append(line)
        }
        walk(page.blocks, depth: 0)
        return result
    }

    static func styled(_ text: NoteText, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let string = text.string as NSString
        let font = base[.font] as? NSFont ?? NoteTheme.bodyFont(.standard, small: true)
        for run in text.runs() {
            var attributes = base
            let marks = run.marks
            let piece = marks.atom?.fallbackText ?? string.substring(with: NSRange(location: run.range.lowerBound, length: run.range.count))
            var traits: NSFontTraitMask = []
            if marks.bold { traits.insert(.boldFontMask) }
            if marks.italic { traits.insert(.italicFontMask) }
            if !traits.isEmpty { attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: traits) }
            if marks.code {
                attributes[.font] = NoteTheme.inlineCodeFont(relativeTo: font)
                attributes[.foregroundColor] = NoteTheme.inlineCodeInk
                attributes[.backgroundColor] = NoteTheme.inlineCodeBackground
            }
            if marks.underline || marks.link != nil || marks.atom != nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if marks.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if marks.link != nil { attributes[.foregroundColor] = NoteTheme.link }
            if let color = marks.color { attributes[color.isBackground ? .backgroundColor : .foregroundColor] = NoteTheme.color(color) }
            result.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return result
    }
}

@MainActor
final class NotePageHistoryView: NSView, NoteFloatingPanelContent {
    static let size = NSSize(width: 660, height: 460)
    static let listWidth: CGFloat = 230

    unowned let editor: NotePageEditor
    let file: NoteFileSession
    var onClose: (() -> Void)?
    var preferredSizeDidChange: (() -> Void)?
    private(set) var versions: [NotePageVersion] = []
    private(set) var selected = 0
    private let titleLabel = NSTextField(labelWithString: "Page History")
    private let subtitleLabel = NSTextField(labelWithString: "Parc keeps a snapshot every few minutes while you write.")
    private let list = NoteMenuList()
    private let divider = NSView()
    private let headerRule = NSView()
    private let scroll = NSScrollView()
    private let preview = NSTextView(usingTextLayoutManager: false)
    private let emptyLabel = NSTextField(wrappingLabelWithString: "No snapshots yet. Keep writing and Parc will tuck one away every few minutes.")
    private let restore = NoteChip("Restore", icon: .symbol("clock.arrow.circlepath"), style: .filled)
    private let cancel = NoteChip("Close", style: .ghost)
    private let lockedHint = NSTextField(labelWithString: "Unlock the page to restore an older version.")

    init(editor: NotePageEditor, file: NoteFileSession) {
        self.editor = editor
        self.file = file
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Page History")
        titleLabel.font = NoteTheme.nunitoExtraBold(16)
        titleLabel.textColor = NoteTheme.menuInk
        subtitleLabel.font = NoteTheme.nunitoRegular(12.5)
        subtitleLabel.textColor = NoteTheme.menuTertiaryInk
        list.rowStyle = .detailed
        list.fixedWidth = Self.listWidth
        list.maximumHeight = Self.size.height
        list.onActivate = { [weak self] item in self?.select(id: item.id) }
        list.onHighlight = { [weak self] item in
            guard let self, let item, NSApp.currentEvent?.type == .keyDown else { return }
            self.select(id: item.id)
        }
        list.onCancel = { [weak self] in self?.onClose?() }
        preview.isEditable = false
        preview.isSelectable = true
        preview.drawsBackground = false
        preview.textContainerInset = NSSize(width: 18, height: 16)
        preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = false
        preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true
        preview.setAccessibilityLabel("Version preview")
        scroll.documentView = preview
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        emptyLabel.font = NoteTheme.nunitoRegular(13.5)
        emptyLabel.textColor = NoteTheme.menuTertiaryInk
        emptyLabel.alignment = .center
        lockedHint.font = NoteTheme.nunitoRegular(12)
        lockedHint.textColor = NoteTheme.menuTertiaryInk
        restore.onPress = { [weak self] in self?.restoreSelected() }
        restore.setToolTip("Restore this version", shortcut: "↩")
        cancel.onPress = { [weak self] in self?.onClose?() }
        for rule in [divider, headerRule] {
            rule.wantsLayer = true
            addSubview(rule)
        }
        for view in [titleLabel, subtitleLabel, list, scroll, emptyLabel, restore, cancel, lockedHint] as [NSView] { addSubview(view) }
        reload()
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size }
    override var fittingSize: NSSize { Self.size }

    private static let absolute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    func reload() {
        versions = NotePageHistory.versions(of: file.url)
        let now = Date()
        list.items = versions.enumerated().map { index, version in
            let phrase = NoteRelativeTime.phrase(for: version.date, now: now)
            let title = version.isCurrent ? "Current version" : phrase.prefix(1).uppercased() + phrase.dropFirst()
            var subtitle = Self.absolute.string(from: version.date)
            if let computer = version.computer, !version.isCurrent { subtitle += " · " + computer }
            return NoteMenuList.Item(id: String(index), title: title, subtitle: subtitle,
                                     icon: .symbol(version.isCurrent ? "doc.text.fill" : "clock"), isChecked: index == selected)
        }
        let empty = versions.count <= 1
        emptyLabel.isHidden = !empty
        select(index: empty ? 0 : min(1, versions.count - 1))
    }

    private func select(id: String) {
        guard let index = Int(id) else { return }
        select(index: index)
    }

    func select(index: Int) {
        guard versions.indices.contains(index) else {
            preview.textStorage?.setAttributedString(NSAttributedString())
            refreshButtons()
            return
        }
        selected = index
        list.setItems(list.items.enumerated().map { offset, item in
            var copy = item
            copy.isChecked = offset == index
            return copy
        }, keepingHighlight: true)
        let version = versions[index]
        let text = NotePageHistory.readText(version.url)?.text ?? ""
        let page = editor.environment.isPlainText ? NotePlainText.parse(text) : NoteMarkdown.parse(text)
        let rendered = NotePagePreviewRenderer.attributed(page, title: file.title, width: Self.size.width - Self.listWidth)
        preview.textStorage?.setAttributedString(rendered)
        preview.scroll(.zero)
        refreshButtons()
    }

    private func refreshButtons() {
        let canRestore = versions.indices.contains(selected) && !versions[selected].isCurrent && !editor.isReadOnly
        restore.isEnabled = canRestore
        lockedHint.isHidden = !editor.isReadOnly
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if (event.keyCode == 36 || event.keyCode == 76), restore.isEnabled {
            restoreSelected()
            return true
        }
        if event.keyCode == 125 || event.keyCode == 126 {
            select(index: min(max(0, selected + (event.keyCode == 125 ? 1 : -1)), versions.count - 1))
            return true
        }
        return list.handleKeyDown(event)
    }

    private func restoreSelected() {
        guard versions.indices.contains(selected), !versions[selected].isCurrent else { return }
        do {
            try NotePageHistory.restore(versions[selected], editor: editor, file: file)
            onClose?()
        } catch {
            editor.onError?(error)
        }
    }

    override func layout() {
        super.layout()
        let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
        titleLabel.frame = NSRect(x: 16, y: 14, width: bounds.width - 32, height: titleHeight)
        let subtitleHeight = ceil(subtitleLabel.intrinsicContentSize.height)
        subtitleLabel.frame = NSRect(x: 16, y: titleLabel.frame.maxY + 2, width: bounds.width - 32, height: subtitleHeight)
        let top = subtitleLabel.frame.maxY + 12
        headerRule.frame = NSRect(x: 0, y: top, width: bounds.width, height: 1)
        let footer: CGFloat = 50
        let bodyHeight = bounds.height - top - 1 - footer
        list.frame = NSRect(x: 0, y: top + 1, width: Self.listWidth, height: bodyHeight)
        divider.frame = NSRect(x: Self.listWidth, y: top + 1, width: 1, height: bounds.height - top - 1)
        scroll.frame = NSRect(x: Self.listWidth + 1, y: top + 1, width: bounds.width - Self.listWidth - 1, height: bodyHeight)
        preview.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(preview.frame.height, scroll.contentSize.height))
        emptyLabel.frame = NSRect(x: 16, y: top + bodyHeight / 2 - 30, width: Self.listWidth - 32, height: 60)
        let chipY = bounds.height - footer + (footer - NoteTheme.chipHeight) / 2
        let restoreWidth = restore.intrinsicContentSize.width, cancelWidth = cancel.intrinsicContentSize.width
        restore.frame = NSRect(x: bounds.width - 14 - restoreWidth, y: chipY, width: restoreWidth, height: NoteTheme.chipHeight)
        cancel.frame = NSRect(x: restore.frame.minX - 6 - cancelWidth, y: chipY, width: cancelWidth, height: NoteTheme.chipHeight)
        let hintHeight = ceil(lockedHint.intrinsicContentSize.height)
        lockedHint.frame = NSRect(x: Self.listWidth + 16, y: bounds.height - footer + (footer - hintHeight) / 2,
                                  width: max(0, cancel.frame.minX - Self.listWidth - 24), height: hintHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
        redisplayChromeSubtree()
    }

    private func refreshAppearance() {
        NoteAnimation.withoutAnimation {
            for rule in [divider, headerRule] { rule.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self) }
        }
    }
}
