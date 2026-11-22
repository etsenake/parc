import Foundation
import Testing
@testable import ParcCore

struct EaselBoardObjectsSectionsTests {
    @Test
    func sectionNamesUseTheFirstFreeNumber() {
        var items = [EaselBoardObjectsTestsSupport.item(.text, 0, 0, 10, 10, text: "Section")]
        #expect(EaselBoardObjects.sectionName(in: items) == "Section", "The first section is called Section")
        items.append(EaselBoardObjectsTestsSupport.item(.section, 0, 0, 640, 480, text: "Section"))
        #expect(EaselBoardObjects.sectionName(in: items) == "Section 2", "The next one is Section 2")
        items.append(EaselBoardObjectsTestsSupport.item(.section, 0, 0, 640, 480, text: " section 2 "))
        items.append(EaselBoardObjectsTestsSupport.item(.section, 0, 0, 640, 480, text: "Section 4"))
        #expect(EaselBoardObjects.sectionName(in: items) == "Section 3", "Names fill the first free number, ignoring case")
        #expect(EaselBoardObjects.sectionName(in: items, excluding: items[1].id) == "Section", "A section being renamed doesn't block its own default")
        let blank = [EaselBoardObjectsTestsSupport.item(.section, 0, 0, 640, 480, text: " ")]
        #expect(EaselBoardObjects.sectionName(in: blank) == "Section 2", "A blank title already shows as Section")
        let wrapped = [EaselBoardObjectsTestsSupport.item(.section, 0, 0, 640, 480, text: "Section\n2"), EaselBoardObjectsTestsSupport.item(.section, 0, 0, 640, 480, text: "")]
        #expect(EaselBoardObjects.sectionName(in: wrapped) == "Section 3", "Names compare the way titles are shown")
    }

    @Test
    func sectionTitlesFlattenWhitespaceAndRespectTheLengthLimit() {
        #expect(EaselBoardObjects.sectionTitle("  Big\nideas \n") == "Big ideas", "Titles stay on one line and trimmed")
        #expect(EaselBoardObjects.sectionTitle(String(repeating: "a", count: 500)).count == EaselBoardObjects.sectionTitleLimit, "Titles are capped")
    }

    @Test
    func aBlankSectionTitleDisplaysTheDefaultName() {
        #expect(EaselBoardObjects.displayTitle(EaselBoardObjectsTestsSupport.item(.section, 0, 0, 10, 10, text: "  ")) == "Section", "An empty title shows Section")
    }

    @Test func membersSitFullyInsideSmallerSectionsCountEqualSections() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let inside = EaselBoardObjectsTestsSupport.item(.sticky, 120, 120, 220, 220)
        let edge = EaselBoardObjectsTestsSupport.item(.text, 100, 100, 600, 400)
        let overlapping = EaselBoardObjectsTestsSupport.item(.sticky, 650, 120, 220, 220)
        let nested = EaselBoardObjectsTestsSupport.item(.section, 150, 150, 300, 200)
        let twin = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let nudged = EaselBoardObjectsTestsSupport.item(.rectangle, 99.7, 120, 50, 50)
        let all = [section, inside, edge, overlapping, nested, twin, nudged]
        let members = Set(EaselBoardObjects.members(of: section, in: all).map(\.id))
        #expect(members == [inside.id, edge.id, nested.id, nudged.id], "Members sit fully inside, smaller sections count, equal sections and overhangs don't")
        #expect(EaselBoardObjects.members(of: inside, in: all).isEmpty, "Only sections have members")
        #expect(EaselBoardObjects.sections(containing: EaselPoint(x: 200, y: 200), in: all) == [section.id, nested.id, twin.id], "Every section under a point is found")
        var outer = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let inner = EaselBoardObjectsTestsSupport.item(.section, 99.6, 99.6, 300, 200)
        let sticky = EaselBoardObjectsTestsSupport.item(.sticky, 99.2, 99.2, 100, 100)
        let board = EaselBoardObjectsTestsSupport.document([outer, inner, sticky])
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

