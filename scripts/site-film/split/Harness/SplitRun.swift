import AppKit
import AVFoundation
import VideoToolbox

@MainActor final class AlphaVideoWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let width: Int, height: Int, fps: Int32
    private var index: Int64 = 0

    init(path: String, width: Int, height: Int, fps: Int32 = 60, bitrate: Int = 70_000_000,
         quality: Double = Double(ProcessInfo.processInfo.environment["SPLIT_QUALITY"] ?? "0.9") ?? 0.9) throws {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        self.width = width; self.height = height; self.fps = fps
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate,
                                              AVVideoExpectedSourceFrameRateKey: Int(fps),
                                              AVVideoQualityKey: quality,
                                              AVVideoMaxKeyFrameIntervalKey: Int(ProcessInfo.processInfo.environment["SPLIT_KEYINT"] ?? "2") ?? 2,
                                              kVTCompressionPropertyKey_TargetQualityForAlpha as String: 1.0],
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
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        memset(base, 0, rowBytes * height)
        if let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
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
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        while done.wait(timeout: .now() + 0.01) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return (index, writer.status, writer.error)
    }
}

@MainActor enum SplitRun {
    static let stripTimes = [0.0, 1.20, 1.95, 2.40, 3.70, 4.85, 5.60, 6.1667, 6.70, 7.30, 7.9833, 9.40]

    static func run(out: String, stills: [Double]?) {
        let started = Date()
        let film = SplitFilm()
        Render.requireNoWindows("after building the split scene")
        let fps = SplitFilm.fps
        let total = Int((SplitFilm.duration * fps).rounded())
        let writer = stills == nil ? try! AlphaVideoWriter(path: out + "/split.mov", width: 2880, height: 1800) : nil
        var strip: [(Double, CGImage)] = []
        let stage = NSRect(x: 0, y: 0, width: 1440, height: 900)
        for frame in 0..<total {
            let t = Double(frame) / fps
            film.step(t)
            let wantsStill = stills?.contains { abs($0 - t) < 0.5 / fps } ?? false
            let inStrip = stripTimes.contains { abs($0 - t) < 0.5 / fps }
            guard writer != nil || wantsStill || inStrip else { continue }
            let bitmap = film.scene.render(stage, pixelsWide: 2880, pixelsHigh: 1800)
            guard let image = bitmap.cgImage else { continue }
            writer?.append(image)
            if wantsStill { Render.writePNG(bitmap, out + String(format: "/still-%.2f.png", t)) }
            if inStrip { strip.append((t, image)) }
            if frame % 60 == 0 { print(String(format: "frame %d t %.2f elapsed %.0fs", frame, t, Date().timeIntervalSince(started))) }
        }
        if let writer {
            let result = writer.finish()
            print("wrote", out + "/split.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        }
        writeStrip(strip, path: out + (stills == nil ? "/split-strip.png" : "/proof-strip.png"))
        let beats: [[String: Any]] = film.beats.sorted { $0.0 < $1.0 }.map { beat in
            ["t": (beat.0 * 1000).rounded() / 1000, "frame": Int((beat.0 * fps).rounded()), "beat": beat.1]
        }
        let json: [String: Any] = ["scene": "split view", "fps": Int(fps), "duration": SplitFilm.duration, "frames": total,
                                   "size": [2880, 1800], "points": [1440, 900], "window": [80, 18, 1280, 840],
                                   "beats": beats, "strip": stripTimes.map { ($0 * 1000).rounded() / 1000 }, "log": film.log]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: out + (stills == nil ? "/split-beats.json" : "/proof-beats.json")))
        print(film.log.joined(separator: "\n"))
        print(String(format: "done in %.0fs", Date().timeIntervalSince(started)))
    }

    static func writeStrip(_ frames: [(Double, CGImage)], path: String) {
        let columns = 4, cell = CGSize(width: 720, height: 450)
        let rows = (frames.count + columns - 1) / columns
        let width = Int(cell.width) * columns, height = Int(cell.height) * rows
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(gray: 0.82, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        for (index, frame) in frames.enumerated() {
            let x = CGFloat(index % columns) * cell.width, y = CGFloat(height) - CGFloat(index / columns + 1) * cell.height
            context.draw(frame.1, in: CGRect(x: x, y: y, width: cell.width, height: cell.height))
            let label = NSAttributedString(string: String(format: "%.2f s", frame.0), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.black])
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            label.draw(at: NSPoint(x: x + 10, y: y + 8))
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let image = context.makeImage() else { return }
        Render.writePNG(NSBitmapImageRep(cgImage: image), path)
    }
}
