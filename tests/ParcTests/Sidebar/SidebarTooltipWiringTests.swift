import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarTooltipWiringTests {
    @MainActor private final class Rendered {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window: SidebarTestWindow

        init() {
            window = sidebarTestWindow(containing: sidebar)
            var state = BrowserState.initial()
            let space = state.spaces[0]
            state.tabs = [BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://a.test", title: "a", kind: .today,
                                     createdAt: Date(), lastAccessed: Date(), savedURL: "https://a.test", savedTitle: "a")]
            sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: true, canForward: true)
            sidebar.layoutSubtreeIfNeeded()
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        func control(_ label: String) -> NSView? { sidebarDescendants(sidebar).first { $0.parcTooltip?.label == label } }
    }

    @Test(arguments: [("Go back", "goBack:"), ("Go forward", "goForward:"), ("Reload this page", "reload:"), ("Clear Today tabs", "clearToday:"),
                      ("Archive this tab", "closeTab:"), ("View Library", "viewLibrary:")])
    func aSidebarControlCarriesItsTooltipWithItsCommandsShortcut(label: String, command: String) {
        let rendered = Rendered()
        #expect(rendered.control(label)?.parcTooltip?.shortcut == .command(command))
    }

    @Test(arguments: ["Go back", "Go forward", "Reload this page", "Reload options", "Clear Today tabs", "Archive this tab", "View Library", "Site Control Center"])
    func aSidebarControlUsesParcsTooltipNotTheSystemOne(label: String) {
        let rendered = Rendered()
        let control = rendered.control(label)
        #expect(control != nil)
        #expect(control?.toolTip == nil)
    }

    @Test func eachSidebarTooltipLabelIsUniqueAmongTheHeaderControls() {
        let rendered = Rendered()
        let labels = sidebarDescendants(rendered.sidebar).compactMap { $0.parcTooltip?.label }.filter { ["Go back", "Go forward", "Reload this page", "View Library"].contains($0) }
        #expect(Set(labels).count == labels.count)
    }
}
