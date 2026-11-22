import AppKit
import MetalKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct FloatingSidebarSwipeCommitTests {
    @MainActor final class Canvas {
        static let width = 128, height = 96
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        let surface: ThemeRendererView
        let canvas: MTKView
        let device: MTLDevice
        let queue: MTLCommandQueue
        private var committed: MTLCommandBuffer?

        init?(floating: Bool) {
            guard let textures = Bundle.module.url(forResource: "ThemeTextures", withExtension: nil) else { return nil }
            surface = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
                makeRenderer: { try ThemeMetalRenderer(textureDirectory: textures) },
                makeCanvas: { ThemeMetalCanvas(frame: $0, device: $1) })
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = surface
            surface.layout()
            if floating { surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius }
            guard let canvas = surface.subviews.compactMap({ $0 as? MTKView }).first, let device = canvas.device,
                  let queue = device.makeCommandQueue() else { return nil }
            (self.canvas, self.device, self.queue) = (canvas, device, queue)
            canvas.framebufferOnly = false
            canvas.autoResizeDrawable = false
            canvas.drawableSize = CGSize(width: Self.width, height: Self.height)
            surface.onCanvasCommit = { [weak self] in guard let self else { return }; self.committed = $0 }
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        func render(_ theme: SpaceTheme, _ transition: ThemePagingTransition? = nil) -> [Int] {
            surface.theme = theme
            surface.pagingTransition = transition
            canvas.releaseDrawables()
            committed = nil
            guard let drawable = canvas.currentDrawable else { return [] }
            canvas.draw(canvas.bounds)
            canvas.needsDisplay = false
            guard let committed else { return [] }
            committed.waitUntilCompleted()
            let texture = drawable.texture, length = texture.width * texture.height * 4
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared),
                  let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else { return [] }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                      to: buffer, destinationOffset: 0, destinationBytesPerRow: texture.width * 4, destinationBytesPerImage: length)
            blit.endEncoding(); command.commit(); command.waitUntilCompleted()
            let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: length)
            return (0..<length).map { Int(bytes[$0]) }
        }
    }

    private static let p: CGFloat = 0.37
    private static var current: SpaceTheme {
        var theme = SpaceTheme(primaryColor: ThemeColor(red: 0.85, green: 0.25, blue: 0.3)!, colorCount: 2, intensity: 0.3)
        theme.noise = 0.6
        return theme
    }
    private static var incoming: SpaceTheme {
        var theme = SpaceTheme(primaryColor: ThemeColor(red: 0.15, green: 0.35, blue: 0.9)!, colorCount: 1, intensity: 1)
        theme.noise = 0.25; theme.texture = .tweed; theme.appearance = .dark
        return theme
    }
    private static func across(_ from: SpaceTheme, _ to: SpaceTheme, _ progress: CGFloat) -> ThemePagingTransition {
        ThemePagingTransition(from: from, theme: to, progress: progress)
    }
    private static func largest(_ a: [Int], _ b: [Int]) -> Int {
        a.count == b.count && !a.isEmpty ? zip(a, b).map { abs($0 - $1) }.max()! : .max
    }
    private static func over(_ source: [Int], opacity: Double, _ backdrop: [Int]) -> [Int] {
        (0..<source.count).map { index in
            let alpha = Double(source[index - index % 4 + 3]) * opacity / 255
            return Int((Double(source[index]) * opacity + Double(backdrop[index]) * (1 - alpha)).rounded())
        }
    }
    private func canvas(_ floating: Bool) throws -> Canvas {
        let canvas = try #require(Canvas(floating: floating))
        _ = canvas.render(Self.current)
        return canvas
    }

    @Test(arguments: [true, false])
    func aMidSwipeCommitLeavesThePictureUnchanged(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        let swipe = Self.across(Self.current, Self.incoming, Self.p)
        #expect(Self.largest(canvas.render(Self.current, swipe), canvas.render(Self.incoming, swipe)) <= 1)
    }

    @Test(arguments: [true, false])
    func pastOnePageWithNeitherPageTheSurfacesOwnThePictureIsTheSame(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        let swipe = Self.across(Self.current, Self.incoming, Self.p)
        #expect(Self.largest(canvas.render(SpaceTheme(), swipe), canvas.render(Self.current, swipe)) <= 1)
    }

    @Test(arguments: [true, false])
    func theSwipesEndsAreEachThemeAlone(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        let alone = canvas.render(Self.current), other = canvas.render(Self.incoming)
        #expect(Self.largest(canvas.render(Self.current, Self.across(Self.current, Self.incoming, 0)), alone) <= 1)
        #expect(Self.largest(canvas.render(Self.incoming, Self.across(Self.current, Self.incoming, 1)), other) <= 1)
    }

    @Test(arguments: [true, false])
    func theSurfaceMixesBothThemesStraightLayersRatherThanCrossfadingThePictures(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        var plainCurrent = Self.current, plainIncoming = Self.incoming
        plainCurrent.noise = 0; plainIncoming.noise = 0
        let a = canvas.render(plainCurrent), b = canvas.render(plainIncoming)
        let mixed = canvas.render(plainCurrent, Self.across(plainCurrent, plainIncoming, Self.p))
        let p = Double(Self.p)
        let expected = (0..<a.count).map { index -> Int in
            let base = index - index % 4
            let alphaA = Double(a[base + 3]) / 255, alphaB = Double(b[base + 3]) / 255
            let alpha = alphaA * (1 - p) + alphaB * p
            if index % 4 == 3 { return Int((alpha * 255).rounded()) }
            let straightA = alphaA > 0 ? Double(a[index]) / alphaA : 0, straightB = alphaB > 0 ? Double(b[index]) / alphaB : 0
            return Int(((straightA * (1 - p) + straightB * p) * alpha).rounded())
        }
        let crossfade = (0..<a.count).map { Int((Double(a[$0]) * (1 - p) + Double(b[$0]) * p).rounded()) }
        #expect(Self.largest(mixed, expected) <= 2)
        #expect(Self.largest(mixed, crossfade) >= 4)
    }

    @Test(arguments: [true, false])
    func aSwipesEndInAnUncolouredSpaceClearsTheCanvas(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        let uncoloured = canvas.render(Self.current, Self.across(Self.current, SpaceTheme(), 1))
        #expect(!uncoloured.isEmpty && uncoloured.allSatisfy { $0 == 0 })
    }

    @Test(arguments: [true, false])
    func aSwipeFromAnUncolouredSpaceEndsOnTheIncomingGradientAsItRests(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        let alone = canvas.render(Self.current)
        #expect(Self.largest(canvas.render(SpaceTheme(), Self.across(SpaceTheme(), Self.current, 1)), alone) <= 1)
    }

    @Test(arguments: [true, false])
    func aMidSwipeCommitWithAnUncolouredSpaceLeavesThePictureUnchanged(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        let fromUncoloured = Self.across(SpaceTheme(), Self.current, Self.p), toUncoloured = Self.across(Self.current, SpaceTheme(), 1 - Self.p)
        let leftBefore = canvas.render(SpaceTheme(), fromUncoloured), leftAfter = canvas.render(Self.current, fromUncoloured)
        let rightBefore = canvas.render(Self.current, toUncoloured), rightAfter = canvas.render(SpaceTheme(), toUncoloured)
        #expect(Self.largest(leftBefore, leftAfter) <= 1)
        #expect(Self.largest(rightBefore, rightAfter) <= 1)
    }

    @Test(arguments: [true, false])
    func anUncolouredSpaceFadesTheThemeTheSameFromEitherSide(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        let left = canvas.render(SpaceTheme(), Self.across(SpaceTheme(), Self.current, Self.p))
        let right = canvas.render(Self.current, Self.across(Self.current, SpaceTheme(), 1 - Self.p))
        #expect(Self.largest(left, right) <= 1)
    }

    @Test(arguments: [true, false])
    func towardsAnUncolouredSpaceTheThemeFadesAsAWhole(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        var plain = Self.current
        plain.noise = 0
        let a = canvas.render(plain)
        let fading = canvas.render(plain, Self.across(plain, SpaceTheme(), Self.p))
        #expect(Self.largest(fading, a.map { Int((Double($0) * (1 - Double(Self.p))).rounded()) }) <= 1)
    }

    @Test(arguments: [true, false])
    func aSecondTranslucentCanvasStackedOverTheFirstWouldJumpAtTheCommit(_ floating: Bool) throws {
        let canvas = try canvas(floating)
        let alone = canvas.render(Self.current), other = canvas.render(Self.incoming)
        let swipe = Self.across(Self.current, Self.incoming, Self.p)
        let before = canvas.render(Self.current, swipe), after = canvas.render(Self.incoming, swipe)
        let backdrop = (0..<alone.count).map { $0 % 4 == 3 ? 255 : 200 }
        let p = Double(Self.p)
        let stackedBefore = Self.over(other, opacity: p, Self.over(alone, opacity: 1, backdrop))
        let stackedAfter = Self.over(alone, opacity: 1 - p, Self.over(other, opacity: 1, backdrop))
        #expect(Self.largest(Self.over(before, opacity: 1, backdrop), Self.over(after, opacity: 1, backdrop)) <= 1)
        #expect(Self.largest(stackedBefore, stackedAfter) > 8)
    }
}
