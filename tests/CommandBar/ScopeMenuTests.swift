import AppKit

@main struct CommandBarScopeTests {
    @MainActor static func main() {
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
