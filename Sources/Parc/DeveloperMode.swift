import AppKit
import Combine
import ParcKit
import ParcSidebar

@MainActor
final class DeveloperModePreferences: ObservableObject {
    static let shared = DeveloperModePreferences()
    static let defaultHosts: Set<String> = ["localhost", "127.0.0.1"]
    private struct State: Codable {
        var version = 1
        var enabledHosts = Set<String>()
        var disabledDefaultHosts = Set<String>()
    }
    @Published private var state: State
    private let defaults: UserDefaults
    private let key = "parc.developerMode.v1"
    private(set) var loadError = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            if let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.version == 1 { state = decoded }
            else { state = State(); loadError = true }
        } else { state = State() }
    }
    func isEnabled(host: String) -> Bool {
        let host = host.lowercased()
        return Self.defaultHosts.contains(host) ? !state.disabledDefaultHosts.contains(host) : state.enabledHosts.contains(host)
    }
    func setEnabled(_ enabled: Bool, host: String) throws {
        guard !loadError, !host.isEmpty else { throw Failure.unavailable }
        let host = host.lowercased()
        var next = state
        if Self.defaultHosts.contains(host) {
            if enabled { next.disabledDefaultHosts.remove(host) } else { next.disabledDefaultHosts.insert(host) }
        } else {
            if enabled { next.enabledHosts.insert(host) } else { next.enabledHosts.remove(host) }
        }
        let encoded = try JSONEncoder().encode(next)
        defaults.set(encoded, forKey: key)
        state = next
    }
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Developer Mode preferences are unavailable. Existing preferences have been preserved." }
    }
}

