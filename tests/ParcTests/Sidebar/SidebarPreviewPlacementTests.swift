import AppKit
import Testing
@testable import ParcSidebar

@MainActor
struct SidebarPreviewPlacementTests {
    private let right = SidebarPreviewPlacement(row: NSRect(x: 8, y: 300, width: 212, height: 32), location: .right)
    private let tile = SidebarPreviewPlacement(row: NSRect(x: 172, y: 60, width: 47, height: 47), location: .diagonal)

    private func solved(_ placement: SidebarPreviewPlacement, height: CGFloat, host: NSSize = NSSize(width: 1000, height: 700)) -> NSRect {
        placement.frame(width: placement.width(hostWidth: host.width), height: height, hostHeight: host.height)
    }

    @Test func aRightCardLeadsFromTheRowCentredAndIs288Wide() {
        #expect(solved(right, height: 200) == NSRect(x: 224, y: 216, width: 288, height: 200))
    }

    @Test(arguments: [(530.0, 288.0), (500.0, 258.0), (400.0, 240.0), (100.0, 240.0)] as [(CGFloat, CGFloat)])
    func aRightCardNarrowsToStayInsideTheWindowButNeverBelow240(hostWidth: CGFloat, width: CGFloat) {
        #expect(right.width(hostWidth: hostWidth) == width)
    }

    @Test func theRightAnchorIsTheRowsTrailingMidpoint() {
        #expect(right.anchor == NSPoint(x: 220, y: 316))
    }

    @Test func theRequiredTopInsetBeatsCentring() {
        let nearTop = SidebarPreviewPlacement(row: NSRect(x: 8, y: 20, width: 212, height: 32), location: .right)
        #expect(solved(nearTop, height: 200).minY == 18)
    }

    @Test func theRequiredBottomInsetBeatsCentring() {
        let nearBottom = SidebarPreviewPlacement(row: NSRect(x: 8, y: 660, width: 212, height: 32), location: .right)
        #expect(solved(nearBottom, height: 200).maxY == 682)
    }

    @Test func contentHeightYieldsOnlyToBothWindowInsets() {
        #expect(solved(right, height: 384, host: NSSize(width: 1000, height: 300)) == NSRect(x: 224, y: 18, width: 288, height: 264))
    }

    @Test func theCardHasA384PointSoftMaximum() {
        #expect(solved(right, height: 500, host: NSSize(width: 1000, height: 900)).height == 384)
    }

    @Test func aCardNeverFlipsToTheLeadingSide() {
        let far = SidebarPreviewPlacement(row: NSRect(x: 900, y: 300, width: 80, height: 32), location: .right)
        #expect(solved(far, height: 200) == NSRect(x: 984, y: 216, width: 240, height: 200))
    }

    @Test func aDiagonalCardHangsFromTheTilesTrailingBottomCorner() {
        #expect(solved(tile, height: 200) == NSRect(x: 215, y: 103, width: 288, height: 200))
        #expect(tile.width(hostWidth: 500) == 267)
        #expect(tile.anchor == NSPoint(x: 219, y: 107))
    }

    private func aim(_ last: (CGFloat, CGFloat), _ point: (CGFloat, CGFloat), _ location: SidebarPreviewLocation) -> Bool {
        SidebarPreviewAim.keepsCurrent(from: NSPoint(x: last.0, y: last.1), to: NSPoint(x: point.0, y: point.1), location: location)
    }

    @Test func aLevelRightwardMoveKeepsTheCard() {
        #expect(aim((100, 300), (110, 300), .right))
        #expect(aim((470, 300), (490, 300), .right))
    }

    @Test func aRightwardMoveKeepsTheCardUpToSlopeThree() {
        #expect(aim((100, 300), (110, 330), .right) && aim((100, 300), (110, 270), .right))
        #expect(!aim((100, 300), (110, 331), .right))
    }

    @Test func verticalAndLeftwardMovesRetarget() {
        #expect(!aim((110, 300), (110, 280), .right))
        #expect(!aim((120, 300), (110, 300), .right))
    }

    @Test func aimReaches478Points() {
        #expect(!aim((470, 300), (480, 310), .right) && aim((460, 300), (477, 310), .right))
        #expect(!aim((470, 300), (478, 290), .diagonal))
        #expect(SidebarPreviewAim.reach == 478)
    }

    @Test func aDiagonalCardKeepsRightAndDownMovesOnly() {
        #expect(aim((100, 300), (110, 280), .diagonal) && aim((100, 300), (100, 280), .diagonal))
        #expect(!aim((100, 300), (110, 301), .diagonal))
        #expect(!aim((110, 300), (100, 290), .diagonal))
    }

    @Test func hoverAndKeyboardFocusAddUp() {
        let opacity = SidebarPreviewHighlight.opacity
        #expect(opacity(false, false) == 0 && opacity(true, false) == 0.08 && opacity(false, true) == 0.08 && opacity(true, true) == 0.16)
    }

    final class FlippedHost: NSView { override var isFlipped: Bool { true } }

    @MainActor final class SessionStage {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let row = NSView(frame: NSRect(x: 8, y: 300, width: 212, height: 32))
        init() {
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.addSubview(row)
            host.layoutSubtreeIfNeeded()
        }
        func keeps(_ x: CGFloat, _ y: CGFloat) -> Bool {
            SidebarPreviewMotion.keepsSessionTarget(windowPoint: host.convert(NSPoint(x: x, y: y), to: nil), anchor: row)
        }
    }

    @Test(arguments: [(20.0, 310.0), (100.0, 316.0)] as [(CGFloat, CGFloat)])
    func thePointerOnTheLiveRowBodyKeepsTheSessionTarget(x: CGFloat, y: CGFloat) {
        #expect(SessionStage().keeps(x, y))
    }

    @Test(arguments: [(240.0, 316.0), (20.0, 280.0)] as [(CGFloat, CGFloat)])
    func leavingTheRowIsNotAStay(x: CGFloat, y: CGFloat) {
        #expect(!SessionStage().keeps(x, y))
    }

    @Test func rowActionButtonsDoNotKeepTheSession() {
        let s = SessionStage()
        s.row.addSubview(NSButton(frame: NSRect(x: 180, y: 4, width: 24, height: 24)))
        s.row.layoutSubtreeIfNeeded()
        #expect(!s.keeps(192, 316))
    }

    @Test func aDetachedAnchorCannotKeepTheSession() {
        let s = SessionStage()
        let point = s.host.convert(NSPoint(x: 20, y: 310), to: nil)
        s.row.removeFromSuperview()
        #expect(!SidebarPreviewMotion.keepsSessionTarget(windowPoint: point, anchor: s.row))
    }
}
