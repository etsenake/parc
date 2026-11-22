import AppKit
import MetalKit
@testable import Parc
@testable import ParcKit

@MainActor enum ThemeReadback {
    static func image(of surface: ThemeRendererView, scale: CGFloat, settle: TimeInterval = 0.25, quiet: Bool = false) -> CGImage? {
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        guard let canvas = surface.subviews.compactMap({ $0 as? MTKView }).first else {
            print("theme: no Metal canvas"); return nil
        }
        guard !canvas.isHidden else { print("theme: canvas hidden"); return nil }
        canvas.framebufferOnly = false
        canvas.autoResizeDrawable = false
        canvas.layer?.contentsScale = scale
        canvas.drawableSize = CGSize(width: surface.bounds.width * scale, height: surface.bounds.height * scale)
        if !quiet { print("theme drawable size", canvas.drawableSize) }
        guard let drawable = canvas.currentDrawable else { print("theme: no drawable"); return nil }
        canvas.draw()
        canvas.needsDisplay = false
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        let texture = drawable.texture
        let width = texture.width, height = texture.height, row = width * 4, length = row * height
        guard let device = canvas.device, let queue = device.makeCommandQueue(),
              let buffer = device.makeBuffer(length: length, options: .storageModeShared),
              let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: row, destinationBytesPerImage: length)
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        let data = Data(bytes: buffer.contents(), count: length)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let space = canvas.colorspace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
