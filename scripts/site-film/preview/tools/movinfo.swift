import AVFoundation
import CoreMedia
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let semaphore = DispatchSemaphore(value: 0)
Task {
    let duration = try await asset.load(.duration)
    let track = try await asset.loadTracks(withMediaType: .video)[0]
    let (size, rate, fps, formats) = try await track.load(.naturalSize, .estimatedDataRate, .nominalFrameRate, .formatDescriptions)
    let frames = try await track.load(.timeRange)
    for format in formats {
        let subtype = CMFormatDescriptionGetMediaSubType(format)
        let code = String(bytes: [UInt8(subtype >> 24 & 255), UInt8(subtype >> 16 & 255), UInt8(subtype >> 8 & 255), UInt8(subtype & 255)], encoding: .ascii) ?? "?"
        let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        let alpha = extensions.keys.filter { $0.lowercased().contains("alpha") || $0.lowercased().contains("depth") }
        print("codec", code, "alpha-related extensions", alpha.map { "\($0)=\(extensions[$0]!)" })
    }
    print("size", size, "fps", fps, "Mbps", rate / 1_000_000, "duration", duration.seconds, "range", frames.duration.seconds)
    semaphore.signal()
}
semaphore.wait()
