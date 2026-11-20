import AppKit
import Combine

extension NoteTheme {
    static let syncedAccent = adaptive("SyncedAccent", light: rgb(0xE0533A), dark: rgb(0xF2876C))
    static let syncedHoverLine = adaptive("SyncedHoverLine", light: rgb(0xE0533A, 0.32), dark: rgb(0xF2876C, 0.38))
    static let syncedMissingLine = adaptive("SyncedMissingLine", light: rgb(0x1F1B2E, 0.28), dark: rgb(0xEDEBFA, 0.3))
    static let syncedBadgeFill = adaptive("SyncedBadgeFill", light: rgb(0xE0533A, 0.12), dark: rgb(0xF2876C, 0.18))
    nonisolated static let syncedBorderOutset: CGFloat = 8
    nonisolated static let syncedHeaderHeight: CGFloat = 22
}

@MainActor
final class NoteSyncedController {
    enum Phase: Equatable { case hidden, hover, editing, missing }

    private weak var editor: NotePageEditor?
    private let engine = NoteSyncedBlocks.shared
    private var chromes: [NoteBlockID: NoteSyncedChromeView] = [:]
    private var infos: [NoteBlockID: NoteSyncedInfo] = [:]
    private var hovered: NoteBlockID?
    private var pinned: NoteBlockID?
    private var subscriptions = Set<AnyCancellable>()
    private var panel: NoteFloatingPanel?

    init(editor: NotePageEditor) {
        self.editor = editor
        engine.changes.sink { [weak self] in self?.engineDidChange() }.store(in: &subscriptions)
    }

    var session: NotePageSession? { editor?.session }

    func sessionDidChange(_ change: NotePageChange) {
        if change.kind != .selection && change.kind != .text { infos.removeAll() }
        refresh()
    }

    func layoutDidChange() { refresh() }

    func pointerMoved(to point: NSPoint) {
        let next = site(at: point)
        guard next != hovered else { return }
        hovered = next
        refresh()
    }

    func pointerExited() {
        guard hovered != nil else { return }
        if let window = editor?.canvas.window, let id = hovered, let chrome = chromes[id],
           chrome.bounds.contains(chrome.convert(window.mouseLocationOutsideOfEventStream, from: nil)) { return }
        hovered = nil
        refresh()
    }

    func dismiss() {
        panel?.dismiss(animated: false)
        panel = nil
        pinned = nil
        for chrome in chromes.values { chrome.removeFromSuperview() }
        chromes.removeAll()
    }

    private func engineDidChange() {
        infos.removeAll()
        refresh()
    }

    private func site(at point: NSPoint) -> NoteBlockID? {
        guard let editor else { return nil }
        let layout = editor.canvas.canvasLayout
        let outset = NoteTheme.syncedBorderOutset
        for site in editor.session.page.syncedSites() {
            guard let frame = layout.outerFrame(of: site.id) else { continue }
            let box = frame.insetBy(dx: -outset - 4, dy: -NoteTheme.syncedHeaderHeight / 2)
            if box.contains(point) { return site.id }
        }
        return nil
    }

    private var editingSite: NoteBlockID? {
        guard let editor, editor.ownsFocus || pinned != nil else { return nil }
        let page = editor.session.page
        switch editor.session.selection {
        case .text(_, let head): return page.syncedSite(containing: head.block)
        case .blocks(let ids):
            let sites = Set(ids.compactMap(page.syncedSite(containing:)))
            return sites.count == 1 ? sites.first : nil
        case .cells(let table, _, _): return page.syncedSite(containing: table)
        case .none: return nil
        }
    }

    func info(for id: NoteBlockID) -> NoteSyncedInfo? {
        if let cached = infos[id] { return cached }
        guard let session, let value = engine.info(for: id, in: session) else { return nil }
        infos[id] = value
        return value
    }

