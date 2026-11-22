import AppKit
import WebKit
import ParcKit

private enum UpdaterColors {
    static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    static let background = dynamic(dark: NSColor(displayP3Red: 0x1F / 255, green: 0x23 / 255, blue: 0x2D / 255, alpha: 1),
                                     light: .windowBackgroundColor)
    static let primary = dynamic(dark: NSColor.white.withAlphaComponent(0.8),
                                 light: NSColor(srgbRed: 0x0E / 255, green: 0x0F / 255, blue: 0x10 / 255, alpha: 0.9))
    static let secondary = dynamic(dark: NSColor.white.withAlphaComponent(0.5), light: NSColor.black.withAlphaComponent(0.5))
    static let button = dynamic(dark: .black, light: .white)
    static let notes = dynamic(dark: .black, light: .white)
}

private final class UpdaterButton: PointingHandButton {
    private let filled: Bool

    init(title: String, filled: Bool) {
        self.filled = filled
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        font = NSFontManager.shared.convert(.systemFont(ofSize: 13), toHaveTrait: .boldFontMask)
        contentTintColor = UpdaterColors.primary
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        if filled {
            NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 170), heightAnchor.constraint(equalToConstant: 48)])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        guard filled, let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = UpdaterColors.button.cgColor
        }
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 5
        layer.shadowOffset = .zero
        layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
    }
}

@MainActor class SoftwareUpdatePanel: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(content: NSView, size: NSSize, hidesOnDeactivate: Bool) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = UpdaterColors.background
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = hidesOnDeactivate
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentView = content
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        onClose = nil
        close()
    }

    func windowWillClose(_ notification: Notification) {
        let closed = onClose
        onClose = nil
        closed?()
    }

    static func icon(_ source: NSImage) -> NSImageView {
        let image = (source.copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 64, height: 64)
        let view = NSImageView(image: image)
        view.imageScaling = .scaleNone
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: 82), view.heightAnchor.constraint(equalToConstant: 82)])
        return view
    }

    static func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}

@MainActor final class SoftwareUpdateWindow: SoftwareUpdatePanel {
    enum Style {
        case upToDate
        case update(prompt: String, action: String, title: String?, notes: String?)
    }

    var onPrimary: (() -> Void)?
    var onSecondary: (() -> Void)?

    init(style: Style) {
        let (content, primary, secondary) = Self.content(style: style, info: Bundle.main.infoDictionary ?? [:],
                                                         icon: NSApp.applicationIconImage)
        super.init(content: content, size: content.fittingSize, hidesOnDeactivate: false)
        window?.title = "Software Update"
        primary.target = self
        primary.action = #selector(primaryClicked)
        secondary?.target = self
        secondary?.action = #selector(secondaryClicked)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func primaryClicked() { onPrimary?() }
    @objc private func secondaryClicked() { onSecondary?() }

    static func content(style: Style, info: [String: Any], icon image: NSImage,
                        websiteDataStore: WKWebsiteDataStore? = nil) -> (NSView, NSButton, NSButton?) {
        let content = NSView()
        let column = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        let name = info["CFBundleName"] as? String ?? "Parc"
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
        let icon = Self.icon(image)
        let title = Self.label(name, font: NSFontManager.shared.convert(.systemFont(ofSize: 24), toHaveTrait: .boldFontMask),
                               color: .labelColor)
        let versionLabel = Self.label(version, font: .systemFont(ofSize: 11), color: UpdaterColors.secondary)
        let promptText: String, actionTitle: String
        switch style {
        case .upToDate: (promptText, actionTitle) = ("Your browser is up to date", "Close")
        case .update(let prompt, let action, _, _): (promptText, actionTitle) = (prompt, action)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4
        let prompt = NSTextField(wrappingLabelWithString: "")
        prompt.attributedStringValue = NSAttributedString(string: promptText, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: UpdaterColors.secondary, .paragraphStyle: paragraph])
        prompt.preferredMaxLayoutWidth = 206
        prompt.translatesAutoresizingMaskIntoConstraints = false
        let primary = UpdaterButton(title: actionTitle, filled: true)
        for view in [icon, title, versionLabel, prompt, primary] { column.addSubview(view) }
        var constraints = [
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            column.widthAnchor.constraint(equalToConstant: 270),
            icon.topAnchor.constraint(equalTo: column.topAnchor, constant: 54),
            icon.centerXAnchor.constraint(equalTo: column.centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            versionLabel.topAnchor.constraint(equalTo: title.bottomAnchor),
            versionLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            versionLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            versionLabel.heightAnchor.constraint(equalToConstant: 13),
            prompt.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 20),
            prompt.widthAnchor.constraint(equalToConstant: 206),
            prompt.centerXAnchor.constraint(equalTo: column.centerXAnchor),
            primary.topAnchor.constraint(equalTo: prompt.bottomAnchor, constant: 30),
            primary.centerXAnchor.constraint(equalTo: column.centerXAnchor),
        ]
        var secondary: NSButton?
        switch style {
        case .upToDate:
            constraints += [column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                            primary.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -38)]
        case .update(_, _, let notesTitle, let notes):
            let later = UpdaterButton(title: "Remind me Later", filled: false)
            column.addSubview(later)
            let release = ReleaseNotesView(title: notesTitle, html: notes, appName: name, websiteDataStore: websiteDataStore)
            content.addSubview(release)
            constraints += [
                later.topAnchor.constraint(equalTo: primary.bottomAnchor, constant: 20),
                later.centerXAnchor.constraint(equalTo: column.centerXAnchor),
                release.leadingAnchor.constraint(equalTo: column.trailingAnchor, constant: 12),
                release.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                release.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                release.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
                release.widthAnchor.constraint(equalToConstant: 398),
                release.heightAnchor.constraint(equalToConstant: 394),
            ]
            secondary = later
        }
        NSLayoutConstraint.activate(constraints)
        content.layoutSubtreeIfNeeded()
        return (content, primary, secondary)
    }
}

