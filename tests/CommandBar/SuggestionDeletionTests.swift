import AppKit

@main @MainActor struct SuggestionDeletionTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; precondition(value(), message)
    }
    static func main() {
        _ = NSApplication.shared
        let row = CommandResultCell(title: "History result", detail: "example.test", accessory: "", isTab: false, icon: nil, enabled: true)
        var deleted = 0, opened = 0, eligible = true
        row.onPress = { opened += 1; return true }
        row.onDelete = { guard eligible else { return false }; deleted += 1; eligible = false; return true }
        let button = row.subviews.compactMap { $0 as? NSButton }.first!
        expect(button.isHidden, "Delete is not displayed just because a row exists")
        row.setSelected(true)
        expect(button.isHidden, "Keyboard selection does not turn into pointer hover")
        row.setHovered(true)
        expect(!button.isHidden && button.isEnabled, "Hover reveals the real removal control")
        expect(button.accessibilityLabel() == "Delete Suggestion", "The control has its recovered accessible label")
        for width: CGFloat in [745, 320, 220] {
            row.frame = NSRect(x: 0, y: 0, width: width, height: 50); row.needsLayout = true; row.layoutSubtreeIfNeeded()
            expect(button.frame.maxX <= width && button.frame.width == 23, "Delete keeps its own usable trailing bounds")
            let text = row.subviews.compactMap { $0 as? NSTextField }.first { $0.attributedStringValue.string.contains("History result") }!
            expect(text.frame.maxX <= button.frame.minX, "A long label cannot cover removal")
        }
        let action = row.accessibilityCustomActions()!.first!
        expect(action.name == "Delete Suggestion", "Keyboard/AX removal is named separately from opening")
        expect(action.handler?() == true && deleted == 1 && opened == 0, "AX delete reaches the original deletion callback, never navigation")
        expect(action.handler?() == false && deleted == 1, "An expired owner can refuse a retained AX action")
        eligible = true; button.performClick(nil)
        expect(deleted == 2 && opened == 0, "Pointer control uses that same original callback")
        row.setHovered(false)
        expect(button.isHidden, "Leaving restores the ordinary row")
        row.onDelete = nil
        expect(row.accessibilityCustomActions()?.isEmpty == true, "Revoking a row removes its AX action")
        expect(action.handler?() == false && deleted == 2, "An already-retained custom action cannot bypass revocation")
        expect(row.accessibilityPerformPress() && opened == 1, "Ordinary opening remains its separate callback")
        let disabled = CommandResultCell(title: "Unavailable", detail: "", accessory: "", isTab: false, icon: nil, enabled: false)
        disabled.onDelete = { deleted += 1; return true }
        expect(disabled.accessibilityCustomActions()?.first?.handler?() == false && deleted == 2, "Disabled state also gates accessibility")
        let local = CommandResultCell(title: "New Note", detail: "", accessory: "⌘N", isTab: false, icon: nil, enabled: true)
        local.setHovered(true)
        expect(local.subviews.compactMap { $0 as? NSButton }.allSatisfy(\.isHidden), "A command without a native provider has no delete button")
        expect(local.accessibilityCustomActions()?.isEmpty != false, "Typed actions have no invented deletion")
        print("\(assertions) command-bar deletion control assertions passed")
    }
}
