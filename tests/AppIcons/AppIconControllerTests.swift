import AppKit
import ImageIO

/// Production catalog/controller with only temporary files and an injected
/// image consumer. Never launches a browser or changes Finder/the user's Dock.
@main @MainActor struct AppIconControllerTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String, line: Int = #line) throws {
        assertions += 1
        if try !condition() { throw NSError(domain: "Line \(line): \(message)", code: assertions) }
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let packaged = root.appendingPathComponent("packaged", isDirectory: true)
        let expected = ["Original", "Candy", "Neon", "FlutedGlass", "Schoolbook", "Colorful", "Hologram", "EarlyBirds", "Canary", "Dev"]
        let sourceController = AppIconController(resources: source)
        try expect(sourceController.availabilityError == nil, "Source-only PNG previews remain supported")
        try expect(sourceController.variants.map(\.id) == expected, "Every approved offline choice keeps its reference/Parc order")
        try expect(sourceController.selectedID == "Original", "A new controller never uses the optional Dev mascot as default")

        let preference = root.appendingPathComponent("session/app-icon.json")
        var applied: [NSImage] = []
        sourceController.configure(preferenceURL: preference) { applied.append($0); return nil }
        try expect(applied.isEmpty, "No saved choice leaves the packaged Original identity alone")
        for variant in sourceController.variants {
            sourceController.select(variant.id)
            try expect(sourceController.selectedID == variant.id && applied.last === variant.image,
                       "\(variant.id) selects immediately without account, referral or build gates")
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: preference)) as! [String: Any]
            try expect(saved["icon"] as? String == variant.id, "\(variant.id) saves the actual available choice")
            let restored = AppIconController(resources: source)
            var restoredImage: NSImage?
            restored.configure(preferenceURL: preference) { restoredImage = $0; return nil }
            try expect(restored.selectedID == variant.id && restoredImage === restored.variants.first(where: { $0.id == variant.id })?.image,
                       "\(variant.id) restores without a discovery prerequisite")
        }
        let savedData = try Data(contentsOf: preference)
        let applyCount = applied.count
        sourceController.select("../../Unapproved")
        try expect(applied.count == applyCount && sourceController.selectedID == "Dev", "Unknown choices cannot reach the applier")
        try expect(try Data(contentsOf: preference) == savedData, "Unknown choices cannot replace the preference")

        // PNG previews are deliberately unreadable: a packaged image must use
        // the actual ICNS representations instead of resampling the preview.
        for id in expected {
            try Data("invalid preview".utf8).write(to: packaged.appendingPathComponent("AppIcons/\(id).png"))
        }
        let nativeController = AppIconController(resources: packaged)
        try expect(nativeController.availabilityError == nil && nativeController.variants.count == 10,
                   "Packaged native icons do not depend on PNG preview decoding")
        let pixelSizes = Set([16, 32, 64, 128, 256, 512, 1024])
        for variant in nativeController.variants {
            let actual = Set(variant.image.representations.map(\.pixelsWide))
            try expect(actual == pixelSizes, "\(variant.id) preserves all native pixel sizes: \(actual)")
            // Compare native compositing, not iconutil's PNG encodings: its
            // legacy 32px export unpremultiplies edge RGB differently even
            // when the ICNS representations render to identical pixels.
            let url = packaged.appendingPathComponent("AppIcons/\(variant.id).icns")
            let decoder = CGImageSourceCreateWithURL(url as CFURL, nil)!
            var rendered: [Int: Data] = [:]
            for index in 0..<CGImageSourceGetCount(decoder) {
                let image = CGImageSourceCreateImageAtIndex(decoder, index, nil)!
                let context = CGContext(data: nil, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                        CGBitmapInfo.byteOrder32Big.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let pixels = Data(bytes: context.data!, count: context.bytesPerRow * image.height)
                if let earlier = rendered[image.width] {
                    try expect(pixels == earlier,
                               "\(variant.id) renders identical native pixels at \(image.width)px regardless of logical scale")
                }
                rendered[image.width] = pixels
            }
        }
        var nativeApplied: NSImage?
        nativeController.configure(preferenceURL: root.appendingPathComponent("native/app-icon.json")) { nativeApplied = $0; return nil }
        nativeController.select("Hologram")
        try expect(nativeApplied === nativeController.variants.first(where: { $0.id == "Hologram" })?.image,
                   "The live identity consumer receives the same native multi-size image")

        let nativeOriginal = packaged.appendingPathComponent("AppIcons/Original.icns")
        let previewOriginal = packaged.appendingPathComponent("AppIcons/Original.png")
        try FileManager.default.removeItem(at: previewOriginal)
        try FileManager.default.copyItem(at: source.appendingPathComponent("AppIcons/Original.png"), to: previewOriginal)
        try Data("invalid native icon".utf8).write(to: nativeOriginal)
        let corrupt = AppIconController(resources: packaged)
        try expect(corrupt.availabilityError != nil && corrupt.variants.isEmpty,
                   "Corrupt existing ICNS fails truthfully instead of falling back to a valid PNG")
        var corruptApplyCount = 0
        let corruptPreference = root.appendingPathComponent("corrupt/app-icon.json")
        corrupt.configure(preferenceURL: corruptPreference) { _ in corruptApplyCount += 1; return nil }
        corrupt.select("Original")
        try expect(corruptApplyCount == 0 && !FileManager.default.fileExists(atPath: corruptPreference.path),
                   "Unavailable artwork cannot mutate the preference or live identity")
        print("AppIconControllerTests: \(assertions) assertions passed")
    }
}
