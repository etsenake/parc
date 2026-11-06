import AppKit

///
/// copied into `Resources/SidebarPlusMenu`.
@MainActor enum SidebarPlusMenuArtwork {
    static let directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("SidebarPlusMenu", isDirectory: true)
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name + ".png")),
              let base = NSBitmapImageRep(data: data) else { return nil }
        let size = NSSize(width: base.pixelsWide, height: base.pixelsHigh)
        base.size = size
        let image = NSImage(size: size)
        image.addRepresentation(base)
        if let data = try? Data(contentsOf: directory.appendingPathComponent(name + "@2x.png")),
           let double = NSBitmapImageRep(data: data) {
            double.size = size
            image.addRepresentation(double)
        }
        if let vector = NSImage(contentsOf: directory.appendingPathComponent(name + ".pdf")) {
            for representation in vector.representations { image.addRepresentation(representation) }
        }
        image.isTemplate = true
        cache[name] = image
        return image
    }
}

///
/// New Folder, New Easel, New Split and New Tab. New Note takes the excluded
///
///
///
///
///
/// at their natural size in the 1.170 reference.
enum SidebarPlusAction: Equatable {
    case space, folder, easel, note, split, tab
}

struct SidebarPlusRow: Equatable {
    let action: SidebarPlusAction
    let title: String
    let symbol: String
    let commandID: String?
    let enabled: Bool
    let shortcut: String
}

enum SidebarPlusMenuModel {
    static let groupBreaks: Set<Int> = [2, 4]

    static func rows(privateBrowsing: Bool, canCreateEasel: Bool, canCreateNote: Bool, canSplit: Bool,
                     shortcut: (String) -> String = { _ in "" }) -> [SidebarPlusRow] {
        [
            row(.space, "New Space", "add-space", nil, !privateBrowsing, shortcut),
            row(.folder, "New Folder", "folder", "createFolder:", !privateBrowsing, shortcut),
            row(.easel, "New Easel", "scribble", "createEasel:", canCreateEasel, shortcut),
            row(.note, "New Note", "doc.text", "createNote:", canCreateNote, shortcut),
            row(.split, "New Split", "split-add-right", "split:", canSplit, shortcut),
            row(.tab, "New Tab", "add-tab", "newTab:", true, shortcut),
        ]
    }

    private static func row(_ action: SidebarPlusAction, _ title: String, _ symbol: String,
                            _ commandID: String?, _ enabled: Bool, _ shortcut: (String) -> String) -> SidebarPlusRow {
        SidebarPlusRow(action: action, title: title, symbol: symbol, commandID: commandID,
                       enabled: enabled, shortcut: commandID.map(shortcut) ?? "")
    }
}

/// Where the HUD window sits in screen coordinates, and where its tail is.
///
/// key child window, location `.above`, disclosure alignment `.bottomOrRight`
///
///
/// The 1.170 crop this HUD is matched to sits the card's trailing edge flush
/// with the button's, the tail center 3.25 points left of the button's center
/// (19.25 points in from the card's trailing edge on a 32-point button), and
/// 16 points of cream between the card and the button.
@MainActor
enum SidebarPlusMenuPlacement {
    static let tailBase: CGFloat = 11
    static let tailHeight: CGFloat = 6
    static let tailLead: CGFloat = 3.25
    static let gap: CGFloat = 16
    static let cornerRadius: CGFloat = 12

    static func windowFrame(anchor: CGRect, menu: CGSize, parentMinX: CGFloat) -> (frame: CGRect, tailX: CGFloat) {
        var x = anchor.maxX - menu.width
        if x < parentMinX { x = parentMinX }
        let frame = CGRect(x: x, y: anchor.maxY + gap - tailHeight, width: menu.width, height: menu.height + tailHeight)
        let edge = cornerRadius + tailBase / 2
        let tailX = min(menu.width - edge, max(edge, anchor.midX - tailLead - x))
        return (frame, tailX)
    }
}

