import Foundation

@main @MainActor
struct NoteFileCodecTests {
    static func main() {
        exitOnFailure {
            encodings()
            lineEndings()
            trailingNewlines()
            naming()
            paths()
            identities()
            summaries()
            reconciling()
            print("NoteFileCodecTests passed")
        }
    }

    static func roundTrip(_ bytes: [UInt8], kind: NoteFileKind = .plainText) -> NoteFileContents {
        guard let contents = NoteFileText.decode(Data(bytes), kind: kind) else { failTest("could not decode \(bytes)") }
        let encoded = NoteFileText.encode(contents.text, format: contents.format)
        expectEqual([UInt8](encoded.data), bytes, "encoding writes the same bytes back")
        expectEqual(encoded.format, contents.format, "the format survives a round trip")
        return contents
    }

    static func encodings() {
        let plain = roundTrip(Array("café\n".utf8))
        expectEqual(plain.text, "café\n", "UTF-8 decodes")
        expectEqual(plain.format, NoteFileFormat(encoding: .utf8, byteOrderMark: false, lineEnding: .lf, endsWithNewline: true), "UTF-8 format")

        let marked = roundTrip([0xEF, 0xBB, 0xBF] + Array("hi".utf8))
        expectEqual(marked.text, "hi", "the UTF-8 BOM isn't part of the text")
        expect(marked.format.byteOrderMark && marked.format.encoding == .utf8, "the UTF-8 BOM is remembered")

        let little = roundTrip([0xFF, 0xFE] + Array("añ\r\n".data(using: .utf16LittleEndian)!))
        expectEqual(little.text, "añ\r\n", "UTF-16 LE with a BOM decodes")
        expect(little.format.encoding == .utf16LittleEndian && little.format.byteOrderMark, "UTF-16 LE is remembered")
        expectEqual(little.format.lineEnding, .crlf, "UTF-16 CRLF is detected")

        let big = roundTrip([0xFE, 0xFF] + Array("✓ ok".data(using: .utf16BigEndian)!))
        expectEqual(big.text, "✓ ok", "UTF-16 BE with a BOM decodes")
        expect(big.format.encoding == .utf16BigEndian, "UTF-16 BE is remembered")

        let wide = roundTrip([0xFF, 0xFE, 0x00, 0x00] + Array("🙂".data(using: .utf32LittleEndian)!))
        expectEqual(wide.text, "🙂", "UTF-32 LE with a BOM decodes")

        let unmarked = roundTrip(Array("hello there\n".data(using: .utf16LittleEndian)!))
        expectEqual(unmarked.text, "hello there\n", "unmarked UTF-16 LE is sniffed")
        expect(unmarked.format.encoding == .utf16LittleEndian && !unmarked.format.byteOrderMark, "unmarked UTF-16 stays unmarked")

        let legacy = roundTrip([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94])
        expectEqual(legacy.text, "café “q”", "Windows Latin 1 is the legacy fallback")
        expectEqual(legacy.format.encoding, .windowsCP1252, "the legacy encoding is remembered")

        let latin = roundTrip([0x41, 0x81, 0x42])
        expectEqual(latin.format.encoding, .isoLatin1, "bytes CP1252 can't map fall back to ISO Latin 1")
        expectEqual(latin.text.unicodeScalars.map(\.value), [0x41, 0x81, 0x42], "ISO Latin 1 keeps every byte")

        expect(NoteFileText.decode(Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x1A, 0x00, 0x00, 0x7F, 0x00]), kind: .markdown) == nil,
               "binary data isn't text")
        let empty = NoteFileText.decode(Data(), kind: .markdown)
        expectEqual(empty?.text, "", "an empty file decodes")
        expectEqual(empty?.format.endsWithNewline, true, "an empty Markdown file will end with a newline once written")
        expectEqual(NoteFileText.decode(Data(), kind: .plainText)?.format.endsWithNewline, false, "an empty text file stays bare")

        var upgraded = legacy.format
        let encoded = NoteFileText.encode("café 🙂", format: upgraded)
        upgraded = encoded.format
        expectEqual(upgraded.encoding, .utf8, "text the legacy encoding can't hold upgrades to UTF-8")
        expectEqual(String(decoding: encoded.data, as: UTF8.self), "café 🙂", "nothing is lost in the upgrade")
    }

    static func lineEndings() {
        expectEqual(NoteFileText.lineEnding(of: "a\nb\n"), .lf, "LF")
        expectEqual(NoteFileText.lineEnding(of: "a\r\nb\r\n"), .crlf, "CRLF")
        expectEqual(NoteFileText.lineEnding(of: "a\rb\r"), .cr, "CR")
        expectEqual(NoteFileText.lineEnding(of: "a\r\nb\r\nc\n"), .crlf, "the majority wins")
        expectEqual(NoteFileText.lineEnding(of: "one line"), nil, "no line breaks, no opinion")
        expectEqual(NoteFileText.normalizedLineEndings("a\r\nb\rc\n"), "a\nb\nc\n", "everything normalizes to LF")
    }

    static func trailingNewlines() {
        func plain(_ text: String) {
            let contents = NoteFileText.decode(Data(text.utf8), kind: .plainText)!
            let editable = NoteFileText.editableText(contents, kind: .plainText)
            let page = NotePlainText.parse(editable)
            let written = NoteFileText.fileText(NotePlainText.serialize(page), format: contents.format, kind: .plainText)
            expectEqual(written, text, "plain text round-trips exactly")
        }
        for sample in ["a\nb\n", "a\nb", "a\n\n", "\n", "", "a\r\nb\r\n", "x\r\n\r\n", "tabs\tand  spaces  \n"] { plain(sample) }
        let contents = NoteFileText.decode(Data("a\nb\n".utf8), kind: .plainText)!
        expectEqual(NoteFileText.editableText(contents, kind: .plainText), "a\nb", "the final newline isn't an empty paragraph")

        let crlf = NoteFileFormat(encoding: .utf8, byteOrderMark: false, lineEnding: .crlf, endsWithNewline: true)
        expectEqual(NoteFileText.fileText("# Hi\n\nThere\n\n\n", format: crlf, kind: .markdown), "# Hi\r\n\r\nThere\r\n",
                    "Markdown keeps one final newline and the file's line endings")
        var bare = crlf
        bare.endsWithNewline = false
        expectEqual(NoteFileText.fileText("# Hi\n", format: bare, kind: .markdown), "# Hi", "a file without a final newline stays that way")
        expectEqual(NoteFileText.fileText("\n\n", format: .standard, kind: .markdown), "", "an empty page writes an empty file")
    }

    static func naming() {
        expectEqual(NoteFileNaming.sanitizedTitle("  Plans/ideas: 2027  "), "Plans-ideas- 2027", "slashes and colons are swapped out")
        expectEqual(NoteFileNaming.sanitizedTitle("..hidden"), "hidden", "leading dots go")
        expectEqual(NoteFileNaming.sanitizedTitle(". . .dots"), "dots", "dots and spaces at the front go")
        expectEqual(NoteFileNaming.sanitizedTitle("line\none\ttab\u{0007}"), "line one tab", "newlines and tabs become spaces, controls vanish")
        expectEqual(NoteFileNaming.sanitizedTitle("   "), "", "whitespace-only names are empty")
        expectEqual(NoteFileNaming.sanitizedTitle("👩‍💻 Work"), "👩‍💻 Work", "emoji sequences survive")
        let long = String(repeating: "é", count: 300)
        let name = NoteFileNaming.fileName(base: long, pathExtension: "md")
        expect(name.utf8.count <= NoteFileNaming.maximumComponentBytes, "long names fit in 255 bytes")
        expect(name.hasSuffix(".md"), "the extension survives truncation")
        expect(NoteFileNaming.fileName(base: long, pathExtension: "md", suffix: " 12").hasSuffix("é 12.md"), "suffixes fit too")
        expect(NoteFileNaming.isUntitled("Untitled") && NoteFileNaming.isUntitled("Untitled 12"), "untitled names are spotted")
        expect(!NoteFileNaming.isUntitled("Untitled plan") && !NoteFileNaming.isUntitled("Untitled "), "other names aren't untitled")
        expectEqual(NoteFileNaming.sanitizedExtension(".PNG"), "png", "extensions are tidied")

        let folder = URL(fileURLWithPath: "/notes", isDirectory: true)
        let taken: Set<String> = ["/notes/Untitled.md", "/notes/Untitled 2.md"]
        expectEqual(NoteFileNaming.uniqueURL(in: folder, base: "Untitled", pathExtension: "md") { taken.contains($0.path) }.path,
                    "/notes/Untitled 3.md", "unique names count up")

        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 11, 20, 14, 3, 22)
        let date = Calendar(identifier: .gregorian).date(from: components)!
        expectEqual(NoteFileNaming.pastedBaseName(at: date, isImage: true), "Pasted image 2026-11-20 at 14.03.22", "pasted images get dated names")
        expectEqual(NoteFileNaming.pastedBaseName(at: date, isImage: false), "Pasted file 2026-11-20 at 14.03.22", "pasted files too")
    }

    static func paths() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        let deep = folder.appendingPathComponent("Sub/Deeper", isDirectory: true)
        try! FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        expectEqual(NoteFilePaths.relativePath(from: folder, to: folder.appendingPathComponent("My Note.md")), "My%20Note.md",
                    "siblings link by encoded name")
        expectEqual(NoteFilePaths.relativePath(from: deep, to: folder.appendingPathComponent("Up (1).md")), "../../Up%20%281%29.md",
                    "parents link with ../ and encoded parentheses")
        expectEqual(NoteFilePaths.relativePath(from: folder, to: deep.appendingPathComponent("Café #2.md")), "Sub/Deeper/Café%20%232.md",
                    "children keep readable letters")
        expectEqual(NoteFilePaths.relativePath(from: URL(fileURLWithPath: "/Users/a"), to: URL(fileURLWithPath: "/Volumes/Disk/x.md")), nil,
                    "different roots don't get relative links")
        expectEqual(NoteFilePaths.encodedSegment("a b:c?d\u{00A0}e"), "a%20b%3Ac%3Fd%C2%A0e", "reserved and invisible characters are encoded")

        let unresolved = URL(fileURLWithPath: "/private/var/../var/nothing-here/x.md")
        expectEqual(NoteFilePaths.canonical(unresolved).path, "/private/var/nothing-here/x.md", "missing paths canonicalize their existing prefix")
        let viaVar = URL(fileURLWithPath: folder.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        expectEqual(NoteFilePaths.canonical(viaVar).path, folder.path, "symlinked prefixes resolve")

        expect(NoteFilePaths.contains(folder: folder, item: deep.appendingPathComponent("n.md")), "nested items are inside")
        expect(!NoteFilePaths.contains(folder: folder, item: folder), "the folder isn't inside itself")
        expect(!NoteFilePaths.contains(folder: deep, item: folder.appendingPathComponent("n.md")), "parents aren't inside children")
        expect(!NoteFilePaths.contains(folder: folder.appendingPathComponent("Sub"), item: folder.appendingPathComponent("Subway/n.md")),
               "a shared prefix isn't containment")
        expect(NoteFilePaths.isInTrash(URL(fileURLWithPath: "/Users/me/.Trash/n.md")), "the Trash is spotted")
        expect(!NoteFilePaths.isInTrash(folder.appendingPathComponent("n.md")), "ordinary folders aren't the Trash")
    }

    static func identities() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        let plan = NoteFileTestSupport.write("plan\n", to: real.appendingPathComponent("Plan.md"))
        let link = folder.appendingPathComponent("Linked", isDirectory: true)
        try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let viaVar = URL(fileURLWithPath: plan.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        let viaLink = link.appendingPathComponent("Plan.md")
        let viaData = URL(fileURLWithPath: "/System/Volumes/Data" + plan.path)
        expectEqual(NoteFilePaths.canonical(viaLink).path, plan.path, "a symlinked folder resolves to the real file")
        expectEqual(NoteFilePaths.canonical(viaData).path, plan.path, "the firmlinked Data volume path is the same file")
        expect(NoteFilePaths.sameItem(plan, viaVar) && NoteFilePaths.sameItem(plan, viaLink) && NoteFilePaths.sameItem(plan, viaData),
               "every spelling of one file is one item")
        expectEqual(Set([plan, viaVar, viaLink, viaData].map(NoteFilePaths.key(for:))).count, 1, "and has one identity key")
        expect(!NoteFilePaths.sameItem(plan, real.appendingPathComponent("Other.md")), "different files stay different")

        let caseInsensitive = pathconf(folder.path, _PC_CASE_SENSITIVE) == 0
        if caseInsensitive {
            let shouted = real.appendingPathComponent("PLAN.md")
            expectEqual(NoteFilePaths.canonical(shouted).lastPathComponent, "Plan.md", "the canonical path takes the case on disk")
            expect(NoteFilePaths.sameItem(plan, shouted), "a different case names the same file")
            let ghost = real.appendingPathComponent("Ghost.md"), whisper = link.appendingPathComponent("ghost.MD")
            expect(NoteFilePaths.sameItem(ghost, whisper), "files that don't exist yet still match across case and symlinks")
            expectEqual(NoteFilePaths.key(for: ghost), NoteFilePaths.key(for: whisper), "with one key")
            let before = NoteFilePaths.key(for: plan)
            try! FileManager.default.removeItem(at: plan)
            expectEqual(NoteFilePaths.key(for: shouted), before, "a deleted file keeps the key it had while it existed")
            NoteFileTestSupport.write("plan\n", to: plan)
        }

        let archive = folder.appendingPathComponent("Archive.md", isDirectory: true)
        try! FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        expect(!NoteFilePaths.isOpenableFile(archive), "a folder named like a note isn't a note")
        expect(!NoteFilePaths.isOpenableFile(real.appendingPathComponent("Nope.md")), "a missing file isn't openable")
        expect(NoteFilePaths.isOpenableFile(viaLink), "a real file through a symlink is")
    }

    static func summaries() {
        let note = """
        ---
        icon: "🚀"
        tags: [a, b]
        ---
        # Launch plan

        - [ ] Book the **venue** for [the party](https://example.com)
        > [!NOTE]
        > Bring snake_case_names and `code`
        ![photo](Attachments/a.png)
        """
        let summary = NoteFileSummary.make(fromHead: note, kind: .markdown)
        expectEqual(summary.icon, "🚀", "the icon comes from front matter")
        expectEqual(summary.snippet, "Launch plan Book the venue for the party Bring snake_case_names and code",
                    "snippets drop Markdown syntax")
        expectEqual(NoteFileSummary.make(fromHead: "---\nicon: 'It''s'\n---\nBody", kind: .markdown).icon, "It's", "single-quoted icons unescape")
        expectEqual(NoteFileSummary.make(fromHead: "---\nicon: 📚 # books\n---\n", kind: .markdown).icon, "📚", "trailing YAML comments go")
        expectEqual(NoteFileSummary.make(fromHead: "---\n  icon: x\ntitle: y\n", kind: .markdown).icon, nil, "unterminated front matter has no icon")
        expectEqual(NoteFileSummary.make(fromHead: "---\nicon: x\n---\nhi", kind: .plainText).snippet, "--- icon: x --- hi", "text files are verbatim")
        expectEqual(NoteFileSummary.make(fromHead: "# Testing 123&#32;\nTom &amp; Jerry&#9;", kind: .markdown).snippet, "Testing 123 Tom & Jerry",
                    "character references show as the characters they stand for")
        expectEqual(NoteFileSummary.make(fromHead: "\\&amp; and &lt;b&gt;", kind: .markdown).snippet, "&amp; and <b>",
                    "an escaped ampersand stays literal")
        expectEqual(NoteFileSummary.make(fromHead: "<!-- parc synced from=\"Josh%E2%80%99s.md#a\" -->\nShared words\n<!-- /parc synced -->\nAfter",
                                         kind: .markdown).snippet, "Shared words After", "synced block markers stay out of previews")
        expectEqual(NoteFileSummary.make(fromHead: "Before <!-- a\nhidden\nlines --> after", kind: .markdown).snippet,
                    "Before after", "comments spanning lines stay out of previews")
        let long = NoteFileSummary.make(fromHead: String(repeating: "word ", count: 100), kind: .markdown).snippet
        expect(long.count <= NoteFileSummary.snippetLength + 1 && long.hasSuffix("…"), "long snippets are clipped")
        expectEqual(NoteFileSummary.make(fromHead: "```swift\nlet x = 1\n```\n| a | b |\n|---|---|", kind: .markdown).snippet,
                    "let x = 1 a b", "code and tables read as text")
    }

    static func reconciling() {
        let a = NoteBlock.paragraph("Alpha"), b = NoteBlock.paragraph("Beta"), c = NoteBlock.paragraph("Gamma")
        let old = NotePage(blocks: [a, b, c])
        let fresh = NotePage(blocks: [.paragraph("Alpha"), .paragraph("Beta, edited"), .paragraph("New"), .paragraph("Gamma")])
        let merged = NoteFileReconciler.preservingIdentity(of: old, in: fresh)
        expectEqual(merged.blocks[0].id, a.id, "unchanged blocks keep their identity")
        expectEqual(merged.blocks[1].id, b.id, "an edited block in the same spot keeps its identity")
        expectEqual(merged.blocks[3].id, c.id, "blocks after an insertion keep their identity")
        expect(Set(merged.blocks.map(\.id)).count == 4, "identities stay unique")
        expectEqual(merged.blocks.map(\.text.string), ["Alpha", "Beta, edited", "New", "Gamma"], "the new content wins")

        let caret = NoteFileReconciler.mapSelection(.caret(NotePosition(b.id, 4)), from: old, to: merged)
        expectEqual(caret, .caret(NotePosition(b.id, 4)), "the caret stays in its block")
        let clamped = NoteFileReconciler.mapSelection(.caret(NotePosition(c.id, 5)), from: old,
                                                      to: NotePage(blocks: [merged.blocks[0], NoteBlock(.paragraph, text: "Ga", id: c.id)]))
        expectEqual(clamped, .caret(NotePosition(c.id, 2)), "the caret clamps to shorter text")
        let gone = NoteFileReconciler.mapSelection(.caret(NotePosition(c.id, 3)), from: old, to: NotePage(blocks: [.paragraph("Only")]))
        expectEqual(gone.caret?.offset, 3, "a vanished block hands the caret to its neighbour")
        expectEqual(NoteFileReconciler.mapSelection(.blocks([a.id, c.id]), from: old, to: NotePage(blocks: [a])), .blocks([a.id]),
                    "block selections keep the survivors")
    }
}
