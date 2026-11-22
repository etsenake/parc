import AppKit
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteEmojiGridFitTests {
    static let sampleItems: [NoteEmojiGridView.Item] = {
        let defaults = TestDefaults("Parc.Notes.EmojiGridFitTests.")!
        let url = Bundle.module.url(forResource: "emoji", withExtension: "json")!
        let catalog = NoteEmojiCatalog(url: url, defaults: defaults)
        return catalog.all.prefix(60).map { NoteEmojiGridView.Item(emoji: $0, character: $0.character) }
    }()

    func checkRows(_ grid: NoteEmojiGridView) {
        #expect(!grid.isEmpty)
        let width = grid.frame.width
        let clearance = NoteEmojiGridView.inset + grid.gutter
        let firstRowY = grid.cellFrame(of: 0).minY
        let firstRow = (0..<grid.items.count).prefix { grid.cellFrame(of: $0).minY == firstRowY }
        let left = grid.cellFrame(of: 0).minX
        let right = grid.span - grid.cellFrame(of: firstRow.last!).maxX
        #expect(left >= clearance, "the first column starts \(left) pt in, needs \(clearance)")
        #expect(right >= clearance, "the last column ends \(right) pt from the edge, needs \(clearance)")
        #expect(abs(left - right) <= 1, "margins are symmetric, left \(left) right \(right)")
        #expect(grid.items.indices.allSatisfy { grid.cellFrame(of: $0).maxX <= width - NoteEmojiGridView.inset },
                "every cell stays inside the \(width) pt clip")
    }

    nonisolated static let spans = Array(120...520)

    @Test(arguments: NoteEmojiGridFitTests.spans)
    func theGridFitsEveryWidth(span: Int) {
        let items = Self.sampleItems
        let grid = NoteEmojiGridView()
        for gutter: CGFloat in [0, 11, 15, 17] {
            for width in [CGFloat(span), CGFloat(span) - gutter] {
                grid.setSections([NoteEmojiGridView.Section(category: nil, title: nil, items: items)], width: width, minimumHeight: 0,
                                 span: CGFloat(span), gutter: gutter)
                #expect(grid.frame.width == width)
                checkRows(grid)
            }
        }
    }

    @Test func theLastColumnClearsAnOverlayScroller() {
        let items = Self.sampleItems
        let grid = NoteEmojiGridView()
        grid.setSections([NoteEmojiGridView.Section(category: nil, title: nil, items: items)], width: 408, minimumHeight: 0, span: 408, gutter: 17)
        grid.layoutGrid(width: 408, minimumHeight: 0, span: 408, gutter: 17)
        #expect(grid.cellFrame(of: 10).maxX <= 408 - 17 - NoteEmojiGridView.inset)
    }

    @MainActor struct PickerFixture {
        let picker: NoteEmojiPicker
        let scrollView: NSScrollView
        let grid: NoteEmojiGridView

        init(style: NSScroller.Style) throws {
            let defaults = TestDefaults("Parc.Notes.EmojiGridFitTests.")!
            let url = try #require(Bundle.module.url(forResource: "emoji", withExtension: "json"))
            picker = NoteEmojiPicker(catalog: NoteEmojiCatalog(url: url, defaults: defaults), showsRemove: true, showsRandom: true)
            scrollView = try #require(picker.subviews.compactMap { $0 as? NSScrollView }.first)
            grid = try #require(scrollView.documentView as? NoteEmojiGridView)
            scrollView.scrollerStyle = style
        }
    }

    func checkFit(_ fixture: PickerFixture) {
        let visible = fixture.scrollView.contentView.frame.width
        #expect(fixture.grid.frame.width == visible, "the grid is \(fixture.grid.frame.width) wide in a \(visible) pt clip")
        checkRows(fixture.grid)
    }

    @Test(arguments: [NSScroller.Style.overlay, .legacy])
    func thePickerFitsTheVisibleWidth(style: NSScroller.Style) throws {
        let fixture = try PickerFixture(style: style)
        checkFit(fixture)
    }

    @Test(arguments: [NSScroller.Style.overlay, .legacy])
    func thePickersGridKeepsClearOfTheScroller(style: NSScroller.Style) throws {
        let fixture = try PickerFixture(style: style)
        #expect(fixture.grid.gutter > 0)
        if let scroller = fixture.scrollView.verticalScroller, !scroller.isHidden {
            #expect(fixture.grid.items.indices.allSatisfy { fixture.grid.cellFrame(of: $0).maxX <= scroller.frame.minX })
        }
    }

    @Test(arguments: [NSScroller.Style.overlay, .legacy])
    func thePickerStillFitsWhenResizedNarrower(style: NSScroller.Style) throws {
        let fixture = try PickerFixture(style: style)
        fixture.picker.setFrameSize(NSSize(width: 360, height: 388))
        fixture.picker.layoutSubtreeIfNeeded()
        checkFit(fixture)
    }

    @Test(arguments: [NSScroller.Style.overlay, .legacy])
    func thePickerStillFitsBackAtItsPreferredSize(style: NSScroller.Style) throws {
        let fixture = try PickerFixture(style: style)
        fixture.picker.setFrameSize(NSSize(width: 360, height: 388))
        fixture.picker.layoutSubtreeIfNeeded()
        fixture.picker.setFrameSize(NoteEmojiPicker.preferredSize)
        fixture.picker.layoutSubtreeIfNeeded()
        checkFit(fixture)
    }
}
