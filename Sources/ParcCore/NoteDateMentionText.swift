import Foundation

extension NoteDateMention {
    package static let reminderHour = 9

    package var startDay: DateComponents { DateComponents(year: year, month: month, day: day) }
    package var endDay: DateComponents? { end.map { DateComponents(year: $0.year, month: $0.month, day: $0.day) } }

    package func zonedCalendar(_ base: Calendar) -> Calendar {
        guard includesTime, let identifier = timeZone, let zone = TimeZone(identifier: identifier) else { return base }
        var value = base
        value.timeZone = zone
        return value
    }

    package func startDate(in base: Calendar) -> Date? {
        zonedCalendar(base).date(from: DateComponents(year: year, month: month, day: day, hour: hour ?? 0,
                                                      minute: hour == nil ? 0 : (minute ?? 0)))
    }

    package func endDate(in base: Calendar) -> Date? {
        guard let end else { return nil }
        return zonedCalendar(base).date(from: DateComponents(year: end.year, month: end.month, day: end.day, hour: end.hour ?? 0,
                                                             minute: end.hour == nil ? 0 : (end.minute ?? 0)))
    }

    package func reminderDate(in base: Calendar) -> Date? {
        let calendar = zonedCalendar(base)
        guard let event = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour ?? Self.reminderHour,
                                                             minute: hour == nil ? 0 : (minute ?? 0))) else { return nil }
        let lead = max(0, remindBefore ?? 0)
        guard lead > 0 else { return event }
        guard let shifted = calendar.date(byAdding: .day, value: -(lead / NoteReminderLead.day), to: event) else { return nil }
        return shifted.addingTimeInterval(-TimeInterval(lead % NoteReminderLead.day) * 60)
    }

    package func isDue(now: Date, calendar: Calendar) -> Bool {
        if remind, let fire = reminderDate(in: calendar), fire <= now { return true }
        guard let start = startDate(in: calendar) else { return false }
        return calendar.startOfDay(for: start) <= calendar.startOfDay(for: now)
    }

    package func settingDay(_ parts: DateComponents) -> NoteDateMention {
        var value = self
        value.year = parts.year ?? year
        value.month = parts.month ?? month
        value.day = parts.day ?? day
        return value
    }

    package func settingEndDay(_ parts: DateComponents) -> NoteDateMention {
        var value = self
        var end = self.end ?? NoteDateEnd(year: year, month: month, day: day, hour: hour, minute: minute)
        end.year = parts.year ?? end.year
        end.month = parts.month ?? end.month
        end.day = parts.day ?? end.day
        value.end = end
        return value
    }

    package func isOrdered(in base: Calendar) -> Bool {
        guard end != nil else { return true }
        guard let start = startDate(in: base), let finish = endDate(in: base) else { return false }
        return start <= finish
    }
}

