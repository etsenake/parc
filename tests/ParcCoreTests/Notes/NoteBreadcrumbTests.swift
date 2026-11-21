import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteBreadcrumbTests {
    func make(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("# Hi\n".utf8).write(to: url)
    }

    func places(notes: URL?, home: URL, volume: String = "Disk") -> NoteBreadcrumbPlaces {
        NoteBreadcrumbPlaces(notesFolder: notes, home: home, volume: { _ in (URL(fileURLWithPath: "/", isDirectory: true), volume) },
                             displayName: { $0.lastPathComponent })
    }

    func trails(in root: URL) {
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        let lisbon = notes.appendingPathComponent("Trips/Food/Lisbon.md")
        let inbox = notes.appendingPathComponent("Inbox.md")
        let readme = root.appendingPathComponent("Code/Project/README.md")
        make(lisbon)
        make(inbox)
        make(readme)

        let deep = NoteBreadcrumb.trail(for: lisbon, places: places(notes: notes, home: root))
        #expect(deep.map(\.kind) == [.notes, .folder, .folder, .note], "a note in the Notes folder starts at the Notes folder: \(deep.map(\.kind))")
        #expect(deep.map(\.name) == ["Notes", "Trips", "Food", "Lisbon"], "every folder on the way is named, then the note: \(deep.map(\.name))")
        #expect(deep[2].url.path == NoteFilePaths.canonical(notes.appendingPathComponent("Trips/Food")).path, "each folder links to itself")
        #expect(deep.dropLast().allSatisfy { $0.isFolder } && !deep.last!.isFolder, "only the note itself isn't a folder")
        #expect(NoteBreadcrumb.text(of: deep) == "Notes / Trips / Food / Lisbon", "the trail reads as a path")

        let top = NoteBreadcrumb.trail(for: inbox, places: places(notes: notes, home: root))
        #expect(top.map(\.name) == ["Notes", "Inbox"], "a note at the top of the Notes folder sits right under it")

        let elsewhere = NoteBreadcrumb.trail(for: readme, places: places(notes: notes, home: root))
        #expect(elsewhere.map(\.kind) == [.home, .folder, .folder, .note], "a note elsewhere in the home folder starts at home")
        #expect(elsewhere.map(\.name) == [root.lastPathComponent, "Code", "Project", "README"], "and walks down from there: \(elsewhere.map(\.name))")

        let away = NoteBreadcrumb.trail(for: readme, places: places(notes: nil, home: root.appendingPathComponent("Nobody")))
        let components = NoteFilePaths.canonical(readme).deletingLastPathComponent().pathComponents
        #expect(away.first?.kind == .volume && away.first?.name == "Disk", "a note outside home starts at its volume")
        #expect(away.count == components.count + 1, "every folder below the volume shows up: \(away.map(\.name))")
        #expect(away.last?.name == "README" && away[1].name == components[1], "from the first folder down to the note")

        let link = root.appendingPathComponent("Shortcut", isDirectory: true)
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: notes)
        let linked = NoteBreadcrumb.trail(for: link.appendingPathComponent("Trips/Food/Lisbon.md"), places: places(notes: link, home: root))
        #expect(linked.map(\.name) == ["Notes", "Trips", "Food", "Lisbon"], "symlinked folders resolve to the real path: \(linked.map(\.name))")

        #expect(NoteBreadcrumb.title(of: URL(fileURLWithPath: "/tmp/Plan.md")) == "Plan", "the note's name drops its extension")
        #expect(NoteBreadcrumb.title(of: URL(fileURLWithPath: "/tmp/ .md")) == "Untitled", "a blank name reads Untitled")
    }

    func browsing(in root: URL) {
        let folder = root.appendingPathComponent("Browse", isDirectory: true)
        make(folder.appendingPathComponent("Top.md"))
        make(folder.appendingPathComponent("Deeper/Inner.md"))
        let shallow = NoteLibrary.browsing(folder)
        #expect(!shallow.isRecursive, "browsing a folder outside the Notes folder lists only that folder")
        #expect(NoteLibrary.browsing(folder) === shallow, "the same folder reuses its listing")
        #expect(shallow.contains(folder.appendingPathComponent("Top.md")) && !shallow.contains(folder.appendingPathComponent("Deeper/Inner.md")), "and leaves subfolders out")
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        let space = NoteLibrary.shared(folder: notes)
        #expect(NoteLibrary.browsing(notes) === space, "a folder that already has a full listing reuses it")
    }

    @Test func parcBreadcrumbReadsAsABreadcrumb() {
        let page = NoteMarkdown.parse("Intro\n\n<!-- parc breadcrumb -->\n\nAfter\n")
        #expect(page.blocks.map(\.kind) == [.paragraph, .breadcrumb, .paragraph], "<!-- parc breadcrumb --> reads as a breadcrumb: \(page.blocks.map(\.kind))")
        #expect(NoteMarkdown.serialize(page) == "Intro\n\n<!-- parc breadcrumb -->\n\nAfter\n", "and writes back byte for byte: \(NoteMarkdown.serialize(page))")
    }

    @Test func colourAndBlockLinkRideInTheSameComment() {
        var colored = NoteBlock(.breadcrumb)
        colored.color = .text(.gray)
        colored.props.anchor = "k3x9qa"
        let written = NoteMarkdown.serialize(NotePage(blocks: [colored, .paragraph("Body")]))
        #expect(written.hasPrefix("<!-- parc breadcrumb color=\"gray\" id=\"k3x9qa\" -->\n"), "colour and block link ride in the same comment: \(written)")
        let read = NoteMarkdown.parse(written)
        #expect(read.blocks.first?.kind == .breadcrumb && read.blocks.first?.color == .text(.gray) && read.blocks.first?.props.anchor == "k3x9qa", "and come back")
        #expect(read.blocks.count == 2 && read.blocks[1].text.plainText == "Body", "the next block stays itself")
    }

    @Test func aBreadcrumbRightUnderALineIsStillA() {
        let tight = NoteMarkdown.parse("Intro\n<!-- parc breadcrumb -->\n")
        #expect(tight.blocks.map(\.kind) == [.paragraph, .breadcrumb], "a breadcrumb right under a line is still a breadcrumb, not that line's setting")
        #expect(tight.blocks[0].color == nil, "and the line keeps its own look")
    }

    @Test func aBreadcrumbInsideAToggleSurvivesASave() {
        let toggle = NoteBlock(.toggle, text: "Where", children: [NoteBlock(.breadcrumb), .paragraph("x")])
        let nested = NoteMarkdown.parse(NoteMarkdown.serialize(NotePage(blocks: [toggle])))
        #expect(nested.blocks.first?.children.map(\.kind) == [.breadcrumb, .paragraph], "a breadcrumb inside a toggle survives a save")
        let bullet = NoteBlock(.bulletedItem, text: "Item", children: [NoteBlock(.breadcrumb)])
        let listed = NoteMarkdown.parse(NoteMarkdown.serialize(NotePage(blocks: [bullet])))
        #expect(listed.blocks.first?.children.map(\.kind) == [.breadcrumb], "and inside a list item")
        let lone = NoteMarkdown.parse(NoteMarkdown.serialize(NotePage(blocks: [NoteBlock(.breadcrumb)])))
        #expect(lone.blocks.map(\.kind) == [.breadcrumb], "a note that's only a breadcrumb stays one")
        #expect(NoteMarkdown.parse("Hello <!-- parc breadcrumb -->\n").blocks.map(\.kind) == [.paragraph], "a flag at the end of a line doesn't swallow the line")
        #expect(NoteMarkdown.parse("<!-- toc -->\n").blocks.map(\.kind) == [.tableOfContents], "the table of contents still reads as before")
        #expect(NoteBlockKind.breadcrumb.supportsColor && !NoteBlockKind.breadcrumb.hasText && !NoteBlockKind.breadcrumb.acceptsChildren, "breadcrumbs take a colour but no text or children")
    }

    @Test func html() {
        let trail = [
            NoteBreadcrumbSegment(kind: .notes, name: "Notes", url: URL(fileURLWithPath: "/n", isDirectory: true)),
            NoteBreadcrumbSegment(kind: .folder, name: "Trips & Food", url: URL(fileURLWithPath: "/n/t", isDirectory: true)),
            NoteBreadcrumbSegment(kind: .note, name: "Lisbon", url: URL(fileURLWithPath: "/n/t/Lisbon.md")),
        ]
        var block = NoteBlock(.breadcrumb)
        block.color = .background(.blue)
        let fragment = NotePageHTML.fragment([block], breadcrumb: trail)
        #expect(fragment.contains("data-block=\"breadcrumb\"") && fragment.contains("Trips &amp; Food") && fragment.contains("aria-current=\"page\">Lisbon"), "copied HTML spells out the path: \(fragment)")
        let back = NoteHTMLReader.blocks(from: fragment, baseURL: nil)
        #expect(back.map(\.kind) == [.breadcrumb] && back.first?.color == .background(.blue), "pasting it back makes a breadcrumb with its colour: \(back.map(\.kind))")
        let document = NotePageHTML.document(NotePage(blocks: [block]), title: "Lisbon", assets: { _ in nil }, embedImages: false, breadcrumb: trail)
        #expect(document.contains("class=\"breadcrumb block-color-") && document.contains("nav.breadcrumb"), "exports style the breadcrumb")
        #expect(NotePageHTML.fragment([NoteBlock(.breadcrumb)]).contains("<ol></ol>"), "with no path known the list is just empty")
    }

    @Test func trails() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-breadcrumb-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        trails(in: root)
    }

    @Test func browsing() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-breadcrumb-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        browsing(in: root)
    }
}
