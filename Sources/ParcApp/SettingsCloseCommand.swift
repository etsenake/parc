import AppKit

/// Settings owns Close Tab while it is key; the native window delegate still
/// decides whether the actual window can close.
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
