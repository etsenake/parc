import AVFoundation
import CoreMedia
import CoreGraphics

let semaphore = DispatchSemaphore(value: 0)
_ = Task.detached {
    do { for path in CommandLine.arguments.dropFirst() {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let duration = try await asset.load(.duration)
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        let rate = try await track.load(.estimatedDataRate)
        let formats = try await track.load(.formatDescriptions)
        let codec = formats.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
        let fourcc = String(bytes: [24, 16, 8, 0].map { UInt8((codec >> $0) & 255) }, encoding: .ascii) ?? "?"
        let extensions = formats.first.flatMap { CMFormatDescriptionGetExtensions($0) as? [String: Any] } ?? [:]
        let alphaKeys = extensions.keys.filter { $0.lowercased().contains("alpha") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(value: 60, timescale: 60))
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }
        print(path.split(separator: "/").last!, "codec", fourcc, "size", size, "fps", fps, String(format: "duration %.2fs", duration.seconds),
              String(format: "%.1f Mbps", rate / 1_000_000), "alpha ext", alphaKeys,
              "corner alpha", alpha(10, 10), "centre alpha", alpha(width / 2, height / 2), "shadow alpha", alpha(width / 2, height - 12))
    }
    } catch { print("verify error", error) }
    semaphore.signal()
}
semaphore.wait()
