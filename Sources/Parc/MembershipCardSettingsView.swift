import AppKit
import Combine
import ParcCore
import UniformTypeIdentifiers

@MainActor
final class MembershipCardSettingsView: LayoutView, @preconcurrency NSSharingServicePickerDelegate {
    let cards: MembershipCardStore
    private let card = MembershipCardView(frame: NSRect(x: 40, y: 56, width: 240, height: 360))
    private let name = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let share = MembershipCardActionButton(title: "", target: nil, action: nil)
    private let download = MembershipCardActionButton(title: "", target: nil, action: nil)
    private let randomize = MembershipCardActionButton(title: "", target: nil, action: nil)
    private let rename = SettingsPillButton(title: "Edit…")
    private let reload = PointingHandButton(title: "Reload Card", target: nil, action: nil)
    private var subscription: AnyCancellable?
    private var errorSubscription: AnyCancellable?
    private var nameSheet: MembershipCardNameSheet?
    private var savePanel: NSSavePanel?
    private var sharingPicker: NSSharingServicePicker?
    private var saveGeneration = UUID()
    var onNameChanged: ((String) -> Void)?
    private(set) var displayName = "Your Card"

    private let nameGroup = SettingsGroupView(frame: NSRect(x: 0, y: 0, width: 292, height: 56))
    private let detailsGroup = SettingsGroupView(frame: NSRect(x: 0, y: 0, width: 292, height: 130))
    private let created = NSTextField(labelWithString: "")
    private let explanation = NSTextField(wrappingLabelWithString:
        "Your name and card design are saved on this Mac. Share, download or randomize it below the card.")
    private let defaultPrompt = MembershipDefaultBrowserPrompt()
    var onMakeDefault: (() -> Void)?

