import AppKit
import Testing
@testable import Parc

struct NavigationLoadingTestsHost {
    @MainActor @Test func theLoadingPillIsOneTwentyEightByFour() {
        #expect(PageLoadingIndicator.size == NSSize(width: 128, height: 4))
    }

    @MainActor @Test func thePillIsCentredInTheBand() {
        #expect(PageLoadingIndicator.frame(paneMinX: 0, paneWidth: 1000, bandHeight: 10) == NSRect(x: 436, y: 3, width: 128, height: 4))
    }

    @MainActor @Test func thePillIsCentredOverTheSecondPane() {
        #expect(PageLoadingIndicator.frame(paneMinX: 500, paneWidth: 500, bandHeight: 10).midX == 750)
    }

    @MainActor @Test func aNarrowPaneClipsThePill() {
        #expect(PageLoadingIndicator.frame(paneMinX: 0, paneWidth: 100, bandHeight: 10).width == 100)
    }

    @MainActor @Test func theHostSpansTheTopInset() {
        #expect(PageLoadingIndicatorHost.frame(pageHost: NSRect(x: 228, y: 10, width: 1232, height: 811)) == NSRect(x: 228, y: 0, width: 1232, height: 10))
    }

    @MainActor @Test func thereIsNoBandInPageFullScreen() {
        #expect(PageLoadingIndicatorHost.frame(pageHost: NSRect(x: 0, y: 0, width: 1470, height: 831)).height == 0)
    }

    @MainActor @Test func aStackedSplitShowsTheFirstPaneOnly() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(PageLoadingIndicatorHost.eligible([a, b, c], stacked: true) == [a])
    }

    @MainActor @Test func sideBySidePanesShowEveryPane() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(PageLoadingIndicatorHost.eligible([a, b, c], stacked: false) == [a, b, c])
    }

    @MainActor @Test func noPanesShowNothing() {
        #expect(PageLoadingIndicatorHost.eligible([], stacked: true).isEmpty)
    }

    @MainActor private static func host(_ panes: [PageLoadingIndicatorHost.Pane]) -> PageLoadingIndicatorHost {
        _ = NSApplication.shared
        let host = PageLoadingIndicatorHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 10))
        host.update(panes)
        return host
    }

    @MainActor @Test func theHostKeepsOneIndicatorPerEligiblePane() {
        let a = UUID(), b = UUID()
        let host = Self.host([.init(id: a, minX: 0, width: 500, loading: true), .init(id: b, minX: 500, width: 500, loading: false)])
        #expect(host.indicators.count == 2)
        #expect(!host.isHidden)
    }

    @MainActor @Test func eachIndicatorFollowsItsOwnPane() {
        let a = UUID(), b = UUID()
        let host = Self.host([.init(id: a, minX: 0, width: 500, loading: true), .init(id: b, minX: 500, width: 500, loading: false)])
        #expect(host.indicators[a]?.isLoading == true)
        #expect(host.indicators[b]?.isLoading == false)
    }

    @MainActor @Test func theSecondPanesPill() {
        let a = UUID(), b = UUID()
        let host = Self.host([.init(id: a, minX: 0, width: 500, loading: true), .init(id: b, minX: 500, width: 500, loading: false)])
        #expect(host.indicators[b]?.frame == NSRect(x: 686, y: 3, width: 128, height: 4))
    }

    @MainActor @Test func aRemovedPaneLosesItsIndicator() {
        let a = UUID(), b = UUID()
        let host = Self.host([.init(id: a, minX: 0, width: 500, loading: true), .init(id: b, minX: 500, width: 500, loading: false)])
        host.update([.init(id: b, minX: 0, width: 1000, loading: true)])
        #expect(host.indicators.count == 1)
        #expect(host.indicators[a] == nil)
        #expect(host.indicators[b]?.isLoading == true)
    }

    @MainActor @Test func aZeroBandHidesAndStops() {
        let b = UUID()
        let host = Self.host([.init(id: b, minX: 0, width: 1000, loading: true)])
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 0)
        host.update([.init(id: b, minX: 0, width: 1000, loading: true)])
        #expect(host.isHidden)
        #expect(host.indicators[b]?.isLoading == false)
    }

    @MainActor @Test func resetRemovesEveryIndicator() {
        let host = Self.host([.init(id: UUID(), minX: 0, width: 1000, loading: true)])
        host.reset()
        #expect(host.indicators.isEmpty)
    }
}
