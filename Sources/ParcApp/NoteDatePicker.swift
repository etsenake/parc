import AppKit
import UserNotifications

@MainActor
final class NoteDatePickerView: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 272
    private static let padding: CGFloat = 10
    private static let headerHeight: CGFloat = 34
    private static let rowHeight: CGFloat = 34

    var preferredSizeDidChange: (() -> Void)?
    var onChange: ((NoteDateMention) -> Void)?
    var onRemove: (() -> Void)?
    private(set) var mention: NoteDateMention
    private let parser: NoteDateParser
    private let monthLabel = NSTextField(labelWithString: "")
    private let previous = NoteToolbarButton(icon: .symbol("chevron.left"), label: "Previous month")
    private let next = NoteToolbarButton(icon: .symbol("chevron.right"), label: "Next month")
    private let today = NoteChip("Today", style: .ghost)
    private let grid: NoteCalendarGridView
    private let timeLabel = NSTextField(labelWithString: "Include time")
    private let timeSwitch = NoteToggleSwitch(label: "Include time")
    private let timeField = NSDatePicker()
    private let remindLabel = NSTextField(labelWithString: "Remind me")
    private let remindSwitch = NoteToggleSwitch(label: "Remind me")
    private let hint = NSTextField(labelWithString: "")
    private let remove = NoteChip("Remove", icon: .symbol("trash"), style: .ghost)
    private let separator = NSView()

    init(mention: NoteDateMention, parser: NoteDateParser = NoteDateParser()) {
        self.mention = mention
        self.parser = parser
        grid = NoteCalendarGridView(parser: parser)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 320))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Date picker")
        monthLabel.font = NoteTheme.nunitoExtraBold(14.5)
        monthLabel.textColor = NoteTheme.menuInk
        monthLabel.lineBreakMode = .byTruncatingTail
        for label in [timeLabel, remindLabel] {
            label.font = NoteTheme.menuTitleFont()
            label.textColor = NoteTheme.menuInk
        }
        hint.font = NoteTheme.menuSubtitleFont()
        hint.textColor = NoteTheme.menuTertiaryInk
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        separator.wantsLayer = true
        timeField.datePickerStyle = .textField
        timeField.datePickerElements = .hourMinute
        timeField.isBezeled = false
        timeField.isBordered = false
        timeField.drawsBackground = false
        timeField.font = NoteTheme.nunitoBold(13.5)
        timeField.textColor = NoteTheme.accent
        timeField.calendar = parser.calendar
        timeField.timeZone = parser.calendar.timeZone
        timeField.locale = parser.locale
        timeField.target = self
        timeField.action = #selector(timeChanged)
        timeField.setAccessibilityLabel("Time")
        previous.onPress = { [weak self] in self?.grid.showMonth(offset: -1, animated: true) }
        next.onPress = { [weak self] in self?.grid.showMonth(offset: 1, animated: true) }
        today.onPress = { [weak self] in self?.jumpToToday() }
        today.setToolTip("Jump to today")
        timeSwitch.onToggle = { [weak self] on in self?.setIncludesTime(on) }
        remindSwitch.onToggle = { [weak self] on in self?.setRemind(on) }
        remove.onPress = { [weak self] in self?.onRemove?() }
        grid.onPick = { [weak self] day in self?.pick(day) }
        grid.onMonthChange = { [weak self] in self?.refreshMonth() }
        for view in [monthLabel, previous, next, today, grid, separator, timeLabel, timeField, timeSwitch, remindLabel, remindSwitch, hint, remove] as [NSView] {
            addSubview(view)
        }
        refresh()
        grid.select(mention, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.width, height: naturalHeight) }
    override var fittingSize: NSSize { intrinsicContentSize }

    private var naturalHeight: CGFloat {
        var height = Self.padding + Self.headerHeight + grid.preferredHeight + 9 + Self.rowHeight * 2
        if !hint.stringValue.isEmpty { height += hintHeight + 2 }
        return ceil(height + 4 + NoteTheme.chipHeight + Self.padding)
    }

    private var hintHeight: CGFloat {
        let width = Self.width - Self.padding * 2 - 8
        return ceil(hint.attributedStringValue.boundingRect(with: NSSize(width: width, height: 100), options: [.usesLineFragmentOrigin]).height)
    }

    override func layout() {
        super.layout()
        let inner = bounds.width - Self.padding * 2
        var y = Self.padding
        let buttonSide = NoteTheme.toolbarButtonSize.height
        next.frame = NSRect(x: bounds.width - Self.padding - buttonSide, y: y + (Self.headerHeight - buttonSide) / 2, width: buttonSide, height: buttonSide)
        previous.frame = next.frame.offsetBy(dx: -buttonSide - 2, dy: 0)
        let todayWidth = max(52, today.fittingSize.width)
        today.frame = NSRect(x: previous.frame.minX - todayWidth - 4, y: y + (Self.headerHeight - NoteTheme.chipHeight) / 2,
                             width: todayWidth, height: NoteTheme.chipHeight)
        let labelHeight = ceil(monthLabel.intrinsicContentSize.height)
        monthLabel.frame = NSRect(x: Self.padding + 4, y: y + (Self.headerHeight - labelHeight) / 2, width: today.frame.minX - Self.padding - 8, height: labelHeight)
        y += Self.headerHeight
        grid.frame = NSRect(x: Self.padding, y: y, width: inner, height: grid.preferredHeight)
        y += grid.preferredHeight
        let scale = window?.backingScaleFactor ?? 2
        separator.frame = NSRect(x: Self.padding + 4, y: y + 4, width: inner - 8, height: 1 / scale)
        separator.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self)
        y += 9
        layoutRow(label: timeLabel, toggle: timeSwitch, y: y)
        let fieldWidth: CGFloat = 84
        let fieldHeight = ceil(timeField.intrinsicContentSize.height)
        timeField.frame = NSRect(x: timeSwitch.frame.minX - fieldWidth - 8, y: y + (Self.rowHeight - fieldHeight) / 2, width: fieldWidth, height: fieldHeight)
        y += Self.rowHeight
        layoutRow(label: remindLabel, toggle: remindSwitch, y: y)
        y += Self.rowHeight
        if !hint.stringValue.isEmpty {
            hint.frame = NSRect(x: Self.padding + 4, y: y, width: inner - 8, height: hintHeight)
            y += hintHeight + 2
        }
        let removeWidth = max(80, remove.fittingSize.width)
        remove.frame = NSRect(x: Self.padding, y: y + 4, width: removeWidth, height: NoteTheme.chipHeight)
    }

    private func layoutRow(label: NSTextField, toggle: NoteToggleSwitch, y: CGFloat) {
        let size = NoteToggleSwitch.size
        toggle.frame = NSRect(x: bounds.width - Self.padding - 4 - size.width, y: y + (Self.rowHeight - size.height) / 2, width: size.width, height: size.height)
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: Self.padding + 4, y: y + (Self.rowHeight - height) / 2, width: 130, height: height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags.isEmpty else { return false }
        switch event.keyCode {
        case 123: return move(byDays: -1)
        case 124: return move(byDays: 1)
        case 126: return move(byDays: -7)
        case 125: return move(byDays: 7)
        case 116: grid.showMonth(offset: -1, animated: true); return true
        case 121: grid.showMonth(offset: 1, animated: true); return true
        default: return false
        }
    }

    @discardableResult
    func move(byDays days: Int) -> Bool {
        guard let date = parser.calendar.date(from: DateComponents(year: mention.year, month: mention.month, day: mention.day)),
              let moved = parser.calendar.date(byAdding: .day, value: days, to: date) else { return false }
        pick(parser.calendar.dateComponents([.year, .month, .day], from: moved))
        return true
    }

    private func pick(_ day: DateComponents) {
        guard let year = day.year, let month = day.month, let value = day.day else { return }
        mention.year = year
        mention.month = month
        mention.day = value
        grid.select(mention, animated: true)
        commit()
    }

    private func jumpToToday() {
        pick(parser.calendar.dateComponents([.year, .month, .day], from: parser.now))
    }

    private func setIncludesTime(_ on: Bool) {
        if on {
            let suggested = parser.reminderVersion(of: NoteDateMention(year: mention.year, month: mention.month, day: mention.day))
            mention.hour = suggested.hour ?? 9
            mention.minute = suggested.minute ?? 0
        } else {
            mention.hour = nil
            mention.minute = nil
        }
        commit()
    }

    private func setRemind(_ on: Bool) {
        mention.remind = on
        commit()
    }

    @objc private func timeChanged() {
        let parts = parser.calendar.dateComponents([.hour, .minute], from: timeField.dateValue)
        mention.hour = parts.hour ?? 9
        mention.minute = parts.minute ?? 0
        commit()
    }

    private func commit() {
        refresh()
        onChange?(mention)
    }

    private func refreshMonth() {
        monthLabel.stringValue = NoteDateFormatting.format(grid.monthStart, template: "MMMMy", calendar: parser.calendar, locale: parser.locale)
        monthLabel.setAccessibilityLabel(monthLabel.stringValue)
    }

    private func refresh() {
        let before = intrinsicContentSize
        refreshMonth()
        timeSwitch.isOn = mention.includesTime
        remindSwitch.isOn = mention.remind
        timeField.isHidden = !mention.includesTime
        if let date = parser.calendar.date(from: DateComponents(year: mention.year, month: mention.month, day: mention.day,
                                                                hour: mention.hour ?? 9, minute: mention.minute ?? 0)) {
            timeField.dateValue = date
        }
        hint.stringValue = hintText()
        setAccessibilityValue(NoteDateFormatting.longLabel(mention, calendar: parser.calendar, locale: parser.locale))
        invalidateIntrinsicContentSize()
        needsLayout = true
        if intrinsicContentSize != before { preferredSizeDidChange?() }
    }

    private func hintText() -> String {
        guard mention.remind else { return "" }
        guard let fire = parser.fireDate(for: mention), fire > parser.now else { return "That moment’s passed. Pick a later one for a nudge." }
        var nudge = mention
        nudge.hour = mention.hour ?? 9
        nudge.minute = mention.hour == nil ? 0 : mention.minute
        return "We’ll nudge you \(NoteDateFormatting.label(nudge, now: parser.now, calendar: parser.calendar, locale: parser.locale))."
    }
}

