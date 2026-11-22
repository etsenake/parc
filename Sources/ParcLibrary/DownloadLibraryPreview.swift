import AppKit
import Quartz
import ParcKit

@MainActor package final class DownloadLibraryPreview: NSWindowController, NSWindowDelegate {
    package var onMove: ((Bool) -> Void)?
    package var onOpen: (() -> Void)?
    package var onCopy: (() -> Void)?
    package var onMenu: (() -> NSMenu?)?
    package var onClosed: (() -> Void)?
    package var sourceRect: (() -> NSRect?)?
    var sourceImage: NSImage?
    private let imageView = DownloadPreviewImage()
    private let content = DownloadPreviewModal()
    private var sourceAspect: CGFloat?
    private let quickLook: QLPreviewView
    private let name = NSTextField(labelWithString: "")
    private let previous = DownloadPreviewButton(symbol: "chevron.backward", label: "Previous download")
    private let next = DownloadPreviewButton(symbol: "chevron.forward", label: "Next download")
    private let dismissButton = DownloadPreviewButton(symbol: "xmark", label: "Close preview")
    private let more = DownloadPreviewButton(symbol: "ellipsis", label: "Download actions")
    private let open = DownloadPreviewButton(symbol: "arrow.up.right", label: "Open download")
    private let root = DownloadPreviewBackdrop()
    private let modal = DownloadPreviewModal()
    private let backdrop = NSView()
    private var closing = false
    private var closed = false
    private var transition: UInt64 = 0
    private var currentURL: URL?
    private weak var originalParent: NSWindow?
    private var observations: [NSObjectProtocol] = []
    private var motionObservation: NSObjectProtocol?
    private let reduceMotion: () -> Bool
    private let presentWindow: @MainActor (NSWindow, NSWindow) -> Void
    private let isPresented: @MainActor (NSWindow) -> Bool
    private var finishing: DownloadLibraryPreview?

    package init(itemName: String = "download",
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         presentWindow: @escaping @MainActor (NSWindow, NSWindow) -> Void = { window, parent in
             parent.addChildWindow(window, ordered: .above)
             window.makeKeyAndOrderFront(nil)
         },
         isPresented: @escaping @MainActor (NSWindow) -> Bool = { $0.isVisible }) {
        self.presentWindow = presentWindow
        self.isPresented = isPresented
        self.reduceMotion = reduceMotion
        let panel = DownloadPreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                                         styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.isMovable = false
        quickLook = QLPreviewView(frame: .zero, style: .normal)
        super.init(window: panel)
        previous.setAccessibilityLabel("Previous " + itemName); next.setAccessibilityLabel("Next " + itemName)
        more.setAccessibilityLabel(itemName.capitalized + " actions"); open.setAccessibilityLabel("Open " + itemName)
        previous.toolTip = "Previous " + itemName; next.toolTip = "Next " + itemName
        more.toolTip = itemName.capitalized + " actions"; open.toolTip = "Open " + itemName
        panel.delegate = self; panel.contentView = root
        quickLook.autostarts = false
        root.wantsLayer = true
        backdrop.wantsLayer = true; backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        backdrop.layer?.cornerRadius = 10
        root.addSubview(backdrop); root.addSubview(modal)
        modal.wantsLayer = true; modal.clipsToBounds = false; modal.layer?.masksToBounds = false
        modal.layer?.cornerRadius = 10; modal.layer?.cornerCurve = .continuous
        modal.layer?.shadowRadius = 5; modal.layer?.shadowOffset = NSSize(width: 0, height: -3)
        modal.layer?.shadowColor = NSColor.black.cgColor; modal.layer?.shadowOpacity = 1
        content.wantsLayer = true; content.layer?.cornerRadius = 10; content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true; content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageView.wantsLayer = true; imageView.imageScaling = .scaleAxesIndependently
        imageView.setAccessibilityElement(false); imageView.setAccessibilityHidden(true)
        imageView.layer?.opacity = 0
        modal.addSubview(content); modal.addSubview(imageView)
        for view in [quickLook, name, previous, next, dismissButton, more, open] { content.addSubview(view) }
        name.font = .systemFont(ofSize: 14, weight: .semibold); name.lineBreakMode = .byTruncatingMiddle
        previous.target = self; previous.action = #selector(movePrevious)
        next.target = self; next.action = #selector(moveNext)
        dismissButton.target = self; dismissButton.action = #selector(dismissPreview)
        more.target = self; more.action = #selector(showMenu)
        open.target = self; open.action = #selector(openFile)
        root.onLayout = { [weak self] in self?.layoutContent() }
        root.onDismiss = { [weak self] in self?.dismiss() }
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.onKey = { [weak self] event in
            guard let self, !self.closing else { return false }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "c" { self.onCopy?(); return true }
            guard modifiers.isEmpty else { return false }
            switch event.keyCode {
            case 49, 53: self.dismiss(); return true
            case 126: if self.previous.isEnabled { self.onMove?(false) }; return true
            case 125: if self.next.isEnabled { self.onMove?(true) }; return true
            case 36, 76: if self.open.isEnabled { self.onOpen?() }; return true
            default: return false
            }
        }
        motionObservation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.reduceMotion(), !self.closed else { return }
                    if self.closing { self.close() } else { self.settleContent() }
                }
            }
    }
    deinit { if let motionObservation { NSWorkspace.shared.notificationCenter.removeObserver(motionObservation) } }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    package func update(url: URL, title: String, ordinal: Int, count: Int, canOpen: Bool,
                canMovePrevious: Bool, canMoveNext: Bool) {
        guard !closing else { return }
        window?.title = title; name.stringValue = title; name.toolTip = "\(title) · \(ordinal) of \(count)"
        name.setAccessibilityValue(name.toolTip)
        open.isEnabled = canOpen; previous.isEnabled = canMovePrevious; next.isEnabled = canMoveNext
        more.isHidden = onMenu == nil
        if currentURL != url { currentURL = url; quickLook.previewItem = url as NSURL }
        root.needsLayout = true
    }
    package func present(on parent: NSWindow) {
        guard let window, !closing, originalParent == nil, parent.attachedSheet == nil else { return }
        originalParent = parent; window.appearance = parent.effectiveAppearance
        window.setFrame(parent.frame, display: false)
        presentWindow(window, parent)
        window.makeFirstResponder(dismissButton)
        root.layoutSubtreeIfNeeded()
        let source = localSourceRect()
        imageView.image = sourceImage
        sourceAspect = source.map { $0.height / $0.width }
        layoutSourceImage()
        let center = NotificationCenter.default
        for notification in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observations.append(center.addObserver(forName: notification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.parentFrameChanged() }
            })
        }
        for notification in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification, NSWindow.willBeginSheetNotification] {
            observations.append(center.addObserver(forName: notification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
        if !reduceMotion(), let source, let layer = modal.layer {
            animate(layer, key: "transform", from: NSValue(caTransform3D: DownloadPreviewGeometry.transform(from: modal.frame, to: source)),
                    to: NSValue(caTransform3D: CATransform3DIdentity), ratio: 0.9, response: 0.25)
            animate(layer, key: "shadowOpacity", from: 0, to: 1, ratio: 0.9, response: 0.25)
            crossfade(opening: true)
            if let backdrop = backdrop.layer { animate(backdrop, key: "opacity", from: 0, to: 1, ratio: 0.9, response: 0.25) }
        }
    }
    private func parentFrameChanged() {
        guard let parent = originalParent, let window, !closed else { return }
        if closing { close(); return }
        transition &+= 1; settleContent()
        window.setFrame(parent.frame, display: true); root.layoutSubtreeIfNeeded()
    }
    private func localSourceRect() -> NSRect? {
        guard let rect = sourceRect?(), let parent = originalParent, let window,
              rect.width > 0, rect.height > 0, rect.intersects(parent.contentView?.bounds ?? .zero) else { return nil }
        return root.convert(window.convertFromScreen(parent.convertToScreen(rect)), from: nil)
    }
    private func layoutContent() {
        backdrop.frame = root.bounds
        modal.frame = DownloadPreviewGeometry.modalFrame(in: root.bounds)
        modal.layer?.anchorPoint = NSPoint(x: 0.5, y: 0.5)
        modal.layer?.position = NSPoint(x: modal.frame.midX, y: modal.frame.midY)
        modal.clipsToBounds = false; modal.layer?.masksToBounds = false
        content.frame = modal.bounds
        modal.layer?.shadowPath = CGPath(roundedRect: modal.bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        content.effectiveAppearance.performAsCurrentDrawingAppearance {
            content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        layoutSourceImage()
        let width = modal.bounds.width, height = modal.bounds.height
        let toolbarHeight = min(height, ceil(name.font!.ascender - name.font!.descender + name.font!.leading) + 14)
        let control: CGFloat = 28, y = max(0, (toolbarHeight - control) / 2)
        dismissButton.frame = NSRect(x: 8, y: y, width: control, height: control)
        previous.frame = NSRect(x: 40, y: y, width: control, height: control)
        next.frame = NSRect(x: 68, y: y, width: control, height: control)
        open.frame = NSRect(x: max(8, width - 36), y: y, width: control, height: control)
        more.frame = NSRect(x: max(8, width - 68), y: y, width: control, height: control)
        let titleX: CGFloat = width < 200 ? 40 : 104
        let trailingWidth: CGFloat = onMenu != nil && width >= 140 ? 76 : 44
        name.frame = NSRect(x: titleX, y: max(0, (toolbarHeight - 20) / 2), width: max(0, width - titleX - trailingWidth), height: 20)
        previous.isHidden = width < 200; next.isHidden = width < 200
        more.isHidden = onMenu == nil || width < 140
        quickLook.frame = NSRect(x: 0, y: toolbarHeight, width: width, height: max(0, height - toolbarHeight))
    }
    private func layoutSourceImage() {
        guard let aspect = sourceAspect else { imageView.frame = modal.bounds; return }
        let height = modal.bounds.width * aspect
        imageView.frame = NSRect(x: 0, y: (modal.bounds.height - height) / 2, width: modal.bounds.width, height: height)
    }
    private func crossfade(opening: Bool) {
        guard imageView.image != nil, let image = imageView.layer, let live = content.layer else { return }
        let ratio = opening ? 0.9 : 0.95, response = opening ? 0.25 : 0.15
        let imageFrom = opening ? Float(1) : image.presentation()?.opacity ?? image.opacity
        let contentFrom = opening ? Float(0) : live.presentation()?.opacity ?? live.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        image.opacity = opening ? 0 : 1; live.opacity = opening ? 1 : 0
        CATransaction.commit()
        animate(image, key: "opacity", from: imageFrom, to: image.opacity, ratio: ratio, response: response)
        animate(live, key: "opacity", from: contentFrom, to: live.opacity, ratio: ratio, response: response)
    }
    private func settleContent() {
        for view in [modal, backdrop, imageView, content] { view.layer?.removeAllAnimations() }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        modal.layer?.transform = CATransform3DIdentity; modal.layer?.shadowOpacity = 1
        backdrop.layer?.opacity = 1; content.layer?.opacity = 1; imageView.layer?.opacity = 0
        CATransaction.commit()
    }
    private func animate(_ layer: CALayer, key: String, from: Any, to: Any, ratio: Double, response: Double) {
        let animation = DownloadPreviewGeometry.spring(keyPath: key, ratio: ratio, response: response)
        animation.fromValue = from; animation.toValue = to; layer.add(animation, forKey: key)
    }
    var isShown: Bool { window.map(isPresented) ?? false }
    func dismiss() {
        guard !closing else { return }
        guard isShown, !reduceMotion(), let source = localSourceRect(), let layer = modal.layer else { close(); return }
        closing = true; finishing = self; transition &+= 1
        let token = transition
        let target = DownloadPreviewGeometry.transform(from: modal.frame, to: source)
        let from = layer.presentation()?.transform ?? CATransform3DIdentity
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { guard let self, self.transition == token else { return }; self.close() }
        }
        let transform = DownloadPreviewGeometry.spring(keyPath: "transform", ratio: 0.95, response: 0.15)
        transform.fromValue = NSValue(caTransform3D: from); transform.toValue = NSValue(caTransform3D: target)
        transform.isRemovedOnCompletion = false; transform.fillMode = .forwards
        layer.add(transform, forKey: "transform")
        crossfade(opening: false)
        animate(layer, key: "shadowOpacity", from: layer.presentation()?.shadowOpacity ?? 1, to: 0, ratio: 0.95, response: 0.15)
        if let backdrop = backdrop.layer {
            animate(backdrop, key: "opacity", from: backdrop.presentation()?.opacity ?? 1, to: 0, ratio: 0.95, response: 0.15)
        }
        CATransaction.setDisableActions(true)
        layer.shadowOpacity = 0; backdrop.layer?.opacity = 0
        CATransaction.commit()
    }
    @objc private func dismissPreview() { dismiss() }
    @objc private func movePrevious() { if !closing, previous.isEnabled { onMove?(false) } }
    @objc private func moveNext() { if !closing, next.isEnabled { onMove?(true) } }
    @objc private func openFile() { if !closing, open.isEnabled { onOpen?() } }
    @objc private func showMenu() {
        guard !closing, let menu = onMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: more.bounds.maxY), in: more)
    }
    package func windowWillClose(_ notification: Notification) { finishClose() }
    private func finishClose() {
        guard !closed else { return }; closing = true; closed = true; transition &+= 1
        for observation in observations { NotificationCenter.default.removeObserver(observation) }; observations = []
        if let motionObservation { NSWorkspace.shared.notificationCenter.removeObserver(motionObservation) }; motionObservation = nil
        for view in [modal, backdrop, imageView, content] { view.layer?.removeAllAnimations() }
        sourceImage = nil; imageView.image = nil; sourceAspect = nil
        quickLook.previewItem = nil; quickLook.close()
        if let window, let parent = window.parent { parent.removeChildWindow(window) }
        let callback = onClosed
        onClosed = nil; onMove = nil; onOpen = nil; onCopy = nil; onMenu = nil; sourceRect = nil
        root.onDismiss = nil; originalParent = nil
        callback?(); finishing = nil
    }
    package override func close() { finishClose(); super.close() }
}

