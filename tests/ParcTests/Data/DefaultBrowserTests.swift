import AppKit
import Testing
@testable import Parc
@testable import ParcSettings

@MainActor
struct DefaultBrowserTests {
    private static let application = URL(fileURLWithPath: "/Applications/Parc.app")
    private static let another = URL(fileURLWithPath: "/Applications/Other/Parc.app")

    @MainActor private final class Harness {
        var handlers: [String: URL] = [:]
        var requests: [(URL, String, DefaultBrowserController.Completion)] = []
        var results: [String?] = []
        lazy var controller = DefaultBrowserController(
            applicationURL: DefaultBrowserTests.application, bundleIdentifier: "org.parc.Browser",
            lookup: { [unowned self] in handlers[$0.scheme ?? ""] },
            setter: { [unowned self] in requests.append(($0, $1, $2)) }, observeActivation: false)

        func request() -> Bool { controller.makeDefault { [unowned self] in results.append($0) } }
        func complete(_ index: Int, _ error: Error? = nil) { requests[index].2(error) }
    }

    private static func failure() -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: -50, userInfo: [NSLocalizedDescriptionKey: "Could not change HTTPS"])
    }

    @Test func readingStatusNeverChangesTheDefault() {
        let harness = Harness()
        #expect(harness.controller.canRequest)
        #expect(harness.requests.isEmpty)
    }

    @Test func anotherCopyWithTheSameNameIsNotTheOriginalApplication() {
        let harness = Harness()
        harness.handlers = ["http": Self.another, "https": Self.another]
        harness.controller.refresh()
        #expect(!harness.controller.state.isDefault)
    }

    @Test func partialOwnershipIsReportedTruthfully() {
        let harness = Harness()
        harness.handlers = ["http": Self.application, "https": Self.another]
        harness.controller.refresh()
        #expect(harness.controller.state.handlesHTTP)
        #expect(!harness.controller.state.isDefault)
    }

    @Test func anExplicitRequestAsksForHTTPWithTheOriginalBundleFirst() {
        let harness = Harness()
        #expect(harness.request())
        #expect(harness.requests.count == 1)
        #expect(harness.requests[0].0 == Self.application)
        #expect(harness.requests[0].1 == "http")
    }

    @Test func oneRequestOwnsConsentAndARepeatIssuesNoSecondPrompt() {
        let harness = Harness()
        _ = harness.request()
        #expect(harness.controller.state.isRequesting)
        #expect(!harness.controller.canRequest)
        #expect(!harness.request())
        #expect(harness.requests.count == 1)
    }

    @Test func httpsFollowsAGenuineHTTPCompletion() {
        let harness = Harness()
        _ = harness.request()
        harness.complete(0)
        #expect(harness.requests.count == 2)
        #expect(harness.requests[1].1 == "https")
        #expect(harness.requests[1].0 == Self.application)
    }

    @Test func aDuplicateFirstCallbackCannotAdvanceOrFinish() {
        let harness = Harness()
        _ = harness.request()
        harness.complete(0)
        harness.complete(0)
        #expect(harness.requests.count == 2)
        #expect(harness.results.isEmpty)
    }

    @Test func aFailurePreservesActualPartialOwnershipAndIsExposedOnce() {
        let harness = Harness()
        harness.handlers = ["http": Self.application]
        harness.controller.refresh()
        _ = harness.request()
        harness.complete(0)
        harness.complete(1, Self.failure())
        #expect(!harness.controller.state.isRequesting)
        #expect(harness.controller.state.handlesHTTP)
        #expect(!harness.controller.state.handlesHTTPS)
        #expect(harness.results == ["Could not change HTTPS"])
    }

    @Test func aPartialOutcomePermitsADeliberateRetry() {
        let harness = Harness()
        _ = harness.request()
        harness.complete(0)
        harness.complete(1, Self.failure())
        #expect(harness.controller.canRequest)
        #expect(harness.request())
        #expect(harness.requests.count == 3)
    }

    @Test func anOldCompletionCannotFinishANewerRequest() {
        let harness = Harness()
        _ = harness.request()
        harness.complete(0)
        harness.complete(1, Self.failure())
        _ = harness.request()
        harness.complete(1)
        #expect(harness.controller.state.isRequesting)
        #expect(harness.requests.count == 3)
        #expect(harness.results.count == 1)
    }

    @Test func cancellationStopsBeforeHTTPSWithoutAnErrorAlert() {
        let harness = Harness()
        _ = harness.request()
        harness.complete(0, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        #expect(harness.requests.count == 1)
        #expect(!harness.controller.state.isRequesting)
        #expect(harness.controller.state.failure == nil)
        #expect(harness.results == [nil])
    }

    @Test func successfulCallbacksAloneNeverEstablishOwnership() {
        let harness = Harness()
        _ = harness.request()
        harness.complete(0)
        harness.complete(1)
        #expect(!harness.controller.state.isDefault)
        #expect(harness.controller.state.failure != nil)
    }

    @Test func aReadOnlyRefreshRecognizesActualOwnership() {
        let harness = Harness()
        harness.handlers = ["http": Self.application, "https": Self.application]
        harness.controller.refresh()
        #expect(harness.controller.state.isDefault)
        #expect(harness.controller.state.failure == nil)
        #expect(!harness.controller.canRequest)
    }

    @Test func anAlreadyDefaultRequestPerformsNoWrites() {
        let harness = Harness()
        harness.handlers = ["http": Self.application, "https": Self.application]
        harness.controller.refresh()
        #expect(!harness.request())
        #expect(harness.requests.isEmpty)
    }

    @Test func changingDefaultsOutsideParcUpdatesAvailability() {
        let harness = Harness()
        harness.handlers = ["http": Self.application, "https": Self.application]
        harness.controller.refresh()
        harness.handlers["http"] = Self.another
        harness.controller.refresh()
        #expect(!harness.controller.state.isDefault)
        #expect(harness.controller.canRequest)
    }

    @Test func theFinalOutcomeRequeriesBothSchemes() {
        let harness = Harness()
        harness.handlers = ["http": Self.another, "https": Self.application]
        harness.controller.refresh()
        _ = harness.request()
        harness.handlers["http"] = Self.application
        harness.complete(0)
        harness.complete(1)
        #expect(harness.controller.state.isDefault)
        #expect(harness.results.last! == nil)
    }

    @Test func aDevelopmentExecutableIsNotRegisteredAsABrowser() {
        let unbundled = DefaultBrowserController(applicationURL: URL(fileURLWithPath: "/tmp/Parc"), bundleIdentifier: nil,
            lookup: { _ in Issue.record("an unbundled executable queried the defaults"); return nil },
            setter: { _, _, _ in Issue.record("an unbundled executable changed the defaults") }, observeActivation: false)
        #expect(!unbundled.isApplication)
        #expect(!unbundled.makeDefault())
    }

    @Test func anImmediateNativeCompletionKeepsOrderingAndFinalState() {
        var handlers: [String: URL] = [:]
        let controller = DefaultBrowserController(applicationURL: Self.application, bundleIdentifier: "org.parc.Browser",
            lookup: { handlers[$0.scheme ?? ""] },
            setter: { application, scheme, complete in handlers[scheme] = application; complete(nil) }, observeActivation: false)
        #expect(controller.makeDefault())
        #expect(controller.state.isDefault)
        #expect(!controller.state.isRequesting)
    }
}
