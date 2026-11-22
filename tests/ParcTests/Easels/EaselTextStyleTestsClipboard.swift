import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

struct EaselTextStyleTestsClipboard {
    @MainActor @Test(arguments: EaselTextStyle.Family.allCases, EaselTextStyle.Size.allCases)
    func theBundledFamiliesResolveWithoutFallback(_ family: EaselTextStyle.Family, _ size: EaselTextStyle.Size) {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let style = EaselTextStyle(family: family, size: size)
        let font = EaselTextAppearance.font(style)
        if family != .clean { #expect(!font.fontName.hasPrefix("."), "Bundled family resolves without system fallback: \(family)/\(size)") }
    }

    @MainActor @Test(arguments: EaselTextStyle.Family.allCases, EaselTextStyle.Size.allCases)
    func privateClipboardPreservesThePaletteStyle(_ family: EaselTextStyle.Family, _ size: EaselTextStyle.Size) throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let style = EaselTextStyle(family: family, size: size)
        let payload = EaselStyledText(text: "Selected 👩🏽‍💻 café\nsecond line", style: style, color: "#194B93")
        try payload.write(to: board)
        #expect(try! EaselStyledText.read(from: board) == payload, "Private clipboard preserves exact text/style/color")
    }

    @MainActor @Test(arguments: EaselTextStyle.Family.allCases, EaselTextStyle.Size.allCases)
    func plainClipboardPreservesUnicode(_ family: EaselTextStyle.Family, _ size: EaselTextStyle.Size) throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let style = EaselTextStyle(family: family, size: size)
        let payload = EaselStyledText(text: "Selected 👩🏽‍💻 café\nsecond line", style: style, color: "#194B93")
        try payload.write(to: board)
        #expect(board.string(forType: .string) == payload.text, "Plain-text representation preserves Unicode")
    }

    @MainActor @Test(arguments: EaselTextStyle.Family.allCases, EaselTextStyle.Size.allCases)
    func rtfClipboardPreservesUnicodeAndNativeFont(_ family: EaselTextStyle.Family, _ size: EaselTextStyle.Size) throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let style = EaselTextStyle(family: family, size: size)
        let payload = EaselStyledText(text: "Selected 👩🏽‍💻 café\nsecond line", style: style, color: "#194B93")
        try payload.write(to: board)
        let rtf = board.data(forType: .rtf)!
        board.clearContents(); board.setData(rtf, forType: .rtf)
        let imported = try EaselStyledText.read(from: board)!
        let decoded = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        #expect(imported.text == payload.text, "RTF preserves Unicode for every palette style")
        #expect(try! EaselRichTextCodec.snapshot(imported.attributed) == EaselRichTextCodec.snapshot(decoded), "RTF preserves the actual exported font, including AppKit system-font substitution")
    }

    @MainActor @Test
    func mixedRtfFontsKeepTheirRanges() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let base = EaselTextAppearance.attributed("One two", style: .init(), color: "#252525")
        let mixed = NSMutableAttributedString(attributedString: base)
        mixed.addAttribute(.font, value: EaselTextAppearance.font(.init(family: .fancy, size: .h2)), range: NSRange(location: 4, length: 3))
        try EaselTextStyleTestsSupport.setRTF(mixed, on: board)
        let importedMixed = try EaselStyledText.read(from: board)!
        #expect(importedMixed.richText?.runs.count == 2, "Mixed fonts import as real range attributes")
        #expect((importedMixed.attributed.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)?.pointSize == 28, "Second font range keeps its size")
    }

    @MainActor @Test
    func plainPasteExtractsWordsFromRtfOnly() throws {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let base = EaselTextAppearance.attributed("One two", style: .init(), color: "#252525")
        let mixed = NSMutableAttributedString(attributedString: base)
        mixed.addAttribute(.font, value: EaselTextAppearance.font(.init(family: .fancy, size: .h2)), range: NSRange(location: 4, length: 3))
        try EaselTextStyleTestsSupport.setRTF(mixed, on: board)
        #expect(try! EaselStyledText.plainText(from: board) == base.string, "Explicit plain-text paste extracts words from clipboard populated with RTF only")
    }

    @MainActor @Test
    func rtfLinkKeepsTheSelectedRange() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let base = EaselTextAppearance.attributed("One two", style: .init(), color: "#252525")
        let linked = NSMutableAttributedString(attributedString: base)
        linked.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 0, length: 3))
        try EaselTextStyleTestsSupport.setRTF(linked, on: board)
        let importedLink = try EaselStyledText.read(from: board)!
        #expect(importedLink.richText?.runs.first?.attributes.link == "https://example.com", "Link range semantics survive RTF import")
    }

    @MainActor @Test
    func rtfKeepsParagraphIndent() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let base = EaselTextAppearance.attributed("One two", style: .init(), color: "#252525")
        let spaced = NSMutableAttributedString(attributedString: base)
        let paragraph = NSMutableParagraphStyle(); paragraph.firstLineHeadIndent = 20
        spaced.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: spaced.length))
        try EaselTextStyleTestsSupport.setRTF(spaced, on: board)
        #expect(try! EaselStyledText.read(from: board)?.richText?.runs.first?.attributes.paragraph?.firstIndent == 20, "Paragraph indentation survives RTF")
    }

    @MainActor @Test
    func rtfKeepsCustomTabAlignment() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let base = EaselTextAppearance.attributed("One two", style: .init(), color: "#252525")
        let spaced = NSMutableAttributedString(attributedString: base)
        let paragraph = NSMutableParagraphStyle(); paragraph.firstLineHeadIndent = 20
        spaced.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: spaced.length))
        paragraph.firstLineHeadIndent = 0; paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 90)]
        spaced.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: spaced.length))
        try EaselTextStyleTestsSupport.setRTF(spaced, on: board)
        #expect(try! EaselStyledText.read(from: board)?.richText?.runs.first?.attributes.paragraph?.tabs.first?.alignment == NSTextAlignment.right.rawValue, "Custom tab alignment survives RTF")
    }

    @MainActor @Test
    func privateClipboardPreservesListMetadata() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let base = EaselTextAppearance.attributed("One two", style: .init(), color: "#252525")
        let spaced = NSMutableAttributedString(attributedString: base)
        let paragraph = NSMutableParagraphStyle(); paragraph.firstLineHeadIndent = 20
        spaced.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: spaced.length))
        let list = NSTextList(markerFormat: .decimal, options: 0); list.startingItemNumber = 3
        paragraph.textLists = [list]; spaced.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: spaced.length))
        let listed = try EaselStyledText.capture(spaced, style: .init(), color: "#252525")
        try listed.write(to: board)
        #expect(try! EaselStyledText.read(from: board) == listed, "Private carrier preserves list marker and start metadata exactly")
    }

    @MainActor @Test
    func anActiveLinkSchemeIsRefused() throws {
        let base = EaselTextAppearance.attributed("One two", style: .init(), color: "#252525")
        let unsafe = NSMutableAttributedString(attributedString: base)
        unsafe.addAttribute(.link, value: "javascript:alert(1)", range: NSRange(location: 0, length: 3))
        #expect(throws: (any Error).self, "active scheme is not imported as an actionable link") { _ = try EaselStyledText.capture(unsafe, style: .init(), color: "#252525") }
    }

    @MainActor @Test
    func anUnknownAttachmentIsRefused() throws {
        let base = EaselTextAppearance.attributed("One two", style: .init(), color: "#252525")
        let unsafe = NSMutableAttributedString(attributedString: base)
        unsafe.addAttribute(.attachment, value: NSTextAttachment(), range: NSRange(location: 0, length: 1))
        #expect(throws: (any Error).self, "attachments are never silently flattened") { _ = try EaselStyledText.capture(unsafe, style: .init(), color: "#252525") }
    }

    @MainActor @Test
    func plainTextHasNoRichClipboardPayload() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("plain", forType: .string)
        #expect(try! EaselStyledText.read(from: board) == nil, "Plain-text fallback stays with canvas")
    }

    @MainActor @Test
    func malformedPrivatePayloadCannotFallBackToPlainText() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("plain", forType: .string)
        board.setData(Data("bad json".utf8), forType: EaselStyledText.pasteboardType)
        #expect(throws: (any Error).self, "damaged private payload must not silently flatten") { _ = try EaselStyledText.read(from: board) }
    }

    @MainActor @Test
    func legacyPrivateTextLoadsWithoutInventingRanges() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let legacy = EaselStyledText(version: 1, text: "Old styled text", style: .init(family: .mono, size: .h2), color: "#194B93")
        board.clearContents(); board.setData(try JSONEncoder().encode(legacy), forType: EaselStyledText.legacyPasteboardType)
        let restoredLegacy = try EaselStyledText.read(from: board)!
        #expect(restoredLegacy.version == 3 && restoredLegacy.text == legacy.text && restoredLegacy.style == legacy.style && restoredLegacy.richText == nil, "Old private clipboard data remains readable without invented ranges")
    }
}