@MainActor
final class NoteCalendarGridView: NSView {
    static let cellHeight: CGFloat = 32
    private static let weekdayHeight: CGFloat = 22
    private static let dotSide: CGFloat = 28

    var onPick: ((DateComponents) -> Void)?
    var onMonthChange: (() -> Void)?
    private(set) var monthStart: Date
    private let parser: NoteDateParser
    private var selected: DateComponents?
    private var hovered: Int?
    private var pressed: Int?
    private let selection = CALayer()
    private let backdrop = NoteCalendarLayerView()
    private let ink = NoteCalendarLayerView()
    private var tracking: NSTrackingArea?
    private var elements: [NoteCalendarDayElement] = []

    init(parser: NoteDateParser) {
        self.parser = parser
        let parts = parser.calendar.dateComponents([.year, .month], from: parser.now)
        monthStart = parser.calendar.date(from: parts) ?? parser.now
        super.init(frame: NSRect(x: 0, y: 0, width: 252, height: Self.weekdayHeight + Self.cellHeight * 6))
        wantsLayer = true
        selection.cornerRadius = Self.dotSide / 2
        selection.cornerCurve = .continuous
        selection.opacity = 0
        backdrop.layer?.addSublayer(selection)
        ink.draws = { [weak self] rect in self?.drawDays(rect) }
        addSubview(backdrop)
        addSubview(ink)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        rebuildAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var preferredHeight: CGFloat { Self.weekdayHeight + Self.cellHeight * 6 }

    private var firstVisibleDay: Date {
        let weekday = parser.calendar.component(.weekday, from: monthStart)
        let lead = (weekday - parser.calendar.firstWeekday + 7) % 7
        return parser.calendar.date(byAdding: .day, value: -lead, to: monthStart) ?? monthStart
    }

    private func day(at index: Int) -> Date {
        parser.calendar.date(byAdding: .day, value: index, to: firstVisibleDay) ?? firstVisibleDay
    }

    private var cellWidth: CGFloat { bounds.width / 7 }

    private func cellFrame(_ index: Int) -> NSRect {
        NSRect(x: CGFloat(index % 7) * cellWidth, y: Self.weekdayHeight + CGFloat(index / 7) * Self.cellHeight, width: cellWidth, height: Self.cellHeight)
    }

    private func dotFrame(_ index: Int) -> NSRect {
        let cell = cellFrame(index)
        return NSRect(x: cell.midX - Self.dotSide / 2, y: cell.midY - Self.dotSide / 2, width: Self.dotSide, height: Self.dotSide)
    }

    private func index(at point: NSPoint) -> Int? {
        guard point.y >= Self.weekdayHeight, bounds.contains(point) else { return nil }
        let column = min(6, max(0, Int(point.x / cellWidth)))
        let row = min(5, max(0, Int((point.y - Self.weekdayHeight) / Self.cellHeight)))
        return row * 7 + column
    }

    private func selectedIndex() -> Int? {
        guard let selected, let date = parser.calendar.date(from: selected) else { return nil }
        let days = parser.calendar.dateComponents([.day], from: firstVisibleDay, to: parser.calendar.startOfDay(for: date)).day ?? -1
        return (0..<42).contains(days) ? days : nil
    }

    func select(_ mention: NoteDateMention, animated: Bool) {
        selected = DateComponents(year: mention.year, month: mention.month, day: mention.day)
        if let date = parser.calendar.date(from: DateComponents(year: mention.year, month: mention.month, day: 1)), date != monthStart {
            setMonth(date, direction: date > monthStart ? 1 : -1, animated: animated)
        }
        placeSelection(animated: animated)
        rebuildAccessibility()
        ink.needsDisplay = true
    }

    func showMonth(offset: Int, animated: Bool) {
        guard let date = parser.calendar.date(byAdding: .month, value: offset, to: monthStart) else { return }
        setMonth(date, direction: offset, animated: animated)
    }

    private func setMonth(_ date: Date, direction: Int, animated: Bool) {
        guard date != monthStart else { return }
        monthStart = date
        hovered = nil
        if animated, let layer = ink.layer {
            let transition = CATransition()
            if NoteAnimation.reduceMotion {
                transition.type = .fade
                transition.duration = NoteAnimation.reducedFadeDuration
            } else {
                transition.type = .push
                transition.subtype = direction > 0 ? .fromRight : .fromLeft
                transition.duration = 0.22
                transition.timingFunction = NoteCurve.hud
            }
            layer.add(transition, forKey: NoteAnimation.keyPrefix + "calendar.month")
        }
        placeSelection(animated: false)
        rebuildAccessibility()
        ink.needsDisplay = true
        onMonthChange?()
    }

    private func placeSelection(animated: Bool) {
        let accent = NoteTheme.resolved(NoteTheme.accent, in: self)
        NoteAnimation.withoutAnimation { selection.backgroundColor = accent }
        guard let index = selectedIndex() else {
            NoteAnimation.withoutAnimation { selection.opacity = 0 }
            return
        }
        let target = dotFrame(index)
        if animated && selection.opacity > 0 {
            NoteAnimation.slideLayer(selection, to: target, spring: .highlight)
        } else {
            NoteAnimation.withoutAnimation { selection.frame = target }
        }
        if selection.opacity == 0 {
            NoteAnimation.withoutAnimation { selection.opacity = 1 }
            if animated { NoteAnimation.pop(selection, from: 0.85, spring: .check) }
        }
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            backdrop.frame = bounds
            ink.frame = bounds
        }
        placeSelection(animated: false)
        rebuildAccessibility()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        placeSelection(animated: false)
        ink.needsDisplay = true
    }

