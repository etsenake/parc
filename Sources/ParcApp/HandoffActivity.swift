import Foundation

enum HandoffActivity {
    static func publishable(_ url: URL) -> URL? {
        guard let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else { return nil }
        guard scheme != scheme.lowercased() else { return url }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.scheme = scheme.lowercased()
        return parts?.url
    }

    static func browsing(_ url: URL) -> NSUserActivity {
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        activity.isEligibleForHandoff = true
        return activity
    }

    static func webpageURL(of activity: NSUserActivity) -> URL? {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb else { return nil }
        return activity.webpageURL.flatMap(publishable)
    }
}