///
/// plus HUD or above it for a card hanging under its button. The tail is
/// outside the card, which clips to its own rounded corners.
@MainActor
class PArcMenuChrome: NSView {
    let content: NSView
    let tailX: CGFloat
    let tailOnTop: Bool
    var colors: PArcMenuColors { didSet { needsDisplay = true } }

    init(content: NSView, size: NSSize, colors: PArcMenuColors, tailX: CGFloat, tailOnTop: Bool = false) {
        self.content = content
        self.tailX = tailX
        self.tailOnTop = tailOnTop
        self.colors = colors
        super.init(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height + SidebarPlusMenuPlacement.tailHeight))
        wantsLayer = true
        content.frame = NSRect(x: 0, y: tailOnTop ? 0 : SidebarPlusMenuPlacement.tailHeight,
                               width: size.width, height: size.height)
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The tail's tip, in this view's coordinates.
    var tailTip: NSPoint { NSPoint(x: tailX, y: tailOnTop ? bounds.height : 0) }

    override func draw(_ dirtyRect: NSRect) {
        let base = SidebarPlusMenuPlacement.tailBase / 2
        let edge = tailOnTop ? bounds.height - SidebarPlusMenuPlacement.tailHeight : SidebarPlusMenuPlacement.tailHeight
        let path = NSBezierPath()
        path.move(to: NSPoint(x: tailX - base, y: edge))
        path.line(to: tailTip)
        path.line(to: NSPoint(x: tailX + base, y: edge))
        path.close()
        colors.fillBackground(path)
    }

    ///
    func scaled(_ scale: CGFloat) -> CATransform3D {
        let tip = tailTip
        var transform = CATransform3DMakeTranslation(tip.x, tip.y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -tip.x, -tip.y, 0)
    }
}

/// The plus HUD's card and tail.
@MainActor
final class SidebarPlusMenuChrome: PArcMenuChrome {
    let card: SidebarPlusMenuView
    override var colors: PArcMenuColors { didSet { card.colors = colors } }

    init(card: SidebarPlusMenuView, tailX: CGFloat) {
        self.card = card
        super.init(content: card, size: card.menuSize, colors: card.colors, tailX: tailX)
        card.autoresizingMask = []
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

///
/// values the history chooser uses (navigation.md "Motion").
@MainActor
enum SidebarPlusMenuMotion {
    static let hiddenScale: CGFloat = 0.95
    static let openTransformDuration: CFTimeInterval = 0.1
    static let openOpacityDuration: CFTimeInterval = 0.05
    static let closeDuration: CFTimeInterval = 0.07
    static var timing: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1) }

    /// A 0.95 scale about the tail to identity over 0.1 s and opacity 0 to 1
    /// over 0.05 s.
    static func animateOpen(_ chrome: PArcMenuChrome) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = chrome.layer else { return }
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: chrome.scaled(hiddenScale))
        transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        transform.duration = openTransformDuration
        transform.timingFunction = timing
        layer.add(transform, forKey: "transform_animation")
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        opacity.duration = openOpacityDuration
        opacity.timingFunction = timing
        layer.add(opacity, forKey: "opacity_animation")
    }

    /// From the presentation values back to the 0.95 scale and opacity 0 over
    /// 0.07 s, fill-forwards; false when it cannot animate and the caller
    /// removes the window itself.
    static func animateClose(_ chrome: PArcMenuChrome, completion: @escaping () -> Void) -> Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = chrome.layer else { return false }
        let current = layer.presentation()
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: current?.transform ?? CATransform3DIdentity)
        transform.toValue = NSValue(caTransform3D: chrome.scaled(hiddenScale))
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = current?.opacity ?? 1
        opacity.toValue = 0
        for animation in [transform, opacity] {
            animation.duration = closeDuration
            animation.timingFunction = timing
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        layer.add(transform, forKey: "transform_animation")
        layer.add(opacity, forKey: "opacity_animation")
        CATransaction.commit()
        return true
    }
}

///
/// arrows, Return and Escape and loses focus on an outside click.
class SidebarPlusMenuWindow: NSWindow {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() { super.resignKey(); onResignKey?() }
}

