import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxMarkupTestsLanguagePickerTests {
    static let languageIDs = NoteCodeLanguage.all.map(\.id)
    static let highlightedIDs = languageIDs.filter { $0 != "plaintext" }

    @Test func plainTextLeadsThePicker() {
        #expect(NoteCodeLanguage.all.first?.id == "plaintext")
        #expect(NoteCodeLanguage.all.first?.name == "Plain Text")
    }

    @Test func theRestOfThePickerIsAlphabetical() {
        let names = NoteCodeLanguage.all.dropFirst().map { $0.name.lowercased() }
        #expect(names == names.sorted())
    }

    @Test func languageIDsAreUnique() {
        #expect(Set(NoteCodeLanguage.all.map(\.id)).count == NoteCodeLanguage.all.count)
    }

    @Test func thePickerOffersAboutThirtyFiveLanguagesAndThenSome() {
        #expect(NoteCodeLanguage.all.count >= 36)
    }

    struct FenceCase: Sendable, CustomTestStringConvertible {
        let fence: String
        let id: String

        init(_ fence: String, _ id: String) {
            self.fence = fence
            self.id = id
        }

        var testDescription: String { "\(fence.debugDescription) names \(id)" }
    }

    @Test(arguments: [
        FenceCase("js", "javascript"), FenceCase("ts", "typescript"), FenceCase("sh", "bash"), FenceCase("shell", "bash"), FenceCase("zsh", "bash"), FenceCase("py", "python"),
        FenceCase("objc", "objectivec"), FenceCase("c++", "cpp"), FenceCase("yml", "yaml"), FenceCase("JSON", "json"), FenceCase("  Swift  ", "swift"), FenceCase("C#", "csharp"),
        FenceCase("rb", "ruby"), FenceCase("rs", "rust"), FenceCase("kt", "kotlin"), FenceCase("md", "markdown"), FenceCase("Dockerfile", "dockerfile"), FenceCase("patch", "diff"),
        FenceCase("python title=\"demo.py\"", "python"), FenceCase("{.rust}", "rust"), FenceCase("language-go", "go"), FenceCase("Objective-C", "objectivec"),
        FenceCase("gql", "graphql"), FenceCase("plain", "plaintext"), FenceCase("Plain Text", "plaintext"), FenceCase("tsx", "tsx"), FenceCase("jsx", "jsx"),
    ])
    func aFenceNamesItsLanguage(fixture: FenceCase) {
        #expect(NoteCodeLanguage.named(fixture.fence)?.id == fixture.id)
    }

    @Test(arguments: ["brainfudge", ""])
    func unknownFencesNameNothing(fence: String) {
        #expect(NoteCodeLanguage.named(fence) == nil)
    }

    @Test(arguments: ["klingon", "text"])
    func unknownAndPlainLanguagesGetNoTokens(language: String) {
        #expect(NoteSyntaxHighlighter.tokens(in: "let x = 1", language: language).isEmpty)
    }

    @Test func emptyCodeGetsNoTokens() {
        #expect(NoteSyntaxHighlighter.tokens(in: "", language: "swift").isEmpty)
    }

    @Test(arguments: highlightedIDs)
    func everyHighlightedLanguageHasALexer(id: String) {
        #expect(NoteSyntaxLexer.lexer(for: id) != nil)
    }
}