package enum NoteDateText {
    package static let arrow = " \u{2192} "

    package static func label(_ mention: NoteDateMention, now: Date?, calendar: Calendar = .autoupdatingCurrent,
                      locale: Locale = .autoupdatingCurrent) -> String {
        let zoned = mention.zonedCalendar(calendar)
        let startTime = mention.hour.map { timeText(hour: $0, minute: mention.minute ?? 0, format: mention.timeFormat, locale: locale) }
        var text = dayText(mention.startDay, format: mention.format, now: now, calendar: calendar, zoned: zoned, locale: locale)
        if let startTime { text += " " + startTime }
        if let end = mention.end {
            let endTime = end.hour.map { timeText(hour: $0, minute: end.minute ?? 0, format: mention.timeFormat, locale: locale) }
            let sameDay = end.year == mention.year && end.month == mention.month && end.day == mention.day
            if sameDay, startTime != nil, let endTime {
                text += arrow + endTime
            } else {
                text += arrow + dayText(DateComponents(year: end.year, month: end.month, day: end.day), format: mention.format, now: now,
                                        calendar: calendar, zoned: zoned, locale: locale)
                if let endTime { text += " " + endTime }
            }
        }
        if let zone = zoneName(mention, calendar: calendar, locale: locale) { text += " " + zone }
        return text
    }

    package static func dayDistance(_ day: DateComponents, from now: Date, calendar: Calendar) -> Int? {
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = day.year, let month = day.month, let date = day.day,
              let from = calendar.date(from: DateComponents(year: today.year, month: today.month, day: today.day, hour: 12)),
              let to = calendar.date(from: DateComponents(year: year, month: month, day: date, hour: 12)) else { return nil }
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    package static func relativeWord(_ distance: Int) -> String? {
        switch distance {
        case -1: return "Yesterday"
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return nil
        }
    }

    package static func dayText(_ day: DateComponents, format: NoteDateFormat?, now: Date?, calendar: Calendar, zoned: Calendar,
                        locale: Locale) -> String {
        let year = day.year ?? 0, month = day.month ?? 1, date = day.day ?? 1
        if format == nil, let now, let distance = dayDistance(day, from: now, calendar: calendar), let word = relativeWord(distance) {
            return word
        }
        switch format {
        case .monthDayYear?: return String(format: "%02d/%02d/%04d", month, date, year)
        case .dayMonthYear?: return String(format: "%02d/%02d/%04d", date, month, year)
        case .yearMonthDay?: return String(format: "%04d/%02d/%02d", year, month, date)
        case .short?, .full?, nil:
            guard let value = zoned.date(from: DateComponents(year: year, month: month, day: date, hour: 12)) else {
                return String(format: "%04d-%02d-%02d", year, month, date)
            }
            return formatted(value, template: format == .short ? "yMMMd" : "yMMMMd", calendar: zoned, locale: locale)
        }
    }

    package static func timeText(hour: Int, minute: Int, format: NoteTimeFormat?, locale: Locale) -> String {
        if format == .twentyFourHour { return String(format: "%02d:%02d", hour, minute) }
        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC") ?? .current
        calendar.timeZone = utc
        guard let value = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = utc
        formatter.locale = locale
        if format == .twelveHour {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.setLocalizedDateFormatFromTemplate("jmm")
        }
        return formatter.string(from: value)
    }

    package static func zoneName(_ mention: NoteDateMention, calendar: Calendar, locale: Locale) -> String? {
        guard mention.includesTime, let identifier = mention.timeZone, let zone = TimeZone(identifier: identifier) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateFormat = "zzz"
        return formatter.string(from: mention.startDate(in: calendar) ?? Date())
    }

    package static func zoneTitle(_ identifier: String) -> String {
        let city = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return city.replacingOccurrences(of: "_", with: " ")
    }

    package static func zoneOffset(_ identifier: String, at date: Date = Date()) -> String? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600, minutes = abs(seconds) % 3600 / 60
        return "GMT" + sign + (minutes == 0 ? "\(hours)" : String(format: "%d:%02d", hours, minutes))
    }

    package static func formatted(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    package static func nextChange(of mentions: [NoteDateMention], after now: Date, calendar: Calendar) -> Date? {
        guard !mentions.isEmpty else { return nil }
        var moments: [Date] = []
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) {
            moments.append(midnight)
        }
        for mention in mentions where mention.remind {
            if let fire = mention.reminderDate(in: calendar), fire > now { moments.append(fire) }
        }
        return moments.min()
    }

    package static func suggestionDateHint(_ mention: NoteDateMention, now: Date, calendar: Calendar, locale: Locale) -> String? {
        let ends = [mention.startDay] + (mention.endDay.map { $0 == mention.startDay ? [] : [$0] } ?? [])
        let named = ends.filter { day in dayDistance(day, from: now, calendar: calendar).flatMap(relativeWord) != nil }
        let dates = named.compactMap { calendar.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day, hour: 12)) }
        guard let first = dates.first, let last = dates.last else { return nil }
        let thisYear = calendar.component(.year, from: now)
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateTemplate = dates.allSatisfy { calendar.component(.year, from: $0) == thisYear } ? "MMMd" : "yMMMd"
        return formatter.string(from: first, to: last)
    }
}

package enum NoteReminderLead {
    package static let hour = 60
    package static let day = 1440
    package static let week = 10080
    package static let timed = [0, 5, 10, 15, 30, 60, 120, 1440, 2880]
    package static let allDay = [0, 1440, 2880, 10080]

    package static func choices(allDay: Bool) -> [Int] { allDay ? Self.allDay : timed }

    package static func fitting(_ lead: Int, allDay: Bool) -> Int {
        choices(allDay: allDay).contains(lead) ? lead : 0
    }

    package static func title(_ lead: Int, allDay: Bool, timeFormat: NoteTimeFormat? = nil, locale: Locale = .autoupdatingCurrent) -> String {
        if allDay {
            let ring = NoteDateText.timeText(hour: NoteDateMention.reminderHour, minute: 0, format: timeFormat, locale: locale)
            return (lead == 0 ? "On day of event" : span(lead) + " before") + " (" + ring + ")"
        }
        return lead == 0 ? "At time of event" : span(lead) + " before"
    }

    package static func span(_ minutes: Int) -> String {
        let (value, unit) = parts(minutes)
        let names: [Character: String] = ["w": "week", "d": "day", "h": "hour", "m": "minute"]
        let name = names[unit] ?? "minute"
        return "\(value) " + name + (value == 1 ? "" : "s")
    }

    package static func token(_ minutes: Int) -> String {
        let (value, unit) = parts(minutes)
        return "\(value)" + String(unit)
    }

    package static func lead(fromToken token: String) -> Int? {
        let factors: [Character: Int] = ["m": 1, "h": hour, "d": day, "w": week]
        guard let unit = token.last, let factor = factors[unit] else { return nil }
        let digits = token.dropLast()
        guard (1...6).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(digits) else { return nil }
        return value * factor
    }

    private static func parts(_ minutes: Int) -> (Int, Character) {
        let value = max(0, minutes)
        if value > 0, value % week == 0 { return (value / week, "w") }
        if value > 0, value % day == 0 { return (value / day, "d") }
        if value > 0, value % hour == 0 { return (value / hour, "h") }
        return (value, "m")
    }
}

