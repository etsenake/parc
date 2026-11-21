import AppKit
import UserNotifications

@MainActor
final class NoteDatePickerView: NSView, NoteFloatingPanelContent {
    enum Page: Equatable { case main, format, remind, zone }

    static let width: CGFloat = 300
    private static let padding: CGFloat = 10
    private static let headerHeight: CGFloat = 34
    private static let rowHeight: CGFloat = 30
    private static let pageHeaderHeight: CGFloat = 40
    private static let listHeight: CGFloat = 318

    var preferredSizeDidChange: (() -> Void)?
    var onChange: ((NoteDateMention) -> Void)?
    var onRemove: (() -> Void)?
    var onNeedsTextFocus: (() -> Void)?
    private(set) var mention: NoteDateMention
    private(set) var editingEnd = false
    private(set) var page: Page = .main
    private let parser: NoteDateParser

    private let mainPage = NoteDatePickerPage()
    private let monthLabel = NSTextField(labelWithString: "")
    private let previous = NoteToolbarButton(icon: .symbol("chevron.left"), label: "Previous month")
    private let next = NoteToolbarButton(icon: .symbol("chevron.right"), label: "Next month")
    private let today = NoteChip("Today", style: .ghost)
    private let grid: NoteCalendarGridView
    private let separator = NSView()
    private let startChip = NoteChip("", icon: nil, style: .ghost)
    private let arrow = NSTextField(labelWithString: "\u{2192}")
    private let endChip = NoteChip("", icon: nil, style: .ghost)
    private let endLabel = NSTextField(labelWithString: "End date")
    private let endSwitch = NoteToggleSwitch(label: "End date")
    private let timeLabel = NSTextField(labelWithString: "Include time")
    private let timeSwitch = NoteToggleSwitch(label: "Include time")
    private let timeField = NSDatePicker()
    private let formatRow = NoteDatePickerRow(title: "Format")
    private let zoneRow = NoteDatePickerRow(title: "Time zone")
    private let remindRow = NoteDatePickerRow(title: "Remind")
    private let hint = NSTextField(labelWithString: "")
    private let remove = NoteChip("Remove", icon: .symbol("trash"), style: .ghost)

    private let detailPage = NoteDatePickerPage()
    private let back = NoteToolbarButton(icon: .symbol("chevron.left"), label: "Back")
    private let detailTitle = NSTextField(labelWithString: "")
    private let search = NoteSearchField(placeholder: "Search cities")
    private let list = NoteMenuList()

