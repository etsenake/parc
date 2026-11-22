import AppKit
import ParcCore

extension BrowserWindowController {
    var savedFrame: SavedWindowFrame? {
        guard let window else { return nil }
        if fullscreenPhase != nil || window.styleMask.contains(.fullScreen) { return windowedFrame }
        return SavedWindowFrame(window.frame)
    }

    static func restoredFrame(_ record: BrowserWindowRecord?, minimumSize: NSSize) -> NSRect? {
        record?.frame?.placed(minimumSize: minimumSize, screens: NSScreen.screens.map(\.visibleFrame))
    }

    func keepSharedFrame() {
        guard let window, fullscreenPhase == nil, !window.styleMask.contains(.fullScreen) else { return }
        window.saveFrame(usingName: Self.sharedFrameAutosaveName)
    }

    func windowDidMove(_ notification: Notification) {
        if window?.inLiveResize != true { reportFrameChange() }
    }
    func windowDidResize(_ notification: Notification) {
        if window?.inLiveResize != true { reportFrameChange() }
    }
    func windowDidEndLiveResize(_ notification: Notification) { reportFrameChange() }

    private func reportFrameChange() {
        guard !isPopupWindow, !store.isEphemeral, fullscreenPhase == nil else { return }
        onSessionRecordChange?()
    }
}
