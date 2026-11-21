import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct CommandMenuIconTests {
    @Test @MainActor func eachRegisteredMenuCommandHasDrawableArtwork() {
        _ = NSApplication.shared
        var mainMenu: NSMenu?
        let registry = KeyboardShortcuts(mainMenu: { mainMenu }, observesKeyboardLayout: false)
        let delegate = AppDelegate()
        mainMenu = delegate.buildMenus(shortcuts: registry, install: false, initialSpaces: BrowserState.initial().spaces)
        let commands = registry.commands
        #expect(commands.contains { $0.id == "openTaskManager:" })
        let namedArtwork: Set<String> = ["add-tab", "add-space", "split-add-right"]
        let missing = commands.filter { command in
            let name = CommandBarCommandPresentation.symbol(commandID: command.id, title: command.title, group: command.group)
            return DocumentDefaultIcon.fallback(named: name) == nil && !namedArtwork.contains(name)
        }
        #expect(missing.map(\.id).isEmpty)
    }
}
