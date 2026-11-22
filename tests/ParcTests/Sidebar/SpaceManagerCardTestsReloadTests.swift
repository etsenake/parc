import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SpaceManagerCardTestsReloadTests {
    private typealias Cards = SpaceManagerCardTestsSupport.Cards

    private func catalog() -> (BrowserState, BrowserTab, BrowserSpace) {
        var catalog = BrowserState.initial()
        let space = catalog.spaces[0]
        let tab = Cards.tab("catalog", .today, in: space)
        catalog.tabs = [tab]
        return (catalog, tab, space)
    }

    @Test func aFirstApplyHasNoPriorFingerprint() {
        let (catalog, _, _) = catalog()
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: nil, next: catalog))
    }

    @Test func anIdenticalCatalogIsATrueNoOp() {
        let (catalog, _, _) = catalog()
        #expect(SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: catalog))
    }

    @Test func aLiveTitleAndURLPublishSkipsTheReload() {
        let (catalog, _, _) = catalog()
        var titled = catalog
        titled.tabs[0].title = "Unrelated live title"
        titled.tabs[0].url = "https://example.test/catalog-live"
        #expect(SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: titled))
    }

    @Test func aSpaceThemeChangeStillReloads() {
        let (catalog, _, _) = catalog()
        var themed = catalog
        themed.spaces[0].theme = .singleColor(ThemeColor(hex: "112233")!)
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: themed))
    }

    @Test func addingASpaceStillReloads() {
        let (catalog, _, space) = catalog()
        var reordered = catalog
        reordered.spaces.append(BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: space.profileID))
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: reordered))
    }

    @Test func aProfileChangeStillReloads() {
        let (catalog, _, _) = catalog()
        var profiled = catalog
        profiled.profiles[0].name = "Renamed Profile"
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: profiled))
    }

    @Test func aSelectionChangeStillReloads() {
        let (catalog, tab, _) = catalog()
        var selectionChanged = catalog
        selectionChanged.selectedTabIDs = [tab.id]
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: selectionChanged))
    }

    @Test func aTitleAndURLPublishRetainsTheAlreadyAppliedCard() {
        let (catalog, _, space) = catalog()
        var titled = catalog
        titled.tabs[0].title = "Unrelated live title"
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        manager.ownerValid = { true }
        manager.reload(catalog)
        let hosted = manager.sidebar(for: space.id)
        manager.reload(titled)
        #expect(manager.sidebar(for: space.id) === hosted)
    }

    @Test func cancellingAThemePreviewStillReappliesThroughReload() {
        let (catalog, _, space) = catalog()
        var themed = catalog
        themed.spaces[0].theme = .singleColor(ThemeColor(hex: "112233")!)
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        manager.ownerValid = { true }
        manager.reload(catalog)
        let hosted = manager.sidebar(for: space.id)
        manager.previewTheme(themed.spaces[0].theme, spaceID: space.id)
        manager.reload(catalog)
        #expect(manager.sidebar(for: space.id) === hosted)
    }

    @Test func aCommittedThemeChangeStillReloadsSpaceManagement() {
        let (catalog, _, space) = catalog()
        var themed = catalog
        themed.spaces[0].theme = .singleColor(ThemeColor(hex: "112233")!)
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        manager.ownerValid = { true }
        manager.reload(catalog)
        manager.reload(themed)
        #expect(manager.sidebar(for: space.id) != nil)
    }
}
