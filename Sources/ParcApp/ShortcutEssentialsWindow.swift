import AppKit
import Combine
import CoreText
import SwiftUI

enum EssentialsCopyRoute: Equatable {
    case unavailable, currentURL, commandWindow

    init(hasURL: Bool, commandBarOpen: Bool, hasNativePage: Bool) {
        if !hasURL { self = .unavailable } else if commandBarOpen || !hasNativePage { self = .currentURL } else { self = .commandWindow }
    }
}

@MainActor
final class ShortcutEssentialsWindow: NSWindowController {
    static let commandIDs = ["newTab:", "cycleToNextRecentTab:", "copyCurrentURL:", "split:"]
    private var subscription: AnyCancellable?
    private let surface = EssentialsSurface()
    var onViewAll: (() -> Void)?
    var onCommand: ((String, NSEvent?) -> Void)?
    var onEscape: (() -> Void)?
    var isOwnerAvailable: (() -> Bool)?
    var canPerformCommand: ((String) -> Bool)?

    init(shortcuts: KeyboardShortcuts) {
        let window = EssentialsNativeWindow(contentRect: NSRect(x: 0, y: 0, width: 475, height: 388),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.setFrame(NSRect(x: 0, y: 0, width: 475, height: 388), display: false)
        window.title = "Essential Keyboard Shortcuts"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isOpaque = false; window.isMovableByWindowBackground = true
        window.level = .floating; window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.isReleasedWhenClosed = false; window.contentView = surface
        surface.onViewAll = { [weak self] in self?.viewAllShortcuts() }
        window.shortcutAction = { [weak self] id, event in
            _ = self?.activateCommand(id, event: event)
        }
        window.escapeAction = { [weak self] in self?.escape() }
        window.shortcuts = shortcuts
        subscription = shortcuts.$revision.sink { [weak self] _ in self?.surface.refresh(shortcuts) }
        surface.refresh(shortcuts)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func canActivateCommand(_ id: String) -> Bool {
        ownsPresentation && Self.commandIDs.contains(id) && (canPerformCommand?(id) ?? true)
    }

    @discardableResult
    func activateCommand(_ id: String, event: NSEvent? = nil) -> Bool {
        guard canActivateCommand(id) else { return false }
        onCommand?(id, event); return true
    }

    func escape() {
        guard ownsPresentation else { return }
        onEscape?()
    }

    private var ownsPresentation: Bool {
        window?.isVisible == true && window?.isKeyWindow == true && window?.attachedSheet == nil
            && (isOwnerAvailable?() ?? true)
    }

    private func viewAllShortcuts() {
        guard ownsPresentation else { return }
        close(); onViewAll?()
    }

    func show(relativeTo parent: NSWindow?) {
        guard let window else { return }
        surface.appearance = parent?.effectiveAppearance ?? NSAppearance.currentDrawing()
        if !window.isVisible {
            if let parent {
                window.setFrameOrigin(Self.origin(parent: parent.frame, education: window.frame.size))
            } else { window.center() }
        }
        showWindow(nil); window.makeKeyAndOrderFront(nil)
    }
    static func origin(parent: NSRect, education: NSSize) -> NSPoint {
        NSPoint(x: parent.maxX - education.width - 10,
                y: parent.maxY - education.height - 10)
    }

}

@MainActor
private final class EssentialsNativeWindow: NSWindow {
    weak var shortcuts: KeyboardShortcuts?
    var shortcutAction: ((String, NSEvent) -> Void)?
    var escapeAction: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { escapeAction?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isKeyWindow, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        if event.keyCode == 53 { escapeAction?(); return true }
        if let shortcuts, let chord = shortcuts.chord(for: event) {
            if chord == shortcuts.activeShortcut(for: "closeTab:") { performClose(nil); return true }
            if let id = ShortcutEssentialsWindow.commandIDs.first(where: { shortcuts.activeShortcut(for: $0) == chord }) {
                shortcutAction?(id, event); return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class EssentialsSurface: NSView {
    var onViewAll: (() -> Void)?
    private let viewAll = EssentialsViewAllControl()
    private var caps: [ShortcutKeycapView] = []
    private var titles: [NSTextField] = [], details: [NSTextField] = []
    private var dark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    private let title = NSTextField(labelWithString: "Essential Keyboard Shortcuts")
    private var separators: [NSBox] = []
    private lazy var instructions = InstructionsAccessibility(owner: self)
    private var instructionRows: [(text: String, frame: NSRect)] {
        caps.indices.compactMap { index in
            let cap = caps[index], name = titles[index + 1], detail = details[index]
            guard !name.isHidden, !cap.isHidden, !detail.isHidden else { return nil }
            return ("\(name.stringValue) \(cap.bindingDescription ?? "") \(detail.stringValue)",
                    name.frame.union(cap.frame).union(detail.frame))
        }
    }
    override func accessibilityChildren() -> [Any]? {
        let header = NSAccessibility.unignoredChildren(from: [title, viewAll])
        return instructions.isAccessibilityElement() ? header + [instructions] : header
    }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        if instructions.isAccessibilityElement(), instructions.accessibilityFrame().contains(point) { return instructions }
        return super.accessibilityHitTest(point)
    }
    @MainActor private final class InstructionsAccessibility: NSAccessibilityElement {
        weak var owner: EssentialsSurface?
        init(owner: EssentialsSurface) { self.owner = owner; super.init() }
        override func isAccessibilityElement() -> Bool {
            guard let owner else { return false }
            return owner.window != nil && !owner.isHiddenOrHasHiddenAncestor && !owner.instructionRows.isEmpty
        }
        override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
        override func accessibilityParent() -> Any? { isAccessibilityElement() ? owner : nil }
        override func accessibilityWindow() -> Any? { isAccessibilityElement() ? owner?.window : nil }
        override func accessibilityTopLevelUIElement() -> Any? { accessibilityWindow() }
        override func accessibilityChildren() -> [Any]? { [] }
        override func accessibilityPerformPress() -> Bool { false }
        override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
            if selector == #selector(accessibilityPerformPress) { return false }
            return super.isAccessibilitySelectorAllowed(selector)
        }
        override func accessibilityValue() -> Any? {
            guard isAccessibilityElement(), let owner else { return nil }
            return owner.instructionRows.map(\.text).joined(separator: " ")
        }
        override func accessibilityFrame() -> NSRect {
            guard isAccessibilityElement(), let owner, let window = owner.window else { return .zero }
            let frame = owner.instructionRows.reduce(NSRect.null) { $0.union($1.frame) }
            return window.convertToScreen(owner.convert(frame, to: nil))
        }
    }
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = (dark ? NSColor(srgbRed: 21/255, green: 28/255, blue: 48/255, alpha: 1)
            : NSColor(srgbRed: 250/255, green: 251/255, blue: 1, alpha: 1)).cgColor
    }
    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 475, height: 388))
        wantsLayer = true
        title.font = Self.headlineFont
        title.attributedStringValue = NSAttributedString(string: title.stringValue, attributes: [.font: Self.headlineFont, .kern: -0.8])
        title.frame = NSRect(x: 30, y: 55, width: 312, height: 27); addSubview(title); titles.append(title)
        viewAll.frame = NSRect(x: 346, y: 53, width: 102, height: 32)
        viewAll.onPress = { [weak self] in self?.onViewAll?() }; addSubview(viewAll)
        let rows = [
            ("Open a New Tab", "Open the Command Bar to create a new tab"),
            ("Switch to a Recent Tab", "Hold this to quickly switch between recent tabs"),
            ("Copy Page URL", "Copy the current tab’s URL"),
            ("Add Split View", "View multiple websites side-by-side")]
        for (index, row) in rows.enumerated() {
            let y = 102 + CGFloat(index) * 73
            let name = NSTextField(labelWithString: row.0)
            name.font = .systemFont(ofSize: 15, weight: .regular)
            name.frame = NSRect(x: 30, y: y, width: 290, height: 20)
            let detail = NSTextField(wrappingLabelWithString: row.1)
            detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
            detail.frame = NSRect(x: 30, y: y + 22, width: 308, height: 31)
            addSubview(name); addSubview(detail); titles.append(name); details.append(detail)
            let cap = ShortcutKeycapView(frame: NSRect(x: 342, y: y + 4, width: 103, height: 30))
            cap.setAccessibilityLabel(row.0 + " shortcut")
            caps.append(cap); addSubview(cap)
            if index < rows.count - 1 {
                let line = NSBox(frame: NSRect(x: 30, y: y + 52, width: 415, height: 1))
                line.boxType = .separator; line.setAccessibilityElement(false)
                separators.append(line); addSubview(line)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private static let headlineFont: NSFont = {
        if let url = Bundle.main.url(forResource: "Nunito-ExtraBold", withExtension: "ttf", subdirectory: "NoteFonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: "Nunito-ExtraBold", size: 20) ?? .systemFont(ofSize: 20, weight: .heavy)
    }()
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updateColors()
    }
    private func updateColors() {
        let foreground = dark ? NSColor.white : NSColor(srgbRed: 0.02, green: 0.05, blue: 0.17, alpha: 1)
        titles.forEach { $0.textColor = foreground }
        let message = dark ? NSColor(srgbRed: 238/255, green: 238/255, blue: 246/255, alpha: 0.75)
            : NSColor(srgbRed: 6/255, green: 14/255, blue: 43/255, alpha: 0.75)
        details.forEach { $0.textColor = message }
        needsDisplay = true
    }
    func refresh(_ shortcuts: KeyboardShortcuts) {
        let previousInstructions = instructionRows.map(\.text)
        updateColors()
        let bindings = ShortcutEssentialsWindow.commandIDs.map { shortcuts.activeShortcut(for: $0) }
        var visibleIndex = 0
        for (index, shortcut) in bindings.enumerated() {
            let cap = caps[index], name = titles[index + 1], detail = details[index]
            let hidden = shortcut == nil
            cap.isHidden = hidden; name.isHidden = hidden; detail.isHidden = hidden
            cap.symbols = shortcut?.keycapSymbols ?? []
            cap.bindingDescription = shortcut?.spokenDisplay ?? "No shortcut"
            let y = 102 + CGFloat(visibleIndex) * 73
            let width = max(27, ShortcutKeycapView.smallWidth(symbols: cap.symbols))
            cap.frame = NSRect(x: 445 - width, y: y + 4, width: width, height: 30)
            name.frame = NSRect(x: 30, y: y, width: min(290, cap.frame.minX - 42), height: 20)
            detail.frame = NSRect(x: 30, y: y + 22, width: min(308, cap.frame.minX - 42), height: 31)
            if index < separators.count {
                separators[index].isHidden = hidden || !bindings.dropFirst(index + 1).contains(where: { $0 != nil })
                separators[index].frame.origin.y = y + 52
            }
            if !hidden { visibleIndex += 1 }
        }
        if window?.isVisible == true, previousInstructions != instructionRows.map(\.text) {
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
    }
}

@MainActor
final class EssentialsViewAllControl: NSHostingView<EssentialsViewAllLabel> {
    var onPress: (() -> Void)?
    required init(rootView: EssentialsViewAllLabel) { super.init(rootView: rootView) }
    convenience init() {
        self.init(rootView: EssentialsViewAllLabel(onPress: {}))
        rootView = EssentialsViewAllLabel(onPress: { [weak self] in self?.onPress?() })
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct EssentialsViewAllLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let onPress: () -> Void
    var body: some View {
        Button(action: onPress) {
            HStack {
                Text("View All")
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color(white: 23/255))
            .padding(2)
        }
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(colorScheme == .dark ? Color.white.opacity(0.172) : Color.black.opacity(0.141), lineWidth: 1)
            .allowsHitTesting(false))
        .pointingHandCursor()
        .accessibilityLabel("View All Shortcuts")
    }
}
