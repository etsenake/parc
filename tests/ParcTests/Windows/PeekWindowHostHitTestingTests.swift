import AppKit
import QuartzCore
import Testing
@testable import Parc

struct PeekWindowHostHitTestingTests {
    private final class Flipped: NSView { override var isFlipped: Bool { true } }

    private final class HostedPage: NSView {
        var scale: CGFloat = 1
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview, PeekWindowLayout.pageAcceptsHit(at: convert(point, from: superview), in: bounds, scale: scale) else { return nil }
            return super.hitTest(point)
        }
    }

    @MainActor private final class Tree {
        let t: CGFloat = 10
        let frame: CGRect
        let root: Flipped
        let page: HostedPage
        let pageContent: Flipped
        let grip: Flipped
        let host: PeekHitView
        let layout: PeekWindowLayout
        let cardContent: Flipped
        let close: Flipped
        let sidebar: Flipped

        init() {
            let window = PeekWindowHostSupport.window
            frame = PeekWindowHostSupport.page(thickness: t)
            let content = Flipped(frame: window)
            root = Flipped(frame: window)
            content.addSubview(root)
            page = HostedPage(frame: frame)
            pageContent = Flipped(frame: page.bounds)
            page.addSubview(pageContent)
            grip = Flipped(frame: CGRect(x: frame.maxX, y: frame.midY - 22, width: t, height: 44))
            let layer = PeekLayerView(frame: window)
            host = PeekHitView(frame: layer.bounds)
            layout = PeekWindowLayout(bounds: host.bounds, page: frame, stepsBack: true)
            host.hitLayout = layout
            let controls = layout.controls(closeWidth: PeekWindowLayout.controlSize)
            host.hitControls = controls
            let card = Flipped(frame: layout.card)
            cardContent = Flipped(frame: card.bounds)
            card.addSubview(cardContent)
            close = Flipped(frame: CGRect(origin: controls.origin, size: CGSize(width: 32, height: 32)))
            host.addSubview(card)
            host.addSubview(close)
            layer.addSubview(host)
            sidebar = Flipped(frame: CGRect(x: 5, y: 5, width: PeekWindowHostSupport.sidebarWidth, height: window.height - 10))
            root.addSubview(page)
            root.addSubview(grip)
            root.addSubview(layer)
            root.addSubview(sidebar)
            page.scale = layout.scale
        }

        func hit(_ x: CGFloat, _ y: CGFloat) -> NSView? { root.hitTest(CGPoint(x: x, y: y)) }
    }

    @MainActor @Test func theTopFrameReachesTheWindowSoItDrags() {
        let v = Tree()
        #expect(v.hit(v.frame.midX + v.layout.card.width / 2 + 60, 4) === v.root)
        #expect(v.root.mouseDownCanMoveWindow)
    }

    @MainActor @Test func theRevealedBandReachesTheWindowForTheFrameMenu() {
        let v = Tree()
        #expect(v.hit(v.frame.maxX - 3, v.frame.midY) === v.root)
    }

    @MainActor @Test func theRightFrameReachesTheWindow() {
        let v = Tree()
        #expect(v.hit(v.frame.maxX + 3, 4) === v.root)
    }

    @MainActor @Test func theFadedPageGoesToThePeekWhichClosesIt() {
        let v = Tree()
        #expect(v.hit(v.frame.minX + 30, v.frame.midY) === v.host)
    }

    @MainActor @Test func theCardsPageGetsItsOwnClicks() {
        let v = Tree()
        #expect(v.hit(v.layout.card.midX, v.frame.midY) === v.cardContent)
        #expect(v.hit(v.layout.card.midX, v.layout.card.minY + 2) === v.cardContent)
    }

    @MainActor @Test func closeGetsItsClick() {
        let v = Tree()
        #expect(v.hit(v.close.frame.midX, v.close.frame.midY) === v.close)
    }

    @MainActor @Test func theSplitGripKeepsWorking() {
        let v = Tree()
        #expect(v.hit(v.grip.frame.midX, v.grip.frame.midY) === v.grip)
    }

    enum ClickRegion: String, Sendable, CustomTestStringConvertible {
        case fadedPage = "faded page"
        case card
        case revealedBand = "revealed band"
        case frame
        case grip

        var testDescription: String { rawValue }
    }

    struct ClickCase: Sendable, CustomTestStringConvertible {
        let region: ClickRegion
        let claimedByPeek: Bool
        var testDescription: String { region.testDescription }

        static let all = [
            Self(region: .fadedPage, claimedByPeek: true),
            Self(region: .card, claimedByPeek: true),
            Self(region: .revealedBand, claimedByPeek: false),
            Self(region: .frame, claimedByPeek: false),
            Self(region: .grip, claimedByPeek: false),
        ]
    }

    @MainActor @Test(arguments: ClickCase.all)
    func theWindowsClickWatchClaimsThePeekRegions(_ sample: ClickCase) {
        let v = Tree()
        let point: CGPoint
        switch sample.region {
        case .fadedPage: point = CGPoint(x: v.frame.minX + 30, y: v.frame.midY)
        case .card: point = CGPoint(x: v.layout.card.midX, y: 14)
        case .revealedBand: point = CGPoint(x: v.frame.maxX - 3, y: v.frame.midY)
        case .frame: point = CGPoint(x: 100, y: 4)
        case .grip: point = v.grip.frame.origin
        }
        #expect(v.host.claims(point) == sample.claimedByPeek)
    }

    @MainActor @Test func theFloatingSidebarStaysAboveThePeek() {
        let v = Tree()
        #expect(v.hit(100, 300) === v.sidebar)
    }

    @MainActor @Test func withTheSidebarAwayItsAreaIsFrameAgain() {
        let v = Tree()
        v.sidebar.removeFromSuperview()
        #expect(v.hit(100, 300) === v.root)
        #expect(v.hit(v.frame.minX + 3, v.frame.midY) === v.root)
    }

    @MainActor @Test func withThePeekHiddenThePageTakesClicksAtItsEdgeAndItsOwn() {
        let v = Tree()
        v.sidebar.removeFromSuperview()
        v.host.isHidden = true
        v.page.scale = 1
        #expect(v.hit(v.frame.minX + 3, v.frame.midY) === v.pageContent)
        #expect(v.hit(v.frame.minX + 30, v.frame.midY) === v.pageContent)
    }
}
