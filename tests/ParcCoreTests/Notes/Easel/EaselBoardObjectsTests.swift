import Foundation
import Testing
@testable import ParcCore

@MainActor struct EaselBoardObjectsTests {
    func item(_ kind: EaselItemKind, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                     z: Int = 0, text: String = "") -> EaselItem {
        var value = EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height), zIndex: z, text: text)
        if kind == .arrow || kind == .freehand { value.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: width, y: height)] }
        return value
    }

    func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    func accepts(_ items: [EaselItem]) -> Bool {
        (try? EaselSession(inMemory: document(items), assets: [:])) != nil
    }

    @Test func stickiesKeepATextScaleAndSectionsCanHide() {
        var sticky = item(.sticky, 10, 10, 220, 220)
        sticky.textStyle = EaselTextStyle(textScale: 2)
        var section = item(.section, 0, 0, 640, 480, text: "Section")
        section.contentsHidden = true
        #expect(accepts([sticky, section]), "Stickies keep a text scale and sections can hide their contents")
        for edge in [0.25, 8.0] {
            var bounded = sticky
            bounded.textStyle = EaselTextStyle(textScale: edge)
            #expect(accepts([bounded]), "A text scale of exactly \(edge) is allowed")
        }
        var towering = sticky
        towering.frame.height = EaselBoardObjects.stickyHeight(sticky, textHeight: 1e12)
        #expect(accepts([towering]), "The tallest sticky still saves")
        for bad in [0.1, 9.0, Double.nan, Double.infinity] {
            var broken = sticky
            broken.textStyle = EaselTextStyle(textScale: bad)
            #expect(!accepts([broken]), "A text scale of \(bad) is refused")
        }
        var scaledText = item(.text, 0, 0, 280, 28, text: "Hi")
        scaledText.textStyle = EaselTextStyle(textScale: 2)
        #expect(!accepts([scaledText]), "Only stickies carry a text scale")
        var hiddenSticky = item(.sticky, 0, 0, 220, 220)
        hiddenSticky.contentsHidden = true
        #expect(!accepts([hiddenSticky]), "Only sections hide contents")
        let plain = document([item(.sticky, 0, 0, 220, 220), item(.section, 0, 0, 640, 480)])
        let encoded = (try? JSONEncoder().encode(plain)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(!encoded.contains("textScale") && !encoded.contains("contentsHidden"), "Unused fields stay out of the file")
        let decoded = (try? JSONEncoder().encode(document([sticky, section])))
            .flatMap { try? JSONDecoder().decode(EaselDocument.self, from: $0) }
        #expect(decoded?.items.first?.textStyle?.textScale == 2 && decoded?.items.last?.contentsHidden == true, "Text scale and hidden contents survive a save")
    }

    @Test func aStickyDropsAsA220PointSquareCentred() {
        let square = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 300, y: 300), wide: false, zIndex: 3)
        #expect(square.kind == .sticky && square.frame == EaselRect(x: 190, y: 190, width: 220, height: 220) && square.zIndex == 3, "A sticky drops as a 220 point square centred on the pointer")
        let wide = EaselBoardObjects.sticky(centeredAt: EaselPoint(x: 100, y: 50), wide: true, zIndex: 0)
        #expect(wide.frame == EaselRect(x: 0, y: 0, width: 440, height: 220), "A wide sticky is 440 by 220 and stays on the canvas")
        #expect(EaselBoardObjects.isWide(wide) && !EaselBoardObjects.isWide(square), "Wide stickies are told apart from squares")
        #expect(EaselBoardObjects.stickyHeight(square, textHeight: 80) == 220, "Short text keeps the square height")
        #expect(EaselBoardObjects.stickyHeight(square, textHeight: 300) == 336, "Long text grows the sticky by its padding")
        #expect(EaselBoardObjects.stickyHeight(square, textHeight: .nan) == 220, "Unmeasurable text keeps the minimum")
        for odd in [Double.infinity, 0, -50] {
            #expect(EaselBoardObjects.stickyHeight(square, textHeight: odd) == 220, "A text height of \(odd) keeps the minimum")
        }
        #expect(EaselBoardObjects.stickyHeight(square, textHeight: 1e12) == EaselRect.maximumCoordinate, "Enormous text stops growing the sticky at the largest size the file allows")
        var scaled = square
        scaled.textStyle = EaselTextStyle(textScale: 2)
        #expect(EaselBoardObjects.stickyMinimumHeight(scaled) == 440 && EaselBoardObjects.stickyInset(scaled) == 36, "Scale grows the minimum height and the padding together")
        #expect(EaselBoardObjects.stickyTextBox(scaled) == EaselRect(x: 226, y: 226, width: 148, height: 148), "Text sits inside the scaled padding")
        #expect(EaselBoardObjects.stickyWidths(scaled) == 440...1760, "Side drags stay between one and four squares wide")
        let measure: (EaselItem) -> Double = { 40_000 / $0.frame.width }
        let widened = EaselBoardObjects.widened(square, wide: true, textHeight: measure)
        #expect(widened.frame.width == 440 && widened.frame.height == 220 && widened.frame.x == square.frame.x && widened.frame.y == square.frame.y, "Going wide keeps the top-left corner and rewraps")
        let narrowed = EaselBoardObjects.widened(EaselBoardObjects.widened(square, wide: true, textHeight: { _ in 600 }),
                                                 wide: false, textHeight: { _ in 600 })
        #expect(narrowed.frame.width == 220 && narrowed.frame.height == 636, "Going square rewraps the text taller")
        let copy = EaselBoardObjects.sticky(origin: EaselPoint(x: 500, y: 40), like: {
            var source = scaled; source.fill = "#AED0E6"; source.frame.width = 600; return source
        }(), zIndex: 9)
        #expect(copy.frame == EaselRect(x: 500, y: 40, width: 600, height: 440) && copy.fill == "#AED0E6"
               && copy.textStyle?.textScale == 2 && copy.text.isEmpty, "Quick create copies the source sticky's colour, width and scale but not its text")
        #expect(EaselBoardObjects.scaledStyle(nil, scale: 1) == nil && EaselBoardObjects.scaledStyle(nil, scale: 1.0002) == nil, "Scale one leaves no style behind")
        #expect(EaselBoardObjects.scaledStyle(nil, scale: 20)?.textScale == 8, "Scale is clamped to eight")
        #expect(!EaselBoardObjects.transforms(.sticky) && !EaselBoardObjects.transforms(.section) && EaselBoardObjects.transforms(.rectangle), "Stickies and sections never rotate or flip")
    }

    @Test func aSideDragWidensUpTo880PointsWithout() {
        let original = item(.sticky, 100, 100, 220, 220)
        let measure: (EaselItem) -> Double = { 30_000 / $0.frame.width }
        var proposed = original
        proposed.frame = EaselRect(x: 100, y: 100, width: 1200, height: 220)
        let widened = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .right, alone: true, textHeight: measure)
        #expect(widened.frame == EaselRect(x: 100, y: 100, width: 880, height: 220) && widened.textStyle == nil, "A side drag widens up to 880 points without scaling the text")
        proposed.frame = EaselRect(x: 250, y: 100, width: 70, height: 220)
        let narrowed = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .left, alone: true, textHeight: measure)
        #expect(narrowed.frame == EaselRect(x: 100, y: 100, width: 220, height: 220), "A side drag never goes narrower than a square")
        let tall: (EaselItem) -> Double = { 60_000 / $0.frame.width }
        let rewrapped = EaselBoardObjects.resizedSticky(original, proposed: original, handle: .left, alone: true, textHeight: tall)
        #expect(rewrapped.frame.height == 309 && rewrapped.frame.x == 100, "Rewrapping refits the height")
        proposed.frame = EaselRect(x: 100, y: 100, width: 440, height: 440)
        let scaled = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .bottomRight, alone: true,
                                                     textHeight: { 100 * EaselBoardObjects.textScale($0) })
        #expect(scaled.frame == EaselRect(x: 100, y: 100, width: 440, height: 440) && scaled.textStyle?.textScale == 2, "A corner drag scales the sticky and its text together")
        proposed.frame = EaselRect(x: 210, y: 210, width: 110, height: 110)
        let shrunk = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .topLeft, alone: true,
                                                     textHeight: { 100 * EaselBoardObjects.textScale($0) })
        #expect(shrunk.frame == EaselRect(x: 210, y: 210, width: 110, height: 110) && shrunk.textStyle?.textScale == 0.5, "A top-left corner drag keeps the bottom-right corner fixed")
        proposed.frame = EaselRect(x: 100, y: 100, width: 1, height: 1)
        let tiny = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .bottomRight, alone: true,
                                                   textHeight: { _ in 0 })
        #expect(tiny.textStyle?.textScale == 0.25 && tiny.frame.width == 55, "Scaling stops at a quarter")
        var big = original
        big.textStyle = EaselTextStyle(textScale: 4)
        big.frame = EaselRect(x: 0, y: 0, width: 880, height: 880)
        proposed.frame = EaselRect(x: 0, y: 0, width: 2640, height: 2640)
        let capped = EaselBoardObjects.resizedSticky(big, proposed: proposed, handle: .bottomRight, alone: true,
                                                     textHeight: { _ in 0 })
        #expect(capped.textStyle?.textScale == 8 && capped.frame.width == 1760 && capped.frame.height == 1760, "Scaling stops at eight times")
        proposed.frame = EaselRect(x: 100, y: 40, width: 220, height: 280)
        let top = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .top, alone: true, textHeight: measure)
        #expect(top.frame == original.frame, "Top and bottom drags leave the automatic height alone")
        proposed.frame = EaselRect(x: 300, y: 260, width: 330, height: 330)
        let grouped = EaselBoardObjects.resizedSticky(original, proposed: proposed, handle: .bottomRight, alone: false,
                                                      textHeight: { 100 * EaselBoardObjects.textScale($0) })
        #expect(grouped.frame.x == 300 && grouped.frame.y == 260 && grouped.textStyle?.textScale == 1.5, "In a group resize a sticky keeps its mapped place and scales evenly")
    }

    @Test func theFirstSectionIsCalledSection() {
        var items = [item(.text, 0, 0, 10, 10, text: "Section")]
        #expect(EaselBoardObjects.sectionName(in: items) == "Section", "The first section is called Section")
        items.append(item(.section, 0, 0, 640, 480, text: "Section"))
        #expect(EaselBoardObjects.sectionName(in: items) == "Section 2", "The next one is Section 2")
        items.append(item(.section, 0, 0, 640, 480, text: " section 2 "))
        items.append(item(.section, 0, 0, 640, 480, text: "Section 4"))
        #expect(EaselBoardObjects.sectionName(in: items) == "Section 3", "Names fill the first free number, ignoring case")
        #expect(EaselBoardObjects.sectionName(in: items, excluding: items[1].id) == "Section", "A section being renamed doesn't block its own default")
        #expect(EaselBoardObjects.sectionTitle("  Big\nideas \n") == "Big ideas", "Titles stay on one line and trimmed")
        #expect(EaselBoardObjects.sectionTitle(String(repeating: "a", count: 500)).count == EaselBoardObjects.sectionTitleLimit, "Titles are capped")
        #expect(EaselBoardObjects.displayTitle(item(.section, 0, 0, 10, 10, text: "  ")) == "Section", "An empty title shows Section")
        let blank = [item(.section, 0, 0, 640, 480, text: " ")]
        #expect(EaselBoardObjects.sectionName(in: blank) == "Section 2", "A blank title already shows as Section")
        let wrapped = [item(.section, 0, 0, 640, 480, text: "Section\n2"), item(.section, 0, 0, 640, 480, text: "")]
        #expect(EaselBoardObjects.sectionName(in: wrapped) == "Section 3", "Names compare the way titles are shown")
    }

    @Test func membersSitFullyInsideSmallerSectionsCountEqualSections() {
        let section = item(.section, 100, 100, 600, 400)
        let inside = item(.sticky, 120, 120, 220, 220)
        let edge = item(.text, 100, 100, 600, 400)
        let overlapping = item(.sticky, 650, 120, 220, 220)
        let nested = item(.section, 150, 150, 300, 200)
        let twin = item(.section, 100, 100, 600, 400)
        let nudged = item(.rectangle, 99.7, 120, 50, 50)
        let all = [section, inside, edge, overlapping, nested, twin, nudged]
        let members = Set(EaselBoardObjects.members(of: section, in: all).map(\.id))
        #expect(members == [inside.id, edge.id, nested.id, nudged.id], "Members sit fully inside, smaller sections count, equal sections and overhangs don't")
        #expect(EaselBoardObjects.members(of: inside, in: all).isEmpty, "Only sections have members")
        #expect(EaselBoardObjects.sections(containing: EaselPoint(x: 200, y: 200), in: all) == [section.id, nested.id, twin.id], "Every section under a point is found")
        var outer = item(.section, 100, 100, 600, 400)
        let inner = item(.section, 99.6, 99.6, 300, 200)
        let sticky = item(.sticky, 99.2, 99.2, 100, 100)
        let board = document([outer, inner, sticky])
        #expect(!EaselBoardObjects.contains(outer, sticky) && Set(EaselBoardObjects.contents(of: outer, in: board.items).map(\.id)) == [inner.id, sticky.id], "Contents reach through nested sections even when each one overhangs a hair")
        outer.contentsHidden = true
        #expect(EaselBoardObjects.hiddenIDs(in: [outer, inner, sticky]) == [inner.id, sticky.id], "Hiding reaches nested contents")
        #expect(EaselBoardObjects.deletion([outer.id], in: board) == [outer.id, inner.id, sticky.id], "Deleting reaches nested contents")
        #expect(EaselBoardObjects.lockTargets([outer.id], all: true, in: board) == [outer.id, inner.id, sticky.id], "Lock All reaches nested contents")
        var moved = board
        moved.items[0].frame.x += 10
        let carried = EaselBoardObjects.carryingSectionContents(moved, previous: board, moved: [outer.id])
        #expect(abs(carried.document.items[2].frame.x - 109.2) < 1e-9, "Moving reaches nested contents")
    }

    @Test func paintOrderAndHiding() {
        let outer = item(.section, 0, 0, 800, 600, z: 9)
        let inner = item(.section, 100, 100, 300, 300, z: 1)
        let low = item(.sticky, 120, 120, 100, 100, z: 0)
        let high = item(.text, 500, 500, 50, 20, z: 5)
        let order = EaselBoardObjects.paintOrder([high, inner, low, outer]).map(\.id)
        #expect(order == [outer.id, inner.id, low.id, high.id], "Sections paint first, nested ones above their parent, then everything else by layer")
        var hiding = inner
        hiding.contentsHidden = true
        let shown = EaselBoardObjects.displayed([high, hiding, low, outer]).map(\.id)
        #expect(shown == [outer.id, hiding.id, high.id], "Hidden contents leave the display but their section stays")
        var hidingOuter = outer
        hidingOuter.contentsHidden = true
        #expect(EaselBoardObjects.hiddenIDs(in: [hidingOuter, hiding, low, high]) == [hiding.id, low.id, high.id], "Hiding a parent hides nested sections and their contents")
        let marquee = EaselRect(x: 90, y: 90, width: 400, height: 400)
        let candidates = EaselBoardObjects.marqueeCandidates([outer, inner, low, high], in: marquee, excluding: [outer.id]).map(\.id)
        #expect(candidates == [inner.id, low.id, high.id], "A marquee needs to cover a section fully and skips the one it started in")
        let partial = EaselBoardObjects.marqueeCandidates([inner], in: EaselRect(x: 0, y: 0, width: 200, height: 200), excluding: [])
        #expect(partial.isEmpty, "A marquee touching a section doesn't select it")
        #expect(EaselBoardObjects.hiddenSummary(1) == "1 object hidden" && EaselBoardObjects.hiddenSummary(12) == "12 objects hidden", "The hidden count reads naturally")
    }

    @Test func deletionAndLocks() {
        let section = item(.section, 0, 0, 600, 400)
        let sticky = item(.sticky, 20, 20, 220, 220)
        var pinned = item(.text, 300, 20, 100, 30)
        pinned.locked = true
        let outside = item(.text, 700, 20, 100, 30)
        let board = document([section, sticky, pinned, outside])
        #expect(EaselBoardObjects.deletion([section.id], in: board) == [section.id, sticky.id], "Deleting a section takes its unlocked contents")
        var lockedSection = section
        lockedSection.locked = true
        let lockedBoard = document([lockedSection, sticky, outside])
        #expect(EaselBoardObjects.deletion([lockedSection.id], in: lockedBoard) == [lockedSection.id], "A locked section never drags its contents into a delete")
        let kept = EaselBoardObjects.removingSections([section.id, sticky.id], from: board)
        #expect(kept?.items.map(\.id) == [sticky.id, pinned.id, outside.id], "Removing only the section keeps everything else")
        #expect(EaselBoardObjects.withContents([section.id], in: board) == [section.id, sticky.id, pinned.id], "Copying a section brings everything inside it, locked or not")
        #expect(EaselDependents.removing([section.id], from: board).items.map(\.id) == [pinned.id, outside.id], "The delete pipeline removes a section with its unlocked contents")
        #expect(EaselDependents.removing([section.id], from: board, keepingSectionContents: true).items.map(\.id)
               == [sticky.id, pinned.id, outside.id], "The keep-contents delete removes just the section")
        #expect(EaselBoardObjects.removingSections([sticky.id], from: board) == nil, "Removing sections needs a section")
        #expect(EaselBoardObjects.lockTargets([section.id], all: true, in: board) == [section.id, sticky.id, pinned.id], "Lock All covers the section and its contents")
        #expect(EaselBoardObjects.lockTargets([section.id, sticky.id], all: false, in: board) == [section.id], "Lock Background Only covers just the section")
        let hidden = EaselBoardObjects.settingContentsHidden(true, sections: [section.id, sticky.id], in: board)
        #expect(hidden?.items.first?.contentsHidden == true && hidden?.items[1].contentsHidden == nil, "Hiding marks only sections")
        #expect(EaselBoardObjects.settingContentsHidden(false, sections: [section.id], in: board) == nil, "Showing shown contents changes nothing")
        let shown = hidden.flatMap { EaselBoardObjects.settingContentsHidden(false, sections: [section.id], in: $0) }
        #expect(shown?.items.first?.contentsHidden == nil, "Showing contents leaves the field out of the file")
    }

    @Test func movingASectionCarriesEverythingInsideItNestedSections() {
        let section = item(.section, 100, 100, 600, 400)
        let nested = item(.section, 150, 150, 200, 200)
        let deep = item(.sticky, 160, 160, 100, 100)
        let arrow = item(.arrow, 400, 300, 100, 50)
        let outside = item(.text, 800, 100, 100, 30)
        let selected = item(.sticky, 450, 150, 100, 100)
        let before = document([section, nested, deep, arrow, outside, selected])
        var after = before
        after.items[0].frame.x += 50; after.items[0].frame.y += 20
        after.items[5].frame.x += 50; after.items[5].frame.y += 20
        let result = EaselBoardObjects.carryingSectionContents(after, previous: before, moved: [section.id, selected.id])
        let frames = Dictionary(result.document.items.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        #expect(frames[nested.id]?.x == 200 && frames[deep.id]?.y == 180 && frames[arrow.id]?.x == 450, "Moving a section carries everything inside it, nested sections included")
        #expect(frames[outside.id] == outside.frame, "Objects outside stay put")
        #expect(frames[selected.id]?.x == 500, "Objects already moving are not moved twice")
        #expect(result.moved == [section.id, selected.id, nested.id, deep.id, arrow.id], "Carried objects join the moved set")
        var resized = before
        resized.items[0].frame.x -= 40; resized.items[0].frame.width += 40
        let resizing = EaselBoardObjects.carryingSectionContents(resized, previous: before, moved: [section.id])
        #expect(resizing.document == resized && resizing.moved == [section.id], "Resizing a section never moves its contents")
        var hidden = before
        hidden.items[0].contentsHidden = true
        var hiddenAfter = hidden
        hiddenAfter.items[0].frame.y += 10
        let hiddenCarry = EaselBoardObjects.carryingSectionContents(hiddenAfter, previous: hidden, moved: [section.id])
        #expect(hiddenCarry.document.items[2].frame.y == 170, "Hidden contents travel with their section")
        var back = before
        back.items[1].frame.x = 0; back.items[1].frame.y = 0
        let alone = EaselBoardObjects.carryingSectionContents(back, previous: before, moved: [nested.id])
        #expect(alone.document.items[2].frame.x == 10 && alone.document.items[2].frame.y == 10, "A nested section carries its own contents when it moves alone")
        let unchanged = EaselBoardObjects.carryingSectionContents(before, previous: before, moved: [outside.id])
        #expect(unchanged.document == before && unchanged.moved == [outside.id], "Moves without sections pass straight through")
        var negative = before
        negative.items[0].frame.x = -60; negative.items[0].frame.y = -30
        let kept = EaselBoardObjects.carryingSectionContents(negative, previous: before, moved: [section.id])
        #expect(kept.document.items[0].frame.x == 0 && kept.document.items[0].frame.y == 0
               && kept.document.items[1].frame.x == 50 && kept.document.items[2].frame.y == 60, "A section pushed past the canvas edge stops at zero and its contents stop with it")
    }

    @Test func aClickedSectionIs640By480Around() {
        #expect(EaselBoardObjects.sectionFrame(centeredAt: EaselPoint(x: 500, y: 400)) == EaselRect(x: 180, y: 160, width: 640, height: 480), "A clicked section is 640 by 480 around the pointer")
        #expect(EaselBoardObjects.sectionFrame(centeredAt: EaselPoint(x: 10, y: 10)).x == 0, "Clicked sections stay on the canvas")
        #expect(EaselBoardObjects.sectionFrame(dragged: EaselRect(x: 5, y: 5, width: 20, height: 900))
               == EaselRect(x: 5, y: 5, width: 120, height: 900), "Dragged sections keep a usable size")
        let fitted = EaselBoardObjects.sectionFrame(fitting: [EaselRect(x: 100, y: 100, width: 50, height: 50),
                                                              EaselRect(x: 300, y: 20, width: 100, height: 100)])
        #expect(fitted == EaselRect(x: 52, y: 0, width: 396, height: 198), "Create Section wraps the selection with padding")
        #expect(EaselBoardObjects.sectionFrame(fitting: []) == nil, "Nothing selected makes no section")
        let made = EaselBoardObjects.section(frame: EaselRect(x: 0, y: 0, width: 640, height: 480),
                                             in: [item(.section, 0, 0, 10, 10, text: "Section")], zIndex: 4)
        #expect(made.kind == .section && made.text == "Section 2" && made.zIndex == 4, "New sections take the next free name")
        let section = item(.section, 100, 100, 600, 400)
        let tab = EaselBoardObjects.titleTab(section, titleWidth: 60, zoom: 1)
        #expect(tab == EaselRect(x: 100, y: 68, width: 80, height: 26), "The title tab sits above the top-left corner")
        let zoomedOut = EaselBoardObjects.titleTab(section, titleWidth: 60, zoom: 0.5)
        #expect(zoomedOut.height == 52 && zoomedOut.y == 100 - 64, "Zoomed out, the title stays readable")
        let high = EaselBoardObjects.titleTab(item(.section, 0, 10, 600, 400), titleWidth: 1000, zoom: 1)
        #expect(high.y == 16 && high.width == 600, "Without room above, the title tucks inside and never overhangs")
    }
}

private extension EaselTextStyle {
    init(textScale: Double) {
        self.init()
        self.textScale = textScale
    }
}