    private func refresh() {
        guard let editor else { return }
        let page = editor.session.page
        let layout = editor.canvas.canvasLayout
        let editing = editingSite
        var wanted: [NoteBlockID: Phase] = [:]
        for site in page.syncedSites() {
            guard layout.outerFrame(of: site.id) != nil else { continue }
            let missing = info(for: site.id)?.isMissing == true
            if site.id == editing || site.id == pinned { wanted[site.id] = .editing }
            else if site.id == hovered { wanted[site.id] = missing ? .missing : .hover }
            else if missing { wanted[site.id] = .missing }
        }
        for (id, chrome) in chromes where wanted[id] == nil {
            chromes[id] = nil
            chrome.hide()
        }
        for (id, phase) in wanted {
            guard let frame = layout.outerFrame(of: id), let info = info(for: id) else { continue }
            let chrome: NoteSyncedChromeView
            if let existing = chromes[id] {
                chrome = existing
            } else {
                chrome = NoteSyncedChromeView(site: id, controller: self)
                editor.canvas.overlayView.addSubview(chrome, positioned: .below, relativeTo: nil)
                chromes[id] = chrome
            }
            chrome.isReadOnly = editor.isReadOnly
            chrome.update(info: info, phase: phase, missing: info.isMissing)
            chrome.place(around: frame)
        }
    }

    func showNotes(for id: NoteBlockID, from anchor: NSRect) {
        guard let info = info(for: id), !info.notes.isEmpty else { return }
        let originalKey = info.originalURL.map(NoteFilePaths.key(for:))
        let items = info.notes.enumerated().map { index, url -> NoteMenuList.Item in
            let isOriginal = originalKey != nil && NoteFilePaths.key(for: url) == originalKey
            return NoteMenuList.Item(id: String(index), title: url.deletingPathExtension().lastPathComponent,
                                     subtitle: isOriginal ? "ORIGINAL" : nil, icon: .symbol(isOriginal ? "doc.text.fill" : "doc.text"),
                                     section: index == 0 ? "Synced in" : nil,
                                     accessibilityLabel: url.deletingPathExtension().lastPathComponent + (isOriginal ? ", original" : ""))
        }
        present(items, from: anchor, site: id) { [weak self] item in
            guard let self, let index = Int(item.id), info.notes.indices.contains(index) else { return }
            let url = info.notes[index]
            let isOriginal = originalKey != nil && NoteFilePaths.key(for: url) == originalKey
            self.open(url, anchor: isOriginal ? self.originalAnchor(of: id) : nil)
        }
    }

    func showActions(for id: NoteBlockID, from anchor: NSRect) {
        guard let editor, let block = editor.session.page.block(id), let info = info(for: id) else { return }
        let editable = !editor.isReadOnly
        var items: [NoteMenuList.Item] = [NoteMenuList.Item(id: "copy", title: "Copy and Sync", icon: .symbol("doc.on.doc"))]
        if block.isSyncedCopy {
            if info.isMissing {
                items.append(NoteMenuList.Item(id: "retry", title: "Look for the Original Again", icon: .symbol("magnifyingglass")))
            } else {
                items.append(NoteMenuList.Item(id: "original", title: "Go to Original", icon: .symbol("arrow.up.forward.square")))
            }
            if editable { items.append(NoteMenuList.Item(id: "unsync", title: "Unsync", icon: .symbol("scissors"), separatorBefore: true)) }
        } else if editable {
            items.append(NoteMenuList.Item(id: "unsyncAll", title: "Unsync All", icon: .symbol("scissors"), separatorBefore: true))
        }
        if editable {
            items.append(NoteMenuList.Item(id: "delete", title: "Delete", icon: .symbol("trash"), shortcut: "⌫", isDestructive: true,
                                           separatorBefore: !items.contains { $0.separatorBefore }))
        }
        present(items, from: anchor, site: id) { [weak self] item in
            guard let self else { return }
            switch item.id {
            case "copy": self.copyAndSync(id)
            case "original": self.goToOriginal(id)
            case "retry": self.lookAgain()
            case "unsync": self.unsync(id)
            case "unsyncAll": self.unsyncAll(id)
            case "delete": self.delete(id)
            default: break
            }
        }
    }

