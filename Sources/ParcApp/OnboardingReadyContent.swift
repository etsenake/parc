import AppKit
import Combine
import UniformTypeIdentifiers

///
/// Share/Download/Randomize match Setup.Action.downloadTapped / randomTapped
/// and UserCard.sharingItem. Replay must not regenerate the saved card.
@MainActor
final class OnboardingReadyContent: NSView, @preconcurrency NSSharingServicePickerDelegate {
    private let card = MembershipCardView(frame: NSRect(origin: .zero, size: MembershipCardArtwork.size))
    private let share = ActionButton("", symbol: "square.and.arrow.up")
    private let download = ActionButton("", symbol: "square.and.arrow.down")
    private let randomize = ActionButton("", symbol: "dice")
    private let status = NSTextField(wrappingLabelWithString: "")
    private var cards: MembershipCardStore?
    private var subscription: AnyCancellable?
    private var sharingPicker: NSSharingServicePicker?
    private var savePanel: NSSavePanel?
    private var saveGeneration = UUID()
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(card)
        //
        //
        for (button, help, label) in [
            (share, "Share", "Share card"), (download, "Download", "Download card"),
            (randomize, "Randomize", "Randomize card design")
        ] {
            button.toolTip = help
            button.setAccessibilityLabel(label)
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.focusRingCornerRadius = 6
            addSubview(button)
        }
        share.actionBlock = { [weak self] in self?.shareCard() }
        download.actionBlock = { [weak self] in self?.downloadCard() }
        randomize.actionBlock = { [weak self] in self?.randomizeCard() }
        randomize.setAccessibilityHelp("Create a new color design and playful title. Your display name and card creation date stay the same.")
        status.font = .systemFont(ofSize: 11)
        status.textColor = OnboardingSetupPalette.message
        status.alignment = .center
        addSubview(status)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Your Parc card")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var cardName: String { cards?.state?.name ?? "" }
    var firstKeyView: NSView { share }

    func chainKeyViews(to next: NSView) {
        share.nextKeyView = download
        download.nextKeyView = randomize
        randomize.nextKeyView = next
    }

    func attach(store: MembershipCardStore) {
        if cards !== store {
            cards = store
            subscription = store.$state.sink { [weak self] state in
                self?.card.display(state, animated: self?.card.state != nil)
                self?.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        let available = cards?.state != nil
        share.isEnabled = available
        download.isEnabled = available
        randomize.isEnabled = available
        if cards?.state != nil { status.stringValue = "" }
        else if let error = cards?.error { status.stringValue = error }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let cardSize = MembershipCardArtwork.size
        card.frame = NSRect(x: (bounds.width - cardSize.width) / 2,
                            y: max(72, (bounds.height - cardSize.height) / 2 - 12),
                            width: cardSize.width, height: cardSize.height)
        //
        let buttons = [share, download, randomize]
        let total = CGFloat(buttons.count * 32 + max(0, buttons.count - 1) * 10)
        var x = bounds.midX - total / 2
        let y = card.frame.maxY + 25
        for button in buttons {
            button.frame = NSRect(x: x, y: y, width: 32, height: 32)
            x += 42
        }
        status.frame = NSRect(x: 16, y: y + 40, width: bounds.width - 32, height: 36)
    }

    private var actionWindow: NSWindow? {
        guard let window, window.isVisible, window.isKeyWindow, window.attachedSheet == nil else { return nil }
        return window
    }

    private func snapshot() throws -> NSBitmapImageRep {
        guard let state = cards?.state, let bitmap = MembershipCardArtwork.sharingBitmap(state) else {
            throw MembershipCardFailure.unreadable
        }
        return bitmap
    }

    private func shareCard() {
        guard actionWindow != nil else { return }
        do {
            let bitmap = try snapshot()
            let image = NSImage(size: bitmap.size); image.addRepresentation(bitmap)
            let picker = NSSharingServicePicker(items: [image, Self.shareText]); picker.delegate = self
            sharingPicker = picker
            picker.show(relativeTo: share.bounds, of: share, preferredEdge: .minY)
        } catch { report(error.localizedDescription) }
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if sharingPicker === sharingServicePicker { sharingPicker = nil }
    }

    private func downloadCard() {
        guard actionWindow != nil, savePanel == nil else { return }
        do {
            guard let data = try snapshot().representation(using: .png, properties: [:]) else {
                throw MembershipCardFailure.unreadable
            }
            //
            let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.canCreateDirectories = true
            panel.nameFieldStringValue = Self.downloadName(cardName: cardName)
            let generation = UUID(); saveGeneration = generation; savePanel = panel
            panel.begin { [weak self, weak panel] response in
                guard let self, let panel, self.saveGeneration == generation else { return }
                self.savePanel = nil
                guard response == .OK, let url = panel.url else { return }
                do { try data.write(to: url, options: .atomic) }
                catch { self.report(error.localizedDescription) }
            }
        } catch { report(error.localizedDescription) }
    }

    private func randomizeCard() {
        guard actionWindow != nil else { return }
        card.squish()
        do { try cards?.regenerate() }
        catch { report(error.localizedDescription) }
    }

    ///
    static let shareText = "I just set up Parc!"

    ///
    static func downloadName(cardName: String) -> String {
        let name = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return name.isEmpty ? "Parc.png" : "\(name)_Parc.png"
    }

    private func report(_ message: String) {
        status.stringValue = message
        NSAccessibility.post(element: status, notification: .valueChanged)
    }
}