/// Presents the HUD in a key child window and tears it down. Every close path
/// ends in `close(animated:)`, which is where `onVisibilityChange(false)` fires;
/// `onVisibilityChange(true)` fires as the window opens.
@MainActor
final class SidebarPlusMenuController: NSObject {
    /// Posted with the parent window as object when the HUD opens or starts
    /// closing; `userInfo["shown"]` is the new state.
    static let visibilityDidChange = Notification.Name("SidebarPlusMenuVisibilityDidChange")
    private static var shown: [ObjectIdentifier: SidebarPlusMenuController] = [:]
    /// Whether a HUD is open over `window`.
    static func isShown(in window: NSWindow?) -> Bool {
        window.map { shown[ObjectIdentifier($0)] != nil } ?? false
    }
    /// Closes the HUD over `window`, if any (the sidebar hid or went away).
    static func dismiss(in window: NSWindow?) {
        window.flatMap { shown[ObjectIdentifier($0)] }?.dismiss()
    }

    var onVisibilityChange: ((Bool) -> Void)?
    /// The window's live theme; an open HUD recolours with it.
    var theme = SpaceTheme() {
        didSet { if theme != oldValue { chrome?.colors = PArcMenuColors(theme: theme) } }
    }
    private var panel: SidebarPlusMenuWindow?
    private var chrome: SidebarPlusMenuChrome?
    private weak var parent: NSWindow?
    private weak var anchor: NSView?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var closing = false
    /// The mouse-down that closed the HUD by pressing its own + button; the
    /// button's action for that same press must not reopen it.
    private var closingPress: Int?

