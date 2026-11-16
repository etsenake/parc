import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum Images {
    public static func load(_ path: String) -> CIImage {
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
        let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        return CIImage(cgImage: cg)
    }

    public static func write(_ cg: CGImage, to url: URL, jpeg: Bool = false) {
        let type = jpeg ? UTType.jpeg.identifier : UTType.png.identifier
        let d = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
        CGImageDestinationAddImage(d, cg, jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary : nil)
        CGImageDestinationFinalize(d)
    }
}

public final class VideoSource {
    public let url: URL
    public let duration: Double
    public let size: CGSize
    public let frameRate: Double
    let asset: AVURLAsset
    let track: AVAssetTrack
    var reader: AVAssetReader?
    var output: AVAssetReaderTrackOutput?
    var frames: [(Double, CIImage)] = []
    var exhausted = false
    public var straightAlpha: Bool?

    public init(_ url: URL) throws {
        self.url = url
        asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var tracks: [AVAssetTrack] = []
        nonisolated(unsafe) var dur = CMTime.zero
        nonisolated(unsafe) var natural = CGSize.zero
        nonisolated(unsafe) var fr: Float = 60
        let a = asset
        Task {
            tracks = (try? await a.loadTracks(withMediaType: .video)) ?? []
            dur = (try? await a.load(.duration)) ?? .zero
            if let t = tracks.first {
                natural = (try? await t.load(.naturalSize)) ?? .zero
                fr = (try? await t.load(.nominalFrameRate)) ?? 60
            }
            sem.signal()
        }
        sem.wait()
        guard let t = tracks.first else { throw NSError(domain: "VideoSource", code: 1, userInfo: [NSLocalizedDescriptionKey: "no video track in \(url.path)"]) }
        track = t
        duration = dur.seconds
        size = natural
        frameRate = Double(fr)
    }

    func restart(at time: Double) {
        reader?.cancelReading()
        frames.removeAll()
        exhausted = false
        let r = try! AVAssetReader(asset: asset)
        let start = max(0, time - 0.25)
        r.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: .positiveInfinity)
        let o = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        o.alwaysCopiesSampleData = false
        r.add(o)
        r.startReading()
        reader = r
        output = o
    }

    func pull() -> Bool {
        guard let o = output, let sb = o.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(sb) else {
            exhausted = true
            return false
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
        var img = CIImage(cvPixelBuffer: pb)
        if straightAlpha == nil {
            let mode = CVBufferCopyAttachment(pb, "AlphaChannelMode" as CFString, nil) as? String
            straightAlpha = mode == "StraightAlpha"
        }
        if straightAlpha == true { img = img.premultiplyingAlpha() }
        frames.append((pts, img))
        if frames.count > 12 { frames.removeFirst(frames.count - 12) }
        return true
    }

    public func image(at time: Double) -> CIImage {
        let step = 1 / max(frameRate, 1)
        let t = min(max(time, 0), max(duration - step * 0.5, 0))
        if reader == nil || (frames.first.map { t < $0.0 - 1e-4 } ?? false) || (frames.last.map { t - $0.0 > 1.0 } ?? false) {
            restart(at: t)
        }
        while !exhausted && (frames.last.map { $0.0 + step <= t + 1e-4 } ?? true) {
            if !pull() { break }
        }
        if frames.isEmpty {
            restart(at: max(0, t - 1))
            while pull() {}
        }
        let pick = frames.last { $0.0 <= t + 1e-4 } ?? frames.first!
        return pick.1
    }
}

public extension Layer {
    static func video(_ name: String, source: VideoSource, size: CGSize, at position: Vec3 = .zero, space: LayerSpace = .world, startOffset: Double = 0, speed: Double = 1) -> Layer {
        let map = Track<Double>(startOffset).keyed(10_000, startOffset + 10_000 * speed, .linear)
        return video(name, source: source, size: size, at: position, space: space, timeMap: map)
    }

    static func video(_ name: String, source: VideoSource, size: CGSize, at position: Vec3 = .zero, space: LayerSpace = .world, timeMap: Track<Double>) -> Layer {
        Layer(name, space: space, size: size, at: position) { t in
            source.image(at: timeMap.value(at: t))
        }
    }
}

public final class VideoWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let width: Int, height: Int, fps: Int
    let colorSpace: CGColorSpace
    public let url: URL

    public init(url: URL, width: Int, height: Int, fps: Int, bitrate: Int, network: Bool, codec: AVVideoCodecType = .h264) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: codec == .hevcWithAlpha ? .mov : .mp4)
        writer.shouldOptimizeForNetworkUse = network
        self.width = width; self.height = height; self.fps = fps
        let color: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
        ]
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps * 2
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
            compression[AVVideoAllowFrameReorderingKey] = true
        }
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: color,
            AVVideoCompressionPropertiesKey: compression
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        writer.add(input)
        let atts: [CFString: Any] = [
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_709_2,
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2
        ]
        colorSpace = CVImageBufferCreateColorSpaceFromAttachments(atts as CFDictionary)?.takeRetainedValue() ?? CGColorSpace(name: CGColorSpace.itur_709)!
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "VideoWriter", code: 1) }
        writer.startSession(atSourceTime: .zero)
    }

    public func append(_ image: CIImage, frame: Int, context: CIContext) {
        while !input.isReadyForMoreMediaData { usleep(1000) }
        var pbOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pbOut)
        let pb = pbOut!
        CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pb, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        context.render(image, to: pb, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: colorSpace)
        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    }

    public func finish() {
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        if writer.status != .completed { FileHandle.standardError.write("writer \(url.lastPathComponent): \(String(describing: writer.error))\n".data(using: .utf8)!) }
        let dir = url.deletingLastPathComponent()
        let stem = url.lastPathComponent + ".sb-"
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix(stem) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }
}
