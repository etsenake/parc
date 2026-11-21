import AppKit
import ParcEngine

@MainActor
enum ParcContextMenuMetrics {
    static let rowHeight: CGFloat = 32
    static let inset = SidebarPlusMenuView.inset
    static let minimumWidth: CGFloat = 180
    static let maximumWidth: CGFloat = 320
    static let titleInset: CGFloat = 10
    static let stateTitleInset: CGFloat = 28
    static let stateCenterX: CGFloat = 15
    static let imageSize: CGFloat = 16
    static let chevronWidth: CGFloat = 16
    static let chevronCenterInset: CGFloat = 14
    static let gap: CGFloat = 4
    static let submenuAimDelay: TimeInterval = 0.25
    static let shadowMargin: CGFloat = 8
    static let shadowOpacity: CGFloat = 0.2
    static let shadowRadius: CGFloat = 3

    static func frame(card size: NSSize, reach: CGFloat, beside row: NSRect, right: Bool,
                      regions: [NSRect]) -> (frame: NSRect, right: Bool) {
        func placed(_ right: Bool) -> NSRect {
            NSRect(x: right ? row.maxX + gap : row.minX - gap - size.width,
                   y: row.maxY + inset - size.height, width: size.width, height: size.height)
        }
        func room(_ right: Bool, in region: NSRect) -> CGFloat {
            right ? region.maxX - row.maxX - gap : row.minX - gap - region.minX
        }
        let roomy = regions.first { region in
            region.minY <= row.minY && row.maxY <= region.maxY && size.height <= region.height
                && (room(true, in: region) >= size.width || room(false, in: region) >= size.width)
        }
        guard let region = roomy ?? regions.last else { return (placed(right), right) }
        let sides = [right, !right]
        let side = sides.first { room($0, in: region) >= reach } ?? sides.first { room($0, in: region) >= size.width }
            ?? (room(!right, in: region) > room(right, in: region) ? !right : right)
        var frame = placed(side)
        frame.origin.x = max(region.minX, min(frame.minX, region.maxX - frame.width))
        frame.origin.y = max(region.minY, min(frame.minY, region.maxY - frame.height))
        return (frame, side)
    }

    static func shownItems(_ menu: NSMenu) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for item in menu.items where !item.isHidden {
            if item.isSeparatorItem, items.last?.isSeparatorItem ?? true { continue }
            items.append(item)
        }
        if items.last?.isSeparatorItem == true { items.removeLast() }
        return items
    }
}

