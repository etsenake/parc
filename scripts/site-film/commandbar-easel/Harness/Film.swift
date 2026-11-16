import AppKit
import AVFoundation
import VideoToolbox
import CoreImage

@MainActor final class AlphaVideoWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let width: Int, height: Int, fps: Int32
    private var index: Int64 = 0

    init(path: String, width: Int, height: Int, fps: Int32 = 60, quality: Double = Double(ProcessInfo.processInfo.environment["QUALITY"] ?? "0.85") ?? 0.85) throws {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        self.width = width; self.height = height; self.fps = fps
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: 70_000_000,
            AVVideoQualityKey: quality,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoExpectedSourceFrameRateKey: Int(fps),
            AVVideoMaxKeyFrameIntervalKey: Int(ProcessInfo.processInfo.environment["GOP"] ?? "1") ?? 1,
            kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha,
            kVTCompressionPropertyKey_TargetQualityForAlpha as String: 1.0,
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "render", code: 1) }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage) {
        var made: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) }
        if made == nil { CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &made) }
        guard let buffer = made else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        adaptor.append(buffer, withPresentationTime: CMTime(value: index, timescale: fps))
        index += 1
    }

    func finish() -> (frames: Int64, status: AVAssetWriter.Status, error: Error?) {
        input.markAsFinished()
        var done = false
        writer.finishWriting { done = true }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return (index, writer.status, writer.error)
    }
}

struct Beat: Codable {
    let time: Double
    let frame: Int
    let beat: String
}

@MainActor enum Film {
    static let fps = 60.0

    static func ease(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    static func easeInOut(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return 0.5 - 0.5 * cos(Double.pi * x)
    }

    static func caDefault(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
        }
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if bezier(mid, 0.25, 0.25) < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, 0.1, 1)
    }

    static func progress(_ t: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (t - start) / (end - start)))
    }

    static func cgImage(_ rep: NSBitmapImageRep) -> CGImage { rep.cgImage! }

    static func writeStrip(_ frames: [(Double, CGImage)], path: String) {
        let columns = 4, thumbWidth = 720, thumbHeight = 450, label = 28
        let rows = (frames.count + columns - 1) / columns
        let width = columns * thumbWidth, height = rows * (thumbHeight + label)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(gray: 0.62, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        for (index, item) in frames.enumerated() {
            let column = index % columns, row = index / columns
            let x = column * thumbWidth, y = height - (row + 1) * (thumbHeight + label)
            context.interpolationQuality = .high
            context.draw(item.1, in: CGRect(x: x, y: y, width: thumbWidth, height: thumbHeight))
            let text = NSAttributedString(string: String(format: "%.2f s", item.0), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.black])
            text.draw(at: NSPoint(x: x + 10, y: y + thumbHeight + 4))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote", path)
    }

    static func writePNG(_ image: CGImage, _ path: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote", path)
    }

    static func writeBeats(_ beats: [Beat], path: String) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(beats).write(to: URL(fileURLWithPath: path))
        print("wrote", path)
    }

    static func blurredBackdrop(_ image: CGImage, crop: CGRect, radius: CGFloat) -> CGImage? {
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let height = CGFloat(image.height)
        let ciCrop = CGRect(x: crop.minX, y: height - crop.maxY, width: crop.width, height: crop.height)
        let source = CIImage(cgImage: image).clampedToExtent()
        let blurred = source.applyingGaussianBlur(sigma: radius)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: 0.02])
        return context.createCGImage(blurred, from: ciCrop)
    }
}
