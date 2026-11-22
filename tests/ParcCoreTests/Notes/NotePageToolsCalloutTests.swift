import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsCalloutTests {
    private func callout(alert: String?, icon: String? = nil, color: NoteColorStyle? = nil) -> NoteBlock {
        var block = NoteBlock(.callout, text: "Heads up")
        block.props.alert = alert
        block.props.icon = icon
        block.color = color
        return block
    }

    struct Alert: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let name: String
        let icon: String
        let color: NoteColor
    }

    private static let alerts = [
        Alert(testDescription: "TIP", name: "TIP", icon: "💡", color: .green),
        Alert(testDescription: "IMPORTANT", name: "IMPORTANT", icon: "❗️", color: .purple),
        Alert(testDescription: "WARNING", name: "WARNING", icon: "⚠️", color: .yellow),
        Alert(testDescription: "CAUTION", name: "CAUTION", icon: "🛑", color: .red),
        Alert(testDescription: "note", name: "note", icon: "ℹ️", color: .blue),
        Alert(testDescription: "info", name: "info", icon: "ℹ️", color: .blue),
        Alert(testDescription: "success", name: "success", icon: "✅", color: .green),
        Alert(testDescription: "question", name: "question", icon: "❓", color: .orange),
        Alert(testDescription: "failure", name: "failure", icon: "❌", color: .red),
        Alert(testDescription: "danger", name: "danger", icon: "⚡️", color: .red),
        Alert(testDescription: "bug", name: "bug", icon: "🐛", color: .red),
        Alert(testDescription: "example", name: "example", icon: "📝", color: .purple),
        Alert(testDescription: "quote", name: "quote", icon: "💬", color: .gray),
        Alert(testDescription: "abstract", name: "abstract", icon: "📋", color: .blue),
        Alert(testDescription: "todo", name: "todo", icon: "☑️", color: .blue),
    ]

    @Test(arguments: alerts) func alertsSupplyDisplayDefaultsWithoutWritingThem(_ example: Alert) {
        let alert = example.name
        let icon = example.icon
        let color = example.color
        let block = callout(alert: alert)
        #expect(block.calloutDisplayIcon == icon, "\(alert) shows \(icon) (got \(block.calloutDisplayIcon ?? "nothing"))")
        #expect(block.calloutDisplayColor == .background(color), "\(alert) gets a \(color) box")
        #expect(block.props.icon == nil && block.color == nil, "\(alert) defaults stay display only")
    }

    @Test func alertNamesIgnoreCase() {
        #expect(callout(alert: "tip").calloutDisplayIcon == "💡", "alert names ignore case")
    }

    @Test func anUnknownAlertHasNoDisplayDefaults() {
        #expect(callout(alert: "mystery").calloutDisplayIcon == nil && callout(alert: "mystery").calloutDisplayColor == nil, "unknown alerts keep the plain grey box")
    }

    @Test func aPlainCalloutHasNoDefaultIcon() {
        #expect(callout(alert: nil).calloutDisplayIcon == nil, "plain callouts without an icon stay iconless")
    }

    @Test func anExplicitIconOverridesTheAlertDefault() {
        #expect(callout(alert: "TIP", icon: "🌳").calloutDisplayIcon == "🌳", "a picked icon wins")
    }

    @Test func anExplicitlyRemovedIconStaysRemoved() {
        #expect(callout(alert: "TIP", icon: "").calloutDisplayIcon == nil, "a removed icon stays removed")
    }

    @Test func anExplicitBackgroundColorOverridesTheAlertDefault() {
        #expect(callout(alert: "TIP", color: .background(.pink)).calloutDisplayColor == .background(.pink), "a picked colour wins")
    }

    @Test func anExplicitTextColorOverridesTheAlertDefault() {
        #expect(callout(alert: "TIP", color: .text(.red)).calloutDisplayColor == .text(.red), "a picked text colour wins too")
    }

    @Test func removingAnAlertIconRecordsExplicitRemoval() {
        #expect(callout(alert: "TIP").calloutIconRemoval == "" && callout(alert: nil).calloutIconRemoval == nil, "removing an alert's icon writes an explicit none, a plain callout just drops it")
    }

    @Test func alertDefaultsApplyOnlyToCallouts() {
        var paragraph = NoteBlock.paragraph("Hi")
        paragraph.props.alert = "TIP"
        #expect(paragraph.calloutDisplayIcon == nil && paragraph.calloutDisplayColor == nil, "only callouts get alert defaults")
    }

    @Test func alertDefaultsDoNotChangeTheMarkdown() {
        let source = "> [!TIP]\n> Try the shortcut.\n"
        let page = NoteMarkdown.parse(source)
        #expect(NoteMarkdown.serialize(page) == source, "showing an alert's defaults never rewrites the file")
    }

    @Test func aRemovedAlertIconSurvivesMarkdownRoundTrip() {
        let source = "> [!TIP]\n> Try the shortcut.\n"
        var page = NoteMarkdown.parse(source)
        page.blocks[0].props.icon = page.blocks[0].calloutIconRemoval
        let reread = NoteMarkdown.parse(NoteMarkdown.serialize(page))
        #expect(reread.blocks[0].props.alert == "TIP" && reread.blocks[0].calloutDisplayIcon == nil, "a removed alert icon survives the file round trip without losing the alert")
    }

    @Test func aHandWrittenGitHubNoteUsesTheInfoDefaults() {
        let githubNote = NoteMarkdown.parse("> [!NOTE]\n> Heads up\n").blocks[0]
        #expect(githubNote.calloutDisplayIcon == "ℹ️" && githubNote.calloutDisplayColor == .background(.blue), "a hand-written GitHub NOTE shows blue with an info icon")
    }

    @Test func plainCalloutsStayPlainAfterMarkdownRoundTrip() {
        let plainNote = NoteMarkdown.parse(NoteMarkdown.serialize(NotePage(blocks: [callout(alert: nil)]))).blocks[0]
        #expect(plainNote.calloutDisplayIcon == nil && plainNote.calloutDisplayColor == nil, "a saved plain callout reloads plain and grey")
    }

    @Test func htmlExportUsesTheAlertAppearanceWithoutAnExplicitColor() {
        let html = NotePageHTML.document(NotePage(blocks: [callout(alert: "WARNING")]), title: "T", assets: { _ in nil }, embedImages: false)
        #expect(html.contains("⚠️") && html.contains("var(--yellow-bg)") && html.contains("<aside class=\"callout\" data-block"), "HTML export shows the alert's look without claiming a picked colour")
    }

    @Test func copiedHtmlDistinguishesTheAlertDefaultsFromExplicitStyle() {
        let fragment = NotePageHTML.fragment([callout(alert: "WARNING")])
        #expect(fragment.contains("data-default-icon") && !fragment.contains("data-color") && !fragment.contains("data-icon="), "copied callouts mark alert defaults so pasting doesn't adopt them")
    }
}
