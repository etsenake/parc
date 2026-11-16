import AppKit

@main @MainActor
struct FolderActionTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        let profile = BrowserProfile(id: UUID(), name: "Personal")
        let foreign = BrowserProfile(id: UUID(), name: "Work")
        let first = BrowserSpace(id: UUID(), name: "Home", symbol: "house", color: "ABCDEF", profileID: profile.id)
        let second = BrowserSpace(id: UUID(), name: "Research", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "ABCDEF", profileID: foreign.id)
        let root = BrowserFolder(id: UUID(), spaceID: first.id, name: "Projects", isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: first.id, name: "Café", parentID: root.id, isExpanded: false)
        let duplicate = BrowserFolder(id: UUID(), spaceID: second.id, name: "Café", isExpanded: false)
        let hidden = BrowserFolder(id: UUID(), spaceID: other.id, name: "Other profile")
        let empty = BrowserFolder(id: UUID(), spaceID: first.id, name: "  ")
        var state = BrowserState(profiles: [profile, foreign], spaces: [first, second, other], activeSpaceID: first.id)
        state.folders = [root, nested, duplicate, hidden, empty]
        state.tabs = [BrowserTab(id: UUID(), spaceID: first.id, profileID: profile.id,
            url: "https://example.test", title: "Original", kind: .pinned, folderID: nested.id,
            createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 1),
            savedURL: "https://example.test", savedTitle: "Original")]
        let actions = CommandBarFolderAction.snapshot(state: state, profileID: profile.id)
        expect(actions.map(\.folderID) == [root.id, nested.id, duplicate.id], "Named ordinary folders follow Space/tree order, including collapsed descendants")
        let original = actions[1]
        expect(original.detail == "Home › Projects" && actions[2].detail == "Research", "Identical names expose their actual Space and ancestor path")
        expect(Set(actions.map(\.id)).count == 3, "Duplicate names have distinct original identities")
        expect(CommandBarFolderAction.matching(actions, query: "open cafe").map(\.folderID) == [nested.id, duplicate.id], "Recovered Open prefix retains literal accent-insensitive destination matching")
        expect(CommandBarFolderAction.matching(actions, query: "cafe home projects").map(\.folderID) == [nested.id], "Actual path disambiguates the destination")
        expect(CommandBarFolderAction.matching(actions, query: "folder").count == 3, "Folder discovery is searchable")
        expect(CommandBarFolderAction.matching(actions, query: "").isEmpty, "Empty input retains existing tab/history providers")
        expect(CommandBarFolderAction.matching(actions, query: "> projects").isEmpty, "No unproven Type Travel trigger")
        expect(CommandBarFolderAction.matching(actions, query: "https://cafe.test").isEmpty, "An address does not become a folder command")
        expect(!original.isCurrent(in: state, profileID: foreign.id), "A new source profile cannot reuse the original row")

        var renamed = state; renamed.folders[1].name = "Renamed"
        expect(original.isCurrent(in: renamed, profileID: profile.id), "Rename preserves original folder identity")
        let updated = CommandBarFolderAction.snapshot(state: renamed, profileID: profile.id)[1]
        expect(updated.id == original.id && updated.name == "Renamed", "Provider refresh carries new title without retargeting")
        var moved = state; moved.folders[1].parentID = nil
        expect(!original.isCurrent(in: moved, profileID: profile.id), "Changing the original parent path expires the chosen command")
        expect(CommandBarFolderAction.snapshot(state: moved, profileID: profile.id).first { $0.folderID == nested.id }?.id != original.id, "Reparented rows cannot inherit an explicit selection")
        moved = state; moved.folders[1].spaceID = second.id
        expect(!original.isCurrent(in: moved, profileID: profile.id), "Cross-Space move invalidates the old tree target")
        var removed = state; removed.folders.removeAll { $0.id == nested.id }
        expect(!original.isCurrent(in: removed, profileID: profile.id), "Removal cannot fall through to a same-name folder")
        removed = state; removed.profiles.removeAll { $0.id == profile.id }
        expect(CommandBarFolderAction.snapshot(state: removed, profileID: profile.id).isEmpty, "Retired profile exposes no destination")
        var cyclic = state; cyclic.folders[0].parentID = nested.id
        expect(CommandBarFolderAction.snapshot(state: cyclic, profileID: profile.id).map(\.folderID) == [duplicate.id], "Cycles never become actionable targets")

        let revealed = original.reveal.applying(to: state)!
        expect(revealed.folders[0].isExpanded && revealed.folders[1].isExpanded, "Shared reveal expands the original folder and ancestors")
        expect(!revealed.folders[2].isExpanded, "Unrelated folder disclosure remains intact")
        var emptyState = state; emptyState.tabs = []
        let emptyAction = CommandBarFolderAction.snapshot(state: emptyState, profileID: profile.id)[1]
        let emptyReveal = emptyAction.reveal.applying(to: emptyState)!
        expect(emptyReveal.folders[0].isExpanded && !emptyReveal.folders[1].isExpanded, "Empty original folder reveals its ancestors without fictitious disclosure")
        var restored = revealed; restored.folders = state.folders
        expect(restored == state, "Reveal does not select, navigate, duplicate, move or archive any original item")
        expect(original.reveal.applying(to: moved) == nil, "Shared transaction rejects changed destination ownership")

        _ = NSApplication.shared
        let row = CommandResultCell(title: original.title, detail: original.detail, accessory: "", isTab: false,
            icon: NSImage(systemSymbolName: "folder", accessibilityDescription: nil), enabled: true, folderAction: original)
        row.frame = NSRect(x: 0, y: 0, width: 745, height: 50); row.layoutSubtreeIfNeeded()
        expect(row.accessibilityLabel() == "Open, Café, Home › Projects", "Native AX exposes literal action and full path")
        var activations = 0
        row.onPress = { activations += 1; return true }
        expect(row.accessibilityPerformPress() && activations == 1, "Native AX invokes the owned command callback")
        row.setSelected(true)
        expect(row.isAccessibilitySelected(), "Highlight retains a contextual action rather than edit-completing text")
        for width: CGFloat in [745, 320, 220] {
            row.frame.size.width = width; row.needsLayout = true; row.layoutSubtreeIfNeeded()
            expect(row.subviews.filter { !$0.isHidden }.allSatisfy { $0.frame.width >= 0 && $0.frame.minX >= 0 && $0.frame.maxX <= width }, "Folder row remains within narrow native geometry")
        }
        let disabled = CommandResultCell(title: original.title, detail: original.detail, accessory: "", isTab: false,
            icon: nil, enabled: false, folderAction: original)
        disabled.onPress = { activations += 1; return true }
        expect(!disabled.accessibilityPerformPress() && activations == 1, "Expired folder cannot activate through AX")
        print("\(assertions) command-bar folder identity/reveal/native row assertions passed")
    }
}
