import Foundation
import Testing
@testable import ParcCore

struct EaselStoreHitTestingTests {
    @Test
    func ellipseClicksFollowTheShapeUntilItIsSelected() {
        let r = EaselRect(x: 100, y: 100, width: 100, height: 100)
        let circle = EaselItem(kind: .circle, frame: r)
        #expect(!EaselContentHitTest.contains(.init(x: 102, y: 102), item: circle, selected: false), "Unselected ellipse rejects transparent bounding-box corner")
        #expect(EaselContentHitTest.contains(.init(x: 150, y: 150), item: circle, selected: false), "Ellipse accepts filled center")
        #expect(EaselContentHitTest.contains(.init(x: 102, y: 102), item: circle, selected: true), "Selected shape preserves rectangular manipulation target")
    }

    @Test
    func marqueeSelectionFollowsTheEllipseOutline() {
        let r = EaselRect(x: 100, y: 100, width: 100, height: 100)
        let circle = EaselItem(kind: .circle, frame: r)
        #expect(!EaselContentHitTest.intersects(.init(x: 100, y: 100, width: 4, height: 4), item: circle, selected: false), "Marquee rejects ellipse empty corner")
        #expect(EaselContentHitTest.intersects(.init(x: 145, y: 145, width: 10, height: 10), item: circle, selected: false), "Marquee accepts filled ellipse intersection")
    }

    @Test
    func smallObjectsKeepABoundedScreenScaledHitTarget() {
        let tiny = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 4, height: 4))
        #expect(EaselContentHitTest.contains(.init(x: 90, y: 102), item: tiny, selected: false), "Small object has centered 30-point target")
        #expect(!EaselContentHitTest.contains(.init(x: 86, y: 102), item: tiny, selected: false), "Small object target is bounded")
        #expect(!EaselContentHitTest.contains(.init(x: 90, y: 102), item: tiny, selected: false, scale: 2), "Minimum target remains screen-scaled")
    }

    @Test
    func arrowClicksFollowTheStroke() {
        let r = EaselRect(x: 100, y: 100, width: 100, height: 100)
        let arrow = EaselItem(kind: .arrow, frame: r, points: [.init(x: 0, y: 100), .init(x: 100, y: 0)])
        #expect(!EaselContentHitTest.contains(.init(x: 110, y: 110), item: arrow, selected: false), "Arrow rejects empty bounding area")
        #expect(EaselContentHitTest.contains(.init(x: 150, y: 160), item: arrow, selected: false), "Arrow uses 30-point round stroke hit region")
    }

    @Test
    func aMarqueeCanCrossAnArrowBetweenItsEndpoints() {
        let r = EaselRect(x: 100, y: 100, width: 100, height: 100)
        let arrow = EaselItem(kind: .arrow, frame: r, points: [.init(x: 0, y: 100), .init(x: 100, y: 0)])
        #expect(!EaselContentHitTest.intersects(.init(x: 105, y: 105, width: 15, height: 15), item: arrow, selected: false), "Arrow marquee rejects empty bounds")
        #expect(EaselContentHitTest.intersects(.init(x: 145, y: 145, width: 10, height: 10), item: arrow, selected: false), "Arrow marquee detects segment crossing without contained endpoint")
    }

    @Test
    func aMarqueeUsesStoredSamplesForAnUnselectedDoodle() {
        let r = EaselRect(x: 100, y: 100, width: 100, height: 100)
        let stroke = EaselItem(kind: .freehand, frame: r, points: [.init(x: 0, y: 0), .init(x: 100, y: 100)])
        #expect(!EaselContentHitTest.intersects(.init(x: 145, y: 145, width: 10, height: 10), item: stroke, selected: false), "Original freehand marquee is stored-sample based")
        #expect(EaselContentHitTest.intersects(.init(x: 95, y: 95, width: 10, height: 10), item: stroke, selected: false), "Freehand marquee accepts contained original sample")
        #expect(EaselContentHitTest.intersects(.init(x: 145, y: 145, width: 10, height: 10), item: stroke, selected: true), "Selected stroke retains group rectangle selection")
    }
}