    private func drawDays(_ dirtyRect: NSRect) {
        let symbols = parser.calendar.veryShortStandaloneWeekdaySymbols
        let headerFont = NoteTheme.nunitoBold(11)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        for column in 0..<7 {
            let symbol = symbols[(column + parser.calendar.firstWeekday - 1) % 7]
            let text = NSAttributedString(string: symbol, attributes: [.font: headerFont, .foregroundColor: NoteTheme.menuTertiaryInk, .paragraphStyle: paragraph])
            let height = ceil(headerFont.ascender - headerFont.descender)
            text.draw(with: NSRect(x: CGFloat(column) * cellWidth, y: (Self.weekdayHeight - height) / 2, width: cellWidth, height: height),
                      options: [.usesLineFragmentOrigin])
        }
        let month = parser.calendar.component(.month, from: monthStart)
        let selectedAt = selectedIndex()
        let regular = NoteTheme.nunitoBold(13)
        let strong = NoteTheme.nunitoExtraBold(13)
        for index in 0..<42 {
            let date = day(at: index)
            let inMonth = parser.calendar.component(.month, from: date) == month
            let isToday = parser.calendar.isDate(date, inSameDayAs: parser.now)
            let isSelected = index == selectedAt
            if !isSelected, index == hovered || index == pressed {
                (index == pressed ? NoteTheme.menuPressed : NoteTheme.menuHighlight).setFill()
                NSBezierPath(ovalIn: dotFrame(index)).fill()
            }
            let ink: NSColor
            if isSelected { ink = .white }
            else if isToday { ink = NoteTheme.accent }
            else if inMonth { ink = NoteTheme.menuInk }
            else { ink = NoteTheme.menuTertiaryInk.withAlphaComponent(0.45) }
            let font = isToday || isSelected ? strong : regular
            let text = NSAttributedString(string: "\(parser.calendar.component(.day, from: date))",
                                          attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
            let cell = cellFrame(index)
            let height = ceil(font.ascender - font.descender)
            text.draw(with: NSRect(x: cell.minX, y: (cell.midY - height / 2).rounded(), width: cell.width, height: height), options: [.usesLineFragmentOrigin])
            if isToday && !isSelected {
                NoteTheme.accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: cell.midX - 1.5, y: cell.midY + height / 2 - 1, width: 3, height: 3)).fill()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow) else { return }
        let next = index(at: convert(event.locationInWindow, from: nil))
        guard next != hovered else { return }
        hovered = next
        ink.needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        ink.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = index(at: convert(event.locationInWindow, from: nil))
        ink.needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = index(at: convert(event.locationInWindow, from: nil))
        hovered = inside
        ink.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil; ink.needsDisplay = true }
        guard let pressed, index(at: convert(event.locationInWindow, from: nil)) == pressed else { return }
        choose(pressed)
    }

    fileprivate func choose(_ index: Int) {
        onPick?(parser.calendar.dateComponents([.year, .month, .day], from: day(at: index)))
    }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: Self.weekdayHeight, width: bounds.width, height: Self.cellHeight * 6), cursor: .pointingHand)
    }

    private func rebuildAccessibility() {
        let selectedAt = selectedIndex()
        elements = (0..<42).map { index in
            let element = NoteCalendarDayElement()
            element.grid = self
            element.index = index
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(NoteDateFormatting.format(day(at: index), template: "EEEEMMMMd", calendar: parser.calendar, locale: parser.locale))
            element.setAccessibilitySelected(index == selectedAt)
            element.setAccessibilityParent(self)
            return element
        }
        setAccessibilityChildren(elements)
        setAccessibilityLabel(NoteDateFormatting.format(monthStart, template: "MMMMy", calendar: parser.calendar, locale: parser.locale))
    }

    fileprivate func screenFrame(of index: Int) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(cellFrame(index), to: nil))
    }
}