    private func present(_ items: [NoteMenuList.Item], from anchor: NSRect, site: NoteBlockID,
                         activate: @escaping (NoteMenuList.Item) -> Void) {
        guard let editor else { return }
        panel?.dismiss(animated: false)
        let list = NoteMenuList()
        list.items = items
        list.minimumWidth = 200
        let card = NoteFloatingPanel(content: list)
        list.onActivate = { [weak self, weak card] item in
            card?.dismiss(animated: true)
            self?.panel = nil
            self?.pinned = nil
            activate(item)
            self?.refresh()
        }
        list.onCancel = { [weak self, weak card] in
            card?.dismiss(animated: true)
            self?.panel = nil
            self?.pinned = nil
            self?.refresh()
        }
        card.onDismiss = { [weak self, weak card] in
            guard let self, self.panel === card else { return }
            self.panel = nil
            self.pinned = nil
            self.refresh()
        }
        panel = card
        pinned = site
        list.prepare(origin: .pointer)
        card.present(in: editor.canvas.overlayView, anchor: anchor, edge: .below)
        refresh()
    }

    @discardableResult
    func copyAndSync(_ id: NoteBlockID) -> Bool {
        guard let editor else { return false }
        guard let reference = engine.reference(for: id, in: editor.session) else {
            editor.handles.presentToast?(.standard("This note is read-only, so its synced block can’t get a copy yet."))
            return false
        }
        let environment = editor.environment
        let html = NotePageHTML.fragment(reference.children, assets: { environment.resolve($0) })
        let payload = NoteClipboard.payload(for: [reference], inline: false,
                                            base: environment.documentURL?.deletingLastPathComponent(), plainTextFile: false, html: html)
        NoteClipboard.write(payload, to: editor.pasteboard)
        editor.handles.presentToast?(.standard("Copied and synced", icon: "arrow.triangle.2.circlepath",
                                               subLabel: "Paste it into any note to keep it in sync."))
        infos.removeAll()
        refresh()
        return true
    }

    func turnIntoSynced(_ ids: [NoteBlockID]) {
        guard let editor, !editor.isReadOnly else { return }
        guard editor.session.turnIntoSynced(ids) != nil else { NSSound.beep(); return }
    }

    func unsync(_ id: NoteBlockID) {
        guard let editor, !editor.isReadOnly else { return }
        editor.session.unsync(id)
    }

    func unsyncAll(_ id: NoteBlockID) {
        guard let editor, !editor.isReadOnly else { return }
        let copies = engine.unsyncAll(id, in: editor.session)
        let title: String
        switch copies {
        case 0: title = "Unsynced"
        case 1: title = "Unsynced 1 copy"
        default: title = "Unsynced \(copies) copies"
        }
        editor.handles.presentToast?(.undoable(title))
    }

    func goToOriginal(_ id: NoteBlockID) {
        guard let info = info(for: id), let url = info.originalURL else { return }
        open(url, anchor: info.anchor)
    }

    private func originalAnchor(of id: NoteBlockID) -> String? { info(for: id)?.anchor }

    private func lookAgain() {
        engine.reconcileAll()
        infos.removeAll()
        refresh()
    }

    private func delete(_ id: NoteBlockID) {
        guard let editor, !editor.isReadOnly else { return }
        editor.session.deleteBlocks([id])
        if let caret = editor.session.selection.caret { editor.focus(caret) }
    }

    private func open(_ url: URL, anchor: String?) {
        guard let editor else { return }
        var target = URL(fileURLWithPath: url.path)
        if let anchor, var components = URLComponents(url: target, resolvingAgainstBaseURL: false) {
            components.fragment = anchor
            target = components.url ?? target
        }
        if let here = editor.environment.documentURL, NoteFilePaths.key(for: here) == NoteFilePaths.key(for: target), let anchor {
            editor.reveal(anchor: anchor)
            return
        }
        editor.open(target)
    }

    func linkToOriginalBlock(_ id: NoteBlockID) -> URL? {
        guard let editor, let site = editor.session.page.syncedSite(containing: id), site != id,
              editor.session.page.block(site)?.isSyncedCopy == true,
              let found = engine.originalSession(for: site, in: editor.session), let url = engine.url(of: found.session) else { return nil }
        let originalID = NoteSyncedBlocks.mix(id, site)
        guard found.session.page.contains(originalID), let anchor = found.session.ensureAnchor(for: originalID) else { return nil }
        var components = URLComponents(url: URL(fileURLWithPath: url.path), resolvingAgainstBaseURL: false)
        components?.fragment = anchor
        return components?.url
    }

    func clipboardBlocks(_ blocks: [NoteBlock], keepingOriginals: Bool) -> [NoteBlock] {
        guard let editor else { return blocks }
        let document = editor.environment.documentURL
        guard !keepingOriginals else { return blocks.map { $0.portableSyncedTargets(documentURL: document) } }
        return editor.session.syncedClipboardBlocks(blocks, documentURL: document)
    }

