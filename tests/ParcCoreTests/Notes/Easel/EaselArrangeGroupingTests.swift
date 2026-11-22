import Foundation
import Testing
@testable import ParcCore

struct EaselArrangeGroupingTests {
    @Test
    func groupingTagsTheChosenObjects() throws {
        let a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), c = EaselArrangeTestsSupport.box(400, 0)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let id = UUID()
        let grouped = try #require(EaselArrange.grouped(board, ids: [a.id, b.id], groupID: id), "Two objects group")
        #expect(grouped.items.filter { $0.groupID == id }.count == 2, "Grouping tags every chosen object")
        #expect(!EaselArrange.canGroup([a.id, b.id], in: grouped), "A whole group can't be grouped with itself")
        #expect(EaselArrange.wholeGroup([a.id, b.id], in: grouped) == id, "The members of one group read as that group")
        #expect(EaselArrange.expandingGroups([a.id], in: grouped) == [a.id, b.id], "Picking one member reaches the whole group")
    }

    @Test
    func regroupingObjectsAppliesANewGroupID() throws {
        let a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), c = EaselArrangeTestsSupport.box(400, 0)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let id = UUID()
        let grouped = try #require(EaselArrange.grouped(board, ids: [a.id, b.id], groupID: id), "Two objects group")
        let outer = UUID()
        let nested = try #require(EaselArrange.grouped(grouped, ids: [a.id, b.id, c.id], groupID: outer), "Groups regroup")
        #expect(nested.items.allSatisfy { $0.groupID == outer }, "Grouping grouped objects puts them all in the new group")
    }

    @Test
    func regroupingDissolvesASingleMemberGroup() throws {
        let a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), c = EaselArrangeTestsSupport.box(400, 0)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let id = UUID()
        let grouped = try #require(EaselArrange.grouped(board, ids: [a.id, b.id], groupID: id), "Two objects group")
        let outer = UUID()
        let partial = try #require(EaselArrange.grouped(grouped, ids: [b.id, c.id], groupID: outer), "Partial regroup")
        #expect(partial.items.first { $0.id == a.id }?.groupID == nil, "A group left with one member dissolves")
    }

    @Test
    func ungroupingOneMemberFreesTheWholeGroup() throws {
        let a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), c = EaselArrangeTestsSupport.box(400, 0)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let id = UUID()
        let grouped = try #require(EaselArrange.grouped(board, ids: [a.id, b.id], groupID: id), "Two objects group")
        let ungrouped = try #require(EaselArrange.ungrouped(grouped, ids: [a.id]), "Ungroup works from one member")
        #expect(ungrouped.items.allSatisfy { $0.groupID == nil }, "Ungroup frees every member of the group")
    }

    @Test
    func ungroupingALooseObjectDoesNothing() {
        let a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), c = EaselArrangeTestsSupport.box(400, 0)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        #expect(EaselArrange.ungrouped(board, ids: [a.id]) == nil, "Ungrouping a loose object changes nothing")
    }

    @Test
    func aSelectionOnlySharesAGroupWhenItsMembersAgree() throws {
        let a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), c = EaselArrangeTestsSupport.box(400, 0)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let id = UUID()
        let grouped = try #require(EaselArrange.grouped(board, ids: [a.id, b.id], groupID: id), "Two objects group")
        #expect(EaselArrange.sharedGroup([a.id], in: grouped) == id && EaselArrange.sharedGroup([a.id, c.id], in: grouped) == nil, "Shift-Return finds the group shared by the selection")
    }

    @Test func lockMarksTheObject() throws {
        let a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(10, 10)
        let board = EaselArrangeTestsSupport.document([a, b])
        let locked = try #require(EaselArrange.settingLock(true, ids: [a.id], in: board), "Locking changes the board")
        #expect(locked.items.first { $0.id == a.id }?.locked == true, "Lock marks the object")
        #expect(EaselArrange.shouldLock([a.id, b.id], in: locked), "A mixed selection locks")
        #expect(!EaselArrange.shouldLock([a.id], in: locked), "An all-locked selection unlocks")
        let unlocked = EaselArrange.settingLock(false, ids: [a.id], in: locked)
        #expect(unlocked?.items.first { $0.id == a.id }?.locked == nil, "Unlocking leaves the field out of the file")
        #expect(EaselArrange.settingLock(false, ids: [b.id], in: board) == nil, "Unlocking an unlocked object changes nothing")
        #expect(!EaselArrange.canAlign([a.id, b.id], in: locked), "One movable object left means nothing to align")
        #expect(!EaselArrange.canGroup([a.id, b.id], in: locked), "Locked objects stay out of new groups")
    }

    @Test
    func aClickPicksTheGroupsUnlockedMembers() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let click = EaselArrange.clickSelection(hit: a, selection: [], entered: nil, extending: false, clickCount: 1, in: board)
        #expect(click.selection == [a.id, b.id] && !click.enteredByClick, "A click picks the group's unlocked members")
    }

    @Test
    func doubleClickOpensAGroupOnOneMember() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let click = EaselArrange.clickSelection(hit: a, selection: [], entered: nil, extending: false, clickCount: 1, in: board)
        let enter = EaselArrange.clickSelection(hit: b, selection: click.selection, entered: nil, extending: false, clickCount: 2, in: board)
        #expect(enter.selection == [b.id] && enter.enteredGroup == group && enter.enteredByClick, "Double-click opens the group on one member")
    }

    @Test
    func shiftClickInAnOpenGroupAddsSingleMembers() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let click = EaselArrange.clickSelection(hit: a, selection: [], entered: nil, extending: false, clickCount: 1, in: board)
        let enter = EaselArrange.clickSelection(hit: b, selection: click.selection, entered: nil, extending: false, clickCount: 2, in: board)
        let inside = EaselArrange.clickSelection(hit: a, selection: enter.selection, entered: group, extending: true, clickCount: 1, in: board)
        #expect(inside.selection == [a.id, b.id] && inside.enteredGroup == group, "Inside an open group Shift-click adds single members")
    }

    @Test
    func clickingOutsideClosesTheGroup() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let click = EaselArrange.clickSelection(hit: a, selection: [], entered: nil, extending: false, clickCount: 1, in: board)
        let enter = EaselArrange.clickSelection(hit: b, selection: click.selection, entered: nil, extending: false, clickCount: 2, in: board)
        let inside = EaselArrange.clickSelection(hit: a, selection: enter.selection, entered: group, extending: true, clickCount: 1, in: board)
        let leave = EaselArrange.clickSelection(hit: loose, selection: inside.selection, entered: group, extending: false, clickCount: 1, in: board)
        #expect(leave.selection == [loose.id] && leave.enteredGroup == nil, "Clicking outside closes the group")
    }

    @Test
    func aStaleOpenGroupClosesWhenNoneOfItsMembersAreSelected() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let stale = EaselArrange.clickSelection(hit: a, selection: [loose.id], entered: group, extending: false, clickCount: 1, in: board)
        #expect(stale.selection == [a.id, b.id], "A group left long ago is closed again when nothing in it is selected")
    }

    @Test
    func shiftClickCanSelectALockedMemberForUnlocking() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let unlocking = EaselArrange.clickSelection(hit: locked, selection: [], entered: nil, extending: true, clickCount: 1, in: board)
        #expect(unlocking.selection == [a.id, b.id, locked.id], "Shift-clicking a locked member picks it along with its group for unlocking")
    }

    @Test
    func shiftClickOnASelectedGroupDeselectsIt() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let toggled = EaselArrange.clickSelection(hit: a, selection: [a.id, b.id], entered: nil, extending: true, clickCount: 1, in: board)
        #expect(toggled.selection.isEmpty, "Shift-click on a selected group drops the whole group")
    }

    @Test
    func marqueeSelectsUnlockedMembersOfAClosedGroup() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let swept = EaselArrange.marqueeSelection(hits: [a.id, locked.id], original: [], operation: .replace, entered: nil, in: board)
        #expect(swept == [a.id, b.id], "A marquee widens to the group and leaves its locked member behind")
    }

    @Test
    func anAdditiveMarqueeKeepsPreviouslySelectedLockedObjects() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let added = EaselArrange.marqueeSelection(hits: [loose.id], original: [locked.id], operation: .add, entered: nil, in: board)
        #expect(added == [locked.id, loose.id], "Shift-marquee keeps a locked object picked earlier")
    }

    @Test
    func marqueeSelectsIndividualMembersOfAnOpenGroup() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        let opened = EaselArrange.marqueeSelection(hits: [a.id], original: [], operation: .replace, entered: group, in: board)
        #expect(opened == [a.id], "Inside an open group a marquee picks single members")
    }

    @Test
    func easelChordsRequireCanvasOrEditorFocus() {
        #expect(EaselChords.consults(canvasFocus: true, editorFocus: false) && EaselChords.consults(canvasFocus: false, editorFocus: true)
               && !EaselChords.consults(canvasFocus: false, editorFocus: false), "Chords only apply with Easel focus")
    }

    @Test
    func duplicateAppliesToLockedButNotVanishedObjects() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        #expect(!EaselChords.applies(.duplicate, selection: [UUID()], in: board), "A stale selection lets ⌘D reach Parc")
        #expect(EaselChords.applies(.duplicate, selection: [locked.id], in: board), "Locked objects can still be duplicated")
    }

    @Test
    func groupChordsOnlyClaimEligibleSelections() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        #expect(!EaselChords.applies(.group, selection: [a.id], in: board) && EaselChords.applies(.group, selection: [loose.id, a.id], in: board), "⌘G only claims two or more objects")
    }

    @Test
    func ungroupChordsOnlyClaimGroupMembers() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        #expect(EaselChords.applies(.ungroup, selection: [a.id], in: board) && !EaselChords.applies(.ungroup, selection: [loose.id], in: board), "⇧⌘G only claims a group")
    }

    @Test
    func layerChordsSkipLockedObjects() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        #expect(!EaselChords.applies(.layer(.forward), selection: [locked.id], in: board), "Locked objects leave ⌘] to Parc")
    }

    @Test
    func otherChordsKeepTheirOwnAdmissionRules() {
        let group = UUID()
        var a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(200, 0), locked = EaselArrangeTestsSupport.box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = EaselArrangeTestsSupport.box(600, 0)
        let board = EaselArrangeTestsSupport.document([a, b, locked, loose])
        #expect(!EaselChords.applies(.alignText(.left), selection: [a.id], in: board), "Other features' chords decide for themselves")
    }
}
