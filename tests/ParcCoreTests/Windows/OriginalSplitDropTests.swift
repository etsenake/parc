import Foundation
import Testing
@testable import ParcCore

struct OriginalSplitDropTests {
    @MainActor private final class Fixture {
        let root: URL
        let store: BrowserStore
        let a: UUID, b: UUID, c: UUID
        let original: BrowserState
        let profile: UUID, space: UUID
        let home = UUID(), bHome = UUID()
        let now = Date(timeIntervalSince1970: 1234)

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-original-split-" + UUID().uuidString)
            let store = try BrowserStore(directory: root)
            let a = store.open("https://saved.invalid", kind: .pinned), b = store.open("https://ordinary.invalid")
            let c = store.open("https://sibling.invalid", kind: .pinned)
            store.selectTab(a)
            self.store = store
            self.a = a; self.b = b; self.c = c
            original = store.state
            profile = store.activeSpace.profileID
            space = store.activeSpaceID
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var aIndex: Int { original.tabs.firstIndex { $0.id == a }! }
        var bIndex: Int { original.tabs.firstIndex { $0.id == b }! }
        var pinnedLocation: SidebarContainerLocation { SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned) }
        var tray: SidebarContainerLocation { SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile) }

        func pinned() -> BrowserState {
            var state = original
            state.tabs[aIndex].url = "https://live.invalid/form"
            state.tabs[aIndex].title = "Live"
            state.tabs[aIndex].customTitle = "Authored"
            state.tabs[aIndex].referrerID = b
            state.sidebarItemOrder[pinnedLocation.key] = [.tab(c), .tab(a)]
            return state
        }

        func favoriteTarget() -> BrowserState {
            var state = original
            state.tabs[aIndex].kind = .favorite
            state.sidebarItemOrder[tray.key] = [.tab(a)]
            return state
        }

        func favoriteContainer() -> (BrowserState, BrowserSplitLayout) {
            var state = favoriteTarget()
            state.tabs[state.tabs.firstIndex { $0.id == c }!].kind = .favorite
            let layout = BrowserSplitLayout(spaceID: space, tabIDs: [a, c], orientation: .horizontal, widthFactors: [0.4, 0.6])
            state.splitLayouts = [layout]
            state.selectedTabIDs = [a, c]
            return (state, layout)
        }

        func propose(_ state: BrowserState, source: UUID? = nil, target: SplitDropTarget = .insert(1),
                     layout: BrowserSplitLayout? = nil, homes: [UUID: UUID]? = nil) -> BrowserState? {
            OriginalSplitDrop.proposal(source: source ?? b, state: state, selection: state.selectedTabIDs,
                layout: layout, target: target, orientation: .horizontal, spaceID: space,
                profileID: profile, now: now, savedHomeIDs: homes ?? [a: home],
                creation: TabCreationProvenance(referrerID: nil, activeTabID: a, profileID: profile, state: state))
        }

        func session(_ state: BrowserState, _ name: String) throws -> URL {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
            return directory
        }

        func breakWrites() throws -> Data {
            let file = root.appendingPathComponent("session.json")
            let saved = try Data(contentsOf: file)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            return saved
        }

        func restoreWrites(_ saved: Data) throws {
            let file = root.appendingPathComponent("session.json")
            try FileManager.default.removeItem(at: file)
            try saved.write(to: file)
        }
    }

    @MainActor @Test func draggingAnOriginalIntoASavedPaneFormsAGroupOfTheOriginalIdentities() throws {
        let f = try Fixture()
        let proposed = try #require(f.propose(f.pinned()))
        #expect(proposed.selectedTabIDs == [f.a, f.b])
        #expect(proposed.splitLayouts.count == 1)
    }

    @MainActor @Test func theLivePageKeepsItsRequestAndProvenanceAndMovesToToday() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let proposed = try #require(f.propose(pinned))
        let live = try #require(proposed.tabs.first { $0.id == f.a })
        #expect(live.url == pinned.tabs[f.aIndex].url)
        #expect(live.title == "Live")
        #expect(live.referrerID == f.b)
        #expect(live.kind == .today)
    }

    @MainActor @Test func theSavedHomeUsesTheSavedAddressAndTitle() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let proposed = try #require(f.propose(pinned))
        let copy = try #require(proposed.tabs.first { $0.id == f.home })
        #expect(copy.url == pinned.tabs[f.aIndex].savedURL)
        #expect(copy.title == pinned.tabs[f.aIndex].savedTitle)
        #expect(copy.customTitle == "Authored")
    }

    @MainActor @Test func theSavedHomeOwnsAFreshCreationReceipt() throws {
        let f = try Fixture()
        let proposed = try #require(f.propose(f.pinned()))
        let copy = try #require(proposed.tabs.first { $0.id == f.home })
        #expect(copy.referrerID == nil)
        #expect(copy.activeTabBeforeCreationID == f.a)
        #expect(copy.createdAt == f.now)
    }

    @MainActor @Test func theSavedHomeReplacesTheOriginalInItsSidebarSlot() throws {
        let f = try Fixture()
        let proposed = try #require(f.propose(f.pinned()))
        #expect(SidebarHierarchy.children(in: f.pinnedLocation, state: proposed) == [.tab(f.c), .tab(f.home)])
    }

    @MainActor @Test func theExistingOrdinaryTabAnchorsTheNewGroup() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let proposed = try #require(f.propose(pinned))
        #expect(proposed.splitLayouts[0].sidebarAnchorID == f.b)
        #expect(proposed.tabs[f.bIndex].url == pinned.tabs[f.bIndex].url)
    }

    @MainActor @Test func aMissingHomeRefuses() throws {
        let f = try Fixture()
        #expect(f.propose(f.pinned(), homes: [:]) == nil)
    }

    @MainActor @Test func aHomeCollidingWithTheOriginalRefuses() throws {
        let f = try Fixture()
        #expect(f.propose(f.pinned(), homes: [f.a: f.a]) == nil)
    }

    @MainActor @Test func centerReplacementLeavesTheSavedItemIntact() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let replaced = try #require(f.propose(pinned, target: .replace(0), homes: [:]))
        #expect(replaced.selectedTabIDs == [f.b])
        #expect(replaced.tabs.first { $0.id == f.a } == pinned.tabs[f.aIndex])
        #expect(replaced.tabs.count == pinned.tabs.count)
        #expect(replaced.splitLayouts.isEmpty)
    }

    @MainActor @Test func groupingTwoSavedItemsKeepsAHomeForEach() throws {
        let f = try Fixture()
        var both = f.pinned()
        both.tabs[f.bIndex].kind = .pinned
        let paired = try #require(f.propose(both, homes: [f.a: f.home, f.b: f.bHome]))
        #expect(paired.tabs.count == both.tabs.count + 2)
        #expect(paired.tabs.filter { [f.a, f.b].contains($0.id) }.allSatisfy { $0.kind == .today })
    }

    @MainActor @Test func twoHomesCannotShareAnIdentity() throws {
        let f = try Fixture()
        var both = f.pinned()
        both.tabs[f.bIndex].kind = .pinned
        #expect(f.propose(both, homes: [f.a: f.home, f.b: f.home]) == nil)
    }

    @MainActor private func sourceGroup(_ f: Fixture) -> (BrowserState, BrowserSplitLayout) {
        var state = f.original
        state.selectedTabIDs = [f.b]
        var old = BrowserSplitLayout(spaceID: f.space, tabIDs: [f.a, f.c], orientation: .vertical, widthFactors: [0.3, 0.7])
        old.customTitle = "Original"
        old.customIcon = .emoji("🌙")
        old.sidebarAnchorID = f.a
        state.splitLayouts = [old]
        state.sidebarItemOrder[f.pinnedLocation.key] = [.tab(f.a)]
        return (state, old)
    }

    @MainActor @Test func draggingAChildOutOfAGroupReplacesItWithItsHomeAndMovesTheAnchor() throws {
        let f = try Fixture()
        let (state, old) = sourceGroup(f)
        let moved = try #require(f.propose(state, source: f.a))
        let kept = try #require(moved.splitLayouts.first { $0.id == old.id })
        #expect(kept.tabIDs == [f.home, f.c])
        #expect(kept.sidebarAnchorID == f.home)
    }

    @MainActor @Test func theSourceGroupKeepsItsGeometryAndAppearance() throws {
        let f = try Fixture()
        let (state, old) = sourceGroup(f)
        let moved = try #require(f.propose(state, source: f.a))
        let kept = try #require(moved.splitLayouts.first { $0.id == old.id })
        #expect(kept.widthFactors == old.widthFactors)
        #expect(kept.orientation == old.orientation)
        #expect(kept.customTitle == old.customTitle)
        #expect(kept.customIcon == old.customIcon)
    }

    @MainActor @Test func theOriginalChildEntersTheDestinationWithoutAClone() throws {
        let f = try Fixture()
        let (state, old) = sourceGroup(f)
        let moved = try #require(f.propose(state, source: f.a))
        #expect(moved.splitLayouts.first { $0.id != old.id }?.tabIDs == [f.b, f.a])
    }

    @MainActor @Test func theSourceGroupKeepsItsSidebarSlot() throws {
        let f = try Fixture()
        let (state, old) = sourceGroup(f)
        let moved = try #require(f.propose(state, source: f.a))
        #expect(SidebarHierarchy.children(in: f.pinnedLocation, state: moved) == [.split(old.id)])
    }

    @MainActor @Test func aMemberIsNotItsOwnDropSource() throws {
        let f = try Fixture()
        let grouped = try #require(f.propose(f.pinned()))
        #expect(f.propose(grouped, source: f.b, target: .insert(0), layout: grouped.splitLayouts[0], homes: [:]) == nil)
    }

    @MainActor @Test func aCrossProfileOriginalRefuses() throws {
        let f = try Fixture()
        var invalid = f.pinned()
        invalid.tabs[f.bIndex].profileID = UUID()
        #expect(f.propose(invalid) == nil)
    }

    @MainActor @Test func aMissingSavedParentRefuses() throws {
        let f = try Fixture()
        var invalid = f.pinned()
        invalid.tabs[f.aIndex].folderID = UUID()
        #expect(f.propose(invalid) == nil)
    }

    @MainActor @Test func anArchivedSourceRefuses() throws {
        let f = try Fixture()
        var invalid = f.pinned()
        invalid.tabs[f.bIndex].archivedAt = f.now
        #expect(f.propose(invalid) == nil)
    }

    @MainActor @Test func aStaleIndexRefuses() throws {
        let f = try Fixture()
        #expect(f.propose(f.pinned(), target: .insert(5)) == nil)
    }

    @MainActor @Test func aStandaloneFavoriteKeepsItsHomeInTheTrayAndRunsLiveInToday() throws {
        let f = try Fixture()
        let moved = try #require(f.propose(f.favoriteTarget()))
        #expect(moved.tabs.first { $0.id == f.a }?.kind == .today)
        #expect(moved.tabs.first { $0.id == f.home }?.kind == .favorite)
    }

    @MainActor @Test func theFavoriteHomeKeepsItsExactTraySlot() throws {
        let f = try Fixture()
        let moved = try #require(f.propose(f.favoriteTarget()))
        #expect(SidebarHierarchy.children(in: f.tray, state: moved) == [.tab(f.home)])
    }

    @MainActor @Test func aWholeFavoriteDestinationKeepsItsGroupAndChildOrder() throws {
        let f = try Fixture()
        let (state, layout) = f.favoriteContainer()
        let inserted = try #require(f.propose(state, layout: layout, homes: [:]))
        #expect(inserted.splitLayouts[0].id == layout.id)
        #expect(inserted.selectedTabIDs == [f.a, f.b, f.c])
    }

    @MainActor @Test func aWholeFavoriteDestinationAdmitsTheChildWithoutReplacingHomes() throws {
        let f = try Fixture()
        let (state, layout) = f.favoriteContainer()
        let inserted = try #require(f.propose(state, layout: layout, homes: [:]))
        #expect(inserted.tabs.count == state.tabs.count)
        #expect(inserted.tabs[f.bIndex].kind == .favorite)
    }

    @MainActor @Test func favoriteReplacementKeepsTheDisplacedOriginalRecord() throws {
        let f = try Fixture()
        let (state, layout) = f.favoriteContainer()
        let replacement = try #require(f.propose(state, target: .replace(0), layout: layout, homes: [:]))
        #expect(replacement.selectedTabIDs == [f.b, f.c])
        #expect(replacement.tabs[f.aIndex] == state.tabs[f.aIndex])
    }

    @MainActor @Test func favoriteReplacementCannotExceedTheTrayRootLimit() throws {
        let f = try Fixture()
        let (state, layout) = f.favoriteContainer()
        var maximum = state
        let template = f.favoriteTarget().tabs[f.aIndex]
        for _ in 0..<11 { var extra = template; extra.id = UUID(); maximum.tabs.append(extra) }
        #expect(f.propose(maximum, target: .replace(0), layout: layout, homes: [:]) == nil)
    }

    @MainActor @Test func anOversizedUnrelatedTrayDoesNotBlockOrdinaryMovement() throws {
        let f = try Fixture()
        var legacyTray = f.pinned()
        let template = f.favoriteTarget().tabs[f.aIndex]
        for _ in 0..<13 { var extra = template; extra.id = UUID(); legacyTray.tabs.append(extra) }
        #expect(f.propose(legacyTray) != nil)
    }

    @MainActor @Test func aSavedSplitTransactionCommitsThroughTheStore() throws {
        let f = try Fixture()
        #expect(f.store.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home]))
    }

    @MainActor @Test func theHomeAndGroupPersistTogether() throws {
        let f = try Fixture()
        _ = f.store.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home])
        let disk = try BrowserStore(directory: f.root)
        #expect(disk.state.tabs.contains { $0.id == f.home })
        #expect(disk.state.selectedTabIDs == [f.a, f.b])
    }

    @MainActor private func groupedStore(_ f: Fixture) -> BrowserSplitLayout {
        _ = f.store.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home])
        return f.store.activeSplitLayout!
    }

    @MainActor @Test func aSaveFailureRefusesTheCommit() throws {
        let f = try Fixture()
        let current = groupedStore(f)
        _ = try f.breakWrites()
        #expect(!f.store.dropTabIntoSplit(f.c, expectedSelection: [f.a, f.b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [f.c: f.bHome]))
    }

    @MainActor @Test func aSaveFailureKeepsTheOriginalRecordsAndSelection() throws {
        let f = try Fixture()
        let current = groupedStore(f)
        let before = f.store.state
        _ = try f.breakWrites()
        _ = f.store.dropTabIntoSplit(f.c, expectedSelection: [f.a, f.b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [f.c: f.bHome])
        #expect(f.store.state == before)
        #expect(f.store.persistenceError != nil)
    }

    @MainActor @Test func retryingAfterASaveFailureCreatesExactlyOneHome() throws {
        let f = try Fixture()
        let current = groupedStore(f)
        let saved = try f.breakWrites()
        _ = f.store.dropTabIntoSplit(f.c, expectedSelection: [f.a, f.b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [f.c: f.bHome])
        try f.restoreWrites(saved)
        #expect(f.store.dropTabIntoSplit(f.c, expectedSelection: [f.a, f.b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [f.c: f.bHome]))
        #expect(f.store.state.tabs.filter { $0.id == f.bHome }.count == 1)
    }

    @MainActor private func typedStore(_ f: Fixture, note: Bool) throws -> (BrowserStore, SidebarDocumentReference, String) {
        let reference: SidebarDocumentReference
        let address: String
        if note {
            let file = f.root.appendingPathComponent("Shared Note.md")
            try Data().write(to: file)
            reference = SidebarDocumentReference(page: .note(file), profileID: f.profile) {
                guard FileManager.default.fileExists(atPath: file.path) else { throw CocoaError(.fileNoSuchFile) }
            }
            address = InternalPage.note(file).urlString
        } else {
            let easels = try EaselStore(directory: f.root.appendingPathComponent("easels"))
            let easel = try easels.create()
            reference = SidebarDocumentReference(page: .easel(easel.document.id), profileID: f.profile) { try easels.validateReference(easel.document.id) }
            address = "parc://easel/" + easel.document.id.uuidString
        }
        var typed = f.pinned()
        typed.tabs[f.aIndex].url = address
        typed.tabs[f.aIndex].savedURL = address
        return (try BrowserStore(directory: f.session(typed, "alias")), reference, address)
    }

    @MainActor @Test(arguments: [true, false])
    func aTypedOriginalRequiresDocumentValidation(_ note: Bool) throws {
        let f = try Fixture()
        let (model, _, _) = try typedStore(f, note: note)
        #expect(!model.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home]))
    }

    @MainActor @Test(arguments: [true, false])
    func aMissingDocumentReceiptPublishesNoAlias(_ note: Bool) throws {
        let f = try Fixture()
        let (model, _, _) = try typedStore(f, note: note)
        let initial = model.state
        _ = model.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home])
        #expect(model.state == initial)
    }

    @MainActor @Test(arguments: [true, false])
    func aValidatedTypedOriginalCommits(_ note: Bool) throws {
        let f = try Fixture()
        let (model, reference, _) = try typedStore(f, note: note)
        #expect(model.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home], documents: [f.a: reference]))
    }

    @MainActor @Test(arguments: [true, false])
    func theTypedOriginalAndItsHomeShareTheAuthoredDocument(_ note: Bool) throws {
        let f = try Fixture()
        let (model, reference, address) = try typedStore(f, note: note)
        _ = model.dropTabIntoSplit(f.b, expectedSelection: [f.a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [f.a: f.home], documents: [f.a: reference])
        #expect(model.state.tabs.first { $0.id == f.home }?.url == address)
        #expect(model.state.tabs.first { $0.id == f.a }?.url == address)
    }

    @MainActor private final class StackFixture {
        let directory: URL
        let store: BrowserStore
        let t: [UUID]

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-original-stacks-" + UUID().uuidString)
            let store = try BrowserStore(directory: directory)
            self.store = store
            t = (0..<13).map { store.open("https://stack\($0).invalid") }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func drop(_ source: UUID, _ target: SplitDropTarget, _ orientation: SplitOrientation = .horizontal) -> Bool {
            store.dropTabIntoSplit(source, expectedSelection: store.state.selectedTabIDs, expectedLayout: store.activeSplitLayout,
                target: target, orientation: orientation)
        }

        func close(_ left: [Double]?, _ right: [Double]?) -> Bool {
            guard let left, let right else { return false }
            return left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
        }

        func flatPair(_ first: Int, _ second: Int, _ orientation: SplitOrientation, _ factors: [Double]) {
            store.setSplit([t[first], t[second]])
            _ = store.setSplitLayout(orientation: orientation, widthFactors: factors)
        }

        func stackedBelow() -> BrowserSplitLayout {
            flatPair(0, 1, .horizontal, [0.4, 0.6])
            _ = drop(t[2], .stack(1, after: true))
            return store.activeSplitLayout!
        }

        func stackedFour() -> BrowserSplitLayout {
            _ = stackedBelow()
            _ = drop(t[3], .stack(1, after: false))
            return store.activeSplitLayout!
        }
    }

    @MainActor @Test func aBottomBandDropCommitsOntoAFlatSplit() throws {
        let s = try StackFixture()
        s.flatPair(0, 1, .horizontal, [0.4, 0.6])
        #expect(s.drop(s.t[2], .stack(1, after: true)))
    }

    @MainActor @Test func theStackedTabSitsBelowItsPaneWhoseColumnKeepsItsWidth() throws {
        let s = try StackFixture()
        s.flatPair(0, 1, .horizontal, [0.4, 0.6])
        let flat = s.store.activeSplitLayout!
        _ = s.drop(s.t[2], .stack(1, after: true))
        let layout = try #require(s.store.activeSplitLayout)
        #expect(layout.id == flat.id)
        #expect(layout.tabIDs == [s.t[0], s.t[1], s.t[2]])
        #expect(layout.orientation == .horizontal)
        #expect(layout.stacks?.slotSizes == [1, 2])
        #expect(s.close(layout.stacks?.slotFactors, [0.4, 0.6]))
    }

    @MainActor @Test func theNewStackSavesWithTheDrop() throws {
        let s = try StackFixture()
        let layout = s.stackedBelow()
        #expect(try BrowserStore(directory: s.directory).activeSplitLayout == layout)
    }

    @MainActor @Test func aDropAboveAStackedPaneCommits() throws {
        let s = try StackFixture()
        _ = s.stackedBelow()
        #expect(s.drop(s.t[3], .stack(1, after: false)))
    }

    @MainActor @Test func aDropAboveJoinsTheExistingStackAboveThatPane() throws {
        let s = try StackFixture()
        let layout = s.stackedFour()
        #expect(layout.tabIDs == [s.t[0], s.t[3], s.t[1], s.t[2]])
        #expect(layout.stacks?.slotSizes == [1, 3])
        #expect(s.close(layout.stacks?.stackFactors[1], [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @MainActor @Test func aStackDropRefusesAtFourPanes() throws {
        let s = try StackFixture()
        _ = s.stackedFour()
        let full = s.store.state
        #expect(!s.drop(s.t[4], .stack(0, after: true)))
        #expect(s.store.state == full)
    }

    @MainActor @Test func replacementStaysAvailableAtFourPanesAndKeepsTheStack() throws {
        let s = try StackFixture()
        let layout = s.stackedFour()
        #expect(s.drop(s.t[4], .replace(2)))
        #expect(s.store.state.selectedTabIDs == [s.t[0], s.t[3], s.t[4], s.t[2]])
        #expect(s.store.activeSplitLayout?.stacks == layout.stacks)
    }

    @MainActor @Test func aRightBandDropCommitsOntoATopAndBottomSplit() throws {
        let s = try StackFixture()
        s.flatPair(5, 6, .vertical, [0.5, 0.5])
        #expect(s.drop(s.t[7], .stack(0, after: true), .vertical))
    }

    @MainActor @Test func theTabSitsRightOfItsPaneInThatRow() throws {
        let s = try StackFixture()
        s.flatPair(5, 6, .vertical, [0.5, 0.5])
        _ = s.drop(s.t[7], .stack(0, after: true), .vertical)
        #expect(s.store.state.selectedTabIDs == [s.t[5], s.t[7], s.t[6]])
        #expect(s.store.activeSplitLayout?.orientation == .vertical)
        #expect(s.store.activeSplitLayout?.stacks?.slotSizes == [2, 1])
    }

    @MainActor @Test func aMainRowInsertStillAddsAFlatPane() throws {
        let s = try StackFixture()
        s.flatPair(8, 9, .horizontal, [0.4, 0.6])
        #expect(s.drop(s.t[10], .insert(1)))
        #expect(s.store.state.selectedTabIDs == [s.t[8], s.t[10], s.t[9]])
        #expect(s.store.activeSplitLayout?.stacks == nil)
        #expect(s.close(s.store.activeSplitLayout?.widthFactors, BrowserSplitLayout.normalized([0.4, 0.5, 0.6], count: 3)))
    }

    @MainActor @Test func aFlatReplacementKeepsItsFlatWeights() throws {
        let s = try StackFixture()
        s.flatPair(8, 9, .horizontal, [0.4, 0.6])
        _ = s.drop(s.t[10], .insert(1))
        let inserted = s.store.activeSplitLayout!
        #expect(s.drop(s.t[11], .replace(1)))
        #expect(s.store.state.selectedTabIDs == [s.t[8], s.t[11], s.t[9]])
        #expect(s.store.activeSplitLayout?.stacks == nil)
        #expect(s.store.activeSplitLayout?.widthFactors == inserted.widthFactors)
    }

    @MainActor private func fullFlat(_ s: StackFixture) {
        s.flatPair(8, 9, .horizontal, [0.4, 0.6])
        _ = s.drop(s.t[10], .insert(1))
        _ = s.drop(s.t[11], .replace(1))
        _ = s.drop(s.t[10], .insert(3))
    }

    @MainActor @Test func aFourthFlatPaneJoinsTheMainRow() throws {
        let s = try StackFixture()
        s.flatPair(8, 9, .horizontal, [0.4, 0.6])
        _ = s.drop(s.t[10], .insert(1))
        _ = s.drop(s.t[11], .replace(1))
        #expect(s.drop(s.t[10], .insert(3)))
        #expect(s.store.activeSplitLayout?.stacks == nil)
    }

    @MainActor @Test func aFullFlatSplitRefusesAStackDrop() throws {
        let s = try StackFixture()
        fullFlat(s)
        let four = s.store.state
        #expect(!s.drop(s.t[12], .stack(1, after: true)))
        #expect(s.store.state == four)
    }

    @MainActor @Test func aFullFlatSplitStillTakesAReplacement() throws {
        let s = try StackFixture()
        fullFlat(s)
        #expect(s.drop(s.t[12], .replace(1)))
        #expect(s.store.state.selectedTabIDs == [s.t[8], s.t[12], s.t[9], s.t[10]])
        #expect(s.store.activeSplitLayout?.stacks == nil)
    }
}
