import AppKit
import ParcCore
import ParcNotes

@MainActor
enum EaselHistoryPanel {
    private static var openPopover: NotePagePopover?

    static func present(editor: EaselEditorViewController) {
        openPopover?.close(animated: false)
        guard !editor.session.isClosed, let history = EaselHistories.history(for: editor.session.document.id) else { NSSound.beep(); return }
        history.flush()
        let view = EaselHistoryView(editor: editor, history: history)
        let popover = NotePagePopover(content: view)
        view.onClose = { [weak popover] in popover?.close() }
        popover.onKeyDown = { [weak view] event in view?.handleKeyDown(event) ?? false }
        popover.onClose = { openPopover = nil }
        openPopover = popover
        let host = editor.view
        let area = editor.canvas.enclosingScrollView.map { host.convert($0.frame, from: $0.superview) } ?? host.bounds
        popover.present(in: host, anchor: NSRect(x: area.midX - 1, y: area.minY + 24, width: 2, height: 0), edge: .below, alignment: .center)
    }

    static func restore(_ version: EaselVersion, editor: EaselEditorViewController, history: EaselHistory) throws {
        let id = editor.session.document.id
        let snapshot = try history.document(version, of: id)
        guard editor.canvas.finishEditingForTransfer() else { throw EaselStoreError.invalidDocument("finish the current edit first") }
        let current = editor.session.document
        history.record(current, savedAt: Date(), wait: true)
        let icon = editor.session.restorableIcon(snapshot.icon)
        var next = current
        next.title = snapshot.title
        next.icon = icon
        next.items = snapshot.items
        next.pages = snapshot.pages
        guard next != current else { return }
        editor.canvas.prepareReplacement(next) { [weak editor] in
            guard let editor, !editor.session.isClosed, editor.session.document.id == id else { return }
            do {
                try editor.session.perform("Restore Version") { document in
                    document.title = snapshot.title
                    document.icon = icon
                    document.items = snapshot.items
                    document.pages = snapshot.pages
                }
            } catch {
                editor.canvas.onError?(error)
            }
        }
    }

    static func preview(of snapshot: EaselDocument, editor: EaselEditorViewController) -> NSImage? {
        var document = snapshot
        document.icon = nil
        var assets: [String: Data] = [:]
        for id in Set(document.items.compactMap(\.assetID)) {
            guard let data = try? editor.session.assetData(id) else { return nil }
            assets[id] = data
        }
        guard let session = try? EaselSession(inMemory: document, assets: assets) else { return nil }
        let canvas = EaselCanvasView(session: session)
        canvas.appearance = editor.view.effectiveAppearance
        guard let pdf = canvas.exportPDF(title: document.title) else { return nil }
        return NSImage(data: pdf)
    }
}

@MainActor
final class EaselHistoryView: NSView, NoteFloatingPanelContent {
    static let size = NSSize(width: 680, height: 470)
    static let listWidth: CGFloat = 240

