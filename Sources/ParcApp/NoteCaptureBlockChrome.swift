import AppKit

@MainActor
final class NoteCaptureSnapshotHeader: NSView {
    static let educationKey = "easel.liveCaptureEducationSeen"
    static let minimumWidth: CGFloat = 320
    var onMakeLive: (() -> Void)?
    var onSnapshot: (() -> Void)?
    var onOpen: (() -> Void)?
    private let header = EmbeddedPageHeader()
    private let makeLive = NoteChip(EaselWebItemChrome.makeLiveTitle, icon: .symbol("dot.radiowaves.left.and.right"), style: .filled)
    private let snapshot = NoteChip(EaselWebItemChrome.backToSnapshotTitle, icon: .symbol("photo"))
    private let openButton = NoteToolbarButton(icon: .symbol("arrow.up.right.square"), label: "Open in a tab")
    private var address: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = NoteMediaStyle.cardRadius
        layer?.cornerCurve = .continuous
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.borderWidth = 1
        header.showsRule = false
        addSubview(header)
        makeLive.onPress = { [weak self] in self?.onMakeLive?() }
        makeLive.setToolTip(EaselWebItemChrome.makeLiveHelp)
        snapshot.onPress = { [weak self] in self?.onSnapshot?() }
        snapshot.setToolTip(EaselWebItemChrome.backToSnapshotHelp)
        openButton.onPress = { [weak self] in self?.onOpen?() }
        header.buttons = [openButton]
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(block: NoteBlock, canEdit: Bool) {
        guard let capture = NoteCaptureLive.capture(of: block) else { return }
        let address = capture.sourceAddress
        let title = NoteCaptureText.title(for: capture, alt: block.props.alt)
        header.setPage(title: title, host: address.map(NoteCaptureText.displayHost) ?? capture.sourceURL)
        let live = NoteCaptureLive.ownsLivePage(block)
        header.setBadge(NoteCaptureLive.badge(of: block), help: NoteCaptureLive.badgeHelp(of: block), live: live)
        if live {
            header.action = canEdit ? snapshot : nil
        } else {
            header.action = canEdit && NoteCaptureLive.canMakeLive(block) ? makeLive : nil
        }
        openButton.isHidden = address == nil
        if let address, address != self.address {
            self.address = address
            header.loadPreview(for: address) { _ in }
        }
        setAccessibilityLabel("Captured from " + (address.map(NoteCaptureText.displayHost) ?? capture.sourceURL))
        setAccessibilityValue(NoteCaptureLive.badge(of: block))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        header.frame = bounds
        NoteMediaMotion.instant {
            layer?.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardFill, in: self)
            layer?.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    static func frame(imageRect: NSRect, columnWidth: CGFloat, alignment: NoteAlignment) -> NSRect {
        let width = max(imageRect.width, min(minimumWidth, columnWidth))
        let x: CGFloat
        switch alignment {
        case .left: x = imageRect.minX
        case .right: x = imageRect.maxX - width
        default: x = imageRect.midX - width / 2
        }
        return NSRect(x: min(max(0, x.rounded()), max(0, columnWidth - width)), y: 0, width: width, height: EmbeddedPageHeader.height)
    }

    static func presentEducation(in window: NSWindow?, confirmed: @escaping () -> Void) -> ParcDialog? {
        guard let window, window.isKeyWindow, window.attachedSheet == nil else { return nil }
        let alert = ParcDialog(.init(title: "Make it Live",
            message: "See an up-to-date, interactive view of the region you captured. This does not work on all sites. You can always return to the original screenshot with Snapshot.",
            confirm: "Make it Live", cancel: "Cancel"))
        guard alert.begin(for: window, completion: { response in
            guard response == .confirm else { return }
            UserDefaults.standard.set(true, forKey: educationKey)
            confirmed()
        }) else { return nil }
        return alert
    }
}
