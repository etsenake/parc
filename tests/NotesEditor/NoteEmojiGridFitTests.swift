import AppKit

@main @MainActor
struct NoteEmojiGridFitTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        let repo = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
        let suite = "Parc.Notes.EmojiGridFitTests.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = NoteEmojiCatalog(url: repo.appendingPathComponent("Resources/NoteEmoji/emoji.json"), defaults: defaults)
        gridFitsEveryWidth(catalog)
        pickerFitsVisibleWidth(catalog, style: .overlay)
        pickerFitsVisibleWidth(catalog, style: .legacy)
        expect(NSApp?.windows.isEmpty ?? true, "no windows were created")
        print("NoteEmojiGridFitTests passed")
    }

    static func checkRows(_ grid: NoteEmojiGridView, _ label: String) {
        expect(!grid.isEmpty, "\(label): the grid has emoji")
        let width = grid.frame.width
        let clearance = NoteEmojiGridView.inset + grid.gutter
        let firstRowY = grid.cellFrame(of: 0).minY
        let firstRow = (0..<grid.items.count).prefix { grid.cellFrame(of: $0).minY == firstRowY }
        let left = grid.cellFrame(of: 0).minX
        let right = grid.span - grid.cellFrame(of: firstRow.last!).maxX
        expect(left >= clearance, "\(label): the first column starts \(left) pt in, needs \(clearance)")
        expect(right >= clearance, "\(label): the last column ends \(right) pt from the edge, needs \(clearance)")
        expect(abs(left - right) <= 1, "\(label): margins are symmetric, left \(left) right \(right)")
        for index in grid.items.indices {
            expect(grid.cellFrame(of: index).maxX <= width - NoteEmojiGridView.inset, "\(label): cell \(index) stays inside the \(width) pt clip")
        }
    }

    static func gridFitsEveryWidth(_ catalog: NoteEmojiCatalog) {
        let items = Array(catalog.all.prefix(60).map { NoteEmojiGridView.Item(emoji: $0, character: $0.character) })
        let grid = NoteEmojiGridView()
        for span in stride(from: CGFloat(120), through: 520, by: 1) {
            for gutter: CGFloat in [0, 11, 15, 17] {
                for width in [span, span - gutter] {
                    grid.setSections([NoteEmojiGridView.Section(category: nil, title: nil, items: items)], width: width, minimumHeight: 0,
                                     span: span, gutter: gutter)
                    expect(grid.frame.width == width, "the grid takes the width it was given")
                    checkRows(grid, "span \(span) width \(width) gutter \(gutter)")
                }
            }
        }
        grid.layoutGrid(width: 408, minimumHeight: 0, span: 408, gutter: 17)
        expect(grid.cellFrame(of: 10).maxX <= 408 - 17 - NoteEmojiGridView.inset, "the last column clears a 17 pt overlay scroller")
    }

    static func pickerFitsVisibleWidth(_ catalog: NoteEmojiCatalog, style: NSScroller.Style) {
        let picker = NoteEmojiPicker(catalog: catalog, showsRemove: true, showsRandom: true)
        guard let scrollView = picker.subviews.compactMap({ $0 as? NSScrollView }).first,
              let grid = scrollView.documentView as? NoteEmojiGridView else { failTest("the picker hosts its grid in a scroll view") }
        scrollView.scrollerStyle = style
        let label = style == .legacy ? "legacy scroller" : "overlay scroller"
        let check = {
            let visible = scrollView.contentView.frame.width
            expect(grid.frame.width == visible, "\(label): the grid is \(grid.frame.width) wide in a \(visible) pt clip")
            checkRows(grid, label)
        }
        check()
        expect(grid.gutter > 0, "\(label): the grid keeps clear of the scroller")
        if let scroller = scrollView.verticalScroller, !scroller.isHidden {
            for index in grid.items.indices {
                expect(grid.cellFrame(of: index).maxX <= scroller.frame.minX, "\(label): cell \(index) stays clear of the scroller at \(scroller.frame.minX)")
            }
        }
        picker.setFrameSize(NSSize(width: 360, height: 388))
        picker.layoutSubtreeIfNeeded()
        check()
        picker.setFrameSize(NoteEmojiPicker.preferredSize)
        picker.layoutSubtreeIfNeeded()
        check()
    }
}
