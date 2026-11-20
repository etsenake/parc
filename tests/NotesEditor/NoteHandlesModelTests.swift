import Foundation

@main @MainActor
struct NoteHandlesModelTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func ids(_ entries: [NoteBlockMenuEntry]) -> [String] { entries.map(\.id) }

    static func main() {
        menuForText()
        menuForKinds()
        menuForSelections()
        menuSearch()
        footer()
        handlePlacement()
        hoverTargets()
        autoscroll()
        dragOrdering()
        columnCopies()
        print("NoteHandlesModelTests passed")
    }

    static func menuForText() {
        var paragraph = NoteBlock.paragraph("Hello there")
        paragraph.color = .background(.yellow)
        let entries = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [paragraph], canMoveToNotes: true))
        expect(ids(entries) == ["delete", "duplicate", "turn", "move", "color"], "a paragraph gets Notion's order without block links")
        expect(entries[0].shortcut == "⌫" && entries[0].isDestructive, "Delete shows a ⌫ keycap and reads as destructive")
        expect(entries[1].shortcut == "⌘D", "Duplicate shows ⌘D")
        expect(entries[3].shortcut == "⇧⌘P" && entries[3].hasSubmenu, "Move to shows ⇧⌘P and opens a note picker")
        let turn = entries[2].children
        expect(turn.first?.title == "Text" && turn.first?.isChecked == true, "Turn Into checks the paragraph's own type")
        expect(turn.filter(\.isChecked).count == 1, "only one Turn Into row is checked")
        expect(turn.contains { $0.title == "Toggle Heading 2" } && turn.contains { $0.title == "Block Equation" }, "Turn Into covers toggle headings and equations")
        let colors = entries[4].children
        expect(colors.count == 20, "ten text colours and ten backgrounds")
        expect(colors.filter(\.isChecked).map(\.id) == ["color.background.yellow"], "the block's background is checked")
        expect(colors.first?.action == .color(nil) && colors.first?.section == "Text Color", "Default Text clears the colour")

        var heading = NoteBlock.heading(2, "Plan")
        heading.props.toggleable = true
        let headingTurn = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [heading]))[2].children
        expect(headingTurn.filter(\.isChecked).map(\.title) == ["Toggle Heading 2"], "a toggle heading checks its toggle style")
        let linked = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [paragraph], supportsBlockLinks: true))
        expect(ids(linked).contains("link") && linked.first { $0.id == "link" }?.shortcut == "⌃⌘L", "block links appear when the format can anchor them")
        let raw = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [NoteBlock(.html, text: "<div></div>")], supportsBlockLinks: true))
        expect(!ids(raw).contains("link"), "raw HTML can't carry an anchor, so it gets no block link")
        expect(NoteBlockMenuModel.linkable(NoteBlock(.code)) && !NoteBlockMenuModel.linkable(NoteBlock(.column)), "code links, a bare column doesn't")
        let locked = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [paragraph], isReadOnly: true, canMoveToNotes: true, supportsBlockLinks: true))
        expect(ids(locked) == ["link"], "a locked page only offers the link")
    }

    static func menuForKinds() {
        var code = NoteBlock(.code, text: "print(1)")
        code.props.language = "Python"
        code.props.wrap = true
        let codeEntries = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [code]))
        expect(ids(codeEntries) == ["delete", "duplicate", "turn", "language", "wrap"], "code gets language and wrap, no colour")
        expect(codeEntries[3].subtitle == "Python", "the language row names the current language")
        expect(codeEntries[3].children.filter(\.isChecked).map(\.title) == ["Python"], "the current language is checked")
        expect(codeEntries[4].isChecked, "Wrap Code shows its state")
        expect(codeEntries[2].children.first { $0.title == "Code" }?.isChecked == true, "Turn Into checks Code")

        var image = NoteBlock(.image)
        image.props.source = "Attachments/cat.png"
        image.props.alignment = .left
        let imageEntries = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [image], canMoveToNotes: true))
        expect(ids(imageEntries) == ["delete", "duplicate", "align", "download", "original", "move"], "images get alignment, download and the original")
        expect(imageEntries[2].children.filter(\.isChecked).map(\.title) == ["Left"], "the image's alignment is checked")
        var pdf = NoteBlock(.pdf)
        pdf.props.source = "Attachments/report.pdf"
        let pdfEntries = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [pdf], canMoveToNotes: true))
        expect(ids(pdfEntries) == ["delete", "duplicate", "turn", "align", "download", "original", "fullScreen", "move"],
               "PDFs get Turn Into, alignment, download, the original and full screen: \(ids(pdfEntries))")
        expect(pdfEntries.first { $0.id == "turn" }?.children.map(\.id) == ["turn.pdf", "turn.file"], "PDFs turn into file rows and back")
        var pdfFile = NoteBlock(.file)
        pdfFile.props.source = "Attachments/report.pdf"
        let fileEntries = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [pdfFile]))
        expect(fileEntries.first { $0.id == "turn" }?.children.first { $0.isChecked }?.id == "turn.file", "a PDF file row can turn into a PDF")
        var zip = NoteBlock(.file)
        zip.props.source = "Attachments/a.zip"
        expect(!ids(NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [zip]))).contains("turn"), "other files can't become PDFs")
        let emptyImage = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [NoteBlock(.image)]))
        expect(ids(emptyImage) == ["delete", "duplicate", "align"], "an empty image has nothing to download")

        var bookmark = NoteBlock(.bookmark)
        bookmark.props.source = "https://parcbrowser.com"
        expect(ids(NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [bookmark]))) == ["delete", "duplicate", "copyOriginal", "original"],
               "bookmarks copy and open the original link")
        let divider = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [NoteBlock(.divider)], canMoveToNotes: true))
        expect(ids(divider) == ["delete", "duplicate", "move"], "dividers can only go away, double or move")
        var tableProps = NoteBlockProps()
        tableProps.table = .empty()
        let tableItems = [NoteBlockMenuEntry(id: "table.headerRow", title: "Header Row", isChecked: true, action: .tableItem("table.headerRow")),
                          NoteBlockMenuEntry(id: "table.fitWidth", title: "Fit to Width", isEnabled: false, action: .tableItem("table.fitWidth"))]
        let table = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [NoteBlock(.table, props: tableProps)], tableEntries: tableItems))
        expect(ids(table) == ["delete", "duplicate", "table.headerRow", "table.fitWidth"], "tables show the table's own actions")
        expect(table[2].isChecked && table[2].group == 1 && !table[3].isEnabled, "and keep their state in the kind group")
        expect(NoteBlockMenuModel.filter(table, query: "fit").isEmpty, "disabled actions stay out of search")
        let lockedTable = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [NoteBlock(.table, props: tableProps)], isReadOnly: true, tableEntries: tableItems))
        expect(!ids(lockedTable).contains("table.headerRow"), "a locked table offers no table actions")
        let toc = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [NoteBlock(.tableOfContents)]))
        expect(ids(toc) == ["delete", "duplicate", "color"], "a table of contents can be coloured but not turned")
    }

    static func menuForSelections() {
        let one = NoteBlock.paragraph("One"), two = NoteBlock(.bulletedItem, text: "Two")
        let mixed = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [one, two], supportsBlockLinks: true))
        expect(ids(mixed) == ["delete", "duplicate", "turn", "color"], "several blocks share actions but never a single-block link")
        expect(!mixed[2].children.contains(where: \.isChecked), "mixed types check nothing in Turn Into")
        let withImage = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [one, NoteBlock(.image)]))
        expect(ids(withImage) == ["delete", "duplicate"], "an image in the mix drops Turn Into and Color")
        let splittable = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [one, two], columnLimit: 3))
        let splits = splittable[2].children.filter { if case .turnIntoColumns = $0.action { return true } else { return false } }
        expect(splits.map(\.title) == ["2 Columns", "3 Columns"], "several blocks can become as many columns as there are blocks")
        expect(splits.map(\.action) == [.turnIntoColumns(2), .turnIntoColumns(3)] && splits.allSatisfy { $0.section == "Turn Into" },
               "column rows sit in Turn Into")
        let imageSplit = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [one, NoteBlock(.image)], columnLimit: 2))
        expect(ids(imageSplit) == ["delete", "duplicate", "turn"] && imageSplit[2].children.map(\.id) == ["turn.columns2"],
               "an image in the mix still offers columns, and only columns")
        let crowd = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [one, two], columnLimit: 9))
        expect(crowd[2].children.last?.id == "turn.columns5", "five columns is the most on offer")
        var redOne = one, redTwo = two
        redOne.color = .text(.red); redTwo.color = .text(.red)
        let red = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [redOne, redTwo]))
        expect(red[3].children.filter(\.isChecked).map(\.id) == ["color.text.red"], "a shared colour is checked")
        let plain = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [one, two]))
        expect(plain[3].children.filter(\.isChecked).map(\.id) == ["color.text.default"], "no colour on every block checks Default Text")
    }

    static func menuSearch() {
        let entries = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [.paragraph("Hi")], canMoveToNotes: true))
        expect(NoteBlockMenuModel.filter(entries, query: "") == entries, "an empty search changes nothing")
        let red = NoteBlockMenuModel.filter(entries, query: "red")
        expect(ids(red) == ["color.text.red", "color.background.red"], "colours are found by name")
        expect(red.allSatisfy { $0.section == "Color" }, "found colours are grouped under Color")
        let heading = NoteBlockMenuModel.filter(entries, query: "h2")
        expect(ids(heading) == ["turn.heading2", "turn.toggleHeading2"], "keywords reach Turn Into styles")
        expect(ids(NoteBlockMenuModel.filter(entries, query: "  DEL ")) == ["delete"], "search ignores case and spaces")
        expect(ids(NoteBlockMenuModel.filter(entries, query: "remove")) == ["delete"], "aliases find Delete")
        expect(NoteBlockMenuModel.filter(entries, query: "turn").count == NoteBlockMenuModel.turnIntoStyles.count, "matching a submenu shows its rows")
        expect(ids(NoteBlockMenuModel.filter(entries, query: "move")) == ["move"], "Move to is searchable")
        expect(NoteBlockMenuModel.filter(entries, query: "zzz").isEmpty, "no match means no rows")
        expect(ids(NoteBlockMenuModel.filter(entries, query: "todo")) == ["turn.todo"], "To-do is found without its hyphen")
        var code = NoteBlock(.code)
        code.props.language = "swift"
        let codeEntries = NoteBlockMenuModel.entries(for: NoteBlockMenuContext(blocks: [code]))
        expect(ids(NoteBlockMenuModel.filter(codeEntries, query: "pyth")) == ["language.python"], "languages are searchable")
    }

    static func footer() {
        let blocks = [NoteBlock.paragraph("Two words"), NoteBlock(.bulletedItem, text: "three more here",
                                                                   children: [NoteBlock(.bulletedItem, text: "nested")])]
        expect(NoteBlockMenuModel.footer(for: blocks) == "6 words · 30 characters", "the footer counts words and characters, children too")
        expect(NoteBlockMenuModel.footer(for: [.paragraph("Hi")]) == "1 word · 2 characters", "singular words read naturally")
        expect(NoteBlockMenuModel.footer(for: [NoteBlock(.divider)]) == nil, "blocks without words have no footer")
    }

    static func handlePlacement() {
        let frame = CGRect(x: 200, y: 100, width: 400, height: 60)
        let rects = NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14)
        expect(rects.grip.maxX == frame.minX - NoteHandleGeometry.contentGap, "the grip sits a small gap left of the block")
        expect(rects.plus.maxX == rects.grip.minX - NoteHandleGeometry.buttonGap, "plus comes before the grip")
        expect(rects.plus.midY == 114 && rects.grip.midY == 114, "both centre on the block's first line")
        expect(rects.plus.size == NoteHandleGeometry.buttonSize, "buttons keep their size")
        let nested = NoteHandleGeometry.rects(blockFrame: frame.offsetBy(dx: 26, dy: 0), anchorY: 14)
        expect(nested.grip.minX == rects.grip.minX + 26, "nested blocks get handles at their indent")
        let edge = NoteHandleGeometry.rects(blockFrame: CGRect(x: 10, y: 0, width: 300, height: 20), anchorY: 10, minimumX: 0)
        expect(edge.plus.minX >= 0, "handles never leave the canvas")
        expect(NoteHandleGeometry.barWidth == NoteHandleGeometry.buttonSize.width * 2 + NoteHandleGeometry.buttonGap, "the bar holds both buttons")
    }

    static func hoverTargets() {
        let a = NoteBlockID(), b = NoteBlockID(), child = NoteBlockID(), container = NoteBlockID(), left = NoteBlockID(), right = NoteBlockID()
        let flat = [NoteHandleTarget(id: a, frame: CGRect(x: 100, y: 0, width: 500, height: 30), depth: 0, anchorY: 15),
                    NoteHandleTarget(id: b, frame: CGRect(x: 100, y: 32, width: 500, height: 30), depth: 0, anchorY: 15)]
        expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 10), in: flat)?.id == a, "the pointer over a block picks it")
        expect(NoteHandleGeometry.target(at: CGPoint(x: 70, y: 40), in: flat)?.id == b, "the left gutter counts as the block")
        expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 31), in: flat) != nil, "the gap between blocks still shows a handle")
        expect(NoteHandleGeometry.target(at: CGPoint(x: 20, y: 10), in: flat) == nil, "far left of the gutter shows nothing")
        expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 200), in: flat) == nil, "below the page shows nothing")
        let tree = [NoteHandleTarget(id: container, frame: CGRect(x: 100, y: 0, width: 500, height: 100), depth: 0, anchorY: 15),
                    NoteHandleTarget(id: child, frame: CGRect(x: 126, y: 40, width: 474, height: 30), depth: 1, anchorY: 15)]
        expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 50), in: tree)?.id == child, "the deepest block under the pointer wins")
        expect(NoteHandleGeometry.target(at: CGPoint(x: 110, y: 50), in: tree)?.id == child, "a nested block's gutter is its own")
        expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 10), in: tree)?.id == container, "the container's own row is the container")
        let columns = [NoteHandleTarget(id: left, frame: CGRect(x: 100, y: 0, width: 220, height: 30), depth: 2, anchorY: 15),
                       NoteHandleTarget(id: right, frame: CGRect(x: 366, y: 0, width: 220, height: 30), depth: 2, anchorY: 15)]
        expect(NoteHandleGeometry.target(at: CGPoint(x: 400, y: 10), in: columns)?.id == right, "each column block has its own handle")
        expect(NoteHandleGeometry.target(at: CGPoint(x: 345, y: 10), in: columns)?.id == right, "the column gap belongs to the next column")
        expect(NoteHandleGeometry.target(at: CGPoint(x: 325, y: 10), in: columns)?.id == left, "just past a column's edge is still that column")
    }

    static func autoscroll() {
        let top: CGFloat = 1000, bottom: CGFloat = 1600
        expect(NoteAutoscroll.velocity(pointerY: 1300, visibleMinY: top, visibleMaxY: bottom) == 0, "the middle of the view never scrolls")
        let nearTop = NoteAutoscroll.velocity(pointerY: top + 40, visibleMinY: top, visibleMaxY: bottom)
        let atTop = NoteAutoscroll.velocity(pointerY: top, visibleMinY: top, visibleMaxY: bottom)
        let aboveTop = NoteAutoscroll.velocity(pointerY: top - 60, visibleMinY: top, visibleMaxY: bottom)
        let wayAbove = NoteAutoscroll.velocity(pointerY: top - 5000, visibleMinY: top, visibleMaxY: bottom)
        expect(nearTop < 0 && atTop < nearTop && aboveTop < atTop, "the top edge scrolls up faster the closer you get")
        expect(wayAbove == -NoteAutoscroll.maximumSpeed, "speed tops out")
        expect(nearTop <= -NoteAutoscroll.minimumSpeed, "the edge zone never crawls below the minimum speed")
        let nearBottom = NoteAutoscroll.velocity(pointerY: bottom - 40, visibleMinY: top, visibleMaxY: bottom)
        expect(nearBottom == -nearTop, "the bottom edge mirrors the top")
        expect(NoteAutoscroll.velocity(pointerY: top + NoteAutoscroll.edgeZone + 1, visibleMinY: top, visibleMaxY: bottom) == 0, "just outside the zone is still")
        let tiny = NoteAutoscroll.velocity(pointerY: 50, visibleMinY: 0, visibleMaxY: 120)
        expect(tiny == 0, "a short view keeps a still middle")
        expect(NoteAutoscroll.step(velocity: 600, elapsed: 1.0 / 60) == 10, "a frame moves velocity × time")
        expect(NoteAutoscroll.step(velocity: 600, elapsed: 2) == 30, "a stalled frame never jumps far")
    }

    static func columnCopies() {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b")
        var page = NotePage(blocks: [a, b])
        let copy = NoteBlock.paragraph("copy")
        page.place([copy], beside: b.id, side: .left)
        expect(page.blocks.count == 2 && page.blocks[1].kind == .columns, "dropping beside a block makes columns in its place")
        expect(page.blocks[1].children.map { $0.children.map(\.text.string) } == [["copy"], ["b"]], "the left side puts the copy first")
        let row = page.blocks[1].id
        let third = NoteBlock.paragraph("third")
        var widened = page
        widened.update(row) { columns in for index in columns.children.indices { columns.children[index].props.width = 0.5 } }
        widened.place([third], beside: b.id, side: .right)
        let columns = widened.block(row)!.children
        expect(columns.map { $0.children.map(\.text.string) } == [["copy"], ["b"], ["third"]], "beside a column block adds a column next to it")
        expect(columns.allSatisfy { $0.props.width == nil }, "a new column evens out the widths")
        var full = NotePage(blocks: [NoteBlock(.columns, children: (0..<5).map { NoteBlock(.column, children: [NoteBlock.paragraph(NoteText("\($0)"))]) })])
        let before = full
        full.place([NoteBlock.paragraph("six")], beside: full.blocks[0].children[2].children[0].id, side: .right)
        expect(full == before, "five columns is the limit")
        var empty = NotePage(blocks: [a])
        empty.place([], beside: a.id, side: .right)
        expect(empty.blocks == [a], "placing nothing changes nothing")
    }

    static func dragOrdering() {
        let a = NoteBlock.paragraph("a"), c = NoteBlock(.bulletedItem, text: "c")
        let b = NoteBlock(.bulletedItem, text: "b", children: [c])
        let d = NoteBlock.paragraph("d")
        let left = NoteBlock(.column, children: [NoteBlock.paragraph("l")]), right = NoteBlock(.column, children: [NoteBlock.paragraph("r")])
        let columns = NoteBlock(.columns, children: [left, right])
        let page = NotePage(blocks: [a, b, d, columns])
        expect(NoteDragPlan.draggedBlocks(grabbing: d.id, selection: .none, page: page) == [d.id], "an unselected block drags alone")
        expect(NoteDragPlan.draggedBlocks(grabbing: d.id, selection: .blocks([d.id, a.id]), page: page) == [a.id, d.id], "a selection drags in document order")
        expect(NoteDragPlan.draggedBlocks(grabbing: a.id, selection: .blocks([b.id]), page: page) == [a.id], "grabbing outside the selection drags just that block")
        expect(NoteDragPlan.draggedBlocks(grabbing: c.id, selection: .blocks([b.id, c.id, a.id]), page: page) == [a.id, b.id], "children travel with their selected parent")
        expect(NoteDragPlan.draggedBlocks(grabbing: left.id, selection: .none, page: page).isEmpty, "a bare column can't be dragged")
        expect(NoteDragPlan.draggedBlocks(grabbing: NoteBlockID(), selection: .none, page: page).isEmpty, "missing blocks drag nothing")
        expect(NoteDragPlan.affectedBlocks([b.id], page: page) == [b.id, c.id], "dimming covers visible children")
        expect(NoteDragPlan.canDrop([b.id], onto: d.id, page: page), "dropping beside another block is fine")
        expect(!NoteDragPlan.canDrop([b.id], onto: c.id, page: page), "a block can't be dropped into itself")
        expect(!NoteDragPlan.canDrop([b.id], onto: b.id, page: page), "a block can't be dropped onto itself")
        expect(!NoteDragPlan.crossesThreshold(from: .zero, to: CGPoint(x: 2, y: 2)), "a wobble is still a click")
        expect(NoteDragPlan.crossesThreshold(from: .zero, to: CGPoint(x: 3, y: 3)), "a real move starts a drag")
        var toggle = NoteBlock(.toggle, text: "t")
        toggle.props.expanded = false
        expect(!NoteDragPlan.shouldExpand(toggle, hoveredSince: 10, now: 10.5), "a toggle waits before opening")
        expect(NoteDragPlan.shouldExpand(toggle, hoveredSince: 10, now: 10.6), "a closed toggle opens after 0.6 s")
        expect(!NoteDragPlan.shouldExpand(a, hoveredSince: 10, now: 20), "only toggles open")
        expect(!NoteDragPlan.shouldExpand(toggle, hoveredSince: nil, now: 20), "no hover, no opening")
        let copies = NoteDragPlan.copies(of: [d.id, b.id, c.id], in: page)
        expect(copies.map(\.text.string) == ["b", "d"] && copies.allSatisfy { $0.id != b.id && $0.id != d.id }, "copies keep order and get fresh ids")
        expect(copies[0].children.first?.id != c.id && copies[0].children.first?.text.string == "c", "copied children are fresh too")
        expect(NoteDragPlan.ghostOrigin(pointer: CGPoint(x: 100, y: 80), grabOffset: CGPoint(x: 10, y: 5)) == CGPoint(x: 90, y: 75), "the ghost keeps the grab offset")
    }
}
