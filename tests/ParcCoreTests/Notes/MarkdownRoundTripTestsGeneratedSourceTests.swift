import Foundation
import Testing
@testable import ParcCore

struct MarkdownRoundTripTestsGeneratedSourceTests {
    private typealias MarkdownRandom = MarkdownRoundTripTestsSupport.MarkdownRandom

    private static let sourcePieces = ["# ", "## ", "> ", "- ", "* ", "+ ", "1. ", "2) ", "- [ ] ", "- [x] ", "    ", "  ", "\t", "```", "~~~", "---", "***", "===",
                               "| a | b |", "| --- | :-: |", "<div>", "</div>", "<!-- c -->", "<details>", "<summary>S</summary>", "</details>",
                               ":::: columns", "::: column", ":::", "::: indent", ":::: indent", "$$", "$x$", "$5", "**", "*", "_", "__", "~~", "==", "`", "[", "]", "(", ")",
                               "[a](b)", "![i](p.png)", "[[W]]", "<u>", "</u>", "<span data-color=\"red\">", "</span>", "<b>", "&amp;", "&#32;",
                               "\\", "\\*", "text", "more words", "https://x.y/z", "www.a.bc", "m@x.io", "[^1]", "[^1]: note", "[r]: /url",
                               "> [!NOTE]", "> [!tip]- T", "<!-- parc color=\"red\" -->", "<!-- toc -->", "<time datetime=\"2026-01-02\">d</time>",
                               "<summary>B <!-- parc button --></summary>", "<!-- parc insert=\"top\" -->", "<!-- parc confirm=\"Sure?\" -->"]

    private static func generateSource(_ random: inout MarkdownRandom) -> String {
        var lines: [String] = []
        for _ in 0..<random.int(1...12) {
            var line = ""
            for _ in 0..<random.int(0...5) { line += random.pick(sourcePieces) + (random.chance(60) ? " " : "") }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    struct GeneratedSource: Sendable, CustomTestStringConvertible {
        let index: Int
        let markdown: String

        var testDescription: String { "source \(index)" }
    }

    private static let generatedSources: [GeneratedSource] = {
        var random = MarkdownRandom(state: 99)
        return (0..<1500).map { index in
            GeneratedSource(index: index, markdown: generateSource(&random))
        }
    }()

    @Test(arguments: generatedSources)
    func generatedSourcesSettleAfterOneSave(fixture: GeneratedSource) {
        #expect(NoteMarkdownCheck.checkStable(fixture.markdown, fixture.testDescription))
    }
}
