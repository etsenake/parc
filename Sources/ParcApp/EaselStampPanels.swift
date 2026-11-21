import AppKit

@MainActor
final class EaselStampPanels: EaselStampPanelsPresenting {
    var onPick: ((EaselStampFace) -> Void)?
    var onPickerClose: (() -> Void)?
    var emojiLibrary: NoteEmojiLibrary?
    private var wheel: NotePagePopover?
    private var picker: NotePagePopover?
    private weak var wheelView: EaselStampWheel?

    var isWheelOpen: Bool { wheel?.isOpen == true }
    var isPickerOpen: Bool { picker?.isOpen == true }

    func close(animated: Bool) {
        wheel?.close(animated: animated)
        picker?.close(animated: animated)
    }

    func presentWheel(in host: NSView, at point: NSPoint, below control: NSRect?, recents: [EaselStampFace], current: EaselStampFace) {
        close(animated: false)
        let view = EaselStampWheel(recents: recents, current: current, library: emojiLibrary)
        wheelView = view
        let popover = NotePagePopover(content: view)
        popover.panel.cornerRadius = EaselStampWheel.diameter / 2
        popover.panel.gap = 0
        popover.onKeyDown = { [weak view] event in view?.handleKey(event) ?? false }
        popover.onClose = { [weak self, weak popover] in
            guard let self, self.wheel === popover else { return }
            self.wheel = nil
        }
        view.onPick = { [weak self] face in self?.pick(face) }
        view.onMore = { [weak self, weak host] in
            guard let self, let host else { return }
            self.presentPicker(in: host, at: point)
        }
        wheel = popover
        let radius = EaselStampWheel.diameter / 2, margin = NoteTheme.menuScreenMargin
        let shown = host.visibleRect.intersection(host.bounds)
        let visible = NoteFloatingPanel.topDown(shown.isEmpty ? host.bounds : shown, in: host).insetBy(dx: margin, dy: margin)
        let source: NSPoint
        if let control {
            let frame = NoteFloatingPanel.topDown(control, in: host)
            source = NSPoint(x: frame.midX, y: frame.maxY + NoteTheme.menuGap + radius)
        } else {
            let local = NoteFloatingPanel.topDown(NSRect(origin: point, size: .zero), in: host)
            source = NSPoint(x: local.minX, y: local.minY)
        }
        let x = visible.width >= radius * 2 ? min(max(source.x, visible.minX + radius), visible.maxX - radius) : visible.midX
        let y = visible.height >= radius * 2 ? min(max(source.y, visible.minY + radius), visible.maxY - radius) : visible.midY
        let anchor = NoteFloatingPanel.topDown(NSRect(x: x - 1, y: y - radius, width: 2, height: 0), in: host)
        popover.present(in: host, anchor: anchor, edge: .below, alignment: .center, animated: !NoteAnimation.reduceMotion)
    }

    func presentPicker(in host: NSView, at point: NSPoint) {
        let origin = wheel?.panel.frame
        close(animated: false)
        let view = EaselStampPicker(library: emojiLibrary)
        let popover = NotePagePopover(content: view)
        popover.onClose = { [weak self, weak popover] in
            guard let self, self.picker === popover else { return }
            self.picker = nil
            self.onPickerClose?()
        }
        view.onPick = { [weak self] face in self?.pick(face) }
        view.onCancel = { [weak popover] in popover?.close() }
        picker = popover
        let centre = origin.map { NSPoint(x: $0.midX, y: $0.midY) } ?? point
        popover.present(in: host, anchor: NSRect(x: centre.x - 1, y: centre.y, width: 2, height: 0), edge: .below, alignment: .center,
                        animated: !NoteAnimation.reduceMotion)
        view.focus()
    }

    private func pick(_ face: EaselStampFace) {
        if let popover = wheel, popover.isOpen, let view = wheelView,
           view.tuckAway(picking: face, done: { [weak popover] in popover?.close(animated: true) }) {
            picker?.close(animated: true)
            onPick?(face)
            return
        }
        close(animated: true)
        onPick?(face)
    }
}

@MainActor
final class EaselStampWheel: NSView, NoteFloatingPanelContent {
    enum Slot: Hashable {
        case ring(Int)
        case recent(Int)
        case more
    }

    static let diameter: CGFloat = 236
    static let ringRadius: CGFloat = 82
    static let itemSide: CGFloat = 46
    static let hubRadius: CGFloat = 48

