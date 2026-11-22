import AppKit
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcSidebar

struct NavigationLoadingTestsReloadOptions {
    @MainActor private static func reloadMenu(_ chosen: @escaping (ReloadOptionsMenu.Choice) -> Void) -> NSMenu {
        ReloadOptionsMenu.make(state: .forceReload, canReload: true, canForceReload: true, canClearCookies: false, choose: chosen)
    }

    @MainActor @Test func theReloadMenuItems() {
        let menu = Self.reloadMenu { _ in }
        #expect(menu.items.map(\.title) == ["Reload", "Refresh (Ignore Cache)", "", "Clear Cookies and Refresh"])
        #expect(menu.items[2].isSeparatorItem)
    }

    @MainActor @Test func theStoredDefaultIsChecked() {
        let menu = Self.reloadMenu { _ in }
        #expect(menu.items[0].state == .off)
        #expect(menu.items[1].state == .on)
    }

    @MainActor @Test func theMenuReflectsAvailability() {
        let menu = Self.reloadMenu { _ in }
        #expect(menu.items[3].isEnabled == false)
        #expect(menu.items[0].isEnabled)
    }

    @MainActor @Test func itemsRunTheirChoices() {
        var chosen: [ReloadOptionsMenu.Choice] = []
        let menu = Self.reloadMenu { chosen.append($0) }
        for index in [0, 1] {
            let item = menu.items[index]
            _ = (item.target as? NSObject)?.perform(item.action)
        }
        #expect(chosen == [.reload, .forceReload])
    }

    private static func withDefaults(_ body: (UserDefaults) -> Void) {
        let defaults = TestDefaults("parc.navigation-loading-tests.")!
        body(defaults)
    }

    @MainActor @Test func theDeveloperReloadDefaultIsReload() {
        Self.withDefaults { defaults in
            #expect(DeveloperReloadPreference.storedState(in: defaults) == .reload)
        }
    }

    @MainActor @Test func storingForceReloadWritesItsRawValue() {
        Self.withDefaults { defaults in
            DeveloperReloadPreference.store(.forceReload, in: defaults)
            #expect(defaults.string(forKey: DeveloperReloadPreference.key) == "forceReload")
        }
    }

    @MainActor @Test func theStoredDeveloperReloadDefaultReadsBack() {
        Self.withDefaults { defaults in
            DeveloperReloadPreference.store(.forceReload, in: defaults)
            #expect(DeveloperReloadPreference.storedState(in: defaults) == .forceReload)
        }
    }
}
