import AppKit

/// Explicit file admission and aggregate outcomes only; credential values stay
/// in the native CSV service and original Profile's encrypted password store.
@MainActor
final class BrowserImportPasswordsView: NSView {
    var onChooseFile: (() -> Void)?
    var onDropFile: ((URL) -> Void)?
    var onHelp: (() -> Void)?
    var onContinue: (() -> Void)?
    var onStop: (() -> Void)?
    var onRemoveFile: (() -> Void)?
    private let title = NSTextField(wrappingLabelWithString: "Bring your Safari passwords")
    private let detail = NSTextField(wrappingLabelWithString: "Export your passwords from Safari or Apple’s Passwords app, then choose that CSV file here. Passwords are saved to this Parc Profile’s encrypted local password store.")
    private let destination = NSTextField(wrappingLabelWithString: "")
    private let choose = ActionButton("Choose Passwords.csv…")
    private let help = ActionButton("How do I find this?")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let continueButton = ActionButton("Skip Passwords")
    private let stop = ActionButton("Stop Import")
    private let remove = ActionButton("Move exported file to Trash…")
    private let progress = NSProgressIndicator()
    private let dropTarget = OnboardingPasswordDropTarget(frame: .zero)
    private let instructions = (1...3).map { OnboardingPasswordInstructionRow(number: $0) }
    private let resultScroll = NSScrollView()
    var usesSetupCard = false { didSet { configurePresentation() } }
    private var permitsFile = false
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 26, weight: .bold); title.textColor = PArcDialogStyle.popoverTitle
        detail.font = .systemFont(ofSize: 14); detail.textColor = PArcDialogStyle.popoverMessage
        destination.font = .systemFont(ofSize: 13, weight: .medium); destination.textColor = PArcDialogStyle.popoverTitle
        status.font = .systemFont(ofSize: 13); status.textColor = PArcDialogStyle.popoverMessage
        for button in [choose, help, continueButton, stop, remove] {
            button.isBordered = true; button.bezelStyle = .rounded
            button.contentTintColor = PArcDialogStyle.popoverTitle; button.focusRingType = .default
        }
        choose.actionBlock = { [weak self] in self?.onChooseFile?() }
        help.actionBlock = { [weak self] in self?.onHelp?() }
        continueButton.actionBlock = { [weak self] in self?.onContinue?() }
        stop.actionBlock = { [weak self] in self?.onStop?() }
        remove.actionBlock = { [weak self] in self?.onRemoveFile?() }
        progress.style = .spinning; progress.controlSize = .small
        [title, detail, destination, choose, help, status, continueButton, stop, remove, progress].forEach(addSubview)
        dropTarget.onChoose = { [weak self] in self?.onChooseFile?() }
        dropTarget.onDrop = { [weak self] in self?.onDropFile?($0) }
        addSubview(dropTarget)
        instructions.forEach(addSubview)
        resultScroll.drawsBackground = false; resultScroll.borderType = .noBorder
        resultScroll.hasVerticalScroller = true; resultScroll.autohidesScrollers = true
        addSubview(resultScroll)
        configurePresentation()
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("Import exported Safari passwords")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func configurePresentation() {
        title.isHidden = usesSetupCard; detail.isHidden = usesSetupCard
        choose.isHidden = usesSetupCard; continueButton.isHidden = usesSetupCard
        dropTarget.isHidden = !usesSetupCard; resultScroll.isHidden = !usesSetupCard
        instructions.forEach { $0.isHidden = !usesSetupCard }
        if usesSetupCard {
            unregisterDraggedTypes() // Admission belongs to the actual outlined target.
            resultScroll.documentView = status
            if #available(macOS 15, *) {
                instructions[0].configure([.text("Open Apple’s "), .menu("Passwords"), .text(" app and unlock it.")])
                instructions[1].configure([.text("Choose "), .menu("File"), .separator,
                                           .menu("Export All Passwords to File"), .text(".")])
            } else {
                instructions[0].configure([.text("Open "), .menu("Safari"), .separator, .menu("Settings"), .text(".")])
                instructions[1].configure([.text("Unlock "), .menu("Passwords"), .text(", then choose "),
                                           .menu("Export All Passwords"), .text(".")])
            }
            instructions[2].configure([.text("Upload your Passwords.csv file to Parc.")])
            help.isBordered = false; help.alignment = .left
            help.font = .systemFont(ofSize: 14, weight: .regular)
            help.attributedTitle = NSAttributedString(string: help.title, attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: OnboardingPasswordPalette.help])
            destination.textColor = OnboardingSetupPalette.message
            help.contentTintColor = OnboardingPasswordPalette.help
            for button in [stop, remove] { button.contentTintColor = OnboardingSetupPalette.title }
        } else {
            resultScroll.documentView = nil
            if status.superview !== self { addSubview(status) }
        }
        needsLayout = true
    }
    func update(destination name: String, canImport: Bool, busy: Bool, removing: Bool,
                result: PCNativePasswordFileImportResult?, fileName: String?, removed: Bool,
                canRemove: Bool, error: String?) {
        permitsFile = canImport
        destination.stringValue = "Destination: \(name)"
        choose.isEnabled = canImport; help.isEnabled = !busy && !removing
        stop.isHidden = !busy; stop.isEnabled = busy
        continueButton.isEnabled = !busy && !removing
        continueButton.title = result == nil ? "Skip Passwords" : "Continue"
        remove.isHidden = !canRemove; remove.isEnabled = canRemove && !removing
        progress.isHidden = !busy && !removing
        if progress.isHidden { progress.stopAnimation(nil) } else { progress.startAnimation(nil) }
        var lines: [String] = []
        if busy { lines.append("Importing \(fileName ?? "passwords")…") }
        else if removing { lines.append("Moving the exported file to Trash…") }
        else if let result {
            lines.append("\(result.importedCount) passwords saved · \(result.existingCount) existing or duplicate rows kept · \(result.invalidCount) unsupported rows")
            if result.outcome == .partial { lines.append("Some rows were not imported. Keep the file to review them.") }
            if result.outcome == .cancelled { lines.append("Import stopped. Confirmed passwords remain saved.") }
            if result.outcome == .failed && error == nil { lines.append("The import could not be completed.") }
        } else { lines.append("Drag a CSV file here or choose it above. Existing passwords are kept. Other Safari data is imported separately.") }
        if removed { lines.append("The exported file was moved to Trash.") }
        else if result != nil { lines.append("The exported file remains on disk until you choose to remove it.") }
        if let error { lines.append(error) }
        status.stringValue = lines.joined(separator: "\n\n")
        status.textColor = error == nil ? (usesSetupCard ? OnboardingSetupPalette.message : PArcDialogStyle.popoverMessage) :
            (usesSetupCard ? OnboardingPasswordPalette.error : .systemOrange)
        let presentation: OnboardingPasswordDropTarget.Presentation
        if removing { presentation = .removingExport }
        else if busy { presentation = .working }
        else if error != nil || (result != nil && result?.outcome != .completed) { presentation = .needsAttention }
        else if result != nil { presentation = .saved }
        else { presentation = .ready }
        dropTarget.update(presentation, canImport: canImport)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let width = bounds.width
        if usesSetupCard {
            // Original ImportKeychainView: ordered guidance, then a 25-point
            // gap and the fixed 460 × 200 drop area in the full setup column.
            let left = (width - 460) / 2
            destination.frame = NSRect(x: left, y: 24, width: 460, height: 20)
            instructions[0].frame = NSRect(x: left, y: 60, width: 460, height: 30)
            instructions[1].frame = NSRect(x: left, y: 95, width: 460, height: 30)
            // ClickOnPasswords owns the help control; it precedes the upload
            // instruction instead of appearing after the entire ordered list.
            help.frame = NSRect(x: left + 28, y: 127, width: 190, height: 22)
            instructions[2].frame = NSRect(x: left, y: 155, width: 460, height: 30)
            dropTarget.frame = NSRect(x: left, y: 210, width: 460, height: 200)
            progress.frame = NSRect(x: left + 422, y: 376, width: 18, height: 18)
            resultScroll.frame = NSRect(x: left, y: 422, width: 460, height: 64)
            let textWidth = max(0, resultScroll.contentSize.width - 12)
            status.frame = NSRect(x: 0, y: 0, width: textWidth,
                height: max(64, status.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height))
            remove.frame = NSRect(x: left + 190, y: 495, width: 270, height: 30)
            stop.frame = NSRect(x: left, y: 495, width: 150, height: 30)
            return
        }
        title.frame = NSRect(x: 34, y: 55, width: width - 68, height: 70)
        detail.frame = NSRect(x: 34, y: 132, width: width - 68, height: 75)
        destination.frame = NSRect(x: 34, y: 217, width: width - 68, height: 25)
        choose.frame = NSRect(x: 34, y: 260, width: 240, height: 42)
        help.frame = NSRect(x: 290, y: 266, width: 175, height: 30)
        progress.frame = NSRect(x: width - 65, y: 270, width: 18, height: 18)
        status.frame = NSRect(x: 34, y: 325, width: width - 68, height: 160)
        remove.frame = NSRect(x: 34, y: bounds.height - 105, width: 260, height: 30)
        stop.frame = NSRect(x: 34, y: bounds.height - 65, width: 130, height: 36)
        continueButton.frame = NSRect(x: width - 174, y: bounds.height - 65, width: 140, height: 36)
    }
    private func file(from sender: NSDraggingInfo) -> URL? {
        guard permitsFile, let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], urls.count == 1,
              let url = urls.first, url.pathExtension.lowercased() == "csv" else { return nil }
        return url
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { file(from: sender) == nil ? [] : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = file(from: sender) else { return false }
        onDropFile?(url); return true
    }
}

