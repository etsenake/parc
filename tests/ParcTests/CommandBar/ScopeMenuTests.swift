import AppKit
import Testing
@testable import ParcCommandBar

struct ScopeMenuTests {
    @Test @MainActor func switchingScopesKeepsTheActualUTF16Selection() {
        let query = "🌌 e\u{301} search"
        let selection = NSRange(location: 3, length: 2)
        let state = CommandBarScopeEditing(query: query, displayedText: query, selection: selection)
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        field.isRichText = false
        field.string = state.query
        field.setSelectedRange(state.selectionForQuery)
        field.insertText("night", replacementRange: field.selectedRange())
        #expect(field.string == "🌌 night search")
    }

    @Test func switchingScopesResumesTheTypedQueryWithoutTheOldCompletion() {
        let state = CommandBarScopeEditing(query: "night", displayedText: "night sky", selection: NSRange(location: 5, length: 4))
        #expect(state.query == "night")
        #expect(state.selectionForQuery == NSRange(location: 5, length: 0))
        #expect(state.selection == NSRange(location: 5, length: 4))
    }

    @Test(arguments: [
        ("wiki", "wikinight", 4, 0), ("wiki ", "wiki night", 5, 0),
        ("🌌", "🌌night", 2, 0), ("", "night", 0, 0), (nil, "night", 0, 5),
    ] as [(String?, String, Int, Int)])
    func removingScopeRestoresItsExactPrefix(prefix: String?, text: String, location: Int, length: Int) {
        let state = CommandBarScopeEditing(query: "night", displayedText: "night sky", selection: NSRange(location: 5, length: 4))
        let removed = state.removingScope(prefix: prefix)
        #expect(removed.text == text)
        #expect(removed.selection == NSRange(location: location, length: length))
    }

    @Test(arguments: [(NSNotFound, 0), (99, 0), (2, Int.max)])
    func anInvalidSelectionFallsBackToTheEnd(location: Int, length: Int) {
        let state = CommandBarScopeEditing(query: "night", displayedText: "night", selection: NSRange(location: location, length: length))
        #expect(state.selectionForQuery == NSRange(location: 5, length: 0))
    }

    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    @MainActor func onlyAnEnabledVisibleSitePillOpensItsMenu(hidden: Bool, disabled: Bool) {
        let pill = CommandBarScopePill()
        pill.showSite(name: "Wikipedia", unavailable: disabled)
        pill.isHidden = hidden
        pill.isEnabled = !disabled
        var presses = 0
        pill.onOpen = { presses += 1 }
        #expect(pill.accessibilityRole() == .button)
        #expect(pill.accessibilityPerformPress() == (!hidden && !disabled))
        #expect(presses == (hidden || disabled ? 0 : 1))
    }

    @Test(arguments: [false, true])
    @MainActor func actionsAndExtensionScopesArePassiveLabels(isExtension: Bool) {
        let pill = CommandBarScopePill()
        if isExtension { pill.showExtension(name: "Extension Finder") }
        let title = isExtension ? "Extension Finder" : "Actions"
        #expect(pill.titleLabel.stringValue == title)
        #expect(pill.accessibilityRole() == .staticText)
        #expect(pill.accessibilityValue() as? String == title)
        #expect(!pill.accessibilityPerformPress())
    }

    @Test @MainActor func aLostProviderIsAnnouncedAsUnavailable() {
        let pill = CommandBarScopePill()
        pill.showSite(name: "Wikipedia", unavailable: true)
        #expect(pill.accessibilityValue() as? String == "Wikipedia, unavailable")
    }

    @Test(arguments: [
        (CommandBarScopeKeyboard.Scope.ordinary, CommandBarScopeKeyboard.TabAction.enterActions),
        (.actions, .leaveScope), (.website, .leaveScope), (.unavailable, .complete),
    ])
    func anEmptyQueryUsesItsCurrentScopesTabAction(scope: CommandBarScopeKeyboard.Scope, action: CommandBarScopeKeyboard.TabAction) {
        #expect(CommandBarScopeKeyboard.tab(query: "", scope: scope) == action)
    }

    @Test(arguments: [" ", "\n", "space", "wikipedia", "🌌", "e\u{301}"])
    func aNonemptyQueryTabCompletesInsteadOfChangingScope(query: String) {
        #expect(CommandBarScopeKeyboard.tab(query: query, scope: .ordinary) == .complete)
        #expect(CommandBarScopeKeyboard.tab(query: query, scope: .website) == .complete)
    }

