import AppKit

@MainActor
enum CommandBarTestSupport {
    static func prepareAppKit() {
        _ = NSApplication.shared
    }

    static func borderlessWindow(width: CGFloat = 400, height: CGFloat = 300) -> NSWindow {
        prepareAppKit()
        return NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [], backing: .buffered, defer: false)
    }

    static func keyEvent(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], characters: String = "\r",
                         type: NSEvent.EventType = .keyDown, window: NSWindow? = nil) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window?.windowNumber ?? 0, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }
}
