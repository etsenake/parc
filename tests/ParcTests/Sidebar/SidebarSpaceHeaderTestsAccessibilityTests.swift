import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarSpaceHeaderTestsAccessibilityTests {
    private typealias Support = SidebarSpaceHeaderTestsSupport
    private typealias Header = Support.Header

    @Test func thePlaceholderIsAppKitsInTheSameSlotAsATitle() {
        let (header, reference) = Support.placeholder()
        #expect(header.field.stringValue == "" && header.field.placeholderString == "Space 1" && header.field.placeholderAttributedString == nil)
        #expect(header.field.intrinsicContentSize.height == reference.nameField.intrinsicContentSize.height)
        #expect(header.field.frame == reference.nameField.frame)
    }

    @Test(arguments: [false, true])
    func thePlaceholderDrawsInPlaceholderTextColorNotTheDarkerForeground(_ dark: Bool) {
        let (header, reference) = Support.placeholder()
        header.host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        header.header.applyStyle(dark: dark, tint: nil); reference.applyStyle(dark: dark, tint: nil)
        let name = Support.pixels(reference.nameField)
        reference.nameField.textColor = .placeholderTextColor
        let drawn = Support.pixels(header.field), expected = Support.pixels(reference.nameField)
        #expect(drawn != nil && drawn == expected && drawn != name)
    }

    @Test func anUntitledSpaceReadsAsAnEmptyValueWithThePlaceholder() {
        let (header, _) = Support.placeholder()
        let element = header.exposed.first as? NSCell
        #expect(element?.accessibilityValue() as? String == "" && element?.accessibilityPlaceholderValue() == "Space 1")
    }

    @Test func theHeaderExposesTheNameFieldsCellThenTheRestingEditButtons() {
        let header = Header()
        let children = header.exposed
        #expect(children.count == 2 && children.first === header.field.cell && children.last === header.button.cell)
    }

    @Test func aTitleReadsAsStaticTextWithTheSpaceNameIdentifier() throws {
        let header = Header()
        let name = try #require(header.exposed.first as? NSCell)
        #expect(name.accessibilityRole() == .staticText && name.accessibilityValue() as? String == "Work" && name.accessibilityPlaceholderValue() == nil)
        #expect(name.accessibilityIdentifier() == "sidebarSpaceName" && header.field.accessibilityIdentifier() == "sidebarSpaceName")
    }

    @Test func theEditButtonIsAnAXButtonWithItsIdentifierAndNoLabelOrTooltipOfItsOwn() throws {
        let header = Header()
        let edit = try #require(header.exposed.last as? NSCell)
        let plain = NSButton(frame: .zero)
        plain.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "")
        #expect(edit.accessibilityRole() == .button && edit.accessibilityIdentifier() == "sidebarSpaceEditButton")
        #expect(header.button.accessibilityIdentifier() == "sidebarSpaceEditButton")
        #expect(edit.accessibilityLabel() == plain.cell?.accessibilityLabel() && header.button.toolTip == nil)
    }

    @Test func aShownEmojiIconIsNotAnElement() {
        let header = Header()
        header.header.update(Support.titled("Trips"), symbol: nil, emoji: "🌴")
        #expect(header.exposed.count == 2 && !header.emoji.isAccessibilityElement() && header.emoji.cell?.isAccessibilityElement() == false)
    }

    @Test func theSymbolViewAndTheHeaderAreNotElements() {
        let header = Header()
        #expect(!header.symbolView.isAccessibilityElement() && !header.header.isAccessibilityElement())
    }

    @Test func aTitledSpacesRightClickMenuHasTheSpaceTitlesAndNoToggle() {
        let header = Header()
        let menu = header.click.flatMap { header.header.menu(for: $0) }
        #expect(menu?.items.map(\.title) == Support.base && menu?.items.allSatisfy(\.isEnabled) == true)
        #expect((header.field.cell?.accessibilityCustomActions() ?? []).map(\.name) == Support.base)
    }

    private func untitledShown() -> Header {
        var first = Support.space("Space 1")
        first.title = nil
        let header = Header()
        header.header.update(Support.content([first], first, setting: true), symbol: nil, emoji: nil)
        return header
    }

    @Test func oneUntitledSpaceShownByTheSettingOffersHideSpaceHeaderLastAndEachItemRunsItsAction() {
        let header = untitledShown()
        let menu = header.click.flatMap { header.header.menu(for: $0) }
        #expect(menu?.items.map(\.title) == Support.base + ["Hide Space Header"] && menu?.items.allSatisfy(\.isEnabled) == true)
        for index in 0..<(menu?.items.count ?? 0) { menu?.performActionForItem(at: index) }
        #expect(header.calls == ["rename", "theme", "folder", "toggle"])
    }

    @Test func voiceOverGetsTheSameActionsWhichRunTheSameParcActions() {
        let header = untitledShown()
        let actions = header.field.cell?.accessibilityCustomActions() ?? []
        #expect(actions.map(\.name) == Support.base + ["Hide Space Header"])
        #expect((header.field.accessibilityCustomActions() ?? []).map(\.name) == actions.map(\.name))
        for action in actions { _ = action.handler?() }
        #expect(header.calls == ["rename", "theme", "folder", "toggle"])
    }

    @Test func theToggleLeavesWithTheContentsToggleTitle() {
        let header = untitledShown()
        header.header.update(Support.titled("Work"), symbol: nil, emoji: nil)
        #expect(header.header.makeMenu().items.map(\.title) == Support.base && (header.field.cell?.accessibilityCustomActions() ?? []).count == 3)
    }

    @Test func aSingleClickOnTheNameDoesNotRename() {
        let header = Header(icon: false)
        header.press(clickCount: 1)
        #expect(header.calls.isEmpty)
    }

    @Test func doubleClickingTheNameStartsRename() {
        let header = Header(icon: false)
        header.press(clickCount: 2)
        #expect(header.calls == ["rename"])
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, .shift, .option])
    func aModifiedDoubleClickDoesNotRename(_ modifiers: NSEvent.ModifierFlags) {
        let header = Header(icon: false)
        header.press(clickCount: 2, modifiers: modifiers)
        #expect(header.calls.isEmpty)
    }
}
