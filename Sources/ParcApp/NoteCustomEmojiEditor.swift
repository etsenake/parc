import AppKit
import UniformTypeIdentifiers

@MainActor
final class NoteCustomEmojiWell: NSView {
    var image: NSImage? { didSet { needsDisplay = true; setAccessibilityValue(image == nil ? "Empty" : "Image chosen") } }
    var isChangeable = true { didSet { window?.invalidateCursorRects(for: self); needsDisplay = true } }
    var onImage: ((Data, String) -> Void)?
    var onError: ((String) -> Void)?
    private var isTargeted = false { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .png, .tiff])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Emoji image")
        setAccessibilityHelp("Choose, drop or paste an image")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isChangeable }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            let frame = bounds.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
            if isTargeted || (isHovered && isChangeable) {
                (isTargeted ? NoteTheme.checkedFill : NoteTheme.hoverFill).setFill()
                path.fill()
            }
            if let image {
                NoteCustomEmojiImages.draw(image, fittingIn: frame.insetBy(dx: 16, dy: 16))
            }
            guard image == nil || isTargeted else { return }
            (isTargeted ? NoteTheme.accent : NoteTheme.separator).setStroke()
            path.lineWidth = 1.5
            path.setLineDash([5, 4], count: 2, phase: 0)
            path.stroke()
            guard image == nil else { return }
            let glyph = NoteEmojiDrawing.symbol("photo.badge.plus", pointSize: 22)
            let tinted = NoteAtomCell.tinted(glyph, size: glyph.size, tint: NoteTheme.tertiaryInk)
            tinted.draw(in: NSRect(x: bounds.midX - glyph.size.width / 2, y: bounds.midY - glyph.size.height / 2 - 10,
                                   width: glyph.size.width, height: glyph.size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let hint = NSAttributedString(string: "Drop, paste or click", attributes: [
                .font: NoteTheme.nunitoRegular(11.5), .foregroundColor: NoteTheme.tertiaryInk])
            let size = hint.size()
            hint.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY + 12))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func resetCursorRects() {
        if isChangeable { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isChangeable else { return }
        NoteAnimation.pop(self, from: NoteAnimation.pressedScale, spring: .press)
    }

    override func mouseUp(with event: NSEvent) {
        guard isChangeable, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        choose()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isChangeable else { return false }
        choose()
        return true
    }

    func choose() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Image"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.load(url) }
        }
    }

    func load(_ url: URL) {
        guard let data = NoteCustomEmojiImages.preparedPNG(contentsOf: url) else {
            onError?(NoteEmojiLibraryError.unreadableImage.localizedDescription)
            return
        }
        onImage?(data, NoteCustomEmojiImages.suggestedName(for: url))
    }

    @discardableResult
    func paste(from pasteboard: NSPasteboard) -> Bool {
        guard isChangeable, let found = NoteCustomEmojiImages.pasteboardImage(pasteboard) else { return false }
        onImage?(found.data, found.name)
        return true
    }

    @objc func paste(_ sender: Any?) {
        if !paste(from: .general) { NSSound.beep() }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isChangeable, accepts(sender.draggingPasteboard) else { return [] }
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        return paste(from: sender.draggingPasteboard)
    }

    private func accepts(_ pasteboard: NSPasteboard) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
                                                             .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: options)
            || pasteboard.availableType(from: [.png, .tiff]) != nil
    }
}

@MainActor
final class NoteCustomEmojiEditor: NSView {
    enum Mode: Equatable {
        case add
        case edit(NoteCustomEmoji)
    }

    let library: NoteEmojiLibrary
    let mode: Mode
    var onSaved: ((NoteCustomEmoji) -> Void)?
    var onDeleted: (() -> Void)?
    var onCancel: (() -> Void)?
    private let backButton = NoteEmojiButton(.glyph(NoteEmojiDrawing.symbol("chevron.left", pointSize: 12)), label: "Back", tooltip: "Back")
    private let titleLabel = NSTextField(labelWithString: "")
    private let well = NoteCustomEmojiWell()
    private let nameField = NoteSearchField(placeholder: "Name it, like party-parrot")
    private let detail = NSTextField(labelWithString: "")
    private let saveChip = NoteChip("Save", style: .filled)
    private let cancelChip = NoteChip("Cancel")
    private let deleteChip = NoteChip("Delete", icon: .symbol("trash"))
    private var png: Data?
    private var suggested = ""
    private var problem: String?
    private var confirmingDelete = false

