import AppKit
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
enum SidebarSpaceHeaderTestsSupport {
    typealias L = SidebarChromeLayout

    typealias H = L.SpaceHeader

    typealias Content = H.Content

    final class FlippedHost: NSView { override var isFlipped: Bool { true } }

    static func space(_ name: String, icon: SidebarGroupIcon? = nil) -> BrowserSpace {
        var space = BrowserSpace(id: UUID(), name: name, symbol: "circle.fill", color: "B9B5D4", profileID: UUID())
        space.customIcon = icon
        if name.hasPrefix("Space "), Int(name.dropFirst(6)) != nil { space.title = nil }
        return space
    }

    static func content(_ spaces: [BrowserSpace], _ active: BrowserSpace?, privateWindow: Bool = false, setting: Bool = false) -> Content {
        H.content(spaces: spaces, activeSpaceID: active?.id, privateWindow: privateWindow, showOnSingleUnnamedSpace: setting)
    }

    static func titled(_ name: String) -> Content { Content(isShown: true, title: name, placeholder: nil, toggleTitle: nil) }

    static func components(_ color: NSColor?) -> [CGFloat]? {
        guard let color = color?.usingColorSpace(.sRGB) else { return nil }
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
    }

    static func components(_ color: CGColor?) -> [CGFloat]? { components(color.flatMap { NSColor(cgColor: $0) }) }

    static func pixels(_ view: NSView) -> Data? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.bitmapData.map { Data(bytes: $0, count: rep.bytesPerRow * rep.pixelsHigh) }
    }

    static let base = ["Rename Space…", "Edit Theme Color…", "New Folder"]

    static let star = NSImage(systemSymbolName: "star", accessibilityDescription: nil)

    static var ellipsis: NSImage? {
        NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
    }

    @MainActor final class Header {
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 228, height: 400), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 228, height: 400))
        let header = SidebarSpaceHeaderView()
        let list = NSView()
        var scheduled: [(delay: TimeInterval, body: @MainActor () -> Void)] = []
        var calls: [String] = []

        init(_ content: Content? = nil, icon: Bool = true) {
            let content = content ?? SidebarSpaceHeaderTestsSupport.titled("Work")
            let symbol = icon ? SidebarSpaceHeaderTestsSupport.star : nil
            window.isReleasedWhenClosed = false
            host.wantsLayer = true
            host.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            host.addSubview(header); host.addSubview(list)
            header.scheduleHoverUpdate = { [weak self] in guard let self else { return }; scheduled.append(($0, $1)) }
            header.frame = NSRect(x: 0, y: H.top(trayHeight: 0, hasFavorites: false), width: 228, height: H.height)
            list.frame = NSRect(x: 8, y: L.tablistTop(trayHeight: 0, spaceHeader: true), width: 212, height: 100)
            header.update(content, symbol: symbol, emoji: nil)
            header.layoutSubtreeIfNeeded()
            header.onRenameSpace = { [weak self] in guard let self else { return }; calls.append("rename") }
            header.onEditTheme = { [weak self] in guard let self else { return }; calls.append("theme") }
            header.onNewFolder = { [weak self] in guard let self else { return }; calls.append("folder") }
            header.onToggleHeader = { [weak self] in guard let self else { return }; calls.append("toggle") }
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        var field: SidebarMaskedTextField { header.nameField }
        var button: SidebarSpaceHeaderEditButton { header.editButton }
        var symbolView: NSImageView { header.subviews.compactMap { $0 as? NSImageView }.first! }
        var emoji: NSTextField { header.subviews.compactMap { $0 as? NSTextField }.first { $0 !== header.nameField }! }
        var titleHeight: CGFloat { field.intrinsicContentSize.height }

        func runScheduled(_ observe: () -> Void = {}) {
            while !scheduled.isEmpty {
                let pending = scheduled.enumerated().sorted { ($0.element.delay, $0.offset) < ($1.element.delay, $1.offset) }.map(\.element)
                scheduled.removeAll()
                for item in pending { item.body(); observe() }
            }
        }
        func crossing(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        func enter() { header.mouseEntered(with: crossing(.mouseEntered)) }
        func exit() { header.mouseExited(with: crossing(.mouseExited)) }
        func showButton() {
            header.canShowHeaderButtonsIfPossible = true
            enter(); runScheduled()
        }
        var click: NSEvent? {
            NSEvent.mouseEvent(with: .rightMouseDown, location: header.convert(NSPoint(x: 100, y: 18), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        func press(clickCount: Int, modifiers: NSEvent.ModifierFlags = []) {
            guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: header.convert(NSPoint(x: 100, y: 18), to: nil),
                                                 modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1) else { return }
            header.mouseDown(with: event)
        }
        func fill() -> [CGFloat]? { button.display(); return SidebarSpaceHeaderTestsSupport.components(button.layer?.backgroundColor) }
        var opacityFade: CABasicAnimation? { button.layer?.animation(forKey: "opacity") as? CABasicAnimation }
        var exposed: [NSObject] {
            NSAccessibility.unignoredChildren(from: header.accessibilityChildren() ?? []).compactMap { $0 as? NSObject }
        }
    }

    static func controlPoints(_ function: CAMediaTimingFunction?) -> [Float]? {
        guard let function else { return nil }
        return (0..<4).flatMap { index -> [Float] in
            var point: [Float] = [0, 0]
            function.getControlPoint(at: index, values: &point)
            return point
        }
    }

    static func isEditFade(_ fade: CABasicAnimation?) -> Bool {
        fade?.duration == 0.1 && controlPoints(fade?.timingFunction) == controlPoints(CAMediaTimingFunction(name: .easeOut))
    }

    static func placeholder() -> (Header, SidebarSpaceHeaderView) {
        var first = Self.space("Space 1")
        first.title = nil
        let header = Header(Self.content([first], first, setting: true), icon: false)
        let reference = SidebarSpaceHeaderView()
        header.host.addSubview(reference)
        reference.frame = NSRect(x: 0, y: 200, width: 228, height: H.height)
        reference.update(Self.titled("Space 1"), symbol: nil, emoji: nil)
        reference.layoutSubtreeIfNeeded()
        return (header, reference)
    }

    static func editing() -> Header {
        let header = Header(icon: false)
        header.header.canShowHeaderButtonsIfPossible = true
        header.header.isEditing = true
        return header
    }
}