@MainActor final class SoftwareUpdateStatusWindow: SoftwareUpdatePanel {
    var onAction: (() -> Void)?
    private let content: SoftwareUpdateStatusView

    init() {
        content = SoftwareUpdateStatusView(icon: NSApp.applicationIconImage)
        super.init(content: content, size: NSSize(width: 270, height: 334), hidesOnDeactivate: true)
        window?.title = "Software Update"
        content.action.target = self
        content.action.action = #selector(actionClicked)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(status text: String, action title: String, progress value: Double?, enabled: Bool = true,
              widthTemplate: String? = nil) {
        content.show(status: text, action: title, progress: value, enabled: enabled, widthTemplate: widthTemplate)
    }

    @objc private func actionClicked() { onAction?() }
}

@MainActor final class SoftwareUpdateStatusView: NSView {
    let status = SoftwareUpdatePanel.label("", font: .monospacedDigitSystemFont(ofSize: 13, weight: .bold),
                                           color: .labelColor)
    let progress: NSProgressIndicator
    let action: NSButton = UpdaterButton(title: "Cancel", filled: true)
    private var statusWidth: NSLayoutConstraint!
    private var animating = false

    init(icon image: NSImage, progress indicator: NSProgressIndicator? = nil) {
        progress = indicator ?? NSProgressIndicator()
        super.init(frame: NSRect(x: 0, y: 0, width: 270, height: 334))
        let icon = SoftwareUpdatePanel.icon(image)
        progress.style = .bar
        progress.usesThreadedAnimation = true
        progress.minValue = 0
        progress.maxValue = 1
        progress.translatesAutoresizingMaskIntoConstraints = false
        statusWidth = status.widthAnchor.constraint(equalToConstant: 270)
        for view in [icon, status, progress, action] { addSubview(view) }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 54),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            status.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 30),
            status.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusWidth,
            progress.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12),
            progress.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            action.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 44),
            action.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(status text: String, action title: String, progress value: Double?, enabled: Bool = true,
              widthTemplate: String? = nil) {
        if status.stringValue != text { status.stringValue = text }
        let alignment: NSTextAlignment = widthTemplate == nil ? .center : .right
        if status.alignment != alignment { status.alignment = alignment }
        let width = widthTemplate.map {
            min(270, ceil(($0 as NSString).size(withAttributes: [.font: status.font!]).width) + 4)
        } ?? 270
        if statusWidth.constant != width { statusWidth.constant = width }
        if action.title != title { action.title = title }
        if action.isEnabled != enabled { action.isEnabled = enabled }
        if let value {
            if progress.isIndeterminate {
                progress.stopAnimation(nil)
                animating = false
                progress.isIndeterminate = false
            }
            let fraction = value.isFinite ? min(1, max(0, value)) : 0
            if progress.doubleValue != fraction { progress.doubleValue = fraction }
        } else if !animating {
            if !progress.isIndeterminate { progress.isIndeterminate = true }
            progress.startAnimation(nil)
            animating = true
        }
    }
}

private final class ReleaseNotesView: NSView, WKNavigationDelegate {
    private static let style = """
    <style>
    * {
        font-family: -apple-system, BlinkMacSystemFont;
        color: rgb(20, 20, 20);
        font-size: 12px;
    }

    body, html {
        margin: 12px 8px 16px 0;
        padding: 0;
    }

    li {
        line-height: 20px;
    }

    a, a:visited {
        color: #458AFF;
    }

    html, body { background: white }

    @media (prefers-color-scheme: dark) {
        html, body { background: black; }
        * { color: #fff; }
    }
    </style>
    """
    private let fade = CAGradientLayer()
    private let notes: NSView

    init(title: String?, html: String?, appName: String, websiteDataStore: WKWebsiteDataStore?) {
        let configuration = WKWebViewConfiguration()
        if let websiteDataStore { configuration.websiteDataStore = websiteDataStore }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        notes = NSView()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        let heading = NSTextField(labelWithString: title?.isEmpty == false ? title! : "A new version is available")
        heading.font = .boldSystemFont(ofSize: 14)
        heading.translatesAutoresizingMaskIntoConstraints = false
        notes.wantsLayer = true
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        notes.layer?.mask = fade
        notes.translatesAutoresizingMaskIntoConstraints = false
        web.translatesAutoresizingMaskIntoConstraints = false
        web.navigationDelegate = self
        notes.addSubview(web)
        addSubview(heading)
        addSubview(notes)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            heading.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            notes.leadingAnchor.constraint(equalTo: leadingAnchor),
            notes.trailingAnchor.constraint(equalTo: trailingAnchor),
            notes.topAnchor.constraint(equalTo: heading.bottomAnchor),
            notes.bottomAnchor.constraint(equalTo: bottomAnchor),
            web.leadingAnchor.constraint(equalTo: notes.leadingAnchor, constant: 32),
            web.trailingAnchor.constraint(equalTo: notes.trailingAnchor, constant: -32),
            web.topAnchor.constraint(equalTo: notes.topAnchor),
            web.bottomAnchor.constraint(equalTo: notes.bottomAnchor),
        ])
        let body = html?.isEmpty == false ? html! : "<p>Thanks for using \(appName)!</p>"
        web.loadHTMLString(Self.style + body, baseURL: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = UpdaterColors.notes.cgColor
        }
    }

    override func layout() {
        super.layout()
        let edge = min(30 / max(notes.bounds.height, 1), 0.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = notes.bounds
        fade.locations = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        CATransaction.commit()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased()) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}
