import AppKit
enum PCNativeShortcutPriority { case preferWebsites, useBoth, preferParc }
@MainActor final class PCNativeShortcutCommand {
    let item: NSMenuItem?
    let revision: UInt64
    let priority: PCNativeShortcutPriority
    init(item: NSMenuItem, revision: UInt64, priority: PCNativeShortcutPriority) {
        self.item = item; self.revision = revision; self.priority = priority
    }
    static func bindingsDidChange() {}
}
