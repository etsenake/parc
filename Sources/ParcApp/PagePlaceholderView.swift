import AppKit
import ImageIO

///
///
/// `BlurredSnapshotView`: the snapshot is an aspect-filled `Image` at the
/// content's full size, taken as the page leaves and never updated (as the user
///
///
/// `FirstResponderAcceptingView` whose click sends `onDidClickBackground`
///
final class PagePlaceholderView: NSView {
    var onClick: (() -> Void)?
    private var snapshotLayer: CALayer?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityHelp("Shown in another window. Press to move it here.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ image: CGImage?) {
        snapshotLayer?.removeFromSuperlayer(); snapshotLayer = nil
        guard let layer, let image else { return }
        let snapshot = CALayer()
        snapshot.contents = image
        snapshot.contentsGravity = .resizeAspectFill
        snapshot.contentsScale = window?.backingScaleFactor ?? 2
        snapshot.frame = bounds
        layer.addSublayer(snapshot)
        snapshotLayer = snapshot
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        snapshotLayer?.frame = bounds
        CATransaction.commit()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        snapshotLayer?.contentsScale = window?.backingScaleFactor ?? 2
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onClick?()
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return onClick != nil }

    /// The smallest copy of `image` that still fills `pixels` at its own
    /// aspect ratio, as the aspect-filled layer draws it; never enlarged.
    static func downsampled(_ image: CGImage, toFill pixels: CGSize) -> CGImage {
        let scale = max(pixels.width / CGFloat(image.width), pixels.height / CGFloat(image.height))
        guard scale < 1, scale > 0 else { return image }
        let width = max(1, Int((CGFloat(image.width) * scale).rounded(.up)))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded(.up)))
        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

/// The placeholder's one frame arrives from the engine as PNG data. It is
/// decoded straight to the pane's size on a background queue; the main
/// thread receives only that small image.
enum PagePlaceholderSnapshot {
    /// The longest side a copy of a `source`-sized capture needs to fill
    /// `target` at its own aspect ratio; never more than the capture.
    static func maxPixelSize(source: CGSize, filling target: CGSize?) -> Int {
        guard source.width > 0, source.height > 0 else { return 0 }
        let scale = target.map { max($0.width / source.width, $0.height / source.height) } ?? 1
        return max(1, Int((max(source.width, source.height) * min(1, max(scale, 0))).rounded(.up)))
    }

    private static let queue = DispatchQueue(label: "parc.page-placeholder.snapshot", qos: .userInitiated)

    static func thumbnail(fromPNG data: Data, maxPixelSize: Int, completion: @escaping (CGImage?) -> Void) {
        queue.async {
            let image = makeThumbnail(data, maxPixelSize: maxPixelSize)
            DispatchQueue.main.async { completion(image) }
        }
    }

    static func makeThumbnail(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        var options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        if maxPixelSize > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

enum PagePlaceholderDim {
    /// `DimState.dimmed(.placeholder)`: windowModal 0.3, popover 0.7, placeholder 0.6.
    static let opacity: Float = 0.6

    ///
    ///
    ///
    ///
    /// 4π·fraction/response, each times mass.
    static func apply(_ dimmed: Bool, to layer: CALayer, animated: Bool) {
        let target: Float = dimmed ? opacity : 1
        guard layer.opacity != target || layer.animation(forKey: "placeholderDim") != nil else { return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = target
        guard animated, from != target, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            layer.removeAnimation(forKey: "placeholderDim"); return
        }
        let response: CGFloat = dimmed ? 0.225 : 0.245, fraction: CGFloat = dimmed ? 0.895 : 0.865
        let spring = CASpringAnimation(keyPath: "opacity")
        spring.stiffness = pow(2 * .pi / response, 2) * spring.mass
        spring.damping = 4 * .pi * fraction * spring.mass / response
        spring.fromValue = from; spring.toValue = target
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "placeholderDim")
    }
}