/// OrderedListCounter's 20-point Circle and 12-point semibold number, beside
/// the original 14-point light Text with semibold menu names. AppKit retains
/// native text layout; the counter is decoration within one spoken instruction.
@MainActor
final class OnboardingPasswordInstructionRow: NSView {
    enum Fragment { case text(String), menu(String), separator }
    private let number: Int
    private let label = NSTextField(wrappingLabelWithString: "")
    private var fragments: [Fragment] = []
    override var isFlipped: Bool { true }

    init(number: Int) {
        self.number = number
        super.init(frame: .zero)
        label.isSelectable = false
        label.setAccessibilityElement(false)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ fragments: [Fragment]) {
        self.fragments = fragments
        let text = NSMutableAttributedString(string: "")
        var spoken = "\(number). "
        for fragment in fragments {
            let value: String
            let weight: NSFont.Weight
            switch fragment {
            case .text(let string): value = string; weight = .light
            case .menu(let string): value = string; weight = .semibold
            case .separator:
                spoken += ", "
                let font = NSFont.systemFont(ofSize: 14, weight: .light)
                let attachment = NSTextAttachment()
                effectiveAppearance.performAsCurrentDrawingAppearance {
                    attachment.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(pointSize: 14, weight: .light))?
                        .withSymbolConfiguration(.init(paletteColors: [OnboardingPasswordPalette.instruction]))
                }
                let size = attachment.image?.size ?? NSSize(width: 7, height: 10)
                attachment.bounds = NSRect(x: 0, y: (font.capHeight - size.height) / 2,
                                           width: size.width, height: size.height)
                let space = NSAttributedString(string: " ", attributes: [.font: font])
                text.append(space)
                text.append(NSAttributedString(attachment: attachment))
                text.append(space)
                continue
            }
            spoken += value
            text.append(NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: weight)]))
        }
        text.addAttribute(.foregroundColor, value: OnboardingPasswordPalette.instruction,
                          range: NSRange(location: 0, length: text.length))
        label.attributedStringValue = text
        setAccessibilityLabel(spoken)
        needsLayout = true; needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        configure(fragments)
    }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 28)
        let height = label.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
        label.frame = NSRect(x: 28, y: max(0, (bounds.height - height) / 2), width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let badge = NSRect(x: 0, y: (bounds.height - 20) / 2, width: 20, height: 20)
        OnboardingPasswordPalette.background.setFill()
        NSBezierPath(ovalIn: badge).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: OnboardingPasswordPalette.foreground]
        let string = String(number) as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2),
                    withAttributes: attributes)
    }
}