@MainActor
final class ParcContextMenuView: NSView {
    let source: NSMenu
    let items: [NSMenuItem]
    private(set) var rows: [NSRect] = []
    var highlighted: Int? { didSet { if highlighted != oldValue { needsDisplay = true } } }
    var colors: ParcMenuColors { didSet { needsDisplay = true } }
    var onPress: ((Int) -> Void)?
    private let showsState: Bool
    private var elements: [Element] = []
    private var faces: [Face] = []
    private static let checkConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
    private static let chevronConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)

    init(menu: NSMenu, colors: ParcMenuColors) {
        let m = ParcContextMenuMetrics.self
        source = menu
        self.colors = colors
        items = m.shownItems(menu)
        showsState = items.contains { $0.state != .off || $0.image != nil }
        let width = Self.cardWidth(items)
        let heights = items.map { $0.isSeparatorItem ? SidebarPlusMenuView.divider : m.rowHeight }
        var top = 2 * (m.shadowMargin + m.inset) + heights.reduce(0, +)
        let size = NSSize(width: width + 2 * m.shadowMargin, height: top)
        top -= m.shadowMargin + m.inset
        for height in heights {
            top -= height
            rows.append(NSRect(x: m.shadowMargin + m.inset, y: top, width: width - 2 * m.inset, height: height))
        }
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        for (index, item) in items.enumerated() where !item.isSeparatorItem {
            let element = Element(index: index, view: self)
            element.setAccessibilityRole(.menuItem)
            element.setAccessibilityLabel(item.title)
            element.setAccessibilityHelp(item.toolTip)
            element.setAccessibilityEnabled(item.isEnabled)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(rows[index])
            elements.append(element)
        }
        setAccessibilityChildren(elements)
        faces = items.map(Face.init)
    }

    private struct Face: Equatable {
        let title: String
        let enabled: Bool
        let state: NSControl.StateValue
        @MainActor init(_ item: NSMenuItem) { title = item.title; enabled = item.isEnabled; state = item.state }
    }

    @discardableResult
    func refresh() -> Set<Int> {
        source.update()
        var changed = Set<Int>()
        for (index, item) in items.enumerated() where Face(item) != faces[index] {
            faces[index] = Face(item)
            changed.insert(index)
        }
        guard !changed.isEmpty else { return changed }
        for element in elements where changed.contains(element.index) {
            element.setAccessibilityLabel(items[element.index].title)
            element.setAccessibilityEnabled(items[element.index].isEnabled)
            NSAccessibility.post(element: element, notification: .titleChanged)
        }
        if let highlighted, !items[highlighted].isEnabled { self.highlighted = nil }
        needsDisplay = true
        return changed
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var reach: CGFloat { Self.reach(items) }

    static func reach(_ items: [NSMenuItem]) -> CGFloat {
        let chains = items.compactMap(\.submenu).map { ParcContextMenuMetrics.gap + reach(ParcContextMenuMetrics.shownItems($0)) }
        return cardWidth(items) + (chains.max() ?? 0)
    }

    static func cardWidth(_ items: [NSMenuItem]) -> CGFloat {
        let m = ParcContextMenuMetrics.self
        let titleWidth = items.map { title($0, color: .black).size().width }.max() ?? 0
        let leading = items.contains { $0.state != .off || $0.image != nil } ? m.stateTitleInset : m.titleInset
        let trailing = m.titleInset + (items.contains { $0.hasSubmenu } ? m.chevronWidth : 0)
        return min(m.maximumWidth, max(m.minimumWidth, ceil(2 * m.inset + leading + titleWidth + trailing)))
    }

    var card: NSRect { bounds.insetBy(dx: ParcContextMenuMetrics.shadowMargin, dy: ParcContextMenuMetrics.shadowMargin) }

    func submenuAnchor(_ row: Int) -> NSRect {
        NSRect(x: card.minX, y: rows[row].minY, width: card.width, height: rows[row].height)
    }

    func row(at point: NSPoint) -> Int? {
        rows.indices.first { rows[$0].contains(point) && !items[$0].isSeparatorItem }
    }

    private static func title(_ item: NSMenuItem, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: item.title, attributes: [
            .font: SidebarPlusRowButton.titleFont, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private static func draw(_ image: NSImage, size: NSSize, color: NSColor?, center: NSPoint) {
        let rect = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let tinted = color.map { color in
            NSImage(size: size, flipped: false) { bounds in
                image.draw(in: bounds)
                color.setFill()
                bounds.fill(using: .sourceAtop)
                return true
            }
        } ?? image
        tinted.draw(in: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        let m = ParcContextMenuMetrics.self
        let path = NSBezierPath(roundedRect: card, xRadius: SidebarPlusMenuPlacement.cornerRadius,
                                yRadius: SidebarPlusMenuPlacement.cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(m.shadowOpacity)
        shadow.shadowBlurRadius = m.shadowRadius
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        colors.base.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        colors.background.setFill()
        path.fill()
        for (index, item) in items.enumerated() {
            let row = rows[index]
            if item.isSeparatorItem {
                let edge = SidebarPlusMenuView.separatorInsets
                let line = NSRect(x: row.minX + edge.left, y: row.minY + edge.bottom,
                                  width: row.width - edge.left - edge.right, height: 1)
                colors.hover.setFill()
                NSBezierPath(roundedRect: line, xRadius: 0.5, yRadius: 0.5).fill()
                continue
            }
            if index == highlighted {
                colors.hover.setFill()
                NSBezierPath(roundedRect: row, xRadius: SidebarPlusRowButton.plateRadius,
                             yRadius: SidebarPlusRowButton.plateRadius).fill()
            }
            let color = item.isEnabled ? colors.title : colors.disabledTitle
            let stateCenter = NSPoint(x: row.minX + m.stateCenterX, y: row.midY)
            if item.state != .off,
               let mark = NSImage(systemSymbolName: item.state == .on ? "checkmark" : "minus", accessibilityDescription: nil)?
                .withSymbolConfiguration(Self.checkConfiguration) {
                Self.draw(mark, size: mark.size, color: color, center: stateCenter)
            } else if let image = item.image {
                Self.draw(image, size: NSSize(width: m.imageSize, height: m.imageSize),
                          color: image.isTemplate ? color : nil, center: stateCenter)
            }
            let leading = showsState ? m.stateTitleInset : m.titleInset
            let trailing = m.titleInset + (item.hasSubmenu ? m.chevronWidth : 0)
            let title = Self.title(item, color: color)
            let height = ceil(title.size().height)
            title.draw(with: NSRect(x: row.minX + leading, y: row.midY - height / 2,
                                    width: row.width - leading - trailing, height: height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            if item.hasSubmenu, let chevron = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(Self.chevronConfiguration) {
                Self.draw(chevron, size: chevron.size, color: item.isEnabled ? colors.subtitle : colors.disabledSubtitle,
                          center: NSPoint(x: row.maxX - m.chevronCenterInset, y: row.midY))
            }
        }
    }

    private final class Element: NSAccessibilityElement {
        let index: Int
        weak var view: ParcContextMenuView?
        init(index: Int, view: ParcContextMenuView) {
            self.index = index
            self.view = view
            super.init()
        }
        override func accessibilityPerformPress() -> Bool {
            MainActor.assumeIsolated {
                guard let onPress = view?.onPress else { return false }
                onPress(index)
                return true
            }
        }
    }
}

@MainActor
final class ParcContextMenu: NSObject, PCNativeMenuPresenter {
    private let anchor: NSRect
    private let regions: [NSRect]
    private weak var parent: NSWindow?
    private let colors: ParcMenuColors
    private var levels: [(view: ParcContextMenuView, window: NSWindow, right: Bool)] = []
    private var running = false
    private var done = false
    private var chosen: NSMenuItem?
    private var pointer: NSPoint?
    private var pendingRow: Timer?
    private var tip: (level: Int, row: Int, timer: Timer?, delay: TimeInterval)?
    private var tipPresenter: (presenter: TooltipPresenter, level: Int)?
    private var refreshed: (level: Int, row: Int)?
    var willPerform: ((NSMenuItem) -> Void)?

    init(anchor: NSRect, regions: [NSRect], parent: NSWindow, colors: ParcMenuColors) {
        self.anchor = anchor
        self.regions = regions
        self.parent = parent
        self.colors = colors
    }

    @objc(presentMenu:)
    func present(_ menu: NSMenu) -> Bool {
        guard !running, let parent, parent.isVisible else { return false }
        running = true
        done = false
        open(menu, beside: anchor, right: true)
        let resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                            object: NSApp, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.done = true }
        }
        while !done, parent.isVisible {
            guard let event = NSApp.nextEvent(matching: .any, until: .distantFuture, inMode: .eventTracking,
                                              dequeue: true) else { continue }
            handle(event)
        }
        NotificationCenter.default.removeObserver(resign)
        close()
        running = false
        if let item = chosen, let owner = item.menu {
            chosen = nil
            willPerform?(item)
            let index = owner.index(of: item)
            if index >= 0 { owner.performActionForItem(at: index) }
        }
        return true
    }

    @objc(cancelMenu)
    func cancel() {
        guard running, !done else { return }
        done = true
        wake()
    }

    private func wake() {
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: true)
        }
    }

    private static let ignored: Set<NSEvent.EventType> = [.keyUp, .flagsChanged, .scrollWheel, .magnify, .rotate, .swipe,
                                                          .smartMagnify, .beginGesture, .endGesture, .pressure]

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            track(location(of: event))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if hit(location(of: event)) == nil { done = true }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if let (level, row) = hit(location(of: event)), let row { choose(level: level, row: row) }
        case .keyDown:
            key(event)
        case let type where Self.ignored.contains(type):
            break
        default:
            NSApp.sendEvent(event)
        }
    }

    private func location(of event: NSEvent) -> NSPoint {
        event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
    }

    private func hit(_ point: NSPoint) -> (level: Int, row: Int?)? {
        for index in levels.indices.reversed() {
            let (view, window, _) = levels[index]
            let local = view.convert(window.convertPoint(fromScreen: point), from: nil)
            if view.card.contains(local) { return (index, view.row(at: local)) }
        }
        return nil
    }

    private func track(_ point: NSPoint) {
        let previous = pointer
        pointer = point
        pendingRow?.invalidate()
        pendingRow = nil
        guard let (level, row) = hit(point) else {
            hover(nil, in: nil)
            levels.last?.view.highlighted = nil
            refreshed = nil
            return
        }
        hover(row, in: level)
        guard let row else { return }
        let item = levels[level].view.items[row]
        let opened = level + 1 < levels.count && levels[level + 1].view.source === item.submenu
        if !opened, level + 1 < levels.count, let previous, heading(from: previous, to: point, into: level + 1) {
            let timer = Timer(timeInterval: ParcContextMenuMetrics.submenuAimDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.highlight(row, in: level) }
            }
            RunLoop.main.add(timer, forMode: .common)
            pendingRow = timer
            return
        }
        highlight(row, in: level)
    }

    private func hover(_ row: Int?, in level: Int?) {
        if let tip, tip.level == level, tip.row == row {
            tip.timer?.fireDate = Date(timeIntervalSinceNow: tip.delay)
            return
        }
        let left = tip != nil
        tip?.timer?.invalidate()
        tip = nil
        guard let level, let row, let reason = levels[level].view.items[row].toolTip, !reason.isEmpty else {
            if left { fadeTip(TooltipTiming.exitDuration) }
            return
        }
        let configuration = TooltipConfiguration(reason)
        if tipPresenter != nil {
            tip = (level, row, nil, 0)
            showTip(configuration, level: level, row: row)
            return
        }
        var delay = TooltipTiming.pointerStopDelay
        if case .onMouseIdle(let idle) = configuration.behavior { delay += idle }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tip?.timer = nil
                self?.showTip(configuration, level: level, row: row)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tip = (level, row, timer, delay)
    }

    private func showTip(_ configuration: TooltipConfiguration, level: Int, row: Int) {
        guard levels.indices.contains(level), let parent else { return }
        let (view, window, _) = levels[level]
        if let current = tipPresenter, current.level != level {
            current.presenter.close()
            tipPresenter = nil
        }
        let presenter = tipPresenter?.presenter ?? TooltipPresenter(parent: window)
        let content = TooltipView.Content(label: configuration.label, keycaps: [],
                                          corners: TooltipCorners(anchor: configuration.anchor),
                                          palette: TooltipController.controller(for: parent).palette ?? .neutral,
                                          maxWidth: TooltipConfiguration.defaultMaxWidth)
        if presenter.present(content, anchor: configuration.anchor, from: view, rect: view.rows[row]) {
            tipPresenter = (presenter, level)
        } else {
            presenter.close()
            tipPresenter = nil
        }
    }

    private func fadeTip(_ duration: TimeInterval) {
        guard let current = tipPresenter else { return }
        current.presenter.dismiss(duration: duration, delay: 0) { [weak self] in
            guard let self, self.tipPresenter?.presenter === current.presenter else { return }
            self.tipPresenter = nil
        }
    }

    private func hideTip(fade: TimeInterval = TooltipTiming.interruptionDuration) {
        tip?.timer?.invalidate()
        tip = nil
        fadeTip(fade)
    }

    private func highlight(_ row: Int, in level: Int) {
        pendingRow = nil
        guard levels.indices.contains(level) else { return }
        let view = levels[level].view
        refresh(row, in: level)
        let item = view.items[row]
        let opened = level + 1 < levels.count && levels[level + 1].view.source === item.submenu
        closeLevels(after: opened ? level + 1 : level)
        view.highlighted = item.isEnabled ? row : nil
        if !opened, item.isEnabled, let submenu = item.submenu { openSubmenu(submenu, from: level, row: row) }
    }

    private func heading(from: NSPoint, to: NSPoint, into level: Int) -> Bool {
        let (view, window, right) = levels[level]
        let card = window.convertToScreen(view.convert(view.card, to: nil))
        let top = NSPoint(x: right ? card.minX : card.maxX, y: card.maxY)
        let bottom = NSPoint(x: top.x, y: card.minY)
        func side(_ a: NSPoint, _ b: NSPoint) -> CGFloat { (b.x - a.x) * (to.y - a.y) - (b.y - a.y) * (to.x - a.x) }
        let sides = [side(from, top), side(top, bottom), side(bottom, from)]
        return !(sides.contains { $0 < 0 } && sides.contains { $0 > 0 })
    }

    private func key(_ event: NSEvent) {
        pendingRow?.invalidate()
        pendingRow = nil
        hideTip()
        guard let level = levels.lastIndex(where: { $0.view.highlighted != nil }) ?? levels.indices.last else { return }
        let view = levels[level].view
        switch event.keyCode {
        case 125, 126:
            closeLevels(after: level)
            move(event.keyCode == 125 ? 1 : -1, in: level)
        case 124, 36, 76, 49:
            guard let row = view.highlighted else { return }
            if let submenu = view.items[row].submenu {
                if levels.count == level + 1 { openSubmenu(submenu, from: level, row: row) }
                move(1, in: level + 1)
            } else if event.keyCode != 124 {
                choose(level: level, row: row)
            }
        case 123:
            if level > 0 { closeLevels(after: level - 1) }
        case 53:
            done = true
        default:
            break
        }
    }

    private func move(_ delta: Int, in level: Int) {
        guard levels.indices.contains(level) else { return }
        let view = levels[level].view
        view.refresh()
        let enabled = view.items.indices.filter { !view.items[$0].isSeparatorItem && view.items[$0].isEnabled }
        guard let first = enabled.first, let last = enabled.last else { return }
        if let current = view.highlighted, let position = enabled.firstIndex(of: current) {
            view.highlighted = enabled[(position + delta + enabled.count) % enabled.count]
        } else {
            view.highlighted = delta > 0 ? first : last
        }
        if let row = view.highlighted { refreshed = (level, row) }
    }

    private func refresh(_ row: Int, in level: Int) {
        guard refreshed?.level != level || refreshed?.row != row else { return }
        refreshed = (level, row)
        levels[level].view.refresh()
    }

    @discardableResult
    private func choose(level: Int, row: Int) -> Bool {
        guard levels.indices.contains(level) else { return false }
        let view = levels[level].view
        refreshed = (level, row)
        guard !view.refresh().contains(row) else { return false }
        let item = view.items[row]
        guard item.isEnabled, !item.isSeparatorItem, !item.hasSubmenu else { return false }
        chosen = item
        done = true
        return true
    }

    private func openSubmenu(_ submenu: NSMenu, from level: Int, row: Int) {
        let (view, window, right) = levels[level]
        open(submenu, beside: window.convertToScreen(view.convert(view.submenuAnchor(row), to: nil)), right: right)
    }

    private func open(_ menu: NSMenu, beside row: NSRect, right: Bool) {
        guard let owner = levels.last?.window ?? parent else { return }
        menu.update()
        menu.delegate?.menuWillOpen?(menu)
        let view = ParcContextMenuView(menu: menu, colors: colors)
        let margin = ParcContextMenuMetrics.shadowMargin
        let placed = ParcContextMenuMetrics.frame(card: view.card.size, reach: view.reach, beside: row, right: right,
                                                 regions: regions)
        let window = NSWindow(contentRect: placed.frame.insetBy(dx: -margin, dy: -margin), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.appearance = parent?.effectiveAppearance
        window.contentView = view
        let level = levels.count
        view.onPress = { [weak self] row in
            guard let self, self.choose(level: level, row: row) else { return }
            self.wake()
        }
        owner.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        levels.append((view, window, placed.right))
        SidebarPlusMenuMotion.animateOpen(view, about: Self.pivot(view, right: placed.right))
    }

    private static func pivot(_ view: ParcContextMenuView, right: Bool) -> NSPoint {
        NSPoint(x: right ? view.card.minX : view.card.maxX, y: view.card.maxY)
    }

    private func closeLevels(after level: Int) {
        if let tip, tip.level > level {
            tip.timer?.invalidate()
            self.tip = nil
        }
        if let current = tipPresenter, current.level > level {
            current.presenter.close()
            tipPresenter = nil
        }
        if let current = refreshed, current.level > level { refreshed = nil }
        while levels.count > level + 1, let (view, window, _) = levels.popLast() {
            view.onPress = nil
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
            view.source.delegate?.menuDidClose?(view.source)
        }
    }

    private func close() {
        pendingRow?.invalidate()
        pendingRow = nil
        pointer = nil
        hideTip()
        while let (view, window, right) = levels.popLast() {
            view.onPress = nil
            let remove = {
                window.parent?.removeChildWindow(window)
                window.orderOut(nil)
            }
            if !SidebarPlusMenuMotion.animateClose(view, about: Self.pivot(view, right: right), completion: remove) {
                remove()
            }
            view.source.delegate?.menuDidClose?(view.source)
        }
    }
}
