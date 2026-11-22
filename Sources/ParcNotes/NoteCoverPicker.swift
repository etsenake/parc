import AppKit
import ParcCore
import UniformTypeIdentifiers
import ParcKit

@MainActor
final class NoteCoverPicker: NSView, NoteFloatingPanelContent {
    enum Tab: Int, CaseIterable {
        case gallery, upload, link, unsplash

        var title: String {
            switch self {
            case .gallery: return "Gallery"
            case .upload: return "Upload"
            case .link: return "Link"
            case .unsplash: return "Unsplash"
            }
        }

        static var available: [Tab] { allCases.filter { $0 != .unsplash || NoteUnsplash.isAvailable } }
    }

    static let size = NSSize(width: 452, height: 332)
    static let unsplashSize = NSSize(width: 452, height: 448)
    static let columns = 3
    private static var thumbnails: [String: NSImage] = [:]

    let environment: NoteEnvironment
    var hasCover: Bool { didSet { removeChip.isHidden = !hasCover } }
    let tabs = Tab.available
    var onChoose: ((NoteCover) -> Void)?
    var onRemove: (() -> Void)?
    var onError: ((Error) -> Void)?
    var preferredSizeDidChange: (() -> Void)?
    private(set) var tab: Tab = .gallery
    private var tabButtons: [Tab: NoteToolbarButton] = [:]
    private let removeChip = NoteChip("Remove", style: .ghost)
    private let separator = NSView()
    private let galleryHeader = NSTextField(labelWithString: "Parc Gallery")
    private var tiles: [NoteCoverTile] = []
    private let dropZone = NotePageImageDropZone(title: "Drop an image here", hint: "Wide images, 1,500 px or more across, look sharpest.")
    private let linkField = NoteSearchField(placeholder: "Paste an image link…")
    private let linkButton = NoteChip("Use Link", style: .filled)
    private let linkHint = NSTextField(wrappingLabelWithString: "Works with any image on the web.")
    private var busyStyle: String?
    private var unsplash: NoteUnsplashBrowser?
    private var unsplashImport: Task<Void, Never>?
    var onOpen: ((URL) -> Void)?

    init(environment: NoteEnvironment, hasCover: Bool) {
        self.environment = environment
        self.hasCover = hasCover
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Cover Picker")
        for item in tabs {
            let button = NoteToolbarButton(.text(item.title), label: item.title)
            button.onPress = { [weak self] in self?.select(item) }
            tabButtons[item] = button
            addSubview(button)
        }
        removeChip.isHidden = !hasCover
        removeChip.setToolTip("Remove cover")
        removeChip.onPress = { [weak self] in self?.onRemove?() }
        addSubview(removeChip)
        separator.wantsLayer = true
        addSubview(separator)
        galleryHeader.font = NoteTheme.menuHeaderFont()
        galleryHeader.textColor = NoteTheme.menuTertiaryInk
        addSubview(galleryHeader)
        for style in NoteCoverGallery.styles {
            let tile = NoteCoverTile(style: style, image: Self.thumbnail(for: style))
            tile.onPress = { [weak self] in self?.pick(style) }
            tiles.append(tile)
            addSubview(tile)
        }
        dropZone.onFile = { [weak self] url in self?.importFile(url) }
        dropZone.onError = { [weak self] error in self?.onError?(error) }
        addSubview(dropZone)
        linkField.showsIcon = false
        linkField.textField.setAccessibilityLabel("Image link")
        linkField.onSubmit = { [weak self] _ in self?.useLink() }
        linkField.onChange = { [weak self] _ in self?.resetLinkHint() }
        linkButton.onPress = { [weak self] in self?.useLink() }
        linkHint.font = NoteTheme.nunitoRegular(12.5)
        linkHint.textColor = NoteTheme.menuTertiaryInk
        addSubview(linkField)
        addSubview(linkButton)
        addSubview(linkHint)
        if tabs.contains(.unsplash) {
            let browser = NoteUnsplashBrowser(orientation: .landscape)
            browser.onPick = { [weak self] photo in self?.pickUnsplash(photo) }
            browser.onOpen = { [weak self] url in self?.onOpen?(url) }
            browser.isHidden = true
            addSubview(browser)
            unsplash = browser
        }
        select(.gallery)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        unsplashImport?.cancel()
    }

