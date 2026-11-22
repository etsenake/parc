import AppKit
import Combine
import QuartzCore
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarResizeRegionTestsGeometryTests {
    private typealias R = SidebarResizeRegionTestsSupport.R
    private typealias Strip = SidebarResizeRegionTestsSupport.Strip

    @Test func aLockedStripStraddlesTheTrailingEdge() {
        #expect(R.frame(trailing: NSRect(x: 0, y: 0, width: 228, height: 700), in: NSRect(x: 0, y: 0, width: 1000, height: 700))
                == NSRect(x: 224, y: 11, width: 8, height: 678))
    }

    @Test func aFloatingStripFollowsTheContainerMaxX() {
        #expect(R.frame(trailing: NSRect(x: 5, y: 5, width: 228, height: 690), in: NSRect(x: 0, y: 0, width: 1000, height: 700))
                == NSRect(x: 229, y: 11, width: 8, height: 678))
    }

    @Test func verticalInsetsFollowTheContainerAndNeverGoNegative() {
        #expect(R.frame(trailing: NSRect(x: 0, y: 0, width: 300, height: 10), in: NSRect(x: 0, y: 40, width: 500, height: 10))
                == NSRect(x: 296, y: 51, width: 8, height: 0))
    }

    @Test func theStripIsLayerBackedAndUnclipped() {
        let s = Strip()
        #expect(s.region.wantsLayer)
        #expect(s.region.layer?.masksToBounds == false)
    }

    @Test func theIndicatorIsAHiddenSublayer() {
        let s = Strip()
        #expect(s.indicator.superlayer === s.region.layer)
        #expect(s.indicator.isHidden)
        #expect(s.indicator.opacity == 0.5)
    }

    @Test func theIndicatorIsThreePointsByHeightMinusEight() {
        #expect(Strip().indicator.bounds.size == CGSize(width: 3, height: 670))
    }

    @Test func theIndicatorIsCentredOnTheLeadingEdge() {
        let s = Strip()
        #expect(s.indicator.anchorPoint == CGPoint(x: 0.5, y: 0.5))
        #expect(s.indicator.position == CGPoint(x: 0, y: 339))
        #expect(s.indicator.frame.minX == -1.5)
        #expect(s.indicator.frame.minY == 4)
    }

    @Test func theRoundedPathFillsTheLine() {
        #expect(Strip().indicator.path?.boundingBox == CGRect(x: 0, y: 0, width: 3, height: 670))
    }

    @Test func theStripNeverDragsTheWindow() {
        #expect(!Strip().region.mouseDownCanMoveWindow)
    }

    @Test func trackingAreasAreReplacedOnEachUpdateWithTheRecoveredOptions() {
        let s = Strip()
        s.region.updateTrackingAreas()
        s.region.updateTrackingAreas()
        let area = s.region.trackingAreas.first
        #expect(s.region.trackingAreas.count == 1)
        #expect(area?.options.rawValue == 0x227)
        #expect(area?.owner === s.region)
    }

    @Test func thereAreTwoRecognizersWithoutADelegate() {
        let s = Strip()
        #expect(s.region.gestureRecognizers.count == 2)
        #expect(s.region.gestureRecognizers.allSatisfy { $0.delegate == nil })
    }

    @Test func theStripInstallsItsPanRecognizer() {
        let s = Strip()
        #expect(s.region.panGestureRecognizer.view === s.region)
    }

    @Test func theStripInstallsARecognizerForTwoClicks() {
        let s = Strip()
        #expect(s.region.doubleClickGestureRecognizer.numberOfClicksRequired == 2)
        #expect(s.region.doubleClickGestureRecognizer.view === s.region)
    }

    @Test func fillAndStrokeUseTheThemeColour() {
        let s = Strip()
        s.region.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        s.region.updateLayer()
        #expect(s.indicator.fillColor == s.region.color.cgColor)
        #expect(s.indicator.strokeColor == s.region.color.cgColor)
    }

    @Test func theIndicatorHeightFollowsRelayout() {
        let s = Strip()
        s.region.frame.size.height = 100
        s.root.layoutSubtreeIfNeeded()
        #expect(s.indicator.bounds.height == 92)
        #expect(s.indicator.position.y == 50)
    }

    @Test func anUnobstructedStripOwnsTheCursor() {
        let s = Strip()
        #expect(s.region.isUnobstructed(atWindowPoint: s.center))
    }

    @Test func thePageAreaDoesNotOwnTheCursor() {
        let s = Strip()
        #expect(!s.region.isUnobstructed(atWindowPoint: NSPoint(x: 600, y: 300)))
    }

    @Test func aViewAboveTheStripObstructsIt() {
        let s = Strip()
        s.root.addSubview(NSView(frame: NSRect(x: 200, y: 0, width: 60, height: 700)))
        #expect(!s.region.isUnobstructed(atWindowPoint: s.center))
    }
}
