import AVFoundation
import AppKit
import VideoToolbox

@MainActor final class AlphaMovieWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let width: Int, height: Int, fps: Int32
    private var index: Int64 = 0

    init(path: String, width: Int, height: Int, fps: Int32 = 60, quality: Double = 0.97) throws {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        self.width = width; self.height = height; self.fps = fps
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let compression: [String: Any] = [
            AVVideoQualityKey: quality,
            AVVideoExpectedSourceFrameRateKey: Int(fps),
            AVVideoMaxKeyFrameIntervalKey: Int(fps),
            kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha as String,
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

    func append(_ draw: (CGContext) -> Void) {
        var made: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) }
        if made == nil { CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &made) }
        guard let buffer = made else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            draw(context)
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