    override var isFlipped: Bool { true }
    var currentSize: NSSize { tab == .unsplash ? Self.unsplashSize : Self.size }
    override var intrinsicContentSize: NSSize { currentSize }
    override var fittingSize: NSSize { currentSize }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else { return }
        unsplashImport?.cancel()
        unsplashImport = nil
        unsplash?.busyPhotoID = nil
    }

    static func thumbnail(for style: NoteCoverStyle) -> NSImage? {
        if let cached = thumbnails[style.id] { return cached }
        guard let image = NoteCoverGallery.image(for: style, pixelSize: NoteCoverGallery.thumbnailPixelSize) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
        thumbnails[style.id] = result
        return result
    }

    static func importGalleryCover(_ style: NoteCoverStyle, environment: NoteEnvironment,
                                   completion: @escaping (Result<String, Error>) -> Void) {
        let id = style.id
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let style = NoteCoverGallery.style(id: id) else { return nil }
                return NoteCoverGallery.assetData(for: style)
            }.value
            guard let data else {
                completion(.failure(CocoaError(.fileWriteUnknown)))
                return
            }
            do {
                let source = try environment.importAsset(data: data, fileExtension: NoteCoverGallery.fileExtension,
                                                         suggestedName: NoteCoverGallery.suggestedName(for: style))
                completion(.success(source))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func select(_ next: Tab) {
        guard tabs.contains(next) else { return }
        let previousSize = currentSize
        tab = next
        for (item, button) in tabButtons { button.isChecked = item == next }
        let gallery = next == .gallery, upload = next == .upload, link = next == .link, photos = next == .unsplash
        galleryHeader.isHidden = !gallery
        for tile in tiles { tile.isHidden = !gallery }
        dropZone.isHidden = !upload
        linkField.isHidden = !link
        linkButton.isHidden = !link
        linkHint.isHidden = !link
        unsplash?.isHidden = !photos
        if link { linkField.focus() }
        if photos { unsplash?.focus() }
        if currentSize != previousSize {
            setFrameSize(currentSize)
            preferredSizeDidChange?()
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 8
        let tabHeight = NoteTheme.toolbarButtonSize.height
        for item in tabs {
            guard let button = tabButtons[item] else { continue }
            let width = button.intrinsicContentSize.width
            button.frame = NSRect(x: x, y: 8, width: width, height: tabHeight)
            x += width + 2
        }
        let removeWidth = removeChip.intrinsicContentSize.width
        removeChip.frame = NSRect(x: bounds.width - 8 - removeWidth, y: 8 + (tabHeight - NoteTheme.chipHeight) / 2,
                                  width: removeWidth, height: NoteTheme.chipHeight)
        separator.frame = NSRect(x: 0, y: 8 + tabHeight + 7, width: bounds.width, height: 1)
        let top = separator.frame.maxY + 10
        let headerHeight = ceil(galleryHeader.intrinsicContentSize.height)
        galleryHeader.frame = NSRect(x: 14, y: top, width: bounds.width - 28, height: headerHeight)
        let gap: CGFloat = 8
        let inset: CGFloat = 12
        let tileWidth = floor((bounds.width - inset * 2 - gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns))
        let tileHeight = floor(tileWidth / 2.5)
        for (index, tile) in tiles.enumerated() {
            let column = index % Self.columns, row = index / Self.columns
            tile.frame = NSRect(x: inset + CGFloat(column) * (tileWidth + gap), y: top + headerHeight + 8 + CGFloat(row) * (tileHeight + gap),
                                width: tileWidth, height: tileHeight)
        }
        dropZone.frame = NSRect(x: inset, y: top, width: bounds.width - inset * 2, height: bounds.height - top - inset)
        let buttonWidth = linkButton.intrinsicContentSize.width
        linkField.frame = NSRect(x: inset, y: top + 6, width: bounds.width - inset * 2 - buttonWidth - 8, height: NoteTheme.fieldHeight)
        linkButton.frame = NSRect(x: bounds.width - inset - buttonWidth, y: top + 6 + (NoteTheme.fieldHeight - NoteTheme.chipHeight) / 2,
                                  width: buttonWidth, height: NoteTheme.chipHeight)
        let hintHeight = ceil(linkHint.sizeThatFits(NSSize(width: bounds.width - inset * 2 - 4, height: 200)).height)
        linkHint.frame = NSRect(x: inset + 2, y: linkField.frame.maxY + 10, width: bounds.width - inset * 2 - 4, height: hintHeight)
        unsplash?.frame = NSRect(x: 0, y: top - 2, width: bounds.width, height: max(0, bounds.height - top + 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
        redisplayChromeSubtree()
    }

    private func refreshAppearance() {
        NoteAnimation.withoutAnimation { separator.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self) }
    }

    private func pick(_ style: NoteCoverStyle) {
        guard busyStyle == nil else { return }
        busyStyle = style.id
        tiles.first { $0.style.id == style.id }?.isBusy = true
        Self.importGalleryCover(style, environment: environment) { [weak self] result in
            guard let self else { return }
            self.busyStyle = nil
            for tile in self.tiles { tile.isBusy = false }
            switch result {
            case .success(let source): self.onChoose?(NoteCover(source: source))
            case .failure(let error): self.onError?(error)
            }
        }
    }

    private func pickUnsplash(_ photo: NoteUnsplashPhoto) {
        guard unsplashImport == nil, let unsplash else { return }
        unsplash.busyPhotoID = photo.id
        let environment = self.environment
        unsplashImport = Task { [weak self] in
            do {
                let imported = try await NoteUnsplashImport.importPhoto(photo, width: NoteUnsplash.coverWidth, environment: environment)
                guard let self, !Task.isCancelled else { return }
                self.unsplashImport = nil
                self.unsplash?.busyPhotoID = nil
                self.onChoose?(NoteCover(source: imported.source, credit: imported.credit))
            } catch {
                guard let self else { return }
                self.unsplashImport = nil
                self.unsplash?.busyPhotoID = nil
                if !(error is CancellationError) { self.onError?(error) }
            }
        }
    }

    private func importFile(_ url: URL) {
        do {
            onChoose?(NoteCover(source: try NoteMediaImport.source(importing: url, environment: environment, scoped: true)))
        } catch {
            onError?(error)
        }
    }

    private func useLink() {
        guard let url = NotePageExport.validatedLink(linkField.text) else {
            linkHint.stringValue = "That doesn’t look like a link. Try one starting with https://."
            linkHint.textColor = NoteTheme.destructiveInk
            NoteAnimation.pop(linkField, from: 0.97, spring: .pill)
            needsLayout = true
            return
        }
        onChoose?(NoteCover(source: url.absoluteString))
    }

    private func resetLinkHint() {
        guard linkHint.textColor != NoteTheme.menuTertiaryInk else { return }
        linkHint.stringValue = "Works with any image on the web."
        linkHint.textColor = NoteTheme.menuTertiaryInk
    }
}

@MainActor
final class NoteCoverTile: PointingHandButton {
    let style: NoteCoverStyle
    var onPress: (() -> Void)?
    var isBusy = false { didSet { needsDisplay = true } }
    private let thumbnail: NSImage?
    private var isHovered = false
    private var hoverArea: NSTrackingArea?

    init(style: NoteCoverStyle, image: NSImage?) {
        self.style = style
        thumbnail = image
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        refusesFirstResponder = true
        wantsLayer = true
        target = self
        action = #selector(pressed)
        setAccessibilityLabel("\(style.name) cover")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    @objc private func pressed() { onPress?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }
    override func mouseMoved(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        guard value != isHovered else { return }
        isHovered = value
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        press(true)
        super.mouseDown(with: event)
        press(false)
    }

    private func press(_ down: Bool) {
        guard let layer else { return }
        let center = NoteAnimation.layerPoint(NSPoint(x: bounds.midX, y: bounds.midY), in: self)
        let target = down ? NoteAnimation.scaleTransform(NoteAnimation.pressedScale, about: center) : CATransform3DIdentity
        NoteAnimation.animate(layer, "transform", to: NSValue(caTransform3D: target), spring: .press, key: NoteAnimation.keyPrefix + "tile.press")
    }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            let rect = bounds.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            if let thumbnail {
                thumbnail.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isBusy ? 0.5 : 1, respectFlipped: true,
                               hints: [.interpolation: NSImageInterpolation.high])
            } else {
                NoteTheme.mediaPlaceholderFill.setFill()
                rect.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            if isHovered || isHighlighted {
                NoteTheme.accent.setStroke()
                let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
                ring.lineWidth = 2
                ring.stroke()
            } else {
                NoteTheme.menuHairline.setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }
        }
    }
}

@MainActor
final class NotePageImageDropZone: NSView {
    var onFile: ((URL) -> Void)?
    var onError: ((Error) -> Void)?
    private let titleLabel: NSTextField
    private let hintLabel: NSTextField
    private let chooseChip = NoteChip("Choose an image…", icon: .featherImage, style: .filled)
    private var isTargeted = false { didSet { needsDisplay = true } }

    init(title: String, hint: String) {
        titleLabel = NSTextField(labelWithString: title)
        hintLabel = NSTextField(wrappingLabelWithString: hint)
        super.init(frame: .zero)
        wantsLayer = true
        titleLabel.font = NoteTheme.nunitoBold(14)
        titleLabel.textColor = NoteTheme.menuInk
        titleLabel.alignment = .center
        hintLabel.font = NoteTheme.nunitoRegular(12.5)
        hintLabel.textColor = NoteTheme.menuTertiaryInk
        hintLabel.alignment = .center
        chooseChip.onPress = { [weak self] in self?.choose() }
        addSubview(titleLabel)
        addSubview(chooseChip)
        addSubview(hintLabel)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let title = titleLabel.intrinsicContentSize
        let chip = chooseChip.intrinsicContentSize
        let hintWidth = min(bounds.width - 40, 300)
        let hintHeight = ceil(hintLabel.sizeThatFits(NSSize(width: hintWidth, height: 200)).height)
        let total = title.height + 12 + chip.height + 12 + hintHeight
        var y = (bounds.height - total) / 2
        titleLabel.frame = NSRect(x: 20, y: y, width: bounds.width - 40, height: title.height)
        y += title.height + 12
        chooseChip.frame = NSRect(x: (bounds.width - chip.width) / 2, y: y, width: chip.width, height: chip.height)
        y += chip.height + 12
        hintLabel.frame = NSRect(x: (bounds.width - hintWidth) / 2, y: y, width: hintWidth, height: hintHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
            if isTargeted {
                NoteTheme.checkedFill.setFill()
                path.fill()
            }
            (isTargeted ? NoteTheme.accent : NoteTheme.separator).setStroke()
            path.lineWidth = 1.5
            path.setLineDash([5, 4], count: 2, phase: 0)
            path.stroke()
        }
    }

    static func imageURL(from info: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
                                                             .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.imageURL(from: sender) != nil else { return [] }
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        guard let url = Self.imageURL(from: sender) else { return false }
        onFile?(url)
        return true
    }

    func choose() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Image"
        let onFile = onFile
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { onFile?(url) }
        }
    }
}

