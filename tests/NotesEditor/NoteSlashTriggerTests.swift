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
        print("NoteSlashTriggerTests passed")
    }
}
