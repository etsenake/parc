import AVFoundation
let a = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let sem = DispatchSemaphore(value: 0)
Task {
    let t = try await a.loadTracks(withMediaType: .video)[0]
    let ds = try await t.load(.formatDescriptions)
    let d = ds[0]
    let sub = CMFormatDescriptionGetMediaSubType(d)
    let size = try await t.load(.naturalSize)
    let fps = try await t.load(.nominalFrameRate)
    let rate = try await t.load(.estimatedDataRate)
    let dur = try await a.load(.duration)
    print(sub == kCMVideoCodecType_HEVCWithAlpha ? "codec muxa (HEVC with alpha)" : "codec \(sub)", size, "fps", fps, "Mbps", rate / 1e6, "s", CMTimeGetSeconds(dur))
    if let ext = CMFormatDescriptionGetExtensions(d) as? [String: Any] { for k in ext.keys.sorted() where !k.contains("SampleDescriptionExtensionAtoms") { print(" ", k, ext[k]!) } }
    sem.signal()
}
sem.wait()
