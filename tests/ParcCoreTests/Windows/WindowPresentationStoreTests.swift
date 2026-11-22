import Foundation
import Testing
@testable import ParcCore

@MainActor
struct WindowPresentationStoreTests {
    private typealias StoreFixture = WindowPresentationTestsSupport.StoreFixture

    @Test func realStoreAdoptionPreservesTheOriginalWindowSelectionAndRecordsThePageOnce() throws {
        let s = try StoreFixture()
        var window = WindowPresentation(state: s.store.state, ready: true)
        let adopted = s.adopt()
        window.reconcile(s.store.state) { _ in true }
        #expect(window.selectedTabIDs == [s.original])
        #expect(s.store.state.tabs.count == 2 && s.store.state.selectedTabIDs == [s.original])
        try s.store.save()
        let loaded = try BrowserStore(directory: s.directory)
        #expect(loaded.state.tabs.filter { $0.id == adopted }.count == 1)
    }

    @Test func theStoreAcceptsSelectionAndSplitGeometryTogether() throws {
        let s = try StoreFixture()
        let adopted = s.adopt()
        let restored = BrowserSplitLayout(spaceID: s.store.activeSpaceID, tabIDs: [s.original, adopted],
                                          orientation: .vertical, widthFactors: [0.25, 0.75])
        #expect(s.store.setWindowPresentation(spaceID: s.store.activeSpaceID, selectedTabIDs: restored.tabIDs, splitLayout: restored))
        #expect(s.store.state.selectedTabIDs == restored.tabIDs && s.store.activeSplitLayout == restored)
    }

    @Test func aForeignLayoutCannotReplaceTheStoresSelectionAndGeometry() throws {
        let s = try StoreFixture()
        let adopted = s.adopt()
        let restored = BrowserSplitLayout(spaceID: s.store.activeSpaceID, tabIDs: [s.original, adopted],
                                          orientation: .vertical, widthFactors: [0.25, 0.75])
        #expect(s.store.setWindowPresentation(spaceID: s.store.activeSpaceID, selectedTabIDs: restored.tabIDs, splitLayout: restored))
        var wrongSpaceLayout = restored
        wrongSpaceLayout.spaceID = UUID()
        #expect(!s.store.setWindowPresentation(spaceID: s.store.activeSpaceID, selectedTabIDs: [s.original], splitLayout: wrongSpaceLayout))
        #expect(s.store.state.selectedTabIDs == restored.tabIDs && s.store.activeSplitLayout == restored)
    }

    @Test func anAddressCommandFromStartKeepsTheExactSavedTabAndWaitsForItsWrapper() throws {
        let s = try StoreFixture()
        let persisted = WindowPresentation(state: s.store.state, ready: true)
        let startTab = s.store.open("about:blank")
        var addressWindow = WindowPresentation(state: s.store.state, ready: true)
        #expect(addressWindow.isLocalSelection(startTab, state: s.store.state, hasNativeWrapper: false))
        let startCount = s.store.state.tabs.count
        s.store.navigate(startTab, input: "https://example.test/from-start")
        addressWindow.captureCommand(s.store.state) { _ in true }
        #expect(addressWindow.selectedTabIDs == [startTab] && s.store.state.tabs.count == startCount)
        #expect(!addressWindow.isLocalSelection(startTab, state: s.store.state, hasNativeWrapper: false))
        #expect(persisted.selectedTabIDs == [s.original])
    }

    @Test func anAddressCommandFromAnEaselKeepsTheExactSavedTabAndWaitsForNativeReadiness() throws {
        let s = try StoreFixture()
        var addressWindow = WindowPresentation(state: s.store.state, ready: true)
        let easelTab = try #require(s.store.openEasel(id: UUID(), title: "Address test"))
        addressWindow.captureCommand(s.store.state) { _ in true }
        #expect(addressWindow.isLocalSelection(easelTab, state: s.store.state, hasNativeWrapper: false))
        let count = s.store.state.tabs.count
        s.store.navigate(easelTab, input: "https://example.test/from-easel")
        addressWindow.captureCommand(s.store.state) { _ in true }
        #expect(addressWindow.selectedTabIDs == [easelTab] && s.store.state.tabs.count == count)
        #expect(!addressWindow.isLocalSelection(easelTab, state: s.store.state, hasNativeWrapper: false))
    }
}