    @Test
    func sectionsPaintBelowTheirContentsAndParentSectionsPaintFirst() {
        let outer = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 800, 600, z: 9)
        let inner = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 300, 300, z: 1)
        let low = EaselBoardObjectsTestsSupport.item(.sticky, 120, 120, 100, 100, z: 0)
        let high = EaselBoardObjectsTestsSupport.item(.text, 500, 500, 50, 20, z: 5)
        let order = EaselBoardObjects.paintOrder([high, inner, low, outer]).map(\.id)
        #expect(order == [outer.id, inner.id, low.id, high.id], "Sections paint first, nested ones above their parent, then everything else by layer")
    }

    @Test
    func hiddenContentsLeaveTheDisplayAndTheirSectionStays() {
        let outer = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 800, 600, z: 9)
        let inner = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 300, 300, z: 1)
        let low = EaselBoardObjectsTestsSupport.item(.sticky, 120, 120, 100, 100, z: 0)
        let high = EaselBoardObjectsTestsSupport.item(.text, 500, 500, 50, 20, z: 5)
        let order = EaselBoardObjects.paintOrder([high, inner, low, outer]).map(\.id)
        #expect(order == [outer.id, inner.id, low.id, high.id], "Sections paint first, nested ones above their parent, then everything else by layer")
        var hiding = inner
        hiding.contentsHidden = true
        let shown = EaselBoardObjects.displayed([high, hiding, low, outer]).map(\.id)
        #expect(shown == [outer.id, hiding.id, high.id], "Hidden contents leave the display but their section stays")
    }

    @Test
    func aHiddenParentHidesItsNestedSectionsAndContents() {
        let outer = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 800, 600, z: 9)
        let inner = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 300, 300, z: 1)
        let low = EaselBoardObjectsTestsSupport.item(.sticky, 120, 120, 100, 100, z: 0)
        let high = EaselBoardObjectsTestsSupport.item(.text, 500, 500, 50, 20, z: 5)
        var hiding = inner
        hiding.contentsHidden = true
        var hidingOuter = outer
        hidingOuter.contentsHidden = true
        #expect(EaselBoardObjects.hiddenIDs(in: [hidingOuter, hiding, low, high]) == [hiding.id, low.id, high.id], "Hiding a parent hides nested sections and their contents")
    }

    @Test
    func aMarqueeSelectsOnlyFullyCoveredSectionsOutsideItsStartingSection() {
        let outer = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 800, 600, z: 9)
        let inner = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 300, 300, z: 1)
        let low = EaselBoardObjectsTestsSupport.item(.sticky, 120, 120, 100, 100, z: 0)
        let high = EaselBoardObjectsTestsSupport.item(.text, 500, 500, 50, 20, z: 5)
        let marquee = EaselRect(x: 90, y: 90, width: 400, height: 400)
        let candidates = EaselBoardObjects.marqueeCandidates([outer, inner, low, high], in: marquee, excluding: [outer.id]).map(\.id)
        #expect(candidates == [inner.id, low.id, high.id], "A marquee needs to cover a section fully and skips the one it started in")
        let partial = EaselBoardObjects.marqueeCandidates([inner], in: EaselRect(x: 0, y: 0, width: 200, height: 200), excluding: [])
        #expect(partial.isEmpty, "A marquee touching a section doesn't select it")
    }

    @Test
    func theHiddenSummaryUsesSingularAndPlural() {
        #expect(EaselBoardObjects.hiddenSummary(1) == "1 object hidden" && EaselBoardObjects.hiddenSummary(12) == "12 objects hidden", "The hidden count reads naturally")
    }

    @Test
    func deletingASectionRemovesItsUnlockedContents() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 600, 400)
        let sticky = EaselBoardObjectsTestsSupport.item(.sticky, 20, 20, 220, 220)
        var pinned = EaselBoardObjectsTestsSupport.item(.text, 300, 20, 100, 30)
        pinned.locked = true
        let outside = EaselBoardObjectsTestsSupport.item(.text, 700, 20, 100, 30)
        let board = EaselBoardObjectsTestsSupport.document([section, sticky, pinned, outside])
        #expect(EaselBoardObjects.deletion([section.id], in: board) == [section.id, sticky.id], "Deleting a section takes its unlocked contents")
        var lockedSection = section
        lockedSection.locked = true
        let lockedBoard = EaselBoardObjectsTestsSupport.document([lockedSection, sticky, outside])
        #expect(EaselBoardObjects.deletion([lockedSection.id], in: lockedBoard) == [lockedSection.id], "A locked section never drags its contents into a delete")
        #expect(EaselDependents.removing([section.id], from: board).items.map(\.id) == [pinned.id, outside.id], "The delete pipeline removes a section with its unlocked contents")
    }

    @Test
    func removingOnlySectionsKeepsTheirContents() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 600, 400)
        let sticky = EaselBoardObjectsTestsSupport.item(.sticky, 20, 20, 220, 220)
        var pinned = EaselBoardObjectsTestsSupport.item(.text, 300, 20, 100, 30)
        pinned.locked = true
        let outside = EaselBoardObjectsTestsSupport.item(.text, 700, 20, 100, 30)
        let board = EaselBoardObjectsTestsSupport.document([section, sticky, pinned, outside])
        let kept = EaselBoardObjects.removingSections([section.id, sticky.id], from: board)
        #expect(kept?.items.map(\.id) == [sticky.id, pinned.id, outside.id], "Removing only the section keeps everything else")
        #expect(EaselDependents.removing([section.id], from: board, keepingSectionContents: true).items.map(\.id)
               == [sticky.id, pinned.id, outside.id], "The keep-contents delete removes just the section")
        #expect(EaselBoardObjects.removingSections([sticky.id], from: board) == nil, "Removing sections needs a section")
    }

    @Test
    func copyingASectionIncludesLockedContents() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 600, 400)
        let sticky = EaselBoardObjectsTestsSupport.item(.sticky, 20, 20, 220, 220)
        var pinned = EaselBoardObjectsTestsSupport.item(.text, 300, 20, 100, 30)
        pinned.locked = true
        let outside = EaselBoardObjectsTestsSupport.item(.text, 700, 20, 100, 30)
        let board = EaselBoardObjectsTestsSupport.document([section, sticky, pinned, outside])
        #expect(EaselBoardObjects.withContents([section.id], in: board) == [section.id, sticky.id, pinned.id], "Copying a section brings everything inside it, locked or not")
    }

    @Test
    func lockingASectionCanIncludeItsContents() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 600, 400)
        let sticky = EaselBoardObjectsTestsSupport.item(.sticky, 20, 20, 220, 220)
        var pinned = EaselBoardObjectsTestsSupport.item(.text, 300, 20, 100, 30)
        pinned.locked = true
        let outside = EaselBoardObjectsTestsSupport.item(.text, 700, 20, 100, 30)
        let board = EaselBoardObjectsTestsSupport.document([section, sticky, pinned, outside])
        #expect(EaselBoardObjects.lockTargets([section.id], all: true, in: board) == [section.id, sticky.id, pinned.id], "Lock All covers the section and its contents")
        #expect(EaselBoardObjects.lockTargets([section.id, sticky.id], all: false, in: board) == [section.id], "Lock Background Only covers just the section")
    }

    @Test
    func togglingHiddenContentsChangesOnlySections() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 0, 0, 600, 400)
        let sticky = EaselBoardObjectsTestsSupport.item(.sticky, 20, 20, 220, 220)
        var pinned = EaselBoardObjectsTestsSupport.item(.text, 300, 20, 100, 30)
        pinned.locked = true
        let outside = EaselBoardObjectsTestsSupport.item(.text, 700, 20, 100, 30)
        let board = EaselBoardObjectsTestsSupport.document([section, sticky, pinned, outside])
        let hidden = EaselBoardObjects.settingContentsHidden(true, sections: [section.id, sticky.id], in: board)
        #expect(hidden?.items.first?.contentsHidden == true && hidden?.items[1].contentsHidden == nil, "Hiding marks only sections")
        #expect(EaselBoardObjects.settingContentsHidden(false, sections: [section.id], in: board) == nil, "Showing shown contents changes nothing")
        let shown = hidden.flatMap { EaselBoardObjects.settingContentsHidden(false, sections: [section.id], in: $0) }
        #expect(shown?.items.first?.contentsHidden == nil, "Showing contents leaves the field out of the file")
    }

    @Test
    func movingASectionCarriesEachContainedObjectOnce() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let nested = EaselBoardObjectsTestsSupport.item(.section, 150, 150, 200, 200)
        let deep = EaselBoardObjectsTestsSupport.item(.sticky, 160, 160, 100, 100)
        let arrow = EaselBoardObjectsTestsSupport.item(.arrow, 400, 300, 100, 50)
        let outside = EaselBoardObjectsTestsSupport.item(.text, 800, 100, 100, 30)
        let selected = EaselBoardObjectsTestsSupport.item(.sticky, 450, 150, 100, 100)
        let before = EaselBoardObjectsTestsSupport.document([section, nested, deep, arrow, outside, selected])
        var after = before
        after.items[0].frame.x += 50; after.items[0].frame.y += 20
        after.items[5].frame.x += 50; after.items[5].frame.y += 20
        let result = EaselBoardObjects.carryingSectionContents(after, previous: before, moved: [section.id, selected.id])
        let frames = Dictionary(result.document.items.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        #expect(frames[nested.id]?.x == 200 && frames[deep.id]?.y == 180 && frames[arrow.id]?.x == 450, "Moving a section carries everything inside it, nested sections included")
        #expect(frames[outside.id] == outside.frame, "Objects outside stay put")
        #expect(frames[selected.id]?.x == 500, "Objects already moving are not moved twice")
        #expect(result.moved == [section.id, selected.id, nested.id, deep.id, arrow.id], "Carried objects join the moved set")
    }

    @Test
    func resizingASectionDoesNotMoveItsContents() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let nested = EaselBoardObjectsTestsSupport.item(.section, 150, 150, 200, 200)
        let deep = EaselBoardObjectsTestsSupport.item(.sticky, 160, 160, 100, 100)
        let arrow = EaselBoardObjectsTestsSupport.item(.arrow, 400, 300, 100, 50)
        let outside = EaselBoardObjectsTestsSupport.item(.text, 800, 100, 100, 30)
        let selected = EaselBoardObjectsTestsSupport.item(.sticky, 450, 150, 100, 100)
        let before = EaselBoardObjectsTestsSupport.document([section, nested, deep, arrow, outside, selected])
        var resized = before
        resized.items[0].frame.x -= 40; resized.items[0].frame.width += 40
        let resizing = EaselBoardObjects.carryingSectionContents(resized, previous: before, moved: [section.id])
        #expect(resizing.document == resized && resizing.moved == [section.id], "Resizing a section never moves its contents")
    }

    @Test
    func movingASectionCarriesHiddenContents() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let nested = EaselBoardObjectsTestsSupport.item(.section, 150, 150, 200, 200)
        let deep = EaselBoardObjectsTestsSupport.item(.sticky, 160, 160, 100, 100)
        let arrow = EaselBoardObjectsTestsSupport.item(.arrow, 400, 300, 100, 50)
        let outside = EaselBoardObjectsTestsSupport.item(.text, 800, 100, 100, 30)
        let selected = EaselBoardObjectsTestsSupport.item(.sticky, 450, 150, 100, 100)
        let before = EaselBoardObjectsTestsSupport.document([section, nested, deep, arrow, outside, selected])
        var hidden = before
        hidden.items[0].contentsHidden = true
        var hiddenAfter = hidden
        hiddenAfter.items[0].frame.y += 10
        let hiddenCarry = EaselBoardObjects.carryingSectionContents(hiddenAfter, previous: hidden, moved: [section.id])
        #expect(hiddenCarry.document.items[2].frame.y == 170, "Hidden contents travel with their section")
    }

    @Test
    func movingANestedSectionAloneCarriesItsOwnContents() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let nested = EaselBoardObjectsTestsSupport.item(.section, 150, 150, 200, 200)
        let deep = EaselBoardObjectsTestsSupport.item(.sticky, 160, 160, 100, 100)
        let arrow = EaselBoardObjectsTestsSupport.item(.arrow, 400, 300, 100, 50)
        let outside = EaselBoardObjectsTestsSupport.item(.text, 800, 100, 100, 30)
        let selected = EaselBoardObjectsTestsSupport.item(.sticky, 450, 150, 100, 100)
        let before = EaselBoardObjectsTestsSupport.document([section, nested, deep, arrow, outside, selected])
        var back = before
        back.items[1].frame.x = 0; back.items[1].frame.y = 0
        let alone = EaselBoardObjects.carryingSectionContents(back, previous: before, moved: [nested.id])
        #expect(alone.document.items[2].frame.x == 10 && alone.document.items[2].frame.y == 10, "A nested section carries its own contents when it moves alone")
    }

    @Test
    func movingWithoutASectionLeavesTheMoveAlone() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let nested = EaselBoardObjectsTestsSupport.item(.section, 150, 150, 200, 200)
        let deep = EaselBoardObjectsTestsSupport.item(.sticky, 160, 160, 100, 100)
        let arrow = EaselBoardObjectsTestsSupport.item(.arrow, 400, 300, 100, 50)
        let outside = EaselBoardObjectsTestsSupport.item(.text, 800, 100, 100, 30)
        let selected = EaselBoardObjectsTestsSupport.item(.sticky, 450, 150, 100, 100)
        let before = EaselBoardObjectsTestsSupport.document([section, nested, deep, arrow, outside, selected])
        let unchanged = EaselBoardObjects.carryingSectionContents(before, previous: before, moved: [outside.id])
        #expect(unchanged.document == before && unchanged.moved == [outside.id], "Moves without sections pass straight through")
    }

    @Test
    func aSectionAndItsContentsStopAtTheCanvasEdge() {
        let section = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let nested = EaselBoardObjectsTestsSupport.item(.section, 150, 150, 200, 200)
        let deep = EaselBoardObjectsTestsSupport.item(.sticky, 160, 160, 100, 100)
        let arrow = EaselBoardObjectsTestsSupport.item(.arrow, 400, 300, 100, 50)
        let outside = EaselBoardObjectsTestsSupport.item(.text, 800, 100, 100, 30)
        let selected = EaselBoardObjectsTestsSupport.item(.sticky, 450, 150, 100, 100)
        let before = EaselBoardObjectsTestsSupport.document([section, nested, deep, arrow, outside, selected])
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
                                             in: [EaselBoardObjectsTestsSupport.item(.section, 0, 0, 10, 10, text: "Section")], zIndex: 4)
        #expect(made.kind == .section && made.text == "Section 2" && made.zIndex == 4, "New sections take the next free name")
        let section = EaselBoardObjectsTestsSupport.item(.section, 100, 100, 600, 400)
        let tab = EaselBoardObjects.titleTab(section, titleWidth: 60, zoom: 1)
        #expect(tab == EaselRect(x: 100, y: 68, width: 80, height: 26), "The title tab sits above the top-left corner")
        let zoomedOut = EaselBoardObjects.titleTab(section, titleWidth: 60, zoom: 0.5)
        #expect(zoomedOut.height == 52 && zoomedOut.y == 100 - 64, "Zoomed out, the title stays readable")
        let high = EaselBoardObjects.titleTab(EaselBoardObjectsTestsSupport.item(.section, 0, 10, 600, 400), titleWidth: 1000, zoom: 1)
        #expect(high.y == 16 && high.width == 600, "Without room above, the title tucks inside and never overhangs")
    }
}