    func pastedBlocks(_ blocks: [NoteBlock], into selection: NotePageSelection) -> [NoteBlock] {
        guard let editor else { return blocks }
        let localized = blocks.map { $0.localizingSyncedTargets(documentURL: editor.environment.documentURL) }
        let target: NoteBlockID?
        switch selection {
        case .text(_, let head): target = head.block
        case .blocks(let ids): target = ids.first
        case .cells(let table, _, _): target = table
        case .none: target = nil
        }
        guard editor.isPlainText || target.flatMap(editor.session.page.syncedSite(containing:)) != nil else { return localized }
        return Self.unwrappingSynced(localized)
    }

    func droppedBlocks(_ blocks: [NoteBlock], at target: NoteCanvasDropTarget?) -> [NoteBlock] {
        guard let editor else { return blocks }
        let localized = blocks.map { $0.localizingSyncedTargets(documentURL: editor.environment.documentURL) }
        let page = editor.session.page
        var inside = editor.isPlainText
        switch target?.action {
        case .move(let insertion)?:
            switch insertion {
            case .before(let id), .after(let id): inside = inside || page.parent(of: id).flatMap(page.syncedSite(containing:)) != nil
            case .firstChild(let id), .lastChild(let id): inside = inside || page.syncedSite(containing: id) != nil
            case .top: break
            }
        case .placeBeside(let id, _)?:
            inside = inside || page.syncedSite(containing: id) != nil
        case nil:
            break
        }
        return inside ? Self.unwrappingSynced(localized) : localized
    }

    static func unwrappingSynced(_ blocks: [NoteBlock]) -> [NoteBlock] {
        blocks.flatMap { block -> [NoteBlock] in
            if block.kind == .synced { return unwrappingSynced(block.children) }
            var copy = block
            copy.children = unwrappingSynced(block.children)
            return [copy]
        }
    }
}

@MainActor
final class NoteSyncedChromeView: NSView {
    let site: NoteBlockID
    private weak var controller: NoteSyncedController?
    private let border = CAShapeLayer()
    private let label = NoteSyncedLabelButton()
    private let badge = NoteSyncedBadge()
    private let tools = NoteSyncedToolStrip()
    private var phase: NoteSyncedController.Phase = .hidden
    private var shown = false
    var isReadOnly = false

    init(site: NoteBlockID, controller: NoteSyncedController) {
        self.site = site
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        border.fillColor = nil
        border.lineWidth = 1.5
        layer?.addSublayer(border)
        addSubview(label)
        addSubview(badge)
        addSubview(tools)
        label.onPress = { [weak self] in
            guard let self else { return }
            self.controller?.showNotes(for: self.site, from: self.convert(self.label.frame, to: self.superview))
        }
        tools.copy.onPress = { [weak self] in
            guard let self else { return }
            self.tools.copy.flash()
            self.controller?.copyAndSync(self.site)
        }
        tools.more.onPress = { [weak self] in
            guard let self else { return }
            self.controller?.showActions(for: self.site, from: self.convert(self.tools.frame, to: self.superview))
        }
        alphaValue = 0
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0.01 else { return nil }
        let local = convert(point, from: superview)
        for control in [label, tools] as [NSView] where !control.isHidden && control.frame.contains(local) {
            return control.hitTest(convert(local, to: control.superview)) ?? control
        }
        return nil
    }

    func update(info: NoteSyncedInfo, phase next: NoteSyncedController.Phase, missing: Bool) {
        let count = info.notes.count
        if missing {
            label.configure(title: "Can’t find the original", icon: "exclamationmark.triangle", tint: NoteTheme.secondaryInk, enabled: false)
        } else if count == 0 {
            label.configure(title: info.isOriginal ? "Synced block · copy it anywhere" : "Synced in this note",
                            icon: "arrow.triangle.2.circlepath", tint: NoteTheme.syncedAccent, enabled: false)
        } else {
            label.configure(title: "Editing in ↙ \(count) other \(count == 1 ? "note" : "notes")", icon: nil,
                            tint: NoteTheme.syncedAccent, enabled: true)
        }
        label.setToolTipText(missing ? "Its note moved or the block was deleted. You’re seeing the last saved copy." :
            (count == 0 ? nil : "See where else this lives"))
        badge.isHidden = !info.isOriginal
        tools.copy.isHidden = false
        tools.more.isHidden = false
        setAccessibilityLabel(missing ? "Synced copy, can’t find the original" : info.isOriginal ? "Original synced block" : "Synced copy")
        let changed = next != phase
        phase = next
        applyBorder(animated: changed && shown)
        if !shown { show() }
        needsLayout = true
    }

