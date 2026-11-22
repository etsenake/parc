import AppKit
import Testing
@testable import Parc

struct NavigationLoadingTestsReloadLayout {
    private static let lights = CGSize(width: 60, height: 14)

    @MainActor @Test func theDeveloperReloadPairIsNineteenPlusFourteenPoints() {
        let developer = SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true, developerReload: true)
        #expect(developer.reload?.width == 19)
        #expect(developer.reloadOptions?.width == 14)
        #expect(developer.reload?.maxX == developer.reloadOptions?.minX)
    }

    @MainActor @Test func theChevronSharesReloadsTrailingEdge() {
        let regular = SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true)
        let developer = SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true, developerReload: true)
        #expect(developer.reloadOptions?.maxX == regular.reload?.maxX)
    }

    @MainActor @Test func regularSpacingPrecedesThePair() {
        let developer = SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true, developerReload: true)
        #expect(developer.forward.map { $0.maxX + 2 } == developer.reload?.minX)
        #expect(developer.forward?.width == 32)
    }

    @MainActor @Test func thereIsNoChevronOutsideDeveloperMode() {
        #expect(SidebarChromeLayout.toolbar(width: 228, windowButtons: Self.lights, showsNavigation: true).reloadOptions == nil)
    }

    @MainActor @Test func aNarrowRowKeepsItsOrdinaryReload() {
        #expect(SidebarChromeLayout.toolbar(width: 200, windowButtons: Self.lights, showsNavigation: true, developerReload: true).reloadOptions == nil)
    }
}