    init(cards: MembershipCardStore) {
        self.cards = cards
        super.init(frame: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsLayout.contentHeight))
        autoresizingMask = [.width]
        addSubview(card)
        addSubview(nameGroup); addSubview(detailsGroup)
        let nameTitle = NSTextField(labelWithString: "Display name")
        nameTitle.font = .systemFont(ofSize: 13); nameTitle.frame = NSRect(x: 16, y: 19, width: 100, height: 18)
        nameGroup.addSubview(nameTitle)
        name.font = .systemFont(ofSize: 13); name.alignment = .right
        name.lineBreakMode = .byTruncatingTail
        rename.target = self; rename.action = #selector(editName)
        rename.frame = NSRect(x: 292 - 12 - rename.fittingWidth, y: 16, width: rename.fittingWidth, height: 24)
        name.frame = NSRect(x: 112, y: 19, width: rename.frame.minX - 10 - 112, height: 18); nameGroup.addSubview(name)
        rename.setAccessibilityLabel("Edit card display name"); nameGroup.addSubview(rename)
        let createdTitle = NSTextField(labelWithString: "Card created")
        createdTitle.font = .systemFont(ofSize: 13); createdTitle.frame = NSRect(x: 16, y: 19, width: 140, height: 18)
        detailsGroup.addSubview(createdTitle)
        created.font = .systemFont(ofSize: 13); created.alignment = .right
        created.frame = NSRect(x: 140, y: 19, width: 136, height: 18); detailsGroup.addSubview(created)
        let rule = NSBox(frame: NSRect(x: 12, y: 56, width: 268, height: 1))
        rule.boxType = .separator; detailsGroup.addSubview(rule)
        explanation.font = .systemFont(ofSize: 13); explanation.textColor = .secondaryLabelColor
        explanation.frame = NSRect(x: 16, y: 66, width: 260, height: 54); detailsGroup.addSubview(explanation)
        for (button, symbol, label, action) in [
            (share, "square.and.arrow.up", "Share card", #selector(shareCard)),
            (download, "square.and.arrow.down", "Download card", #selector(downloadCard)),
            (randomize, "dice", "Randomize card design", #selector(randomizeCard))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imagePosition = .imageOnly; button.isBordered = false
            button.focusRingType = .exterior
            button.contentTintColor = NSColor(srgbRed: 0.435, green: 0.435, blue: 0.435, alpha: 1)
            button.target = self; button.action = action; button.toolTip = label
            button.setAccessibilityLabel(label); addSubview(button)
        }
        randomize.setAccessibilityHelp("Create a new color design and playful title. Your display name and card creation date stay the same.")
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; addSubview(status)
        reload.bezelStyle = .rounded; reload.target = self; reload.action = #selector(reloadCard)
        reload.isHidden = true; addSubview(reload)
        defaultPrompt.isHidden = true
        defaultPrompt.onMakeDefault = { [weak self] in self?.onMakeDefault?() }
        addSubview(defaultPrompt)
        layoutContent()
        subscription = cards.$state.sink { [weak self] value in self?.refresh(value) }
        errorSubscription = cards.$error.sink { [weak self] error in
            if let error { self?.report(error) }
        }
    }
    override func layout() { super.layout(); layoutContent() }
    func showDefaultBrowserPrompt(_ visible: Bool, waiting: Bool, failure: String? = nil) {
        defaultPrompt.waiting = waiting
        defaultPrompt.failure = failure
        defaultPrompt.isHidden = !visible
        needsLayout = true
    }
    private func layoutContent() {
        let banner = defaultPrompt.isHidden ? 0 : MembershipDefaultBrowserPrompt.height + 38
        let cardX = max(16, ((bounds.width - 556) / 2).rounded())
        var top = max(16, ((bounds.height - 416 - banner) / 2).rounded())
        if !defaultPrompt.isHidden {
            let width = min(defaultPrompt.fittingWidth, bounds.width - 32)
            defaultPrompt.frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: top,
                                         width: width, height: MembershipDefaultBrowserPrompt.height)
            top += banner
        }
        card.frame = NSRect(x: cardX, y: top, width: 240, height: 360)
        for (index, button) in [share, download, randomize].enumerated() {
            button.frame = NSRect(x: cardX + 64 + CGFloat(index) * 40, y: top + 384, width: 32, height: 32)
        }
        let column = cardX + 264
        nameGroup.frame = NSRect(x: column, y: top, width: 292, height: 56)
        detailsGroup.frame = NSRect(x: column, y: nameGroup.frame.maxY + 16, width: 292, height: 130)
        status.frame = NSRect(x: column, y: detailsGroup.frame.maxY + 16, width: 292, height: 44)
        reload.frame = NSRect(x: column + 292 - 112, y: status.frame.maxY + 4, width: 112, height: 32)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func refresh(_ state: MembershipCardState?) {
        let changed = card.state != nil && card.state != state
        card.display(state, animated: changed)
        name.stringValue = state?.name ?? "Card unavailable"
        created.stringValue = state.map(MembershipCardArtwork.date) ?? ""
        displayName = state?.name ?? "Your Card"
        onNameChanged?(displayName)
        for button in [share, download, randomize, rename] { button.isEnabled = state != nil }
        reload.isHidden = state != nil
        if state != nil { status.stringValue = "" }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancelPresentation() }
        super.viewWillMove(toWindow: newWindow)
    }
    func cancelPresentation() {
        saveGeneration = UUID()
        if let panel = savePanel { panel.cancel(nil) }
        savePanel = nil
        if let sheet = nameSheet?.window, let parent = sheet.sheetParent { parent.endSheet(sheet, returnCode: .cancel) }
        nameSheet = nil; sharingPicker = nil; card.stopMotion()
    }
    private var actionWindow: NSWindow? {
        guard let window, window.isVisible, window.attachedSheet == nil,
              !isHiddenOrHasHiddenAncestor else { return nil }
        return window
    }
    @objc private func reloadCard() {
        guard actionWindow != nil else { return }
        cards.reload()
    }
    @objc private func randomizeCard() {
        guard actionWindow != nil else { return }
        do { try cards.regenerate() }
        catch { report(error.localizedDescription) }
    }
    @objc private func editName() {
        guard let parent = actionWindow, let expected = cards.state, nameSheet == nil else { return }
        let sheet = MembershipCardNameSheet(name: expected.name) { [weak self, weak parent] value in
            guard let self, let parent, self.window === parent, self.nameSheet?.window?.sheetParent === parent else {
                throw MembershipCardFailure.changed
            }
            try self.cards.rename(value, expected: expected)
        }
        guard let child = sheet.window else { return }
        nameSheet = sheet
        parent.beginSheet(child) { [weak self, weak child] _ in
            guard self?.nameSheet?.window === child else { return }
            self?.nameSheet = nil
        }
        sheet.focusName()
    }
    private func snapshot() throws -> NSBitmapImageRep {
        guard let state = cards.state, let bitmap = MembershipCardArtwork.sharingBitmap(state) else { throw MembershipCardFailure.unreadable }
        return bitmap
    }
    @objc private func shareCard() {
        guard actionWindow != nil else { return }
        do {
            let bitmap = try snapshot()
            let image = NSImage(size: bitmap.size); image.addRepresentation(bitmap)
            let picker = NSSharingServicePicker(items: [image]); picker.delegate = self
            sharingPicker = picker
            picker.show(relativeTo: share.bounds, of: share, preferredEdge: .minY)
        } catch { report(error.localizedDescription) }
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if sharingPicker === sharingServicePicker { sharingPicker = nil }
    }
    @objc private func downloadCard() {
        guard let parent = actionWindow, savePanel == nil else { return }
        do {
            guard let data = try snapshot().representation(using: .png, properties: [:]) else { throw MembershipCardFailure.unreadable }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.canCreateDirectories = true
            panel.nameFieldStringValue = "Parc Card.png"; panel.title = "Download your Parc card"
            let generation = UUID(); saveGeneration = generation; savePanel = panel
            panel.beginSheetModal(for: parent) { [weak self, weak panel, weak parent] response in
                guard let self, let panel, self.saveGeneration == generation else { return }
                self.savePanel = nil
                guard response == .OK, let url = panel.url, let parent, self.window === parent, parent.isVisible else { return }
                do {
                    try data.write(to: url, options: .atomic)
                    self.status.stringValue = "Card saved."
                    NSAccessibility.post(element: self.status, notification: .valueChanged)
                } catch { self.report(error.localizedDescription) }
            }
        } catch { report(error.localizedDescription) }
    }
    private func report(_ message: String) {
        status.stringValue = message; reload.isHidden = false
        NSAccessibility.post(element: status, notification: .valueChanged)
    }
}

@MainActor
private final class MembershipCardNameSheet: NSWindowController, NSTextFieldDelegate {
    private let field = NSTextField()
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let save = ActionButton("Save")
    private let cancel = ActionButton("Cancel")
    private let commit: (String) throws -> Void
    init(name: String, commit: @escaping (String) throws -> Void) {
        self.commit = commit
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 496, height: 252),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Edit your display name"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = LayoutView(frame: NSRect(x: 0, y: 0, width: 496, height: 252)); window.contentView = content
        let title = NSTextField(labelWithString: "Edit your display name")
        title.font = .systemFont(ofSize: 17, weight: .bold); title.frame = NSRect(x: 32, y: 24, width: 432, height: 24); content.addSubview(title)
        let help = NSTextField(wrappingLabelWithString: "This name appears on your local Parc card and any copy you share or download.")
        help.font = .systemFont(ofSize: 13); help.textColor = .secondaryLabelColor
        help.frame = NSRect(x: 32, y: 62, width: 432, height: 38); content.addSubview(help)
        field.stringValue = name; field.frame = NSRect(x: 32, y: 112, width: 432, height: 28)
        field.delegate = self; field.setAccessibilityLabel("Card display name"); content.addSubview(field)
        feedback.font = .systemFont(ofSize: 11); feedback.textColor = .systemRed
        feedback.frame = NSRect(x: 32, y: 148, width: 432, height: 38); content.addSubview(feedback)
        for (button, x) in [(cancel, CGFloat(278)), (save, CGFloat(374))] {
            button.frame = NSRect(x: x, y: 202, width: 90, height: 30); button.isBordered = true
            button.bezelStyle = .rounded; button.contentTintColor = .labelColor
            button.focusRingType = .exterior; content.addSubview(button)
        }
        save.keyEquivalent = "\r"; cancel.keyEquivalent = "\u{1b}"
        save.actionBlock = { [weak self] in self?.submit() }
        cancel.actionBlock = { [weak self] in
            guard let window = self?.window else { return }
            window.sheetParent?.endSheet(window, returnCode: .cancel)
        }
        field.nextKeyView = cancel; cancel.nextKeyView = save; save.nextKeyView = field
        window.autorecalculatesKeyViewLoop = false; window.initialFirstResponder = field
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func focusName() { window?.makeFirstResponder(field); field.selectText(nil) }
    func controlTextDidChange(_ obj: Notification) {
        save.isEnabled = (try? MembershipCardState.validatedName(field.stringValue)) != nil
        feedback.stringValue = ""
    }
    private func submit() {
        guard save.isEnabled, let window, window.sheetParent != nil else { return }
        guard !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false) else { return }
        do {
            try commit(field.stringValue)
            window.sheetParent?.endSheet(window, returnCode: .OK)
        } catch {
            feedback.stringValue = error.localizedDescription
            NSAccessibility.post(element: feedback, notification: .valueChanged)
        }
    }
}

