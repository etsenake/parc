import CoreGraphics
import Testing
@testable import Parc

struct PageCaptureEdgeGuardTests {
    private static let host = CGRect(x: 0, y: 0, width: 1200, height: 800)

    @Test(arguments: [
        CGRect(x: 10, y: 10, width: 1180, height: 780),
        CGRect(x: 3, y: 3, width: 1194, height: 794),
        PageCaptureEdgeGuardTests.host,
    ])
    func thePageReachesEveryNearbyWindowEdge(_ source: CGRect) {
        #expect(PageCaptureEdgeReach.guardFrame(source: source, host: Self.host) == Self.host)
    }

    @Test(arguments: [
        (CGRect(x: 260, y: 10, width: 930, height: 780), CGRect(x: 260, y: 0, width: 940, height: 800)),
        (CGRect(x: 10, y: 50, width: 1180, height: 740), CGRect(x: 0, y: 50, width: 1200, height: 750)),
        (CGRect(x: 10, y: 10, width: 585, height: 780), CGRect(x: 0, y: 0, width: 595, height: 800)),
        (CGRect(x: 150, y: 80, width: 900, height: 640), CGRect(x: 150, y: 80, width: 900, height: 640)),
    ])
    func distantEdgesStayOutsideCapture(_ source: CGRect, _ expected: CGRect) {
        #expect(PageCaptureEdgeReach.guardFrame(source: source, host: Self.host) == expected)
    }

    @Test(arguments: [CGRect.zero, CGRect(x: 2000, y: 0, width: 10, height: 10)])
    func aPageWithNoAreaInTheWindowHasNoGuard(_ source: CGRect) {
        #expect(PageCaptureEdgeReach.guardFrame(source: source, host: Self.host) == .zero)
    }
}
