import AVFoundation
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let done = DispatchSemaphore(value: 0)
Task {
    let duration = try await asset.load(.duration)
    for track in try await asset.loadTracks(withMediaType: .video) {
        let size = try await track.load(.naturalSize)
        let rate = try await track.load(.nominalFrameRate)
        let formats = try await track.load(.formatDescriptions)
        let codec = formats.first.map { CMFormatDescriptionGetMediaSubType($0) }.map { String(format: "%c%c%c%c", ($0 >> 24) & 255, ($0 >> 16) & 255, ($0 >> 8) & 255, $0 & 255) } ?? "?"
        print("duration \(duration.seconds)s size \(size) fps \(rate) codec \(codec)")
    }
    done.signal()
}
done.wait()
