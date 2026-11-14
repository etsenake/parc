import AppKit
import CoreText

@MainActor
enum NoteDocumentAppearance {
    private static let registerFonts: Void = {
        for name in ["Nunito-ExtraBold", "Nunito-Regular", "Nunito-Bold", "Nunito-Italic", "Nunito-BoldItalic"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "NoteFonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()
    static var titleFont: NSFont {
        _ = registerFonts
        return NSFont(name: "Nunito-ExtraBold", size: 34) ?? .systemFont(ofSize: 34, weight: .heavy)
    }
    static var bodyFont: NSFont {
        _ = registerFonts
        return NSFont(name: "Nunito-Regular", size: 18) ?? .systemFont(ofSize: 18)
    }
    static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraph.lineHeightMultiple = 1.25; paragraph.paragraphSpacingBefore = 4; paragraph.paragraphSpacing = 8
        return [.font: bodyFont, .foregroundColor: bodyColor, .paragraphStyle: paragraph]
    }
    static func attributedBody(_ body: NoteBody) -> NSAttributedString {
        let result = NSMutableAttributedString(string: body.text, attributes: bodyAttributes)
        for run in body.richText.runs {
            result.setAttributes(EaselRichTextCodec.attributes(run.attributes), range: NSRange(location: run.location, length: run.length))
        }
        return result
    }
    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("Parc.Note." + name)) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
    static let backgroundColor = NotePaper.color
    static let bodyColor = EaselRichTextCodec.noteBodyColor
    static let cursorColor = adaptive("Cursor", light: NSColor(srgbRed: 39 / 255, green: 2 / 255, blue: 194 / 255, alpha: 1),
        dark: NSColor(srgbRed: 147 / 255, green: 128 / 255, blue: 224 / 255, alpha: 1))
    static let selectionColor = adaptive("Selection", light: NSColor(srgbRed: 205 / 255, green: 205 / 255, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 82 / 255, green: 53 / 255, blue: 206 / 255, alpha: 1))
    static let linkColor = adaptive("Link", light: NSColor(srgbRed: 0.133, green: 0.047, blue: 0.498, alpha: 1),
        dark: NSColor(srgbRed: 0.902, green: 0.902, blue: 1, alpha: 1))
    static var titleAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.25; paragraph.paragraphSpacingBefore = 4; paragraph.paragraphSpacing = 8
        return [.font: titleFont, .foregroundColor: titleColor, .paragraphStyle: paragraph]
    }
    static let titleColor = adaptive("Title", light: NSColor(srgbRed: 34 / 255, green: 12 / 255, blue: 127 / 255, alpha: 1),
        dark: NSColor(srgbRed: 230 / 255, green: 230 / 255, blue: 1, alpha: 1))
    static let placeholderColor = adaptive("TitlePlaceholder", light: NSColor(srgbRed: 0.133, green: 0.047, blue: 0.498, alpha: 0.4),
        dark: NSColor(srgbRed: 0.902, green: 0.902, blue: 1, alpha: 0.4))
    static var titlePlaceholder: NSAttributedString {
        var attributes = titleAttributes
        attributes[.foregroundColor] = placeholderColor
        return NSAttributedString(string: NSLocalizedString("Title", comment: "Placeholder for 'title' string"), attributes: attributes)
    }
}

@MainActor
final class NoteDocumentLayout: NSView {
    let column = NSView()
    let titleContainer = NSView()
    let bodyContainer = NSView()
    private var titleHeight: NSLayoutConstraint!
    private var minimumInsets: [NSLayoutConstraint] = []
    override var isFlipped: Bool { true }

