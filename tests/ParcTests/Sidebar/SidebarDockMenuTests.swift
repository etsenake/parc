import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarDockMenuTests {
    static func space(_ name: String, icon: SidebarGroupIcon? = nil) -> BrowserSpace {
        var space = BrowserSpace(id: UUID(), name: name, symbol: "circle.fill", color: "B9B5D4", profileID: UUID())
        space.customIcon = icon
        if name.hasPrefix("Space "), Int(name.dropFirst(6)) == 1 { space.title = nil }
        return space
    }

    static func actions(_ element: Any?) -> [String] {
        let selector = NSSelectorFromString("accessibilityActionNames")
        guard let object = element as? NSObject, object.responds(to: selector) else { return [] }
        return object.perform(selector)?.takeUnretainedValue() as? [String] ?? []
    }

    static let base = ["Rename Space…", "Edit Theme Color…", "New Folder"]

    @MainActor final class Dock {
        let directory: URL
        let store: BrowserStore
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        let strip = SidebarDockStrip(frame: NSRect(x: 8, y: 0, width: 147, height: 50))
        var fixture: [BrowserSpace]?
        var creating = false
        var calls: [String] = []
        var buttons: [UUID: NSButton] = [:]
        var menus: [UUID: SidebarDockItemMenu] = [:]
        var spaces: [BrowserSpace] { fixture ?? store.state.spaces }
        var active: UUID? { fixture == nil ? store.state.activeSpaceID : fixture?.last?.id }

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-dock-menu-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            store = try BrowserStore(directory: directory)
            window.isReleasedWhenClosed = false
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
            window.contentView = host
            host.addSubview(strip)
            render()
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
            MainActor.assumeIsolated { window.contentView = nil }
        }

        func spaceMenu(_ id: UUID) -> SidebarSpaceMenu? {
            SidebarSpaceMenu.dock(spaces: spaces, spaceID: id, activeSpaceID: active, creatingSpace: creating,
                                  showOnSingleUnnamedSpace: store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false,
                                  rename: { [weak self] id in guard let self else { return }; calls.append("rename " + (spaces.first { $0.id == id }?.name ?? "?")) },
                                  editTheme: { [weak self] in guard let self else { return }; calls.append("theme") },
                                  newFolder: { [weak self] in guard let self else { return }; calls.append("folder") },
                                  toggleHeader: { [weak self] in guard let self else { return }; store.toggleSpaceHeaderOnSingleUnnamedSpaces() })
        }

        func render() {
            let buttonsInOrder = spaces.map { space -> NSButton in
                let button = buttons[space.id] ?? NSButton(frame: .zero)
                buttons[space.id] = button
                button.isBordered = false; button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
                button.imagePosition = .imageOnly
                SidebarAccessibility.configureSpace(button, name: space.name)
                let id = space.id
                let menu = menus[id] ?? SidebarDockItemMenu { [weak self] in self?.spaceMenu(id) }
                menus[id] = menu
                menu.install(on: button)
                return button
            }
            let shown = SidebarChromeLayout.dockShowsSpaces(count: spaces.count, anyCustomIcon: spaces.contains { $0.customIcon != nil }, creating: creating)
            strip.items = shown ? buttonsInOrder : []
            strip.selectedIndex = shown ? spaces.firstIndex { $0.id == active } : nil
            strip.layoutSubtreeIfNeeded()
        }

        func opened(_ id: UUID) -> NSMenu? {
            guard let menu = buttons[id]?.menu else { return nil }
            menu.delegate?.menuNeedsUpdate?(menu)
            return menu
        }

        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags, _ button: NSButton) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil),
                               modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)
        }

        var first: BrowserSpace { store.state.spaces[0] }

        func addWork() -> BrowserSpace {
            let id = store.createSpace(name: "Work")
            render()
            return store.state.spaces.first { $0.id == id }!
        }
    }

    @Test func aNewSessionHasOneUntitledSpaceAndTheSettingOff() throws {
        let dock = try Dock()
        #expect(dock.store.state.spaces.count == 1 && dock.first.name == "Space 1")
        #expect(dock.store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == nil)
    }

    @Test func oneUntitledIconlessSpaceIsOmittedFromTheDock() throws {
        let dock = try Dock()
        #expect(dock.strip.items.isEmpty && dock.strip.selectedIndex == nil)
    }

    @Test func theItemsButtonCarriesItsSpaceMenu() throws {
        let dock = try Dock()
        #expect(dock.buttons[dock.first.id]?.menu === dock.menus[dock.first.id]?.menu)
    }

    @Test func aRightClickAndAControlClickAskTheButtonForTheSpaceMenu() throws {
        let dock = try Dock()
        let button = try #require(dock.buttons[dock.first.id]), itemMenu = try #require(dock.menus[dock.first.id])
        for event in [dock.event(.rightMouseDown, [], button), dock.event(.leftMouseDown, .control, button)] {
            #expect(event.flatMap { button.menu(for: $0) } === itemMenu.menu)
        }
    }

    @Test func theCellStillOffersShowMenuAndTheOmittedSpaceIsNotInTheVoiceOverOrder() throws {
        let dock = try Dock()
        let button = try #require(dock.buttons[dock.first.id])
        #expect(Self.actions(button.cell).contains("AXShowMenu"))
        #expect(!(dock.strip.accessibilityChildren() ?? []).contains { ($0 as AnyObject) === button.cell })
    }

    @Test func oneUntitledIconlessSpaceOffersTheSpaceItemsThenShowSpaceHeaderAllEnabled() throws {
        let dock = try Dock()
        let menu = dock.opened(dock.first.id)
        #expect(menu?.items.map(\.title) == Self.base + ["Show Space Header"])
        #expect(menu?.items.allSatisfy(\.isEnabled) == true)
    }

    @Test func showSpaceHeaderTurnsTheSettingOnAndTheMenuOffersHideAsItNextOpens() throws {
        let dock = try Dock()
        dock.opened(dock.first.id)?.performActionForItem(at: 3)
        #expect(dock.store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true)
        let menu = dock.opened(dock.first.id)
        #expect(menu?.items.last?.title == "Hide Space Header" && menu?.items.count == 4)
    }

    @Test func hideSpaceHeaderTurnsItOffAndTheMenuOffersShowAgain() throws {
        let dock = try Dock()
        dock.opened(dock.first.id)?.performActionForItem(at: 3)
        dock.opened(dock.first.id)?.performActionForItem(at: 3)
        #expect(dock.store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == false)
        #expect(dock.opened(dock.first.id)?.items.last?.title == "Show Space Header")
    }

    @Test func theActiveSpacesItemRunsRenameThemeAndFolderAndSelectsNothing() throws {
        let dock = try Dock()
        for index in 0..<3 { dock.opened(dock.first.id)?.performActionForItem(at: index) }
        #expect(dock.calls == ["rename Space 1", "theme", "folder"])
        #expect(dock.store.state.activeSpaceID == dock.first.id && dock.strip.selectedIndex == nil)
    }

    @Test func aNewSpaceIsActive() throws {
        let dock = try Dock()
        let second = dock.addWork()
        #expect(dock.store.state.activeSpaceID == second.id && dock.strip.selectedIndex == 1)
    }

    @Test func eachItemKeepsItsOwnMenu() throws {
        let dock = try Dock()
        let first = dock.first, second = dock.addWork()
        let other = dock.opened(first.id), current = dock.opened(second.id)
        #expect(other !== current)
        #expect(dock.buttons[first.id]?.menu === other && dock.buttons[second.id]?.menu === current)
    }

    @Test func anotherSpacesItemEnablesOnlyRename() throws {
        let dock = try Dock()
        let first = dock.first
        _ = dock.addWork()
        let other = dock.opened(first.id)
        #expect(other?.items.map(\.title) == Self.base && other?.items.map(\.isEnabled) == [true, false, false])
    }

    @Test func theActiveSpacesItemEnablesEverythingWithNoToggleWithTwoSpaces() throws {
        let dock = try Dock()
        let second = dock.addWork()
        let current = dock.opened(second.id)
        #expect(current?.items.map(\.title) == Self.base && current?.items.allSatisfy(\.isEnabled) == true)
    }

    @Test func anotherSpacesItemRenamesThatSpaceAndRunsNothingElse() throws {
        let dock = try Dock()
        let first = dock.first
        _ = dock.addWork()
        let other = dock.opened(first.id)
        for index in 0..<3 { other?.performActionForItem(at: index) }
        #expect(dock.calls == ["rename Space 1"])
    }

    @Test func theActiveSpacesItemActsOnItAndNeitherMenuSwitchesSpace() throws {
        let dock = try Dock()
        let first = dock.first, second = dock.addWork()
        for index in 0..<3 { dock.opened(first.id)?.performActionForItem(at: index) }
        dock.calls.removeAll()
        for index in 0..<3 { dock.opened(second.id)?.performActionForItem(at: index) }
        #expect(dock.calls == ["rename Work", "theme", "folder"])
        #expect(dock.store.state.activeSpaceID == second.id && dock.strip.selectedIndex == 1)
    }

    @Test func theSettingAddsNoToggleWhileTheWindowHasTwoSpaces() throws {
        let dock = try Dock()
        let first = dock.first, second = dock.addWork()
        dock.store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        #expect(dock.opened(first.id)?.items.count == 3 && dock.opened(second.id)?.items.count == 3)
    }

    @Test(arguments: [("Space 1", false, true), ("Trips", false, false), ("Space 1", true, false), ("", false, true), ("Space 2", false, false)])
    func aLoneSpaceOffersTheToggleOnlyWhenUntitledAndIconless(_ name: String, _ starred: Bool, _ toggles: Bool) throws {
        let dock = try Dock()
        let fixture = Self.space(name, icon: starred ? .symbol("star") : nil)
        dock.fixture = [fixture]; dock.render()
        #expect(dock.opened(fixture.id)?.items.map(\.title) == Self.base + (toggles ? ["Show Space Header"] : []))
    }

    @Test(arguments: [false, true])
    func aLoneSpaceStaysInTheDockOnlyWithACustomIcon(_ starred: Bool) throws {
        let dock = try Dock()
        let fixture = Self.space(starred ? "Space 1" : "Trips", icon: starred ? .symbol("star") : nil)
        dock.fixture = [fixture]; dock.render()
        #expect(dock.strip.items.count == (starred ? 1 : 0))
    }

    @Test func thereIsNoMenuForASpaceTheWindowDoesNotHave() {
        let lone = Self.space("Space 1")
        #expect(SidebarSpaceMenu.dock(spaces: [lone], spaceID: UUID(), activeSpaceID: lone.id, creatingSpace: false,
                                      showOnSingleUnnamedSpace: false, rename: { _ in }, editTheme: nil, newFolder: nil, toggleHeader: nil) == nil)
    }

    private func creating() throws -> (Dock, NSButton, SidebarDockItemMenu) {
        let dock = try Dock()
        let button = try #require(dock.buttons[dock.first.id]), itemMenu = try #require(dock.menus[dock.first.id])
        dock.creating = true; dock.render()
        return (dock, button, itemMenu)
    }

    @Test func creatingASpaceRemovesEveryItemsMenu() throws {
        let (dock, button, _) = try creating()
        #expect(dock.spaces.allSatisfy { dock.buttons[$0.id]?.menu == nil })
        #expect(dock.event(.rightMouseDown, [], button).flatMap { button.menu(for: $0) } == nil)
    }

    @Test func creatingASpaceRemovesShowMenu() throws {
        let (_, button, _) = try creating()
        #expect(!Self.actions(button.cell).contains("AXShowMenu"))
    }

    @Test func aMenuOpeningDuringCreationHasNoItems() throws {
        let (_, _, itemMenu) = try creating()
        itemMenu.menuNeedsUpdate(itemMenu.menu)
        #expect(itemMenu.menu.items.isEmpty)
    }

    @Test func theMenusReturnWhenCreationEnds() throws {
        let (dock, button, itemMenu) = try creating()
        dock.creating = false; dock.render()
        #expect(button.menu === itemMenu.menu && Self.actions(button.cell).contains("AXShowMenu"))
        #expect(dock.opened(dock.first.id)?.items.map(\.title) == Self.base + ["Show Space Header"])
    }
}
