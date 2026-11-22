import Foundation
import Testing
@testable import ParcCore

struct EaselCodeBlockModelTests {
    func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Code", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    @MainActor func accepts(_ items: [EaselItem]) -> Bool {
        (try? EaselSession(inMemory: document(items), assets: [:])) != nil
    }

    @Test
    func aNewCodeBlockStartsWithFourEmptyLines() {
        let block = EaselCodeBlock.item(at: .init(x: 10, y: 20), language: "typescript", zIndex: 3)
        #expect(block.kind == .code && block.text == "\n\n\n", "a new code block starts with four empty lines")
        #expect(block.frame.height == EaselCodeBlock.height(lines: 4), "a new code block is four lines tall")
        #expect(block.frame.width == EaselCodeBlock.defaultWidth && block.zIndex == 3, "a new code block takes the default width and layer")
    }

    @Test
    func aCodeBlockSavesItsLanguageAndRoundTrips() {
        let block = EaselCodeBlock.item(at: .init(x: 10, y: 20), language: "typescript", zIndex: 3)
        #expect(block.kind == .code && block.text == "\n\n\n", "a new code block starts with four empty lines")
        #expect(block.frame.height == EaselCodeBlock.height(lines: 4), "a new code block is four lines tall")
        #expect(block.frame.width == EaselCodeBlock.defaultWidth && block.zIndex == 3, "a new code block takes the default width and layer")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(block)) ?? Data()
        #expect(String(decoding: data, as: UTF8.self).contains("\"language\":\"typescript\""), "the language is saved")
        #expect((try? JSONDecoder().decode(EaselItem.self, from: data)) == block, "a code block round-trips")
    }

    @Test
    func objectsWithoutLanguagesOmitTheField() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let note = EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 10, height: 10))
        let plain = String(decoding: (try? encoder.encode(note)) ?? Data(), as: UTF8.self)
        #expect(!plain.contains("language"), "objects without a language leave it out of the file")
    }

    @Test
    func olderFilesOpenWithoutALanguage() {
        let older = Data("{\"id\":\"\(UUID().uuidString)\",\"kind\":\"text\",\"frame\":{\"x\":0,\"y\":0,\"width\":10,\"height\":10},\"zIndex\":0,\"text\":\"\",\"color\":\"#252525\",\"points\":[]}".utf8)
        #expect((try? JSONDecoder().decode(EaselItem.self, from: older))?.language == nil, "older files open without a language")
    }

    @Test
    func lineCountRecognizesUnixAndWindowsNewlines() {
        #expect(EaselCodeBlock.lineCount("") == 1 && EaselCodeBlock.lineCount("a\nb") == 2, "lines are counted by newlines")
        #expect(EaselCodeBlock.lineCount("a\r\nb\n") == 3, "Windows line endings count once per line")
    }

    @Test
    func codeBlocksHoldPlainText() {
        #expect(!EaselItemKind.code.holdsText, "code blocks keep plain text, never rich text")
    }

    @MainActor @Test
    func codeBlocksAcceptAValidLanguage() {
        let block = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "python", zIndex: 0)
        #expect(accepts([block]), "a code block with a language saves")
    }

    @MainActor @Test
    func codeBlocksAcceptNoLanguage() {
        let block = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "python", zIndex: 0)
        var plain = block
        plain.language = nil
        #expect(accepts([plain]), "a plain text code block saves without a language")
    }

    @MainActor @Test
    func codeBlocksAcceptAWellFormedFutureLanguage() {
        let block = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "python", zIndex: 0)
        var future = block
        future.language = "future-lang2"
        #expect(accepts([future]), "a language from a newer Parc still opens")
    }

    @MainActor @Test
    func codeBlocksRejectMisspelledLanguageIdentifiers() {
        let block = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "python", zIndex: 0)
        var spaced = block
        spaced.language = "Type Script"
        #expect(!accepts([spaced]), "a malformed language is refused")
    }

    @MainActor @Test
    func codeBlocksRejectOverlongLanguageIdentifiers() {
        let block = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "python", zIndex: 0)
        var long = block
        long.language = String(repeating: "a", count: 33)
        #expect(!accepts([long]), "an overlong language is refused")
    }

    @MainActor @Test
    func codeBlocksRejectEmptyLanguageIdentifiers() {
        let block = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "python", zIndex: 0)
        var empty = block
        empty.language = ""
        #expect(!accepts([empty]), "an empty language is refused")
    }

    @MainActor @Test
    func otherKindsRejectCodeBlockLanguages() {
        var text = EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: 10, height: 10))
        text.language = "swift"
        #expect(!accepts([text]), "a language on a non-code object is refused")
    }

    @MainActor @Test
    func codeBlocksRejectRichText() {
        let block = EaselCodeBlock.item(at: .init(x: 0, y: 0), language: "python", zIndex: 0)
        var rich = block
        rich.text = "let a = 1"
        rich.richText = EaselRichText(runs: [])
        #expect(!accepts([rich]), "rich text on a code block is refused")
    }

    @Test
    func aNewCodeBlockUsesTheRememberedLanguageOrDefault() {
        #expect(EaselCodeBlock.newLanguage(remembered: nil) == "typescript", "the first block starts in TypeScript")
        #expect(EaselCodeBlock.newLanguage(remembered: "py") == "python", "the last language is reused")
        #expect(EaselCodeBlock.newLanguage(remembered: "plaintext") == nil, "plain text is remembered too")
        #expect(EaselCodeBlock.newLanguage(remembered: "klingon") == "typescript", "an unknown memory falls back to TypeScript")
    }

    @Test
    func plainTextAndLanguagesUseDistinctStoredValues() {
        #expect(EaselCodeBlock.rememberedValue(nil) == "plaintext" && EaselCodeBlock.rememberedValue("swift") == "swift",
               "plain text and real languages are remembered distinctly")
        #expect(EaselCodeBlock.stored(.plainText) == nil, "plain text is stored as no language")
    }

    @Test
    func aLanguageDisplaysItsHumanReadableName() {
        #expect(EaselCodeBlock.displayName(nil) == "Plain Text", "no language reads as plain text")
        #expect(EaselCodeBlock.displayName("typescript") == "TypeScript", "known languages use their proper names")
        #expect(EaselCodeBlock.displayName("future-lang") == "future-lang", "unknown languages show what was saved")
    }

    @Test
    func highlightingResolvesKnownLanguagesAndFallsBackToPlainText() {
        #expect(EaselCodeBlock.language("tsx").id == "tsx" && EaselCodeBlock.language("nope").id == "plaintext", "languages resolve for highlighting")
    }

    @Test
    func everyNotesLanguageCanBeStored() {
        #expect(NoteCodeLanguage.all.allSatisfy { EaselItem.isValidLanguage($0.id) }, "every Notes language is a valid stored value")
    }
}
