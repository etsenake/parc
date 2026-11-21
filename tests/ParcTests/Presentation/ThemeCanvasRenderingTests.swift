import AppKit
import Metal
import MetalKit
import Testing
import ParcCore
@testable import Parc

@MainActor
struct ThemeCanvasRenderingTests {
    private struct Readback {
        let mean: Double
        let alpha: Double
        let deviation: Double
    }

    private static let side = 400
    private static let pointSize = CGSize(width: 200, height: 200)

    private func textures() throws -> URL {
        try #require(Bundle.module.url(forResource: "ThemeTextures", withExtension: nil))
    }

    private func image(_ name: String) throws -> CGImage {
        let image = try #require(NSImage(contentsOf: try textures().appendingPathComponent("\(name).png")))
        return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private func render(noise: Double, active: Bool, texture: SpaceTheme.Texture = .grain) throws -> Readback {
        let renderer = try ThemeMetalRenderer(textureDirectory: try textures())
        var theme = SpaceTheme.singleColor(try #require(ThemeColor(red: 0.5, green: 0.5, blue: 0.5)))
        theme.intensity = 1
        theme.noise = noise
        theme.texture = texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Self.side, height: Self.side,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        let target = try #require(renderer.device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].storeAction = .store
        let queue = try #require(renderer.device.makeCommandQueue())
        let command = try #require(queue.makeCommandBuffer())
        #expect(renderer.encode(into: command, target: pass, theme: theme, isDark: false, isActive: active,
                                pointSize: Self.pointSize, sampleRect: SIMD4(0, 0, 1, 1)))
        command.commit()
        command.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        target.getBytes(&bytes, bytesPerRow: Self.side * 4, from: MTLRegionMake2D(0, 0, Self.side, Self.side), mipmapLevel: 0)
        let count = Self.side * Self.side
        var sum = 0.0, squares = 0.0, alpha = 0.0
        for pixel in 0..<count {
            let green = Double(bytes[pixel * 4 + 1])
            sum += green
            squares += green * green
            alpha += Double(bytes[pixel * 4 + 3])
        }
        let mean = sum / Double(count)
        return Readback(mean: mean, alpha: alpha / Double(count), deviation: (squares / Double(count) - mean * mean).squareRoot())
    }

    @Test func theBundledGrainIsA200PixelStraightAlphaImage() throws {
        let grain = try image("grain")
        #expect(grain.alphaInfo == .last)
        #expect(grain.width == 200 && grain.height == 200)
    }

    @Test func theBundledTweedIsOpaque() throws {
        let tweed = try image("tweed")
        #expect(tweed.alphaInfo != .last && tweed.alphaInfo != .first)
        #expect(tweed.width == 100)
    }

    @Test func theThemeCanvasOutputsSRGB() throws {
        let surface = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let canvas = try #require(surface.subviews.compactMap { $0 as? MTKView }.first)
        #expect(canvas.colorspace?.name == CGColorSpace.sRGB)
    }

    @Test func anOffscreenRenderProducesTheThemedSurface() throws {
        #expect(try render(noise: 0, active: true).mean > 100)
        #expect(try render(noise: 1, active: true).mean > 0)
    }

    @Test func fullGrainDarkensTheSurfaceOnlySlightly() throws {
        let plain = try render(noise: 0, active: true)
        let grained = try render(noise: 1, active: true)
        #expect(grained.mean / plain.mean > 0.95 && grained.mean / plain.mean < 1.03)
    }

    @Test func fullGrainStaysWithinThePremultipliedAmplitude() throws {
        let grained = try render(noise: 1, active: true)
        #expect(grained.deviation > 3 && grained.deviation < 13)
    }

    @Test func inactiveOwnershipQuartersTheGrainAmplitude() throws {
        let active = try render(noise: 1, active: true)
        let inactive = try render(noise: 1, active: false)
        #expect(inactive.deviation < active.deviation / 2.5)
    }

    @Test func opaqueTweedCompositesUnchangedAtItsMeasuredMaximum() throws {
        let tweed = try image("tweed")
        let space = try #require(tweed.colorSpace)
        let context = try #require(CGContext(data: nil, width: tweed.width, height: tweed.height, bitsPerComponent: 8,
                                             bytesPerRow: tweed.width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(tweed, in: CGRect(x: 0, y: 0, width: tweed.width, height: tweed.height))
        let texels = try #require(context.data).bindMemory(to: UInt8.self, capacity: tweed.width * tweed.height * 4)
        let texel = (0..<(tweed.width * tweed.height)).reduce(0.0) { $0 + Double(texels[$1 * 4 + 1]) }
            / Double(tweed.width * tweed.height) / 255
        let plain = try render(noise: 0, active: true)
        let woven = try render(noise: 1, active: true, texture: .tweed)
        let strength = 0.4, base = plain.mean / 255, baseAlpha = plain.alpha / 255
        let predicted = 255 * (strength * texel * (1 - baseAlpha + base) + base * (1 - strength))
        #expect(abs(woven.mean - predicted) < 2)
    }
}
