import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitPaneMenuLinksTests {
    private static let links = [FolderLinks.Link(tabID: UUID(), title: "Fish & <Chips>", url: "https://one.invalid/a?b=1&c=2"),
                                FolderLinks.Link(tabID: UUID(), title: "", url: "https://two.invalid/")]

    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("parc-split-links-" + UUID().uuidString))
    }

    @Test func copyLinksWritesThePasteboard() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        #expect(LinkPasteboard.write(Self.links, format: .plain, to: pasteboard))
    }

    @Test func plainTextTargetsGetOneBareAddressPerLineInOrder() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        _ = LinkPasteboard.write(Self.links, format: .plain, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "https://one.invalid/a?b=1&c=2\nhttps://two.invalid/")
    }

    @Test func richTextTargetsGetEachTitleLinkedToItsAddress() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        _ = LinkPasteboard.write(Self.links, format: .plain, to: pasteboard)
        #expect(pasteboard.string(forType: .html) == "<meta charset=\"utf-8\"><a href=\"https://one.invalid/a?b=1&amp;c=2\">Fish &amp; &lt;Chips&gt;</a><br>\n"
                + "<a href=\"https://two.invalid/\">https://two.invalid/</a>")
    }

    @Test func markdownCopiesStayMarkdownOnly() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        #expect(LinkPasteboard.write(Self.links, format: .markdown, to: pasteboard))
        #expect(pasteboard.types?.contains(.html) == false)
        #expect(pasteboard.string(forType: .string)?.hasPrefix("[Fish & \\<Chips>](<https://one.invalid/a?b=1&c=2>)") == true)
    }

    @Test func nothingToCopyLeavesThePasteboardAlone() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        _ = LinkPasteboard.write(Self.links, format: .plain, to: pasteboard)
        let count = pasteboard.changeCount
        #expect(!LinkPasteboard.write([], format: .plain, to: pasteboard))
        #expect(pasteboard.changeCount == count)
    }
}
