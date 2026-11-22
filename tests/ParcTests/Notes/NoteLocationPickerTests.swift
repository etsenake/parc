import AppKit
import Testing
@testable import ParcKit
@testable import ParcNotes

@MainActor
struct NoteLocationPickerTests {
    final class Recorder {
        var iconRequests: [URL] = []
        var chosen: [NoteLocationPicker.Choice] = []
    }

    static let notes = URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes", isDirectory: true)
    static let custom = URL(fileURLWithPath: "/Volumes/Archive/Thinking Out Loud", isDirectory: true)

    func makePicker(showing folder: URL? = nil) -> (NoteLocationPicker, Recorder) {
        _ = NSApplication.shared
        let recorder = Recorder()
        let icon = NSWorkspace.shared.icon(for: .folder)
        let picker = NoteLocationPicker()
        picker.iconProvider = { recorder.iconRequests.append($0); return icon }
        picker.onChoose = { recorder.chosen.append($0) }
        if let folder { picker.update(folder, enabled: true) }
        return (picker, recorder)
    }

    func choose(_ tag: Int, in picker: NoteLocationPicker) {
        picker.selectItem(withTag: tag)
        _ = picker.sendAction(picker.action, to: picker.target)
    }

    @Test func thePickerIsAsWideAsTheDownloadLocationPicker() {
        #expect(makePicker().0.frame.width == DownloadLocationPicker.width)
    }

    @Test func thePickerIsAPopUpNotAPullDown() {
        #expect(!makePicker().0.pullsDown)
    }

    @Test func thePickerHasAnAccessibleName() {
        #expect(makePicker().0.accessibilityLabel() == "Notes Folder")
    }

    @Test func withoutASpaceThePickerGuessesNothingAndStaysPut() {
        let picker = makePicker().0
        #expect(picker.itemTitles == ["Unavailable"])
        #expect(!picker.isEnabled)
    }

    @Test func theMenuListsTheFolderOtherADividerAndShowInFinder() {
        let picker = makePicker(showing: Self.notes).0
        #expect(picker.itemTitles == ["Parc Notes", "Other…", "", "Show in Finder"])
        #expect(picker.item(at: 2)?.isSeparatorItem == true)
    }

    @Test func rowsCarryTagsZeroOneAndTwo() {
        let picker = makePicker(showing: Self.notes).0
        #expect(picker.itemArray.filter { !$0.isSeparatorItem }.map(\.tag) == [0, 1, 2])
    }

    @Test func theFolderRowIsSelected() {
        let picker = makePicker(showing: Self.notes).0
        #expect(picker.selectedTag() == 0)
        #expect(picker.titleOfSelectedItem == "Parc Notes")
    }

    @Test func theFolderIconIsDrawnAtSixteenBySixteen() {
        let picker = makePicker(showing: Self.notes).0
        #expect(picker.item(at: 0)?.image?.size == NoteLocationPicker.iconSize)
    }

    @Test func theIconComesFromTheFolderItself() {
        let (_, recorder) = makePicker(showing: Self.notes)
        #expect(recorder.iconRequests == [Self.notes])
    }

    @Test func onlyTheFolderRowHasAnIcon() {
        let picker = makePicker(showing: Self.notes).0
        #expect(picker.item(at: 1)?.image == nil)
        #expect(picker.item(at: 3)?.image == nil)
    }

    @Test func theFullPathShowsOnHover() {
        let picker = makePicker(showing: Self.notes).0
        #expect(picker.item(at: 0)?.toolTip == Self.notes.path)
        #expect(picker.toolTip == Self.notes.path)
    }

    @Test func rechoosingTheFolderSendsNothing() {
        let (picker, recorder) = makePicker(showing: Self.notes)
        choose(0, in: picker)
        #expect(recorder.chosen.isEmpty)
    }

    @Test func showInFinderAsksForFinder() {
        let (picker, recorder) = makePicker(showing: Self.notes)
        choose(2, in: picker)
        #expect(recorder.chosen == [.showInFinder])
    }

    @Test func showInFinderSnapsThePickerBackToTheFolder() {
        let (picker, _) = makePicker(showing: Self.notes)
        choose(2, in: picker)
        #expect(picker.selectedTag() == 0)
        #expect(picker.toolTip == Self.notes.path)
    }

    @Test func otherAsksForTheFolderPanel() {
        let (picker, recorder) = makePicker(showing: Self.notes)
        choose(1, in: picker)
        #expect(recorder.chosen == [.other])
    }

    @Test func thePickerIsEmptyWhileItsFolderPanelRuns() {
        let picker = makePicker().0
        picker.update(Self.notes, enabled: true, panelOpen: true)
        #expect(picker.numberOfItems == 0)
        #expect(picker.panelOpen)
    }

    @Test func nothingIsReselectedWhileThePanelRuns() {
        let picker = makePicker().0
        picker.update(Self.notes, enabled: true, panelOpen: true)
        picker.revert()
        #expect(picker.numberOfItems == 0)
    }

    @Test func aChosenFolderShowsItsOwnNameAndPath() {
        let picker = makePicker(showing: Self.custom).0
        #expect(picker.selectedTag() == 0)
        #expect(picker.titleOfSelectedItem == "Thinking Out Loud")
        #expect(picker.item(at: 0)?.toolTip == Self.custom.path)
    }

    @Test func anEnabledRowShowsItsTitleAtFullStrength() {
        let picker = makePicker(showing: Self.notes).0
        let title = NSTextField(labelWithString: "Notes folder")
        picker.rowTitle = title
        #expect(title.alphaValue == 1)
    }

    @Test func anUnavailableRowDimsItsTitleToTwentyFivePercent() {
        let picker = makePicker(showing: Self.notes).0
        let title = NSTextField(labelWithString: "Notes folder")
        picker.rowTitle = title
        picker.update(nil, enabled: true)
        #expect(!picker.isEnabled)
        #expect(title.alphaValue == 0.25)
    }

    @Test func anUnavailablePickerSendsNothing() {
        let (picker, recorder) = makePicker()
        picker.update(nil, enabled: true)
        picker.selectItem(at: 0)
        _ = picker.sendAction(picker.action, to: picker.target)
        #expect(recorder.chosen.isEmpty)
    }

    @Test func aFolderThatDoesNotExistYetStillGetsAFolderIcon() {
        _ = NSApplication.shared
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/Parc Notes", isDirectory: true)
        #expect(NoteLocationPicker.folderIcon(missing).size.width > 0)
    }
}
