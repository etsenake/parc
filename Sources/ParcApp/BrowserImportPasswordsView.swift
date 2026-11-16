import AppKit

@MainActor
final class BrowserImportPasswordsView: NSView {
    var onChooseFile: (() -> Void)?
    var onDropFile: ((URL) -> Void)?
    var onHelp: (() -> Void)?
    var onContinue: (() -> Void)?
    var onStop: (() -> Void)?
    var onRemoveFile: (() -> Void)?
    private let title = NSTextField(wrappingLabelWithString: "Stay logged in.")
    private let detail = NSTextField(wrappingLabelWithString: "To manually import passwords from Safari, you’ll have to export them.")
    private let help = ActionButton("How do I find this?")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let continueButton = ParcDialogButton(title: "Skip Passwords", primary: true, hint: false)
    private let stop = ActionButton("Stop Import")
    private let remove = ActionButton("Move exported file to Trash…")
    private let dropTarget = OnboardingPasswordDropTarget(frame: .zero)
    private let instructions = (1...3).map { OnboardingPasswordInstructionRow(number: $0) }
    var usesSetupCard = false { didSet { configurePresentation() } }
    var export: BrowserPasswordExport = .safari { didSet { if export != oldValue { configureInstructions() } } }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 26, weight: .bold)
        detail.font = .systemFont(ofSize: 14)
        status.font = .systemFont(ofSize: 13)
        for button in [stop, remove] {
            button.isBordered = true; button.bezelStyle = .rounded; button.focusRingType = .default
        }
        help.isBordered = false; help.alignment = .left; help.focusRingType = .default
        help.actionBlock = { [weak self] in self?.onHelp?() }
        continueButton.target = self; continueButton.action = #selector(continueClicked)
        stop.actionBlock = { [weak self] in self?.onStop?() }
        remove.actionBlock = { [weak self] in self?.onRemoveFile?() }
        [title, detail, help, status, continueButton, stop, remove].forEach(addSubview)
        dropTarget.onChoose = { [weak self] in self?.onChooseFile?() }
        dropTarget.onDrop = { [weak self] in self?.onDropFile?($0) }
        addSubview(dropTarget)
        instructions.forEach(addSubview)
        configureInstructions()
        configurePresentation()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func continueClicked() { onContinue?() }
    private func configureInstructions() {
        switch export {
        case .safari:
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
            detail.stringValue = "To manually import passwords from Safari, you’ll have to export them."
        case .firefox:
            instructions[0].configure([.text("In Firefox, open the "), .symbol("☰", spoken: "application"),
                                       .text(" menu and choose "), .menu("Passwords"), .text(".")])
            instructions[1].configure([.text("Choose "), .symbol("⋯", spoken: "the Passwords page menu"), .separator,
                                       .menu("Export Passwords…"), .text(".")])
            instructions[2].configure([.text("Upload your passwords.csv file to Parc.")])
            detail.stringValue = "To use your Firefox passwords in Parc, you’ll have to export them from Firefox."
        }
        setAccessibilityLabel("Import exported \(export.browserName) passwords")
    }
    private var ink: NSColor { usesSetupCard ? OnboardingSetupPalette.title : ParcDialogStyle.popoverTitle }
    private func configurePresentation() {
        title.isHidden = usesSetupCard; detail.isHidden = usesSetupCard; continueButton.isHidden = usesSetupCard
        continueButton.keyEquivalent = usesSetupCard ? "" : "\r"
        [title, detail, status].forEach { $0.textColor = ink }
        instructions.forEach { $0.ink = ink }
        help.attributedTitle = NSAttributedString(string: help.title, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular), .foregroundColor: ink,
            .underlineStyle: NSUnderlineStyle.single.rawValue])
        for button in [stop, remove] { button.contentTintColor = ink }
        needsLayout = true
    }
    func update(canImport: Bool, busy: Bool, removing: Bool,
                result: PCNativePasswordFileImportResult?, canRemove: Bool, error: String?) {
        help.isEnabled = !busy && !removing
        stop.isHidden = !busy; stop.isEnabled = busy
        continueButton.isEnabled = !busy && !removing; continueButton.isLoading = busy || removing
        let continueTitle = result == nil ? "Skip Passwords" : "Continue"
        if continueButton.title != continueTitle { continueButton.title = continueTitle; needsLayout = true }
        remove.isHidden = !canRemove; remove.isEnabled = canRemove && !removing
        var problem = error
        if problem == nil, !busy, let outcome = result?.outcome, outcome != .completed {
            problem = outcome == .cancelled ? "Import stopped." : outcome == .partial
                ? "Some passwords couldn’t be imported." : "The passwords couldn’t be imported."
        }
        status.stringValue = problem ?? ""
        let presentation: OnboardingPasswordDropTarget.Presentation
        if removing { presentation = .removingExport }
        else if busy { presentation = .working }
        else if problem != nil { presentation = .needsAttention }
        else if result != nil { presentation = .saved }
        else { presentation = .ready }
        dropTarget.update(presentation, canImport: canImport)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let width = bounds.width
        let left = (width - 460) / 2, top: CGFloat = usesSetupCard ? 0 : 90
        if !usesSetupCard {
            title.frame = NSRect(x: left, y: 50, width: 460, height: 34)
            detail.frame = NSRect(x: left, y: 90, width: 460, height: 40)
        }
        instructions[0].frame = NSRect(x: left, y: top + 60, width: 460, height: 30)
        instructions[1].frame = NSRect(x: left, y: top + 95, width: 460, height: 30)
        help.frame = NSRect(x: left + 28, y: top + 127, width: 190, height: 22)
        instructions[2].frame = NSRect(x: left, y: top + 155, width: 460, height: 30)
        dropTarget.frame = NSRect(x: left, y: top + 210, width: 460, height: 200)
        status.frame = NSRect(x: left, y: top + 418, width: 460, height: 44)
        let controls = usesSetupCard ? top + 465 : bounds.height - 60
        stop.frame = NSRect(x: left, y: controls, width: 150, height: 30)
        remove.frame = NSRect(x: left, y: controls, width: 270, height: 30)
        continueButton.frame = NSRect(x: width - 28 - continueButton.bodyWidth - 0.5, y: bounds.height - 64.5,
                                      width: continueButton.bodyWidth + 1, height: 38.5)
    }
}
@MainActor
final class OnboardingPasswordInstructionRow: NSView {
    enum Fragment { case text(String), menu(String), symbol(String, spoken: String), separator }
    private let number: Int
    private let label = NSTextField(wrappingLabelWithString: "")
    private var fragments: [Fragment] = []
    var ink: NSColor = OnboardingSetupPalette.title { didSet { configure(fragments) } }
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
            case .symbol(let string, let words):
                spoken += words
                text.append(NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]))
                continue
            case .separator:
                spoken += ", "
                let font = NSFont.systemFont(ofSize: 14, weight: .light)
                let attachment = NSTextAttachment()
                effectiveAppearance.performAsCurrentDrawingAppearance {
                    attachment.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(pointSize: 14, weight: .light))?
                        .withSymbolConfiguration(.init(paletteColors: [ink]))
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
        text.addAttribute(.foregroundColor, value: ink,
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
