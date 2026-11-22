import AppKit
import QuartzCore
import SwiftUI

enum DeveloperReloadState: String { case reload, forceReload }

@MainActor enum DeveloperReloadPreference {
    static let key = "parc.developerMode.reloadState"
    static var state: DeveloperReloadState {
        get { storedState(in: .standard) }
        set { store(newValue, in: .standard) }
    }
    static func storedState(in defaults: UserDefaults) -> DeveloperReloadState {
        defaults.string(forKey: key).flatMap(DeveloperReloadState.init(rawValue:)) ?? .reload
    }
    static func store(_ state: DeveloperReloadState, in defaults: UserDefaults) {
        defaults.set(state.rawValue, forKey: key)
    }
}

@MainActor enum ReloadOptionsMenu {
    enum Choice { case reload, forceReload, clearCookies }

    static func make(state: DeveloperReloadState, canReload: Bool, canForceReload: Bool, canClearCookies: Bool,
                     choose: @escaping (Choice) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let reload = item("Reload") { choose(.reload) }
        let force = item("Refresh (Ignore Cache)") { choose(.forceReload) }
        let cookies = item("Clear Cookies and Refresh") { choose(.clearCookies) }
        copyKeyEquivalent(of: "reload:", to: reload)
        copyKeyEquivalent(of: "forceReload:", to: force)
        reload.state = state == .reload ? .on : .off
        force.state = state == .forceReload ? .on : .off
        reload.isEnabled = canReload; force.isEnabled = canForceReload; cookies.isEnabled = canClearCookies
        for item in [reload, force, .separator(), cookies] { menu.addItem(item) }
        return menu
    }

    private final class Action: NSObject {
        let block: () -> Void
        init(_ block: @escaping () -> Void) { self.block = block }
        @objc func invoke() { block() }
    }
    private static func item(_ title: String, _ block: @escaping () -> Void) -> NSMenuItem {
        let action = Action(block)
        let item = NSMenuItem(title: title, action: #selector(Action.invoke), keyEquivalent: "")
        item.target = action; item.representedObject = action
        return item
    }

    private static func copyKeyEquivalent(of selector: String, to item: NSMenuItem) {
        guard let source = find(NSSelectorFromString(selector), in: NSApp.mainMenu) else { return }
        item.keyEquivalent = source.keyEquivalent
        item.keyEquivalentModifierMask = source.keyEquivalentModifierMask
    }
    private static func find(_ action: Selector, in menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.action == action { return item }
            if let found = find(action, in: item.submenu) { return found }
        }
        return nil
    }

    static func present(_ menu: NSMenu, from button: NSView) {
        if let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseUp].contains(event.type),
           event.window === button.window {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.isFlipped ? button.bounds.maxY : 0), in: button)
        }
    }
}
