import AppKit

final class CommandResultCell: NSView {
    var onPress: (() -> Bool)?
    var onDelete: (() -> Bool)? {
        didSet {
            setAccessibilityCustomActions(onDelete == nil ? [] : [
                NSAccessibilityCustomAction(name: "Delete Suggestion") { [weak self] in self?.deleteSuggestion() ?? false }
            ])
            updateDeleteVisibility(); needsLayout = true
        }
    }
    static let iconTileIdentifier = NSUserInterfaceItemIdentifier("CommandResultIconTile")
    private let deleteButton = PointingHandButton()
    private var isHovered = false
    var selectedColor: NSColor = CommandBarPalette.colourless.selected { didSet { setSelected(isSelected) } }
    private var isSelected = false
    private let isAction: Bool
    private let iconTile = NSView()
    private let icon = NSImageView()
    private var baseIcon: NSImage?
    private let label = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let accessory = NSTextField(labelWithString: "")
    private let badge = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let spaceCapsule = NSView()
    private let spaceIcon = NSImageView()
    private let spaceLabel = NSTextField(labelWithString: "")
    private let spaceDetail = NSTextField(labelWithString: "")
    private let hasContext: Bool
    private let isTab: Bool
    private let title: String
    private let subtitle: String?
    private let detail: String
    private let enabled: Bool
    init(title: String, subtitle: String? = nil, detail: String, accessory: String, isTab: Bool, icon: NSImage?,
         spokenAccessory: String? = nil, spokenSubtitle: String? = nil, enabled: Bool,
         spaceAction: CommandBarSpaceAction? = nil, folderAction: CommandBarFolderAction? = nil, isAction: Bool = false) {
        self.title = title; self.subtitle = subtitle; self.detail = detail; self.enabled = enabled; self.isTab = isTab
        self.hasContext = spaceAction != nil || folderAction != nil
        self.isAction = isAction
        super.init(frame: .zero)
        iconTile.wantsLayer = true; iconTile.layer?.cornerRadius = 4; iconTile.layer?.cornerCurve = .continuous
        iconTile.identifier = Self.iconTileIdentifier
        addSubview(iconTile)
        baseIcon = icon; self.icon.imageScaling = .scaleProportionallyDown
        self.accessory.stringValue = isTab ? accessory : ""; self.accessory.font = CommandBarTypography.label
        self.accessory.alignment = .right; self.accessory.lineBreakMode = .byTruncatingTail
        badgeLabel.stringValue = isTab ? "→" : accessory
        badgeLabel.font = .systemFont(ofSize: isTab ? 17 : 12, weight: .medium)
        if isTab { badgeLabel.alignment = .center }
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4; badge.layer?.cornerCurve = .continuous; badge.layer?.masksToBounds = true
        badge.isHidden = badgeLabel.stringValue.isEmpty
        badge.addSubview(badgeLabel)
        label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingMiddle; subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.isHidden = hasContext || (subtitle ?? "").isEmpty
        addSubview(self.icon); addSubview(label); addSubview(subtitleLabel); addSubview(self.accessory); addSubview(badge)
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        deleteButton.imageScaling = .scaleProportionallyDown
        deleteButton.parcTooltip = TooltipConfiguration("Delete Suggestion",
                                                        shortcut: .fixed(KeyboardShortcut(key: "\u{7f}", flags: [.command, .option])))
        deleteButton.setAccessibilityHelp("Delete Suggestion (⌘⌥⌫)"); deleteButton.cell?.setAccessibilityHelp("Delete Suggestion (⌘⌥⌫)")
        deleteButton.setAccessibilityLabel("Delete Suggestion")
        deleteButton.target = self; deleteButton.action = #selector(deleteSuggestion)
        deleteButton.isHidden = true; addSubview(deleteButton)
        spaceCapsule.wantsLayer = true; spaceCapsule.layer?.cornerRadius = 4
        spaceCapsule.isHidden = !hasContext
        spaceCapsule.toolTip = spaceAction.map { $0.detail.isEmpty ? $0.name : $0.name + " — " + $0.detail }
            ?? folderAction.map { $0.name + " — " + $0.detail }
        spaceLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        spaceLabel.lineBreakMode = .byTruncatingTail
        spaceIcon.imageScaling = .scaleProportionallyDown
        spaceLabel.stringValue = spaceAction?.name ?? folderAction?.name ?? ""
        spaceIcon.image = NSImage(systemSymbolName: spaceAction?.symbol ?? "folder", accessibilityDescription: nil)
        spaceCapsule.addSubview(spaceIcon); spaceCapsule.addSubview(spaceLabel); addSubview(spaceCapsule)
        spaceDetail.stringValue = hasContext ? detail : ""
        spaceDetail.font = .systemFont(ofSize: 12); spaceDetail.lineBreakMode = .byTruncatingTail
        addSubview(spaceDetail)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel([title, spaceAction?.name ?? folderAction?.name ?? "", hasContext ? detail : spokenSubtitle ?? subtitle ?? "",
                               spokenAccessory ?? accessory].filter { !$0.isEmpty }.joined(separator: ", "))
        setAccessibilityEnabled(enabled)
        setSelected(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func setIcon(_ image: NSImage) { baseIcon = image; setSelected(isSelected) }
    private var showsTile: Bool { isAction || (isSelected && baseIcon?.isTemplate == false) }
    func setSelected(_ value: Bool) {
        isSelected = value
        let primary: NSColor = enabled ? (value ? CommandBarPalette.selectedText : CommandBarPalette.textPrimary) : .disabledControlTextColor
        let secondary = value ? CommandBarPalette.selectedSecondaryText : CommandBarPalette.textSecondary
        let font = CommandBarTypography.label
        label.attributedStringValue = Self.line(title, font: font, color: primary, truncation: .byTruncatingTail)
        subtitleLabel.attributedStringValue = Self.line(subtitle ?? "", font: font, color: secondary, truncation: .byTruncatingMiddle)
        accessory.textColor = value ? CommandBarPalette.selectedText : CommandBarPalette.textSecondary
        iconTile.isHidden = !showsTile
        if value, showsTile, let base = baseIcon, base.isTemplate {
            icon.image = Self.tinted(base, selectedColor)
        } else {
            icon.image = baseIcon
        }
        icon.contentTintColor = isAction && !value ? CommandBarPalette.accessoryForeground : primary
        effectiveAppearance.performAsCurrentDrawingAppearance {
            iconTile.layer?.backgroundColor = (value ? CommandBarPalette.selectedTile : CommandBarPalette.accessoryBackground).cgColor
            badge.layer?.backgroundColor = (value ? CommandBarPalette.selectedTile : CommandBarPalette.accessoryBackground).cgColor
        }
        let badgeColor: NSColor = value ? selectedColor : CommandBarPalette.accessoryForeground
        if isTab {
            badgeLabel.textColor = badgeColor
        } else {
            let clipping = NSMutableParagraphStyle(); clipping.lineBreakMode = .byClipping
            badgeLabel.attributedStringValue = NSAttributedString(string: badgeLabel.stringValue, attributes: [
                .font: badgeLabel.font ?? .systemFont(ofSize: 12, weight: .medium), .foregroundColor: badgeColor,
                .kern: 2, .paragraphStyle: clipping
            ])
        }
        spaceLabel.textColor = primary; spaceIcon.contentTintColor = primary
        spaceDetail.textColor = secondary
        effectiveAppearance.performAsCurrentDrawingAppearance {
            spaceCapsule.layer?.backgroundColor = (value ? NSColor.white.withAlphaComponent(0.16)
                                                        : CommandBarPalette.accessoryBackground).cgColor
        }
        deleteButton.contentTintColor = primary
        alphaValue = enabled ? 1 : 0.55
        setAccessibilitySelected(value)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); setSelected(isSelected)
    }
    override func layout() {
        super.layout()
        let text = badgeLabel.intrinsicContentSize
        let badgeSize = badge.isHidden ? .zero : isTab ? NSSize(width: 23, height: 23)
            : NSSize(width: ceil(text.width) + 6, height: ceil(text.height) + 8)
        let badgeWidth = badgeSize.width
        let textWidth = isTab ? min(bounds.width * 0.30, accessory.singleLineWidth) : 0
        let deleteWidth: CGFloat = onDelete == nil ? 0 : 23
        let trailing = max(deleteWidth, badgeWidth + (textWidth > 0 ? textWidth + 8 : 0))
        deleteButton.frame = NSRect(x: max(0, bounds.width - 35), y: 14, width: min(23, bounds.width), height: 23)
        iconTile.frame = NSRect(x: 11, y: 13, width: 24, height: 24)
        icon.frame = NSRect(x: 16, y: 18, width: 14, height: 14)
        badge.frame = NSRect(x: bounds.width - badgeWidth - 12, y: 14 + (23 - badgeSize.height) / 2,
                             width: badgeWidth, height: badgeSize.height)
        badgeLabel.frame = isTab ? badge.bounds
            : badgeLabel.frame(forAlignmentRect: NSRect(x: 4, y: 4, width: ceil(text.width), height: ceil(text.height)))
        accessory.frame = NSRect(x: bounds.width - trailing - 12, y: 16, width: textWidth, height: 17)
        let available = max(0, bounds.width - trailing - 70)
        if hasContext {
            let prefixWidth = min(label.singleLineWidth, available)
            label.frame = NSRect(x: 44, y: 16, width: prefixWidth, height: 17)
            let detailWidth = detail.isEmpty ? 0 : min(spaceDetail.singleLineWidth, available * 0.3)
            let reserve = detailWidth > 0 ? detailWidth + 8 : 0
            let capsuleWidth = min(max(0, available - prefixWidth - 8 - reserve), spaceLabel.singleLineWidth + 32)
            let x = label.frame.maxX + 8
            spaceCapsule.frame = NSRect(x: x, y: 13, width: capsuleWidth, height: 24)
            spaceIcon.frame = NSRect(x: 7, y: 6, width: min(12, max(0, capsuleWidth - 14)), height: 12)
            spaceLabel.frame = NSRect(x: 25, y: 3, width: max(0, capsuleWidth - 32), height: 17)
            let detailX = spaceCapsule.frame.maxX + 8
            spaceDetail.frame = NSRect(x: detailX, y: 16, width: max(0, 44 + available - detailX), height: 17)
        } else {
            let titleWidth = min(label.singleLineWidth, 480, available)
            label.frame = NSRect(x: 44, y: 16, width: titleWidth, height: 17)
            let subtitleX = label.frame.maxX + 4
            let subtitleWidth = subtitleLabel.isHidden ? 0
                : min(subtitleLabel.singleLineWidth, 280, max(0, 44 + available - subtitleX))
            subtitleLabel.frame = NSRect(x: subtitleX, y: 16, width: subtitleWidth, height: 17)
        }
    }
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let copy = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect); color.set(); rect.fill(using: .sourceAtop); return true
        }
        copy.isTemplate = false
        return copy
    }
    private static func line(_ string: String, font: NSFont, color: NSColor, truncation: NSLineBreakMode) -> NSAttributedString {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = truncation
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
    func setHovered(_ value: Bool) {
        isHovered = value; updateDeleteVisibility()
    }
    private func updateDeleteVisibility() {
        deleteButton.isHidden = !isHovered || onDelete == nil
        deleteButton.isEnabled = enabled && onDelete != nil
    }
    @objc private func deleteSuggestion() -> Bool { enabled && (onDelete?() ?? false) }
    override func accessibilityPerformPress() -> Bool { enabled && (onPress?() ?? false) }
}
