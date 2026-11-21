import Foundation
import Testing
@testable import ParcCore

struct EaselRichTextInlineTests {
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    private static let note = EaselRichText.Inline.note(URL(fileURLWithPath: "/Users/someone/Parc Notes/Roadmap.md"), title: "Roadmap")
    private static let text = "See \u{FFFC} soon"

    private static var mention: NoteDateMention {
        var mention = NoteDateMention(year: 2026, month: 11, day: 24, hour: 8, minute: 40)
        mention.remind = true
        mention.remindBefore = 15
        mention.end = NoteDateEnd(year: 2026, month: 11, day: 24, hour: 9, minute: 30)
        mention.timeZone = "Europe/Paris"
        mention.format = .short
        mention.timeFormat = .twentyFourHour
        return mention
    }

    private static var date: EaselRichText.Inline { .date(mention) }
    private static let plain = EaselRichText.Inline.date(NoteDateMention(year: 2026, month: 2, day: 3))
    private static var mentioned: EaselRichText { rich(text, inlineAt: 4, note) }

    private static func attributes(_ inline: EaselRichText.Inline? = nil) -> EaselRichText.Attributes {
        EaselRichText.Attributes(font: .init(name: "Helvetica", size: 15), ink: "#252525FF", inline: inline)
    }

    private static func rich(_ text: String, inlineAt location: Int, _ inline: EaselRichText.Inline) -> EaselRichText {
        let length = (text as NSString).length
        var runs: [EaselRichText.Run] = []
        if location > 0 { runs.append(.init(location: 0, length: location, attributes: attributes())) }
        runs.append(.init(location: location, length: 1, attributes: attributes(inline)))
        if location + 1 < length { runs.append(.init(location: location + 1, length: length - location - 1, attributes: attributes())) }
        return EaselRichText(runs: runs)
    }

    private static func valid(_ inline: EaselRichText.Inline) -> Bool { (try? inline.validate()) != nil }

