import AppKit
import AVFoundation
import VideoToolbox

@MainActor final class VideoWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let width: Int, height: Int, fps: Int32, alpha: Bool
    private var index: Int64 = 0

    init(path: String, width: Int, height: Int, fps: Int32 = 60, alpha: Bool = false, bitRate: Int = 70_000_000) throws {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        self.width = width; self.height = height; self.fps = fps; self.alpha = alpha
        writer = try AVAssetWriter(outputURL: url, fileType: alpha ? .mov : .mp4)
        let alphaSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.97,
                                              AVVideoExpectedSourceFrameRateKey: Int(fps),
                                              kVTCompressionPropertyKey_TargetQualityForAlpha as String: 1.0,
                                              kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha as String],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]]
        let plainSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoExpectedSourceFrameRateKey: Int(fps)],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: alpha ? alphaSettings : plainSettings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "render", code: 1) }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage, background: CGColor) {
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &made)
        guard let buffer = made else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            if !alpha { context.setFillColor(background); context.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
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
