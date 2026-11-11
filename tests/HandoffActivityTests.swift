import Foundation

@main
struct HandoffActivityTests {
    static var count = 0
    static func check(_ value: Bool, _ message: String) throws {
        count += 1; if !value { throw NSError(domain: message, code: 1) }
    }

    static func main() throws {
        let page = URL(string: "https://example.com/a?b=c")!
        try check(HandoffActivity.publishable(page) == page, "an https page is published")
        try check(HandoffActivity.publishable(URL(string: "HTTP://example.com/a")!) == URL(string: "http://example.com/a"),
                  "an upper-case scheme is published in lower case, as webpageURL requires")
        for other in ["parc://note/1", "file:///tmp/a.html", "about:blank", "chrome://settings", "data:text/plain,a"] {
            try check(HandoffActivity.publishable(URL(string: other)!) == nil, "\(other) is not published")
        }
        let activity = HandoffActivity.browsing(page)
        try check(activity.activityType == NSUserActivityTypeBrowsingWeb && activity.webpageURL == page
                  && activity.isEligibleForHandoff, "the published activity is a Handoff web page")
        try check(HandoffActivity.webpageURL(of: activity) == page, "a continued web page opens its address")
        let other = NSUserActivity(activityType: "com.example.reading")
        other.webpageURL = page
        try check(HandoffActivity.webpageURL(of: other) == nil, "another app's activity type is refused")
        let empty = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        try check(HandoffActivity.webpageURL(of: empty) == nil, "a web activity without a page opens nothing")
        print("HandoffActivity: \(count) checks passed")
    }
}