@MainActor
final class DeveloperToolbarView: NSView, NSTextFieldDelegate {
    enum Action { case siteInfo, copy, portrait, capture, console, network, inspect, extensions, split, tools, blocked }
    var onAction: ((Action, NSView) -> Void)?
    var onEdit: ((String, NSRange) -> Void)?
    var onFocus: (() -> Bool)?
    var onEscape: (() -> Void)?
    private let field = DeveloperAddressField()
    private let divider = NSView()
    private var buttons: [(Action, DeveloperToolbarButton)] = []
    private let blocked = DeveloperToolbarButton(symbol: "nosign", title: "Blocked")
    private var blockedContent: BlockedPageContent?
    private var committedURL = ""
    private var tint = DeveloperToolbarLayout.fallbackTint
    private var textColor = NSColor.white
    private var lastStripeSize = NSSize.zero
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityRole(.toolbar); setAccessibilityLabel("Developer Mode")
        let cell = VerticallyAlignedTextFieldCell()
        cell.isBordered = false; cell.drawsBackground = false
        cell.lineBreakMode = .byTruncatingMiddle
        field.cell = cell
        field.isBordered = false; field.drawsBackground = false
        field.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        field.focusRingType = .none; field.delegate = self
        field.setAccessibilityLabel("Full page address")
        field.setAccessibilityHelp("Edit the address to search or navigate using the command bar. Escape returns to the page.")
        addSubview(field)
        divider.wantsLayer = true
        divider.setAccessibilityElement(false)
        addSubview(divider)
        let specs: [(Action, String, String)] = [(.siteInfo, "Site Settings", "lock.fill"),
            (.copy, "Copy Link", "link"), (.portrait, "Capture in Portrait Mode", "rectangle.inset.filled"),
            (.capture, "Capture", "camera"), (.console, "JavaScript Console", "terminal"),
            (.network, "Network Inspector", "network"), (.inspect, "Inspect Element", "scope"),
            (.extensions, "Extensions Menu", "puzzlepiece.extension"), (.split, "Split View Menu", "rectangle.split.2x1")]
        let bindings: [Action: String] = [.copy: "copyCurrentURL:", .capture: "capturePage:",
                                          .console: "javaScriptConsole:", .inspect: "inspectElements:"]
        for (action, title, symbol) in specs {
            let button = DeveloperToolbarButton(symbol: symbol, title: title)
            LiveShortcutToolTip.set(button, title, commandID: bindings[action])
            button.actionBlock = { [weak self, weak button] in
                guard let self, let button else { return }; self.onAction?(action, button)
            }
            addSubview(button); buttons.append((action, button))
            if action == .inspect { addSubview(blocked) }
        }
        blocked.actionBlock = { [weak self] in
            guard let self else { return }; self.onAction?(.blocked, self.blocked)
        }
        blocked.setTrailingHidden(true)
        applyTintLayers()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func update(url: String, tint: NSColor?, editing: Bool, enabled: Bool, secure: Bool, siteInfo: Bool, copy: Bool, capture: Bool, split: Bool) {
        committedURL = url
        buttons[0].1.image = NSImage(systemSymbolName: secure ? "lock.fill" : "info.circle", accessibilityDescription: nil)
        if field.currentEditor() == nil { field.stringValue = url }
        if let rgb = tint?.usingColorSpace(.sRGB) { self.tint = rgb }
        else { self.tint = DeveloperToolbarLayout.fallbackTint }
        let color = self.tint.usingColorSpace(.sRGB) ?? self.tint
        textColor = (color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722) > 0.58 ? .black : .white
        field.textColor = textColor; field.isEnabled = editing
        for (action, button) in buttons {
            button.contentTintColor = textColor.withAlphaComponent(0.85)
            button.isEnabled = enabled && (action == .siteInfo ? siteInfo : action == .copy ? copy : action == .capture || action == .portrait ? capture : action == .split ? split : true)
        }
        blocked.contentTintColor = textColor.withAlphaComponent(0.85)
        blocked.isEnabled = enabled
        applyTintLayers()
        needsDisplay = true
    }
    func updateBlockedContent(_ content: BlockedPageContent?) {
        guard content != blockedContent else { return }
        let appearing = blockedContent == nil && content != nil
        if let content {
            if content.glyphName != blockedContent?.glyphName { blocked.image = SiteControlCenterArtwork.image(content.glyphName) }
            LiveShortcutToolTip.set(blocked, content.summary)
            blocked.setAccessibilityLabel(content.summary)
            blocked.setAccessibilityHelp(BlockedContentSign.help)
        }
        blockedContent = content
        if appearing { BlockedContentSign.reveal(blocked, animated: true, alpha: 1) }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let frames = DeveloperToolbarLayout.frames(in: bounds,
            blockedTitleRoom: blockedContent == nil ? nil : BlockedContentSign.toolbarTitleRoom)
        buttons[0].1.frame = frames.siteInfo
        buttons[0].1.isHidden = false
        field.frame = frames.address
        for (index, pair) in buttons.dropFirst().enumerated() {
            let hidden = index < frames.hiddenTrailing.count && frames.hiddenTrailing[index]
            pair.1.setTrailingHidden(hidden)
            pair.1.frame = hidden ? .zero : frames.trailing[index]
        }
        blocked.setTrailingHidden(frames.blocked == nil)
        blocked.frame = frames.blocked ?? .zero
        divider.frame = frames.divider
        divider.isHidden = frames.divider.width < 0.5
        applyTintLayers()
        if lastStripeSize != bounds.size {
            lastStripeSize = bounds.size
            needsDisplay = true
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSColor.white.withAlphaComponent(DeveloperToolbarLayout.stripeForegroundAlpha(isDark: isDark)).setFill()
        DeveloperToolbarLayout.stripePath(in: bounds).fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTintLayers()
        needsDisplay = true
    }
    private func applyTintLayers() {
        layer?.backgroundColor = tint.cgColor
        divider.layer?.backgroundColor = textColor.withAlphaComponent(0.25).cgColor
    }
    var ownsFocus: Bool { field.currentEditor() != nil }
    func restoreCommittedAddress() { field.stringValue = committedURL }
    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool { onFocus?() ?? false }
    func controlTextDidChange(_ notification: Notification) {
        guard let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() else { return }
        onEdit?(field.stringValue, editor.selectedRange())
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            field.stringValue = committedURL; onEscape?(); return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            onEdit?(field.stringValue, textView.selectedRange()); return true
        }
        return false
    }
}

@MainActor private final class DeveloperAddressField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        DeveloperToolbarFirstEdit.apply(self)
        return true
    }
}

@MainActor private final class VerticallyAlignedTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let title = super.titleRect(forBounds: rect)
        let size = cellSize(forBounds: super.drawingRect(forBounds: rect))
        return NSRect(x: title.minX, y: title.minY + (title.height - size.height) * 0.5,
                      width: title.width, height: size.height)
    }
}