@MainActor enum DownloadPreviewGeometry {
    static func modalFrame(in bounds: NSRect) -> NSRect {
        let width = min(bounds.width, max((bounds.width * 0.8).rounded() - 50, 100))
        let height = min(bounds.height, max((bounds.height * 0.8).rounded() - 50, 100))
        return NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }
    static func transform(from frame: NSRect, to source: NSRect) -> CATransform3D {
        let scale = source.width / max(1, frame.width)
        var transform = CATransform3DMakeTranslation(source.midX - frame.midX, source.midY - frame.midY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return transform
    }
    static func spring(keyPath: String, ratio: Double, response: Double) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1; animation.stiffness = pow(2 * .pi / response, 2)
        animation.damping = 4 * .pi * ratio / response; animation.duration = animation.settlingDuration
        return animation
    }
}

@MainActor private final class DownloadPreviewBackdrop: LayoutView {
    var onDismiss: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        layer?.cornerRadius = 10; layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func mouseDown(with event: NSEvent) { onDismiss?() }
}

@MainActor private final class DownloadPreviewModal: LayoutView {
    override func mouseDown(with event: NSEvent) {}
}

@MainActor private final class DownloadPreviewImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor private final class DownloadPreviewButton: PointingHandButton {
    private var tracking: NSTrackingArea?
    private var hovered = false
    init(symbol: String, label: String) {
        super.init(frame: .zero); isBordered = false; bezelStyle = .regularSquare
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        toolTip = label; setAccessibilityLabel(label); focusRingType = .default
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovered = isTopmost(atWindowPoint: event.locationInWindow); needsDisplay = true }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        let value = isTopmost(atWindowPoint: event.locationInWindow)
        guard value != hovered else { return }
        hovered = value; needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (hovered || isHighlighted) {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.16 : 0.1).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        super.draw(dirtyRect)
    }
}

@MainActor private final class DownloadPreviewPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        let editing = (firstResponder as? NSTextView).map { $0.isEditable || $0.hasMarkedText() } ?? false
        if event.type == .keyDown, !editing, onKey?(event) == true { return }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}
