import AVFoundation
import CoreImage
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let done = DispatchSemaphore(value: 0)
Task {
    let track = try await asset.loadTracks(withMediaType: .video)[0]
    let rate = try await track.load(.estimatedDataRate)
    let formats = try await track.load(.formatDescriptions)
    let ext = CMFormatDescriptionGetExtensions(formats[0]) as? [String: Any] ?? [:]
    print("estimated data rate \(String(format: "%.1f", rate / 1_000_000)) Mbps")
    print("alpha extension:", ext["ContainsAlphaChannel"] ?? "none", "alpha mode:", ext[kCVImageBufferAlphaChannelModeKey as String] ?? "none")
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output); reader.startReading()
    var index = 0
    while let sample = output.copyNextSampleBuffer() {
        if index == 90, let buffer = CMSampleBufferGetImageBuffer(sample) {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self), row = CVPixelBufferGetBytesPerRow(buffer)
            for (name, x, y) in [("corner", 5, 5), ("shadow below window", 1440, 1745), ("sidebar", 300, 900), ("card", 1500, 900)] {
                let p = base + y * row + x * 4
                print("\(name) BGRA:", p[0], p[1], p[2], p[3])
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        index += 1
    }
    print("frames decoded", index)
    done.signal()
}
done.wait()
