import AppKit
import ImageIO

//
// page-to-Easel delegate seam is recovered; this local picker layout is a Parc
// adaptation. Persistence and undo use the same sessions as the Easel editor.
@MainActor
final class EaselImageDestinationController: NSWindowController {
    private let image: EaselImageInput
    private let store: EaselStore
    private let destinations: [EaselSummary]
    private let picker = NSPopUpButton()
    private let name = NSTextField(string: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let valid: () -> Bool
    private let saved: (UUID, String) -> Void
    private let finished: () -> Void
    private var committing = false

    convenience init(image: PCNativeContextImage, directory: URL, valid: @escaping () -> Bool,
         saved: @escaping (UUID, String) -> Void, finished: @escaping () -> Void) throws {
        if let message = image.errorMessage {
            throw NSError(domain: "Parc.EaselCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        try self.init(image: EaselImageInput(pngData: image.pngData, sourceURL: image.sourceURL,
            pageTitle: image.pageTitle, valid: { image.isValid }), directory: directory,
            valid: valid, saved: saved, finished: finished)
    }

    init(image: EaselImageInput, directory: URL, valid: @escaping () -> Bool,
         saved: @escaping (UUID, String) -> Void, finished: @escaping () -> Void) throws {
        let data = image.pngData
        _ = try EaselImagePlacement.pixelSize(data)
        guard let preview = NSImage(data: data) else { throw EaselStoreError.invalidImage }
        self.image = image; self.valid = valid; self.saved = saved; self.finished = finished
        store = try EaselEditorViewController.sharedStore(directory: directory)
        destinations = try store.list()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
                            styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Add Image to Easel"; panel.isReleasedWhenClosed = false
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading
        root.spacing = 14; root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        panel.contentView = root
        let heading = NSTextField(labelWithString: "Add image to Easel")
        heading.font = .systemFont(ofSize: 20, weight: .semibold); root.addArrangedSubview(heading)
        let picture = NSImageView(image: preview); picture.imageScaling = .scaleProportionallyUpOrDown
        picture.setAccessibilityLabel("Image from webpage")
        picture.heightAnchor.constraint(equalToConstant: 136).isActive = true
        picture.widthAnchor.constraint(equalToConstant: 392).isActive = true
        root.addArrangedSubview(picture)
        let origin = NSTextField(labelWithString: image.sourceURL?.host ?? image.pageTitle)
        origin.textColor = .secondaryLabelColor; origin.font = .systemFont(ofSize: 12)
        origin.lineBreakMode = .byTruncatingMiddle; root.addArrangedSubview(origin)
        picker.addItem(withTitle: "New Easel…")
        for item in destinations { picker.addItem(withTitle: item.title) }
        picker.setAccessibilityLabel("Destination Easel"); picker.target = self
        picker.action = #selector(destinationChanged); root.addArrangedSubview(picker)
        picker.widthAnchor.constraint(equalToConstant: 392).isActive = true
        name.placeholderString = "Name your Easel"; name.setAccessibilityLabel("New Easel name")
        name.stringValue = image.pageTitle.isEmpty ? "Untitled Easel" : image.pageTitle
        root.addArrangedSubview(name); name.widthAnchor.constraint(equalToConstant: 392).isActive = true
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        status.stringValue = "Saved locally in this profile."; root.addArrangedSubview(status)
        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 10
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"; cancel.bezelStyle = .rounded
        let add = NSButton(title: "Add Image", target: self, action: #selector(addImage))
        add.keyEquivalent = "\r"; add.bezelStyle = .rounded
        buttons.addArrangedSubview(cancel); buttons.addArrangedSubview(add); root.addArrangedSubview(buttons)
        panel.setContentSize(root.fittingSize)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present(on parent: NSWindow) {
        guard let window, valid(), image.isValid, parent.attachedSheet == nil else { finished(); return }
        parent.beginSheet(window) { [weak self] _ in self?.finished() }
    }
    func dismissIfInvalid() { if !valid() || !image.isValid { dismiss() } }
    func dismiss() {
        guard let window else { return }
        if let parent = window.sheetParent { parent.endSheet(window); window.orderOut(nil) }
    }
    @objc private func cancel() { dismiss() }
    @objc private func destinationChanged() { name.isHidden = picker.indexOfSelectedItem != 0 }
    @objc private func addImage() {
        guard !committing, valid(), image.isValid else { dismiss(); return }
        committing = true
        do {
            let destinationID: UUID?
            if picker.indexOfSelectedItem == 0 { destinationID = nil }
            else {
                let index = picker.indexOfSelectedItem - 1
                guard destinations.indices.contains(index) else { committing = false; return }
                destinationID = destinations[index].id
            }
            let result = try EaselImagePlacement.place(image, in: store,
                destinationID: destinationID, newTitle: name.stringValue)
            withExtendedLifetime(result) { dismiss(); saved(result.id, result.title) }
        } catch {
            status.stringValue = error.localizedDescription; status.textColor = .systemRed
            committing = false
        }
    }
}
