import Foundation

@main
struct EaselRichTextInlineTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!

    static func attributes(_ inline: EaselRichText.Inline? = nil) -> EaselRichText.Attributes {
        EaselRichText.Attributes(font: .init(name: "Helvetica", size: 15), ink: "#252525FF", inline: inline)
    }

    static func rich(_ text: String, inlineAt location: Int, _ inline: EaselRichText.Inline) -> EaselRichText {
        let length = (text as NSString).length
        var runs: [EaselRichText.Run] = []
        if location > 0 { runs.append(.init(location: 0, length: location, attributes: attributes())) }
        runs.append(.init(location: location, length: 1, attributes: attributes(inline)))
        if location + 1 < length { runs.append(.init(location: location + 1, length: length - location - 1, attributes: attributes())) }
        return EaselRichText(runs: runs)
    }

    static func valid(_ inline: EaselRichText.Inline) -> Bool { (try? inline.validate()) != nil }

    @MainActor static func main() throws {
        let note = EaselRichText.Inline.note(URL(fileURLWithPath: "/Users/someone/Parc Notes/Roadmap.md"), title: "Roadmap")
        expect(valid(note), "note mentions validate")
        expect(note.noteURL?.lastPathComponent == "Roadmap.md", "note mentions keep their file")
        expect(valid(.init(kind: .note, target: "parc://easel/" + UUID().uuidString, title: "Board")), "Easel targets validate")
        expect(!valid(.init(kind: .note, target: "https://example.com", title: "Web")), "web targets are refused")
        expect(!valid(.init(kind: .note, target: nil, title: "Nowhere")), "a note mention needs a target")
        expect(!valid(.init(kind: .note, target: note.target, title: String(repeating: "x", count: 2_000))), "titles are capped")
        expect(!valid(.init(kind: .note, target: note.target, title: "A", tex: "x")), "fields from other kinds are refused")

        var mention = NoteDateMention(year: 2026, month: 11, day: 24, hour: 8, minute: 40)
        mention.remind = true
        mention.remindBefore = 15
        mention.end = NoteDateEnd(year: 2026, month: 11, day: 24, hour: 9, minute: 30)
        mention.timeZone = "Europe/Paris"
        mention.format = .short
        mention.timeFormat = .twentyFourHour
        let date = EaselRichText.Inline.date(mention)
        expect(valid(date), "dates validate")
        expect(date.dateMention == mention, "dates round-trip to the Notes mention")
        let plain = EaselRichText.Inline.date(NoteDateMention(year: 2026, month: 2, day: 3))
        expect(plain.remind == nil && plain.end == nil && plain.format == nil, "plain dates leave optional fields out")
        expect(plain.dateMention?.remind == false, "plain dates are not reminders")
        var bad = date
        bad.start = .init(year: 2026, month: 2, day: 30)
        expect(!valid(bad), "impossible days are refused")
        bad = date
        bad.timeZone = "Mars/Olympus"
        expect(!valid(bad), "unknown zones are refused")
        bad = date
        bad.remind = nil
        expect(!valid(bad), "a reminder lead needs a reminder")
        bad = date
        bad.format = "weird"
        expect(!valid(bad), "unknown formats are refused")
        bad = plain
        bad.start = .init(year: 2026, month: 2, day: 3, hour: nil, minute: 5)
        expect(!valid(bad), "minutes need an hour")

        expect(valid(.equation("x^2")), "equations validate")
        expect(valid(.equation("")), "empty equations validate")
        expect(!valid(.equation(String(repeating: "x", count: 5_000))), "equations are capped")
        expect(valid(.emoji("party-parrot", image: png)), "custom emoji validate")
        expect(valid(.emoji("blob", image: nil)), "custom emoji without their picture validate")
        expect(!valid(.emoji("Bad Name", image: png)), "emoji names follow the Notes rules")
        expect(!valid(.emoji("blob", image: Data([1, 2, 3]))), "emoji pictures must be PNG")

        let text = "See \u{FFFC} soon"
        let mentioned = rich(text, inlineAt: 4, note)
        try mentioned.validate(text: text)
        expect((try? rich("See x soon", inlineAt: 4, note).validate(text: "See x soon")) == nil, "inline runs sit on U+FFFC")
        var wide = mentioned
        wide.runs[1].length = 2
        wide.runs[2].location = 6
        wide.runs[2].length = 4
        expect((try? wide.validate(text: text)) == nil, "inline runs cover one character")
        var both = mentioned
        both.runs[1].attributes.image = .init(data: png, fileType: "public.png", width: 1, height: 1)
        expect((try? both.validate(text: text)) == nil, "a run is an image or an inline, never both")

        let encoded = try JSONEncoder().encode(mentioned)
        let decoded = try JSONDecoder().decode(EaselRichText.self, from: encoded)
        expect(decoded == mentioned, "inline runs round-trip through JSON")
        let old = EaselRichText(runs: [.init(location: 0, length: 5, attributes: attributes())])
        let oldJSON = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        expect(!oldJSON.contains("inline"), "runs without inlines leave the field out")
        let dateJSON = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        expect(!dateJSON.contains("remind") && !dateJSON.contains("timeZone"), "unused date fields stay out of the file")

        expect(mentioned.inline(at: 4) == note, "the inline is found at its location")
        expect(EaselRichText.readable(text, rich: mentioned) == "See Roadmap soon", "readable text spells out mentions")
        let emojiText = "Hi \u{FFFC}"
        expect(EaselRichText.readable(emojiText, rich: rich(emojiText, inlineAt: 3, .emoji("blob", image: png))) == "Hi :blob:",
               "readable text writes custom emoji as their name")
        let equationText = "\u{FFFC}!"
        expect(EaselRichText.readable(equationText, rich: rich(equationText, inlineAt: 0, .equation("e^x"))) == "e^x!",
               "readable text writes equations as TeX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 2, day: 3, hour: 12))!
        let today = plain.readable(now: noon, calendar: calendar, locale: Locale(identifier: "en_US"))
        expect(today == "@Today", "dates read as Notes words them: \(today)")
        expect(mentioned.dateMentions.isEmpty && rich(text, inlineAt: 4, date).dateMentions == [mention], "dates are collected")

        let item = EaselItem(kind: .sticky, frame: EaselRect(x: 0, y: 0, width: 200, height: 200), text: text, richText: mentioned)
        var document = EaselDocument(id: UUID(), title: "Test", createdAt: noon, modifiedAt: noon)
        document.items = [item]
        let found = EaselFinder.matches(of: "Road", in: document)
        expect(found.count == 1 && found.first?.range == 4..<5, "find reaches into mentions and points at the pill")
        expect(EaselFinder.matches(of: "soon", in: document).first?.range == 6..<10, "find keeps offsets after a mention")
        let replaced = EaselFinder.replace(found, with: "Plan", in: document)
        expect(replaced.count == 0 && replaced.document == document, "replace leaves mentions alone")
        let after = EaselFinder.replace(EaselFinder.matches(of: "soon", in: document), with: "later", in: document)
        expect(after.document.items[0].text == "See \u{FFFC} later" && after.document.items[0].richText?.inline(at: 4) == note,
               "replace around a mention keeps it")

        print("EaselRichTextInlineTests passed \(assertions) assertions")
    }
}
