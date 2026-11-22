import Foundation
import Testing
@testable import ParcCore

struct NoteMermaidOutcomeTests {
    @Test func aSuccessfulReplyReturnsSvgWithWholePointDimensions() {
        let good: [String: Any] = ["ok": true, "svg": "<svg/>", "x": 0, "y": 2, "width": 120.4, "height": 80]
        guard let parsed = NoteMermaidOutcome.parse(good), let drawing = parsed.outcome.drawing else {
            Issue.record("a good reply parses")
            return
        }
        #expect(drawing.svg == "<svg/>" && drawing.size == CGSize(width: 121, height: 80) && parsed.origin == CGPoint(x: 0, y: 2), "sizes round up to whole points")
    }

    @Test func aFailedReplyTrimsItsErrorMessage() {
        let bad: [String: Any] = ["ok": false, "message": "  Parse error on line 2:\nA -->\n  "]
        if case .failure(let message)? = NoteMermaidOutcome.parse(bad)?.outcome {
            #expect(message == "Parse error on line 2:\nA -->", "error messages are trimmed")
        } else {
            Issue.record("a failed reply becomes a failure")
            return
        }
    }

    @Test func aFailedReplyWithoutAMessageUsesTheFallback() {
        if case .failure(let message)? = NoteMermaidOutcome.parse(["ok": false])?.outcome {
            #expect(message == NoteMermaidProblem.fallback, "a silent failure still says something")
        } else {
            Issue.record("a failure without a message still fails")
            return
        }
    }

    @Test func nonDictionaryRepliesAreIgnored() {
        #expect(NoteMermaidOutcome.parse(nil) == nil && NoteMermaidOutcome.parse("nope") == nil, "garbage replies don't parse")
    }

    @Test func aDrawingWithNoWidthIsRejected() {
        #expect(NoteMermaidOutcome.parse(["ok": true, "svg": "<svg/>", "width": 0, "height": 10]) == nil, "empty drawings don't parse")
    }

    @Test func diagramFailuresCacheButRendererFailuresCanRetry() {
        #expect(NoteMermaidOutcome.failure("x").isCacheable && !NoteMermaidOutcome.unavailable("x").isCacheable, "Mermaid's verdicts cache, broken renderers retry")
    }

    @Test func aMultilineProblemExtractsAHeadlineDetailAndLineNumber() {
        let message = "Parse error on line 3:\n...lowchart TD  A -->\n---------------------^\nExpecting 'AMP', got 'EOF'"
        let problem = NoteMermaidProblem(message: message)
        #expect(problem.headline == "Parse error on line 3", "the first line headlines without its colon")
        #expect(problem.detail == "...lowchart TD  A -->\n---------------------^\nExpecting 'AMP', got 'EOF'", "the pointer stays verbatim")
        #expect(problem.line == 3, "the line number is read")
    }

    @Test func anUnlocatedProblemHasNoLineOrDetail() {
        let unknown = NoteMermaidProblem(message: "No diagram type detected matching given configuration for text: hi")
        #expect(unknown.detail == nil && unknown.line == nil, "one-line errors have no detail")
    }

    @Test func blankProblemsUseTheFallbackHeadline() {
        #expect(NoteMermaidProblem(message: "   ").headline == NoteMermaidProblem.fallback, "empty errors still explain")
    }

    @Test func aLexicalErrorExtractsItsLine() {
        #expect(NoteMermaidProblem(message: "Lexical error on line 12. Unrecognized text.").line == 12, "lexical errors find their line")
    }

    @Test func anErrorBeyondTheSourcePointsToItsLastLine() {
        let message = "Parse error on line 3:\n...lowchart TD  A -->\n---------------------^\nExpecting 'AMP', got 'EOF'"
        let problem = NoteMermaidProblem(message: message)
        let source = "flowchart TD\n  A -->"
        let range = problem.range(in: source)
        #expect(range == 13..<20, "an error past the end points at the last real line: \(String(describing: range))")
    }

    @Test func theFirstLineMapsToItsText() {
        let source = "flowchart TD\n  A -->"
        #expect(NoteMermaidProblem(message: "Parse error on line 1:").range(in: source) == 0..<12, "line one is the first line")
    }

    @Test func anErrorOnABlankLinePointsToThePrecedingText() {
        #expect(NoteMermaidProblem(message: "Parse error on line 2:").range(in: "graph\n\n") == 0..<5, "blank lines step back to text")
    }

    @Test func anErrorWithoutALineHasNoHighlightRange() {
        let unknown = NoteMermaidProblem(message: "No diagram type detected matching given configuration for text: hi")
        let source = "flowchart TD\n  A -->"
        #expect(unknown.range(in: source) == nil, "no line, no range")
    }
}
