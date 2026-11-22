import Foundation
import Testing
@testable import ParcCore

struct NoteMermaidMarkdownTests {
    private func diagram(_ source: String, mode: NoteDiagramMode? = nil, language: String = "mermaid") -> NoteBlock {
        var block = NoteBlock(.code, text: NoteText(source))
        block.props.language = language
        block.props.diagramMode = mode
        return block
    }

    @Test func defaultPreviewSerializesAsAPlainMermaidFence() {
        let source = "flowchart TD\n  A --> B"
        let plain = NoteMarkdown.serialize(NotePage(blocks: [diagram(source)]))
        #expect(plain == "```mermaid\n" + source + "\n```\n", "a previewed diagram stays a plain fence GitHub draws: \(plain.debugDescription)")
    }

    @Test func explicitPreviewSerializesLikeDefaultPreview() {
        let source = "flowchart TD\n  A --> B"
        let plain = NoteMarkdown.serialize(NotePage(blocks: [diagram(source)]))
        let explicitPreview = NoteMarkdown.serialize(NotePage(blocks: [diagram(source, mode: .preview)]))
        #expect(explicitPreview == plain, "Preview is the default, so it writes nothing extra")
    }

    @Test(arguments: [NoteDiagramMode.code, .split]) func nondefaultModesRoundTripWithoutChangingTheFence(_ mode: NoteDiagramMode) {
        let source = "flowchart TD\n  A --> B"
        let written = NoteMarkdown.serialize(NotePage(blocks: [diagram(source, mode: mode)]))
        #expect(written.hasPrefix("```mermaid\n" + source + "\n```\n"), "the fence itself stays plain in \(mode.title)")
        #expect(written.contains("<!-- parc view=\"\(mode.rawValue)\" -->"), "\(mode.title) rides along in invisible metadata: \(written)")
        let read = NoteMarkdown.parse(written).blocks
        #expect(read.count == 1 && read[0].kind == .code, "the metadata doesn't become a block")
        #expect(read[0].props.diagramMode == mode, "\(mode.title) survives the round trip")
        #expect(read[0].props.language == "mermaid" && read[0].text.string == source, "the diagram source survives the round trip")
        #expect(NoteMarkdown.serialize(NotePage(blocks: read)) == written, "\(mode.title) writes back byte for byte")
    }

    @Test func diagramViewCanShareMetadataWithWrapping() {
        let source = "flowchart TD\n  A --> B"
        let wrapped = diagram(source, mode: .split)
        var both = wrapped
        both.props.wrap = true
        let combined = NoteMarkdown.serialize(NotePage(blocks: [both]))
        let reread = NoteMarkdown.parse(combined).blocks.first
        #expect(reread?.props.wrap == true && reread?.props.diagramMode == .split, "view shares the comment with wrap: \(combined)")
    }

    @Test func otherCodeLanguagesDoNotStoreDiagramModes() {
        let other = NoteMarkdown.serialize(NotePage(blocks: [diagram("print(1)", mode: .split, language: "python")]))
        #expect(!other.contains("view="), "only Mermaid blocks remember a view")
    }

    @Test func anExplicitPreviewTagParsesAsDefaultPreview() {
        let previewTag = NoteMarkdown.parse("```mermaid\ngraph TD\n```\n<!-- parc view=\"preview\" -->\n").blocks.first
        #expect(previewTag?.props.diagramMode == nil, "an explicit preview tag reads as the default")
    }

    @Test func unknownDiagramModesAreIgnored() {
        let junk = NoteMarkdown.parse("```mermaid\ngraph TD\n```\n<!-- parc view=\"sideways\" -->\n").blocks.first
        #expect(junk?.props.diagramMode == nil && junk?.text.string == "graph TD", "unknown views are ignored")
    }

    @Test func aClipboardArchiveRetainsDiagramMode() {
        let source = "flowchart TD\n  A --> B"
        let wrapped = diagram(source, mode: .split)
        let archived = try? JSONDecoder().decode(NoteBlock.self, from: JSONEncoder().encode(wrapped))
        #expect(archived?.props.diagramMode == .split, "the clipboard archive keeps the view")
    }
}
