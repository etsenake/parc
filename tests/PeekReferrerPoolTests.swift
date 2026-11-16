import Foundation

@main
struct PeekReferrerPoolTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let source = store.open("https://source.example", kind: .pinned)
        let other = store.open("https://unrelated.example")
        let profile = store.activeSpace.profileID, space = store.activeSpaceID
        let path = store.independentEngineProfilePath(for: profile)
        let receipt = TabCreationProvenance(referrerID: source, activeTabID: other,
                                           profileID: profile, state: store.state)
        var window = WindowPresentation(state: store.state, ready: true)
        let ordinary = store.open("https://ordinary.example", creation: receipt)
        window.recordCreation(ordinary, state: store.state)
        expect(window.referrerPool == [source, ordinary], "Ordinary creation seeds the original chain")
        let next = store.open("https://next.example", creation: receipt)
        window.recordCreation(next, state: store.state)
        expect(window.referrerPool == [source, ordinary, next], "Ordinary explicit-referrer creation still unions")
        let peer = WindowPresentation(state: store.state, ready: true)
        let originalSelection = window.selectedTabIDs
        let promoted = store.adoptNativePage(url: URL(string: "https://peek.example/result"), title: "Original Peek",
            profilePath: path, preferredSpaceID: space, select: false, creation: receipt)!
        let tab = store.state.tabs.first { $0.id == promoted }!
        expect(tab.referrerID == source && tab.activeTabBeforeCreationID == source,
               "Actual adopted page records original modal source for both identities")
        expect(tab.url == "https://peek.example/result" && tab.title == "Original Peek",
               "Adoption records actual page metadata without another navigation")
        expect(window.referrerPool == [source, ordinary, next], "A provisional model record is not accepted promotion")
        expect(window.selectedTabIDs == originalSelection, "Admission does not alter physical-window selection")
        expect(window.recordPeekPromotion(promoted, state: store.state), "Accepted promotion records its pool")
        expect(window.referrerPool == [source, promoted], "Modal promotion replaces the old chain with the exact pair")
        expect(peer.referrerPool.isEmpty, "Another physical window never receives the transition")
        window.adopt(promoted, state: store.state, foreground: true)
        window.recordSelectionForReturn(promoted, state: store.state)
        expect(window.referrerPool == [source, promoted], "Selecting the new Today item preserves the modal pair")
        let selected = FolderRemovalSelection.resolve(removing: [promoted], spaceID: space, profileID: profile,
            state: store.state, selected: [promoted], focused: promoted, referrerPool: window.referrerPool,
            available: { _ in true })!
        expect(selected.tabIDs == [source], "Closing the promoted item returns to its original pinned source")
        let unavailable = FolderRemovalSelection.resolve(removing: [promoted], spaceID: space, profileID: profile,
            state: store.state, selected: [promoted], focused: promoted, referrerPool: window.referrerPool,
            available: { $0 != source })!
        expect(unavailable.tabIDs != [source], "A source unavailable to this window cannot be reclaimed")
        window.recordSelectionForReturn(source, state: store.state)
        expect(window.referrerPool == [source], "Original saved-source selection uses the existing singleton transition")
        expect(window.recordPeekPromotion(promoted, state: store.state), "Split promotion uses the same exact replacement")
        store.setSplit([source, promoted])
        window.captureCommand(store.state) { _ in true }
        window.recordSelectionForReturn(promoted, state: store.state)
        expect(window.selectedTabIDs == [source, promoted], "Actual split command keeps both original items")
        expect(window.referrerPool == [source, promoted], "Split focus retains the new modal pair")
        let surviving = FolderRemovalSelection.resolve(removing: [promoted], spaceID: space, profileID: profile,
            state: store.state, selected: [source, promoted], focused: promoted,
            referrerPool: window.referrerPool, available: { _ in true })!
        expect(surviving.tabIDs == [source], "Surviving original split pane precedes other return candidates")

        let validState = store.state, pair = window.referrerPool
        expect(!window.recordPeekPromotion(UUID(), state: validState), "Unknown item cannot replace the pool")
        var changed = validState
        changed.tabs[changed.tabs.firstIndex { $0.id == promoted }!].archivedAt = Date()
        expect(!window.recordPeekPromotion(promoted, state: changed), "Closed promoted item cannot replace the pool")
        changed = validState; changed.tabs.removeAll { $0.id == source }
        expect(!window.recordPeekPromotion(promoted, state: changed), "Missing original source cannot be silently replaced")
        changed = validState; changed.tabs[changed.tabs.firstIndex { $0.id == source }!].archivedAt = Date()
        expect(!window.recordPeekPromotion(promoted, state: changed), "Archived original source cannot authorize a transition")
        changed = validState; changed.tabs[changed.tabs.firstIndex { $0.id == source }!].profileID = UUID()
        expect(!window.recordPeekPromotion(promoted, state: changed), "Original source cannot cross Profiles")
        changed = validState; changed.tabs[changed.tabs.firstIndex { $0.id == promoted }!].profileID = UUID()
        expect(!window.recordPeekPromotion(promoted, state: changed), "The window cannot accept a foreign Profile item")
        changed = validState; changed.tabs[changed.tabs.firstIndex { $0.id == promoted }!].referrerID = promoted
        expect(!window.recordPeekPromotion(promoted, state: changed), "An item cannot be its own modal source")
        expect(window.referrerPool == pair, "Every refused transition leaves the prior pool intact")
        let ownerless = store.adoptNativePage(url: URL(string: "https://window.example"), title: "Window source",
            profilePath: path, preferredSpaceID: space, select: false)!
        expect(window.recordPeekPromotion(ownerless, state: store.state), "Source.window accepts its actual item without inventing an active ID")
        expect(window.referrerPool == [ownerless], "A window-source modal produces exactly a singleton")
        window.recordPeekPromotion(promoted, state: store.state)
        let discarded = store.adoptNativePage(url: URL(string: "https://refused.example"), title: "Refused",
            profilePath: path, preferredSpaceID: space, select: false, creation: receipt)!
        store.removeTab(discarded)
        expect(window.referrerPool == pair, "Failed native ownership leaves no promotion transition")
        expect(!window.recordPeekPromotion(discarded, state: store.state), "Rolled-back saved record cannot later mutate the pool")
        expect(WindowPresentation(state: store.state, ready: true).referrerPool.isEmpty,
               "Process/window restoration does not manufacture a pool from durable provenance")

        var validator: (() -> Bool)?, completion: ((Bool) -> Void)?, closed: Bool?
        store.requestPageRetirement = { _, validate, complete in validator = validate; completion = complete }
        store.closeTabs([promoted], selection: surviving, shouldCommit: { true }) { closed = $0 }
        expect(validator?() == true && closed == nil, "Original close remains pending behind genuine retirement admission")
        completion?(false)
        expect(closed == false && store.state.tabs.first { $0.id == promoted }?.archivedAt == nil,
               "Refused close preserves the promoted original item")
        store.closeTabs([promoted], selection: surviving, shouldCommit: { true }) { closed = $0 }
        expect(validator?() == true, "Retry revalidates the original split/selection")
        completion?(true)
        expect(closed == true && store.state.tabs.first { $0.id == promoted }?.archivedAt != nil,
               "Accepted close archives only the actual promoted item")
        expect(window.finishFolderRemoval(surviving, state: store.state, available: { _ in true }),
               "Accepted close applies the original window's existing focus receipt")
        expect(store.state.tabs.first { $0.id == source }?.kind == .today
               && window.selectedTabIDs == [source] && window.referrerPool == [source, promoted],
               "Committed close returns the original source with its unpinned pool transition")
        let savedSource = store.open("https://saved-source.example", kind: .pinned)
        let savedReceipt = TabCreationProvenance(referrerID: savedSource, activeTabID: savedSource,
                                                 profileID: profile, state: store.state)
        let modal = store.adoptNativePage(url: URL(string: "https://modal.example/result"), title: "Modal",
            profilePath: path, preferredSpaceID: space, select: false, creation: savedReceipt)!
        var savedWindow = WindowPresentation(state: store.state, ready: true)
        savedWindow.recordSelectionForReturn(savedSource, state: store.state)
        expect(savedWindow.recordPeekPromotion(modal, state: store.state), "Promotion from a pinned source records its pair")
        savedWindow.adopt(modal, state: store.state, foreground: true)
        savedWindow.recordSelectionForReturn(modal, state: store.state)
        let modalReturn = FolderRemovalSelection.resolve(removing: [modal], spaceID: space, profileID: profile,
            state: store.state, selected: [modal], focused: modal, referrerPool: savedWindow.referrerPool,
            available: { _ in true })!
        expect(modalReturn.tabIDs == [savedSource], "Closing the promoted page returns to its pinned source")
        closed = nil
        store.closeTabs([modal], selection: modalReturn, shouldCommit: { true }) { closed = $0 }
        expect(validator?() == true, "The pinned-source close passes retirement validation")
        completion?(true)
        expect(closed == true, "The pinned-source close commits")
        expect(savedWindow.finishFolderRemoval(modalReturn, state: store.state, available: { _ in true }),
               "The original window applies its pinned-source return")
        expect(savedWindow.selectedTabIDs == [savedSource] && savedWindow.referrerPool == [savedSource],
               "Committed close returns the pinned source and applies its saved-item pool transition")
        let favorite = store.open("https://global-favorite.example", kind: .favorite)
        let favoriteSpace = store.state.tabs.first { $0.id == favorite }!.spaceID
        let destination = store.createSpace(name: "Current Window Space")
        let favoriteReceipt = TabCreationProvenance(referrerID: favorite, activeTabID: nil,
            profileID: profile, state: store.state)
        let currentSpaceModal = store.adoptNativePage(url: URL(string: "https://peek.example/original-document"), title: "Original",
            profilePath: path, preferredSpaceID: destination, select: false, creation: favoriteReceipt)!
        let currentSpaceTab = store.state.tabs.first { $0.id == currentSpaceModal }!
        expect(destination != favoriteSpace && currentSpaceTab.spaceID == destination,
               "A global Favorite's promoted original page enters the current Space, not its source Space")
        expect(currentSpaceTab.profileID == profile && currentSpaceTab.referrerID == favorite,
               "Cross-Space promotion preserves the original Profile and Favorite referrer")
        var favoriteWindow = WindowPresentation(state: store.state, ready: true)
        expect(favoriteWindow.recordPeekPromotion(currentSpaceModal, state: store.state),
               "Cross-Space Favorite promotion retains the original modal return receipt")
        print("Passed \(count) Peek promotion/referrer-pool assertions")
    }
}
