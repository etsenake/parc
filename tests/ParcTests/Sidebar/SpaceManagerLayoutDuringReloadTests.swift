import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SpaceManagerLayoutDuringReloadTests {
    @Test func aLayoutWhileCardsAreStillBeingBuiltLinksOnlyTheCardsThatExist() {
        var state = BrowserState.initial()
        let first = state.spaces[0]
        for name in ["Second", "Third"] {
            state.spaces.append(BrowserSpace(id: UUID(), name: name, symbol: "star.fill", color: "AABBCC", profileID: first.profileID))
        }
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        manager.ownerValid = { true }
        let window = sidebarTestWindow(containing: manager)
        var configured: [UUID] = []
        manager.configureSidebar = { [unowned manager] id, _ in
            configured.append(id)
            manager.needsLayout = true
            manager.layoutSubtreeIfNeeded()
        }
        manager.reload(state)
        #expect(configured == state.spaces.map(\.id))
        #expect(manager.sidebar(for: state.spaces[2].id) != nil)
        withExtendedLifetime(window) {}
    }
}
