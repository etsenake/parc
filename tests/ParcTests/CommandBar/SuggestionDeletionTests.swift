import AppKit
import Testing
@testable import Parc
@testable import ParcCommandBar

@MainActor
struct SuggestionDeletionTests {
    final class Calls {
        var deleted = 0
        var opened = 0
        var eligible = true
    }

    let calls = Calls()

    func historyRow() throws -> (row: CommandResultCell, button: NSButton) {
        CommandBarTestSupport.prepareAppKit()
        let row = CommandResultCell(title: "History result", detail: "example.test", accessory: "", isTab: false, icon: nil, enabled: true)
        row.onPress = { [calls] in calls.opened += 1; return true }
        row.onDelete = { [calls] in
            guard calls.eligible else { return false }
            calls.deleted += 1
            calls.eligible = false
            return true
        }
        let button = try #require(row.subviews.compactMap { $0 as? NSButton }.first)
        return (row, button)
    }

    @Test func deleteIsHiddenUntilTheRowIsHovered() throws {
        let (_, button) = try historyRow()
        #expect(button.isHidden)
    }

    @Test func keyboardSelectionDoesNotRevealDelete() throws {
        let (row, button) = try historyRow()
        row.setSelected(true)
        #expect(button.isHidden)
    }

    @Test func hoverRevealsAnEnabledDeleteControl() throws {
        let (row, button) = try historyRow()
        row.setHovered(true)
        #expect(!button.isHidden)
        #expect(button.isEnabled)
    }

    @Test func theDeleteControlIsNamedForAccessibility() throws {
        let (_, button) = try historyRow()
        #expect(button.accessibilityLabel() == "Delete Suggestion")
    }

    @Test(arguments: [745, 320, 220] as [CGFloat])
    func deleteKeepsItsOwnTrailingBoundsAtEveryWidth(width: CGFloat) throws {
        let (row, button) = try historyRow()
        row.frame = NSRect(x: 0, y: 0, width: width, height: 50)
        row.needsLayout = true
        row.layoutSubtreeIfNeeded()
        #expect(button.frame.maxX <= width)
        #expect(button.frame.width == 23)
    }

    @Test(arguments: [745, 320, 220] as [CGFloat])
    func aLongLabelCannotCoverDelete(width: CGFloat) throws {
        let (row, button) = try historyRow()
        row.frame = NSRect(x: 0, y: 0, width: width, height: 50)
        row.needsLayout = true
        row.layoutSubtreeIfNeeded()
        let text = try #require(row.subviews.compactMap { $0 as? NSTextField }.first { $0.attributedStringValue.string.contains("History result") })
        #expect(text.frame.maxX <= button.frame.minX)
    }

    @Test func accessibilityOffersDeleteAsItsOwnAction() throws {
        let (row, _) = try historyRow()
        #expect(row.accessibilityCustomActions()?.first?.name == "Delete Suggestion")
    }

    @Test func accessibilityDeleteReachesTheDeletionCallbackNotNavigation() throws {
        let (row, _) = try historyRow()
        let action = try #require(row.accessibilityCustomActions()?.first)
        #expect(action.handler?() == true)
        #expect(calls.deleted == 1)
        #expect(calls.opened == 0)
    }

    @Test func anExpiredOwnerCanRefuseARetainedAccessibilityAction() throws {
        let (row, _) = try historyRow()
        let action = try #require(row.accessibilityCustomActions()?.first)
        calls.eligible = false
        #expect(action.handler?() == false)
        #expect(calls.deleted == 0)
    }

    @Test func clickingTheControlUsesTheSameDeletionCallback() throws {
        let (_, button) = try historyRow()
        button.sendClick()
        #expect(calls.deleted == 1)
        #expect(calls.opened == 0)
    }

    @Test func leavingTheRowHidesDeleteAgain() throws {
        let (row, button) = try historyRow()
        row.setHovered(true)
        row.setHovered(false)
        #expect(button.isHidden)
    }

    @Test func revokingDeletionRemovesTheAccessibilityAction() throws {
        let (row, _) = try historyRow()
        row.onDelete = nil
        #expect(row.accessibilityCustomActions()?.isEmpty == true)
    }

    @Test func aRetainedAccessibilityActionCannotBypassRevocation() throws {
        let (row, _) = try historyRow()
        let action = try #require(row.accessibilityCustomActions()?.first)
        row.onDelete = nil
        #expect(action.handler?() == false)
        #expect(calls.deleted == 0)
    }

    @Test func openingRemainsItsOwnCallback() throws {
        let (row, _) = try historyRow()
        #expect(row.accessibilityPerformPress())
        #expect(calls.opened == 1)
        #expect(calls.deleted == 0)
    }

    @Test func aDisabledRowGatesAccessibilityDeletion() {
        CommandBarTestSupport.prepareAppKit()
        let disabled = CommandResultCell(title: "Unavailable", detail: "", accessory: "", isTab: false, icon: nil, enabled: false)
        disabled.onDelete = { [calls] in calls.deleted += 1; return true }
        #expect(disabled.accessibilityCustomActions()?.first?.handler?() == false)
        #expect(calls.deleted == 0)
    }

    @Test func aCommandWithoutANativeProviderHasNoDeleteButton() {
        CommandBarTestSupport.prepareAppKit()
        let local = CommandResultCell(title: "New Note", detail: "", accessory: "⌘N", isTab: false, icon: nil, enabled: true)
        local.setHovered(true)
        let visibleButtons = local.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }
        #expect(visibleButtons.isEmpty)
    }

    @Test func aCommandWithoutANativeProviderHasNoDeleteAction() {
        CommandBarTestSupport.prepareAppKit()
        let local = CommandResultCell(title: "New Note", detail: "", accessory: "⌘N", isTab: false, icon: nil, enabled: true)
        #expect(local.accessibilityCustomActions()?.isEmpty != false)
    }
}
