import CoreGraphics
import Foundation

enum CaptureSelectionMode: String, CaseIterable, Equatable {
    case element, region
}

enum CaptureModeItem: String, CaseIterable, Equatable {
    case element, region, visibleArea, fullPage, cancel

    var mode: CaptureSelectionMode? {
        switch self {
        case .element: return .element
        case .region: return .region
        case .visibleArea, .fullPage, .cancel: return nil
        }
    }

    var group: Int {
        switch self {
        case .element, .region: return 0
        case .visibleArea, .fullPage: return 1
        case .cancel: return 2
        }
    }

    var title: String {
        switch self {
        case .element: return "Element"
        case .region: return "Region"
        case .visibleArea: return "Visible Area"
        case .fullPage: return "Full Page"
        case .cancel: return "Cancel"
        }
    }

    var key: String {
        switch self {
        case .element: return "E"
        case .region: return "R"
        case .visibleArea: return "V"
        case .fullPage: return "F"
        case .cancel: return "esc"
        }
    }

    var symbol: String {
        switch self {
        case .element: return "cursorarrow.rays"
        case .region: return "rectangle.dashed"
        case .visibleArea: return "macwindow"
        case .fullPage: return "rectangle.expand.vertical"
        case .cancel: return "xmark"
        }
    }

    var toolTip: String {
        switch self {
        case .element: return "Capture the part of the page under the pointer"
        case .region: return "Drag out any rectangle"
        case .visibleArea: return "Capture everything you can see"
        case .fullPage: return "Capture the whole page, top to bottom"
        case .cancel: return "Stop capturing"
        }
    }
}

enum CaptureModeKeys {
    private static let letters: [Character: CaptureModeItem] = ["e": .element, "r": .region, "v": .visibleArea, "f": .fullPage]
    private static let physical: [UInt16: CaptureModeItem] = [14: .element, 15: .region, 9: .visibleArea, 3: .fullPage]

    static func item(typed: String?, keyCode: UInt16) -> CaptureModeItem? {
        let typed = typed?.lowercased() ?? ""
        if typed.count == 1, let character = typed.first, character.isASCII { return letters[character] }
        return typed.isEmpty || typed.unicodeScalars.contains(where: { !$0.isASCII }) ? physical[keyCode] : nil
    }
}

enum CaptureModeHint {
    static let capturing = "Capturing…"
    static let noElement = "Nothing to grab there. Drag out a region instead"

    static func text(mode: CaptureSelectionMode, targeted: Bool, dragging: Bool) -> String {
        if dragging { return "Let go to capture this region" }
        switch mode {
        case .element: return targeted ? "Click to capture this, or drag out a region" : "Point at part of the page, or drag out a region"
        case .region: return "Drag across the part you want"
        }
    }

    static func accessibilityValue(mode: CaptureSelectionMode, targeted: Bool) -> String {
        switch mode {
        case .element where targeted: return "Element mode. Area selected. Press Return to capture it."
        case .element: return "Element mode. Point at part of the page or drag to select a region. V captures the visible area."
        case .region: return "Region mode. Drag to select a region. Return captures the visible area."
        }
    }
}

enum CaptureSizeReadout {
    static func text(_ size: CGSize) -> String {
        "\(Int(max(0, size.width.rounded()))) × \(Int(max(0, size.height.rounded())))"
    }

    static func elementRect(_ rect: CGRect, viewport: CGSize) -> CGRect {
        rect.insetBy(dx: -2, dy: -2).intersection(CGRect(origin: .zero, size: viewport))
    }

    static func viewportRect(_ rect: CGRect, overlay: CGSize, viewport: CGSize) -> CGRect? {
        guard overlay.width > 0, overlay.height > 0, viewport.width > 0, viewport.height > 0 else { return nil }
        return CGRect(x: rect.minX / overlay.width * viewport.width, y: rect.minY / overlay.height * viewport.height,
                      width: rect.width / overlay.width * viewport.width, height: rect.height / overlay.height * viewport.height)
    }

    static func pointSize(_ rect: CGRect) -> CGSize {
        guard !rect.isNull, !rect.isEmpty, rect.minX.isFinite, rect.minY.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite else { return .zero }
        return CGSize(width: (rect.maxX - 0.001).rounded(.up) - (rect.minX + 0.001).rounded(.down),
                      height: (rect.maxY - 0.001).rounded(.up) - (rect.minY + 0.001).rounded(.down))
    }

    static func placement(for frame: CGRect, size: CGSize, in bounds: CGRect,
                          avoiding obstacle: CGRect? = nil, gap: CGFloat = 6, margin: CGFloat = 8) -> CGRect {
        let safe = bounds.insetBy(dx: min(margin, bounds.width / 4), dy: min(margin, bounds.height / 4))
        let x = min(max(frame.maxX - size.width, safe.minX), max(safe.minX, safe.maxX - size.width))
        let candidates = [frame.maxY + gap, frame.minY - gap - size.height,
                          frame.maxY - gap - size.height, frame.minY + gap]
        let frames = candidates.map { CGRect(x: x, y: $0, width: size.width, height: size.height) }
        if let fit = frames.first(where: { safe.contains($0) && !(obstacle?.intersects($0) ?? false) }) { return fit }
        let inside = frames[2]
        return CGRect(x: x, y: min(max(inside.minY, safe.minY), max(safe.minY, safe.maxY - size.height)),
                      width: size.width, height: size.height)
    }
}

enum CaptureModeBarLayout {
    enum Density: Equatable { case full, labels, icons }

    static let margin: CGFloat = 16
    static let hintGap: CGFloat = 8

    static func density(available: CGFloat, full: CGFloat, labels: CGFloat) -> Density {
        available >= full ? .full : available >= labels ? .labels : .icons
    }

    static func frame(size: CGSize, in bounds: CGRect) -> CGRect {
        let inset = min(margin, bounds.width / 8, bounds.height / 8)
        let width = min(size.width, max(0, bounds.width - 2 * inset))
        let height = min(size.height, max(0, bounds.height - 2 * inset))
        return CGRect(x: (bounds.midX - width / 2).rounded(), y: (bounds.maxY - inset - height).rounded(),
                      width: width, height: height)
    }

    static func hintFrame(size: CGSize, above bar: CGRect, in bounds: CGRect) -> CGRect {
        let width: CGFloat = min(size.width, max(0, bounds.width - 2 * min(margin, bounds.width / 8)))
        let top: CGFloat = max(bounds.minY, bar.minY - hintGap - size.height)
        return CGRect(x: (bounds.midX - width / 2).rounded(), y: top.rounded(), width: width, height: size.height)
    }
}
