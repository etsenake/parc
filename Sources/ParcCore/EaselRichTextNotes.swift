import Foundation

extension EaselRichText.Inline {
    package static func note(_ url: URL, title: String) -> Self {
        Self(kind: .note, target: url.absoluteString, title: String(title.prefix(256)))
    }

    package static func equation(_ tex: String) -> Self { Self(kind: .equation, tex: tex) }

    package static func emoji(_ name: String, image: Data?) -> Self { Self(kind: .emoji, title: name, image: image) }

    package static func date(_ mention: NoteDateMention) -> Self {
        var value = Self(kind: .date)
        value.start = Moment(year: mention.year, month: mention.month, day: mention.day, hour: mention.hour,
                             minute: mention.hour == nil ? nil : mention.minute ?? 0)
        value.end = mention.end.map { Moment(year: $0.year, month: $0.month, day: $0.day, hour: $0.hour, minute: $0.hour == nil ? nil : $0.minute ?? 0) }
        value.remind = mention.remind ? true : nil
        value.remindBefore = mention.remind ? mention.remindBefore : nil
        value.timeZone = mention.timeZone
        value.format = mention.format?.rawValue
        value.timeFormat = mention.timeFormat?.rawValue
        return value
    }

    package var dateMention: NoteDateMention? {
        guard kind == .date, let start else { return nil }
        var mention = NoteDateMention(year: start.year, month: start.month, day: start.day, hour: start.hour, minute: start.minute)
        mention.remind = remind == true
        mention.remindBefore = remind == true ? remindBefore : nil
        mention.end = end.map { NoteDateEnd(year: $0.year, month: $0.month, day: $0.day, hour: $0.hour, minute: $0.minute) }
        mention.timeZone = timeZone
        mention.format = format.flatMap(NoteDateFormat.init(rawValue:))
        mention.timeFormat = timeFormat.flatMap(NoteTimeFormat.init(rawValue:))
        return mention
    }

    package var noteURL: URL? {
        guard kind == .note, let target, let url = URL(string: target) else { return nil }
        return url
    }

    package var atom: NoteAtom {
        switch kind {
        case .note: return .page(target: target ?? "", title: title ?? "")
        case .equation: return .equation(tex ?? "")
        case .emoji: return .customEmoji(title ?? "")
        case .date: return dateMention.map(NoteAtom.date) ?? .raw("")
        }
    }

    package func readable(now: Date, calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> String {
        switch kind {
        case .note: return (title ?? "").isEmpty ? "Untitled" : title ?? ""
        case .equation: return tex ?? ""
        case .emoji: return NoteCustomEmojiName.reference(title ?? "")
        case .date: return dateMention.map { "@" + NoteDateText.label($0, now: now, calendar: calendar, locale: locale) } ?? ""
        }
    }
}

extension EaselRichText {
    var inlines: [(location: Int, inline: Inline)] {
        runs.compactMap { run in run.attributes.inline.map { (run.location, $0) } }
    }

    package var dateMentions: [NoteDateMention] { inlines.compactMap { $0.inline.dateMention } }

    package func inline(at location: Int) -> Inline? {
        runs.first { $0.location == location && $0.length == 1 }?.attributes.inline
    }

    package static func readable(_ text: String, rich: EaselRichText?, now: Date = Date()) -> String {
        readableMap(text, rich: rich, now: now).text
    }

    static func readableMap(_ text: String, rich: EaselRichText?, now: Date = Date()) -> (text: String, starts: [Int], ends: [Int]) {
        let source = text as NSString
        var atoms: [Int: Attributes] = [:]
        for run in rich?.runs ?? [] where run.attributes.isAtomic && run.length == 1 { atoms[run.location] = run.attributes }
        var result = "", starts: [Int] = [], ends: [Int] = []
        var location = 0
        func append(_ part: String, from origin: Int, to finish: Int) {
            result += part
            for _ in 0..<(part as NSString).length {
                starts.append(origin)
                ends.append(finish)
            }
        }
        while location < source.length {
            let unit = source.character(at: location)
            if unit == 0xFFFC {
                if let inline = atoms[location]?.inline { append(inline.readable(now: now), from: location, to: location + 1) }
                location += 1
                continue
            }
            let piece = location
            var next = location + 1
            while next < source.length, source.character(at: next) != 0xFFFC { next += 1 }
            let part = source.substring(with: NSRange(location: piece, length: next - piece))
            for offset in 0..<(next - piece) {
                starts.append(piece + offset)
                ends.append(piece + offset + 1)
            }
            result += part
            location = next
        }
        return (result, starts, ends)
    }
}

extension EaselRichText {
    package static func noteText(_ text: String, rich: EaselRichText?) -> NoteText {
        let source = text as NSString
        var value = NoteText()
        var location = 0
        for run in rich?.runs ?? [] where run.attributes.isAtomic && run.length == 1 && run.location >= location && run.location < source.length {
            if run.location > location { value.append(NoteText(source.substring(with: NSRange(location: location, length: run.location - location)))) }
            if let inline = run.attributes.inline { value.append(.atom(inline.atom)) }
            location = run.location + 1
        }
        if location < source.length { value.append(NoteText(source.substring(from: location))) }
        return value
    }
}

extension EaselDocument {
    var inlineTexts: [(text: String, rich: EaselRichText)] {
        var result: [(String, EaselRichText)] = []
        for item in EaselPages.pageDocuments(self).flatMap(\.items) {
            if let rich = item.richText, rich.runs.contains(where: { $0.attributes.inline != nil }) { result.append((item.text, rich)) }
            for row in item.table?.cells ?? [] {
                for cell in row {
                    if let rich = cell.richText, rich.runs.contains(where: { $0.attributes.inline != nil }) { result.append((cell.text, rich)) }
                }
            }
        }
        return result
    }

    package var dateMentions: [NoteDateMention] { inlineTexts.flatMap { $0.rich.dateMentions } }

    package var reminderPage: NotePage {
        NotePage(blocks: inlineTexts.filter { $0.rich.dateMentions.contains(where: \.remind) }.map {
            NoteBlock(.paragraph, text: EaselRichText.noteText($0.text, rich: $0.rich))
        })
    }
}

package struct EaselReminderOwner: Equatable {
    package static func destination(of id: UUID, in directories: [URL], exists: (URL) -> Bool) -> URL? {
        let name = id.uuidString.lowercased() + ".json"
        return directories.lazy.map { $0.appendingPathComponent(name) }.first(where: exists)
    }

    package var profile: UUID
    package var id: UUID
    package var file: URL

    package init?(file: URL) {
        let parts = file.standardizedFileURL.pathComponents
        guard parts.count >= 5, file.pathExtension == "json", parts[parts.count - 2] == "documents", parts[parts.count - 3] == "Easels",
              parts[parts.count - 5] == "Profiles", let profile = UUID(uuidString: parts[parts.count - 4]),
              let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return nil }
        self.profile = profile
        self.id = id
        self.file = file
    }
}