@MainActor
package final class NotePageIconPicker: NSView, NoteFloatingPanelContent {
    enum Tab { case emoji, upload }

    static let tabHeight: CGFloat = 44

    let environment: NoteEnvironment
    package var onPick: ((String) -> Void)?
    package var onImage: ((String) -> Void)?
    package var onRemove: (() -> Void)?
    package var onCancel: (() -> Void)?
    package var onError: ((Error) -> Void)?
    package var preferredSizeDidChange: (() -> Void)?
    private(set) var tab: Tab = .emoji
    private let emojiTab = NoteToolbarButton(.text("Emoji"), label: "Emoji")
    private let uploadTab = NoteToolbarButton(.text("Upload"), label: "Upload")
    private let removeChip = NoteChip("Remove", style: .ghost)
    private let separator = NSView()
    private let picker: NoteEmojiPicker
    private let dropZone = NotePageImageDropZone(title: "Drop an image here", hint: "Square images around 280 px look sharpest.")
    private let linkField = NoteSearchField(placeholder: "Or paste an image link…")
    private let librarySwitch = NoteToggleSwitch(label: "Add to this folder’s emoji")
    private let libraryLabel = NSTextField(labelWithString: "Also add it to this folder’s emoji")
    var current: String? { didSet { if current != oldValue { refreshCurrent() } } }

    package init(environment: NoteEnvironment, current: String?) {
        self.environment = environment
        self.current = current
        picker = NoteEmojiPicker(showsRemove: false, showsRandom: true, library: environment.emojiLibrary)
        super.init(frame: NSRect(x: 0, y: 0, width: NoteEmojiPicker.preferredSize.width,
                                 height: NoteEmojiPicker.preferredSize.height + Self.tabHeight))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Icon Picker")
        picker.freezesRecents = true
        picker.onPick = { [weak self] emoji in self?.onPick?(emoji) }
        picker.onCancel = { [weak self] in self?.onCancel?() }
        emojiTab.onPress = { [weak self] in self?.select(.emoji) }
        uploadTab.onPress = { [weak self] in self?.select(.upload) }
        removeChip.setToolTip("Remove icon")
        removeChip.onPress = { [weak self] in self?.onRemove?() }
        dropZone.onFile = { [weak self] url in self?.importFile(url) }
        linkField.showsIcon = false
        linkField.textField.setAccessibilityLabel("Image link")
        linkField.onSubmit = { [weak self] text in self?.useLink(text) }
        separator.wantsLayer = true
        libraryLabel.font = NoteTheme.nunitoRegular(12.5)
        libraryLabel.textColor = NoteTheme.menuInk
        libraryLabel.setAccessibilityElement(false)
        for view in [emojiTab, uploadTab, removeChip, separator, picker, dropZone, linkField, librarySwitch, libraryLabel] as [NSView] {
            addSubview(view)
        }
        refreshCurrent()
        select(.emoji)
        refreshAppearance()
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func refreshCurrent() {
        let icon = (current ?? "").isEmpty ? nil : current
        picker.currentEmoji = icon.flatMap { NotePageImageLoader.isImageSource($0) ? nil : $0 }
        removeChip.isHidden = icon == nil
    }

    package override var isFlipped: Bool { true }
    package override var intrinsicContentSize: NSSize {
        NSSize(width: NoteEmojiPicker.preferredSize.width, height: NoteEmojiPicker.preferredSize.height + Self.tabHeight)
    }
    package override var fittingSize: NSSize { intrinsicContentSize }

    package func focus() {
        if tab == .emoji { picker.focusSearch() } else { linkField.focus() }
    }

    func select(_ next: Tab) {
        tab = next
        emojiTab.isChecked = next == .emoji
        uploadTab.isChecked = next == .upload
        picker.isHidden = next != .emoji
        dropZone.isHidden = next != .upload
        linkField.isHidden = next != .upload
        librarySwitch.isHidden = next != .upload || environment.emojiLibrary == nil
        libraryLabel.isHidden = librarySwitch.isHidden
        focus()
        needsLayout = true
    }

    package override func layout() {
        super.layout()
        let button = NoteTheme.toolbarButtonSize.height
        var x: CGFloat = 8
        for tab in [emojiTab, uploadTab] {
            let width = tab.intrinsicContentSize.width
            tab.frame = NSRect(x: x, y: 8, width: width, height: button)
            x += width + 2
        }
        let removeWidth = removeChip.intrinsicContentSize.width
        removeChip.frame = NSRect(x: bounds.width - 8 - removeWidth, y: 8 + (button - NoteTheme.chipHeight) / 2,
                                  width: removeWidth, height: NoteTheme.chipHeight)
        separator.frame = NSRect(x: 0, y: Self.tabHeight - 1, width: bounds.width, height: 1)
        picker.frame = NSRect(x: 0, y: Self.tabHeight, width: bounds.width, height: bounds.height - Self.tabHeight)
        let switchRow: CGFloat = environment.emojiLibrary == nil ? 0 : 30
        librarySwitch.frame = NSRect(x: 14, y: bounds.height - 12 - NoteToggleSwitch.size.height - 2,
                                     width: NoteToggleSwitch.size.width, height: NoteToggleSwitch.size.height)
        libraryLabel.frame = NSRect(x: librarySwitch.frame.maxX + 8, y: librarySwitch.frame.midY - 9, width: bounds.width - librarySwitch.frame.maxX - 22, height: 18)
        linkField.frame = NSRect(x: 12, y: bounds.height - 12 - switchRow - NoteTheme.fieldHeight, width: bounds.width - 24, height: NoteTheme.fieldHeight)
        dropZone.frame = NSRect(x: 12, y: Self.tabHeight + 12, width: bounds.width - 24, height: linkField.frame.minY - 12 - Self.tabHeight - 12)
    }

    package override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
        redisplayChromeSubtree()
    }

    private func refreshAppearance() {
        NoteAnimation.withoutAnimation { separator.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self) }
    }

    private func importFile(_ url: URL) {
        if librarySwitch.isOn, environment.emojiLibrary != nil {
            addToLibrary(NoteCustomEmojiImages.preparedPNG(contentsOf: url), name: NoteCustomEmojiImages.suggestedName(for: url))
            return
        }
        do {
            onImage?(try NoteMediaImport.source(importing: url, environment: environment, scoped: true))
        } catch {
            onError?(error)
        }
    }

    private func useLink(_ text: String) {
        guard let url = NotePageExport.validatedLink(text) else {
            NoteAnimation.pop(linkField, from: 0.97, spring: .pill)
            NSSound.beep()
            return
        }
        guard librarySwitch.isOn, environment.emojiLibrary != nil else {
            onImage?(url.absoluteString)
            return
        }
        NotePageImageLoader.shared.load(url) { [weak self] image in
            let data = image?.tiffRepresentation.flatMap(NoteCustomEmojiImages.preparedPNG(from:))
            self?.addToLibrary(data, name: NoteCustomEmojiImages.suggestedName(for: url))
        }
    }

    private func addToLibrary(_ png: Data?, name: String) {
        guard let library = environment.emojiLibrary else { return }
        guard let png else {
            onError?(NoteEmojiLibraryError.unreadableImage)
            return
        }
        do {
            let entry = try library.add(png: png, name: library.uniqueName(for: name) ?? library.uniqueName(for: "emoji") ?? "emoji")
            onPick?(entry.reference)
        } catch {
            onError?(error)
        }
    }
}