    func place(around frame: NSRect) {
        let outset = NoteTheme.syncedBorderOutset
        let header = NoteTheme.syncedHeaderHeight
        let box = frame.insetBy(dx: -outset, dy: 0)
        let next = box.insetBy(dx: -2, dy: -header / 2 - 2)
        NoteAnimation.withoutAnimation {
            if self.frame != next { self.frame = next }
            let line = NSRect(x: 2, y: header / 2 + 2, width: box.width, height: box.height)
            border.frame = bounds
            let radius = max(0, min(7, line.width / 2 - 0.5, line.height / 2 - 0.5))
            border.path = CGPath(roundedRect: line, cornerWidth: radius, cornerHeight: radius, transform: nil)
            layoutHeader(line: line)
        }
    }

    private func layoutHeader(line: NSRect) {
        let height = NoteTheme.syncedHeaderHeight
        let y = line.minY - height / 2
        let labelSize = label.fittingSize
        label.frame = NSRect(x: line.minX + 10, y: y, width: min(labelSize.width, max(0, line.width * 0.62)), height: height)
        let badgeSize = badge.fittingSize
        badge.frame = NSRect(x: label.frame.maxX + 6, y: y + (height - badgeSize.height) / 2, width: badgeSize.width, height: badgeSize.height)
        let toolsSize = tools.fittingSize
        tools.frame = NSRect(x: line.maxX - 10 - toolsSize.width, y: y, width: toolsSize.width, height: height)
    }

    private func applyBorder(animated: Bool) {
        let color: NSColor
        switch phase {
        case .editing: color = NoteTheme.syncedAccent
        case .hover: color = NoteTheme.syncedHoverLine
        case .missing: color = NoteTheme.syncedMissingLine
        case .hidden: color = .clear
        }
        let target = NoteTheme.resolved(color, in: self)
        let from = border.presentation()?.strokeColor ?? border.strokeColor
        NoteAnimation.withoutAnimation {
            border.strokeColor = target
            border.lineDashPattern = phase == .missing ? [5, 4] : nil
        }
        if animated, let from, !NoteAnimation.reduceMotion {
            let fade = NoteAnimation.basic("strokeColor", from: from, to: target, duration: 0.15, curve: NoteCurve.easeOut)
            _ = NoteAnimation.run(fade, on: border, key: NoteAnimation.keyPrefix + "synced.border")
        }
    }

    private func show() {
        shown = true
        NoteAnimation.fade(self, visible: true, duration: 0.12)
        let point = NSPoint(x: 0, y: label.bounds.midY)
        if !NoteAnimation.reduceMotion { NoteAnimation.pop(label, from: NoteAnimation.hudHiddenScale, spring: .pill, about: point) }
    }

    func hide() {
        NoteAnimation.fade(self, visible: false, duration: NoteAnimation.hudCloseDuration) { [weak self] in
            guard let self, self.alphaValue < 0.01 else { return }
            self.removeFromSuperview()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBorder(animated: false)
    }
}

@MainActor
final class NoteSyncedLabelButton: NoteControlButton {
    private var title = ""
    private var icon: String?
    private var tint: NSColor = NoteTheme.syncedAccent
    private var font: NSFont { NoteTheme.chromeFont(11.5) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = NoteTheme.syncedHeaderHeight / 2
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, icon: String?, tint: NSColor, enabled: Bool) {
        let changed = title != self.title || icon != self.icon
        self.title = title
        self.icon = icon
        self.tint = tint
        isEnabled = true
        alphaValue = 1
        setAccessibilityLabel(title)
        setAccessibilityEnabled(enabled)
        acceptsPress = enabled
        if changed { invalidateIntrinsicContentSize() }
        needsDisplay = true
    }

    var acceptsPress = true

