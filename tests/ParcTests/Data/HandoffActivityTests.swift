import Foundation
import Testing
@testable import Parc

struct HandoffActivityTests {
    private static let page = URL(string: "https://example.com/a?b=c")!

    @Test func anHTTPSPageIsPublished() {
        #expect(HandoffActivity.publishable(Self.page) == Self.page)
    }

    @Test func anUpperCaseSchemeIsPublishedInLowerCase() {
        #expect(HandoffActivity.publishable(URL(string: "HTTP://example.com/a")!) == URL(string: "http://example.com/a"))
    }

    @Test(arguments: ["parc://note/1", "file:///tmp/a.html", "about:blank", "chrome://settings", "data:text/plain,a"])
    func aNonWebAddressIsNotPublished(address: String) {
        #expect(HandoffActivity.publishable(URL(string: address)!) == nil)
    }

    @Test func thePublishedActivityIsAHandoffWebPage() {
        let activity = HandoffActivity.browsing(Self.page)
        #expect(activity.activityType == NSUserActivityTypeBrowsingWeb)
        #expect(activity.webpageURL == Self.page)
        #expect(activity.isEligibleForHandoff)
    }

    @Test func aContinuedWebPageOpensItsAddress() {
        #expect(HandoffActivity.webpageURL(of: HandoffActivity.browsing(Self.page)) == Self.page)
    }

    @Test func anotherAppsActivityTypeIsRefused() {
        let other = NSUserActivity(activityType: "com.example.reading")
        other.webpageURL = Self.page
        #expect(HandoffActivity.webpageURL(of: other) == nil)
    }

    @Test func aWebActivityWithoutAPageOpensNothing() {
        #expect(HandoffActivity.webpageURL(of: NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)) == nil)
    }
}
