import Foundation
import Testing
@testable import ParcCore

@MainActor
enum WindowPresentationTestsSupport {
    struct World {
        var shared = BrowserState.initial()
        let firstSpace: BrowserSpace
        let otherProfile: BrowserProfile
        let otherSpace: BrowserSpace
        let siblingSpace: BrowserSpace
        let a: BrowserTab
        let b: BrowserTab
        let c: BrowserTab
        let pin: BrowserTab
        let firstRecord: BrowserWindowRecord
        let secondRecord: BrowserWindowRecord

        init() {
            firstSpace = shared.spaces[0]
            otherProfile = BrowserProfile(id: UUID(), name: "Other profile")
            otherSpace = BrowserSpace(id: UUID(), name: "Other Space", symbol: "circle", color: "112233", profileID: otherProfile.id)
            siblingSpace = BrowserSpace(id: UUID(), name: "Same profile", symbol: "circle", color: "112233", profileID: firstSpace.profileID)
            shared.profiles.append(otherProfile)
            shared.spaces += [otherSpace, siblingSpace]
            a = Self.tab(firstSpace)
            b = Self.tab(otherSpace)
            c = Self.tab(firstSpace)
            pin = Self.tab(firstSpace, kind: .pinned)
            shared.tabs = [a, b, c, pin]
            shared.selectedTabIDs = [a.id]
            shared.selectionBySpace[otherSpace.id.uuidString] = [b.id]
            firstRecord = BrowserWindowRecord(sidebarWidth: 230, id: UUID(), focusedSpaceID: firstSpace.id,
                                              selectedTabIDs: [a.id, c.id], focusedTabID: c.id)
            secondRecord = BrowserWindowRecord(sidebarWidth: 250, id: UUID(), focusedSpaceID: otherSpace.id,
                                               selectedTabIDs: [b.id], focusedTabID: b.id)
        }

        static func tab(_ space: BrowserSpace, kind: TabKind = .today) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID,
                       url: "https://example.test/result", title: "Result", kind: kind,
                       createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/", savedTitle: "Saved")
        }

        func tab(_ space: BrowserSpace, kind: TabKind = .today) -> BrowserTab { Self.tab(space, kind: kind) }

        func restoredFirst() -> WindowPresentation {
            var window = WindowPresentation(state: shared, ready: true, restoredRecord: firstRecord)
            window.reconcile(shared, available: { _ in true })
            return window
        }
    }

    @MainActor struct Engine {
        var w = World()
        var state: BrowserState
        let favorite: BrowserTab
        let ownership = NativePageOwnership()
        let windowA = UUID()
        var window: WindowPresentation

        init() {
            state = w.shared
            state.activeSpaceID = w.firstSpace.id
            state.selectedTabIDs = [w.a.id, w.c.id]
            favorite = w.tab(w.firstSpace, kind: .favorite)
            state.tabs.append(favorite)
            window = WindowPresentation(state: state, ready: true)
        }

        func availableA(_ id: UUID) -> Bool { ownership.canUse(id, owner: windowA) }
    }

    @MainActor final class StoreFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-window-test-" + UUID().uuidString)
        let store: BrowserStore
        let original: UUID

        init() throws {
            store = try BrowserStore(directory: directory)
            original = store.open("https://example.test/original")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func adopt() -> UUID {
            store.adoptNativePage(url: URL(string: "https://example.test/post-result"), title: "POST result",
                                  profilePath: store.independentEngineProfilePath(for: store.activeSpace.profileID),
                                  preferredSpaceID: store.activeSpaceID, select: false)!
        }
    }
}