    func setToolTipText(_ text: String?) {
        if let text { setToolTip(text, anchor: .top) } else { parcTooltip = nil }
    }

    override func mouseDown(with event: NSEvent) {
        guard acceptsPress else { return }
        super.mouseDown(with: event)
    }

    override var showsPointingHand: Bool { acceptsPress && isEnabled }

    override var fittingSize: NSSize { intrinsicContentSize }

    override var intrinsicContentSize: NSSize {
        let width = ceil(NSAttributedString(string: title, attributes: [.font: font]).size().width)
        return NSSize(width: width + (icon == nil ? 20 : 38), height: NoteTheme.syncedHeaderHeight)
    }

    override func fill(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor? {
        guard acceptsPress else { return NoteTheme.menuFill }
        return pressed ? NoteTheme.syncedBadgeFill : hovered ? NoteTheme.syncedBadgeFill : NoteTheme.menuFill
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2 - 0.5, yRadius: bounds.height / 2 - 0.5)
        NoteTheme.menuHairline.setStroke()
        card.lineWidth = 1
        card.stroke()
        var x = bounds.minX + 10
        if let icon {
            NoteIconRenderer.draw(.symbol(icon), in: NSRect(x: x - 1, y: bounds.midY - 7, width: 14, height: 14), tint: tint,
                                  pointSize: 10.5, weight: .bold)
            x += 18
        }
        let height = ceil(font.ascender - font.descender)
        NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: tint])
            .draw(with: NSRect(x: x, y: (bounds.midY - height / 2).rounded(), width: bounds.maxX - x - 8, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

@MainActor
final class NoteSyncedBadge: NSView {
    private var font: NSFont { NoteTheme.chromeFont(9.5) }
    private let text = "ORIGINAL"

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Original")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        let size = NSAttributedString(string: text, attributes: [.font: font, .kern: 0.8]).size()
        return NSSize(width: ceil(size.width) + 12, height: 16)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let plate = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        NoteTheme.menuFill.setFill()
        plate.fill()
        NoteTheme.syncedBadgeFill.setFill()
        plate.fill()
        let height = ceil(font.ascender - font.descender)
        NSAttributedString(string: text, attributes: [.font: font, .kern: 0.8, .foregroundColor: NoteTheme.syncedAccent])
            .draw(with: NSRect(x: 6, y: (bounds.midY - height / 2).rounded(), width: bounds.width - 12, height: height),
                  options: [.usesLineFragmentOrigin])
    }
}

@MainActor
final class NoteSyncedToolStrip: NSView {
    let copy = NoteSyncedToolButton(symbol: "doc.on.doc", label: "Copy and sync")
    let more = NoteSyncedToolButton(symbol: "ellipsis", label: "More actions")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = NoteTheme.syncedHeaderHeight / 2
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        addSubview(copy)
        addSubview(more)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize { NSSize(width: 4 + 26 * 2 + 4, height: NoteTheme.syncedHeaderHeight) }

    override func layout() {
        super.layout()
        let size = NSSize(width: 26, height: bounds.height - 2)
        copy.frame = NSRect(x: 4, y: 1, width: size.width, height: size.height)
        more.frame = NSRect(x: copy.frame.maxX, y: 1, width: size.width, height: size.height)
    }

    override func updateLayer() {
        layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuFill, in: self)
        layer?.borderColor = NoteTheme.resolved(NoteTheme.menuHairline, in: self)
    }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
final class NoteSyncedToolButton: NoteControlButton {
    private let symbol: String
    private var flashing = false

    init(symbol: String, label: String) {
        self.symbol = symbol
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 20))
        cornerRadius = 9
        setAccessibilityLabel(label)
        setAccessibilityRole(.button)
        setToolTip(label, anchor: .top)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func flash() {
        flashing = true
        needsDisplay = true
        if let layer, !NoteAnimation.reduceMotion {
            NoteAnimation.pop(layer, from: 0.85, spring: .check, about: CGPoint(x: bounds.midX, y: bounds.midY))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.flashing = false
            self?.needsDisplay = true
        }
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        let name = flashing ? "checkmark" : symbol
        NoteIconRenderer.draw(.symbol(name), in: NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16),
                              tint: flashing ? NoteTheme.syncedAccent : ink, pointSize: 11, weight: .semibold)
    }
}
