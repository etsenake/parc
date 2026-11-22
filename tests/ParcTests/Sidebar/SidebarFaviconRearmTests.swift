import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarFaviconRearmTests {
    @MainActor private final class Rearm {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window: SidebarTestWindow
        var state = BrowserState.initial()
        let today: BrowserTab
        let favorite: BrowserTab
        var tabRequests: [UUID] = []
        var savedRequests: [UUID] = []
        let art = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in NSColor.blue.setFill(); rect.fill(); return true }

        init() {
            window = sidebarTestWindow(containing: sidebar)
            let space = state.spaces[0]
            func make(_ name: String, _ kind: TabKind) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                           kind: kind, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
            }
            today = make("today", .today)
            favorite = make("favorite", .favorite)
            state.tabs = [today, favorite]
            let art = self.art
            sidebar.requestTabFavicon = { [weak self] tab, done in self?.tabRequests.append(tab.id); done(art) }
            sidebar.requestSavedFavicon = { [weak self] tab, done in self?.savedRequests.append(tab.id); done(art) }
            render()
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        func render(_ state: BrowserState? = nil) {
            sidebar.render(state: state ?? self.state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
            sidebar.layoutSubtreeIfNeeded()
        }

        func requests(for id: UUID) -> Int { tabRequests.filter { $0 == id }.count }
    }

    @Test func theFirstRenderRequestsATabsFavicon() {
        let r = Rearm()
        #expect(r.requests(for: r.today.id) == 1)
    }

    @Test func renderingTheSameStateAgainDoesNotRequestTheFaviconAgain() {
        let r = Rearm()
        let before = r.requests(for: r.today.id)
        r.render()
        r.render()
        #expect(r.requests(for: r.today.id) == before)
    }

    @Test func aChangedPageURLRequestsTheFaviconAgain() {
        let r = Rearm()
        let before = r.requests(for: r.today.id)
        var moved = r.state
        moved.tabs[0].url = "https://example.test/elsewhere"
        r.render(moved)
        #expect(r.requests(for: r.today.id) > before)
    }

    @Test func reloadingAFaviconForcesARequest() {
        let r = Rearm()
        let before = r.requests(for: r.today.id)
        r.sidebar.reloadFavicon(for: r.today.id)
        #expect(r.requests(for: r.today.id) > before)
    }

    @Test func renderingTheSameFavoriteAgainDoesNotRequestItsIconAgain() {
        let r = Rearm()
        let before = r.requests(for: r.favorite.id)
        r.render()
        r.render()
        #expect(r.requests(for: r.favorite.id) == before)
    }

    @Test func aChangedFavoriteURLRequestsItsIconAgain() {
        let r = Rearm()
        let before = r.requests(for: r.favorite.id)
        var moved = r.state
        moved.tabs[1].url = "https://example.test/elsewhere"
        moved.tabs[1].savedURL = "https://example.test/elsewhere"
        r.render(moved)
        #expect(r.requests(for: r.favorite.id) > before)
    }
}
