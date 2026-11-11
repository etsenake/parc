import AppKit

struct AboutParcInfo {
    let version: String
    let build: String
    let chromium: String
    let webKit: String

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        version = info["CFBundleShortVersionString"] as? String ?? "Development"
        build = info["CFBundleVersion"] as? String ?? "unversioned"
        chromium = info["ParcChromiumVersion"] as? String ?? "Unavailable in this build"
        webKit = Bundle(path: "/System/Library/Frameworks/WebKit.framework")?
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "System version"
    }
}

@MainActor final class AboutParcWindow: NSWindowController {
    private final class Content: NSView {
        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
        }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    }
    private let icon = NSImageView(frame: NSRect(x: 194, y: 254, width: 52, height: 52))
    init(info: AboutParcInfo = AboutParcInfo()) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "About Parc"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        let content = Content(frame: NSRect(x: 0, y: 0, width: 440, height: 340))
        content.wantsLayer = true
        window.contentView = content
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = NSApp.applicationIconImage
        content.addSubview(icon)
        func label(_ text: String, y: CGFloat, height: CGFloat = 20, size: CGFloat = 13, bold: Bool = false) {
            let field = NSTextField(wrappingLabelWithString: text)
            field.frame = NSRect(x: 18, y: y, width: 404, height: height)
            field.alignment = .center
            field.font = .systemFont(ofSize: size, weight: bold ? .bold : .medium)
            field.isSelectable = true
            content.addSubview(field)
        }
        label("Parc", y: 218, size: 15, bold: true)
        label("Version \(info.version) (\(info.build))", y: 192)
        label("Chromium Engine Version \(info.chromium)", y: 175)
        label("Media and FairPlay via WebKit", y: 144, bold: true)
        label("WebKit \(info.webKit) · AVFoundation", y: 126, size: 12)
        label("Copyright © \(Calendar.current.component(.year, from: Date())) Parc.", y: 95)
        let credits = NSTextField(wrappingLabelWithString: "")
        credits.frame = NSRect(x: 24, y: 22, width: 392, height: 60)
        credits.isSelectable = true
        credits.allowsEditingTextAttributes = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = "Parc is made possible by the Chromium open source project, Chromium’s open source software, and WebKit."
        let value = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
        for (title, url) in [("Chromium open source project", "https://www.chromium.org/"),
                             ("Chromium’s open source software", "https://source.chromium.org/chromium/chromium/src/+/main:third_party/"),
                             ("WebKit", "https://webkit.org/")] {
            value.addAttributes([.link: URL(string: url)!, .foregroundColor: NSColor.linkColor,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue],
                                range: (text as NSString).range(of: title))
        }
        credits.attributedStringValue = value
        content.addSubview(credits)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() {
        icon.image = NSApp.applicationIconImage
        window?.makeKeyAndOrderFront(nil)
    }
}
