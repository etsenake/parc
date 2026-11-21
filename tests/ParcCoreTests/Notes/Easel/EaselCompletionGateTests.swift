import Testing
@testable import ParcCore

struct EaselCompletionGateTests {
    @Test func typingTheClosingColonMayCompleteAShortcode() {
        #expect(EaselCompletionGate.action(inserted: ":", editedByOne: true, panelOpen: false) == .complete, "Typing the closing colon may complete a shortcode")
    }

    @Test func oneTypedLetterMayOpenTheEmojiList() {
        #expect(EaselCompletionGate.action(inserted: "h", editedByOne: true, panelOpen: false) == .open, "One typed letter may open the emoji list")
        #expect(EaselCompletionGate.action(inserted: "🚀", editedByOne: true, panelOpen: true) == .open, "One typed emoji counts as one character")
    }

    @Test func pastingAShortcodeNeverConvertsIt() {
        #expect(EaselCompletionGate.action(inserted: "ship it :rocket:", editedByOne: false, panelOpen: false) == .dismiss, "Pasting a shortcode never converts it")
        #expect(EaselCompletionGate.action(inserted: "ab", editedByOne: false, panelOpen: true) == .dismiss, "Two characters at once are not typing")
    }

    @Test func deletingRefreshesAnOpenQueryAndNeverOpensTheList() {
        #expect(EaselCompletionGate.action(inserted: nil, editedByOne: true, panelOpen: true) == .refresh, "Deleting inside an open query refreshes it")
        #expect(EaselCompletionGate.action(inserted: nil, editedByOne: true, panelOpen: false) == .dismiss, "Deleting never opens the list")
    }

    @Test func dictationAutocorrectAndDropsCloseTheList() {
        #expect(EaselCompletionGate.action(inserted: nil, editedByOne: false, panelOpen: true) == .dismiss, "Dictation, autocorrect and drops close the list")
    }
}
