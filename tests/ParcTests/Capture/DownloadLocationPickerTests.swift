import AppKit
import Testing
@testable import ParcKit

struct DownloadLocationPickerTests {
    private let downloads = URL(fileURLWithPath: "/Users/parc-sample/Downloads", isDirectory: true)
    private let custom = URL(fileURLWithPath: "/Volumes/Archive/Incoming Files", isDirectory: true)

    @MainActor private func picker(prompt: Bool? = nil) -> DownloadLocationPicker {
        let picker = DownloadLocationPicker()
        picker.iconProvider = { _ in NSImage(size: NSSize(width: 32, height: 32)) }
        if let prompt { picker.update(.init(directory: downloads, prompt: prompt), enabled: true) }
        return picker
    }

    @MainActor private func choose(_ tag: Int, in picker: DownloadLocationPicker) -> [DownloadLocationPicker.Choice] {
        var choices: [DownloadLocationPicker.Choice] = []
        picker.onChoose = { choices.append($0) }
        picker.selectItem(withTag: tag)
        _ = picker.sendAction(picker.action, to: picker.target)
        picker.onChoose = nil
        return choices
    }

    @MainActor @Test func anUnavailableLocationCannotBeChanged() {
        let picker = picker()
        #expect(!picker.isEnabled && picker.itemTitles == ["Unavailable"])
    }

    @MainActor @Test func theLocationControlIsAnAccessibleNativePopup() {
        let picker = picker()
        #expect(picker.frame.width == 180 && !picker.pullsDown)
        #expect(picker.accessibilityLabel() == "Download Location")
    }

    @MainActor @Test func theMenuListsFolderOtherAndPromptInOrder() {
        let picker = picker(prompt: false)
        #expect(picker.itemTitles == ["Downloads", "Other…", "", "Ask every time"])
        #expect(picker.item(at: 2)?.isSeparatorItem == true)
    }

    @MainActor @Test(arguments: [(false, 0), (true, 2)])
    func theCurrentPreferenceSelectsAndChecksItsOwnRow(_ prompt: Bool, _ tag: Int) {
        let picker = picker(prompt: prompt)
        #expect(picker.selectedTag() == tag && picker.selectedItem?.state == .on)
    }

    @MainActor @Test func onlyTheFolderRowHasAFolderIcon() {
        let picker = picker(prompt: false)
        #expect(picker.item(at: 0)?.image?.size == NSSize(width: 16, height: 16))
        #expect(picker.item(at: 1)?.image == nil && picker.item(at: 3)?.image == nil)
    }

    @MainActor @Test func theFolderTooltipShowsTheFullEffectivePath() {
        let picker = picker(prompt: false)
        #expect(picker.item(at: 0)?.toolTip == downloads.path && picker.toolTip == downloads.path)
    }

    @MainActor @Test func promptingHasNoFolderTooltip() {
        #expect(picker(prompt: true).toolTip == nil)
    }

    @MainActor @Test(arguments: [(false, 0), (true, 2)])
    func rechoosingTheEffectiveRowDoesNotSendAnAction(_ prompt: Bool, _ tag: Int) {
        #expect(choose(tag, in: picker(prompt: prompt)).isEmpty)
    }

    @MainActor @Test(arguments: [(false, 2, DownloadLocationPicker.Choice.prompt), (true, 0, .folder), (false, 1, .other)])
    func choosingADifferentRowSendsItsAction(_ prompt: Bool, _ tag: Int, _ choice: DownloadLocationPicker.Choice) {
        #expect(choose(tag, in: picker(prompt: prompt)) == [choice])
    }

    @MainActor @Test func revertingAnUnacceptedChoiceRestoresTheEffectiveRow() {
        let picker = picker(prompt: false)
        _ = choose(1, in: picker)
        picker.revert()
        #expect(picker.selectedTag() == 0)
    }

    @MainActor @Test func aCustomLocationShowsItsNameAndFullPath() {
        let picker = picker()
        picker.update(.init(directory: custom, prompt: false), enabled: true)
        #expect(picker.titleOfSelectedItem == "Incoming Files")
        #expect(picker.item(at: 0)?.toolTip == custom.path)
    }

    @MainActor @Test func thePopupRemainsEmptyWhileTheFolderPanelOwnsTheChoice() {
        let picker = picker(prompt: true)
        picker.update(.init(directory: downloads, prompt: true), enabled: true, panelOpen: true)
        picker.revert()
        #expect(picker.numberOfItems == 0 && picker.panelOpen)
    }

    @MainActor @Test func closingTheFolderPanelRestoresThePromptRow() {
        let picker = picker(prompt: true)
        picker.update(.init(directory: downloads, prompt: true), enabled: true, panelOpen: true)
        picker.update(.init(directory: downloads, prompt: true), enabled: true)
        #expect(picker.selectedTag() == 2)
    }

    @MainActor @Test func aManagedFolderIsShownInADisabledPopup() {
        let picker = picker()
        picker.update(.init(directory: custom, prompt: false), enabled: false)
        #expect(picker.titleOfSelectedItem == "Incoming Files" && !picker.isEnabled)
    }

    @MainActor @Test(arguments: [(false, 0.25), (true, 1.0)])
    func theRowTitleIsMutedWhenThePickerIsDisabled(_ enabled: Bool, _ alpha: Double) {
        let picker = picker()
        let title = NSTextField(labelWithString: "Download location")
        picker.rowTitle = title
        picker.update(.init(directory: downloads, prompt: false), enabled: enabled)
        #expect(Double(title.alphaValue) == alpha)
    }
}
