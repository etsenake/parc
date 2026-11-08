// No native host is linked or constructed by this inert component fixture.
import AppKit
@MainActor final class BrowserWindowController {}
// Stand-ins for the engine's media types (native_appkit_bridge.h).
enum PCNativeMediaAction { case play, pause, previousTrack, nextTrack, toggleMuted, toggleMicrophone, toggleCamera, enterPictureInPicture }
enum PCNativeAirPlayState { case unavailable, available, connecting, connected }
enum PCNativeCastState { case unavailable, available, connecting, connected }
@MainActor final class PCNativeMediaState {
    let identifier: String, title = "Song", sourceURL = "https://example.test/"
    let playing = true, canPlayPause = true, hasPreviousTrack = true, hasNextTrack = true, muted = false
    let volume = 1.0, canSetVolume = true, canToggleMicrophone = false, canToggleCamera = false
    let microphoneOn = false, cameraOn = false, canEnterPictureInPicture = true
    let airPlayState = PCNativeAirPlayState.unavailable, airPlayDeviceName: String? = nil
    let castState = PCNativeCastState.unavailable, castDeviceName: String? = nil
    init(identifier: String) { self.identifier = identifier }
}
@MainActor final class PCNativePage {
    var isClosed = false
    var mediaState: PCNativeMediaState?
    var onAction: ((PCNativeMediaAction) -> Void)?
    func performMediaAction(_ action: PCNativeMediaAction, state: PCNativeMediaState) -> Bool { onAction?(action); return true }
    func setMediaVolume(_ volume: Double, state: PCNativeMediaState) -> Bool { true }
    func dismissMediaState(_ state: PCNativeMediaState) -> Bool { true }
    func performMediaAction(_ action: PCNativeMediaAction, state: PCNativeMediaState, in window: NSWindow) -> Bool { onAction?(action); return true }
    func setMediaVolume(_ volume: Double, state: PCNativeMediaState, in window: NSWindow) -> Bool { true }
    func dismissMediaState(_ state: PCNativeMediaState, in window: NSWindow) -> Bool { true }
    func showAirPlayPicker(for state: PCNativeMediaState, relativeTo rect: NSRect, of view: NSView, in window: NSWindow,
                           dismissed: @escaping () -> Void) -> Bool { true }
    func showCastChooser(for state: PCNativeMediaState, relativeTo rect: NSRect, of view: NSView, in window: NSWindow,
                         dismissed: @escaping () -> Void) -> Bool { true }
}

struct PCNativeCaptureState { let camera = false, microphone = false, tab = false, window = false, display = false, mirrored = false, shared = false }
