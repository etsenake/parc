import AppKit

@main
struct MembershipCardTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-Card-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let url = root.appendingPathComponent("card.json")
        let store = MembershipCardStore(url: url, initialName: "Ada Lovelace", now: { date })
        let initial = try require(store.state)
        precondition(initial.name == "Ada Lovelace" && initial.createdAt == date && initial.isValid)
        let a = MembershipCardStore.shared(directory: root, name: "Shared")
        let pane = MembershipCardSettingsView(cards: a)
        let window = NSWindow(contentRect: pane.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = pane
        SettingsFocusState.connectKeyViews(in: pane)
        func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
        let buttons = descendants(pane).compactMap { $0 as? NSButton }.filter { $0.superview?.isHidden == false }
        precondition(buttons.count == 5)
        for label in ["Share card", "Download card", "Randomize card design", "Edit card display name"] {
            precondition(buttons.contains { $0.accessibilityLabel() == label && $0.isEnabled })
        }
        let card = try require(pane.subviews.compactMap { $0 as? MembershipCardView }.first)
        precondition(card.accessibilityRole() == .image)
        precondition(card.accessibilityLabel()?.contains("Local Parc card created") == true)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        for shape in 1...4 {
            var specimen = initial; specimen.shape = shape; specimen.palette = shape - 1
            let bitmap = try require(MembershipCardArtwork.render(specimen))
            let chromeOnly = try require(MembershipCardArtwork.render(specimen, includeArtwork: false))
            precondition(bitmap.pixelsWide == 720 && bitmap.pixelsHigh == 1080)
            precondition(bitmap.colorAt(x: 360, y: 600)?.alphaComponent ?? 0 > 0.99)
            func pixel(_ image: NSBitmapImageRep, x: Int, y: Int) -> [CGFloat] {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return [] }
                return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            }
            precondition(pixel(bitmap, x: 360, y: 600) != pixel(chromeOnly, x: 360, y: 600),
                         "chrome-only render leaves the 208×192 artwork hole without the baked silhouette")
            var chromeMatch = false
            for y in 0..<bitmap.pixelsHigh where pixel(bitmap, x: 360, y: y) == pixel(chromeOnly, x: 360, y: y) {
                if (pixel(bitmap, x: 360, y: y).first ?? 1) < 0.9 { chromeMatch = true; break }
            }
            precondition(chromeMatch, "chrome-only and full renders match on name/ticket ink")
            try require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("card-\(shape).png"))
        }
        for palette in 0..<8 { precondition(MembershipCardArtwork.image("fallback-gradient-\(MembershipCardState.fallbackNumbers[palette])") != nil) }
        let matte = try require(MembershipCardArtwork.sharingBitmap(initial))
        precondition(matte.pixelsWide == 1236 && matte.pixelsHigh == 1593)
        try require(matte.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("sharing-matte.png"))
        for (appearance, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            pane.appearance = NSAppearance(named: appearance)
            pane.layoutSubtreeIfNeeded(); pane.displayIfNeeded()
            let full = try require(pane.bitmapImageRepForCachingDisplay(in: pane.bounds))
            pane.cacheDisplay(in: pane.bounds, to: full)
            try require(full.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("pane-\(label).png"))
        }
        pane.showDefaultBrowserPrompt(true, waiting: false)
        for (appearance, label) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            pane.appearance = NSAppearance(named: appearance)
            pane.layoutSubtreeIfNeeded(); pane.displayIfNeeded()
            let full = try require(pane.bitmapImageRepForCachingDisplay(in: pane.bounds))
            pane.cacheDisplay(in: pane.bounds, to: full)
            try require(full.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("pane-banner-\(label).png"))
        }
        pane.showDefaultBrowserPrompt(true, waiting: false, failure: "macOS refused the change.")
        precondition(descendants(pane).contains { ($0 as? NSTextField)?.stringValue == "macOS refused the change." },
                     "a refused default-browser request is shown on the banner")
        window.contentView = nil
        let surface = try require(card.layer?.sublayers?.first?.sublayers?.first)
        precondition(surface.animationKeys()?.isEmpty ?? true)
        let art = try require(surface.sublayers?.first { abs($0.frame.width - 208) < 0.5 && abs($0.frame.height - 192) < 0.5 })
        precondition(art.isHidden == false, "stopMotion keeps the live artwork layer visible")
        let rotors = art.sublayers?.filter { $0.bounds == .zero } ?? []
        precondition(rotors.count == 15, "the card background draws fifteen blobs")
        let current = try require(a.state)
        let field = MembershipCardBlobField(current)
        for (rotor, blob) in zip(rotors, field.rest) {
            precondition((0.2...0.35).contains(blob.scale) && (0...300).contains(blob.offset.x) && (0...300).contains(blob.offset.y)
                         && abs(blob.rotation) <= 2 * .pi, "blob attributes stay in range")
            precondition(sameAngle(rotor, blob.rotation), "each blob rests at its rotation about the artwork centre")
            precondition(rotor.sublayers?.first?.position == blob.offset)
        }
        precondition(MembershipCardBlobField(current).rest.map(\.offset) == field.rest.map(\.offset),
                     "the same saved design always rests the same way")
        try a.regenerate()
        let randomized = try require(a.state)
        let after = MembershipCardBlobField(randomized)
        precondition(after.rest.map(\.offset) != field.rest.map(\.offset) && after.colors != field.colors,
                     "Randomize changes the blob arrangement and colours")
        precondition(card.state == randomized, "the live card shows the randomized design")
        let movedRotors = try require(surface.sublayers?.first { abs($0.frame.width - 208) < 0.5 }?.sublayers?.filter { $0.bounds == .zero })
        precondition(zip(movedRotors, after.rest).allSatisfy { sameAngle($0.0, $0.1.rotation) },
                     "the live blobs move to the new arrangement")
        for (state, label) in [(current, "before"), (randomized, "after")] {
            let bitmap = try require(MembershipCardArtwork.render(state))
            try require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("randomize-\(label).png"))
        }
        print("PASS: membership persistence, regeneration, validation, failed writes, stale owner, future/corrupt preservation, shared ownership, native AX controls, inactive motion cleanup and four rendered masks")
    }
    static func sameAngle(_ layer: CALayer, _ angle: CGFloat) -> Bool {
        let value = (layer.value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue ?? .nan
        return abs(sin(value) - sin(angle)) < 0.001 && abs(cos(value) - cos(angle)) < 0.001
    }
    static func require<T>(_ value: T?) throws -> T { guard let value else { throw CocoaError(.coderValueNotFound) }; return value }
}
