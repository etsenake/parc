import AppKit
import Testing
@testable import Parc

@MainActor
struct IconSettingsTests {
    @MainActor private final class PaneHolder {
        var owned: IconSettingsView?
        weak var observed: IconSettingsView?
        func build(icons: AppIconController) {
            let pane = IconSettingsView(icons: icons)
            owned = pane
            observed = pane
        }
    }

    @Test func everyApprovedVariantGetsOneControl() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        #expect(fixture.rows.map(\.iconID) == IconSettingsFixture.variantIDs)
    }

    @Test func thePreviewKeepsItsSixtyFourPointFrame() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        let preview = fixture.original.subviews.compactMap { $0 as? NSImageView }.first
        #expect(preview?.frame.size == NSSize(width: 64, height: 64))
    }

    @Test func onlyTheSavedChoiceIsSelected() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        #expect(fixture.original.state == .on)
        #expect(fixture.rows.dropFirst().allSatisfy { $0.state == .off })
    }

    @Test func onlyTheCurrentResponderDrawsTheFocusRing() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.original)
        #expect(fixture.original.showsIconFocusRing)
        #expect(!fixture.sorbet.showsIconFocusRing)
    }

    @Test func losingKeyRemovesTheRingAndInvalidatesDisplay() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.original)
        fixture.original.needsDisplay = false
        fixture.window.simulatedKey = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        #expect(!fixture.original.showsIconFocusRing)
        #expect(fixture.original.needsDisplay)
    }

    @Test func regainingKeyRedrawsTheUnchangedResponderRing() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.original)
        fixture.window.simulatedKey = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        fixture.original.needsDisplay = false
        fixture.window.simulatedKey = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: fixture.window)
        #expect(fixture.original.showsIconFocusRing)
        #expect(fixture.original.needsDisplay)
    }

    @Test func anInactiveApplicationNeverShowsAnActiveRing() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.original)
        fixture.original.needsDisplay = false
        fixture.applicationActive = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(!fixture.original.showsIconFocusRing)
        #expect(fixture.original.needsDisplay)
    }

    @Test func theApplicationReturningRedrawsTheEligibleRing() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.original)
        fixture.applicationActive = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        fixture.original.needsDisplay = false
        fixture.applicationActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        #expect(fixture.original.showsIconFocusRing)
        #expect(fixture.original.needsDisplay)
    }

    @Test func aRowIsANativeRadioButtonNamedByItsVariant() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        #expect(fixture.sorbet.accessibilityRole() == .radioButton)
        #expect(fixture.sorbet.accessibilityLabel() == "Sorbet")
    }

    @Test func artworkAndLabelsDoNotDuplicateAccessibilityControls() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        #expect(fixture.sorbet.accessibilityChildren()?.isEmpty == true)
    }

    @Test func theChoicesAreOneNamedRadioGroup() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        #expect(fixture.sorbet.superview?.accessibilityRole() == .radioGroup)
        #expect(fixture.sorbet.superview?.accessibilityLabel() == "App icon")
    }

    @Test(arguments: [NSPoint(x: 26, y: 39), NSPoint(x: 90, y: 39), NSPoint(x: 170, y: 39), NSPoint(x: 450, y: 39)])
    func theEntireRowSharesOneHitTarget(point: NSPoint) throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        let hit = fixture.sorbet.hitTest(fixture.sorbet.convert(point, to: fixture.sorbet.superview))
        #expect(hit === fixture.sorbet)
    }

    @Test func unclippedChildrenCannotEnlargeTheHitTarget() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        #expect(fixture.sorbet.hitTest(fixture.sorbet.convert(NSPoint(x: -2, y: 40), to: fixture.sorbet.superview)) == nil)
    }

    @Test func pressFeedbackPrecedesSelection() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.sorbet.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.sorbet))
        #expect(fixture.sorbet.isHighlighted)
        #expect(fixture.applications == 0)
        #expect(fixture.original.state == .on)
    }

    @Test func leavingTheRowDisarmsItsAppearance() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.sorbet.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.sorbet))
        fixture.sorbet.mouseDragged(with: fixture.mouse(.leftMouseDragged, on: fixture.sorbet, inside: false))
        #expect(!fixture.sorbet.isHighlighted)
    }

    @Test func releasingOutsideTheRowCancels() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.sorbet.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.sorbet))
        fixture.sorbet.mouseDragged(with: fixture.mouse(.leftMouseDragged, on: fixture.sorbet, inside: false))
        fixture.sorbet.mouseUp(with: fixture.mouse(.leftMouseUp, on: fixture.sorbet, inside: false))
        #expect(fixture.applications == 0)
        #expect(fixture.sorbet.state == .off)
    }

    @Test func returningToTheRowBeforeReleaseRearmsThePress() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.sorbet.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.sorbet))
        fixture.sorbet.mouseDragged(with: fixture.mouse(.leftMouseDragged, on: fixture.sorbet, inside: false))
        fixture.sorbet.mouseDragged(with: fixture.mouse(.leftMouseDragged, on: fixture.sorbet))
        #expect(fixture.sorbet.isHighlighted)
    }

    @Test func oneCompletedGestureChangesTheSavedChoiceAndEveryRadioState() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.click(fixture.sorbet)
        #expect(fixture.applications == 1)
        #expect(fixture.icons.selectedID == "Sorbet")
        #expect(fixture.sorbet.state == .on)
        #expect(fixture.original.state == .off)
    }

    @Test func theSelectionMarkerDoesNotShiftTheTitle() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        let title = try #require(fixture.original.subviews.compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "The Original Parc" })
        let frame = title.frame
        fixture.click(fixture.sorbet)
        fixture.view.layoutSubtreeIfNeeded()
        #expect(title.frame == frame)
    }

    @Test func aStrayReleaseDoesNotReplayTheAction() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.click(fixture.sorbet)
        fixture.sorbet.mouseUp(with: fixture.mouse(.leftMouseUp, on: fixture.sorbet))
        #expect(fixture.applications == 1)
    }

    @Test(arguments: [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification])
    func aWindowInterruptionCancelsAnOutstandingPress(notification: Notification.Name) throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.afterHours.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.afterHours))
        NotificationCenter.default.post(name: notification, object: fixture.window)
        fixture.afterHours.mouseUp(with: fixture.mouse(.leftMouseUp, on: fixture.afterHours))
        #expect(!fixture.afterHours.isHighlighted)
        #expect(fixture.applications == 0)
    }

    @Test func aStaleAccessibilityReferenceCannotActivateAClosedWindow() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: fixture.window)
        #expect(!fixture.afterHours.accessibilityPerformPress())
    }

    @Test func applicationDeactivationCancelsAPress() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.afterHours.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.afterHours))
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        fixture.afterHours.mouseUp(with: fixture.mouse(.leftMouseUp, on: fixture.afterHours))
        #expect(fixture.applications == 0)
    }

    @Test func aDisabledControlCannotActivateThroughTheMouse() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.afterHours.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.afterHours))
        fixture.afterHours.isEnabled = false
        fixture.afterHours.mouseUp(with: fixture.mouse(.leftMouseUp, on: fixture.afterHours))
        #expect(fixture.applications == 0)
    }

    @Test func aDisabledControlCannotActivateThroughAccessibility() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.afterHours.isEnabled = false
        #expect(!fixture.afterHours.accessibilityPerformPress())
    }

    @Test func heldSpaceGivesFeedbackWithoutRepeatingSaves() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.afterHours)
        fixture.afterHours.keyDown(with: fixture.key(.keyDown, 49))
        fixture.afterHours.keyDown(with: fixture.key(.keyDown, 49, repeated: true))
        #expect(fixture.afterHours.isHighlighted)
        #expect(fixture.applications == 0)
    }

    @Test func spaceReleaseSelectsExactlyOnce() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.afterHours)
        fixture.press(fixture.afterHours, code: 49)
        fixture.afterHours.keyUp(with: fixture.key(.keyUp, 49))
        #expect(fixture.applications == 1)
        #expect(fixture.afterHours.state == .on)
        #expect(!fixture.afterHours.isHighlighted)
    }

    @Test func escapeCancelsKeyboardActivation() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.sorbet)
        fixture.sorbet.keyDown(with: fixture.key(.keyDown, 36))
        fixture.sorbet.keyDown(with: fixture.key(.keyDown, 53))
        fixture.sorbet.keyUp(with: fixture.key(.keyUp, 36))
        #expect(fixture.applications == 0)
        #expect(!fixture.sorbet.isHighlighted)
    }

    @Test func movingFocusCancelsHeldInput() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.sorbet)
        fixture.sorbet.keyDown(with: fixture.key(.keyDown, 49))
        _ = fixture.window.makeFirstResponder(fixture.afterHours)
        fixture.sorbet.keyUp(with: fixture.key(.keyUp, 49))
        #expect(fixture.applications == 0)
    }

    @Test func arrowNavigationFocusesAndSelectsTheNeighborThroughTheController() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.afterHours)
        fixture.afterHours.keyDown(with: fixture.key(.keyDown, 126))
        #expect(fixture.window.firstResponder === fixture.sorbet)
        #expect(fixture.icons.selectedID == "Sorbet")
        #expect(fixture.applications == 1)
    }

    @Test func navigationStopsAtTheListEdgeWithoutWritingAgain() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.window.makeFirstResponder(fixture.sorbet)
        fixture.sorbet.keyDown(with: fixture.key(.keyDown, 126))
        fixture.original.keyDown(with: fixture.key(.keyDown, 126))
        #expect(fixture.icons.selectedID == "Original")
        #expect(fixture.applications == 1)
    }

    @Test func anAccessibilityPressUsesTheSamePersistedSelection() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        #expect(fixture.afterHours.accessibilityPerformPress())
        #expect(fixture.icons.selectedID == "AfterHours")
        #expect(fixture.applications == 1)
    }

    @Test func accessibilityValuesFollowTheAuthoritativeSelection() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        _ = fixture.afterHours.accessibilityPerformPress()
        #expect((fixture.afterHours.accessibilityValue() as? NSNumber)?.intValue == 1)
        #expect((fixture.original.accessibilityValue() as? NSNumber)?.intValue == 0)
    }

    @Test func hidingAndShowingThePaneNeverInheritsAPress() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.sorbet.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.sorbet))
        fixture.view.isHidden = true
        fixture.view.isHidden = false
        fixture.sorbet.mouseUp(with: fixture.mouse(.leftMouseUp, on: fixture.sorbet))
        #expect(fixture.applications == 0)
    }

    @Test func anExternalSelectionRetiresPendingInput() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.icons.select("AfterHours")
        fixture.refreshPendingSelection()
        fixture.sorbet.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.sorbet))
        fixture.icons.select("Original")
        fixture.refreshPendingSelection()
        let applied = fixture.applications
        fixture.sorbet.mouseUp(with: fixture.mouse(.leftMouseUp, on: fixture.sorbet))
        #expect(fixture.applications == applied)
        #expect(fixture.icons.selectedID == "Original")
    }

    @Test func aFailedSaveKeepsThePreviousModelAndVisualSelection() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        let blocker = fixture.directory.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocker)
        fixture.icons.configure(preferenceURL: blocker.appendingPathComponent("choice.json")) { _ in nil }
        fixture.sorbet.performClick(nil)
        #expect(fixture.icons.selectedID == "Original")
        #expect(fixture.original.state == .on)
        #expect(fixture.sorbet.state == .off)
    }

    @Test func aSaveFailureKeepsTruthfulFeedback() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        let blocker = fixture.directory.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocker)
        fixture.icons.configure(preferenceURL: blocker.appendingPathComponent("choice.json")) { _ in nil }
        fixture.sorbet.performClick(nil)
        #expect(fixture.icons.message != nil)
        #expect(!fixture.icons.canRetry)
    }

    @Test func aDetachedRowCancelsAndRefusesAccessibilityActivation() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        fixture.sorbet.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.sorbet))
        fixture.sorbet.removeFromSuperview()
        #expect(!fixture.sorbet.accessibilityPerformPress())
        #expect(!fixture.sorbet.isHighlighted)
    }

    @Test func reattachmentDoesNotReviveOldInput() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        let parent = try #require(fixture.sorbet.superview)
        fixture.sorbet.mouseDown(with: fixture.mouse(.leftMouseDown, on: fixture.sorbet))
        fixture.sorbet.removeFromSuperview()
        parent.addSubview(fixture.sorbet)
        fixture.sorbet.mouseUp(with: fixture.mouse(.leftMouseUp, on: fixture.sorbet))
        #expect(fixture.applications == 0)
    }

    @Test func thePaneIsNotRetainedBySubscriptionsOrRowCallbacks() throws {
        let fixture = try IconSettingsFixture()
        defer { fixture.close() }
        let holder = PaneHolder()
        autoreleasepool { holder.build(icons: fixture.icons) }
        autoreleasepool { holder.owned = nil }
        #expect(holder.observed == nil)
    }
}