@MainActor
private final class NoteCalendarLayerView: NSView {
    var draws: ((NSRect) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { draws?(dirtyRect) }
}

@MainActor
private final class NoteCalendarDayElement: NSAccessibilityElement {
    weak var grid: NoteCalendarGridView?
    var index = 0

    override func accessibilityFrame() -> NSRect {
        MainActor.assumeIsolated { grid?.screenFrame(of: index) ?? .zero }
    }

    override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated {
            guard let grid else { return false }
            grid.choose(index)
            return true
        }
    }
}

@MainActor
final class NoteToggleSwitch: NoteControlButton {
    static let size = NSSize(width: 30, height: 18)
    var onToggle: ((Bool) -> Void)?
    var isOn = false { didSet { if isOn != oldValue { refreshKnob(animated: true) } } }
    private let knob = NSView()

    init(label: String) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        cornerRadius = Self.size.height / 2
        knob.wantsLayer = true
        knob.layer?.cornerCurve = .continuous
        knob.layer?.shadowColor = NSColor.black.cgColor
        knob.layer?.shadowOpacity = 0.22
        knob.layer?.shadowRadius = 1.5
        knob.layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        addSubview(knob)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(label)
        onPress = { [weak self] in
            guard let self else { return }
            self.isOn.toggle()
            self.onToggle?(self.isOn)
        }
        refreshKnob(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { Self.size }

    override func fill(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor? { nil }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isOn ? NoteTheme.accent : NoteTheme.fieldFill).setFill()
        track.fill()
        if !isOn {
            NoteTheme.menuHairline.setStroke()
            track.lineWidth = 1 / (window?.backingScaleFactor ?? 2)
            track.stroke()
        }
    }

