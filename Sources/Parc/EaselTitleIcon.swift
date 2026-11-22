import AppKit
import Combine
import ParcCore

@MainActor
final class EaselTitleIcon: NSView {
    static let side: CGFloat = 32
    static let gap: CGFloat = 4

    private let session: EaselSession
    private let environment: EaselIconEnvironment
    private let iconView: NotePageIconView
    private let addChip = NoteChip("Add icon", icon: .featherSmile, style: .ghost)
    private var popover: NotePagePopover?
    private var hoverArea: NSTrackingArea?
    private var hovered = false
    private var shown: EaselPageIcon?
    private var loading = false
    private var titleBase = NSRect.zero
    var host: () -> NSView? = { nil }
    var onGeometryChange: (() -> Void)?
    var onError: ((Error) -> Void)?
    var isTitleEditing: () -> Bool = { false }
    var titleTextWidth: () -> CGFloat = { 0 }

    init(session: EaselSession, easelIcons: EaselTabIcons? = nil) {
        self.session = session
        environment = EaselIconEnvironment(session: session, easelIcons: easelIcons)
        iconView = NotePageIconView(environment: environment)
        super.init(frame: .zero)
        iconView.isCompact = true
        iconView.noun = "Easel"
        iconView.frame = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
        iconView.onPress = { [weak self] in self?.presentPicker() }
        iconView.setAccessibilityHelp("Change icon")
        addChip.setToolTip("Add icon")
        addChip.onPress = { [weak self] in self?.addRandomIcon() }
        addChip.setAccessibilityLabel("Add icon")
        addChip.wantsLayer = true
        addChip.layer?.opacity = 0
        addSubview(iconView)
        addSubview(addChip)
        shown = session.document.icon
        applyShown()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    var hasIcon: Bool { shown != nil }
    var occupiedWidth: CGFloat { hasIcon ? Self.side + Self.gap : 0 }

    func refresh() {
        let next = session.document.icon
        guard next != shown else { return }
        let hadIcon = shown != nil
        shown = next
        applyShown()
        if !hadIcon, next != nil { NoteAnimation.pop(iconView, from: NoteAnimation.checkPopScale, spring: .pop) }
        onGeometryChange?()
    }

    func place(title base: NSRect, in container: NSRect) -> NSRect {
        frame = container
        let side = Self.side
        iconView.frame = NSRect(x: base.minX - 4, y: base.minY, width: side, height: side)
        iconView.isHidden = !hasIcon
        titleBase = base
        positionChip()
        addChip.isHidden = hasIcon
        guard hasIcon else { return base }
        let shift = occupiedWidth
        return NSRect(x: base.minX + shift, y: base.minY, width: max(80, base.width - shift), height: base.height)
    }

    func closePicker() {
        popover?.close(animated: false)
        popover = nil
    }

    private func positionChip() {
        let chipSize = addChip.intrinsicContentSize
        let after = titleBase.minX + min(max(titleTextWidth(), 0) + 12, max(0, titleBase.width - chipSize.width))
        addChip.frame = NSRect(x: after, y: titleBase.minY + (titleBase.height - chipSize.height) / 2,
                               width: chipSize.width, height: chipSize.height)
    }

    func updateHover() {
        if hovered, !hasIcon { positionChip() }
        let visible = hovered && !hasIcon && !session.isClosed && !isTitleEditing()
        guard let layer = addChip.layer else { return }
        NoteAnimation.fade(layer, to: visible ? 1 : 0, duration: NoteAnimation.hoverDuration)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; updateHover() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateHover() }
    override func mouseMoved(with event: NSEvent) { updateHover() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redisplayChromeSubtree()
    }

    private func applyShown() {
        iconView.icon = shown?.raw
        iconView.isEditable = !session.isClosed
        iconView.isHidden = shown == nil
        addChip.isHidden = shown != nil
        updateHover()
    }

    private func addRandomIcon() {
        guard !session.isClosed, let emoji = NoteEmojiCatalog.shared.random() else { return }
        let character = NoteEmojiCatalog.shared.character(for: emoji)
        NoteEmojiCatalog.shared.recordUse(character)
        apply(EaselPageIcon.emoji(character), name: "Add icon")
    }

    private func apply(_ icon: EaselPageIcon?, name: String, discarding fresh: String? = nil) {
        do {
            try session.perform(name) { $0.icon = icon }
        } catch {
            if let fresh { session.discardUnusedAssets([fresh]) }
            onError?(error)
        }
    }

    private func presentPicker() {
        guard !session.isClosed, let container = host() else { return }
        popover?.close(animated: false)
        let picker = NotePageIconPicker(environment: environment, current: session.document.icon?.raw)
        let popover = NotePagePopover(content: picker)
        popover.exempt(iconView)
        picker.onPick = { [weak self, weak popover] value in
            NoteEmojiCatalog.shared.recordUse(value)
            self?.apply(EaselPageIcon(raw: value), name: "Change icon")
            popover?.close()
        }
        picker.onImage = { [weak self, weak popover] source in
            self?.useImage(source)
            popover?.close()
        }
        picker.onRemove = { [weak self, weak popover] in
            self?.apply(nil, name: "Remove icon")
            popover?.close()
        }
        picker.onCancel = { [weak popover] in popover?.close() }
        picker.onError = { [weak self] error in self?.onError?(error) }
        popover.onClose = { [weak self] in self?.popover = nil }
        self.popover = popover
        popover.present(in: container, anchor: container.convert(iconView.bounds, from: iconView), edge: .below)
        picker.focus()
    }

    private func useImage(_ source: String) {
        if EaselAssetType.of(assetID: source) != nil {
            apply(EaselPageIcon.image(assetID: source), name: "Change icon", discarding: source)
            return
        }
        guard !loading, let url = URL(string: source) else { return }
        loading = true
        NotePageImageLoader.shared.load(url) { [weak self] image in
            guard let self else { return }
            self.loading = false
            guard let tiff = image?.tiffRepresentation, let png = NoteCustomEmojiImages.preparedPNG(from: tiff) else {
                self.onError?(EaselStoreError.invalidImage)
                return
            }
            do {
                let asset = try self.session.importAsset(png, type: .png)
                self.apply(EaselPageIcon.image(assetID: asset), name: "Change icon", discarding: asset)
            } catch {
                self.onError?(error)
            }
        }
    }
}
