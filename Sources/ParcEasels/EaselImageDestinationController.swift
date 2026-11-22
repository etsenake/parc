import AppKit
import ImageIO
import ParcCore
import ParcEngine
import ParcNotes

@MainActor
private final class EaselImageDestinationView: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 360
    static let pictureHeight: CGFloat = 120

    var preferredSizeDidChange: (() -> Void)?
    let field = NoteSearchField(placeholder: "Name a new Easel or find one")
    let list = NoteMenuList()
    private let picture = NSImageView()
    private let origin = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "Saved on this Mac.")

    init(preview: NSImage, origin text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 240))
        wantsLayer = true
        picture.image = preview
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.wantsLayer = true
        picture.layer?.cornerRadius = 8
        picture.layer?.cornerCurve = .continuous
        picture.layer?.masksToBounds = true
        picture.setAccessibilityLabel("Image from webpage")
        origin.stringValue = text
        origin.font = NoteTheme.captionFont()
        origin.textColor = NoteTheme.menuSecondaryInk
        origin.lineBreakMode = .byTruncatingMiddle
        status.font = NoteTheme.captionFont()
        status.textColor = NoteTheme.menuTertiaryInk
        field.showsIcon = false
        field.textField.setAccessibilityLabel("New Easel name or search")
        list.fixedWidth = Self.width
        list.maximumHeight = 260
        list.preferredSizeDidChange = { [weak self] in self?.contentChanged() }
        for view in [picture, origin, field, list, status] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Add image to Easel")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func show(error message: String?) {
        status.stringValue = message ?? "Saved on this Mac."
        status.textColor = message == nil ? NoteTheme.menuTertiaryInk : NoteTheme.destructiveInk
    }

    private func contentChanged() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        preferredSizeDidChange?()
    }

    override var intrinsicContentSize: NSSize {
        let inset = NoteTheme.menuInset
        let top = inset * 2 + Self.pictureHeight + 8 + 16 + 8 + NoteTheme.fieldHeight + 4
        return NSSize(width: Self.width, height: top + list.fittingSize.height + 22)
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            let inset = NoteTheme.menuInset * 2
            let inner = max(0, bounds.width - inset * 2)
            picture.frame = NSRect(x: inset, y: inset, width: inner, height: Self.pictureHeight)
            origin.frame = NSRect(x: inset + 2, y: picture.frame.maxY + 8, width: inner - 4, height: 16)
            field.frame = NSRect(x: inset, y: origin.frame.maxY + 8, width: inner, height: NoteTheme.fieldHeight)
            let listTop = field.frame.maxY + 4
            let listHeight = list.fittingSize.height
            list.frame = NSRect(x: 0, y: listTop, width: bounds.width, height: listHeight)
            status.frame = NSRect(x: inset + 2, y: list.frame.maxY + 4, width: inner - 4, height: 16)
        }
    }
}

@MainActor
package final class EaselImageDestinationController {
    private let image: EaselImageInput
    private let store: EaselStore
    private let destinations: [EaselSummary]
    private let defaultName: String
    private let view: EaselImageDestinationView
    private let valid: () -> Bool
    private let saved: (UUID, String) -> Void
    private let finished: () -> Void
    private var popover: NotePagePopover?
    private var edited = false
    private var committing = false

    package convenience init(image: PCNativeContextImage, directory: URL, valid: @escaping () -> Bool,
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
        defaultName = image.pageTitle.isEmpty ? "Untitled Easel" : image.pageTitle
        view = EaselImageDestinationView(preview: preview, origin: image.sourceURL?.host ?? image.pageTitle)
        view.field.text = defaultName
        view.field.onChange = { [weak self] _ in
            self?.edited = true
            self?.refreshRows()
        }
        view.field.onCommand = { [weak self] selector in
            guard let self else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
                return self.view.list.handle(command: selector)
            case #selector(NSResponder.insertNewline(_:)):
                return self.view.list.activateHighlighted()
            case #selector(NSResponder.cancelOperation(_:)):
                self.dismiss()
                return true
            default:
                return false
            }
        }
        view.list.onActivate = { [weak self] item in self?.activate(item) }
        view.list.onCancel = { [weak self] in self?.dismiss() }
        refreshRows()
    }

    private var newName: String {
        let typed = view.field.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? defaultName : typed
    }

    private func refreshRows() {
        var items = [NoteMenuList.Item(id: "new", title: "New Easel “\(newName)”", icon: .symbol("plus"), section: "Add to Easel")]
        let query = edited ? view.field.text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        for destination in destinations where query.isEmpty || destination.title.localizedCaseInsensitiveContains(query) {
            var item = NoteMenuList.Item(id: "easel." + destination.id.uuidString, title: destination.title.isEmpty ? "Untitled Easel" : destination.title,
                                         icon: .symbol("square.on.square"), section: "Easels")
            item.subtitle = destination.itemCount == 1 ? "1 object" : "\(destination.itemCount) objects"
            items.append(item)
        }
        view.list.setItems(items, keepingHighlight: false)
        view.list.highlight(id: "new", animated: false)
    }

    package func present(on parent: NSWindow) {
        guard valid(), image.isValid, parent.attachedSheet == nil, let host = parent.contentView else { finished(); return }
        let next = NotePagePopover(content: view)
        next.onClose = { [weak self, weak next] in
            guard let self, self.popover === next else { return }
            self.popover = nil
            self.finished()
        }
        popover = next
        let anchor = NSRect(x: host.bounds.midX - 1, y: host.bounds.maxY - host.bounds.height / 3, width: 2, height: 2)
        next.present(in: host, anchor: anchor, edge: .below, alignment: .center)
        view.list.prepare(origin: .keyboard)
        view.field.focus()
        view.field.textField.currentEditor()?.selectAll(nil)
    }

    package func dismissIfInvalid() { if !valid() || !image.isValid { dismiss() } }

    package func dismiss() { popover?.close() }

    private func activate(_ item: NoteMenuList.Item) {
        guard !committing, valid(), image.isValid else { dismiss(); return }
        let destinationID: UUID?
        if item.id == "new" {
            destinationID = nil
        } else {
            guard item.id.hasPrefix("easel."), let id = UUID(uuidString: String(item.id.dropFirst(6))),
                  destinations.contains(where: { $0.id == id }) else { return }
            destinationID = id
        }
        committing = true
        do {
            let result = try EaselImagePlacement.place(image, in: store, destinationID: destinationID, newTitle: newName)
            withExtendedLifetime(result) { dismiss(); saved(result.id, result.title) }
        } catch {
            view.show(error: error.localizedDescription)
            committing = false
        }
    }
}
