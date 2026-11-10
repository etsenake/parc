import AppKit

/// The dock + menu's inset, plate, type and separators, with 32-point rows:
/// the Site Control Center's tile and footer height.
@MainActor
enum PArcContextMenuMetrics {
    static let rowHeight: CGFloat = 32
    static let inset = SidebarPlusMenuView.inset
    static let minimumWidth: CGFloat = 180
    static let maximumWidth: CGFloat = 320
    /// Title inset from the row's edges, and with a state column.
    static let titleInset: CGFloat = 10
    static let stateTitleInset: CGFloat = 28
    static let stateCenterX: CGFloat = 15
    static let imageSize: CGFloat = 16
    static let chevronWidth: CGFloat = 16
    static let chevronCenterInset: CGFloat = 14
    /// Between the card and the control or row it hangs from.
    static let gap: CGFloat = 4
    /// How long a row waits while the pointer heads into an open submenu.
    static let submenuAimDelay: TimeInterval = 0.25
    ///
    /// 3, one point down; the window pads the card for it.
    static let shadowMargin: CGFloat = 8
    static let shadowOpacity: CGFloat = 0.2
    static let shadowRadius: CGFloat = 3

    /// The card beside `row` (screen coordinates), its first row level with
    /// `row`: to the right when `right` and it fits, otherwise on the side
    /// with more room, then moved up or down onto `screen`.
    static func frame(card size: NSSize, beside row: NSRect, right: Bool,
                      screen: NSRect?) -> (frame: NSRect, right: Bool) {
        func placed(_ right: Bool) -> NSRect {
            NSRect(x: right ? row.maxX + gap : row.minX - gap - size.width,
                   y: row.maxY + inset - size.height, width: size.width, height: size.height)
        }
        guard let screen else { return (placed(right), right) }
        let fits = { (right: Bool) in right ? placed(true).maxX <= screen.maxX : placed(false).minX >= screen.minX }
        var side = right
        if !fits(side) { side = fits(!side) ? !side : screen.maxX - row.maxX >= row.minX - screen.minX }
        var frame = placed(side)
        if frame.minY < screen.minY { frame.origin.y = screen.minY }
        if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }
        return (frame, side)
    }

    /// The items a menu shows: visible ones, without leading, trailing or
    /// repeated separators.
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

