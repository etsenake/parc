import AppKit

@main @MainActor
struct DefaultBrowserTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        let application = URL(fileURLWithPath: "/Applications/Parc.app")
        let another = URL(fileURLWithPath: "/Applications/Other/Parc.app")
        var handlers: [String: URL] = [:]
        var requests: [(URL, String, DefaultBrowserController.Completion)] = []
        let controller = DefaultBrowserController(applicationURL: application, bundleIdentifier: "org.parc.Browser",
            lookup: { handlers[$0.scheme ?? ""] }, setter: { requests.append(($0, $1, $2)) }, observeActivation: false)
        check(controller.canRequest && requests.isEmpty, "Reading status never changes the OS default")
        handlers = ["http": another, "https": another]; controller.refresh()
        check(!controller.state.isDefault, "Another copy with the same display name is not the original application")
        handlers["http"] = application; controller.refresh()
        check(controller.state.handlesHTTP && !controller.state.isDefault, "Partial ownership is truthful")
        var results: [String?] = []
        check(controller.makeDefault { results.append($0) }, "Explicit request is admitted")
        check(requests.count == 1 && requests[0].0 == application && requests[0].1 == "http", "HTTP receives original bundle URL first")
        check(controller.state.isRequesting && !controller.canRequest, "One application request owns consent")
        check(!controller.makeDefault() && requests.count == 1, "Repeated action does not issue another prompt")
        requests[0].2(nil)
        check(requests.count == 2 && requests[1].1 == "https" && requests[1].0 == application, "HTTPS follows genuine HTTP completion")
        requests[0].2(nil)
        check(requests.count == 2 && results.isEmpty, "Duplicate first callback cannot advance or finish HTTPS")
        let failure = NSError(domain: NSOSStatusErrorDomain, code: -50, userInfo: [NSLocalizedDescriptionKey: "Could not change HTTPS"])
        requests[1].2(failure)
        check(!controller.state.isRequesting && controller.state.handlesHTTP && !controller.state.handlesHTTPS, "Failure preserves actual partial ownership")
        check(results.count == 1 && results[0] == "Could not change HTTPS", "Real failure is exposed once")
        check(controller.canRequest, "Partial outcome permits a deliberate retry")
        check(controller.makeDefault { results.append($0) }, "Retry begins a fresh request")
        requests[1].2(nil)
        check(controller.state.isRequesting && requests.count == 3 && results.count == 1, "Old completion cannot finish a newer request")
        requests[2].2(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        check(requests.count == 3 && !controller.state.isRequesting && controller.state.failure == nil, "Cancellation stops before HTTPS without an error alert")
        check(results.count == 2 && results[1] == nil, "Cancellation completion is delivered once")
        controller.makeDefault { results.append($0) }
        requests[3].2(nil)
        requests[4].2(nil)
        check(!controller.state.isDefault && controller.state.failure != nil, "Successful callbacks alone never establish actual ownership")
        handlers["https"] = application; controller.refresh()
        check(controller.state.isDefault && controller.state.failure == nil && !controller.canRequest, "Read-only refresh recognizes actual ownership")
        check(!controller.makeDefault() && requests.count == 5, "Already-default action performs no writes")
        handlers["http"] = another; controller.refresh()
        check(!controller.state.isDefault && controller.canRequest, "Changing defaults outside Parc updates availability")
        controller.makeDefault { results.append($0) }
        handlers["http"] = application
        requests[5].2(nil); requests[6].2(nil)
        check(controller.state.isDefault && results.last! == nil, "Final outcome re-queries both schemes")
        let unbundled = DefaultBrowserController(applicationURL: URL(fileURLWithPath: "/tmp/Parc"), bundleIdentifier: nil,
            lookup: { _ in preconditionFailure("Unbundled executable should not query defaults") },
            setter: { _, _, _ in preconditionFailure("Unbundled executable should not change defaults") }, observeActivation: false)
        check(!unbundled.isApplication && !unbundled.makeDefault(), "Development command-line executable is not registered as a browser")
        var synchronousHandlers: [String: URL] = [:]
        let synchronous = DefaultBrowserController(applicationURL: application, bundleIdentifier: "org.parc.Browser",
            lookup: { synchronousHandlers[$0.scheme ?? ""] },
            setter: { app, scheme, complete in synchronousHandlers[scheme] = app; complete(nil) }, observeActivation: false)
        check(synchronous.makeDefault() && synchronous.state.isDefault && !synchronous.state.isRequesting, "Immediate native completion preserves ordering and final state")
        print("\(checks) default-browser ownership assertions passed; no system defaults changed")
    }
}
