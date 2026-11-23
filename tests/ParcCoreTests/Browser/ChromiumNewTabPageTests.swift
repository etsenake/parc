import Testing
@testable import ParcCore

struct ChromiumNewTabPageTests {
    @Test(arguments: ["parc://newtab/", "chrome://newtab", "chrome://new-tab-page/", "parc://new-tab-page-third-party/", " CHROME://NewTab/ "])
    func chromiumsNewTabAddressesMatch(_ address: String) {
        #expect(ChromiumNewTabPage.matches(address))
    }

    @Test(arguments: ["parc://settings/", "https://newtab.example/", "chrome://history/", "about:blank", "", "newtab"])
    func otherAddressesDoNotMatch(_ address: String) {
        #expect(!ChromiumNewTabPage.matches(address))
    }

    @Test func aMissingAddressDoesNotMatch() {
        #expect(!ChromiumNewTabPage.matches(nil))
    }
}
