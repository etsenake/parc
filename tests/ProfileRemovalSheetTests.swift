import AppKit

/// Real, offscreen AppKit sheets with the production controller and isolated
/// native-boundary doubles. No browser or native profile directory is opened.
@main @MainActor
struct ProfileRemovalSheetTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !condition() { throw NSError(domain: message, code: assertions) }
    }
    static func edit(_ sheet: ProfileRemovalDialog, _ value: String) {
        sheet.confirmation.stringValue = value
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sheet.confirmation))
    }
    static func present(_ sheet: ProfileRemovalDialog, in parent: NSWindow) {
        parent.beginSheet(sheet.window!)
    }
    static func dismiss(_ sheet: ProfileRemovalDialog, from parent: NSWindow) {
        parent.endSheet(sheet.window!); sheet.window?.orderOut(nil)
    }
    static func capture(_ sheet: ProfileRemovalDialog, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["PARC_REMOVAL_CAPTURES"],
              let view = sheet.window?.contentView else { return }
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            sheet.window?.appearance = NSAppearance(named: appearance)
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: directory).appendingPathComponent(name + "-" + suffix + ".png"))
        }
    }
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-Removal-Sheets-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 680, height: 650),
            styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.orderOut(nil) }
        let collision = ProfileRemovalSheet(profile: BrowserProfile(id: UUID(), name: "Deleting"), tabCount: 0, historyCount: 0)
        let warning = collision.detail.attributedString()
        let firstFont = warning.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        let nameFont = warning.attribute(.font, at: "Deleting ".utf16.count, effectiveRange: nil) as! NSFont
        try expect(!NSFontManager.shared.traits(of: firstFont).contains(.boldFontMask) && NSFontManager.shared.traits(of: nameFont).contains(.boldFontMask), "Only the interpolated name is emphasized when it matches warning copy")
        let confirmName = UnusedProfileRemovalSheet(profiles: [BrowserProfile(id: UUID(), name: "CONFIRM 🧭")])
        let bulkWarning = confirmName.detail.attributedString()
        let promptFont = bulkWarning.attribute(.font, at: bulkWarning.length - 1, effectiveRange: nil) as! NSFont
        try expect(NSFontManager.shared.traits(of: promptFont).contains(.boldFontMask), "Bulk confirmation prompt remains emphasized with colliding and Unicode profile names")
        let profile = BrowserProfile(id: UUID(), name: "Work")
        let sheet = ProfileRemovalSheet(profile: profile, tabCount: 5, historyCount: 12)
        var confirms = 0, closes = 0
        sheet.onConfirm = { _ in confirms += 1 }
        sheet.onCancel = { closes += 1 }
        try expect(sheet.window?.contentView?.bounds.width == 450, "Recovered dialog width")
        try expect(sheet.window?.initialFirstResponder === sheet.confirmation, "Confirmation is initial focus")
        try expect(sheet.confirmation.nextKeyView === sheet.cancelButton && sheet.cancelButton.nextKeyView === sheet.removeButton,
                   "Confirmation, Cancel, Delete native key order")
        try expect(sheet.detail.isSelectable && !sheet.detail.isEditable, "Warning permits native text selection")
        try expect(sheet.detail.string.contains("5 saved tabs") && sheet.detail.string.contains("12 local history"), "Actual saved-record counts remain disclosed")
        edit(sheet, " Work ")
        try expect(!sheet.removeButton.isEnabled, "Whitespace cannot authorize deletion")
        edit(sheet, "wOrK")
        try expect(sheet.removeButton.isEnabled, "Recovered case-insensitive equality")
        sheet.removeButton.performClick(nil)
        try expect(confirms == 0, "Detached sheet cannot authorize deletion")
        present(sheet, in: parent)
        sheet.removeButton.performClick(nil)
        sheet.removeButton.performClick(nil)
        try expect(confirms == 1 && !sheet.confirmation.isEnabled && !sheet.removeButton.isEnabled, "Submission latches before callback and disables edits")
        sheet.setProgress("Removing this profile’s browser data…", canCancel: false)
        try expect(sheet.cancelButton.title == "Close" && sheet.cancelButton.isEnabled, "Committed removal can close presentation")
        sheet.cancelButton.performClick(nil)
        try expect(closes == 1, "Close delegates cancellation decision to owner")
        let failure = String(repeating: "The operation remains recoverable. ", count: 30)
        sheet.showFailure(failure, isRecovery: true, canCancel: false)
        try expect(sheet.feedback.string == failure && sheet.feedback.enclosingScrollView != nil, "Full errors stay readable in scrolling feedback")
        try expect(sheet.removeButton.isEnabled && sheet.removeButton.title == "Retry" && !sheet.confirmation.isEnabled,
                   "Recovery retries without asking for a new authorization")
        try expect(sheet.removeButton.accessibilityLabel() == "Retry", "Native accessibility follows actual action title")
        sheet.feedback.setSelectedRange(NSRange(location: 4, length: 20))
        sheet.showFailure(failure, isRecovery: true, canCancel: false)
        try expect(sheet.feedback.selectedRange() == NSRange(location: 4, length: 20), "Repeated status refresh preserves readable text selection")
        for text in [sheet.detail, sheet.feedback] {
            text.enclosingScrollView?.scrollerStyle = .legacy
            text.enclosingScrollView?.autohidesScrollers = false
        }
        sheet.showFailure(failure, isRecovery: true, canCancel: false)
        for text in [sheet.detail, sheet.feedback] {
            try expect(text.frame.width <= text.enclosingScrollView!.contentSize.width, "Legacy scrollers must not clip warning or feedback text")
        }
        sheet.feedback.enclosingScrollView?.contentView.scroll(to: NSPoint(x: 0, y: 30))
        sheet.showFailure(failure, isRecovery: true, canCancel: false)
        try expect(sheet.feedback.enclosingScrollView!.contentView.bounds.origin.y == 30, "Repeated feedback retains the scroll position")
        sheet.feedback.enclosingScrollView?.autohidesScrollers = true
        sheet.showFailure("Safe retry", isRecovery: true, canCancel: false)
        try expect(sheet.feedback.frame.width <= sheet.feedback.enclosingScrollView!.contentSize.width, "Fitting feedback measures the hidden legacy-scroller viewport")
        sheet.showFailure(failure, isRecovery: true, canCancel: false)
        try expect(sheet.feedback.frame.width <= sheet.feedback.enclosingScrollView!.contentSize.width, "Growing feedback measures the newly visible legacy-scroller viewport")
        try capture(sheet, name: "single-recovery")
        sheet.removeButton.performClick(nil)
        try expect(confirms == 2, "Recovery Retry reaches original callback once")
        sheet.showComplete()
        try expect(sheet.completed && sheet.removeButton.isHidden && sheet.cancelButton.title == "Done", "Actual completion presents Done without another deletion")
        try expect(sheet.cancelButton.keyEquivalent == "\r" && sheet.window?.defaultButtonCell === sheet.cancelButton.cell,
                   "Completion preserves Escape and default Done action")
        sheet.window?.cancelOperation(nil)
        try expect(closes == 2, "Escape command retains original close callback")
        dismiss(sheet, from: parent)

        let store = try BrowserStore(directory: directory)
        let first = store.createProfile(name: "First"), second = store.createProfile(name: "Second")
        let reviewed = store.unusedProfilesForRemoval
        let controller = ProfileRemovalController(); controller.configure(store: store)
        let bulk = UnusedProfileRemovalSheet(profiles: reviewed)
        bulk.onConfirm = { text in
            do { try controller.removeUnusedProfiles(reviewed, confirmation: text); bulk.refresh(store: store, controller: controller) }
            catch { bulk.showFailure(error) }
        }
        present(bulk, in: parent)
        try expect(bulk.detail.string.contains("First, Second") && bulk.detail.string.contains("CONFIRM"), "Original target names and confirmation are visible")
        edit(bulk, " CONFIRM")
        try expect(!bulk.removeButton.isEnabled, "Bulk confirmation does not trim")
        edit(bulk, "confirm"); bulk.removeButton.performClick(nil)
        try expect(PCNativeBrowserApplication.preparations.count == 2 && bulk.submitted, "Original set reaches real controller admission")
        let firstLease = PCNativeBrowserApplication.prepare(0)
        PCNativeBrowserApplication.preparations[1].completion(nil, ProfileRemovalError.unavailable)
        firstLease.completion?(.removed, nil)
        bulk.refresh(store: store, controller: controller)
        try expect(bulk.results.string.contains("First — Removed") && bulk.results.string.contains("Second — This profile is no longer available."), "Partial outcomes keep each original result")
        try expect(bulk.feedback.string.contains("1 of 2") && bulk.removeButton.isEnabled, "Partial removal permits retry without false success")
        let newProfile = store.createProfile(name: "Not in the review")
        bulk.results.enclosingScrollView?.scrollerStyle = .legacy
        bulk.results.enclosingScrollView?.autohidesScrollers = false
        bulk.refresh(store: store, controller: controller)
        try expect(bulk.results.frame.width <= bulk.results.enclosingScrollView!.contentSize.width, "Legacy scrollers must not clip per-profile results")
        try capture(bulk, name: "bulk-partial")
        bulk.removeButton.performClick(nil)
        try expect(PCNativeBrowserApplication.preparations.count == 3 && !store.isProfileRemovalPending(newProfile), "Retry never expands reviewed targets")
        let secondLease = PCNativeBrowserApplication.prepare(2)
        secondLease.completion?(.pending, ProfileRemovalError.incompleteOperation)
        bulk.refresh(store: store, controller: controller)
        bulk.removeButton.performClick(nil)
        try expect(PCNativeBrowserApplication.recoveries.count == 1, "Incomplete native result retries exact original journal")
        PCNativeBrowserApplication.recoveries[0].completion(.removed, nil)
        bulk.refresh(store: store, controller: controller)
        try expect(bulk.completed && bulk.feedback.string.contains("Removed all 2"), "Full actual completion remains visible")
        try expect(!store.state.profiles.contains { $0.id == first || $0.id == second } && store.state.profiles.contains { $0.id == newProfile }, "Only reviewed profiles removed from disposable model")
        try capture(bulk, name: "bulk-complete")
        dismiss(bulk, from: parent)
        bulk.onConfirm = nil
        print("Profile removal sheets: \(assertions) assertions passed (offscreen AppKit; isolated native-boundary doubles)")
    }
}