    init(library: NoteEmojiLibrary, mode: Mode) {
        self.library = library
        self.mode = mode
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        titleLabel.font = NoteTheme.nunitoBold(14)
        titleLabel.textColor = NoteTheme.menuInk
        titleLabel.lineBreakMode = .byTruncatingTail
        detail.font = NoteTheme.nunitoRegular(12)
        detail.lineBreakMode = .byTruncatingTail
        nameField.showsIcon = false
        nameField.textField.setAccessibilityLabel("Emoji name")
        nameField.onChange = { [weak self] _ in self?.nameChanged() }
        nameField.onSubmit = { [weak self] _ in self?.save() }
        nameField.onCommand = { [weak self] selector in
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            self?.cancel()
            return true
        }
        well.onImage = { [weak self] data, name in self?.choose(data, name: name) }
        well.onError = { [weak self] message in self?.show(problem: message) }
        backButton.onPress = { [weak self] in self?.cancel() }
        saveChip.onPress = { [weak self] in self?.save() }
        cancelChip.onPress = { [weak self] in self?.cancel() }
        deleteChip.onPress = { [weak self] in self?.delete() }
        for view in [backButton, titleLabel, well, nameField, detail, cancelChip, saveChip, deleteChip] as [NSView] { addSubview(view) }
        switch mode {
        case .add:
            titleLabel.stringValue = "New custom emoji"
            setAccessibilityLabel("New custom emoji")
            deleteChip.isHidden = true
        case .edit(let entry):
            titleLabel.stringValue = "Edit " + entry.reference
            setAccessibilityLabel("Edit custom emoji")
            well.isChangeable = false
            well.image = NoteCustomEmojiImages.image(for: entry, in: library)
            nameField.text = entry.name
        }
        refreshDetail()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func focus() {
        nameField.focus()
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 12
        backButton.frame = NSRect(x: padding - 4, y: 6, width: 30, height: 30)
        titleLabel.frame = NSRect(x: backButton.frame.maxX + 4, y: 12, width: bounds.width - backButton.frame.maxX - padding - 4, height: 19)
        let side: CGFloat = 112
        well.frame = NSRect(x: (bounds.width - side) / 2, y: 46, width: side, height: side)
        nameField.frame = NSRect(x: padding, y: well.frame.maxY + 16, width: bounds.width - 2 * padding, height: NoteTheme.fieldHeight)
        detail.frame = NSRect(x: padding + 2, y: nameField.frame.maxY + 7, width: bounds.width - 2 * padding - 4, height: 17)
        let chip = NoteTheme.chipHeight
        let bottom = bounds.height - padding - chip
        let save = saveChip.intrinsicContentSize.width
        saveChip.frame = NSRect(x: bounds.width - padding - save, y: bottom, width: save, height: chip)
        let cancel = cancelChip.intrinsicContentSize.width
        cancelChip.frame = NSRect(x: saveChip.frame.minX - 6 - cancel, y: bottom, width: cancel, height: chip)
        let delete = deleteChip.intrinsicContentSize.width
        deleteChip.frame = NSRect(x: padding, y: bottom, width: delete, height: chip)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "v", well.isChangeable,
           NoteCustomEmojiImages.pasteboardImage(.general) != nil {
            return well.paste(from: .general)
        }
        return super.performKeyEquivalent(with: event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDetail()
    }

    private var proposedName: String? { NoteCustomEmojiName.normalized(nameField.text) }

    private var currentName: String? {
        if case .edit(let entry) = mode { return entry.name }
        return nil
    }

    private func choose(_ data: Data, name: String) {
        png = data
        well.image = NSImage(data: data)
        NoteAnimation.pop(well, from: 0.9, spring: .check)
        let fresh = library.uniqueName(for: name) ?? ""
        if nameField.text.isEmpty || nameField.text == suggested, !fresh.isEmpty {
            nameField.text = fresh
            suggested = fresh
        }
        problem = nil
        refreshDetail()
        nameField.focus()
    }

    private func nameChanged() {
        problem = nil
        if confirmingDelete { setConfirmingDelete(false) }
        refreshDetail()
    }

    private func show(problem message: String) {
        problem = message
        refreshDetail()
        NoteAnimation.pop(nameField, from: 0.97, spring: .pill)
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func refreshDetail() {
        let text: String
        var color = NoteTheme.menuTertiaryInk
        if confirmingDelete, let currentName {
            text = "Notes using :\(currentName): will show the shortcode instead."
            color = NoteTheme.color(.text(.red))
        } else if let problem {
            text = problem
            color = NoteTheme.color(.text(.red))
        } else if let name = proposedName {
            if name != currentName, library.emoji(named: name).map({ $0.name == name }) == true {
                text = "There’s already a :\(name): here."
                color = NoteTheme.color(.text(.red))
            } else {
                text = "Type :\(name): in any note in this folder."
            }
        } else if nameField.text.isEmpty {
            text = png == nil && currentName == nil ? "Pick an image, then give it a name." : "Give it a name."
        } else {
            text = "Names need a letter or number."
            color = NoteTheme.color(.text(.red))
        }
        detail.stringValue = text
        detail.textColor = color
        detail.toolTip = text
        saveChip.isEnabled = proposedName != nil && (png != nil || currentName != nil) && !confirmingDelete
    }

    private func save() {
        guard !confirmingDelete else { return }
        guard let name = proposedName else {
            show(problem: NoteEmojiLibraryError.invalidName.localizedDescription)
            return
        }
        do {
            switch mode {
            case .add:
                guard let png else {
                    NoteAnimation.pop(well, from: 0.94, spring: .pill)
                    show(problem: "Pick an image first.")
                    return
                }
                onSaved?(try library.add(png: png, name: name))
            case .edit(let entry):
                onSaved?(try library.rename(entry.name, to: name))
            }
        } catch {
            show(problem: error.localizedDescription)
        }
    }

    private func delete() {
        guard let currentName else { return }
        guard confirmingDelete else {
            setConfirmingDelete(true)
            return
        }
        do {
            try library.remove(currentName)
            onDeleted?()
        } catch {
            setConfirmingDelete(false)
            show(problem: error.localizedDescription)
        }
    }

    private func setConfirmingDelete(_ value: Bool) {
        confirmingDelete = value
        deleteChip.chipTitle = value ? "Delete for good" : "Delete"
        deleteChip.style = value ? .filled : .ghost
        if value { NoteAnimation.pop(deleteChip, from: 0.94, spring: .pill) }
        needsLayout = true
        refreshDetail()
    }

    private func cancel() {
        if confirmingDelete {
            setConfirmingDelete(false)
            return
        }
        onCancel?()
    }
}