    var preferredSizeDidChange: (() -> Void)?
    var onPick: ((EaselStampFace) -> Void)?
    var onMore: (() -> Void)?
    let recents: [EaselStampFace]
    let current: EaselStampFace
    private let library: NoteEmojiLibrary?
    private var highlighted: Slot? { didSet { if highlighted != oldValue { highlightMoved(from: oldValue); needsDisplay = true } } }
    private var pressed: Slot? { didSet { if pressed != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?
    private var elements: [Slot: EaselStampWheelElement] = [:]
    private var openedAt: CFTimeInterval?
    private var growth: [Slot: (from: CGFloat, to: CGFloat, start: CFTimeInterval)] = [:]
    private var flight: (slot: Slot, target: NSPoint, start: CFTimeInterval, done: () -> Void)?
    private var driver: EaselCanvasFrameDriver?

    init(recents: [EaselStampFace], current: EaselStampFace, library: NoteEmojiLibrary? = nil) {
        self.recents = recents
        self.current = current
        self.library = library
        super.init(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Stamps")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.diameter, height: Self.diameter) }
    override var fittingSize: NSSize { intrinsicContentSize }

    var slots: [Slot] { EaselStamps.ring.indices.map(Slot.ring) + recents.indices.map(Slot.recent) + [.more] }

    func face(for slot: Slot) -> EaselStampFace? {
        switch slot {
        case .ring(let index): return EaselStamps.ring.indices.contains(index) ? .design(EaselStamps.ring[index]) : nil
        case .recent(let index): return recents.indices.contains(index) ? recents[index] : nil
        case .more: return nil
        }
    }

    func title(for slot: Slot) -> String {
        guard let face = face(for: slot) else { return "All emoji and icons" }
        return EaselStampArtwork.title(face)
    }

    func rect(for slot: Slot) -> NSRect {
        let centre = NSPoint(x: bounds.midX, y: bounds.midY)
        func square(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> NSRect {
            NSRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
        }
        switch slot {
        case .ring(let index):
            let offset = EaselStamps.wheelOffset(of: index, radius: Double(Self.ringRadius))
            return square(centre.x + CGFloat(offset.x), centre.y + CGFloat(offset.y), Self.itemSide)
        case .recent(let index):
            let side: CGFloat = 26, spacing: CGFloat = 3
            let total = CGFloat(recents.count) * side + CGFloat(max(0, recents.count - 1)) * spacing
            return square(centre.x - total / 2 + side / 2 + CGFloat(index) * (side + spacing), centre.y - 12, side)
        case .more:
            return recents.isEmpty ? square(centre.x, centre.y, 36) : square(centre.x, centre.y + 17, 24)
        }
    }

    func slot(at point: NSPoint) -> Slot? {
        for slot in recents.indices.map(Slot.recent) + [.more] where rect(for: slot).insetBy(dx: -2, dy: -2).contains(point) { return slot }
        let dx = Double(point.x - bounds.midX), dy = Double(point.y - bounds.midY)
        return EaselStamps.wheelIndex(dx: dx, dy: dy, inner: Double(Self.hubRadius + 2), outer: Double(Self.diameter / 2)).map(Slot.ring)
    }

    func activate(_ slot: Slot) {
        if let face = face(for: slot) { onPick?(face) } else { onMore?() }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if characters == "e" || characters == "+" || characters == "=" { onMore?(); return true }
        if let digit = Int(characters), (1...EaselStamps.ring.count).contains(digit) { activate(.ring(digit - 1)); return true }
        switch event.keyCode {
        case 123, 126: moveHighlight(by: -1); return true
        case 124, 125: moveHighlight(by: 1); return true
        case 36, 76, 49:
            if let highlighted { activate(highlighted) }
            return true
        default: return false
        }
    }

    private func moveHighlight(by step: Int) {
        let all = slots
        let currentIndex = highlighted.flatMap { all.firstIndex(of: $0) }
            ?? all.firstIndex { face(for: $0) == current }.map { $0 - step } ?? (step > 0 ? -1 : 0)
        let next = ((currentIndex + step) % all.count + all.count) % all.count
        highlighted = all[next]
        if let element = element(for: all[next]) {
            NSAccessibility.post(element: element, notification: .focusedUIElementChanged)
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: title(for: all[next]), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { driver?.stop(); driver = nil; openedAt = nil; growth.removeAll(); finishFlight(); return }
        guard !reduceMotion else { return }
        openedAt = CACurrentMediaTime()
        startDriver()
    }

    private func startDriver() {
        if driver == nil { driver = EaselCanvasFrameDriver { [weak self] in self?.frameTick() ?? false } }
        driver?.start(in: self)
    }

    private func frameTick() -> Bool {
        let now = CACurrentMediaTime()
        if let opened = openedAt, now - opened >= EaselStampWheelMotion.duration(count: slots.count) { openedAt = nil }
        for (slot, grow) in growth where now - grow.start >= 0.35 && grow.to == 1 { growth.removeValue(forKey: slot) }
        if let flight, now - flight.start >= EaselStampWheelMotion.tuck { finishFlight() }
        needsDisplay = true
        return openedAt != nil || flight != nil || growth.contains { now - $0.value.start < 0.35 }
    }

    private func finishFlight() {
        guard let done = flight?.done else { return }
        flight = nil
        done()
    }

    private func highlightMoved(from previous: Slot?) {
        guard window != nil, !reduceMotion, flight == nil else { growth.removeAll(); return }
        let now = CACurrentMediaTime()
        if let previous { growth[previous] = (hoverScale(previous, at: now), 1, now) }
        if let highlighted { growth[highlighted] = (hoverScale(highlighted, at: now), CGFloat(EaselStampWheelMotion.hoverScale), now) }
        startDriver()
    }

    private func hoverScale(_ slot: Slot, at now: CFTimeInterval) -> CGFloat {
        if let grow = growth[slot] {
            return grow.from + (grow.to - grow.from) * CGFloat(EaselObjectSpring.highlight.progress(at: now - grow.start))
        }
        return slot == highlighted && !reduceMotion ? CGFloat(EaselStampWheelMotion.hoverScale) : 1
    }

    func tuckAway(picking face: EaselStampFace, done: @escaping () -> Void) -> Bool {
        guard window != nil, !reduceMotion, flight == nil, let slot = slots.first(where: { self.face(for: $0) == face }) else { return false }
        var target = NSPoint(x: bounds.midX, y: bounds.midY)
        if let window {
            let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(pointer) { target = pointer }
        }
        let limit = Self.diameter / 2 - Self.itemSide / 2
        let dx = target.x - bounds.midX, dy = target.y - bounds.midY, distance = hypot(dx, dy)
        if distance > limit { target = NSPoint(x: bounds.midX + dx / distance * limit, y: bounds.midY + dy / distance * limit) }
        flight = (slot, target, CACurrentMediaTime(), done)
        startDriver()
        return true
    }

    private func presentation(for slot: Slot, at now: CFTimeInterval) -> (offset: CGPoint, scale: CGFloat, opacity: CGFloat) {
        let box = rect(for: slot)
        let reach = CGPoint(x: box.midX - bounds.midX, y: box.midY - bounds.midY)
        var face = EaselStampWheelMotion.Face(reach: 1, scale: 1, opacity: 1)
        if let opened = openedAt, let index = slots.firstIndex(of: slot) { face = EaselStampWheelMotion.fan(slot: index, elapsed: now - opened) }
        let grow = hoverScale(slot, at: now)
        if let flight {
            let elapsed = now - flight.start
            if flight.slot == slot {
                let travel = EaselStampWheelMotion.flight(elapsed: elapsed)
                let from = CGPoint(x: reach.x * CGFloat(face.reach), y: reach.y * CGFloat(face.reach))
                let to = CGPoint(x: flight.target.x - bounds.midX, y: flight.target.y - bounds.midY)
                let t = CGFloat(travel.travel)
                return (CGPoint(x: from.x + (to.x - from.x) * t - reach.x, y: from.y + (to.y - from.y) * t - reach.y),
                        CGFloat(travel.scale) * grow, CGFloat(travel.opacity))
            }
            face = EaselStampWheelMotion.tucked(face, elapsed: elapsed)
        }
        return (CGPoint(x: reach.x * (CGFloat(face.reach) - 1), y: reach.y * (CGFloat(face.reach) - 1)), CGFloat(face.scale) * grow, CGFloat(face.opacity))
    }

    override func draw(_ dirtyRect: NSRect) {
        let centre = NSPoint(x: bounds.midX, y: bounds.midY)
        let now = CACurrentMediaTime()
        let hub = NSBezierPath(ovalIn: NSRect(x: centre.x - Self.hubRadius, y: centre.y - Self.hubRadius,
                                              width: Self.hubRadius * 2, height: Self.hubRadius * 2))
        let hubFade = flight.map { 1 - CGFloat(EaselObjectTransition.easeInOut((now - $0.start) / EaselStampWheelMotion.tuck)) } ?? 1
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.setAlpha(hubFade)
        NoteTheme.menuHighlight.setFill()
        hub.fill()
        NoteTheme.menuSeparator.setStroke()
        hub.lineWidth = 1
        hub.stroke()
        context?.restoreGState()
        var flown: Slot?
        for slot in slots {
            if flight?.slot == slot { flown = slot; continue }
            drawSlot(slot, at: now, in: context)
        }
        if let flown { drawSlot(flown, at: now, in: context) }
    }

    private func drawSlot(_ slot: Slot, at now: CFTimeInterval, in context: CGContext?) {
        let shown = presentation(for: slot, at: now)
        guard shown.opacity > 0.001 else { return }
        let box = rect(for: slot)
        context?.saveGState()
        defer { context?.restoreGState() }
        if let context, shown.offset != .zero || shown.scale != 1 || shown.opacity < 1 {
            context.translateBy(x: box.midX + shown.offset.x, y: box.midY + shown.offset.y)
            context.scaleBy(x: shown.scale, y: shown.scale)
            context.translateBy(x: -box.midX, y: -box.midY)
            context.setAlpha(shown.opacity)
        }
        let plate = NSBezierPath(ovalIn: box.insetBy(dx: -1, dy: -1))
        if pressed == slot { NoteTheme.menuPressed.setFill(); plate.fill() }
        else if highlighted == slot { NoteTheme.menuHighlight.setFill(); plate.fill() }
        if let face = face(for: slot) {
            if face == current {
                NoteTheme.accent.setStroke()
                plate.lineWidth = 1.5
                plate.stroke()
            }
            let inset: CGFloat = slot == .more ? 0 : (box.width > 30 ? 6 : 2)
            EaselStampArtwork.draw(face, in: box.insetBy(dx: inset, dy: inset), ink: NoteTheme.menuInk, library: library)
        } else {
            EaselStampArtwork.draw(.icon("plus"), in: box.insetBy(dx: box.width * 0.24, dy: box.width * 0.24), ink: NoteTheme.menuSecondaryInk)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        for slot in slots { addCursorRect(rect(for: slot), cursor: .pointingHand) }
    }

    override func mouseMoved(with event: NSEvent) { highlighted = slot(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { highlighted = nil }
    override func mouseDown(with event: NSEvent) { pressed = slot(at: convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) {
        let over = slot(at: convert(event.locationInWindow, from: nil))
        highlighted = over
        if over != pressed { pressed = nil }
    }
    override func mouseUp(with event: NSEvent) {
        let over = slot(at: convert(event.locationInWindow, from: nil))
        let chosen = pressed
        pressed = nil
        if let chosen, chosen == over { activate(chosen) }
    }

    private func element(for slot: Slot) -> EaselStampWheelElement? {
        if let existing = elements[slot] { return existing }
        let made = EaselStampWheelElement(wheel: self, slot: slot)
        elements[slot] = made
        return made
    }

    override func accessibilityChildren() -> [Any]? { slots.compactMap(element(for:)) }

    func screenRect(for slot: Slot) -> NSRect {
        NSAccessibility.screenRect(fromView: self, rect: rect(for: slot))
    }
}

@MainActor
final class EaselStampWheelElement: NSAccessibilityElement {
    private weak var wheel: EaselStampWheel?
    private let slot: EaselStampWheel.Slot

    init(wheel: EaselStampWheel, slot: EaselStampWheel.Slot) {
        self.wheel = wheel
        self.slot = slot
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(wheel.face(for: slot).map(EaselStampArtwork.accessibilityLabel) ?? wheel.title(for: slot))
        setAccessibilityParent(wheel)
    }

    override func accessibilityFrame() -> NSRect { wheel?.screenRect(for: slot) ?? .zero }

    override func accessibilityPerformPress() -> Bool {
        guard let wheel else { return false }
        wheel.activate(slot)
        return true
    }
}

@MainActor
final class EaselStampPicker: NSView, NoteFloatingPanelContent {
    enum Tab { case emoji, icons }

    static let tabHeight: CGFloat = 44

    var preferredSizeDidChange: (() -> Void)?
    var onPick: ((EaselStampFace) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var tab: Tab = .emoji
    private let emojiTab = NoteToolbarButton(.text("Emoji"), label: "Emoji")
    private let iconsTab = NoteToolbarButton(.text("Icons"), label: "Icons")
    private let separator = NSView()
    private let emoji: NoteEmojiPicker
    private let field = NoteSearchField(placeholder: "Search icons…")
    private let list = NoteMenuList()

    init(library: NoteEmojiLibrary?) {
        emoji = NoteEmojiPicker(showsRandom: true, library: library ?? EaselStampArtwork.customEmojiLibrary)
        super.init(frame: NSRect(x: 0, y: 0, width: NoteEmojiPicker.preferredSize.width,
                                 height: NoteEmojiPicker.preferredSize.height + Self.tabHeight))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Stamp picker")
        emoji.onPick = { [weak self] character in
            guard let face = EaselStampFace(emoji: character) else { NSSound.beep(); return }
            self?.onPick?(face)
        }
        emoji.onCancel = { [weak self] in self?.onCancel?() }
        emojiTab.onPress = { [weak self] in self?.select(.emoji) }
        iconsTab.onPress = { [weak self] in self?.select(.icons) }
        field.textField.setAccessibilityLabel("Search icons")
        field.onChange = { [weak self] text in
            guard let self else { return }
            self.list.filterText = text
            self.list.prepare(origin: .keyboard)
        }
        field.onCommand = { [weak self] selector in self?.list.handle(command: selector) ?? false }
        list.items = EaselStampIcons.sections.flatMap { section in
            section.icons.map { icon -> NoteMenuList.Item in
                var item = NoteMenuList.Item(id: icon.symbol, title: icon.title, icon: .symbol(icon.symbol), section: section.title)
                item.keywords = icon.keywords + [icon.symbol]
                return item
            }
        }
        list.noResultsTitle = "No icons by that name. Try “server” or “person”?"
        list.maximumHeight = NoteEmojiPicker.preferredSize.height - NoteTheme.fieldHeight - NoteTheme.menuInset * 4
        list.onActivate = { [weak self] item in
            guard let face = EaselStampFace(token: "icon:" + item.id) else { return }
            self?.onPick?(face)
        }
        list.onCancel = { [weak self] in self?.onCancel?() }
        separator.wantsLayer = true
        for view in [emojiTab, iconsTab, separator, emoji, field, list] as [NSView] { addSubview(view) }
        select(.emoji)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NoteEmojiPicker.preferredSize.width, height: NoteEmojiPicker.preferredSize.height + Self.tabHeight)
    }
    override var fittingSize: NSSize { intrinsicContentSize }

    func focus() {
        if tab == .emoji { emoji.focusSearch() } else { field.focus() }
    }

    func select(_ next: Tab) {
        tab = next
        emojiTab.isChecked = next == .emoji
        iconsTab.isChecked = next == .icons
        emoji.isHidden = next != .emoji
        field.isHidden = next != .icons
        list.isHidden = next != .icons
        if next == .icons { list.prepare(origin: .keyboard) }
        focus()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let button = NoteTheme.toolbarButtonSize.height
        var x: CGFloat = 8
        for tab in [emojiTab, iconsTab] {
            let width = tab.intrinsicContentSize.width
            tab.frame = NSRect(x: x, y: 8, width: width, height: button)
            x += width + 2
        }
        separator.frame = NSRect(x: 0, y: Self.tabHeight - 1, width: bounds.width, height: 1)
        emoji.frame = NSRect(x: 0, y: Self.tabHeight, width: bounds.width, height: bounds.height - Self.tabHeight)
        let inset = NoteTheme.menuInset
        field.frame = NSRect(x: inset * 2, y: Self.tabHeight + inset * 2, width: max(0, bounds.width - inset * 4), height: NoteTheme.fieldHeight)
        list.frame = NSRect(x: 0, y: field.frame.maxY + inset, width: bounds.width, height: max(0, bounds.height - field.frame.maxY - inset))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private func refreshAppearance() {
        NoteAnimation.withoutAnimation { separator.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self) }
    }
}