@MainActor
private final class MembershipCardActionButton: SettingsHoverButton {
    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (isHovered || cell?.isHighlighted == true) {
            NSColor.labelColor.withAlphaComponent(cell?.isHighlighted == true ? 0.14 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
}

@MainActor
private final class MembershipDefaultBrowserPrompt: LayoutView {
    static let height: CGFloat = 36
    private let message = NSTextField(labelWithString: "Parc isn’t your default browser.")
    private let button = SettingsPillButton(title: "Make Parc your default", symbol: "heart.fill", loadable: true)
    var onMakeDefault: (() -> Void)?
    var waiting = false { didSet { button.isEnabled = !waiting } }
    var failure: String? {
        didSet {
            message.stringValue = failure ?? "Parc isn’t your default browser."
            message.toolTip = failure; updateColors(); needsLayout = true
        }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 6; layer?.cornerCurve = .continuous
        message.font = .systemFont(ofSize: 13); message.lineBreakMode = .byTruncatingTail
        button.target = self; button.action = #selector(makeDefault)
        button.setAccessibilityLabel("Make Parc your default browser")
        addSubview(message); addSubview(button)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    var fittingWidth: CGFloat { 16 + ceil(message.intrinsicContentSize.width) + 8 + button.fittingWidth + 16 }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsLayout = true }
    override func layout() {
        super.layout()
        let text = max(0, bounds.width - 40 - button.fittingWidth)
        message.frame = NSRect(x: 16, y: (bounds.height - 17) / 2, width: text, height: 17)
        button.frame = NSRect(x: bounds.width - 16 - button.fittingWidth, y: 6, width: button.fittingWidth, height: 24)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.396, green: 0.376, blue: 0.408, alpha: 1) : NSColor.white).cgColor
        layer?.borderWidth = dark ? 0 : 1
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.borderColor = NSColor.separatorColor.cgColor }
        message.textColor = failure != nil ? .systemRed : dark ? NSColor(white: 1, alpha: 0.85) : NSColor(white: 0, alpha: 0.66)
    }
    @objc private func makeDefault() { onMakeDefault?() }
}
