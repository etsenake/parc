import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitAppearancePickerTests {
    @MainActor private final class KeyTestWindow: NSWindow {
        var key = false
        override var isKeyWindow: Bool { key }
        convenience init() {
            self.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
            isReleasedWhenClosed = false
        }
    }

    private final class Recorder {
        var commits: [SidebarGroupIcon?] = []
        var finished = 0
    }

    private func picker(selected: SidebarGroupIcon? = nil, recorder: Recorder, closesAfterChoice: Bool = false,
                        current: Bool = true) -> SidebarGroupIconPicker {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: selected)
        _ = picker.view
        picker.isCurrent = { current }
        picker.closesAfterChoice = closesAfterChoice
        picker.onCommit = { recorder.commits.append($0) }
        picker.onFinish = { recorder.finished += 1 }
        return picker
    }

    @Test func theTabAndSpacePickerIs272By272AndOpensOnEmojiWithoutAnIcon() throws {
        let view = try #require(picker(recorder: Recorder()).pickerView)
        #expect(view.frame.size == NSSize(width: 272, height: 272))
        #expect(view.page == .emoji)
    }

    @Test func theSegmentOrderIsEmojiThenIcon() throws {
        let view = try #require(picker(recorder: Recorder()).pickerView)
        #expect(view.segmentedControl?.label(forSegment: 0) == "Emoji")
        #expect(view.segmentedControl?.label(forSegment: 1) == "Icon")
    }

    @Test func removeOnlyAppearsWithAnIcon() throws {
        let view = try #require(picker(recorder: Recorder()).pickerView)
        #expect(view.removeButton.isHidden)
        #expect(!view.canRemoveIcon)
    }

    @Test func invalidNativeInputRetainsTheEdit() {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("not emoji"))
        #expect(recorder.commits.isEmpty)
        #expect(!picker.finished)
    }

    @Test func aChoiceCommitsOnceAndKeepsThePickerOpen() {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("🌍"))
        #expect(recorder.commits == [.emoji("🌍")])
        #expect(!picker.finished)
        #expect(picker.selected == .emoji("🌍"))
    }

    @Test func aCommittedEmojiIsMarkedAndRemoveAppears() throws {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("🌍"))
        let view = try #require(picker.pickerView)
        #expect(view.canRemoveIcon)
        #expect(!view.removeButton.isHidden)
        #expect(view.emojiPage?.selectedEmoji == "🌍")
    }

    @Test func theSameIconIsNotRepublished() {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("🌍"))
        picker.choose(.emoji("🌍"))
        #expect(recorder.commits.count == 1)
    }

    @Test func aGridIndexPublishesItsCatalogIcon() throws {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("🌍"))
        let view = try #require(picker.pickerView)
        view.iconGrid.selectIcon(at: 9)
        #expect(recorder.commits.last! == .icon(.shapes))
        #expect(view.iconGrid.selectedIcon == .shapes)
        #expect(view.emojiPage?.selectedEmoji == nil)
    }

    @Test func selectedOrOutOfRangeCellsPublishNothing() throws {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        let view = try #require(picker.pickerView)
        view.iconGrid.selectIcon(at: 9)
        view.iconGrid.selectIcon(at: 9)
        view.iconGrid.selectIcon(at: 56)
        #expect(recorder.commits.count == 1)
    }

    @Test func removePublishesNilAndKeepsThePicker() throws {
        let recorder = Recorder()
        let picker = picker(selected: .emoji("🌍"), recorder: recorder)
        let view = try #require(picker.pickerView)
        _ = view.removeButton.accessibilityPerformPress()
        #expect(recorder.commits.count == 1 && recorder.commits[0] == nil)
        #expect(!picker.finished)
        #expect(picker.selected == nil)
    }

    @Test func dismissalFinishesOnce() {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.cancel()
        picker.cancel()
        #expect(recorder.finished == 1)
        #expect(picker.finished)
    }

    @Test func dismissalIsNotIconRemoval() {
        let recorder = Recorder()
        let picker = picker(selected: .symbol("star"), recorder: recorder)
        picker.cancel()
        picker.choose(nil)
        #expect(recorder.commits.isEmpty)
    }

    @Test func anExpiredOwnerRefusesPublication() {
        let recorder = Recorder()
        let picker = picker(selected: .symbol("star"), recorder: recorder, current: false)
        picker.choose(nil)
        #expect(recorder.commits.isEmpty)
        #expect(picker.finished)
    }

    @Test func aSpaceCreationChoiceCommitsThenCloses() throws {
        let recorder = Recorder()
        let picker = picker(selected: .emoji("🌙"), recorder: recorder, closesAfterChoice: true)
        try #require(picker.pickerView).iconGrid.selectIcon(at: 0)
        #expect(recorder.commits == [.icon(.star)])
        #expect(picker.finished)
        #expect(recorder.finished == 1)
    }

    @Test func aSpaceCreationRemoveAlsoCloses() throws {
        let recorder = Recorder()
        let picker = picker(selected: .emoji("🌙"), recorder: recorder, closesAfterChoice: true)
        _ = try #require(picker.pickerView).removeButton.accessibilityPerformPress()
        #expect(recorder.commits.count == 1 && recorder.commits[0] == nil)
        #expect(picker.finished)
    }

    @Test func aFailedCommitKeepsThePickerAndTheOriginalSelection() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: .symbol("star"))
        let picker = SidebarGroupIconPicker(selected: f.target().group.customIcon)
        picker.isCurrent = { true }
        _ = picker.view
        var failures = 0
        picker.onFailure = { _ in failures += 1 }
        let target = f.target(), state = f.store.state
        try f.breakDisk()
        var committed: [SidebarGroupIcon?] = []
        picker.onCommit = { value in
            _ = try f.store.saveSplitAppearance(target, icon: value)
            committed.append(value)
        }
        picker.choose(nil)
        #expect(!picker.finished)
        #expect(f.store.state == state)
        #expect(committed.isEmpty)
        #expect(failures == 1)
        #expect(picker.selected == target.group.customIcon)
        #expect(picker.pickerView?.canRemoveIcon == true)
        picker.cancel()
    }

    @Test func aRepairedStoreLetsThePickerRetryTheCommit() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: .symbol("star"))
        let picker = SidebarGroupIconPicker(selected: f.target().group.customIcon)
        picker.isCurrent = { true }
        _ = picker.view
        picker.onFailure = { _ in }
        let target = f.target()
        let persisted = try Data(contentsOf: f.file)
        try f.breakDisk()
        var committed: [SidebarGroupIcon?] = []
        picker.onCommit = { value in
            _ = try f.store.saveSplitAppearance(target, icon: value)
            committed.append(value)
        }
        picker.choose(nil)
        try FileManager.default.removeItem(at: f.file)
        try persisted.write(to: f.file)
        picker.choose(nil)
        #expect(!picker.finished)
        #expect(committed.count == 1 && committed[0] == nil)
        #expect(f.target().group.customIcon == nil)
        picker.cancel()
    }

    @Test func noKeyWindowLeavesTheLeaseUnheld() {
        let browser = KeyTestWindow(), pickerWindow = KeyTestWindow()
        let owned = SidebarGroupIconPicker(selected: nil)
        pickerWindow.contentView = owned.view
        defer { pickerWindow.contentView = nil }
        #expect(owned.presentationWindow === pickerWindow)
        #expect(!SplitCustomizationFocus.isHeld(window: browser, presentation: owned.presentationWindow))
    }

    @Test func aKeyPickerPopoverHoldsTheLease() {
        let browser = KeyTestWindow(), pickerWindow = KeyTestWindow()
        let owned = SidebarGroupIconPicker(selected: nil)
        pickerWindow.contentView = owned.view
        defer { pickerWindow.contentView = nil }
        pickerWindow.key = true
        #expect(SplitCustomizationFocus.isHeld(window: browser, presentation: owned.presentationWindow))
    }

    @Test func aKeySkinToneChildWindowHoldsTheLease() {
        let browser = KeyTestWindow(), pickerWindow = KeyTestWindow(), toneWindow = KeyTestWindow()
        let owned = SidebarGroupIconPicker(selected: nil)
        pickerWindow.contentView = owned.view
        pickerWindow.addChildWindow(toneWindow, ordered: .above)
        defer { pickerWindow.removeChildWindow(toneWindow); pickerWindow.contentView = nil }
        toneWindow.key = true
        #expect(owned.presentationWindow === toneWindow)
        #expect(SplitCustomizationFocus.isHeld(window: browser, presentation: owned.presentationWindow))
    }

    @Test func theTonePopoverWindowCountsEvenUnparented() {
        let pickerWindow = KeyTestWindow(), looseTone = KeyTestWindow()
        looseTone.key = true
        #expect(SidebarGroupIconPicker.ownedKeyWindow(of: pickerWindow, extra: looseTone) === looseTone)
        #expect(SidebarGroupIconPicker.ownedKeyWindow(of: pickerWindow, extra: nil) == nil)
    }

    @Test func aClosedPickerReleasesItsControllerViewAndEmojiGrid() {
        _ = NSApplication.shared
        weak var leakedPicker: SidebarGroupIconPicker?
        weak var leakedView: NSView?
        weak var leakedGrid: NSCollectionView?
        autoreleasepool {
            let transient = SidebarGroupIconPicker(selected: nil)
            _ = transient.view
            transient.isCurrent = { true }
            transient.configurePopover()
            transient.pickerView?.emojiPage?.submit("pizza")
            leakedPicker = transient
            leakedView = transient.view
            leakedGrid = transient.pickerView?.emojiPage?.collectionView
            transient.cancel()
        }
        #expect(leakedPicker == nil && leakedView == nil && leakedGrid == nil)
    }
}