package enum NoteDateMarkup {
    package static func stamp(year: Int, month: Int, day: Int, hour: Int?, minute: Int?) -> String {
        var value = String(format: "%04d-%02d-%02d", year, month, day)
        if let hour { value += String(format: "T%02d:%02d", hour, minute ?? 0) }
        return value
    }

    package static func start(_ mention: NoteDateMention) -> String {
        stamp(year: mention.year, month: mention.month, day: mention.day, hour: mention.hour, minute: mention.minute)
    }

    package static func end(_ end: NoteDateEnd) -> String {
        stamp(year: end.year, month: end.month, day: end.day, hour: end.hour, minute: end.minute)
    }

    package static func parse(_ value: String) -> NoteDateEnd? {
        let bytes = Array(value.utf8)
        func number(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= bytes.count, bytes[range].allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
            return Int(String(decoding: bytes[range], as: UTF8.self))
        }
        guard bytes.count == 10 || bytes.count == 16, let year = number(0..<4), bytes[4] == 45, let month = number(5..<7),
              bytes[7] == 45, let day = number(8..<10), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var parsed = NoteDateEnd(year: year, month: month, day: day)
        if bytes.count == 16 {
            guard bytes[10] == 84, let hour = number(11..<13), bytes[13] == 58, let minute = number(14..<16), hour < 24, minute < 60 else { return nil }
            parsed.hour = hour
            parsed.minute = minute
        }
        return parsed
    }

    package static func mention(from attributes: [(String, String?)]) -> NoteDateMention? {
        var names = Set<String>()
        var mention: NoteDateMention?
        var end: NoteDateEnd?
        var remind = false
        var lead: Int?
        var zone: String?
        var format: NoteDateFormat?
        var timeFormat: NoteTimeFormat?
        for (name, value) in attributes {
            guard names.insert(name).inserted else { return nil }
            switch name {
            case "datetime":
                guard let value, let day = parse(value) else { return nil }
                mention = NoteDateMention(year: day.year, month: day.month, day: day.day, hour: day.hour, minute: day.minute)
            case "data-end":
                guard let value, let day = parse(value) else { return nil }
                end = day
            case "data-remind":
                remind = true
                if let value {
                    guard let minutes = NoteReminderLead.lead(fromToken: value) else { return nil }
                    lead = minutes > 0 ? minutes : nil
                }
            case "data-timezone":
                guard let value, !value.isEmpty, !value.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
                zone = value
            case "data-format":
                guard let value, let parsed = NoteDateFormat(rawValue: value) else { return nil }
                format = parsed
            case "data-clock":
                guard let value, let parsed = NoteTimeFormat(rawValue: value) else { return nil }
                timeFormat = parsed
            default:
                return nil
            }
        }
        guard var result = mention else { return nil }
        result.end = end
        result.remind = remind
        result.remindBefore = lead
        result.timeZone = zone
        result.format = format
        result.timeFormat = timeFormat
        return result
    }

    package static func markdownTag(_ mention: NoteDateMention, escape: (String) -> String) -> String {
        var tag = "<time datetime=\"" + start(mention) + "\""
        if let end = mention.end { tag += " data-end=\"" + self.end(end) + "\"" }
        if let zone = mention.timeZone { tag += " data-timezone=\"" + escape(zone) + "\"" }
        if mention.remind {
            tag += mention.reminderLead > 0 ? " data-remind=\"" + NoteReminderLead.token(mention.reminderLead) + "\"" : " data-remind"
        }
        if let format = mention.format { tag += " data-format=\"" + format.rawValue + "\"" }
        if let timeFormat = mention.timeFormat { tag += " data-clock=\"" + timeFormat.rawValue + "\"" }
        return tag + ">" + NoteAtom.date(mention).fallbackText + "</time>"
    }
}