/// One level of the menu: its card and rows, padded for the shadow.
@MainActor
final class PArcContextMenuView: NSView {
    /// The menu this card shows.
    let source: NSMenu
    let items: [NSMenuItem]
    /// Each item's row, separators included, in this view's coordinates.
    private(set) var rows: [NSRect] = []
    var highlighted: Int? { didSet { if highlighted != oldValue { needsDisplay = true } } }
    var colors: PArcMenuColors { didSet { needsDisplay = true } }
    var onPress: ((Int) -> Void)?
    private let showsState: Bool
    private static let checkConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
    private static let chevronConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)

    init(menu: NSMenu, colors: PArcMenuColors) {
        let m = PArcContextMenuMetrics.self
        source = menu
        self.colors = colors
        items = m.shownItems(menu)
        showsState = items.contains { $0.state != .off || $0.image != nil }
        let titleWidth = items.map { Self.title($0, color: .black).size().width }.max() ?? 0
        let leading = showsState ? m.stateTitleInset : m.titleInset
        let trailing = m.titleInset + (items.contains { $0.hasSubmenu } ? m.chevronWidth : 0)
        let width = min(m.maximumWidth, max(m.minimumWidth, ceil(2 * m.inset + leading + titleWidth + trailing)))
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
        var elements: [Element] = []
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The card, inside the shadow's margin.
    var card: NSRect { bounds.insetBy(dx: PArcContextMenuMetrics.shadowMargin, dy: PArcContextMenuMetrics.shadowMargin) }

    /// Where `row`'s submenu hangs from: the card's edges at the row's height.
    func submenuAnchor(_ row: Int) -> NSRect {
        NSRect(x: card.minX, y: rows[row].minY, width: card.width, height: rows[row].height)
    }

    /// The item row (not a separator) under `point`, in this view's coordinates.
    func row(at point: NSPoint) -> Int? {
        rows.indices.first { rows[$0].contains(point) && !items[$0].isSeparatorItem }
    }

    private static func title(_ item: NSMenuItem, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: item.title, attributes: [
            .font: SidebarPlusRowButton.titleFont, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    /// `image` filled with `color` where it has ink, centred on `center`.
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
        let m = PArcContextMenuMetrics.self
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

    /// A row as VoiceOver sees it; pressing it chooses the item.
    private final class Element: NSAccessibilityElement {
        let index: Int
        weak var view: PArcContextMenuView?
        init(index: Int, view: PArcContextMenuView) {
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

///
/// at Josh's request in place of AppKit's grey menu at the pointer. The card
/// hangs beside the control like a submenu beside its row, and submenus hang
/// the same way. Like NSMenu, `present` runs its own event loop and returns
/// once the menu has closed and the chosen item has been performed, so the
/// engine's model lease spans the command.
@MainActor
final class PArcContextMenu: NSObject, PCNativeMenuPresenter {
    private let anchor: NSRect
    private weak var parent: NSWindow?
    private let colors: PArcMenuColors
    private var levels: [(view: PArcContextMenuView, window: NSWindow, right: Bool)] = []
    private var running = false
    private var done = false
    private var chosen: NSMenuItem?
    /// Where the pointer last was, and a row switch waiting while it heads
    /// into an open submenu.
    private var pointer: NSPoint?
    private var pendingRow: Timer?

    /// `anchor` is the control's rectangle on screen; the cards are child
    /// windows of `parent`, in its appearance.
    init(anchor: NSRect, parent: NSWindow, colors: PArcMenuColors) {
        self.anchor = anchor
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
        // NSMenu's mode: page and engine work continues; default-mode timers wait.
        while !done, parent.isVisible {
            guard let event = NSApp.nextEvent(matching: .any, until: .distantFuture, inMode: .eventTracking,
                                              dequeue: true) else { continue }
            handle(event)
        }
        NotificationCenter.default.removeObserver(resign)
        close()
        running = false
        // AppKit performs the chosen item after the menu has closed.
        if let item = chosen, let owner = item.menu {
            chosen = nil
            owner.performActionForItem(at: owner.index(of: item))
        }
        return true
    }

    @objc(cancelMenu)
    func cancel() {
        guard running, !done else { return }
        done = true
        wake()
    }

    /// Engine work and VoiceOver end the menu between events; the loop waits
    /// for one.
    private func wake() {
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: true)
        }
    }

    private static let ignored: Set<NSEvent.EventType> = [.keyUp, .flagsChanged, .scrollWheel, .magnify, .rotate, .swipe,
                                                          .smartMagnify, .beginGesture, .endGesture, .pressure]

    /// NSMenu's handling: the pointer and keys drive the cards, a press
    /// outside them closes the menu without reaching anything else, and the
    /// window server's and the app's own events pass through.
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

    /// The deepest card under `point` (screen), and the item row there.
    private func hit(_ point: NSPoint) -> (level: Int, row: Int?)? {
        for index in levels.indices.reversed() {
            let (view, window, _) = levels[index]
            let local = view.convert(window.convertPoint(fromScreen: point), from: nil)
            if view.card.contains(local) { return (index, view.row(at: local)) }
        }
        return nil
    }

    /// The row under the pointer takes the highlight and opens its submenu;
    /// another row closes it, after a moment while the pointer heads into
    /// the open submenu, as NSMenu's does. Off every card the deepest card
    /// lets go.
    private func track(_ point: NSPoint) {
        let previous = pointer
        pointer = point
        pendingRow?.invalidate()
        pendingRow = nil
        guard let (level, row) = hit(point) else {
            levels.last?.view.highlighted = nil
            return
        }
        guard let row else { return }
        let item = levels[level].view.items[row]
        let opened = level + 1 < levels.count && levels[level + 1].view.source === item.submenu
        if !opened, level + 1 < levels.count, let previous, heading(from: previous, to: point, into: level + 1) {
            let timer = Timer(timeInterval: PArcContextMenuMetrics.submenuAimDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.highlight(row, in: level) }
            }
            RunLoop.main.add(timer, forMode: .common)
            pendingRow = timer
            return
        }
        highlight(row, in: level)
    }

    private func highlight(_ row: Int, in level: Int) {
        pendingRow = nil
        guard levels.indices.contains(level) else { return }
        let view = levels[level].view
        let item = view.items[row]
        let opened = level + 1 < levels.count && levels[level + 1].view.source === item.submenu
        closeLevels(after: opened ? level + 1 : level)
        view.highlighted = item.isEnabled ? row : nil
        if !opened, item.isEnabled, let submenu = item.submenu { openSubmenu(submenu, from: level, row: row) }
    }

    /// Whether `to` lies in the triangle from `from` to the near corners of
    /// the card at `level`: the pointer is on its way into that card.
    private func heading(from: NSPoint, to: NSPoint, into level: Int) -> Bool {
        let (view, window, right) = levels[level]
        let card = window.convertToScreen(view.convert(view.card, to: nil))
        let top = NSPoint(x: right ? card.minX : card.maxX, y: card.maxY)
        let bottom = NSPoint(x: top.x, y: card.minY)
        func side(_ a: NSPoint, _ b: NSPoint) -> CGFloat { (b.x - a.x) * (to.y - a.y) - (b.y - a.y) * (to.x - a.x) }
        let sides = [side(from, top), side(top, bottom), side(bottom, from)]
        return !(sides.contains { $0 < 0 } && sides.contains { $0 > 0 })
    }

    /// As in NSMenu, the card with the lit row has the keys, even under a
    /// submenu the pointer opened; Right or Return goes into that submenu.
    private func key(_ event: NSEvent) {
        pendingRow?.invalidate()
        pendingRow = nil
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

    /// The next enabled row, wrapping; from none, the first or the last.
    private func move(_ delta: Int, in level: Int) {
        guard levels.indices.contains(level) else { return }
        let view = levels[level].view
        let enabled = view.items.indices.filter { !view.items[$0].isSeparatorItem && view.items[$0].isEnabled }
        guard let first = enabled.first, let last = enabled.last else { return }
        if let current = view.highlighted, let position = enabled.firstIndex(of: current) {
            view.highlighted = enabled[(position + delta + enabled.count) % enabled.count]
        } else {
            view.highlighted = delta > 0 ? first : last
        }
    }

    @discardableResult
    private func choose(level: Int, row: Int) -> Bool {
        guard levels.indices.contains(level) else { return false }
        let item = levels[level].view.items[row]
        guard item.isEnabled, !item.isSeparatorItem, !item.hasSubmenu else { return false }
        chosen = item
        done = true
        return true
    }

    private func openSubmenu(_ submenu: NSMenu, from level: Int, row: Int) {
        let (view, window, right) = levels[level]
        open(submenu, beside: window.convertToScreen(view.convert(view.submenuAnchor(row), to: nil)), right: right)
    }

    /// A card for `menu` beside `row` (screen), in a child window of the card
    /// it hangs from. The cards never become key; this loop reads the keys.
    private func open(_ menu: NSMenu, beside row: NSRect, right: Bool) {
        guard let owner = levels.last?.window ?? parent else { return }
        menu.update()
        menu.delegate?.menuWillOpen?(menu)
        let view = PArcContextMenuView(menu: menu, colors: colors)
        let margin = PArcContextMenuMetrics.shadowMargin
        let placed = PArcContextMenuMetrics.frame(card: view.card.size, beside: row, right: right,
                                                 screen: owner.screen?.visibleFrame)
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

    ///
    private static func pivot(_ view: PArcContextMenuView, right: Bool) -> NSPoint {
        NSPoint(x: right ? view.card.minX : view.card.maxX, y: view.card.maxY)
    }

    /// Submenus close at once, as NSMenu's do.
    private func closeLevels(after level: Int) {
        while levels.count > level + 1, let (view, window, _) = levels.popLast() {
            view.onPress = nil
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
            view.source.delegate?.menuDidClose?(view.source)
        }
    }

    ///
    private func close() {
        pendingRow?.invalidate()
        pendingRow = nil
        pointer = nil
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