    init(mention: NoteDateMention, parser: NoteDateParser = NoteDateParser()) {
        self.mention = mention
        self.parser = parser
        grid = NoteCalendarGridView(parser: parser)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 420))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Date picker")
        for label in [monthLabel, detailTitle] {
            label.font = NoteTheme.nunitoExtraBold(14.5)
            label.textColor = NoteTheme.menuInk
            label.lineBreakMode = .byTruncatingTail
        }
        for label in [endLabel, timeLabel] {
            label.font = NoteTheme.menuTitleFont()
            label.textColor = NoteTheme.menuInk
        }
        arrow.font = NoteTheme.menuTitleFont()
        arrow.textColor = NoteTheme.menuTertiaryInk
        arrow.alignment = .center
        arrow.setAccessibilityElement(false)
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
        timeField.target = self
        timeField.action = #selector(timeChanged)
        startChip.onPress = { [weak self] in self?.edit(end: false) }
        endChip.onPress = { [weak self] in self?.edit(end: true) }
        previous.onPress = { [weak self] in self?.grid.showMonth(offset: -1, animated: true) }
        next.onPress = { [weak self] in self?.grid.showMonth(offset: 1, animated: true) }
        today.onPress = { [weak self] in self?.jumpToToday() }
        today.setToolTip("Jump to today")
        endSwitch.onToggle = { [weak self] on in self?.setHasEnd(on) }
        timeSwitch.onToggle = { [weak self] on in self?.setIncludesTime(on) }
        formatRow.onPress = { [weak self] in self?.show(.format) }
        zoneRow.onPress = { [weak self] in self?.show(.zone) }
        remindRow.onPress = { [weak self] in self?.show(.remind) }
        remove.onPress = { [weak self] in self?.onRemove?() }
        grid.onPick = { [weak self] day in self?.pick(day, pointer: true) }
        grid.onMonthChange = { [weak self] in self?.refreshMonth() }
        for view in [monthLabel, previous, next, today, grid, separator, startChip, arrow, endChip, endLabel, endSwitch, timeLabel, timeField,
                     timeSwitch, formatRow, zoneRow, remindRow, hint, remove] as [NSView] {
            mainPage.addSubview(view)
        }
        back.onPress = { [weak self] in self?.show(.main) }
        search.bind(to: list)
        list.fixedWidth = Self.width
        list.maximumHeight = Self.listHeight
        list.onActivate = { [weak self] item in self?.choose(item) }
        list.onCancel = { [weak self] in self?.show(.main) }
        list.onCollapse = { [weak self] in self?.show(.main) }
        list.preferredSizeDidChange = { [weak self] in self?.contentDidResize() }
        for view in [back, detailTitle, search, list] as [NSView] { detailPage.addSubview(view) }
        detailPage.isHidden = true
        addSubview(mainPage)
        addSubview(detailPage)
        refresh()
        grid.select(mention, editingEnd: editingEnd, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.width, height: naturalHeight) }
    override var fittingSize: NSSize { intrinsicContentSize }

    private var hasEnd: Bool { mention.end != nil }

    private var naturalHeight: CGFloat {
        switch page {
        case .main:
            var height = Self.padding + Self.headerHeight + grid.preferredHeight + 9
            height += Self.rowHeight * CGFloat(hasEnd ? 5 : 4)
            if mention.includesTime { height += Self.rowHeight }
            if !hint.stringValue.isEmpty { height += hintHeight + 2 }
            return ceil(height + 6 + NoteTheme.chipHeight + Self.padding)
        case .format, .remind, .zone:
            var height = Self.pageHeaderHeight + list.intrinsicContentSize.height
            if page == .zone { height += NoteTheme.fieldHeight + NoteTheme.menuInset }
            return ceil(height)
        }
    }

    private var hintHeight: CGFloat {
        let width = Self.width - Self.padding * 2 - 8
        return ceil(hint.attributedStringValue.boundingRect(with: NSSize(width: width, height: 100), options: [.usesLineFragmentOrigin]).height)
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            mainPage.frame = bounds
            detailPage.frame = bounds
        }
        if page == .main { layoutMain() } else { layoutDetail() }
    }

    private func layoutMain() {
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
        if hasEnd {
            layoutChips(y: y, inner: inner)
            y += Self.rowHeight
        }
        layoutRow(label: endLabel, toggle: endSwitch, y: y)
        y += Self.rowHeight
        layoutRow(label: timeLabel, toggle: timeSwitch, y: y)
        let fieldWidth: CGFloat = 84
        let fieldHeight = ceil(timeField.intrinsicContentSize.height)
        timeField.frame = NSRect(x: timeSwitch.frame.minX - fieldWidth - 8, y: y + (Self.rowHeight - fieldHeight) / 2, width: fieldWidth, height: fieldHeight)
        y += Self.rowHeight
        for row in [formatRow, zoneRow, remindRow] where !row.isHidden {
            row.frame = NSRect(x: Self.padding, y: y + 1, width: inner, height: Self.rowHeight - 2)
            y += Self.rowHeight
        }
        if !hint.stringValue.isEmpty {
            hint.frame = NSRect(x: Self.padding + 4, y: y + 2, width: inner - 8, height: hintHeight)
            y += hintHeight + 2
        }
        let removeWidth = max(80, remove.fittingSize.width)
        remove.frame = NSRect(x: Self.padding, y: y + 6, width: removeWidth, height: NoteTheme.chipHeight)
    }

    private func layoutChips(y: CGFloat, inner: CGFloat) {
        let arrowWidth: CGFloat = 20
        let half = (inner - arrowWidth) / 2
        let top = y + (Self.rowHeight - NoteTheme.chipHeight) / 2
        startChip.frame = NSRect(x: Self.padding, y: top, width: half, height: NoteTheme.chipHeight)
        let arrowHeight = ceil(arrow.intrinsicContentSize.height)
        arrow.frame = NSRect(x: Self.padding + half, y: y + (Self.rowHeight - arrowHeight) / 2, width: arrowWidth, height: arrowHeight)
        endChip.frame = NSRect(x: Self.padding + half + arrowWidth, y: top, width: half, height: NoteTheme.chipHeight)
    }

    private func layoutRow(label: NSTextField, toggle: NoteToggleSwitch, y: CGFloat) {
        let size = NoteToggleSwitch.size
        toggle.frame = NSRect(x: bounds.width - Self.padding - 4 - size.width, y: y + (Self.rowHeight - size.height) / 2, width: size.width, height: size.height)
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: Self.padding + 4, y: y + (Self.rowHeight - height) / 2, width: 130, height: height)
    }

    private func layoutDetail() {
        let side = NoteTheme.toolbarButtonSize.height
        back.frame = NSRect(x: Self.padding - 2, y: (Self.pageHeaderHeight - side) / 2 + 2, width: side, height: side)
        let labelHeight = ceil(detailTitle.intrinsicContentSize.height)
        detailTitle.frame = NSRect(x: back.frame.maxX + 4, y: (Self.pageHeaderHeight - labelHeight) / 2 + 2,
                                   width: bounds.width - back.frame.maxX - Self.padding - 4, height: labelHeight)
        var y = Self.pageHeaderHeight
        if page == .zone {
            search.frame = NSRect(x: NoteTheme.menuInset, y: y, width: bounds.width - NoteTheme.menuInset * 2, height: NoteTheme.fieldHeight)
            y += NoteTheme.fieldHeight + NoteTheme.menuInset
        }
        list.frame = NSRect(x: 0, y: y - NoteTheme.menuInset, width: bounds.width, height: max(0, bounds.height - y + NoteTheme.menuInset))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if page != .main { return list.handleKeyDown(event) }
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

    func handleCommand(_ selector: Selector) -> Bool {
        guard page != .main else { return false }
        if list.handle(command: selector) { return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSResponder.moveLeft(_:)) {
            show(.main)
            return true
        }
        return selector == #selector(NSResponder.moveRight(_:))
    }

    @discardableResult
    func move(byDays days: Int) -> Bool {
        guard page == .main else { return false }
        let day = editingEnd ? (mention.endDay ?? mention.startDay) : mention.startDay
        guard let date = parser.calendar.date(from: day), let moved = parser.calendar.date(byAdding: .day, value: days, to: date) else { return false }
        pick(parser.calendar.dateComponents([.year, .month, .day], from: moved), pointer: false)
        return true
    }

    private func pick(_ day: DateComponents, pointer: Bool) {
        var value: NoteDateMention
        if hasEnd && editingEnd {
            value = mention.settingEndDay(day)
            if !value.isOrdered(in: parser.calendar) {
                value = pointer ? mention.settingDay(day) : Self.pulled(value)
            } else if pointer {
                editingEnd = false
            }
        } else {
            value = Self.pushed(mention.settingDay(day), calendar: parser.calendar)
            if pointer && hasEnd { editingEnd = true }
        }
        mention = value
        grid.select(mention, editingEnd: editingEnd, animated: true)
        commit()
    }

    private static func pushed(_ mention: NoteDateMention, calendar: Calendar) -> NoteDateMention {
        guard !mention.isOrdered(in: calendar), var end = mention.end else { return mention }
        end.year = mention.year
        end.month = mention.month
        end.day = mention.day
        var value = mention
        value.end = end
        if !value.isOrdered(in: calendar) {
            end.hour = mention.hour
            end.minute = mention.minute
            value.end = end
        }
        return value
    }

    private static func pulled(_ mention: NoteDateMention) -> NoteDateMention {
        guard let end = mention.end else { return mention }
        var value = mention
        value.year = end.year
        value.month = end.month
        value.day = end.day
        if mention.includesTime {
            value.hour = end.hour ?? mention.hour
            value.minute = end.minute ?? mention.minute
        }
        return value
    }

    private func edit(end: Bool) {
        guard hasEnd, editingEnd != end else { return }
        editingEnd = end
        grid.select(mention, editingEnd: editingEnd, animated: true)
        refresh()
    }

    private func jumpToToday() {
        pick(parser.calendar.dateComponents([.year, .month, .day], from: parser.now), pointer: false)
    }

    private func setHasEnd(_ on: Bool) {
        if on {
            var end = NoteDateEnd(year: mention.year, month: mention.month, day: mention.day, hour: mention.hour, minute: mention.minute)
            if let hour = mention.hour, hour < 23 { end.hour = hour + 1 }
            mention.end = end
            editingEnd = true
        } else {
            mention.end = nil
            editingEnd = false
        }
        grid.select(mention, editingEnd: editingEnd, animated: true)
        commit()
    }

    private func setIncludesTime(_ on: Bool) {
        if on {
            let suggested = parser.reminderVersion(of: NoteDateMention(year: mention.year, month: mention.month, day: mention.day))
            mention.hour = suggested.hour ?? NoteDateMention.reminderHour
            mention.minute = suggested.minute ?? 0
            if var end = mention.end {
                end.hour = min(23, (mention.hour ?? NoteDateMention.reminderHour) + 1)
                end.minute = mention.minute
                mention.end = end
                mention = Self.pushed(mention, calendar: parser.calendar)
            }
        } else {
            mention.hour = nil
            mention.minute = nil
            mention.end?.hour = nil
            mention.end?.minute = nil
            mention.timeZone = nil
        }
        if mention.remind {
            let lead = NoteReminderLead.fitting(mention.reminderLead, allDay: !on)
            mention.remindBefore = lead > 0 ? lead : nil
        }
        commit()
    }

    @objc private func timeChanged() {
        let parts = parser.calendar.dateComponents([.hour, .minute], from: timeField.dateValue)
        let hour = parts.hour ?? NoteDateMention.reminderHour, minute = parts.minute ?? 0
        if hasEnd && editingEnd {
            mention.end?.hour = hour
            mention.end?.minute = minute
            if !mention.isOrdered(in: parser.calendar) { mention = Self.pulled(mention) }
        } else {
            mention.hour = hour
            mention.minute = minute
            mention = Self.pushed(mention, calendar: parser.calendar)
        }
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
        endSwitch.isOn = hasEnd
        timeSwitch.isOn = mention.includesTime
        timeField.isHidden = !mention.includesTime
        for chip in [startChip, arrow, endChip] as [NSView] { chip.isHidden = !hasEnd }
        startChip.chipTitle = chipTitle(mention.startDay, hour: mention.hour, minute: mention.minute)
        endChip.chipTitle = mention.end.map { chipTitle(DateComponents(year: $0.year, month: $0.month, day: $0.day), hour: $0.hour, minute: $0.minute) } ?? ""
        startChip.isChecked = hasEnd && !editingEnd
        endChip.isChecked = hasEnd && editingEnd
        startChip.setAccessibilityLabel("Start, " + startChip.chipTitle)
        endChip.setAccessibilityLabel("End, " + endChip.chipTitle)
        let activeHour = editingEnd ? (mention.end?.hour ?? mention.hour) : mention.hour
        let activeMinute = editingEnd ? (mention.end?.minute ?? mention.minute) : mention.minute
        let activeDay = editingEnd ? (mention.endDay ?? mention.startDay) : mention.startDay
        if let date = parser.calendar.date(from: DateComponents(year: activeDay.year, month: activeDay.month, day: activeDay.day,
                                                                hour: activeHour ?? NoteDateMention.reminderHour, minute: activeMinute ?? 0)) {
            timeField.dateValue = date
        }
        timeField.setAccessibilityLabel(hasEnd ? (editingEnd ? "End time" : "Start time") : "Time")
        timeField.locale = mention.timeFormat.map { $0 == .twentyFourHour ? Locale(identifier: "en_GB") : Locale(identifier: "en_US") } ?? parser.locale
        formatRow.value = formatSummary()
        zoneRow.isHidden = !mention.includesTime
        zoneRow.value = mention.timeZone.map { NoteDateText.zoneTitle($0) } ?? "Local time"
        remindRow.value = mention.remind
            ? NoteReminderLead.title(mention.reminderLead, allDay: !mention.includesTime, timeFormat: mention.timeFormat, locale: parser.locale)
            : "None"
        hint.stringValue = parser.reminderHint(for: mention)
        setAccessibilityValue(NoteDateFormatting.longLabel(mention, calendar: parser.calendar, locale: parser.locale))
        if page != .main { list.setItems(items(for: page), keepingHighlight: true) }
        invalidateIntrinsicContentSize()
        needsLayout = true
        if intrinsicContentSize != before { preferredSizeDidChange?() }
    }

    private func chipTitle(_ day: DateComponents, hour: Int?, minute: Int?) -> String {
        guard let date = parser.calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { return "" }
        let sameYear = day.year == parser.calendar.component(.year, from: parser.now)
        var title = NoteDateFormatting.format(date, template: sameYear ? "MMMd" : "yMMMd", calendar: parser.calendar, locale: parser.locale)
        if let hour { title += " " + NoteDateText.timeText(hour: hour, minute: minute ?? 0, format: mention.timeFormat, locale: parser.locale) }
        return title
    }

    private func formatSummary() -> String {
        var summary = Self.formatTitle(mention.format)
        if mention.includesTime, let clock = mention.timeFormat { summary += " \u{00B7} " + Self.clockTitle(clock) }
        return summary
    }

    private static func formatTitle(_ format: NoteDateFormat?) -> String {
        switch format {
        case nil: return "Relative"
        case .full?: return "Full date"
        case .short?: return "Short date"
        case .monthDayYear?: return "Month/Day/Year"
        case .dayMonthYear?: return "Day/Month/Year"
        case .yearMonthDay?: return "Year/Month/Day"
        }
    }

    private static func clockTitle(_ clock: NoteTimeFormat?) -> String {
        switch clock {
        case nil: return "Like my Mac"
        case .twelveHour?: return "12 hour"
        case .twentyFourHour?: return "24 hour"
        }
    }

    private func show(_ next: Page) {
        guard next != page else { return }
        let leavingZone = page == .zone
        let forward = next != .main
        page = next
        if next != .main {
            detailTitle.stringValue = Self.pageTitle(next)
            detailTitle.setAccessibilityLabel(detailTitle.stringValue)
            search.isHidden = next != .zone
            search.text = ""
            list.filterText = ""
            list.rowStyle = .compact
            list.noResultsTitle = next == .zone ? "No zone by that name. Try a city?" : "Nothing here."
            list.setAccessibilityLabel(detailTitle.stringValue)
            list.items = items(for: next)
            list.prepare(origin: .keyboard)
            if let checked = list.items.first(where: \.isChecked) { list.highlight(id: checked.id, animated: false) }
        }
        mainPage.isHidden = next != .main
        detailPage.isHidden = next == .main
        slide(forward: forward)
        invalidateIntrinsicContentSize()
        needsLayout = true
        layoutSubtreeIfNeeded()
        preferredSizeDidChange?()
        if next == .zone {
            search.focus()
        } else if leavingZone {
            onNeedsTextFocus?()
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    private func slide(forward: Bool) {
        guard let layer, window != nil else { return }
        let transition = CATransition()
        if NoteAnimation.reduceMotion {
            transition.type = .fade
            transition.duration = NoteAnimation.reducedFadeDuration
        } else {
            transition.type = .push
            transition.subtype = forward ? .fromRight : .fromLeft
            transition.duration = 0.22
            transition.timingFunction = NoteCurve.hud
        }
        layer.add(transition, forKey: NoteAnimation.keyPrefix + "datepicker.page")
    }

    private func contentDidResize() {
        guard page != .main else { return }
        invalidateIntrinsicContentSize()
        needsLayout = true
        preferredSizeDidChange?()
    }

    private static func pageTitle(_ page: Page) -> String {
        switch page {
        case .main: return "Date"
        case .format: return "Format"
        case .remind: return "Remind"
        case .zone: return "Time zone"
        }
    }

    private func items(for page: Page) -> [NoteMenuList.Item] {
        switch page {
        case .main: return []
        case .format: return formatItems()
        case .remind: return remindItems()
        case .zone: return zoneItems()
        }
    }

    private func formatItems() -> [NoteMenuList.Item] {
        var items: [NoteMenuList.Item] = []
        let formats: [NoteDateFormat?] = [nil] + NoteDateFormat.allCases.map { Optional($0) }
        for format in formats {
            var sample = mention
            sample.end = nil
            sample.hour = nil
            sample.minute = nil
            sample.format = format
            var item = NoteMenuList.Item(id: "format." + (format?.rawValue ?? "relative"), title: Self.formatTitle(format),
                                         subtitle: NoteDateText.label(sample, now: parser.now, calendar: parser.calendar, locale: parser.locale),
                                         section: "Date format")
            item.isChecked = mention.format == format
            items.append(item)
        }
        guard mention.includesTime else { return items }
        let clocks: [NoteTimeFormat?] = [nil, .twelveHour, .twentyFourHour]
        for clock in clocks {
            var item = NoteMenuList.Item(id: "clock." + (clock?.rawValue ?? "system"), title: Self.clockTitle(clock),
                                         subtitle: NoteDateText.timeText(hour: mention.hour ?? NoteDateMention.reminderHour, minute: mention.minute ?? 0,
                                                                         format: clock, locale: parser.locale),
                                         section: "Time format")
            item.isChecked = mention.timeFormat == clock
            items.append(item)
        }
        return items
    }

    private func remindItems() -> [NoteMenuList.Item] {
        var none = NoteMenuList.Item(id: "remind.none", title: "None")
        none.isChecked = !mention.remind
        var items = [none]
        let allDay = !mention.includesTime
        var leads = NoteReminderLead.choices(allDay: allDay)
        if mention.remind, !leads.contains(mention.reminderLead) { leads.append(mention.reminderLead) }
        for lead in leads {
            var item = NoteMenuList.Item(id: "remind.\(lead)",
                                         title: NoteReminderLead.title(lead, allDay: allDay, timeFormat: mention.timeFormat, locale: parser.locale))
            item.isChecked = mention.remind && mention.reminderLead == lead
            var probe = mention
            probe.remind = true
            probe.remindBefore = lead > 0 ? lead : nil
            if let fire = parser.fireDate(for: probe), fire <= parser.now { item.isEnabled = false }
            items.append(item)
        }
        return items
    }

    private func zoneItems() -> [NoteMenuList.Item] {
        let moment = mention.startDate(in: parser.calendar) ?? parser.now
        let local = parser.calendar.timeZone.identifier
        var localItem = NoteMenuList.Item(id: "zone.local", title: "Local time",
                                          subtitle: NoteDateText.zoneTitle(local) + " \u{00B7} " + (NoteDateText.zoneOffset(local, at: moment) ?? ""),
                                          icon: .symbol("location"))
        localItem.isChecked = mention.timeZone == nil
        localItem.keywords = [local, "local", "here"]
        var items = [localItem]
        let zones = TimeZone.knownTimeZoneIdentifiers.compactMap { identifier -> (String, Int)? in
            guard identifier.contains("/"), !identifier.hasPrefix("Etc/"), let zone = TimeZone(identifier: identifier) else { return nil }
            return (identifier, zone.secondsFromGMT(for: moment))
        }.sorted { $0.1 == $1.1 ? NoteDateText.zoneTitle($0.0) < NoteDateText.zoneTitle($1.0) : $0.1 < $1.1 }
        for (identifier, _) in zones {
            let region = identifier.split(separator: "/").first.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? ""
            var item = NoteMenuList.Item(id: "zone." + identifier, title: NoteDateText.zoneTitle(identifier),
                                         subtitle: region + " \u{00B7} " + (NoteDateText.zoneOffset(identifier, at: moment) ?? ""))
            item.isChecked = mention.timeZone == identifier
            var keywords = [identifier.replacingOccurrences(of: "_", with: " ")]
            if let abbreviation = TimeZone(identifier: identifier)?.abbreviation(for: moment) { keywords.append(abbreviation) }
            item.keywords = keywords
            items.append(item)
        }
        return items
    }

    private func choose(_ item: NoteMenuList.Item) {
        let id = item.id
        if id.hasPrefix("format.") {
            let raw = String(id.dropFirst("format.".count))
            mention.format = raw == "relative" ? nil : NoteDateFormat(rawValue: raw)
            commit()
        } else if id.hasPrefix("clock.") {
            let raw = String(id.dropFirst("clock.".count))
            mention.timeFormat = raw == "system" ? nil : NoteTimeFormat(rawValue: raw)
            commit()
        } else if id == "remind.none" {
            mention.remind = false
            mention.remindBefore = nil
            commit()
            show(.main)
        } else if id.hasPrefix("remind."), let lead = Int(id.dropFirst("remind.".count)) {
            mention.remind = true
            mention.remindBefore = lead > 0 ? lead : nil
            commit()
            show(.main)
        } else if id == "zone.local" {
            mention.timeZone = nil
            commit()
            show(.main)
        } else if id.hasPrefix("zone.") {
            mention.timeZone = String(id.dropFirst("zone.".count))
            commit()
            show(.main)
        }
    }
}

@MainActor
private final class NoteDatePickerPage: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class NoteDatePickerRow: NoteControlButton {
    let rowTitle: String
    var value = "" {
        didSet {
            guard value != oldValue else { return }
            setAccessibilityValue(value)
            needsDisplay = true
        }
    }

    init(title: String) {
        rowTitle = title
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        setAccessibilityLabel(title)
        setAccessibilityRole(.popUpButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        let font = NoteTheme.menuTitleFont()
        let height = ceil(font.ascender - font.descender)
        let top = (bounds.midY - height / 2).rounded()
        let title = NSAttributedString(string: rowTitle, attributes: [.font: font, .foregroundColor: NoteTheme.menuInk])
        let titleWidth = ceil(title.size().width)
        title.draw(with: NSRect(x: bounds.minX + 4, y: top, width: titleWidth, height: height), options: [.usesLineFragmentOrigin])
        let chevron = NSRect(x: bounds.maxX - 18, y: bounds.midY - 7, width: 14, height: 14)
        NoteIconRenderer.draw(.symbol("chevron.right"), in: chevron, tint: NoteTheme.menuTertiaryInk, pointSize: 10)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingHead
        let left = bounds.minX + 4 + titleWidth + 12
        NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
            .draw(with: NSRect(x: left, y: top, width: max(0, chevron.minX - 2 - left), height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
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
    private var other: DateComponents?
    private var span: (start: DateComponents, end: DateComponents)?
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
        backdrop.draws = { [weak self] rect in self?.drawRange(rect) }
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

    private func offset(of day: DateComponents?) -> Int? {
        guard let day, let date = parser.calendar.date(from: day) else { return nil }
        return parser.calendar.dateComponents([.day], from: firstVisibleDay, to: parser.calendar.startOfDay(for: date)).day
    }

    private func visibleIndex(of day: DateComponents?) -> Int? {
        guard let days = offset(of: day) else { return nil }
        return (0..<42).contains(days) ? days : nil
    }

    private func selectedIndex() -> Int? { visibleIndex(of: selected) }

    func select(_ mention: NoteDateMention, editingEnd: Bool, animated: Bool) {
        let start = mention.startDay
        let end = mention.endDay
        let active = editingEnd ? (end ?? start) : start
        selected = active
        other = end.map { editingEnd ? start : $0 }
        span = end.map { (start, $0) }
        if let date = parser.calendar.date(from: DateComponents(year: active.year, month: active.month, day: 1)), date != monthStart {
            setMonth(date, direction: date > monthStart ? 1 : -1, animated: animated)
        }
        placeSelection(animated: animated)
        rebuildAccessibility()
        backdrop.needsDisplay = true
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
        if animated {
            for layer in [ink.layer, backdrop.layer].compactMap({ $0 }) {
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
        }
        placeSelection(animated: false)
        rebuildAccessibility()
        backdrop.needsDisplay = true
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
        backdrop.needsDisplay = true
        placeSelection(animated: false)
        rebuildAccessibility()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        placeSelection(animated: false)
        backdrop.needsDisplay = true
        ink.needsDisplay = true
    }

    private func drawRange(_ dirtyRect: NSRect) {
        if let span, let lead = offset(of: span.start), let tail = offset(of: span.end), lead < tail {
            let from = max(0, lead), to = min(41, tail)
            NoteTheme.accent.withAlphaComponent(0.16).setFill()
            var index = from
            while index <= to {
                let rowEnd = min(to, index / 7 * 7 + 6)
                let left = cellFrame(index), right = cellFrame(rowEnd)
                let minX = index == lead ? left.midX : left.minX + 2
                let maxX = rowEnd == tail ? right.midX : right.maxX - 2
                let rect = NSRect(x: minX, y: left.midY - Self.dotSide / 2, width: max(0, maxX - minX), height: Self.dotSide)
                NSBezierPath(roundedRect: rect, xRadius: Self.dotSide / 2, yRadius: Self.dotSide / 2).fill()
                index = rowEnd + 1
            }
        }
        if let index = visibleIndex(of: other) {
            NoteTheme.accent.setFill()
            NSBezierPath(ovalIn: dotFrame(index)).fill()
        }
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
        let otherAt = visibleIndex(of: other)
        let regular = NoteTheme.nunitoBold(13)
        let strong = NoteTheme.nunitoExtraBold(13)
        for index in 0..<42 {
            let date = day(at: index)
            let inMonth = parser.calendar.component(.month, from: date) == month
            let isToday = parser.calendar.isDate(date, inSameDayAs: parser.now)
            let isSelected = index == selectedAt || index == otherAt
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
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func pointerCursor(at point: NSPoint) -> NSCursor {
        NSRect(x: 0, y: Self.weekdayHeight, width: bounds.width, height: Self.cellHeight * 6).contains(point) ? .pointingHand : .arrow
    }

    override func cursorUpdate(with event: NSEvent) {
        if !applyNoteCursor(pointerCursor(at: convert(event.locationInWindow, from: nil)), for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        let owned = applyNoteCursor(pointerCursor(at: convert(event.locationInWindow, from: nil)), for: event)
        let next = owned ? index(at: convert(event.locationInWindow, from: nil)) : nil
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

    private func rebuildAccessibility() {
        let selectedAt = selectedIndex()
        let otherAt = visibleIndex(of: other)
        elements = (0..<42).map { index in
            let element = NoteCalendarDayElement()
            element.grid = self
            element.index = index
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(NoteDateFormatting.format(day(at: index), template: "EEEEMMMMd", calendar: parser.calendar, locale: parser.locale))
            element.setAccessibilitySelected(index == selectedAt || index == otherAt)
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
        content.sound = .default
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func open(noteID: String?, bookmark: Data?, path: String?) {
        let location = book.location(noteID: noteID, bookmark: bookmark, path: path)
        book.prune()
        guard let location else { return }
        if let onOpenNote { onOpenNote(location) } else { pendingOpen = location }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
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
