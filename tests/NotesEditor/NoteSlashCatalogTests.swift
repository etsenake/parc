import Foundation

@main
struct NoteSlashCatalogTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func top(_ query: String, _ context: NoteCatalogContext = .slash) -> String? {
        NoteBlockCatalog.results(for: query, in: context).first?.id
    }

    static func ids(_ query: String, _ context: NoteCatalogContext = .slash) -> [String] {
        NoteBlockCatalog.results(for: query, in: context).map(\.id)
    }

    static func main() {
        let all = NoteBlockCatalog.items + NoteBlockCatalog.turnIntoItems + NoteBlockCatalog.turnIntoMenuItems
        expect(Set(all.map(\.id)).count == all.count, "every catalog id is unique")
        expect(all.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty }, "every item has a title and a short description")

        let unfiltered = NoteBlockCatalog.results(for: "")
        var sections: [NoteCatalogSection] = []
        for item in unfiltered where sections.last != item.section { sections.append(item.section) }
        expect(sections == [.basic, .media, .advanced, .inline], "the empty menu runs Basic, Media, Advanced, then Inline: \(sections)")
        expect(!unfiltered.contains { $0.section == .colors || $0.section == .actions }, "colours and actions wait for a query")
        expect(unfiltered.first?.id == "text" && unfiltered.map(\.id).prefix(4) == ["text", "heading1", "heading2", "heading3"],
               "Text then the headings lead the menu")
        let basic = unfiltered.filter { $0.section == .basic }.map(\.id)
        expect(basic == ["text", "heading1", "heading2", "heading3", "heading4", "bulleted", "numbered", "todo", "toggle",
                         "toggleHeading1", "toggleHeading2", "toggleHeading3", "toggleHeading4", "quote", "callout", "divider", "newNote",
                         "linkToNote", "table"],
               "basic blocks follow Notion's order: \(basic)")
        expect(unfiltered.filter { $0.section == .media }.map(\.id) == ["image", "video", "audio", "file", "bookmark", "embed"], "media order")
        expect(unfiltered.filter { $0.section == .advanced }.map(\.id) == ["tableOfContents", "equation", "code", "columns2", "columns3", "columns4", "columns5"],
               "advanced order")
        expect(unfiltered.filter { $0.section == .inline }.map(\.id) == ["mention", "date", "emoji", "inlineEquation"], "inline order")

        let aliases: [(String, String)] = [
            ("h1", "heading1"), ("#", "heading1"), ("##", "heading2"), ("###", "heading3"), ("h4", "heading4"), ("####", "heading4"),
            ("th4", "toggleHeading4"), ("toggle h4", "toggleHeading4"), ("todo", "todo"), ("[]", "todo"),
            ("ul", "bulleted"), ("ol", "numbered"), ("num", "numbered"), ("img", "image"), ("hr", "divider"), ("div", "divider"),
            ("---", "divider"), ("math", "equation"), ("tex", "equation"), ("latex", "equation"), ("plain", "text"), ("call", "callout"),
            ("book", "bookmark"), ("web", "bookmark"), ("toc", "tableOfContents"), ("red", "color.red"), ("red background", "background.red"),
            ("red b", "background.red"), ("grey", "color.gray"), ("default", "color.default"), ("del", "action.delete"),
            ("dup", "action.duplicate"), ("code", "code"), ("```", "code"), ("quote", "quote"), ("\"", "quote"), (">", "toggle"),
            ("page", "newNote"), ("link", "linkToNote"), ("2 col", "columns2"), ("3col", "columns3"), ("emoji", "emoji"),
            ("mention", "mention"), ("date", "date"), ("remind", "date"), ("inline math", "inlineEquation"), ("th2", "toggleHeading2"),
            ("to-do", "todo"), ("todolist", "todo"), ("bullet", "bulleted"), ("heading 2", "heading2"), ("video", "video"),
        ]
        for (query, expected) in aliases {
            let found = top(query)
            expect(found == expected, "/\(query) puts \(expected) first, got \(found ?? "nothing")")
        }

        expect(ids("h").prefix(8) == ["heading1", "heading2", "heading3", "heading4", "toggleHeading1", "toggleHeading2", "toggleHeading3",
                                      "toggleHeading4"],
               "a lone h lists every heading before anything an alias drags in: \(ids("h").prefix(8))")
        expect(ids("list").prefix(4) == ["bulleted", "numbered", "todo", "toggle"], "list finds every list, in catalog order")
        let back = ids("back")
        expect(back.count == 9 && back.allSatisfy { $0.hasPrefix("background.") }, "/back lists the nine backgrounds: \(back)")
        let colors = ids("color")
        expect(colors.count == 19 && colors.first == "color.default", "/color lists Default plus nine text and nine background colours")
        expect(ids("red").prefix(2) == ["color.red", "background.red"], "/red puts the text colour above the background")
        let tog = ids("tog")
        expect(!tog.isEmpty && tog.allSatisfy { $0.lowercased().contains("toggle") }, "/tog lists only toggles: \(tog)")
        expect(ids("td").contains("todo"), "/td still finds To-do through fuzzy fallback: \(ids("td"))")
        expect(ids("hdg").first == "heading1", "fuzzy subsequences still find headings")
        expect(ids("tbl").first == "table", "fuzzy finds table from tbl")
        expect(ids("zzzz").isEmpty, "nonsense finds nothing")
        expect(ids("x").isEmpty, "a single letter only matches word starts, not anything containing it")

        let turn = ids("turn")
        expect(turn.count == NoteCatalogBlock.turnIntoTargets.count && turn.allSatisfy { $0.hasPrefix("turn.") }, "/turn lists every Turn into")
        expect(top("turnbullet") == "turn.bulleted", "/turnbullet goes straight to Turn into Bulleted list")
        expect(top("turn into h1") == "turn.heading1", "/turn into h1 works")
        expect(top("turn into h4") == "turn.heading4", "/turn into h4 reaches the new heading")
        expect(top("turninto quote") == "turn.quote", "/turninto quote works")
        expect(top("turn callout") == "turn.callout", "/turn callout works")

        expect(!ids("delete", .plus).contains("action.delete"), "the + menu never offers actions on its fresh block")
        expect(ids("red", .plus).first == "color.red", "the + menu still paints colours")
        var nested = NoteCatalogContext.slash
        nested.allowsColumns = false
        expect(!ids("columns", nested).contains { $0.hasPrefix("columns") }, "columns hide inside columns")
        nested.allowsNewNote = false
        expect(!ids("page", nested).contains("newNote"), "New note hides when there's no folder to put it in")

        let menu = NoteBlockCatalog.results(for: "", in: .turnInto)
        expect(menu.map(\.title).prefix(5) == ["Text", "Heading 1", "Heading 2", "Heading 3", "Heading 4"], "Turn into lists plain block names")
        expect(menu.contains { $0.id == "into.toggleHeading4" }, "Turn into offers Toggle heading 4")
        expect(menu.allSatisfy { if case .turnInto = $0.effect { return true } else { return false } }, "Turn into rows only convert")
        expect(NoteBlockCatalog.results(for: "quo", in: .turnInto).first?.id == "into.quote", "Turn into filters too")

        let todo = NoteBlock(.todo)
        expect(NoteCatalogBlock.todo.describes(todo) && !NoteCatalogBlock.text.describes(todo), "templates recognise their blocks")
        var toggleHeading = NoteBlock.heading(2)
        toggleHeading.props.toggleable = true
        expect(NoteCatalogBlock.toggleHeading(2).describes(toggleHeading) && !NoteCatalogBlock.heading(2).describes(toggleHeading),
               "toggle headings and headings stay distinct")
        let columns = NoteCatalogBlock.columns(3).makeBlock()
        expect(columns.kind == .columns && columns.children.count == 3 && columns.children.allSatisfy { $0.kind == .column && $0.children.first?.kind == .paragraph },
               "3 columns builds three columns with an empty paragraph each")
        let callout = NoteCatalogBlock.callout.makeBlock()
        expect(callout.kind == .callout && callout.props.icon != nil, "a fresh callout gets an icon")
        let heading = NoteCatalogBlock.toggleHeading(1).makeBlock()
        expect(heading.kind == .heading && heading.props.toggleable && heading.props.expanded && heading.props.level == 1, "toggle heading 1 is a folding H1")
        let fourth = NoteCatalogBlock.heading(4).makeBlock()
        expect(fourth.kind == .heading && !fourth.props.toggleable && fourth.props.level == 4, "heading 4 is a plain H4")
        let foldingFourth = NoteCatalogBlock.toggleHeading(4).makeBlock()
        expect(foldingFourth.props.toggleable && foldingFourth.props.level == 4, "toggle heading 4 folds")
        print("NoteSlashCatalogTests passed")
    }
}
