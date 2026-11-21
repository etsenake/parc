import Combine
import Foundation
import Testing
@testable import ParcCore

struct SplitSubmissionTests {
    @MainActor struct Split {
        let directory: URL
        let store: BrowserStore
        let source: UUID
        let right: UUID
        let url = URL(string: "https://example.test/search?q=a%26b#fragment")!

        init() throws {
            directory = CommandBarFixtures.temporaryDirectory("command-split")
            store = try BrowserStore(directory: directory)
            source = store.openResolvedURL(URL(string: "https://example.test/source")!)
            right = store.openResolvedURL(URL(string: "https://example.test/right")!)
            store.setSplit([source, right])
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [3, 1])
        }

        func insertNewTab() -> UUID {
            let target = UUID()
            _ = store.insertCommandBarSplit(after: source, expectedSelection: [source, right], tabID: target, newURL: url)
            return target
        }

        func tab(_ id: UUID) -> BrowserTab? { store.state.tabs.first { $0.id == id } }
    }

    @Test @MainActor func newTokenMetadataPublishesWithItsFinalDestinationInOneTransaction() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let target = UUID()
        var publications = 0
        var sawTargetWithWrongSelection = false
        let observation = split.store.statePublisher.dropFirst().sink { state in
            publications += 1
            if state.tabs.contains(where: { $0.id == target }),
               state.selectedTabIDs != [split.source, target, split.right] {
                sawTargetWithWrongSelection = true
            }
        }
        #expect(split.store.insertCommandBarSplit(after: split.source, expectedSelection: [split.source, split.right],
                                                  tabID: target, newURL: split.url))
        observation.cancel()
        #expect(!sawTargetWithWrongSelection)
        #expect(publications == 1)
    }

    @Test @MainActor func insertGoesImmediatelyAfterTheFocusedPaneNotAtTheEnd() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let target = split.insertNewTab()
        #expect(split.store.state.selectedTabIDs == [split.source, target, split.right])
    }

    @Test @MainActor func insertedTabKeepsTheRequestURLAndTheActiveProfile() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let target = split.insertNewTab()
        #expect(split.tab(target)?.url == split.url.absoluteString)
        #expect(split.tab(target)?.profileID == split.store.activeSpace.profileID)
    }

    @Test @MainActor func insertKeepsTheExistingOrientationAndPaneProportion() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        _ = split.insertNewTab()
        let layout = try #require(split.store.activeSplitLayout)
        #expect(layout.orientation == .vertical)
        #expect(abs(layout.widthFactors[0] / layout.widthFactors[2] - 3) < 0.0001)
    }

    @Test @MainActor func staleSelectionCannotCommitAndDoesNotMutate() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        _ = split.insertNewTab()
        let before = split.store.state
        #expect(!split.store.insertCommandBarSplit(after: split.source, expectedSelection: [split.source, split.right],
                                                   tabID: UUID(), newURL: split.url))
        #expect(split.store.state == before)
    }

    @Test @MainActor func missingOriginalFocusCannotCommit() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        #expect(!split.store.insertCommandBarSplit(after: UUID(), expectedSelection: split.store.state.selectedTabIDs,
                                                   tabID: UUID(), newURL: split.url))
    }

    @Test @MainActor func newRequestCannotReplaceAnExistingIdentity() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let target = split.insertNewTab()
        #expect(!split.store.insertCommandBarSplit(after: split.source, expectedSelection: split.store.state.selectedTabIDs,
                                                   tabID: target, newURL: split.url))
    }

    @Test @MainActor func existingTabEntersTheSplitAfterTheFocusedMiddlePaneWithoutCloning() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let target = split.insertNewTab()
        let existing = split.store.openResolvedURL(URL(string: "https://example.test/existing")!)
        let expected = [split.source, target, split.right]
        split.store.setSplit(expected)
        let tabCount = split.store.state.tabs.count
        #expect(split.store.insertCommandBarSplit(after: target, expectedSelection: expected, tabID: existing))
        #expect(split.store.state.selectedTabIDs == [split.source, target, existing, split.right])
        #expect(split.store.state.tabs.count == tabCount)
    }

    @Test @MainActor func fullSplitRejectsBeforeCreatingATabAndPreservesAllState() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let target = split.insertNewTab()
        let existing = split.store.openResolvedURL(URL(string: "https://example.test/existing")!)
        split.store.setSplit([split.source, target, split.right])
        #expect(split.store.insertCommandBarSplit(after: target, expectedSelection: [split.source, target, split.right], tabID: existing))
        let full = split.store.state
        #expect(!split.store.insertCommandBarSplit(after: target, expectedSelection: full.selectedTabIDs,
                                                   tabID: UUID(), newURL: split.url))
        #expect(split.store.state == full)
    }

    @Test @MainActor func alreadyVisibleOriginalTabStaysEligibleWithoutReorderingOrDuplicatingPanes() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let target = split.insertNewTab()
        let existing = split.store.openResolvedURL(URL(string: "https://example.test/existing")!)
        split.store.setSplit([split.source, target, split.right])
        _ = split.store.insertCommandBarSplit(after: target, expectedSelection: [split.source, target, split.right], tabID: existing)
        let full = split.store.state
        #expect(split.store.insertCommandBarSplit(after: target, expectedSelection: full.selectedTabIDs, tabID: split.right))
        #expect(split.store.state == full)
    }

    @Test @MainActor func aTodayNoteJoinsAsALaterPaneWithoutBeingPromoted() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let host = split.store.openResolvedURL(URL(string: "https://example.test/later-host")!)
        split.store.selectTab(host)
        let noteURL = URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")
        let noteID = try #require(split.store.openNote(url: noteURL, title: "Later Note"))
        split.store.selectTab(host)
        #expect(split.store.insertCommandBarSplit(after: host, expectedSelection: [host], tabID: noteID))
        #expect(split.store.state.selectedTabIDs == [host, noteID])
        #expect(split.store.state.tabs.filter { InternalPage(urlString: $0.url)?.noteURL != nil }.count == 1)
    }

    @Test @MainActor func aTodayEaselJoinsAsALaterPaneWithoutBeingPromoted() throws {
        let split = try Split()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let host = split.store.openResolvedURL(URL(string: "https://example.test/easel-host")!)
        split.store.selectTab(host)
        let easel = try #require(split.store.openEasel(id: UUID(), title: "Later Easel"))
        split.store.selectTab(host)
        #expect(split.store.insertCommandBarSplit(after: host, expectedSelection: [host], tabID: easel))
        #expect(split.store.state.selectedTabIDs == [host, easel])
    }

    @MainActor struct Foreign {
        let split: Split
        let otherSpace: UUID
        let other: UUID
        let foreign: UUID
        let sourceSpace: UUID

        init() throws {
            let base = try Split()
            split = base
            let store = base.store
            store.setSplit([base.source])
            otherSpace = store.createSpace(name: "Other")
            other = store.openResolvedURL(URL(string: "https://example.test/other")!)
            foreign = store.openResolvedURL(URL(string: "https://example.test/foreign")!)
            let home = store.state.tabs.first { $0.id == base.source }!.spaceID
            sourceSpace = home
            store.selectSpace(home)
            store.setSplit([base.source])
        }
    }

    @Test @MainActor func aForeignSpaceTabMovesIntoThisSpaceWithoutASpaceSwitch() throws {
        let fixture = try Foreign()
        defer { try? FileManager.default.removeItem(at: fixture.split.directory) }
        let store = fixture.split.store
        #expect(store.insertCommandBarSplit(after: fixture.split.source, expectedSelection: [fixture.split.source],
                                            tabID: fixture.foreign))
        #expect(store.state.selectedTabIDs == [fixture.split.source, fixture.foreign])
        #expect(store.activeSpaceID == fixture.sourceSpace)
        #expect(fixture.split.tab(fixture.foreign)?.spaceID == fixture.sourceSpace)
    }

    @Test @MainActor func aSameProfileFavoriteFromAnotherSpaceJoinsTheTodaySplitAndKeepsItsTrayHome() throws {
        let fixture = try Foreign()
        defer { try? FileManager.default.removeItem(at: fixture.split.directory) }
        let store = fixture.split.store
        store.setKind(fixture.other, .favorite)
        #expect(store.insertCommandBarSplit(after: fixture.split.source, expectedSelection: [fixture.split.source],
                                            tabID: fixture.other))
        let favoriteHome = store.state.tabs.first {
            $0.id != fixture.other && $0.kind == .favorite && $0.savedURL == "https://example.test/other"
        }
        #expect(fixture.split.tab(fixture.other)?.kind == .today)
        #expect(fixture.split.tab(fixture.other)?.spaceID == fixture.sourceSpace)
        #expect(favoriteHome?.spaceID == fixture.otherSpace)
    }

    @Test @MainActor func splitSelectionAndLayoutPersistAfterAFavoriteJoins() throws {
        let fixture = try Foreign()
        defer { try? FileManager.default.removeItem(at: fixture.split.directory) }
        let store = fixture.split.store
        store.setKind(fixture.other, .favorite)
        _ = store.insertCommandBarSplit(after: fixture.split.source, expectedSelection: [fixture.split.source], tabID: fixture.other)
        try store.save()
        let restored = try BrowserStore(directory: fixture.split.directory)
        #expect(restored.state.selectedTabIDs == [fixture.split.source, fixture.other])
        #expect(restored.activeSplitLayout?.tabIDs == [fixture.split.source, fixture.other])
    }
}
