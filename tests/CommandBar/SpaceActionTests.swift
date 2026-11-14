import AppKit

@main @MainActor
struct SpaceActionTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; precondition(condition(), message)
    }
    static func main() {
        let personal = BrowserProfile(id: UUID(), name: "Personal")
        let work = BrowserProfile(id: UUID(), name: "Work")
        let profiles = [personal, work]
        let first = BrowserSpace(id: UUID(), name: "Research", symbol: "circle.fill", color: "ABCDEF", profileID: personal.id)
        var second = BrowserSpace(id: UUID(), name: "Research", symbol: "star.fill", color: "ABCDEF", profileID: work.id)
        let cafe = BrowserSpace(id: UUID(), name: "Café", symbol: "cup.and.saucer", color: "ABCDEF", profileID: personal.id)
        let invalid = BrowserSpace(id: UUID(), name: "Removed profile", symbol: "circle", color: "ABCDEF", profileID: UUID())
        let original = CommandBarSpaceAction.snapshot(spaces: [first, second, cafe, invalid], profiles: profiles)
        expect(original.count == 3, "Missing profiles never become destinations")
        expect(Set(original.map(\.id)).count == 3, "Identical names retain distinct original identities")
        expect(original[0].detail == "Space 1" && original[1].detail == "Space 2", "Duplicate names expose their position")
        expect(original[2].detail.isEmpty, "Unique Space retains the compact reference row")
        expect(CommandBarSpaceAction.matching(original, query: "space").map(\.id) == original.map(\.id), "Generic Space query preserves user order")
        expect(CommandBarSpaceAction.matching(original, query: "research").map(\.spaceID) == [first.id, second.id], "Duplicate names both match")
        expect(CommandBarSpaceAction.matching(original, query: "focus on cafe").map(\.spaceID) == [cafe.id], "Word matching and accents preserve actual destination")
        expect(CommandBarSpaceAction.matching(original, query: "  ").isEmpty, "Empty query does not replace recent tab/history behavior")
        expect(CommandBarSpaceAction.matching(original, query: "> space").isEmpty, "No invented command-only trigger")
        expect(CommandBarSpaceAction.matching(original, query: "https://space.test").isEmpty, "An address is not reinterpreted as a Space")
        second.name = "Renamed"
        let renamed = CommandBarSpaceAction.snapshot(spaces: [first, second, cafe], profiles: profiles)
        expect(renamed[1].id == original[1].id && renamed[1].name == "Renamed", "Rename refreshes presentation without changing the action identity")
        expect(original[1].isCurrent(spaces: [first, second, cafe], profiles: profiles), "Original target remains the same Space after rename")
        expect(!original[1].isCurrent(spaces: [first, cafe], profiles: profiles), "Removed original cannot redirect to a same-name Space")
        expect(!original[1].isCurrent(spaces: [first, second], profiles: [personal]), "Retired profile invalidates original target")
        second.profileID = personal.id
        expect(!original[1].isCurrent(spaces: [first, second], profiles: profiles), "Reassigned profile cannot satisfy an old target")
        let reassigned = CommandBarSpaceAction.snapshot(spaces: [second], profiles: profiles)[0]
        expect(reassigned.id != original[1].id, "Reassignment changes row identity so a highlighted old action can expire")

        _ = NSApplication.shared
        let row = CommandResultCell(title: original[1].title, detail: original[1].detail, accessory: "", isTab: false,
            icon: NSImage(systemSymbolName: "arrow.right.square.fill", accessibilityDescription: nil), enabled: true, spaceAction: original[1])
        row.frame = NSRect(x: 0, y: 0, width: 745, height: 50)
        row.layoutSubtreeIfNeeded()
        expect(row.subviews.first(where: { $0.toolTip != nil })?.frame.width ?? 0 > 0, "The actual native capsule is laid out")
        expect(row.accessibilityLabel() == "Focus on, Research, Space 2", "Native AX exposes full original name/position")
        expect(row.isAccessibilityEnabled(), "Available row exposes its native action")
        var presses = 0
        row.onPress = { presses += 1; return true }
        expect(row.accessibilityPerformPress() && presses == 1, "AX press invokes the same owned selection callback")
        row.setSelected(true)
        expect(row.isAccessibilitySelected(), "Selection is exposed without changing the typed query")
        for width: CGFloat in [745, 320, 220] {
            row.frame.size.width = width; row.needsLayout = true; row.layoutSubtreeIfNeeded()
            expect(row.subviews.filter { !$0.isHidden }.allSatisfy { $0.frame.width >= 0 && $0.frame.minX >= 0 && $0.frame.maxX <= width }, "Capsule and text remain inside a narrow sidebar row")
        }
        var longSpace = first
        longSpace.name = String(repeating: "A long Space name ", count: 12)
        var longDuplicate = second; longDuplicate.name = longSpace.name
        let longTarget = CommandBarSpaceAction.snapshot(spaces: [longSpace, longDuplicate], profiles: profiles)[0]
        let longRow = CommandResultCell(title: longTarget.title, detail: longTarget.detail, accessory: "", isTab: false,
            icon: nil, enabled: true, spaceAction: longTarget)
        longRow.frame = NSRect(x: 0, y: 0, width: 220, height: 50); longRow.needsLayout = true; longRow.layoutSubtreeIfNeeded()
        let profileField = longRow.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Space 1" }
        expect((profileField?.frame.width ?? 0) > 0, "A long Space capsule cannot erase duplicate-name disambiguation")
        let disabled = CommandResultCell(title: original[0].title, detail: "", accessory: "", isTab: false,
            icon: nil, enabled: false, spaceAction: original[0])
        disabled.onPress = { presses += 1; return true }
        expect(!disabled.accessibilityPerformPress() && presses == 1, "Unavailable action cannot execute through AX")
        let ordinary = CommandResultCell(title: "New Note", detail: "", accessory: "⌘N", isTab: false, icon: nil, enabled: true)
        ordinary.frame = NSRect(x: 0, y: 0, width: 745, height: 50); ordinary.layoutSubtreeIfNeeded()
        expect(ordinary.accessibilityLabel() == "New Note, ⌘N", "Ordinary menu/Notes rows keep their existing shortcut presentation")
        print("\(assertions) command-bar Space identity/native row assertions passed")
    }
}
