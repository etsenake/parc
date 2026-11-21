import AppKit
import Testing
@testable import Parc

@MainActor
struct SettingsFocusTests {
    @MainActor
    private final class TestWindow: NSWindow {
        var simulatedVisible = true
        var key = true
        var simulatedSheet: TestWindow?
        var ended: [NSApplication.ModalResponse] = []
        override var isVisible: Bool { simulatedVisible }
        override var isKeyWindow: Bool { key }
        override var attachedSheet: NSWindow? { simulatedSheet }

        override func endSheet(_ sheetWindow: NSWindow, returnCode: NSApplication.ModalResponse) {
            if sheetWindow.attachedSheet != nil { Issue.record("a nested sheet must retire first") }
            ended.append(returnCode)
            simulatedSheet = nil
        }
    }

    @MainActor
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor
    private final class Target: NSObject {
        var count = 0
        @objc func invoke() { count += 1 }
    }

    @MainActor
    private final class Fixture {
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let first = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 25))
        let button = NSButton(title: "Apply", target: nil, action: nil)
        let lower = NSTextField(frame: NSRect(x: 20, y: 80, width: 200, height: 25))
        let label = NSTextField(labelWithString: "Explanation")
        let state = SettingsFocusState()

        init() {
            _ = NSApplication.shared
            window.isReleasedWhenClosed = false
            window.contentView = root
            first.stringValue = "Original draft"
            first.setAccessibilityLabel("Profile name")
            button.frame = NSRect(x: 230, y: 20, width: 80, height: 25)
            [lower, button, label, first].forEach(root.addSubview)
            SettingsFocusState.connectKeyViews(in: root)
            let activity = activity
            state.applicationIsActive = { activity.active }
        }

        deinit {
            MainActor.assumeIsolated { window.close() }
        }

        final class Activity { var active = true }
        private let activity = Activity()

        var isApplicationActive: Bool {
            get { activity.active }
            set { activity.active = newValue }
        }

        func rememberSelectedDraft(context: String) {
            window.makeFirstResponder(first)
            let editor = first.currentEditor() as! NSTextView
            editor.setSelectedRange(NSRange(location: 4, length: 5))
            state.remember(in: window, root: root, context: context)
        }
    }

    @Test func passiveLabelsAreNotDuplicateKeyboardControls() {
        #expect(SettingsFocusState.controls(in: Fixture().root).count == 3)
    }

    @Test func tabTraversalFormsOneNativeVisualOrderLoop() {
        let fixture = Fixture()
        #expect(fixture.first.nextKeyView === fixture.button)
        #expect(fixture.button.nextKeyView === fixture.lower)
        #expect(fixture.lower.nextKeyView === fixture.first)
    }

    @Test func nativeReverseLinksPreserveShiftTabOrder() {
        let fixture = Fixture()
        #expect(fixture.lower.previousKeyView === fixture.button)
        #expect(fixture.button.previousKeyView === fixture.first)
    }

    @Test func theConfiguredFieldLabelIsRetained() {
        #expect(Fixture().first.accessibilityLabel() == "Profile name")
    }

    @Test func aDisabledNativeActionCannotDispatchAndReportsUnavailable() {
        let fixture = Fixture()
        let target = Target()
        fixture.button.target = target
        fixture.button.action = #selector(Target.invoke)
        fixture.button.isEnabled = false
        fixture.button.sendClick()
        #expect(target.count == 0)
        #expect(!fixture.button.isAccessibilityEnabled())
    }

    @Test func anEnabledNativeActionDispatchesOnce() {
        let fixture = Fixture()
        let target = Target()
        fixture.button.target = target
        fixture.button.action = #selector(Target.invoke)
        _ = fixture.button.sendAction(fixture.button.action, to: fixture.button.target)
        #expect(target.count == 1)
    }

    @Test func theOriginalContextResponderIsRestored() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.window.makeFirstResponder(fixture.lower)
        #expect(fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A"))
    }

    @Test func theSharedFieldEditorResolvesToItsOriginalControlAndSelection() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.window.makeFirstResponder(fixture.lower)
        fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A")
        #expect(fixture.first.currentEditor() === fixture.window.firstResponder)
        #expect((fixture.first.currentEditor() as? NSTextView)?.selectedRange() == NSRange(location: 4, length: 5))
    }

    @Test func aDifferentProfileNeverAdoptsAnotherProfilesRememberedControl() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.window.makeFirstResponder(fixture.lower)
        fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:B", fallback: fixture.lower)
        #expect(fixture.lower.currentEditor() === fixture.window.firstResponder)
    }

    @Test func aDeletedOriginalProfileReturnsToTheNativeListEvenWithAValidSurvivorBookmark() {
        let fixture = Fixture()
        fixture.window.makeFirstResponder(fixture.first)
        fixture.state.remember(in: fixture.window, root: fixture.root, context: "profiles:B")
        let survivingList = NSTableView(frame: NSRect(x: 20, y: 120, width: 200, height: 80))
        survivingList.addTableColumn(NSTableColumn(identifier: .init("profiles")))
        fixture.root.addSubview(survivingList)
        fixture.state.restore(in: fixture.window, root: fixture.root, context: nil, fallback: survivingList)
        #expect(fixture.window.firstResponder === survivingList)
    }

    @Test func nonKeySettingsNeverStealsFocus() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.window.key = false
        #expect(!fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A"))
    }

    @Test func anInactiveApplicationNeverChangesFocus() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.isApplicationActive = false
        #expect(!fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A"))
    }

    @Test func closedSettingsCannotRestoreAQueuedBookmark() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.window.simulatedVisible = false
        #expect(!fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A"))
    }

    @Test func aDisabledOriginalControlUsesTheAvailableFallback() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.first.isEnabled = false
        #expect(fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A", fallback: fixture.lower))
        #expect(fixture.lower.currentEditor() === fixture.window.firstResponder)
    }

    @Test func aHiddenControlIsNotRevived() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.first.isHidden = true
        fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A", fallback: fixture.lower)
        #expect(fixture.lower.currentEditor() === fixture.window.firstResponder)
    }

    @Test func aDetachedOriginalControlIsNotRevived() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.first.removeFromSuperview()
        fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A", fallback: fixture.lower)
        #expect(fixture.lower.currentEditor() === fixture.window.firstResponder)
    }

    @Test func aReplacementSheetBlocksQueuedRestoration() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.window.simulatedSheet = TestWindow()
        #expect(!fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A"))
    }

    @Test func closingTheParentCancelsTheInnermostSheetBeforeTheParentNeverApprovingIt() {
        let fixture = Fixture()
        let sheet = TestWindow(), nested = TestWindow()
        fixture.window.simulatedSheet = sheet
        sheet.simulatedSheet = nested
        SettingsFocusState.cancelAttachedSheets(of: fixture.window)
        #expect(fixture.window.simulatedSheet == nil)
        #expect(sheet.simulatedSheet == nil)
        #expect(fixture.window.ended == [.cancel])
        #expect(sheet.ended == [.cancel])
    }

    @Test func reopenedSettingsCannotReuseARetiredBookmark() {
        let fixture = Fixture()
        fixture.rememberSelectedDraft(context: "profiles:A")
        fixture.state.forget()
        fixture.state.restore(in: fixture.window, root: fixture.root, context: "profiles:A", fallback: fixture.lower)
        #expect(fixture.lower.currentEditor() === fixture.window.firstResponder)
    }

    @Test func thePreferencePaneNavigationCannotBeHiddenByTheToolbarCommand() {
        _ = NSApplication.shared
        let native = SettingsNativeWindow()
        #expect(!native.responds(to: #selector(NSWindow.toggleToolbarShown(_:))))
    }
}