    override func layout() {
        super.layout()
        refreshKnob(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshKnob(animated: false)
    }

    private func refreshKnob(animated: Bool) {
        let side = bounds.height - 4
        let target = NSRect(x: isOn ? bounds.width - side - 2 : 2, y: 2, width: side, height: side)
        knob.layer?.cornerRadius = side / 2
        knob.layer?.backgroundColor = NoteTheme.resolved(.white, in: self)
        if animated, window != nil || layer?.superlayer != nil {
            NoteAnimation.slide(knob, to: target, spring: .press)
        } else {
            NoteAnimation.withoutAnimation { knob.frame = target }
        }
        setAccessibilityValue(isOn ? 1 : 0)
        needsDisplay = true
    }
}

@MainActor
final class NoteReminderNotifications: NoteReminderScheduling {
    nonisolated static let noteIDKey = "parc.notes.reminder.note"
    nonisolated static let bookmarkKey = "parc.notes.reminder.bookmark"
    nonisolated static let pathKey = "parc.notes.reminder.path"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    func pendingRequests() async -> [NoteReminderRequest] {
        await center.pendingNotificationRequests().compactMap { request in
            guard let noteID = request.content.userInfo[Self.noteIDKey] as? String
                    ?? NoteReminderBook.noteID(fromIdentifier: request.identifier) else { return nil }
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            return NoteReminderRequest(identifier: request.identifier, noteID: noteID, title: request.content.title,
                                       body: request.content.body,
                                       fireDate: trigger.flatMap { Calendar.current.date(from: $0.dateComponents) } ?? .distantPast,
                                       bookmark: request.content.userInfo[Self.bookmarkKey] as? Data,
                                       path: request.content.userInfo[Self.pathKey] as? String)
        }
    }

