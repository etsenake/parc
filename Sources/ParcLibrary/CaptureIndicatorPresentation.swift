import AppKit
import ParcEngine

package struct CaptureIndicatorPresentation: Equatable {
    package let camera: Bool
    package let microphone: Bool
    package let tab: Bool
    package let window: Bool
    package let display: Bool
    package let mirrored: Bool
    package let shared: Bool

    package init(_ state: PCNativeCaptureState) {
        camera = state.camera; microphone = state.microphone
        tab = state.tab; window = state.window
        display = state.display; mirrored = state.mirrored; shared = state.shared
    }
    package var active: Bool { camera || microphone || tab || window || display || mirrored || shared }
    package var symbol: String {
        if display { return "display" }
        if window { return "macwindow" }
        if tab || mirrored || shared { return "rectangle.on.rectangle" }
        return camera ? "video.fill" : "mic.fill"
    }
    package var details: [String] {
        var result: [String] = []
        if display { result.append("Sharing a screen") }
        if window { result.append("Sharing a window or system audio") }
        if tab { result.append("Sharing a tab") }
        if mirrored { result.append("Tab capture is active") }
        if shared { result.append("This tab is being shared") }
        if camera { result.append("Camera is on") }
        if microphone { result.append("Microphone is on") }
        return result
    }
    package var summary: String { details.joined(separator: ", ") }
}
