import AppKit

@main struct CommandBarScopeTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); assertions += 1
        }
        let unicode = "🌌 e\u{301} search"
        let original = CommandBarScopeEditing(query: unicode, displayedText: unicode,
            selection: NSRange(location: 3, length: 2))
        check(original.query == unicode, "literal query is retained")
        check(original.selectionForQuery == NSRange(location: 3, length: 2), "native selected combining range survives switch")
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        field.isRichText = false; field.string = original.query
        field.setSelectedRange(original.selectionForQuery)
        field.insertText("night", replacementRange: field.selectedRange())
        check(field.string == "🌌 night search", "switch uses actual UTF-16 selection and subsequent native editing")
        let projected = CommandBarScopeEditing(query: "night", displayedText: "night sky",
            selection: NSRange(location: 5, length: 4))
        check(projected.query == "night", "old engine completion is not a new request")
        check(projected.selection == NSRange(location: 5, length: 4), "cancel retains projected field selection")
        check(projected.selectionForQuery == NSRange(location: 5, length: 0), "new engine restores real query caret")
        let removed = projected.removingScope(prefix: "wiki")
        check(removed.text == "wikinight", "recovered removal adds no separator")
        check(removed.selection == NSRange(location: 4, length: 0), "removal caret is original prefix boundary")
        let spaced = original.removingScope(prefix: "wiki ")
        check(spaced.text == "wiki " + unicode, "literal original whitespace remains literal")
        check(spaced.selection == NSRange(location: 5, length: 0), "existing prefix space is counted")
        let surrogate = projected.removingScope(prefix: "🌌")
        check(surrogate.selection == NSRange(location: 2, length: 0), "AppKit caret does not split a surrogate")
        let missing = projected.removingScope(prefix: nil)
        check(missing.text == "night", "missing prefix retains genuine query")
        check(missing.selection == NSRange(location: 0, length: 5), "recovered missing-prefix edit policy selects all")
        let emptyPrefix = projected.removingScope(prefix: "")
        check(emptyPrefix.selection == NSRange(location: 0, length: 0), "present empty prefix keeps its boundary")
        let empty = CommandBarScopeEditing(query: "", displayedText: "", selection: nil)
        check(empty.removingScope(prefix: nil).selection == NSRange(location: 0, length: 0), "empty query has a valid empty range")
        for invalid in [NSRange(location: NSNotFound, length: 0), NSRange(location: 99, length: 0), NSRange(location: 1, length: Int.max)] {
            let value = CommandBarScopeEditing(query: "abc", displayedText: "abc", selection: invalid)
            check(value.selection == NSRange(location: 3, length: 0), "invalid input selection safely collapses")
        }
        let pill = CommandBarScopePill()
        pill.showSite(name: "Wikipedia", unavailable: false)
        var opened = 0; pill.onOpen = { opened += 1 }
        pill.performClick(nil)
        check(opened == 1, "native button action opens same menu owner")
        check(pill.accessibilityRole() == .button, "pill exposes native button semantics")
        check(pill.accessibilityHelp()?.contains("site search menu") == true, "AX describes actual actions")
        check(pill.accessibilityPerformPress() && opened == 2, "AX press shares the actual menu action")
        pill.isEnabled = false; pill.performClick(nil)
        check(opened == 2, "unavailable pill cannot invoke menu")
        check(!pill.accessibilityPerformPress() && opened == 2, "disabled AX cannot invoke menu")
        pill.isEnabled = true; pill.isHidden = true
        check(!pill.accessibilityPerformPress() && opened == 2, "hidden AX cannot invoke menu")
        check(CommandBarScopeKeyboard.tab(query: "", scope: .ordinary) == .enterActions, "empty ordinary Tab enters Actions")
        check(CommandBarScopeKeyboard.tab(query: "", scope: .actions) == .leaveScope, "empty Actions Tab exits")
        check(CommandBarScopeKeyboard.tab(query: "", scope: .website) == .leaveScope, "empty website Tab uses scope restoration")
        check(CommandBarScopeKeyboard.tab(query: "", scope: .unavailable) == .complete, "lost provider cannot become Actions implicitly")
        for query in [" ", "\n", "space", "wikipedia", "🌌", "e\u{301}"] {
            for scope in [CommandBarScopeKeyboard.Scope.ordinary, .actions, .website, .unavailable] {
                check(CommandBarScopeKeyboard.tab(query: query, scope: scope) == .complete,
                      "nonempty Tab keeps native editing/completion, not a command or scope transition")
            }
        }
        for query in ["github", "git", "github.co", "github.com/etsenake", "www.github.com", " github.com", ""] {
            check(!CommandBarScopeKeyboard.spaceEnters(query: query, keyword: "github.com", enabled: true),
                  "a site name or partial address followed by Space stays an ordinary search")
        }
        for query in ["github.com", "GitHub.com"] {
            check(CommandBarScopeKeyboard.spaceEnters(query: query, keyword: "github.com", enabled: true),
                  "the engine's whole keyword followed by Space enters its scope")
            check(!CommandBarScopeKeyboard.spaceEnters(query: query, keyword: "github.com", enabled: false),
                  "the Profile's Space-trigger preference still turns Space entry off")
        }
        check(!CommandBarScopeKeyboard.spaceEnters(query: "", keyword: "", enabled: true), "an engine without a keyword never enters by Space")
        let reported = CommandBarScopeKeyboard.typedBeforeSpace(previous: "github.com", edited: "github ")
        check(reported == "github", "Space over the inline .com completion follows what was typed")
        check(!CommandBarScopeKeyboard.spaceEnters(query: reported ?? "", keyword: "github.com", enabled: true),
              "github then Space stays an ordinary search instead of entering GitHub's scope")
        check(CommandBarScopeKeyboard.typedBeforeSpace(previous: "github.com/etsenake/parc", edited: "github.com ") == "github.com",
              "Space over an arrowed row's selected path follows the whole keyword")
        check(CommandBarScopeKeyboard.typedBeforeSpace(previous: "github.com", edited: "github.com ") == "github.com", "Space at the caret end")
        for (previous, edited) in [("", "github.com "), ("github.com", "github.com"), ("github.com", " "), ("github.com", "github .com")] {
            check(CommandBarScopeKeyboard.typedBeforeSpace(previous: previous, edited: edited) == nil,
                  "a paste, a non-space edit or a mid-text space is not a typed trailing Space")
        }
        func key(_ type: NSEvent.EventType, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent? {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 49)
        }
        check(CommandBarScopeKeyboard.isTypedSpace(key(.keyDown, " ")), "a Space keystroke can enter a scope")
        check(CommandBarScopeKeyboard.isTypedSpace(key(.keyDown, " ", .shift)), "Shift-Space still types a space")
        check(!CommandBarScopeKeyboard.isTypedSpace(key(.keyDown, "v", .command)), "pasting a space never enters a scope")
        check(!CommandBarScopeKeyboard.isTypedSpace(key(.keyDown, "z", .command)), "undoing back to a trailing space never enters a scope")
        check(!CommandBarScopeKeyboard.isTypedSpace(key(.keyDown, " ", .control)), "Control-Space is not a typed space")
        check(!CommandBarScopeKeyboard.isTypedSpace(key(.keyDown, "\u{A0}", .option)), "Option-Space's no-break space is not a typed space")
        check(!CommandBarScopeKeyboard.isTypedSpace(key(.keyUp, " ")), "a key release is not a typed space")
        check(!CommandBarScopeKeyboard.isTypedSpace(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)), "a menu paste or a drop has no Space keystroke")
        check(!CommandBarScopeKeyboard.isTypedSpace(nil), "an edit without a current event is not a typed space")
        let pending: [(text: String, selection: NSRange, typed: String?)] = [
            ("github.com", NSRange(location: 6, length: 4), "github"),
            ("github.com/etsenake/parc", NSRange(location: 10, length: 14), "github.com"),
            ("github.com", NSRange(location: 10, length: 0), "github.com"),
            ("🌌", NSRange(location: 2, length: 0), "🌌"),
            ("github.com", NSRange(location: 6, length: 0), nil),
            ("github.com", NSRange(location: 0, length: 10), nil),
            ("github.com", NSRange(location: NSNotFound, length: 0), nil),
            ("github.com", NSRange(location: 11, length: 0), nil)]
        for (text, selection, typed) in pending {
            let predicted = CommandBarScopeKeyboard.typedBeforeSpace(text: text, selection: selection)
            check(predicted == typed, "the hint predicts the text a typed Space would follow")
            if let predicted {
                let edited = (text as NSString).replacingCharacters(in: selection, with: " ")
                check(CommandBarScopeKeyboard.typedBeforeSpace(previous: text, edited: edited) == predicted,
                      "the hint and the typed Space read the same text")
            }
        }
        for query in ["man", "Manage Passwords", "password manager", "saved passwords"] {
            check(CommandBarScopeKeyboard.matchesPasswords(query: query), "Actions and ordinary input share the existing password command matching")
        }
        for query in ["", "ma", "password manager extra", "wikipedia"] {
            check(!CommandBarScopeKeyboard.matchesPasswords(query: query), "no unrelated password command alias is invented")
        }
        let actions = CommandBarScopePill()
        var pressed = 0; actions.onOpen = { pressed += 1 }
        check(actions.titleLabel.stringValue == "Actions", "observed command-only scope label")
        check(actions.accessibilityRole() == .staticText, "Actions is a label, not an unavailable site-search menu")
        check(actions.accessibilityHelp()?.contains("Backspace") == true, "scope exit is discoverable to accessibility")
        check(!actions.accessibilityPerformPress() && pressed == 0, "Actions opens no site search menu")
        actions.showExtension(name: "Extension Finder")
        check(actions.titleLabel.stringValue == "Extension Finder", "the actual extension name owns the label")
        check(actions.accessibilityRole() == .staticText, "extension scope is not a saved-site mutation button")
        check(actions.accessibilityValue() as? String == "Extension Finder", "AX carries the exact extension name")
        check(actions.accessibilityHelp()?.contains("this extension") == true, "AX describes event submission, not URL navigation")
        check(!actions.accessibilityPerformPress() && pressed == 0, "extension scope opens no site search menu")
        actions.showSite(name: "Wikipedia", unavailable: false)
        check(actions.accessibilityRole() == .button && actions.accessibilityValue() as? String == "Wikipedia", "a site's pill is its menu button")
        check(actions.accessibilityPerformPress() && pressed == 1, "a site's pill opens the site search menu")
        actions.showSite(name: "Wikipedia", unavailable: true)
        check(actions.accessibilityValue() as? String == "Wikipedia, unavailable", "AX names a lost provider as unavailable")
        actions.showActions()
        check(actions.titleLabel.stringValue == "Actions" && actions.accessibilityValue() as? String == "Actions", "leaving extension restores Actions identity")
        check(actions.accessibilityHelp()?.contains("Search commands") == true, "reused label restores its actual command-only behavior")
        field.string = "space"; field.setSelectedRange(NSRange(location: 0, length: 5))
        field.deleteBackward(nil)
        check(field.string.isEmpty, "selected query deletion remains native text editing")
        check(CommandBarScopeKeyboard.tab(query: field.string, scope: .actions) == .leaveScope,
              "the next empty Tab exits after native selected-text deletion")
        print("\(assertions) command scope/editor/pill assertions passed")
    }
}