    func toggle(from button: NSView, rows: [SidebarPlusRow], perform: @escaping (SidebarPlusAction) -> Void) {
        if let press = closingPress {
            closingPress = nil
            if NSApp.currentEvent.map({ Self.isMouse($0) && $0.eventNumber == press }) == true { return }
        }
        if panel != nil {
            dismiss()
            return
        }
        guard let parent = button.window else { return }
        let menu = SidebarPlusMenuView(rows: rows, colors: PArcMenuColors(theme: theme), dismiss: { [weak self] in
            self?.dismiss()
        }) { [weak self] action in
            self?.dismiss()
            DispatchQueue.main.async { perform(action) }
        }
        let anchorRect = parent.convertToScreen(button.convert(button.bounds, to: nil))
        let placed = SidebarPlusMenuPlacement.windowFrame(anchor: anchorRect, menu: menu.menuSize,
                                                           parentMinX: parent.frame.minX)
        let chrome = SidebarPlusMenuChrome(card: menu, tailX: placed.tailX)
        let panel = SidebarPlusMenuWindow(contentRect: placed.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.setAccessibilityLabel("New Tab, Folder, or Space")
        panel.contentView = chrome
        panel.onResignKey = { [weak self] in self?.lostFocus() }
        self.panel = panel
        self.chrome = chrome
        self.parent = parent
        self.anchor = button
        // The parent resigns key inside makeKeyAndOrderFront. Register first so
        // that resignation still sees the HUD as open.
        Self.shown[ObjectIdentifier(parent)] = self
        announce(true)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(menu)
        observe(parent)
        SidebarPlusMenuMotion.animateOpen(chrome)
    }

    func dismiss() { close(animated: true) }

    private func observe(_ parent: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification,
                     NSWindow.willBeginSheetNotification] {
            // Window-level dismissals close at once, without the exit animation.
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(animated: false) }
            })
        }
        //
        for (name, object) in [(NSWindow.didResizeNotification, parent as AnyObject?),
                               (NSMenu.didSendActionNotification, nil),
                               (NSApplication.didResignActiveNotification, nil)] {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }
    }

    ///
    /// is remembered so that press's toggle does not reopen the HUD.
    private func lostFocus() {
        guard panel != nil, !closing else { return }
        if let event = NSApp.currentEvent, event.type == .leftMouseDown, let anchor, let window = anchor.window,
           event.window === window, anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
            closingPress = event.eventNumber
        }
        dismiss()
    }

    private static func isMouse(_ event: NSEvent) -> Bool {
        [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type)
    }

    private func announce(_ shown: Bool) {
        onVisibilityChange?(shown)
        if let parent {
            NotificationCenter.default.post(name: Self.visibilityDidChange, object: parent, userInfo: ["shown": shown])
        }
    }

    private func close(animated: Bool) {
        guard let panel, !closing else { return }
        closing = true
        chrome?.card.acceptsActions = false
        panel.ignoresMouseEvents = true
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        let parent = self.parent
        if let parent {
            Self.shown[ObjectIdentifier(parent)] = nil
            if panel.isKeyWindow, parent.isVisible, NSApp.isActive { parent.makeKey() }
        }
        announce(false)
        let remove = { [weak self, weak parent] in
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            guard let self, self.panel === panel else { return }
            self.panel = nil
            self.chrome = nil
            self.anchor = nil
            self.closing = false
        }
        guard animated, let chrome, panel.isVisible, SidebarPlusMenuMotion.animateClose(chrome, completion: remove) else {
            remove()
            return
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

@MainActor
final class SidebarPlusMenuView: NSView {
    let menuSize: NSSize
    private let rows: [SidebarPlusRow]
    private let dismiss: () -> Void
    private let perform: (SidebarPlusAction) -> Void
    private var buttons: [SidebarPlusRowButton] = []
    private var separators: [NSRect] = []
    private var highlighted = 0
    /// False once the HUD starts closing; rows and keys do nothing then.
    var acceptsActions = true
    var colors: PArcMenuColors {
        didSet {
            needsDisplay = true
            for button in buttons { button.colors = colors }
        }
    }
    static let width: CGFloat = 210
    static let rowHeight: CGFloat = 40
    nonisolated static let inset: CGFloat = 8
    ///
    ///
    static let separatorInsets = NSEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
    static let divider = separatorInsets.top + 1 + separatorInsets.bottom

    /// The card's 12-point continuous corners, which its content clips to.
    static func shapeCard(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = SidebarPlusMenuPlacement.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }

    init(rows: [SidebarPlusRow], colors: PArcMenuColors, dismiss: @escaping () -> Void = {},
         perform: @escaping (SidebarPlusAction) -> Void) {
        self.rows = rows
        self.colors = colors
        self.dismiss = dismiss
        self.perform = perform
        let breaks = rows.indices.filter { SidebarPlusMenuModel.groupBreaks.contains($0) }.count
        menuSize = NSSize(
            width: Self.width,
            height: Self.inset * 2 + CGFloat(rows.count) * Self.rowHeight + CGFloat(breaks) * Self.divider
        )
        super.init(frame: NSRect(x: 0, y: 0, width: menuSize.width, height: menuSize.height))
        Self.shapeCard(self)
        var y = Self.inset
        for (index, row) in rows.enumerated() {
            if SidebarPlusMenuModel.groupBreaks.contains(index) {
                let edge = Self.inset + Self.separatorInsets.left
                separators.append(NSRect(x: edge, y: y + Self.separatorInsets.top,
                                         width: Self.width - edge - Self.inset - Self.separatorInsets.right, height: 1))
                y += Self.divider
            }
            let button = SidebarPlusRowButton(row: row, colors: colors)
            button.target = self
            button.action = #selector(choose(_:))
            button.tag = index
            addSubview(button)
            button.frame = NSRect(x: Self.inset, y: y, width: Self.width - Self.inset * 2, height: Self.rowHeight)
            buttons.append(button)
            y += Self.rowHeight
        }
        highlighted = rows.lastIndex(where: { $0.action == .tab && $0.enabled }) ?? rows.indices.last ?? 0
        refreshHighlight()
        setAccessibilityRole(.menu)
        setAccessibilityLabel("New Tab, Folder, or Space")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        colors.fillBackground(NSBezierPath(rect: bounds))
        colors.hover.setFill()
        for line in separators { NSBezierPath(roundedRect: line, xRadius: 0.5, yRadius: 0.5).fill() }
    }

    override func keyDown(with event: NSEvent) {
        guard acceptsActions else { return }
        if event.keyCode == 126 { moveHighlight(-1) }
        else if event.keyCode == 125 { moveHighlight(1) }
        else if event.keyCode == 36 || event.keyCode == 76 { activateHighlighted() }
        else if event.keyCode == 53 { dismiss() }
        else { super.keyDown(with: event) }
    }

    @objc private func choose(_ sender: SidebarPlusRowButton) {
        guard acceptsActions, sender.row.enabled else { return }
        perform(sender.row.action)
    }

    private func moveHighlight(_ delta: Int) {
        guard !buttons.isEmpty else { return }
        var index = highlighted
        for _ in buttons.indices {
            index = (index + delta + buttons.count) % buttons.count
            if rows[index].enabled { highlighted = index; refreshHighlight(); return }
        }
    }

    private func activateHighlighted() {
        guard acceptsActions, rows.indices.contains(highlighted), rows[highlighted].enabled else { return }
        perform(rows[highlighted].action)
    }

    private func refreshHighlight() {
        for (index, button) in buttons.enumerated() { button.emphasized = index == highlighted }
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        guard acceptsActions else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let index = buttons.firstIndex(where: { $0.frame.contains(point) }), rows[index].enabled {
            highlighted = index
            refreshHighlight()
        }
    }
}

@MainActor
final class SidebarPlusRowButton: NSButton {
    let row: SidebarPlusRow
    var emphasized = false { didSet { if emphasized != oldValue { needsDisplay = true } } }
    var colors: PArcMenuColors { didSet { needsDisplay = true } }
    private let icon: NSImage?
    private let iconIsArtwork: Bool
    ///
    ///
    ///
    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let shortcutFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private static let shortcutKern: CGFloat = 2
    private static let iconConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
    static let iconCenter = NSPoint(x: 20, y: 20)
    private static let artworkSize = NSSize(width: 24, height: 24)
    static let titleOrigin = NSPoint(x: 42, y: 12)
    /// The highlighted row's plate.
    static let plateRadius: CGFloat = 8
    private static let shortcutRightInset: CGFloat = 10

    init(row: SidebarPlusRow, colors: PArcMenuColors) {
        self.row = row
        self.colors = colors
        let artwork = SidebarPlusMenuArtwork.image(row.symbol)
        iconIsArtwork = artwork != nil
        icon = artwork ?? NSImage(systemSymbolName: row.symbol, accessibilityDescription: row.title)?
            .withSymbolConfiguration(Self.iconConfiguration)
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        image = nil
        imagePosition = .noImage
        isEnabled = row.enabled
        setAccessibilityLabel(row.title)
        setAccessibilityEnabled(row.enabled)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = Self.plateRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if emphasized, isEnabled {
            colors.hover.setFill()
            NSBezierPath(rect: bounds).fill()
        }
        let titleColor = row.enabled ? colors.title : colors.disabledTitle
        if let icon {
            let tinted = NSImage(size: icon.size, flipped: false) { rect in
                icon.draw(in: rect)
                titleColor.setFill()
                rect.fill(using: .sourceAtop)
                return true
            }
            let size = iconIsArtwork ? Self.artworkSize : icon.size
            let iconRect = NSRect(x: Self.iconCenter.x - size.width / 2, y: Self.iconCenter.y - size.height / 2,
                                  width: size.width, height: size.height)
            tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: true, hints: nil)
        }
        let title = NSAttributedString(string: row.title, attributes: [
            .font: Self.titleFont, .foregroundColor: titleColor
        ])
        title.draw(at: Self.titleOrigin)
        let shortcut = NSAttributedString(string: row.shortcut, attributes: [
            .font: Self.shortcutFont, .kern: Self.shortcutKern,
            .foregroundColor: row.enabled ? colors.subtitle : colors.disabledSubtitle
        ])
        let shortcutWidth = shortcut.size().width
        shortcut.draw(at: NSPoint(x: bounds.width - Self.shortcutRightInset - shortcutWidth, y: 12))
    }
}
