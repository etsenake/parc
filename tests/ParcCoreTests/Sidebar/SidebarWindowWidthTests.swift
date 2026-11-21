import Foundation
import Testing
@testable import ParcCore

struct SidebarWindowWidthTests {
    func drag(_ window: inout SidebarWindowWidth, by translation: Double, locked: Bool = true,
              _ completion: SidebarResizeGesture.Completion, lastUsed: inout Double) -> Double? {
        var gesture = SidebarResizeGesture(width: window.width, locked: locked)
        _ = gesture.change(translationX: translation, velocityX: 0, now: 0)
        let written = window.end(gesture.end(completion, translationX: translation), completion)
        if let written { lastUsed = written }
        return written
    }

    @Test func windowsKeepTheirOwnWidthsAcrossDragsResetsAndSettingsEdits() {
        var lastUsed = SidebarResizeGesture.defaultWidth
        var first = SidebarWindowWidth(lastUsed: lastUsed), second = SidebarWindowWidth(lastUsed: lastUsed)
        #expect(first.width == 228 && second.width == 228, "new windows take the last-used width")

        let r1 = drag(&first, by: 72, .ended, lastUsed: &lastUsed)
        #expect(r1 == 300, "a completed drag writes the last-used width")
        #expect(first.width == 300 && lastUsed == 300, "the dragging window and the last-used width follow the drag")
        #expect(second.width == 228, "another open window keeps its own width")
        #expect(SidebarWindowWidth(lastUsed: lastUsed).width == 300, "a later window takes the last-used width")
        #expect(SidebarResizeGesture(width: second.width, locked: true).widthOnBegin == 228, "a drag starts from its own window's width")

        let r2 = drag(&second, by: 100, .cancelled, lastUsed: &lastUsed)
        #expect(r2 == nil, "cancel writes nothing")
        #expect(second.width == 228 && lastUsed == 300, "cancel restores the start width")
        let r3 = drag(&second, by: -30, .failed, lastUsed: &lastUsed)
        #expect(r3 == nil, "failure writes nothing")
        #expect(second.width == 228 && lastUsed == 300, "failure restores the start width")

        let r4 = drag(&second, by: -150, .ended, lastUsed: &lastUsed)
        #expect(r4 == nil, "a collapse writes nothing")
        #expect(second.width == 228 && lastUsed == 300, "a collapse keeps this window's width and the last-used width")
        let r5 = drag(&second, by: -150, locked: false, .ended, lastUsed: &lastUsed)
        #expect(r5 == 164, "a floating release clamps and writes")
        #expect(second.width == 164 && lastUsed == 164, "the floating release sets both")

        lastUsed = first.reset()
        #expect(first.width == 228 && lastUsed == 228 && second.width == 164, "reset to 228 in one window")

        lastUsed = 400
        first.applySetting(lastUsed); second.applySetting(lastUsed)
        #expect(first.width == 400 && second.width == 400, "a Settings edit applies to open windows")
    }

    @Test func aSettingsEditApplies() {
        #expect(SidebarWindowWidth(lastUsed: 50).width == 164 && SidebarWindowWidth(lastUsed: 900).width == 500, "seeding clamps")
    }

    @Test func aReopenedWindowTakesItsSavedWidth() {
        var lastUsed = 228.0
        var first = SidebarWindowWidth(lastUsed: lastUsed)
        var reopened = SidebarWindowWidth(lastUsed: 228, restored: 312)
        #expect(reopened.width == 312, "a reopened window takes its saved width")
        #expect(SidebarWindowWidth(lastUsed: 260, restored: nil).width == 260, "a window without a record takes the last-used width")
        #expect(SidebarWindowWidth(lastUsed: 260, restored: 40).width == 164
              && SidebarWindowWidth(lastUsed: 260, restored: 720).width == 500, "a saved width clamps")
        lastUsed = 260
        let r6 = drag(&reopened, by: 40, .cancelled, lastUsed: &lastUsed)
        #expect(r6 == nil && reopened.width == 312 && lastUsed == 260,
              "cancel keeps the restored width")
        let r7 = drag(&reopened, by: -260, .ended, lastUsed: &lastUsed)
        #expect(r7 == nil && reopened.width == 312 && lastUsed == 260,
              "a collapse keeps the restored width")
        let r8 = drag(&reopened, by: -12, .ended, lastUsed: &lastUsed)
        #expect(r8 == 300 && reopened.width == 300 && lastUsed == 300,
              "a completed drag from a restored width writes both")
        let r9 = drag(&first, by: 600, .ended, lastUsed: &lastUsed)
        #expect(r9 == 500 && first.width == 500, "drag ends clamp")
        first.applySetting(10)
        #expect(first.width == 164, "settings clamp")
        #expect(SidebarWindowWidth.settingDidChange.rawValue == "ParcSidebarWidthSettingDidChange", "Settings notification name")

    }
}
