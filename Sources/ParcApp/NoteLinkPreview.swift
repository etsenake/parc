import AppKit

@MainActor
final class NoteLinkHoverCard: NSView, NoteFloatingPanelContent {
    enum Action: CaseIterable { case open, copy, edit, remove }

    static let height: CGFloat = 36
    static let maximumLabelWidth: CGFloat = 250

    var preferredSizeDidChange: (() -> Void)?
    var onAction: ((Action) -> Void)?
    let title: String
    let actions: [Action]
    private let iconView: NoteIconView
    private let label = NSTextField(labelWithString: "")
    private let divider = NSView()
    private var buttons: [(Action, NoteToolbarButton)] = []

    init(title: String, icon: NoteIcon, actions: [Action], tooltipAnchor: TooltipConfiguration.Anchor = .bottom) {
        self.title = title
        self.actions = actions
        iconView = NoteIconView(icon: icon, pointSize: 13)
        super.init(frame: .zero)
        wantsLayer = true
        iconView.tint = NoteTheme.menuSecondaryInk
        addSubview(iconView)
        label.stringValue = title
        label.font = NoteTheme.nunitoBold(13)
        label.textColor = NoteTheme.menuInk
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        label.setAccessibilityElement(true)
        addSubview(label)
        divider.wantsLayer = true
        addSubview(divider)
        for action in actions {
            let button = NoteToolbarButton(icon: Self.icon(for: action), label: Self.title(for: action))
            button.iconPointSize = 13
            button.setToolTip(Self.title(for: action), shortcut: action == .edit ? NoteFormatShortcut.link.display : nil, anchor: tooltipAnchor)
            button.onPress = { [weak self] in self?.onAction?(action) }
            buttons.append((action, button))
            addSubview(button)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Link: " + title)
        setFrameSize(intrinsicContentSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    static func title(for action: Action) -> String {
        switch action {
        case .open: return "Open Link"
        case .copy: return "Copy Link"
        case .edit: return "Edit Link"
        case .remove: return "Remove Link"
        }
    }

    static func icon(for action: Action) -> NoteIcon {
        switch action {
        case .open: return .symbol("arrow.up.right.square")
        case .copy: return .symbol("doc.on.doc")
        case .edit: return .symbol("pencil")
        case .remove: return .symbol("trash")
        }
    }

    private var labelWidth: CGFloat {
        min(Self.maximumLabelWidth, ceil(label.cell?.cellSize.width ?? label.intrinsicContentSize.width) + 1)
    }

    override var intrinsicContentSize: NSSize {
        let buttonWidth = CGFloat(buttons.count) * NoteTheme.toolbarButtonSize.width + CGFloat(max(0, buttons.count - 1))
        return NSSize(width: ceil(8 + 18 + 6 + labelWidth + 10 + 1 + 5 + buttonWidth + 4), height: Self.height)
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    override func layout() {
        super.layout()
        let height = Self.height
        NoteAnimation.withoutAnimation {
            iconView.frame = NSRect(x: 8, y: (height - 18) / 2, width: 18, height: 18)
            let labelHeight = ceil(label.intrinsicContentSize.height)
            label.frame = NSRect(x: 32, y: ((height - labelHeight) / 2).rounded(), width: labelWidth, height: labelHeight)
            divider.frame = NSRect(x: label.frame.maxX + 10, y: (height - 18) / 2, width: 1, height: 18)
            var x = divider.frame.maxX + 5
            for (_, button) in buttons {
                button.frame = NSRect(x: x, y: (height - NoteTheme.toolbarButtonSize.height) / 2,
                                      width: NoteTheme.toolbarButtonSize.width, height: NoteTheme.toolbarButtonSize.height)
                x += NoteTheme.toolbarButtonSize.width + 1
            }
            divider.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    func button(for action: Action) -> NoteToolbarButton? { buttons.first { $0.0 == action }?.1 }

    override func mouseDown(with event: NSEvent) {}
}