    weak var editor: EaselEditorViewController?
    let history: EaselHistory
    var onClose: (() -> Void)?
    var preferredSizeDidChange: (() -> Void)?
    private(set) var versions: [EaselVersion] = []
    private(set) var selected = 0
    private var previews: [String: NSImage] = [:]
    private let titleLabel = NSTextField(labelWithString: "Easel History")
    private let subtitleLabel = NSTextField(labelWithString: "Parc keeps a snapshot every few minutes while you work.")
    private let list = NoteMenuList()
    private let divider = NSView()
    private let headerRule = NSView()
    private let frameView = NSView()
    private let preview = NSImageView()
    private let previewNote = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "No snapshots yet. Keep working and Parc will tuck one away every few minutes.")
    private let restore = NoteChip("Restore", icon: .symbol("clock.arrow.circlepath"), style: .filled)
    private let cancel = NoteChip("Close", style: .ghost)

    init(editor: EaselEditorViewController, history: EaselHistory) {
        self.editor = editor
        self.history = history
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Easel History")
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
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = 10
        frameView.layer?.cornerCurve = .continuous
        frameView.layer?.masksToBounds = true
        frameView.layer?.borderWidth = 1
        preview.imageScaling = .scaleProportionallyDown
        preview.imageAlignment = .alignCenter
        preview.setAccessibilityLabel("Version preview")
        previewNote.font = NoteTheme.nunitoRegular(13)
        previewNote.textColor = NoteTheme.menuTertiaryInk
        previewNote.alignment = .center
        emptyLabel.font = NoteTheme.nunitoRegular(13.5)
        emptyLabel.textColor = NoteTheme.menuTertiaryInk
        emptyLabel.alignment = .center
        restore.onPress = { [weak self] in self?.restoreSelected() }
        restore.setToolTip("Restore this version", shortcut: "↩")
        cancel.onPress = { [weak self] in self?.onClose?() }
        for rule in [divider, headerRule] {
            rule.wantsLayer = true
            addSubview(rule)
        }
        frameView.addSubview(preview)
        frameView.addSubview(previewNote)
        for view in [titleLabel, subtitleLabel, list, frameView, emptyLabel, restore, cancel] as [NSView] { addSubview(view) }
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

    private static func objects(_ count: Int) -> String { count == 1 ? "1 object" : "\(count) objects" }

    func reload() {
        guard let editor else { return }
        let document = editor.session.document
        versions = [EaselVersion(id: "", savedAt: document.modifiedAt, itemCount: document.items.count)] + history.versions(of: document.id)
        let now = Date()
        let currentIcon = editor.session.storeDirectory.map { NoteIcon.easel(document.id, directory: $0) } ?? NoteIcon.easelMark
        list.items = versions.enumerated().map { index, version in
            let phrase = NoteRelativeTime.phrase(for: version.savedAt, now: now)
            let title = index == 0 ? "Current version" : phrase.prefix(1).uppercased() + phrase.dropFirst()
            let subtitle = Self.absolute.string(from: version.savedAt) + " · " + Self.objects(version.itemCount)
            return NoteMenuList.Item(id: String(index), title: title, subtitle: subtitle,
                                     icon: index == 0 ? currentIcon : .symbol("clock"), isChecked: index == selected)
        }
        let empty = versions.count <= 1
        emptyLabel.isHidden = !empty
        select(index: empty ? 0 : 1)
    }

    private func select(id: String) {
        guard let index = Int(id) else { return }
        select(index: index)
    }

    func select(index: Int) {
        guard versions.indices.contains(index), let editor else { return }
        selected = index
        list.setItems(list.items.enumerated().map { offset, item in
            var copy = item
            copy.isChecked = offset == index
            return copy
        }, keepingHighlight: true)
        let version = versions[index]
        let image: NSImage?
        if let cached = previews[version.id] {
            image = cached
        } else {
            let document = index == 0 ? editor.session.document : try? history.document(version, of: editor.session.document.id)
            image = document.flatMap { EaselHistoryPanel.preview(of: $0, editor: editor) }
            if let image { previews[version.id] = image }
        }
        preview.image = image
        previewNote.isHidden = image != nil
        previewNote.stringValue = image == nil ? "This version can’t be previewed." : ""
        preview.setAccessibilityValue(Self.objects(version.itemCount))
        restore.isEnabled = index > 0 && !editor.session.isClosed
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 36 || event.keyCode == 76 {
            if restore.isEnabled { restoreSelected() }
            return true
        }
        if event.keyCode == 125 || event.keyCode == 126 {
            select(index: min(max(0, selected + (event.keyCode == 125 ? 1 : -1)), versions.count - 1))
            return true
        }
        return list.handleKeyDown(event)
    }

    private func restoreSelected() {
        guard versions.indices.contains(selected), selected > 0 else { return }
        guard let editor, !editor.session.isClosed else { onClose?(); return }
        do {
            try EaselHistoryPanel.restore(versions[selected], editor: editor, history: history)
            onClose?()
        } catch {
            editor.canvas.onError?(error)
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
        frameView.frame = NSRect(x: Self.listWidth + 17, y: top + 17, width: bounds.width - Self.listWidth - 34, height: bodyHeight - 24)
        preview.frame = frameView.bounds.insetBy(dx: 8, dy: 8)
        let noteHeight = ceil(previewNote.intrinsicContentSize.height)
        previewNote.frame = NSRect(x: 8, y: (frameView.bounds.height - noteHeight) / 2, width: frameView.bounds.width - 16, height: noteHeight)
        emptyLabel.frame = NSRect(x: 16, y: top + bodyHeight / 2 - 30, width: Self.listWidth - 32, height: 60)
        let chipY = bounds.height - footer + (footer - NoteTheme.chipHeight) / 2
        let restoreWidth = restore.intrinsicContentSize.width, cancelWidth = cancel.intrinsicContentSize.width
        restore.frame = NSRect(x: bounds.width - 14 - restoreWidth, y: chipY, width: restoreWidth, height: NoteTheme.chipHeight)
        cancel.frame = NSRect(x: restore.frame.minX - 6 - cancelWidth, y: chipY, width: cancelWidth, height: NoteTheme.chipHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
        redisplayChromeSubtree()
    }

    private func refreshAppearance() {
        NoteAnimation.withoutAnimation {
            for rule in [divider, headerRule] { rule.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self) }
            frameView.layer?.backgroundColor = NoteTheme.resolved(EaselAppearance.paper, in: self)
            frameView.layer?.borderColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self)
        }
    }
}
