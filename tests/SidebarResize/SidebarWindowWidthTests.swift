import Foundation

/// Window-local sidebar width over the app-wide last-used value. The model
/// decides which ends write the last-used width; the controller applies it.
@main struct SidebarWindowWidthTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarWindowWidth: \(message)") }
    }
    /// The controller's drag end: apply whatever the model returns.
    static func drag(_ window: inout SidebarWindowWidth, by translation: Double, locked: Bool = true,
                     _ completion: SidebarResizeGesture.Completion, lastUsed: inout Double) -> Double? {
        var gesture = SidebarResizeGesture(width: window.width, locked: locked)
        _ = gesture.change(translationX: translation, velocityX: 0, now: 0)
        let written = window.end(gesture.end(completion, translationX: translation), completion)
        if let written { lastUsed = written }
        return written
    }
    static func main() {
        var lastUsed = SidebarResizeGesture.defaultWidth
        var first = SidebarWindowWidth(lastUsed: lastUsed), second = SidebarWindowWidth(lastUsed: lastUsed)
        check(first.width == 228 && second.width == 228, "new windows take the last-used width")

        // A completed drag in one window sets it and the last-used width only.
        check(drag(&first, by: 72, .ended, lastUsed: &lastUsed) == 300, "a completed drag writes the last-used width")
        check(first.width == 300 && lastUsed == 300, "the dragging window and the last-used width follow the drag")
        check(second.width == 228, "another open window keeps its own width")
        check(SidebarWindowWidth(lastUsed: lastUsed).width == 300, "a later window takes the last-used width")
        check(SidebarResizeGesture(width: second.width, locked: true).widthOnBegin == 228, "a drag starts from its own window's width")

        // Cancelled and failed drags restore the start width and write nothing.
        check(drag(&second, by: 100, .cancelled, lastUsed: &lastUsed) == nil, "cancel writes nothing")
        check(second.width == 228 && lastUsed == 300, "cancel restores the start width")
        check(drag(&second, by: -30, .failed, lastUsed: &lastUsed) == nil, "failure writes nothing")
        check(second.width == 228 && lastUsed == 300, "failure restores the start width")

        // A locked release at or below 82 collapses with the start width: no
        // width changed, so another window's last-used width survives.
        check(drag(&second, by: -150, .ended, lastUsed: &lastUsed) == nil, "a collapse writes nothing")
        check(second.width == 228 && lastUsed == 300, "a collapse keeps this window's width and the last-used width")
        // A floating sidebar never collapses; the release clamps to 164.
        check(drag(&second, by: -150, locked: false, .ended, lastUsed: &lastUsed) == 164, "a floating release clamps and writes")
        check(second.width == 164 && lastUsed == 164, "the floating release sets both")

        // The double-click reset is 228 in that window and as the last-used width.
        lastUsed = first.reset()
        check(first.width == 228 && lastUsed == 228 && second.width == 164, "reset to 228 in one window")

        // Parc's Settings slider applies to every open window.
        lastUsed = 400
        first.applySetting(lastUsed); second.applySetting(lastUsed)
        check(first.width == 400 && second.width == 400, "a Settings edit applies to open windows")

        check(SidebarWindowWidth(lastUsed: 50).width == 164 && SidebarWindowWidth(lastUsed: 900).width == 500, "seeding clamps")

        // A reopened window takes its own saved width, not the last-used one.
        var reopened = SidebarWindowWidth(lastUsed: 228, restored: 312)
        check(reopened.width == 312, "a reopened window takes its saved width")
        check(SidebarWindowWidth(lastUsed: 260, restored: nil).width == 260, "a window without a record takes the last-used width")
        check(SidebarWindowWidth(lastUsed: 260, restored: 40).width == 164
              && SidebarWindowWidth(lastUsed: 260, restored: 720).width == 500, "a saved width clamps")
        lastUsed = 260
        check(drag(&reopened, by: 40, .cancelled, lastUsed: &lastUsed) == nil && reopened.width == 312 && lastUsed == 260,
              "cancel keeps the restored width")
        check(drag(&reopened, by: -260, .ended, lastUsed: &lastUsed) == nil && reopened.width == 312 && lastUsed == 260,
              "a collapse keeps the restored width")
        check(drag(&reopened, by: -12, .ended, lastUsed: &lastUsed) == 300 && reopened.width == 300 && lastUsed == 300,
              "a completed drag from a restored width writes both")
        check(drag(&first, by: 600, .ended, lastUsed: &lastUsed) == 500 && first.width == 500, "drag ends clamp")
        first.applySetting(10)
        check(first.width == 164, "settings clamp")
        check(SidebarWindowWidth.settingDidChange.rawValue == "ParcSidebarWidthSettingDidChange", "Settings notification name")
        print("SidebarWindowWidth: \(count) assertions passed")
    }
}
