import Foundation
import Testing
@testable import ParcCore

struct SidebarWindowWidthTests {
    private struct Drag {
        var window: SidebarWindowWidth
        var lastUsed: Double
        var written: Double?

        init(window: SidebarWindowWidth, lastUsed: Double) {
            self.window = window
            self.lastUsed = lastUsed
        }

        mutating func apply(by translation: Double, locked: Bool = true, _ completion: SidebarResizeGesture.Completion) {
            var gesture = SidebarResizeGesture(width: window.width, locked: locked)
            _ = gesture.change(translationX: translation, velocityX: 0, now: 0)
            written = window.end(gesture.end(completion, translationX: translation), completion)
            if let written { lastUsed = written }
        }
    }

    private func drag(from width: Double = 228, lastUsed: Double = 228, restored: Double? = nil) -> Drag {
        Drag(window: SidebarWindowWidth(lastUsed: width, restored: restored), lastUsed: lastUsed)
    }

    @Test func aNewWindowTakesTheLastUsedWidth() {
        #expect(SidebarWindowWidth(lastUsed: 228).width == 228)
    }

    @Test func aCompletedDragWritesTheLastUsedWidth() {
        var d = drag()
        d.apply(by: 72, .ended)
        #expect(d.written == 300)
        #expect(d.lastUsed == 300)
    }

    @Test func aCompletedDragMovesOnlyTheDraggingWindow() {
        var d = drag()
        let other = SidebarWindowWidth(lastUsed: 228)
        d.apply(by: 72, .ended)
        #expect(d.window.width == 300)
        #expect(other.width == 228)
    }

    @Test func aLaterWindowTakesTheWidthOfTheLastCompletedDrag() {
        var d = drag()
        d.apply(by: 72, .ended)
        #expect(SidebarWindowWidth(lastUsed: d.lastUsed).width == 300)
    }

    @Test func aDragStartsFromItsOwnWindowsWidth() {
        #expect(SidebarResizeGesture(width: SidebarWindowWidth(lastUsed: 228).width, locked: true).widthOnBegin == 228)
    }

    @Test(arguments: [(SidebarResizeGesture.Completion.cancelled, 100.0), (.failed, -30.0)])
    func aCancelledOrFailedDragWritesNothingAndRestoresTheStartWidth(completion: SidebarResizeGesture.Completion, translation: Double) {
        var d = drag(lastUsed: 300)
        d.apply(by: translation, completion)
        #expect(d.written == nil)
        #expect(d.window.width == 228)
        #expect(d.lastUsed == 300)
    }

    @Test func aCollapseWritesNothingAndKeepsBothWidths() {
        var d = drag(lastUsed: 300)
        d.apply(by: -150, .ended)
        #expect(d.written == nil)
        #expect(d.window.width == 228)
        #expect(d.lastUsed == 300)
    }

    @Test func aFloatingReleaseClampsAndWritesBothWidths() {
        var d = drag(lastUsed: 300)
        d.apply(by: -150, locked: false, .ended)
        #expect(d.written == 164)
        #expect(d.window.width == 164)
        #expect(d.lastUsed == 164)
    }

    @Test func resettingOneWindowReturnsItToTheDefaultAndLeavesOthers() {
        var first = SidebarWindowWidth(lastUsed: 300)
        let second = SidebarWindowWidth(lastUsed: 164)
        #expect(first.reset() == 228)
        #expect(first.width == 228)
        #expect(second.width == 164)
    }

    @Test func aSettingsEditAppliesToAnOpenWindow() {
        var window = SidebarWindowWidth(lastUsed: 228)
        window.applySetting(400)
        #expect(window.width == 400)
    }

    @Test(arguments: [(50.0, 164.0), (900.0, 500.0)])
    func seedingClampsTheLastUsedWidth(lastUsed: Double, expected: Double) {
        #expect(SidebarWindowWidth(lastUsed: lastUsed).width == expected)
    }

    @Test func aSettingsEditClampsToTheMinimum() {
        var window = SidebarWindowWidth(lastUsed: 228)
        window.applySetting(10)
        #expect(window.width == 164)
    }

    @Test func aReopenedWindowTakesItsSavedWidth() {
        #expect(SidebarWindowWidth(lastUsed: 228, restored: 312).width == 312)
    }

    @Test func aWindowWithoutARecordTakesTheLastUsedWidth() {
        #expect(SidebarWindowWidth(lastUsed: 260, restored: nil).width == 260)
    }

    @Test(arguments: [(40.0, 164.0), (720.0, 500.0)])
    func aSavedWidthClamps(restored: Double, expected: Double) {
        #expect(SidebarWindowWidth(lastUsed: 260, restored: restored).width == expected)
    }

    @Test func cancellingADragFromARestoredWidthKeepsIt() {
        var d = drag(from: 260, lastUsed: 260, restored: 312)
        d.apply(by: 40, .cancelled)
        #expect(d.written == nil)
        #expect(d.window.width == 312)
        #expect(d.lastUsed == 260)
    }

    @Test func aCollapseFromARestoredWidthKeepsIt() {
        var d = drag(from: 260, lastUsed: 260, restored: 312)
        d.apply(by: -260, .ended)
        #expect(d.written == nil)
        #expect(d.window.width == 312)
        #expect(d.lastUsed == 260)
    }

    @Test func aCompletedDragFromARestoredWidthWritesBothWidths() {
        var d = drag(from: 260, lastUsed: 260, restored: 312)
        d.apply(by: -12, .ended)
        #expect(d.written == 300)
        #expect(d.window.width == 300)
        #expect(d.lastUsed == 300)
    }

    @Test func aDragPastTheMaximumEndsAtTheMaximum() {
        var d = drag()
        d.apply(by: 600, .ended)
        #expect(d.written == 500)
        #expect(d.window.width == 500)
    }

    @Test func theSettingsNotificationNameIsFixed() {
        #expect(SidebarWindowWidth.settingDidChange.rawValue == "ParcSidebarWidthSettingDidChange")
    }
}