    private static var noon: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 2, day: 3, hour: 12))!
    }

    private static var document: EaselDocument {
        let item = EaselItem(kind: .sticky, frame: EaselRect(x: 0, y: 0, width: 200, height: 200), text: text, richText: mentioned)
        var document = EaselDocument(id: UUID(), title: "Test", createdAt: noon, modifiedAt: noon)
        document.items = [item]
        return document
    }

    @Test func noteMentionsValidateAndKeepTheirFile() {
        #expect(Self.valid(Self.note))
        #expect(Self.note.noteURL?.lastPathComponent == "Roadmap.md")
    }

    @Test func easelTargetsValidate() {
        #expect(Self.valid(.init(kind: .note, target: "parc://easel/" + UUID().uuidString, title: "Board")))
    }

    @Test func easelHostsCompareWithoutCase() {
        #expect(Self.valid(.init(kind: .note, target: "parc://EASEL/" + UUID().uuidString.lowercased(), title: "B")))
    }

    @Test(arguments: [
        EaselRichText.Inline(kind: .note, target: "https://example.com", title: "Web"),
        EaselRichText.Inline(kind: .note, target: nil, title: "Nowhere"),
        EaselRichText.Inline(kind: .note, target: note.target, title: String(repeating: "x", count: 2_000)),
        EaselRichText.Inline(kind: .note, target: note.target, title: "A", tex: "x"),
        EaselRichText.Inline(kind: .note, target: "parc://easel/" + UUID().uuidString.lowercased() + "?x=1", title: "B"),
    ])
    func webMissingOverlongMixedOrQueriedNoteTargetsAreRefused(inline: EaselRichText.Inline) {
        #expect(!Self.valid(inline))
    }

    @Test func datesValidateAndRoundTripToTheNotesMention() {
        #expect(Self.valid(Self.date))
        #expect(Self.date.dateMention == Self.mention)
    }

    @Test func plainDatesLeaveOptionalFieldsOutAndAreNotReminders() {
        #expect(Self.plain.remind == nil && Self.plain.end == nil && Self.plain.format == nil)
        #expect(Self.plain.dateMention?.remind == false)
    }

    @Test func impossibleDaysAreRefused() {
        var bad = Self.date
        bad.start = .init(year: 2026, month: 2, day: 30)
        #expect(!Self.valid(bad))
    }

    @Test func unknownZonesAreRefused() {
        var bad = Self.date
        bad.timeZone = "Mars/Olympus"
        #expect(!Self.valid(bad))
    }

    @Test func aReminderLeadNeedsAReminder() {
        var bad = Self.date
        bad.remind = nil
        #expect(!Self.valid(bad))
    }

    @Test func unknownFormatsAreRefused() {
        var bad = Self.date
        bad.format = "weird"
        #expect(!Self.valid(bad))
    }

    @Test func minutesNeedAnHour() {
        var bad = Self.plain
        bad.start = .init(year: 2026, month: 2, day: 3, hour: nil, minute: 5)
        #expect(!Self.valid(bad))
    }

    @Test(arguments: ["x^2", ""])
    func equationsValidate(tex: String) {
        #expect(Self.valid(.equation(tex)))
    }

    @Test func equationsAreCapped() {
        #expect(!Self.valid(.equation(String(repeating: "x", count: 5_000))))
    }

    @Test(arguments: [png, nil])
    func customEmojiValidateWithOrWithoutTheirPicture(image: Data?) {
        #expect(Self.valid(.emoji("blob", image: image)))
    }

    @Test func emojiNamesFollowTheNotesRules() {
        #expect(!Self.valid(.emoji("Bad Name", image: Self.png)))
    }

    @Test func emojiPicturesMustBePNG() {
        #expect(!Self.valid(.emoji("blob", image: Data([1, 2, 3]))))
    }

    @Test func inlineRunsSitOnTheObjectReplacementCharacter() throws {
        try Self.mentioned.validate(text: Self.text)
        #expect((try? Self.rich("See x soon", inlineAt: 4, Self.note).validate(text: "See x soon")) == nil)
    }

    @Test func inlineRunsCoverOneCharacter() {
        var wide = Self.mentioned
        wide.runs[1].length = 2
        wide.runs[2].location = 6
        wide.runs[2].length = 4
        #expect((try? wide.validate(text: Self.text)) == nil)
    }

    @Test func aRunIsAnImageOrAnInlineNeverBoth() {
        var both = Self.mentioned
        both.runs[1].attributes.image = .init(data: Self.png, fileType: "public.png", width: 1, height: 1)
        #expect((try? both.validate(text: Self.text)) == nil)
    }

    @Test func inlineRunsRoundTripThroughJSON() throws {
        let decoded = try JSONDecoder().decode(EaselRichText.self, from: JSONEncoder().encode(Self.mentioned))
        #expect(decoded == Self.mentioned)
    }

    @Test func runsWithoutInlinesLeaveTheFieldOut() throws {
        let old = EaselRichText(runs: [.init(location: 0, length: 5, attributes: Self.attributes())])
        #expect(!String(decoding: try JSONEncoder().encode(old), as: UTF8.self).contains("inline"))
    }

    @Test func unusedDateFieldsStayOutOfTheFile() throws {
        let json = String(decoding: try JSONEncoder().encode(Self.plain), as: UTF8.self)
        #expect(!json.contains("remind") && !json.contains("timeZone"))
    }

    @Test func theInlineIsFoundAtItsLocation() {
        #expect(Self.mentioned.inline(at: 4) == Self.note)
    }

    @Test func readableTextSpellsOutMentions() {
        #expect(EaselRichText.readable(Self.text, rich: Self.mentioned) == "See Roadmap soon")
    }

    @Test func readableTextWritesCustomEmojiAsTheirName() {
        let text = "Hi \u{FFFC}"
        #expect(EaselRichText.readable(text, rich: Self.rich(text, inlineAt: 3, .emoji("blob", image: Self.png))) == "Hi :blob:")
    }

    @Test func readableTextWritesEquationsAsTex() {
        let text = "\u{FFFC}!"
        #expect(EaselRichText.readable(text, rich: Self.rich(text, inlineAt: 0, .equation("e^x"))) == "e^x!")
    }

    @Test func orphanReplacementCharactersNeverLeakIntoWords() {
        let stray = "a\u{FFFC}b \u{FFFC}"
        #expect(EaselRichText.readable(stray, rich: Self.rich(stray, inlineAt: 4, Self.note)) == "ab Roadmap")
    }

    @Test func plainTextDropsReplacementCharactersToo() {
        #expect(EaselRichText.readable("x\u{FFFC}y", rich: nil) == "xy")
    }

    @Test func datesReadAsNotesWordsThem() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(Self.plain.readable(now: Self.noon, calendar: calendar, locale: Locale(identifier: "en_US")) == "@Today")
    }

    @Test func datesAreCollectedFromRichText() {
        #expect(Self.mentioned.dateMentions.isEmpty)
        #expect(Self.rich(Self.text, inlineAt: 4, Self.date).dateMentions == [Self.mention])
    }

    @Test func findReachesIntoMentionsAndPointsAtThePill() {
        let found = EaselFinder.matches(of: "Road", in: Self.document)
        #expect(found.count == 1 && found.first?.range == 4..<5)
    }

    @Test func findKeepsOffsetsAfterAMention() {
        #expect(EaselFinder.matches(of: "soon", in: Self.document).first?.range == 6..<10)
    }

    @Test func replaceLeavesMentionsAlone() {
        let document = Self.document
        let replaced = EaselFinder.replace(EaselFinder.matches(of: "Road", in: document), with: "Plan", in: document)
        #expect(replaced.count == 0 && replaced.document == document)
    }

    @Test func replaceAroundAMentionKeepsIt() {
        let document = Self.document
        let after = EaselFinder.replace(EaselFinder.matches(of: "soon", in: document), with: "later", in: document)
        #expect(after.document.items[0].text == "See \u{FFFC} later")
        #expect(after.document.items[0].richText?.inline(at: 4) == Self.note)
    }

    @Test func easelTextBecomesNotesTextWithTheMentionAsAnAtom() {
        let noteText = EaselRichText.noteText(Self.text, rich: Self.mentioned)
        #expect(noteText.string == Self.text)
        #expect(noteText.marks(at: 4).atom == Self.note.atom)
        #expect(noteText.marks(at: 0).atom == nil)
    }

    private static var board: (EaselDocument, NoteDateMention) {
        var reminder = mention
        reminder.remind = true
        var board = document
        board.items.insert(EaselItem(kind: .text, frame: EaselRect(x: 0, y: 0, width: 100, height: 40), text: text,
                                     richText: rich(text, inlineAt: 4, .date(reminder))), at: 0)
        return (board, reminder)
    }

    @Test func onlyTextWithRemindersReachesTheReminderPage() {
        #expect(Self.board.0.reminderPage.blocks.count == 1)
    }

    @Test func datesAreCollectedFromTheWholeEasel() {
        let (board, reminder) = Self.board
        #expect(board.dateMentions == [reminder])
    }

    @Test func reminderOwnersAreRecognisedFromTheEaselFile() {
        let profile = UUID(), easelID = UUID()
        let file = URL(fileURLWithPath: "/Library/Parc/Profiles/" + profile.uuidString + "/Easels/documents/" + easelID.uuidString.lowercased() + ".json")
        #expect(EaselReminderOwner(file: file) == EaselReminderOwner(file: file))
        #expect(EaselReminderOwner(file: file)?.id == easelID)
        #expect(EaselReminderOwner(file: file)?.profile == profile)
    }

    @Test func notesAreNotEaselOwners() {
        #expect(EaselReminderOwner(file: URL(fileURLWithPath: "/Users/someone/Parc Notes/Roadmap.md")) == nil)
    }

    @Test func inlinePayloadsHaveATotalCapPerText() {
        let heavy = EaselRichText(runs: (0..<80).map { .init(location: $0, length: 1, attributes: Self.attributes(.equation(String(repeating: "x", count: 4_000)))) })
        #expect((try? heavy.validate(text: String(repeating: "\u{FFFC}", count: 80))) == nil)
    }

    @Test func ordinaryInlinePayloadsFit() {
        let light = EaselRichText(runs: (0..<60).map { .init(location: $0, length: 1, attributes: Self.attributes(.equation(String(repeating: "x", count: 4_000)))) })
        #expect((try? light.validate(text: String(repeating: "\u{FFFC}", count: 60))) != nil)
    }
}
