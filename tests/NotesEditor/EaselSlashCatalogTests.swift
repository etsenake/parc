import Foundation

@main
struct EaselSlashCatalogTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func ids(_ query: String, _ context: EaselSlashContext = EaselSlashContext()) -> [String] {
        EaselSlashCatalog.results(for: query, in: context).map(\.id)
    }

    static func main() {
        rows()
        searching()
        gating()
        placement()
        print("EaselSlashCatalogTests passed")
    }

    static func rows() {
        let all = EaselSlashCatalog.rows(in: EaselSlashContext(checklist: true, divider: true, mention: true, date: true, inlineEquation: true))
        expect(Set(all.map(\.id)).count == all.count, "Every Easel slash row has its own id")
        expect(all.map(\.item.section).reduce(into: [NoteCatalogSection]()) { if $0.last != $1 { $0.append($1) } } == [.basic, .inline, .easel],
               "The menu runs text rows, inline rows, then Add to the Easel")
        expect(all.filter { $0.item.section == .basic }.map(\.id) == ["text", "heading1", "heading2", "heading3", "bulleted", "numbered", "todo", "quote", "divider"],
               "Text rows follow the Notes order")
        expect(all.filter { $0.item.section == .inline }.map(\.id) == ["mention", "date", "emoji", "inlineEquation"], "Inline rows follow the Notes order")
        expect(all.filter { $0.item.section == .easel }.map(\.id) == EaselSlashObject.allCases.map { "easel." + $0.rawValue },
               "Every object the Easel can place has a row")
        expect(NoteCatalogSection.easel.title == "Add to the Easel" && !NoteCatalogSection.easel.needsQuery, "The object section has its own header")
        for row in all where row.item.section == .easel {
            expect(!row.item.title.isEmpty && !row.item.summary.isEmpty && !row.item.summary.contains("this note") && !row.item.summary.contains("the note"),
                   "\(row.id) has a title and a summary that talks about the Easel")
        }
        expect(all.first { $0.id == "easel.equation" }?.item.title == "Block equation" && all.first { $0.id == "easel.pdf" }?.item.title == "PDF",
               "Object rows use the Notes names")
    }

    static func searching() {
        expect(ids("h1").first == "heading1" && ids("#").first == "heading1", "Notes aliases find headings")
        expect(ids("img").first == "easel.image" && ids("photo").first == "easel.image", "Notes aliases find objects")
        expect(ids("sticky").first == "easel.sticky" && ids("post-it").first == "easel.sticky", "Stickies answer to their names")
        expect(ids("rect").first == "easel.shape" && ids("circle").first == "easel.shape", "Shapes answer to their names")
        expect(ids("math").first == "easel.equation" || ids("tex").first == "easel.equation", "Math finds the block equation")
        expect(ids("emoji").first == "emoji" && ids("smiley").first == "emoji", "Emoji is one search away")
        expect(ids("zzzzzz").isEmpty, "Nonsense finds nothing")
        expect(ids("").count == EaselSlashCatalog.rows(in: EaselSlashContext()).count, "An empty query lists everything")
    }

    static func gating() {
        let bare = ids("")
        expect(!bare.contains("todo") && !bare.contains("divider") && !bare.contains("mention") && !bare.contains("date") && !bare.contains("inlineEquation"),
               "Rows wait for their commands before they appear")
        expect(bare.contains("emoji") && bare.contains("text") && bare.contains("quote"), "Rows with working commands appear")
        expect(ids("todo").isEmpty || ids("todo").first != "todo", "A to-do search finds nothing until checklists exist")
        let withChecklist = ids("todo", EaselSlashContext(checklist: true))
        expect(withChecklist.first == "todo", "Checklists appear once they exist")
        let noObjects = ids("", EaselSlashContext(objects: false))
        expect(!noObjects.contains { $0.hasPrefix("easel.") }, "Cells and labels offer no objects")
    }

    static func placement() {
        let text = EaselRect(x: 100, y: 100, width: 200, height: 60)
        let right = EaselSlashPlacement.frame(size: (100, 80), beside: text, occupied: [text])
        expect(right.x == 332 && right.y == 100, "Objects land to the right of the text")
        let blocked = EaselSlashPlacement.frame(size: (100, 80), beside: text, occupied: [text, EaselRect(x: 320, y: 90, width: 200, height: 200)])
        expect(blocked.x == 100 && blocked.y == 192, "A crowded right side drops the object below")
        let crowded = EaselSlashPlacement.frame(size: (100, 80), beside: text,
                                                occupied: [text, EaselRect(x: 320, y: 90, width: 200, height: 200), EaselRect(x: 90, y: 170, width: 300, height: 200)])
        expect(crowded.x == 332 && crowded.y == 100, "With no room anywhere the object still lands on the right, never off the left edge")
        expect(EaselSlashPlacement.frame(size: (10, 10), beside: EaselRect(x: .nan, y: 0, width: 1, height: 1), occupied: []).x == 0,
               "Bad numbers fall back to the origin")
    }
}