    func removeRequests(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: NoteReminderRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        var info: [String: Any] = [Self.noteIDKey: request.noteID]
        if let bookmark = request.bookmark { info[Self.bookmarkKey] = bookmark }
        if let path = request.path { info[Self.pathKey] = path }
        content.userInfo = info
        content.threadIdentifier = request.noteID
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: request.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }
}

@MainActor
final class NoteReminderCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared: NoteReminderCenter = {
        let center = NoteReminderCenter()
        Task { @MainActor in center.book.prune() }
        return center
    }()

    var onOpenNote: ((URL) -> Void)? {
        didSet {
            guard let onOpenNote, let pendingOpen else { return }
            self.pendingOpen = nil
            onOpenNote(pendingOpen)
        }
    }
    let book: NoteReminderBook
    private var pendingOpen: URL?
    private var requestedAuthorization = false

    private override init() {
        let center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        book = NoteReminderBook(scheduler: center.map(NoteReminderNotifications.init(center:)), defaults: .standard)
        super.init()
    }

    func reconcile(page: NotePage, document: URL?, title: String, openedAt: Date) {
        if book.reconcile(page: page, document: document, title: title, openedAt: openedAt) { requestAuthorizationIfNeeded() }
    }

    func forget(document: URL) {
        book.forget(document: document)
    }

    func noteMoved(from old: URL, to new: URL) {
        book.noteMoved(from: old, to: new)
    }

    func requestAuthorizationIfNeeded() {
        guard !requestedAuthorization, book.scheduler != nil else { return }
        requestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func open(noteID: String?, bookmark: Data?, path: String?) {
        let location = book.location(noteID: noteID, bookmark: bookmark, path: path)
        book.prune()
        guard let location else { return }
        if let onOpenNote { onOpenNote(location) } else { pendingOpen = location }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        let info = request.content.userInfo
        let noteID = info[NoteReminderNotifications.noteIDKey] as? String ?? NoteReminderBook.noteID(fromIdentifier: request.identifier)
        let bookmark = info[NoteReminderNotifications.bookmarkKey] as? Data
        let path = info[NoteReminderNotifications.pathKey] as? String
        completionHandler()
        guard noteID != nil || bookmark != nil || path != nil else { return }
        Task { @MainActor in NoteReminderCenter.shared.open(noteID: noteID, bookmark: bookmark, path: path) }
    }
}
