import AppKit

@main @MainActor struct FieldAnchorTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        let address = "fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&login_hint=josh.etsenake%40fullscript.com&session_hint=AUTHENTICATED"
        var state = CommandBarEditState(query: "")
        state.userEdit("fullscript.okta", selection: NSRange(location: 15, length: 0), hasMarkedText: false, didBackspace: false)
        expect(state.projectInline(resultID: "history", text: address, selection: NSRange(location: 15, length: 0), hasMarkedText: false),
               "the reported address completes inline")
        let completion = CommandBarFieldAnchor.completion(state)
        expect(completion == NSRange(location: 15, length: (address as NSString).length - 15), "the filled-in tail is the completion")
        let anchored = CommandBarFieldAnchor.visibleRange(text: address, displayed: state.displayedText, selection: state.selection,
                                                          completion: completion, hasMarkedText: false)
        expect(anchored == NSRange(location: 15, length: CommandBarFieldAnchor.leadCharacters),
               "the field keeps the typed/filled boundary in view, plus a short lead of the completion")
        expect(CommandBarFieldAnchor.visibleRange(text: address, displayed: state.displayedText, selection: NSRange(location: 40, length: 0),
                                                  completion: completion, hasMarkedText: false) == nil,
               "a caret the user moved is left to the native editor")
        expect(CommandBarFieldAnchor.visibleRange(text: address, displayed: state.displayedText, selection: NSRange(location: 15, length: 30),
                                                  completion: completion, hasMarkedText: false) == nil,
               "a selection the user changed is left alone")
        expect(CommandBarFieldAnchor.visibleRange(text: address, displayed: state.displayedText, selection: state.selection,
                                                  completion: completion, hasMarkedText: true) == nil,
               "marked text is never scrolled by the anchor")
        expect(CommandBarFieldAnchor.visibleRange(text: "fullscript.okta.x", displayed: state.displayedText, selection: state.selection,
                                                  completion: completion, hasMarkedText: false) == nil,
               "an editor whose text has moved on is not anchored to stale state")
        var accepted = state
        accepted.accept()
        expect(CommandBarFieldAnchor.completion(accepted) == nil, "an accepted completion is typed text with an ordinary caret")
        var short = CommandBarEditState(query: "")
        short.userEdit("git", selection: NSRange(location: 3, length: 0), hasMarkedText: false, didBackspace: false)
        _ = short.projectInline(resultID: "domain", text: "github.com", selection: NSRange(location: 3, length: 0), hasMarkedText: false)
        expect(CommandBarFieldAnchor.visibleRange(text: "github.com", displayed: short.displayedText, selection: short.selection,
                                                  completion: CommandBarFieldAnchor.completion(short), hasMarkedText: false)
               == NSRange(location: 3, length: 7), "a short tail is kept whole")
        var arrowed = CommandBarEditState(query: "dashboard")
        arrowed.project(resultID: "row", text: address)
        expect(CommandBarFieldAnchor.visibleRange(text: address, displayed: arrowed.displayedText, selection: arrowed.selection,
                                                  completion: CommandBarFieldAnchor.completion(arrowed), hasMarkedText: false)?.location == 0,
               "an arrowed row whose text does not continue the query shows its start")
        var emoji = CommandBarEditState(query: "")
        emoji.userEdit("🌌", selection: NSRange(location: 2, length: 0), hasMarkedText: false, didBackspace: false)
        _ = emoji.projectInline(resultID: "emoji", text: "🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌🌌", selection: NSRange(location: 2, length: 0), hasMarkedText: false)
        let emojiLead = CommandBarFieldAnchor.visibleRange(text: emoji.displayedText, displayed: emoji.displayedText, selection: emoji.selection,
                                                           completion: CommandBarFieldAnchor.completion(emoji), hasMarkedText: false)
        expect(emojiLead == NSRange(location: 2, length: 2 * CommandBarFieldAnchor.leadCharacters), "the lead never splits a character")
        var hebrew = CommandBarEditState(query: "")
        hebrew.userEdit("של", selection: NSRange(location: 2, length: 0), hasMarkedText: false, didBackspace: false)
        _ = hebrew.projectInline(resultID: "rtl", text: "שלום עולם", selection: NSRange(location: 2, length: 0), hasMarkedText: false)
        expect(CommandBarFieldAnchor.visibleRange(text: hebrew.displayedText, displayed: hebrew.displayedText, selection: hebrew.selection,
                                                  completion: CommandBarFieldAnchor.completion(hebrew), hasMarkedText: false) == nil,
               "right-to-left text keeps the native scrolling")

        expect(!CommandBarFieldAnchor.fades(text: "a", textEnd: 300.4, visibleEnd: 300, padding: 0), "sub-pixel rounding is not overflow")
        expect(!CommandBarFieldAnchor.fades(text: "a", textEnd: 305.5, visibleEnd: 300, padding: 5),
               "the trailing padding and pixel snapping are not overflow")
        expect(CommandBarFieldAnchor.fades(text: "a", textEnd: 320, visibleEnd: 300, padding: 0), "text past the trailing edge fades")
        expect(!CommandBarFieldAnchor.fades(text: "a", textEnd: 120, visibleEnd: 300, padding: 0), "fitting text has no fade")
        expect(!CommandBarFieldAnchor.fades(text: "", textEnd: 400, visibleEnd: 300, padding: 0), "an empty field never fades its placeholder")
        expect(!CommandBarFieldAnchor.fades(text: "שלום עולם", textEnd: 400, visibleEnd: 300, padding: 0),
               "right-to-left text is not faded at the wrong edge")
        expect(CommandBarFieldAnchor.fades(text: "a", textEnd: nil, visibleEnd: 300, padding: 0), "unmeasured very long text fades")
        expect(CommandBarFieldAnchor.leavesCompletion(selection: NSRange(location: 40, length: 0), completion: completion),
               "moving away from the filled-in tail touches the completion")
        expect(!CommandBarFieldAnchor.leavesCompletion(selection: state.selection, completion: completion),
               "the filled-in tail itself is untouched")
        expect(!CommandBarFieldAnchor.leavesCompletion(selection: NSRange(location: 3, length: 0), completion: nil),
               "without a completion nothing is touched")
        expect(CommandBarFieldAnchor.visibleRange(text: address, displayed: state.displayedText, selection: state.selection,
                                                  completion: completion, hasMarkedText: false, touched: true) == nil,
               "a completion the user scrolled or reselected by hand keeps native scrolling until the next fill")
        expect(CommandBarFieldAnchor.fadeWidth(fieldWidth: 600, fontSize: 18) == 24, "the large field fades over 24 points")
        expect(CommandBarFieldAnchor.fadeWidth(fieldWidth: 400, fontSize: 13) == 17, "the compact field fades over 17 points")
        expect(CommandBarFieldAnchor.fadeWidth(fieldWidth: 20, fontSize: 18) == 10, "a tiny field never fades more than half")
        expect(CommandBarFieldAnchor.fadeLocations(width: 600, fade: 24) == [0, 576.0 / 600.0, 1], "the fade sits at the trailing edge")

        let title = "My Apps Dashboard | Fullscript"
        let historyURL = "https://fullscript.okta.com/app/UserHome?iss=x"
        expect(CommandBarCompletionTitle.text(title: title, url: historyURL, isSearch: false, completion: "fullscript.okta.com") == title,
               "a real page title is shown")
        expect(CommandBarCompletionTitle.display(title) == "— " + title, "the visible title follows a dash")
        expect(CommandBarCompletionTitle.text(title: "  My Apps\nDashboard ", url: historyURL, isSearch: false, completion: "fullscript.okta.com")
               == "My Apps Dashboard", "title whitespace is tidied to one line")
        expect(CommandBarCompletionTitle.text(title: "", url: historyURL, isSearch: false, completion: "fullscript.okta.com") == nil,
               "no title, no suffix")
        expect(CommandBarCompletionTitle.text(title: "fullscript.okta.com/app/UserHome?iss=x", url: historyURL, isSearch: false,
                                              completion: "fullscript.okta.com/app/UserHome?iss=x") == nil,
               "a title that is the address is hidden")
        expect(CommandBarCompletionTitle.text(title: "fullscript.okta.com", url: historyURL, isSearch: false, completion: "fullscript.okta.com") == nil,
               "a title that is the site's host is hidden")
        expect(CommandBarCompletionTitle.text(title: "www.github.com", url: "https://github.com/", isSearch: false, completion: "github.com") == nil,
               "www and scheme differences are still the address")
        expect(CommandBarCompletionTitle.text(title: "fullscript.okta.com/app/UserHome", url: historyURL, isSearch: false,
                                              completion: "fullscript.okta.com") == nil,
               "an address-shaped title on the same site is hidden")
        expect(CommandBarCompletionTitle.text(title: "GitHub", url: "https://github.com/", isSearch: false, completion: "github.com") == "GitHub",
               "a one-word site name is a real title")
        expect(CommandBarCompletionTitle.text(title: "weather calgary", url: nil, isSearch: true, completion: "weather calgary") == nil,
               "search completions never get a title")

        expect(CommandBarCompletionTitle.isInline(query: "fullscript.okta", text: address, displayed: state.displayedText,
                                                  selection: state.selection, completion: completion, hasMarkedText: false),
               "an untouched inline completion shows its title")
        expect(!CommandBarCompletionTitle.isInline(query: "fullscript.okta", text: address, displayed: state.displayedText,
                                                   selection: NSRange(location: (address as NSString).length, length: 0),
                                                   completion: completion, hasMarkedText: false),
               "moving the caret hides the title")
        expect(!CommandBarCompletionTitle.isInline(query: "fullscript.okta", text: address, displayed: state.displayedText,
                                                   selection: state.selection, completion: completion, hasMarkedText: true),
               "composition hides the title")
        expect(!CommandBarCompletionTitle.isInline(query: "fullscript.okta", text: address, displayed: accepted.displayedText,
                                                   selection: accepted.selection, completion: CommandBarFieldAnchor.completion(accepted),
                                                   hasMarkedText: false),
               "Tab acceptance hides the title")
        expect(!CommandBarCompletionTitle.isInline(query: "dashboard", text: address, displayed: arrowed.displayedText,
                                                   selection: arrowed.selection, completion: CommandBarFieldAnchor.completion(arrowed),
                                                   hasMarkedText: false),
               "a whole-row replacement is not an inline completion")
        var deleted = state
        deleted.userEdit("fullscript.okt", selection: NSRange(location: 14, length: 0), hasMarkedText: false, didBackspace: true)
        expect(!deleted.projectInline(resultID: "history", text: address, selection: NSRange(location: 14, length: 0), hasMarkedText: false)
               && !CommandBarCompletionTitle.isInline(query: deleted.query, text: deleted.displayedText, displayed: deleted.displayedText,
                                                      selection: deleted.selection, completion: CommandBarFieldAnchor.completion(deleted),
                                                      hasMarkedText: false),
               "deleting suppresses completion and its title")

        expect(CommandBarCompletionTitle.frame(textEnd: 200, fieldEnd: 600, natural: 180, gap: 4, minimum: 72).map { [$0.x, $0.width] }
               == [204, 180], "a fitting title keeps its natural width right after the text")
        expect(CommandBarCompletionTitle.frame(textEnd: 450, fieldEnd: 600, natural: 300, gap: 4, minimum: 72).map { [$0.x, $0.width] }
               == [454, 146], "a long title truncates at the field's edge")
        expect(CommandBarCompletionTitle.frame(textEnd: 560, fieldEnd: 600, natural: 300, gap: 4, minimum: 72) == nil,
               "too little room hides the title instead of showing a stub")
        expect(CommandBarCompletionTitle.frame(textEnd: 560, fieldEnd: 600, natural: 30, gap: 4, minimum: 72).map { $0.width } == 30,
               "a short title that fits whole still shows")
        expect(CommandBarCompletionTitle.frame(textEnd: 640, fieldEnd: 600, natural: 30, gap: 4, minimum: 72) == nil,
               "overflowing text has no title")

        let clip = NSClipView(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        let editor = CommandBarAnchoredEditor(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        editor.isFieldEditor = true
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = false
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: 1e7, height: 22)
        editor.maxSize = NSSize(width: 1e7, height: 22)
        editor.font = CommandBarTypography.field
        var clipChanges = 0
        editor.onClipChange = { _ in clipChanges += 1 }
        clip.documentView = editor
        expect(clipChanges > 0, "joining a clip view reports its geometry")
        func boundary(_ index: Int) -> CGFloat {
            let prefix = editor.textStorage!.attributedSubstring(from: NSRange(location: 0, length: index))
            return editor.textContainerOrigin.x + editor.textContainer!.lineFragmentPadding + prefix.size().width
        }
        var touched = false
        editor.onUserScroll = { touched = true }
        func show(_ edit: CommandBarEditState) {
            touched = false
            editor.string = edit.displayedText
            editor.setSelectedRange(edit.selection)
            editor.scrollRangeToVisible(editor.selectedRange())
        }
        show(state)
        expect(clip.bounds.minX > boundary(15), "without the anchor the editor scrolls the typed text out of view")
        var current = state
        editor.anchorsScroll = {
            guard let range = CommandBarFieldAnchor.visibleRange(text: editor.string, displayed: current.displayedText,
                                                                 selection: editor.selectedRange(),
                                                                 completion: CommandBarFieldAnchor.completion(current),
                                                                 hasMarkedText: editor.hasMarkedText(),
                                                                 touched: touched) else { return false }
            editor.reveal(range)
            return true
        }
        let before = clipChanges
        show(state)
        expect(clip.bounds.minX == 0, "the typed text shows from its start")
        expect(editor.textEnd.map { abs($0 - boundary((address as NSString).length)) < 0.01 } == true,
               "the measured text end matches the laid-out text")
        expect(boundary(15) < clip.bounds.maxX, "the boundary between typed and filled-in text is in view")
        expect(clipChanges > before, "anchored scrolling reports the move so the fade can follow")
        _ = editor.scrollToVisible(NSRect(x: boundary((address as NSString).length) - 2, y: 0, width: 2, height: 10))
        expect(clip.bounds.minX == 0, "the editor's own scroll requests keep the anchor")
        let typed = String(address.prefix(60))
        current = CommandBarEditState(query: "")
        current.userEdit(typed, selection: NSRange(location: 60, length: 0), hasMarkedText: false, didBackspace: false)
        _ = current.projectInline(resultID: "history", text: address, selection: NSRange(location: 60, length: 0), hasMarkedText: false)
        show(current)
        expect(clip.bounds.minX > 0 && boundary(60) > clip.bounds.minX && boundary(60) < clip.bounds.maxX,
               "long typed text keeps its end and the boundary in view")
        expect(boundary(current.displayedText.utf16.count) > clip.bounds.maxX, "the filled-in tail trails off past the edge")
        expect(CommandBarFieldAnchor.fades(text: editor.string, textEnd: editor.textEnd, visibleEnd: editor.visibleEnd,
                                           padding: editor.trailingPadding), "the cut-off completion fades")
        editor.doCommand(by: #selector(NSResponder.scrollPageDown(_:)))
        expect(!touched && clip.bounds.minX > 0 && boundary(60) < clip.bounds.maxX,
               "a vertical scroll command cannot move the single line, so the anchor stays")
        editor.doCommand(by: #selector(NSResponder.scrollToEndOfDocument(_:)))
        expect(touched && editor.selectedRange() == current.selection && clip.bounds.maxX >= editor.frame.maxX - 1,
               "scrolling to the end yourself is not pulled back to the anchor")
        show(current)
        expect(!touched && boundary(60) < clip.bounds.maxX, "the next fill anchors again")
        editor.setSelectedRange(NSRange(location: (address as NSString).length, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        expect(clip.bounds.minX > boundary(60) && clip.bounds.maxX >= editor.frame.maxX - 1,
               "the user's own caret move scrolls natively to the end")
        expect(!CommandBarFieldAnchor.fades(text: editor.string, textEnd: editor.textEnd, visibleEnd: editor.visibleEnd,
                                            padding: editor.trailingPadding), "scrolled to its end, the text no longer fades")
        editor.setSelectedRange(current.selection)
        touched = false
        editor.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: 60, length: 0))
        expect(editor.hasMarkedText() && editor.anchorsScroll?() == false, "marked text scrolls natively instead of being anchored")
        editor.unmarkText()

        let field = CommandBarInputField(frame: NSRect(x: 0, y: 0, width: 600, height: 31))
        field.wantsLayer = true
        field.setTrailingFade(true, width: 24)
        let mask = field.layer?.mask as? CAGradientLayer
        expect(mask?.frame == field.bounds, "the fade covers the field")
        expect(mask?.locations?.map(\.doubleValue) == [0, 576.0 / 600.0, 1], "the fade starts 24 points from the trailing edge")
        field.setFrameSize(NSSize(width: 300, height: 31))
        expect((field.layer?.mask as? CAGradientLayer)?.locations?.map(\.doubleValue) == [0, 276.0 / 300.0, 1], "the fade follows resizing")
        field.setTrailingFade(false, width: 24)
        expect(field.layer?.mask == nil, "fitting text has no fade")

        let label = CommandBarCompletionTitleLabel.make()
        label.stringValue = CommandBarCompletionTitle.display(title)
        label.spokenTitle = title
        label.frame = NSRect(x: 0, y: 0, width: 200, height: 31)
        expect(label.hitTest(NSPoint(x: 10, y: 10)) == nil, "clicks on the title reach the field")
        expect(label.accessibilityValue() == title, "VoiceOver hears the title without the dash")
        expect(label.accessibilityRole() == .staticText, "VoiceOver treats the title as text, not typed input")
        expect(!label.isEditable && !label.isSelectable, "the title is never part of the field's text")
        expect(label.lineBreakMode == .byTruncatingTail, "the title truncates gracefully")
        print("\(count) command-bar field anchor assertions passed")
    }
}
