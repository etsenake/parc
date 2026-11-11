import AppKit

@MainActor
enum SettingsCloseCommand {
    static func isAvailable(window: NSWindow?, appIsActive: Bool) -> Bool {
        guard let window else { return false }
        return appIsActive && window.isVisible && window.isKeyWindow && window.attachedSheet == nil
    }

    static func perform(window: NSWindow?, appIsActive: Bool, sender: Any?) {
        guard isAvailable(window: window, appIsActive: appIsActive), let window else { return }
        window.performClose(sender)
    }
}
