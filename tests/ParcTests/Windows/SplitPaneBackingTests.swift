import AppKit
import Testing
@testable import Parc

private final class FlippedHost: NSView { override var isFlipped: Bool { true } }

private func alphas(_ image: CGImage) -> [UInt8] {
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<(image.width * image.height)).map { data[$0 * 4 + 3] }
}

private func alpha(_ image: CGImage, _ x: Int, _ yFromTop: Int) -> UInt8 { alphas(image)[yFromTop * image.width + x] }

@MainActor private func shadows(_ split: ParcSplitView) -> [CALayer] {
    (split.layer?.sublayers ?? []).filter { $0.name == "Split pane shadow" }
}

@MainActor private func color(_ layer: CALayer?) -> NSColor? {
    layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB)
}

@MainActor private struct SplitSetup {
    let host: NSView
    let split = ParcSplitView()
    let first = NSView(), second = NSView()

    init(width: CGFloat = 1230, height: CGFloat = 820, host: NSView? = nil) {
        self.host = host ?? NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        self.host.wantsLayer = true
        self.host.addSubview(split)
        split.constrain(to: self.host)
    }

    func lone(translucent: Bool) {
        split.configure(orientation: .horizontal, factors: [1])
        split.reconcileArrangedSubviews([first])
        host.layoutSubtreeIfNeeded()
        split.adjustSubviews()
        split.configureBacking(in: host, hasTranslucentPane: translucent)
    }

    func divided() {
        lone(translucent: true)
        split.configure(orientation: .horizontal, factors: [0.5, 0.5])
        split.reconcileArrangedSubviews([first, second])
        split.adjustSubviews()
        split.configureBacking(in: host, hasTranslucentPane: false)
    }
}

