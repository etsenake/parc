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

@MainActor final class AboutParcWindow: NSWindowController, NSTextViewDelegate {
    private final class Content: NSView {
        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
        }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    }
    private let icon = NSImageView(frame: NSRect(x: 194, y: 286, width: 52, height: 52))
    private let openPage: (URL) -> Void
    init(info: AboutParcInfo = AboutParcInfo(), openPage: @escaping (URL) -> Void = { _ in }) {
        self.openPage = openPage
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 372),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "About Parc"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        let content = Content(frame: NSRect(x: 0, y: 0, width: 440, height: 372))
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
        label("Parc", y: 250, size: 15, bold: true)
        label("Version \(info.version) (\(info.build))", y: 224)
        label("Chromium Engine Version \(info.chromium)", y: 207)
        label("Media and FairPlay via WebKit", y: 176, bold: true)
        label("WebKit \(info.webKit) · AVFoundation", y: 158, size: 12)
        label("Copyright © \(Calendar.current.component(.year, from: Date())) Josh Etsenake and Parc contributors.", y: 127)
        let credits = NSTextView(frame: NSRect(x: 24, y: 14, width: 392, height: 104))
        credits.isEditable = false
        credits.isSelectable = true
        credits.drawsBackground = false
        credits.textContainerInset = .zero
        credits.delegate = self
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let made = "Parc is made possible by the Chromium open source project, Chromium’s open source software, and WebKit."
        let freedom = "Parc is free software under the GNU Affero General Public License and comes with no warranty."
        let text = made + "\n\n" + freedom + "\nLicenses · Source code"
        let value = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
        for (title, url) in [("Chromium open source project", "https://www.chromium.org/"),
                             ("Chromium’s open source software", "https://source.chromium.org/chromium/chromium/src/+/main:third_party/"),
                             ("WebKit", "https://webkit.org/"),
                             ("Licenses", "parc://license/"),
                             ("Source code", "https://github.com/etsenake/parc")] {
            value.addAttributes([.link: URL(string: url)!, .foregroundColor: NSColor.linkColor,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue],
                                range: (text as NSString).range(of: title))
        }
        credits.textStorage?.setAttributedString(value)
        content.addSubview(credits)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL, url.scheme == "parc" else { return false }
        openPage(url)
        return true
    }
    func present() {
        icon.image = NSApp.applicationIconImage
        window?.makeKeyAndOrderFront(nil)
    }
}
