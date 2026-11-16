import AVFoundation
import AppKit
let semaphore = DispatchSemaphore(value: 0)
Task {
    for path in CommandLine.arguments.dropFirst() {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let track = try! await asset.loadTracks(withMediaType: .video).first!
        let formats = try! await track.load(.formatDescriptions)
        let rate = try! await track.load(.nominalFrameRate)
        let bits = try! await track.load(.estimatedDataRate)
        let size = try! await track.load(.naturalSize)
        let duration = try! await asset.load(.duration)
        for format in formats {
            let codec = CMFormatDescriptionGetMediaSubType(format)
            let fourcc = String(bytes: [24, 16, 8, 0].map { UInt8((codec >> $0) & 255) }, encoding: .ascii) ?? "?"
            let alpha = CMFormatDescriptionGetExtension(format, extensionKey: "ContainsAlphaChannel" as CFString)
            print(path.split(separator: "/").last!, fourcc, "alpha", alpha ?? "nil" as CFString, size, rate, "fps", String(format: "%.1f Mbps", bits / 1e6), String(format: "%.2f s", duration.seconds))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let image = try! await generator.image(at: CMTime(value: 200, timescale: 60)).image
        let rep = NSBitmapImageRep(cgImage: image)
        let corner = rep.colorAt(x: 2, y: 2)!.alphaComponent, center = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)!.alphaComponent
        if let data = rep.representation(using: .png, properties: [:]) { try! data.write(to: URL(fileURLWithPath: path + ".frame200.png")) }
        print("  decoded frame 200 alpha corner", corner, "center", center, "alphaInfo", image.alphaInfo.rawValue)
    }
    semaphore.signal()
}
semaphore.wait()
