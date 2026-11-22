import AppKit
import Testing
@testable import Parc
@testable import ParcSidebar

struct SidebarPresentationFrameTests {
    private let root = NSRect(x: 0, y: 0, width: 1470, height: 831)
    private func frame(_ placement: SidebarPresentationFrame) -> NSRect { placement.rect(width: 228, in: root) }

    @Test(arguments: [
        (SidebarPresentationFrame.locked, NSRect(x: 0, y: 0, width: 228, height: 831)),
        (.floating, NSRect(x: 5, y: 5, width: 228, height: 821)),
        (.hiding, NSRect(x: -238, y: 0, width: 228, height: 831)),
        (.hidden, NSRect(x: -238, y: 5, width: 228, height: 821)),
        (.revealing, NSRect(x: -228, y: 0, width: 228, height: 831)),
    ])
    func eachPlacementHasItsFrame(placement: SidebarPresentationFrame, expected: NSRect) {
        #expect(frame(placement) == expected)
    }

    @Test(arguments: [SidebarPresentationFrame.hiding, .hidden, .revealing])
    func everyHiddenFrameLiesWhollyOutsideTheRoot(placement: SidebarPresentationFrame) {
        #expect(frame(placement).maxX <= root.minX)
    }

    struct Placement: Sendable, CustomTestStringConvertible {
        let presentation: SidebarPresentation
        let inMotion: Bool
        let surface: Bool
        let anchored: Bool
        let expected: SidebarPresentationFrame
        let testDescription: String
    }

    @Test(arguments: [
        Placement(presentation: .locked, inMotion: false, surface: false, anchored: false, expected: .locked, testDescription: "settled locked"),
        Placement(presentation: .floating, inMotion: false, surface: false, anchored: false, expected: .floating, testDescription: "settled floating"),
        Placement(presentation: .hidden, inMotion: false, surface: false, anchored: false, expected: .hidden, testDescription: "a settled hide"),
        Placement(presentation: .locked, inMotion: true, surface: false, anchored: false, expected: .locked, testDescription: "an anchored hide's preparation"),
        Placement(presentation: .hidden, inMotion: true, surface: false, anchored: false, expected: .hiding, testDescription: "inside an anchored hide's group"),
        Placement(presentation: .hidden, inMotion: true, surface: false, anchored: true, expected: .revealing, testDescription: "an anchored reveal's preparation"),
        Placement(presentation: .locked, inMotion: true, surface: false, anchored: true, expected: .locked, testDescription: "inside an anchored reveal's group"),
        Placement(presentation: .hidden, inMotion: true, surface: true, anchored: false, expected: .hidden, testDescription: "a floating reveal's preparation"),
        Placement(presentation: .floating, inMotion: true, surface: true, anchored: false, expected: .floating, testDescription: "inside a floating reveal's group"),
        Placement(presentation: .locked, inMotion: true, surface: true, anchored: false, expected: .locked, testDescription: "inside a floating to locked group"),
    ])
    func placementFollowsPresentationAndMotion(_ c: Placement) {
        #expect(SidebarPresentationFrame(c.presentation, inMotion: c.inMotion, floatingSurface: c.surface, revealsAnchored: c.anchored) == c.expected)
    }

    struct Transition: Sendable, CustomTestStringConvertible {
        let from: SidebarPresentation
        let to: SidebarPresentation
        let style: SidebarMotionController.Style
        let surface: Bool
        let docks: Bool
        let anchored: Bool
        let flushes: Bool
        var testDescription: String { "\(from) to \(to)" }
    }

    @Test(arguments: [
        Transition(from: .locked, to: .hidden, style: .anchored, surface: false, docks: false, anchored: false, flushes: false),
        Transition(from: .hidden, to: .locked, style: .anchored, surface: false, docks: false, anchored: true, flushes: true),
        Transition(from: .hidden, to: .floating, style: .floating, surface: true, docks: false, anchored: false, flushes: true),
        Transition(from: .floating, to: .hidden, style: .floating, surface: true, docks: false, anchored: false, flushes: false),
        Transition(from: .floating, to: .locked, style: .anchored, surface: true, docks: true, anchored: false, flushes: false),
        Transition(from: .locked, to: .floating, style: .anchored, surface: true, docks: false, anchored: false, flushes: false),
    ])
    func transitionChoosesItsStyleAndSurface(_ c: Transition) {
        let transition = SidebarTransition(from: c.from, to: c.to)
        #expect(transition.style == c.style)
        #expect(transition.keepsFloatingSurface == c.surface)
        #expect(transition.docksFloatingSurface == c.docks)
        #expect(transition.revealsAnchored == c.anchored)
        #expect(transition.flushesPreparation == c.flushes)
    }

    @Test func onlyASettledHideIsNotPresented() {
        #expect(!SidebarPresentation.hidden.presents(inMotion: false))
        #expect(SidebarPresentation.hidden.presents(inMotion: true))
        for presentation in [SidebarPresentation.locked, .floating] {
            #expect(presentation.presents(inMotion: false) && presentation.presents(inMotion: true))
        }
    }
}
