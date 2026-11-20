import AppKit

@main @MainActor
struct NoteLocationPickerTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        _ = NSApplication.shared
        let folderIcon = NSWorkspace.shared.icon(for: .folder)
        let notes = URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes", isDirectory: true)
        let custom = URL(fileURLWithPath: "/Volumes/Archive/Thinking Out Loud", isDirectory: true)
        let picker = NoteLocationPicker()
        var iconRequests: [URL] = []
        picker.iconProvider = { iconRequests.append($0); return folderIcon }
        var chosen: [NoteLocationPicker.Choice] = []
        picker.onChoose = { chosen.append($0) }

        expect(picker.frame.width == DownloadLocationPicker.width, "the picker is as wide as the Download location picker")
        expect(!picker.pullsDown, "the picker is a pop-up, not a pull-down")
        expect(picker.accessibilityLabel() == "Notes Folder", "the picker has an accessible name")
        expect(picker.itemTitles == ["Unavailable"] && !picker.isEnabled, "without a Space the picker guesses nothing and stays put")

        picker.update(notes, enabled: true)
        expect(picker.itemTitles == ["Parc Notes", "Other…", "", "Show in Finder"], "the folder, Other…, a divider, then Show in Finder")
        expect(picker.item(at: 2)?.isSeparatorItem == true, "a divider sits above Show in Finder")
        expect(picker.itemArray.filter { !$0.isSeparatorItem }.map(\.tag) == [0, 1, 2], "rows carry tags 0, 1 and 2")
        expect(picker.selectedTag() == 0 && picker.titleOfSelectedItem == "Parc Notes", "the folder row is selected")
        expect(picker.item(at: 0)?.image?.size == NoteLocationPicker.iconSize, "the folder's Finder icon is drawn at 16×16")
        expect(iconRequests == [notes], "the icon comes from the folder itself")
        expect(picker.item(at: 1)?.image == nil && picker.item(at: 3)?.image == nil, "only the folder row has an icon")
        expect(picker.item(at: 0)?.toolTip == notes.path && picker.toolTip == notes.path, "the full path shows on hover")

        picker.selectItem(withTag: 0); _ = picker.sendAction(picker.action, to: picker.target)
        expect(chosen.isEmpty, "re-choosing the folder sends nothing")
        picker.selectItem(withTag: 2); _ = picker.sendAction(picker.action, to: picker.target)
        expect(chosen == [.showInFinder], "Show in Finder asks for Finder")
        expect(picker.selectedTag() == 0 && picker.toolTip == notes.path, "Show in Finder snaps the picker back to the folder")
        picker.selectItem(withTag: 1); _ = picker.sendAction(picker.action, to: picker.target)
        expect(chosen == [.showInFinder, .other], "Other… asks for the folder panel")

        picker.update(notes, enabled: true, panelOpen: true)
        expect(picker.numberOfItems == 0 && picker.panelOpen, "the picker is empty while its folder panel runs")
        picker.revert()
        expect(picker.numberOfItems == 0, "nothing is reselected while the panel runs")
        picker.update(custom, enabled: true)
        expect(picker.selectedTag() == 0 && picker.titleOfSelectedItem == "Thinking Out Loud", "a chosen folder shows its own name")
        expect(picker.item(at: 0)?.toolTip == custom.path, "the chosen folder's path is on hover")

        let title = NSTextField(labelWithString: "Notes folder")
        picker.rowTitle = title
        expect(title.alphaValue == 1, "an enabled row shows its title at full strength")
        picker.update(nil, enabled: true)
        expect(!picker.isEnabled && title.alphaValue == 0.25, "an unavailable row dims its title to 25%")
        chosen.removeAll()
        picker.selectItem(at: 0); _ = picker.sendAction(picker.action, to: picker.target)
        expect(chosen.isEmpty, "an unavailable picker sends nothing")

        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/Parc Notes", isDirectory: true)
        expect(NoteLocationPicker.folderIcon(missing).size.width > 0, "a folder that doesn't exist yet still gets a folder icon")
        expect(NoteLocationPicker.helpText.count < 70, "the help line stays short")
        print("NoteLocationPickerTests passed")
    }
}