    init(title: NSTextView, body: NSTextView) {
        super.init(frame: .zero)
        addSubview(column); column.translatesAutoresizingMaskIntoConstraints = false
        for container in [titleContainer, bodyContainer] {
            column.addSubview(container); container.translatesAutoresizingMaskIntoConstraints = false
        }
        titleContainer.addSubview(title); bodyContainer.addSubview(body)
        let preferredWidth = column.widthAnchor.constraint(equalToConstant: 900)
        preferredWidth.priority = .defaultHigh
        titleHeight = titleContainer.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 900), preferredWidth,
            titleContainer.topAnchor.constraint(equalTo: column.topAnchor, constant: 64), titleHeight,
            bodyContainer.topAnchor.constraint(equalTo: titleContainer.bottomAnchor, constant: 16),
            bodyContainer.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -64)
        ])
        for container in [titleContainer, bodyContainer] {
            let leading = container.leadingAnchor.constraint(greaterThanOrEqualTo: column.leadingAnchor, constant: 20)
            let trailing = container.trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor, constant: -20)
            minimumInsets += [leading, trailing]
            let preferredLeading = container.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 100)
            let preferredTrailing = container.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -100)
            let minimumWidth = container.widthAnchor.constraint(greaterThanOrEqualToConstant: 250)
            for constraint in [preferredLeading, preferredTrailing, minimumWidth] { constraint.priority = .defaultHigh }
            NSLayoutConstraint.activate([leading, trailing, preferredLeading, preferredTrailing, minimumWidth,
                                         container.centerXAnchor.constraint(equalTo: column.centerXAnchor)])
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func arrange(viewport: NSSize, title: NSTextView, body: NSTextView) {
        let inset = min(20, max(0, viewport.width) / 2)
        for (index, constraint) in minimumInsets.enumerated() { constraint.constant = index.isMultiple(of: 2) ? inset : -inset }
        setFrameSize(NSSize(width: max(0, viewport.width), height: max(145, viewport.height)))
        layoutSubtreeIfNeeded()
        let titleUsed = measure(title, width: titleContainer.bounds.width)
        let bodyUsed = measure(body, width: bodyContainer.bounds.width)
        applyMeasuredHeight(viewport: viewport, title: title, body: body, titleUsed: titleUsed, bodyUsed: bodyUsed)
    }

    @discardableResult
    func reflowIfHeightChanged(viewport: NSSize, title: NSTextView, body: NSTextView) -> Bool {
        let width = titleContainer.bounds.width
        guard width >= 1 else {
            arrange(viewport: viewport, title: title, body: body)
            return true
        }
        let titleUsed = measure(title, width: width)
        let bodyUsed = measure(body, width: bodyContainer.bounds.width)
        let next = NSSize(width: max(0, viewport.width), height: max(viewport.height, 64 + titleUsed + 16 + bodyUsed + 64))
        if titleHeight.constant == titleUsed && bounds.size == next {
            title.frame = titleContainer.bounds; body.frame = bodyContainer.bounds
            return false
        }
        applyMeasuredHeight(viewport: viewport, title: title, body: body, titleUsed: titleUsed, bodyUsed: bodyUsed)
        return true
    }

    private func applyMeasuredHeight(viewport: NSSize, title: NSTextView, body: NSTextView, titleUsed: CGFloat, bodyUsed: CGFloat) {
        titleHeight.constant = titleUsed
        setFrameSize(NSSize(width: max(0, viewport.width), height: max(viewport.height, 64 + titleUsed + 16 + bodyUsed + 64)))
        layoutSubtreeIfNeeded()
        title.frame = titleContainer.bounds; body.frame = bodyContainer.bounds
    }
    private func measure(_ text: NSTextView, width: CGFloat) -> CGFloat {
        guard let container = text.textContainer, let layout = text.layoutManager else { return 1 }
        text.setFrameSize(NSSize(width: max(0, width), height: max(1, text.frame.height)))
        container.containerSize = NSSize(width: max(1, width - 2 * text.textContainerInset.width), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let line = layout.defaultLineHeight(for: text.font ?? .systemFont(ofSize: 15))
        let extra = layout.extraLineFragmentTextContainer === container ? layout.extraLineFragmentRect.maxY : 0
        return ceil(max(line, layout.usedRect(for: container).maxY, extra) + 2 * text.textContainerInset.height)
    }
}

@MainActor
final class NoteLoadErrorView: NoteCanvasView {
    let heading = NSTextField(wrappingLabelWithString: "Can't load this note")
    let detail: NSTextField
    private let content = NSView()
    override var isFlipped: Bool { true }
    init(error: Error) {
        detail = NSTextField(wrappingLabelWithString: error.localizedDescription)
        super.init(frame: .zero)
        heading.font = NoteDocumentAppearance.titleFont; heading.textColor = NoteDocumentAppearance.titleColor
        detail.font = NoteDocumentAppearance.bodyFont; detail.textColor = .secondaryLabelColor
        for label in [heading, detail] {
            label.alignment = .center; label.maximumNumberOfLines = 0; label.isSelectable = true
            label.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(label)
        }
        content.translatesAutoresizingMaskIntoConstraints = false; addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor), content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            heading.topAnchor.constraint(equalTo: content.topAnchor), heading.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            heading.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detail.topAnchor.constraint(equalTo: heading.bottomAnchor), detail.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            detail.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20)
        ])
        let width = content.widthAnchor.constraint(equalToConstant: 500); width.priority = .defaultHigh; width.isActive = true
        NoteAccessibility.configureLoadError(self, heading: heading, detail: detail)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
class NoteCanvasView: LocalContentDropView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NoteDocumentAppearance.backgroundColor.setFill()
        dirtyRect.fill(using: .sourceOver)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func inheritSpaceContentAppearance(_ appearance: NSAppearance?) {
        guard self.appearance != appearance else { return }
        self.appearance = appearance
        needsDisplay = true
    }
}
