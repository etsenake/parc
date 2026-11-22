import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitResizeCommandAvailabilityTests {
    @MainActor final class Host: NSWindow {
        var key = true
        override var isKeyWindow: Bool { key }
        override var isVisible: Bool { true }

        static func make() -> Host {
            _ = NSApplication.shared
            let window = Host(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            return window
        }
    }

    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let host = Host.make()
        let store: BrowserStore
        let owner: BrowserWindowController
        let ids: [UUID]
        let layout: BrowserSplitLayout

        init(equal: Bool = false) throws {
            let store = try BrowserStore(directory: directory)
            self.store = store
            store.scheduleDeferredSave = { _, _ in }
            ids = (0..<2).map { _ in store.openResolvedURL(URL(string: "about:blank")!) }
            store.setSplit(ids)
            try #require(store.setSplitLayout(orientation: .horizontal, widthFactors: equal ? [1, 1] : [2, 1]))
            layout = try #require(store.activeSplitLayout)
            owner = try BrowserWindowController(store: store, ownership: NativePageOwnership(), windowHost: host)
            owner.rendering = true
            owner.isSpaceCommandApplicationActive = { true }
            owner.canPresentSplitInteraction = { _ in true }
            owner.focusedTabID = ids[0]
            owner.pageHost.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
            host.contentView?.addSubview(owner.pageHost)
            owner.pageHost.addSubview(owner.splitView)
            owner.splitView.frame = owner.pageHost.bounds
            for id in ids {
                let pane = BrowserPane(frame: .zero)
                pane.showBlank()
                owner.panes[id] = pane
                owner.splitView.addArrangedSubview(pane)
            }
            owner.renderedPaneIDs = ids
            owner.splitView.configure(orientation: layout.orientation, factors: layout.widthFactors)
        }

        deinit {
            MainActor.assumeIsolated { host.close() }
            try? FileManager.default.removeItem(at: directory)
        }

        func pendingPane() throws -> SplitPaneInsertionSession {
            let request = try #require(SplitPaneInsertion(paneID: ids[0], operation: .addAfter, state: owner.presentedState))
            return SplitPaneInsertionSession(request: request, candidateIDs: [], validate: { true })
        }
    }

    enum Command: String, CaseIterable {
        case widen = "Widen Current Split"
        case narrow = "Narrow Current Split"
        case equalize = "Make All Split Panes Equal"
    }

    enum Blocker: CaseIterable {
        case inactiveWindow, pendingPane, undisplayedPane, nativeGate
    }

    @MainActor private final class ViewMenu {
        let delegate = AppDelegate()
        let root: NSMenu

        init(owner: BrowserWindowController) {
            let shortcuts = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
            root = delegate.buildMenus(shortcuts: shortcuts, install: false, initialSpaces: owner.store.state.spaces)
            delegate.splitCommandWindow = { [weak owner] in owner }
        }

        func item(_ command: Command) throws -> NSMenuItem {
            let menu = try #require(root.item(withTitle: "View")?.submenu)
            return try #require(menu.item(withTitle: command.rawValue))
        }
    }

    @Test(arguments: Command.allCases)
    func viewCommandSavesTheFocusedPanesResize(command: Command) throws {
        let fixture = try Fixture()
        let menu = ViewMenu(owner: fixture.owner)
        let item = try menu.item(command)
        try #require(menu.delegate.validateMenuItem(item))
        let action = try #require(item.action)
        _ = menu.delegate.perform(action, with: item)

        let saved = try #require(BrowserStore(directory: fixture.directory).activeSplitLayout)
        #expect(saved.id == fixture.layout.id)
        #expect(saved.tabIDs == fixture.ids)
        switch command {
        case .widen: #expect(saved.widthFactors[0] > fixture.layout.widthFactors[0])
        case .narrow: #expect(saved.widthFactors[0] < fixture.layout.widthFactors[0])
        case .equalize: #expect(saved.widthFactors == [0.5, 0.5])
        }
    }

    @Test(arguments: Command.allCases, Blocker.allCases)
    func viewCommandWaitsForAnAvailableDisplayedSplit(command: Command, blocker: Blocker) throws {
        let fixture = try Fixture()
        let menu = ViewMenu(owner: fixture.owner)
        let item = try menu.item(command)
        try #require(menu.delegate.validateMenuItem(item))

        switch blocker {
        case .inactiveWindow: fixture.host.key = false
        case .pendingPane: fixture.owner.splitInsertion = try fixture.pendingPane()
        case .undisplayedPane: fixture.owner.renderedPaneIDs.removeLast()
        case .nativeGate: fixture.owner.canPresentSplitInteraction = { _ in false }
        }
        let action = try #require(item.action)
        _ = menu.delegate.perform(action, with: item)
        #expect(!menu.delegate.validateMenuItem(item))
        #expect(fixture.store.activeSplitLayout == fixture.layout)
    }

    @Test func equalizeIsUnavailableWhenTheSplitIsAlreadyEven() throws {
        let fixture = try Fixture(equal: true)
        let menu = ViewMenu(owner: fixture.owner)
        let item = try menu.item(.equalize)

        #expect(!menu.delegate.validateMenuItem(item))
        #expect(fixture.store.activeSplitLayout == fixture.layout)
    }

    @Test func changingTheHostBoundsInvalidatesAPendingResizeWrite() throws {
        let fixture = try Fixture()
        let write = try #require(fixture.owner.prepareSplitResize())
        fixture.owner.pageHost.setFrameSize(NSSize(width: 800, height: 600))

        #expect(!write([0.25, 0.75]))
        #expect(fixture.store.activeSplitLayout == fixture.layout)
    }
}
