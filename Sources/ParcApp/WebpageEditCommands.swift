import AppKit

///
/// Spelling, Substitutions, Transformations and Speech submenus). Every entry
/// is nil-targeted, so AppKit routes it to the actual first responder: native
/// text owns its own editing, and the engine's page view answers the commands
/// its RenderWidgetHostViewCocoa implements. No command reconstructs a page
/// operation or replaces native validation.
@MainActor
enum WebpageEditCommands {
    /// Paste and Match Style's shipped selector.
    static let pasteMatchingStyle = NSSelectorFromString("pasteAsPlainText:")
    ///
    ///
    /// method list entries 0xd7748a4 and 0xd7748e0 share IMP 0x416351c); the
    /// pinned engine implements only this one, so the application forwards it.
    static let pageMatchStyle = NSSelectorFromString("pasteAndMatchStyle:")

    private enum ChainOwner { case nativeText, page(NSResponder), none }
    /// Walks one window's responder chain as AppKit does. A responder that
    /// answers `pasteAsPlainText:` itself (native text, an Easel canvas) keeps
    /// the command, so only an engine page view without it is a target.
    private static func owner(in window: NSWindow?) -> ChainOwner {
        var responder = window?.firstResponder
        while let current = responder {
            if current.responds(to: pasteMatchingStyle) { return .nativeText }
            if current.responds(to: pageMatchStyle) { return .page(current) }
            responder = current.nextResponder
        }
        return .none
    }
    static func pageTarget(in window: NSWindow?) -> NSResponder? {
        if case .page(let page) = owner(in: window) { return page }
        return nil
    }
    /// AppKit's nil-target order: the key window's chain, then the main window's
    /// when the key window (a panel or popover) has no answering responder.
    private static var commandTarget: NSResponder? {
        switch owner(in: NSApp.keyWindow) {
        case .page(let page): return page
        case .nativeText: return nil
        case .none:
            guard let main = NSApp.mainWindow, main !== NSApp.keyWindow else { return nil }
            return pageTarget(in: main)
        }
    }

    static func canPasteMatchingStyle(_ item: NSMenuItem) -> Bool { canPasteMatchingStyle(item, target: commandTarget) }
    static func pasteMatchingStyle(from sender: Any?) { pasteMatchingStyle(from: sender, target: commandTarget) }
    static func canPasteMatchingStyle(_ item: NSMenuItem, in window: NSWindow?) -> Bool {
        canPasteMatchingStyle(item, target: pageTarget(in: window))
    }
    static func pasteMatchingStyle(from sender: Any?, in window: NSWindow?) {
        pasteMatchingStyle(from: sender, target: pageTarget(in: window))
    }

    private static func canPasteMatchingStyle(_ item: NSMenuItem, target: NSResponder?) -> Bool {
        guard let target else { return false }
        // The engine view validates its own selector (main-frame widget only).
        let probe = NSMenuItem(title: item.title, action: pageMatchStyle, keyEquivalent: "")
        return (target as AnyObject).validateUserInterfaceItem?(probe) ?? true
    }
    private static func pasteMatchingStyle(from sender: Any?, target: NSResponder?) {
        guard let target else { return }
        if let item = sender as? NSMenuItem, !canPasteMatchingStyle(item, target: target) { return }
        NSApp.sendAction(pageMatchStyle, to: target, from: sender)
    }

    /// Delete and the four standard text submenus, in the shipped order.
    static func addTextMenus(to edit: NSMenu, deleteBefore selectAll: NSMenuItem, after findRoot: NSMenuItem) {
        let delete = NSMenuItem(title: "Delete", action: NSSelectorFromString("delete:"), keyEquivalent: "")
        edit.insertItem(delete, at: edit.index(of: selectAll))
        var index = edit.index(of: findRoot) + 1
        func submenu(_ title: String, menuTitle: String, _ entries: [(String, String, String)?]) {
            let menu = NSMenu(title: menuTitle)
            for entry in entries {
                guard let (name, selector, key) = entry else { menu.addItem(.separator()); continue }
                let item = NSMenuItem(title: name, action: NSSelectorFromString(selector), keyEquivalent: key)
                item.keyEquivalentModifierMask = key.isEmpty ? [] : .command
                menu.addItem(item)
            }
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            root.submenu = menu
            edit.insertItem(root, at: index); index += 1
        }
        submenu("Spelling and Grammar", menuTitle: "Spelling", [
            ("Show Spelling and Grammar", "showGuessPanel:", ":"),
            ("Check Document Now", "checkSpelling:", ";"),
            nil,
            ("Check Spelling While Typing", "toggleContinuousSpellChecking:", ""),
            ("Check Grammar With Spelling", "toggleGrammarChecking:", ""),
            ("Correct Spelling Automatically", "toggleAutomaticSpellingCorrection:", "")])
        submenu("Substitutions", menuTitle: "Substitutions", [
            ("Show Substitutions", "orderFrontSubstitutionsPanel:", ""),
            nil,
            ("Smart Copy/Paste", "toggleSmartInsertDelete:", ""),
            ("Smart Quotes", "toggleAutomaticQuoteSubstitution:", ""),
            ("Smart Dashes", "toggleAutomaticDashSubstitution:", ""),
            ("Smart Links", "toggleAutomaticLinkDetection:", ""),
            ("Data Detectors", "toggleAutomaticDataDetection:", ""),
            ("Text Replacement", "toggleAutomaticTextReplacement:", "")])
        submenu("Transformations", menuTitle: "Transformations", [
            ("Make Upper Case", "uppercaseWord:", ""),
            ("Make Lower Case", "lowercaseWord:", ""),
            ("Capitalize", "capitalizeWord:", "")])
        submenu("Speech", menuTitle: "Speech", [
            ("Start Speaking", "startSpeaking:", ""),
            ("Stop Speaking", "stopSpeaking:", "")])
    }
}
