import AppKit

@MainActor private final class ProbeWindow: NSWindow {
    var shown = true
    var key = true
    var testSheet: NSWindow?
    var closeRequests = 0
    override var isVisible: Bool { shown }
    override var isKeyWindow: Bool { key }
    override var attachedSheet: NSWindow? { testSheet }
    override func performClose(_ sender: Any?) { closeRequests += 1 }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}
@main @MainActor struct SettingsCloseCommandTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let settings = ProbeWindow(), browser = ProbeWindow(), sheet = ProbeWindow()
        SettingsCloseCommand.perform(window: settings, appIsActive: true, sender: nil)
        precondition(settings.closeRequests == 1 && browser.closeRequests == 0)
        settings.key = false
        SettingsCloseCommand.perform(window: settings, appIsActive: true, sender: nil)
        settings.key = true; settings.testSheet = sheet
        SettingsCloseCommand.perform(window: settings, appIsActive: true, sender: nil)
        settings.testSheet = nil; settings.shown = false
        SettingsCloseCommand.perform(window: settings, appIsActive: true, sender: nil)
        settings.shown = true
        SettingsCloseCommand.perform(window: settings, appIsActive: false, sender: nil)
        SettingsCloseCommand.perform(window: nil, appIsActive: true, sender: nil)
        precondition(settings.closeRequests == 1 && browser.closeRequests == 0)
        print("Settings close: original owner and five refusal cases passed")
    }
}
