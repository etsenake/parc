import Foundation

@main
struct NoteSlashTriggerTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func trigger(_ old: String, _ new: String, _ caret: Int? = nil) -> (NoteInlineTrigger, Int)? {
        NoteTriggerRule.trigger(from: old, to: new, caret: caret ?? (new as NSString).length).map { ($0.trigger, $0.start) }
    }

    static func main() {
        expect(trigger("", "/").map { $0 == (.slash, 0) } == true, "a slash at the start of a block opens the menu")
        expect(trigger("Hello ", "Hello /").map { $0 == (.slash, 6) } == true, "a slash after a space opens the menu")
        expect(trigger("and", "and/") == nil, "and/or stays plain text")
        expect(trigger("Hello\n", "Hello\n/").map { $0 == (.slash, 6) } == true, "a slash after a line break counts as a fresh start")
        expect(trigger("(", "(/") == nil, "a slash after a bracket isn't a command")
        expect(trigger("ab", "a/b", 2).map { $0 == (.slash, 1) } == nil, "a slash typed mid-word stays text")
        expect(trigger(" b", " /b", 2).map { $0 == (.slash, 1) } == true, "a slash typed before a word but after a space opens")
        expect(trigger("", "x /") == nil, "pasting several characters never opens a menu")
        expect(trigger("Hello /", "Hello /") == nil, "no change, no menu")
        expect(trigger("Hello / ", "Hello /", 7) == nil, "deleting a character never opens a menu")

        expect(trigger("", "@").map { $0 == (.mention, 0) } == true, "@ at the start opens mentions")
        expect(trigger("see ", "see @").map { $0 == (.mention, 4) } == true, "@ after a space opens mentions")
        expect(trigger("(", "(@").map { $0 == (.mention, 1) } == true, "@ after an opening bracket opens mentions")
        expect(trigger("me", "me@") == nil, "email addresses stay text")
        expect(trigger("[", "[[").map { $0 == (.noteLink, 0) } == true, "[[ opens the note link menu")
        expect(trigger("a[", "a[[") == nil, "[[ glued to a word stays text")
        expect(trigger("see [", "see [[").map { $0 == (.noteLink, 4) } == true, "[[ after a space opens the note link menu")

        let insertion = NoteTriggerRule.insertion(from: "Hello", to: "Hel/lo", caret: 4)
        expect(insertion?.range == 3..<4 && insertion?.text == "/", "insertion finds what was typed and where")
        expect(NoteTriggerRule.insertion(from: "abc", to: "xbc", caret: 1) == nil, "a replacement isn't an insertion")
        expect(NoteTriggerRule.insertion(from: "a", to: "a👍", caret: 3)?.text == "👍", "insertions count UTF-16 like NoteText")

        let emoji = NoteTriggerRule.emojiQuery(in: "hi :sm", caret: 6)
        expect(emoji?.start == 3 && emoji?.query == "sm", ":sm suggests emoji")
        expect(NoteTriggerRule.emojiQuery(in: "hi :s", caret: 5) == nil, "one letter isn't enough")
        expect(NoteTriggerRule.emojiQuery(in: "12:30", caret: 5) == nil, "times stay times")
        expect(NoteTriggerRule.emojiQuery(in: "Note:ab", caret: 7) == nil, "a colon glued to a word isn't an emoji")
        expect(NoteTriggerRule.emojiQuery(in: "http://ab", caret: 9) == nil, "URLs stay URLs")
        expect(NoteTriggerRule.emojiQuery(in: ":smile", caret: 6)?.query == "smile", "an emoji at the start of a block works")
        expect(NoteTriggerRule.emojiQuery(in: "hi :sm ile", caret: 10) == nil, "a space ends the emoji query")
        expect(NoteTriggerRule.emojiQuery(in: "hi :sm", caret: 5) == nil, "the caret must sit after two letters")
        expect(NoteTriggerRule.emojiQuery(in: ":+1", caret: 3) == nil, "the query starts with a letter")
        expect(NoteTriggerRule.emojiQuery(in: "(:thumbs_up", caret: 11)?.query == "thumbs_up", "underscores and brackets work")
        let done = NoteTriggerRule.completedShortcode(in: "hi :smile:", caret: 10)
        expect(done?.range == 3..<10 && done?.shortcode == "smile", ":smile: completes")
        expect(NoteTriggerRule.completedShortcode(in: "10:30:", caret: 6) == nil, "clock times never complete")
        expect(NoteTriggerRule.completedShortcode(in: "::", caret: 2) == nil, "empty shortcodes never complete")
        expect(NoteTriggerRule.completedShortcode(in: ":Heart:", caret: 7)?.shortcode == "heart", "shortcodes are case-insensitive")

        var slash = NoteQueryTracker.slash
        expect(slash.update(query: "", hasResults: true) == .open, "an empty query stays open")
        expect(slash.update(query: "h", hasResults: true) == .open, "matches keep it open")
        expect(slash.update(query: "hx", hasResults: false) == .open, "one miss is forgiven")
        expect(slash.update(query: "hxy", hasResults: false) == .open, "two misses are forgiven")
        expect(slash.update(query: "hxyz", hasResults: false) == .close, "three misses close the menu")
        var spaced = NoteQueryTracker.slash
        _ = spaced.update(query: "red", hasResults: true)
        expect(spaced.update(query: "red b", hasResults: true) == .open, "spaces are fine while things match")
        expect(spaced.update(query: "red bx ", hasResults: false) == .close, "a space with no results closes")
        var leading = NoteQueryTracker.slash
        expect(leading.update(query: " ", hasResults: false) == .close, "a slash followed by a space was never a command")
        var mention = NoteQueryTracker.mention
        _ = mention.update(query: "dec", hasResults: true)
        expect(mention.update(query: "dec ", hasResults: false) == .open, "mentions tolerate spaces while you type a date")
        expect(mention.update(query: "dec 3", hasResults: true) == .open, "and reopen the moment it parses")
        expect(mention.update(query: "dec 3 zzzz", hasResults: false) == .close, "but give up after a few misses")
        var newline = NoteQueryTracker.mention
        expect(newline.update(query: "a\n", hasResults: false) == .close, "a line break always closes")

        var at = NoteQueryToken(start: 0, trigger: "@", text: "@", caret: 1)
        let whole = NoteQueryMatch(query: "tomorrow", range: 0..<9)
        expect(at.resolve(in: "@tomorrow", caret: 9) == whole, "the token is everything typed after the trigger")
        expect(at.resolve(in: "@tomorrow", caret: 4) == whole, "walking the caret left still covers the whole token")
        expect(at.resolve(in: "@tomorrow", caret: 1) == whole, "the caret can sit right after the trigger")
        expect(at.resolve(in: "@tomorrow", caret: 0) == nil, "slipping left of the trigger closes the menu")
        var dated = NoteText("@tomorrow")
        if let range = at.resolve(in: dated.string, caret: 4)?.range {
            dated.replace(range, with: .atom(.date(NoteDateMention(year: 2026, month: 11, day: 21))))
        }
        expect(dated.string == NoteAtom.character, "choosing replaces the whole query, so nothing like [Tomorrow]orrow is left behind")

        var slashed = NoteQueryToken(start: 6, trigger: "/", text: "Hello / world", caret: 7)
        expect(slashed.resolve(in: "Hello /hea world", caret: 10) == NoteQueryMatch(query: "hea", range: 6..<10), "words after the token aren't part of it")
        expect(slashed.resolve(in: "Hello /hea world", caret: 8)?.query == "hea", "the query is the whole token wherever the caret is")
        expect(slashed.resolve(in: "Hello /hea world", caret: 11) == nil, "moving past the token's end closes the menu")
        expect(slashed.resolve(in: "Hello /head world", caret: 9)?.query == "head", "typing in the middle grows the token")
        expect(slashed.resolve(in: "Hello /headworld", caret: 11)?.query == "head", "forward-deleting into the next word keeps the token")
        expect(slashed.resolve(in: "Hello /headworld", caret: 11)?.range == 6..<11, "and the token stops at the caret")
        expect(slashed.resolve(in: "Hello head world", caret: 10) == nil, "deleting the trigger closes the menu")
        var broken = NoteQueryToken(start: 0, trigger: "/", text: "/", caret: 1)
        expect(broken.resolve(in: "/he\nad", caret: 3) == nil, "a line break inside the token closes the menu")
        var plus = NoteQueryToken(start: 0, trigger: "", text: "", caret: 0)
        expect(plus.resolve(in: "quo", caret: 1)?.query == "quo", "menus without a trigger track their token too")

        let typed = NoteBlock.paragraph(NoteText("/heading"))
        var heading = NoteQueryToken(start: 0, trigger: "/", text: "/", caret: 1)
        let headingRange = heading.resolve(in: "/heading", caret: 3)?.range ?? 0..<3
        let applied = NoteCatalogApplier.apply(.block(.heading(1)), to: NotePage(blocks: [typed]), at: NotePosition(typed.id, 0),
                                               removing: headingRange)
        let result = applied?.page.blocks.first
        expect(result?.kind == .heading && result?.text.isEmpty == true, "picking a block with the caret mid-query leaves no stray letters")

        var shortcode = NoteQueryToken(start: 3, trigger: ":", text: "hi :sm", caret: 6)
        let smile = shortcode.resolve(in: "hi :smile", caret: 6)
        expect(smile == NoteQueryMatch(query: "smile", range: 3..<9), "emoji tokens cover the whole shortcode")
        expect(NoteTriggerRule.isEmojiQuery("smile") && NoteTriggerRule.isEmojiQuery("thumbs_up"), "shortcodes are emoji queries")
        expect(!NoteTriggerRule.isEmojiQuery("s") && !NoteTriggerRule.isEmojiQuery("+1") && !NoteTriggerRule.isEmojiQuery("sm ile"),
               "short, symbol-led or spaced queries aren't")
        print("NoteSlashTriggerTests passed")
    }
}