    @Test(arguments: [
        ("github.com", true, true), ("GitHub.com", true, true), ("github.com", false, false),
        ("github", true, false), ("git", true, false), ("github.co", true, false),
        ("github.com/etsenake", true, false), ("www.github.com", true, false),
        (" github.com", true, false), ("", true, false),
    ])
    func spaceEntersOnlyAnEnabledExactKeyword(query: String, enabled: Bool, enters: Bool) {
        #expect(CommandBarScopeKeyboard.spaceEnters(query: query, keyword: "github.com", enabled: enabled) == enters)
    }

    @Test(arguments: [
        ("github.com", "github ", "github"),
        ("github.com/etsenake/parc", "github.com ", "github.com"),
        ("github.com", "github.com ", "github.com"),
        ("", "github.com ", nil), ("github.com", "github.com", nil), ("github.com", " ", nil),
    ] as [(String, String, String?)])
    func aSpaceAfterCompletionUsesTheWordsActuallyTyped(previous: String, edited: String, expected: String?) {
        #expect(CommandBarScopeKeyboard.typedBeforeSpace(previous: previous, edited: edited) == expected)
    }

    @Test(arguments: [("man", true), ("Manage Passwords", true), ("password manager", true), ("saved passwords", true),
                      ("", false), ("ma", false), ("password manager extra", false), ("wikipedia", false)])
    func passwordTriggersMatchOnlyTheIntendedWords(query: String, matches: Bool) {
        #expect(CommandBarScopeKeyboard.matchesPasswords(query: query) == matches)
    }
}

extension ScopeMenuTests {
    @Test(arguments: [
        (NSEvent.EventType.keyDown, " ", NSEvent.ModifierFlags(), true),
        (.keyDown, " ", NSEvent.ModifierFlags.shift, true),
        (.keyDown, "v", NSEvent.ModifierFlags.command, false),
        (.keyDown, "z", NSEvent.ModifierFlags.command, false),
        (.keyDown, " ", NSEvent.ModifierFlags.control, false),
        (.keyDown, "\u{a0}", NSEvent.ModifierFlags.option, false),
        (.keyUp, " ", NSEvent.ModifierFlags(), false),
    ])
    @MainActor func theScopeTriggerRequiresATypedSpace(type: NSEvent.EventType, text: String,
                                                       flags: NSEvent.ModifierFlags, expected: Bool) {
        let event = CommandBarTestSupport.keyEvent(49, flags, characters: text, type: type)
        #expect(CommandBarScopeKeyboard.isTypedSpace(event) == expected)
    }

    @Test @MainActor func changingTheScopeRestoresItsOwnAccessibilityHelp() {
        let pill = CommandBarScopePill()
        pill.showExtension(name: "Extension Finder")
        #expect(pill.accessibilityHelp()?.contains("this extension") == true)
        pill.showActions()
        #expect(pill.accessibilityHelp()?.contains("Search commands") == true)
    }

    @Test @MainActor func deletingTheQueryInActionsUsesNativeEditing() {
        let editor = NSTextView(frame: .zero)
        editor.string = "query"
        editor.setSelectedRange(NSRange(location: 0, length: 5))
        editor.deleteBackward(nil)
        #expect(editor.string.isEmpty)
        #expect(CommandBarScopeKeyboard.tab(query: editor.string, scope: .actions) == .leaveScope)
    }
}

extension ScopeMenuTests {
    @Test(arguments: [false, true])
    @MainActor func pointerAndAccessibilityPressesBothOpenTheOriginalSiteMenu(accessibility: Bool) {
        let pill = CommandBarScopePill()
        pill.showSite(name: "Wikipedia", unavailable: false)
        var presses = 0
        pill.onOpen = { presses += 1 }
        if accessibility { #expect(pill.accessibilityPerformPress()) }
        else { pill.sendClick() }
        #expect(presses == 1)
        #expect(pill.accessibilityHelp()?.contains("site search menu") == true)
    }

    @Test func aMissingEventIsNotAnExplicitSpaceKeystroke() {
        #expect(!CommandBarScopeKeyboard.isTypedSpace(nil))
    }
}
