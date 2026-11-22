import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarSpaceHeaderTestsContentTests {
    private typealias Support = SidebarSpaceHeaderTestsSupport
    private typealias H = Support.H
    private typealias Content = Support.Content
    private typealias Header = Support.Header

    @Test func aFreshSingleSpaceHasNoHeaderThePlaceholderAndShowSpaceHeader() {
        let first = Support.space("Space 1")
        #expect(Support.content([first], first) == Content(isShown: false, title: "", placeholder: "Space 1", toggleTitle: "Show Space Header"))
    }

    @Test func theSettingShowsItAndTheMenuOffersHideSpaceHeader() {
        let first = Support.space("Space 1")
        #expect(Support.content([first], first, setting: true) == Content(isShown: true, title: "", placeholder: "Space 1", toggleTitle: "Hide Space Header"))
    }

    struct SpacePosition: CustomTestStringConvertible {
        let testDescription: String
        let index: Int
        let placeholder: String
    }

    @Test(arguments: [
        SpacePosition(testDescription: "First Space", index: 0, placeholder: "Space 1"),
        SpacePosition(testDescription: "Second Space", index: 1, placeholder: "Space 2"),
    ])
    func aSecondSpaceShowsTheHeaderWithEachPositionsPlaceholderAndNoToggle(_ sample: SpacePosition) {
        let spaces = [Support.space("Space 1"), Support.space("Space 2")]
        #expect(Support.content(spaces, spaces[sample.index]) == Content(isShown: true, title: "", placeholder: sample.placeholder, toggleTitle: nil))
    }

    @Test func renamingFromSpaceOneTitlesIt() {
        var first = Support.space("Space 1")
        first.name = "Work"
        #expect(Support.content([first], first) == Support.titled("Work"))
    }

    @Test func explicitlyRenamingToSpaceOneKeepsAnAuthoredTitle() {
        var first = Support.space("Space 1")
        first.name = "Work"
        first.name = "Space 1"
        #expect(Support.content([first], first) == Support.titled("Space 1"))
    }

    @Test func anEmptyNameIsUntitled() {
        var first = Support.space("Space 1")
        first.name = "Work"
        first.name = ""
        #expect(Support.content([first], first) == Content(isShown: false, title: "", placeholder: "Space 1", toggleTitle: "Show Space Header"))
    }

    @Test func spaceOneInTheSecondPositionIsATitle() {
        var first = Support.space("Space 1")
        first.name = ""
        first.name = "Space 1"
        #expect(Support.content([Support.space("Space 2"), first], first) == Support.titled("Space 1"))
    }

    @Test func aCustomIconShowsTheHeaderAndDropsTheToggle() {
        let starred = Support.space("Space 1", icon: .symbol("star"))
        #expect(Support.content([starred], starred) == Content(isShown: true, title: "", placeholder: "Space 1", toggleTitle: nil))
    }

    @Test func neverInAPrivateWindow() {
        let first = Support.space("Space 1"), second = Support.space("Space 2"), starred = Support.space("Space 1", icon: .symbol("star"))
        #expect(!Support.content([first, second, starred], starred, privateWindow: true, setting: true).isShown)
        #expect(!Support.content([first], first, privateWindow: true, setting: true).isShown)
    }

    @Test func noActiveSpaceNoHeader() {
        #expect(Support.content([Support.space("Space 1")], nil) == Content(isShown: false, title: "", placeholder: nil, toggleTitle: nil))
    }

    struct RenameClick: CustomTestStringConvertible {
        let testDescription: String
        let count: Int
        let modifiers: NSEvent.ModifierFlags
        let editing: Bool
    }

    @Test(arguments: [
        RenameClick(testDescription: "Control double-click", count: 2, modifiers: .control, editing: false),
        RenameClick(testDescription: "Double-click during rename", count: 2, modifiers: [], editing: true),
        RenameClick(testDescription: "Triple-click", count: 3, modifiers: [], editing: false),
    ])
    func aControlDoubleClickARenameDoubleClickOrATripleClickLeavesTheNameAlone(_ sample: RenameClick) {
        #expect(!H.beginsRename(clickCount: sample.count, modifiers: sample.modifiers, editing: sample.editing))
    }
}