struct SplitPanePlaceholderTests {
    @MainActor @Test(arguments: [(NSAppearance.Name.aqua, 0.666), (NSAppearance.Name.darkAqua, 0.1)])
    func emptyContentIsWhiteAtTheAppearancesAlpha(name: NSAppearance.Name, alpha: CGFloat) throws {
        let pane = SplitPanePlaceholder(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        pane.appearance = NSAppearance(named: name)
        pane.updateLayer()
        let color = try #require(pane.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
        #expect(abs(color.alphaComponent - alpha) < 0.001)
        #expect(color.redComponent == 1 && color.greenComponent == 1 && color.blueComponent == 1)
    }

    @MainActor @Test func emptyContentHasNoPageTitleOrControl() {
        let pane = SplitPanePlaceholder(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(pane.subviews.isEmpty)
    }

    @MainActor @Test func emptyContentIsAnAccessibilityGroup() {
        let pane = SplitPanePlaceholder(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(pane.isAccessibilityElement() && pane.accessibilityRole() == .group)
    }
}

struct ContentShadowImageTests {
    typealias Shadow = ContentShadowImage

    @Test func thePageCardHasASixPointCorner() {
        #expect(PageCard.cornerRadius == 6)
    }

    @Test func theImageIsTenPointsOfOutsetAroundOneStretchablePoint() {
        #expect(Shadow.size == 51)
        let edge: CGFloat = 25 / 51, point: CGFloat = 1 / 51
        #expect(Shadow.stretchableCenter == CGRect(x: edge, y: edge, width: point, height: point))
    }

    @Test func theShadowReachesTenPointsBeyondTheCard() {
        #expect(Shadow.frame(around: CGRect(x: 220, y: 10, width: 1230, height: 820)) == CGRect(x: 210, y: 0, width: 1250, height: 840))
    }

    @Test func theImageIsDrawnAtBackingScale() throws {
        let image = try #require(Shadow.image(scale: 2))
        #expect(image.width == 102 && image.height == 102)
    }

    @Test func theCardsInteriorAndEdgesAreClear() throws {
        let image = try #require(Shadow.image(scale: 2))
        let middle = image.width / 2, card = 20
        #expect(alpha(image, middle, middle) == 0)
        #expect(alpha(image, middle, card + 4) == 0 && alpha(image, card + 4, middle) == 0)
    }

    @Test func theShadowFallsOnePointDown() throws {
        let image = try #require(Shadow.image(scale: 2))
        let middle = image.width / 2, card = 20, inner = image.height - 20
        let below = alpha(image, middle, inner + 1), above = alpha(image, middle, card - 2)
        #expect(below > above && above > 0)
    }

    @Test func theShadowIsAtMostAQuarterBlackAtTheEdge() throws {
        let image = try #require(Shadow.image(scale: 2))
        #expect(alpha(image, image.width / 2, image.height - 20 + 1) <= 64)
    }

    @Test func theBlurFadesOutInsideTheOutset() throws {
        let image = try #require(Shadow.image(scale: 2))
        #expect(alpha(image, 0, 0) == 0 && alpha(image, image.width / 2, image.height - 1) == 0)
    }

    @MainActor @Test func everyPixelInsideTheCardsContinuousCornerIsClear() throws {
        let scale: CGFloat = 8
        let fine = try #require(Shadow.image(scale: scale))
        let mask = CGContext(data: nil, width: fine.width, height: fine.height, bitsPerComponent: 8, bytesPerRow: fine.width,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        mask.scaleBy(x: scale, y: scale)
        mask.translateBy(x: Shadow.outset, y: Shadow.outset)
        let shape = CALayer()
        shape.bounds = CGRect(x: 0, y: 0, width: Shadow.size - 2 * Shadow.outset, height: Shadow.size - 2 * Shadow.outset)
        shape.backgroundColor = CGColor(gray: 1, alpha: 1)
        shape.cornerRadius = 6
        shape.cornerCurve = .continuous
        shape.render(in: mask)
        let covered = mask.data!.assumingMemoryBound(to: UInt8.self), pixels = alphas(fine)
        let shadowedInside = (0..<pixels.count).filter { covered[$0] == 255 && pixels[$0] != 0 }.count
        #expect(shadowedInside == 0)
    }
}

struct PageCardShadowViewTests {
    @MainActor private func placed() -> PageCardShadowView {
        let view = PageCardShadowView()
        view.place(around: NSRect(x: 220, y: 10, width: 1230, height: 820))
        return view
    }

    @MainActor @Test func itIsPlacedAroundThePageHost() {
        #expect(placed().frame == NSRect(x: 210, y: 0, width: 1250, height: 840))
    }

    @MainActor @Test func itNeverTakesAClick() {
        let view = placed()
        #expect(view.hitTest(NSPoint(x: 600, y: 400)) == nil && view.hitTest(NSPoint(x: 215, y: 5)) == nil)
    }

    @MainActor @Test func itIsNotInAccessibility() {
        let view = placed()
        #expect(!view.isAccessibilityElement() && (view.accessibilityChildren() ?? []).isEmpty)
    }

    @MainActor @Test func aResizeStretchesItWithoutRedrawing() {
        #expect(placed().layerContentsRedrawPolicy == .onSetNeedsDisplay)
    }

    @MainActor @Test func itsLayerShowsTheStretchableShadow() {
        let view = placed()
        view.updateLayer()
        #expect(view.layer?.contents != nil && view.layer?.contentsCenter == ContentShadowImage.stretchableCenter)
    }
}

struct SplitBackingTests {
    @MainActor @Test func aLoneEmptyContentShowsThroughAClearClippingHost() {
        let setup = SplitSetup()
        setup.lone(translucent: true)
        #expect(setup.host.layer?.masksToBounds == true && color(setup.host.layer)?.alphaComponent == 0)
    }

    @MainActor @Test func theHostClipsALonePane() {
        let setup = SplitSetup()
        setup.lone(translucent: true)
        #expect(setup.first.layer?.cornerRadius == 0 && setup.first.layer?.masksToBounds == false)
    }

    @MainActor @Test func aLonePanesSplitShadowWaitsHidden() {
        let setup = SplitSetup()
        setup.lone(translucent: true)
        #expect(shadows(setup.split).count == 1 && shadows(setup.split).allSatisfy(\.isHidden))
    }

    @MainActor @Test func aLonePageKeepsTheWhiteHost() {
        let setup = SplitSetup()
        setup.lone(translucent: true)
        setup.split.configureBacking(in: setup.host, hasTranslucentPane: false)
        #expect(color(setup.host.layer)?.alphaComponent == 1)
    }

    @MainActor @Test func aDividedSplitIsUnclippedSoEachCardsShadowShows() {
        let setup = SplitSetup()
        setup.divided()
        #expect(setup.host.layer?.masksToBounds == false)
    }

    @MainActor @Test func eachDividedPaneClipsItself() {
        let setup = SplitSetup()
        setup.divided()
        #expect([setup.first, setup.second].allSatisfy { $0.layer?.cornerRadius == 6 && $0.layer?.masksToBounds == true })
    }

    @MainActor @Test func eachDividedPaneHasAVisibleShadowBelowIt() {
        let setup = SplitSetup()
        setup.divided()
        let layers = shadows(setup.split)
        #expect(layers.count == 2 && layers.allSatisfy { !$0.isHidden && $0.zPosition < 0 && $0.contents != nil })
        for pane in [setup.first, setup.second] {
            #expect(layers.contains { $0.frame == ContentShadowImage.frame(around: pane.frame) }, "a shadow surrounds \(pane.frame)")
        }
    }

    @MainActor @Test func aDepartingPaneTakesItsShadowAndTheLoneOneHides() {
        let setup = SplitSetup()
        setup.divided()
        setup.split.reconcileArrangedSubviews([setup.second])
        setup.split.adjustSubviews()
        #expect(shadows(setup.split).count == 1 && shadows(setup.split).allSatisfy(\.isHidden))
    }

    @MainActor @Test func anEmptySplitKeepsNoShadow() {
        let setup = SplitSetup()
        setup.divided()
        setup.split.reconcileArrangedSubviews([])
        setup.split.adjustSubviews()
        #expect(shadows(setup.split).isEmpty)
    }

    @MainActor @Test func stackedPanesInAFlippedHostEachGetAShadowAroundTheirLayer() throws {
        let setup = SplitSetup(host: FlippedHost(frame: NSRect(x: 0, y: 0, width: 600, height: 800)))
        let top = NSView(), bottom = NSView()
        setup.split.configure(orientation: .vertical, factors: [0.3, 0.7])
        setup.split.reconcileArrangedSubviews([top, bottom])
        setup.split.configureBacking(in: setup.host, hasTranslucentPane: false)
        setup.host.layoutSubtreeIfNeeded()
        setup.split.adjustSubviews()
        #expect(top.frame.height < bottom.frame.height && top.frame.minY < bottom.frame.minY)
        let layers = shadows(setup.split)
        for pane in [top, bottom] {
            let paneLayer = try #require(pane.layer)
            #expect(layers.contains { $0.frame == ContentShadowImage.frame(around: paneLayer.frame) },
                    "a shadow surrounds the pane's layer at \(paneLayer.frame)")
        }
    }
}
