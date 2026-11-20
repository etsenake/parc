import AppKit

@MainActor
final class NoteMermaidCanvas: NSView {
    var image: NSImage? { didSet { if image !== oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
}

@MainActor
final class NoteMermaidStage: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class NoteMermaidProblemView: NSView {
    static let inset = NSEdgeInsets(top: 9, left: 12, bottom: 10, right: 12)
    static let iconSize: CGFloat = 14
    static let iconGap: CGFloat = 8
    static let lineGap: CGFloat = 3

    private let icon = NoteIconView(icon: .symbol("exclamationmark.triangle.fill"), pointSize: 11)
    private let headline = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private(set) var problem: NoteMermaidProblem?

    private var headlineFont: NSFont { NoteTheme.nunitoBold(13) }
    private var detailFont: NSFont { NoteCodeFont.code(size: 11.5) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        icon.tint = NoteTheme.destructiveInk
        addSubview(icon)
        for label in [headline, detail] {
            label.isSelectable = false
            label.drawsBackground = false
            label.isBezeled = false
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.setAccessibilityElement(false)
            addSubview(label)
        }
        headline.font = headlineFont
        headline.textColor = NoteTheme.destructiveInk
        detail.font = detailFont
        detail.textColor = NoteTheme.secondaryInk
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        refreshFill()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func show(_ problem: NoteMermaidProblem?) {
        self.problem = problem
        headline.stringValue = problem?.headline ?? ""
        detail.stringValue = problem?.detail ?? ""
        detail.isHidden = problem?.detail == nil
        let spoken = [problem?.headline, problem?.detail].compactMap { $0 }.joined(separator: ". ")
        setAccessibilityLabel(spoken.isEmpty ? nil : "Mermaid error: " + spoken)
        needsLayout = true
    }

    private func textWidth(for width: CGFloat) -> CGFloat {
        max(40, width - Self.inset.left - Self.iconSize - Self.iconGap - Self.inset.right)
    }

    private func height(of text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let rect = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height) + 2
    }

    func height(for width: CGFloat) -> CGFloat {
        guard let problem else { return 0 }
        let text = textWidth(for: width)
        var total = Self.inset.top + height(of: problem.headline, font: headlineFont, width: text)
        if let detail = problem.detail { total += Self.lineGap + height(of: detail, font: detailFont, width: text) }
        return ceil(max(total + Self.inset.bottom, Self.inset.top + Self.iconSize + Self.inset.bottom))
    }

    override func layout() {
        super.layout()
        let text = textWidth(for: bounds.width)
        let x = Self.inset.left + Self.iconSize + Self.iconGap
        let headlineHeight = height(of: headline.stringValue, font: headlineFont, width: text)
        icon.frame = NSRect(x: Self.inset.left - 2, y: Self.inset.top + 1, width: Self.iconSize + 4, height: Self.iconSize + 4)
        headline.frame = NSRect(x: x, y: Self.inset.top, width: text, height: headlineHeight)
        let detailHeight = height(of: detail.stringValue, font: detailFont, width: text)
        detail.frame = NSRect(x: x, y: headline.frame.maxY + Self.lineGap, width: text, height: detailHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFill()
    }

    private func refreshFill() {
        NoteAnimation.withoutAnimation { layer?.backgroundColor = NoteTheme.resolved(NoteTheme.destructiveHighlight, in: self) }
    }
}

@MainActor
final class NoteMermaidPreviewView: NSView {
    static let padding = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    static let emptyHeight: CGFloat = 44
    static let problemGap: CGFloat = 12
    static let drawingTitle = "Drawing your diagram…"
    static let emptyTitle = "Type some Mermaid and watch it draw itself."

    let scrollView = NoteCodeScrollView()
    let stage = NoteMermaidStage()
    let canvas = NoteMermaidCanvas()
    private let problemView = NoteMermaidProblemView()
    private let note = NSTextField(labelWithString: "")
    private(set) var art: NoteMermaidArt?
    private(set) var problem: NoteMermaidProblem?
    private(set) var message: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        stage.addSubview(canvas)
        scrollView.documentView = stage
        addSubview(scrollView)
        problemView.isHidden = true
        addSubview(problemView)
        note.font = NoteTheme.nunitoRegular(13.5)
        note.textColor = NoteTheme.tertiaryInk
        note.alignment = .center
        note.lineBreakMode = .byTruncatingTail
        note.isHidden = true
        addSubview(note)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        refreshAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var hasDrawing: Bool { art != nil }

    func show(art: NoteMermaidArt?, problem: NoteMermaidProblem?, message: String?, animated: Bool) {
        let replacing = art?.image !== self.art?.image
        self.art = art
        self.problem = problem
        self.message = art == nil && problem == nil ? message : nil
        if replacing, animated, window != nil, !NoteAnimation.reduceMotion, let layer = canvas.layer {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.14
            transition.timingFunction = NoteCurve.easeOut
            layer.add(transition, forKey: NoteAnimation.keyPrefix + "diagram")
        }
        canvas.image = art?.image
        canvas.isHidden = art == nil
        problemView.show(problem)
        problemView.isHidden = problem == nil
        note.stringValue = self.message ?? ""
        note.isHidden = self.message == nil
        scrollView.hasHorizontalScroller = false
        refreshAccessibility()
        needsLayout = true
    }

    private func innerWidth(for width: CGFloat) -> CGFloat {
        max(40, width - Self.padding.left - Self.padding.right)
    }

    private var drawingHeight: CGFloat {
        if let art { return ceil(art.size.height) }
        return problem == nil ? Self.emptyHeight : 0
    }

    func height(for width: CGFloat) -> CGFloat {
        let inner = innerWidth(for: width)
        var total = Self.padding.top + drawingHeight
        if problem != nil {
            if art != nil { total += Self.problemGap }
            total += problemView.height(for: inner)
        }
        return ceil(total + Self.padding.bottom)
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            let inner = innerWidth(for: bounds.width)
            let drawing = drawingHeight
            let size = art?.size ?? .zero
            let stageWidth = max(inner, ceil(size.width))
            scrollView.frame = NSRect(x: Self.padding.left, y: Self.padding.top, width: inner, height: drawing)
            stage.frame = NSRect(x: 0, y: 0, width: stageWidth, height: drawing)
            canvas.frame = NSRect(x: ((stageWidth - ceil(size.width)) / 2).rounded(), y: 0, width: ceil(size.width), height: ceil(size.height))
            scrollView.hasHorizontalScroller = stageWidth > inner + 0.5
            note.frame = NSRect(x: Self.padding.left, y: Self.padding.top + (drawing - 20) / 2, width: inner, height: 20)
            let problemTop = Self.padding.top + drawing + (art != nil ? Self.problemGap : 0)
            problemView.frame = NSRect(x: Self.padding.left, y: art == nil && problem != nil ? Self.padding.top : problemTop,
                                       width: inner, height: problemView.height(for: inner))
        }
    }

    private func refreshAccessibility() {
        if art != nil {
            setAccessibilityRole(.image)
            setAccessibilityLabel(problem == nil ? "Mermaid diagram" : "Mermaid diagram, last good drawing")
        } else {
            setAccessibilityRole(.group)
            setAccessibilityLabel(problem == nil ? message : "Mermaid diagram with an error")
        }
    }
}

@MainActor
final class NoteDiagramModeSegment: NoteControlButton {
    let mode: NoteDiagramMode

    init(_ mode: NoteDiagramMode) {
        self.mode = mode
        super.init(frame: NSRect(x: 0, y: 0, width: 60, height: NoteTheme.chipHeight))
        setAccessibilityLabel(mode.title)
        setAccessibilityRole(.radioButton)
        setFrameSize(intrinsicContentSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var titleFont: NSFont { NoteTheme.chromeFont(12.5) }

    override var intrinsicContentSize: NSSize {
        let width = ceil(NSAttributedString(string: mode.title, attributes: [.font: titleFont]).size().width)
        return NSSize(width: width + 18, height: NoteTheme.chipHeight)
    }

    override func fill(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor? {
        checked ? nil : super.fill(hovered: hovered, pressed: pressed, checked: false)
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        let font = titleFont
        let height = ceil(font.ascender - font.descender)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSAttributedString(string: mode.title, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
            .draw(with: NSRect(x: bounds.minX, y: (bounds.midY - height / 2).rounded(), width: bounds.width, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

@MainActor
final class NoteDiagramModeControl: NSView {
    static let spacing: CGFloat = 1

    var onChoose: ((NoteDiagramMode) -> Void)?
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            segments.forEach { $0.isEnabled = isEnabled }
            plate.alphaValue = isEnabled ? 1 : NoteTheme.disabledOpacity
        }
    }
    private let plate = NSView()
    private let segments: [NoteDiagramModeSegment]
    private(set) var selected: NoteDiagramMode = .preview

    override init(frame: NSRect) {
        segments = NoteDiagramMode.allCases.map { NoteDiagramModeSegment($0) }
        super.init(frame: frame)
        wantsLayer = true
        plate.wantsLayer = true
        plate.layer?.cornerRadius = NoteTheme.controlRadius
        plate.layer?.cornerCurve = .continuous
        addSubview(plate)
        for segment in segments {
            segment.onPress = { [weak self, weak segment] in
                guard let self, let segment, self.isEnabled else { return }
                self.onChoose?(segment.mode)
            }
            segment.setToolTip("Show " + segment.mode.title.lowercased())
            addSubview(segment)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Diagram view")
        select(.preview, animated: false)
        refreshPlate()
        setFrameSize(intrinsicContentSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let widths = segments.map(\.intrinsicContentSize.width).reduce(0, +)
        return NSSize(width: widths + Self.spacing * CGFloat(segments.count - 1), height: NoteTheme.chipHeight)
    }

    func select(_ mode: NoteDiagramMode, animated: Bool) {
        selected = mode
        for segment in segments {
            segment.isChecked = segment.mode == mode
            segment.setAccessibilityValue(segment.mode == mode ? 1 : 0)
        }
        setAccessibilityValue(mode.title)
        guard let target = segments.first(where: { $0.mode == mode })?.frame, !target.isEmpty else { return }
        if animated, window != nil, !NoteAnimation.reduceMotion {
            NoteAnimation.slide(plate, to: target, spring: .highlight)
        } else {
            NoteAnimation.withoutAnimation { plate.frame = target }
        }
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            var x: CGFloat = 0
            for segment in segments {
                let width = segment.intrinsicContentSize.width
                segment.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
                x += width + Self.spacing
            }
            if let target = segments.first(where: { $0.mode == selected })?.frame, plate.layer?.animationKeys()?.isEmpty ?? true {
                plate.frame = target
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPlate()
    }

    private func refreshPlate() {
        NoteAnimation.withoutAnimation { plate.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.checkedFill, in: self) }
    }

    override func accessibilityChildren() -> [Any]? { segments }
}
