import AppKit

///
///
enum DeveloperToolbarLayout {
    ///
    static let height: CGFloat = 40
    ///
    static let leadingInset: CGFloat = 8
    ///
    static let trailingInset: CGFloat = 5
    ///
    static let buttonSize: CGFloat = 28
    /// Default `HStack` spacing between the lock and the address.
    static let addressLeadingSpacing: CGFloat = 8
    /// Floor kept so the address remains hittable after trailing collapse.
    static let addressMinWidth: CGFloat = 20
    ///
    static let dividerWidth: CGFloat = 1.5
    static let dividerHeight: CGFloat = 20
    ///
    static let dividerPadding: CGFloat = 7.5
    /// Trailing controls left of the 1.5-point divider: Copy, Portrait, Capture.
    static let dividerAfterTrailingIndex = 2
    static let trailingCount = 8

    ///
    static let stripeDegrees: Double = -45
    ///
    static let stripeBarWidth: CGFloat = 15
    ///
    static let stripeBarSpacing: CGFloat = 15
    ///
    static let stripeForegroundAlphaLight: CGFloat = 0.3
    ///
    static let stripeForegroundAlphaDark: CGFloat = 0.02
    /// Fallback fill when the page has no theme color.
    static let fallbackTint = NSColor(calibratedRed: 0.05, green: 0.33, blue: 0.43, alpha: 1)

    struct Frames: Equatable {
        var siteInfo: NSRect
        var address: NSRect
        var trailing: [NSRect]
        var divider: NSRect
        var hiddenTrailing: [Bool]
    }

    static func stripeForegroundAlpha(isDark: Bool) -> CGFloat {
        isDark ? stripeForegroundAlphaDark : stripeForegroundAlphaLight
    }

    static func stripeOrigins(width: CGFloat, height: CGFloat) -> [CGFloat] {
        let period = stripeBarWidth + stripeBarSpacing
        guard period > 0, width > 0, height > 0 else { return [] }
        let extra = height
        var origins: [CGFloat] = []
        var x = -extra
        while x < width + extra {
            origins.append(x)
            x += period
        }
        return origins
    }

    static func stripePath(in bounds: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let height = bounds.height
        for origin in stripeOrigins(width: bounds.width, height: height) {
            path.move(to: NSPoint(x: origin, y: 0))
            path.line(to: NSPoint(x: origin + stripeBarWidth, y: 0))
            path.line(to: NSPoint(x: origin + stripeBarWidth + height, y: height))
            path.line(to: NSPoint(x: origin + height, y: height))
            path.close()
        }
        return path
    }

    ///
    ///
    static func scheduleFirstEditSelection(_ field: NSTextField) {
        DispatchQueue.main.async {
            field.currentEditor()?.selectAll(field)
        }
    }

    static func frames(in bounds: NSRect) -> Frames {
        var hidden = Array(repeating: false, count: trailingCount)
        var result = pack(in: bounds, hiddenTrailing: hidden)
        while result.address.width + 0.5 < addressMinWidth {
            guard let index = hidden.firstIndex(of: false) else { break }
            hidden[index] = true
            result = pack(in: bounds, hiddenTrailing: hidden)
        }
        return result
    }

    private static func pack(in bounds: NSRect, hiddenTrailing: [Bool]) -> Frames {
        let y = (bounds.height - buttonSize) / 2
        let siteInfo = NSRect(x: leadingInset, y: y, width: buttonSize, height: buttonSize)
        var trailing = Array(repeating: NSRect.zero, count: trailingCount)
        var divider = NSRect.zero
        var right = bounds.width - trailingInset
        for index in stride(from: trailingCount - 1, through: 0, by: -1) {
            guard !hiddenTrailing[index] else { continue }
            if index == dividerAfterTrailingIndex,
               dividerAfterTrailingIndex + 1 < trailingCount,
               !hiddenTrailing[dividerAfterTrailingIndex + 1] {
                right -= dividerPadding
                divider = NSRect(x: right - dividerWidth,
                                 y: (bounds.height - dividerHeight) / 2,
                                 width: dividerWidth, height: dividerHeight)
                right -= dividerWidth + dividerPadding
            }
            right -= buttonSize
            trailing[index] = NSRect(x: right, y: y, width: buttonSize, height: buttonSize)
        }
        let trailingLeft = trailing.enumerated()
            .filter { !hiddenTrailing[$0.offset] && $0.element.width > 0 }
            .map(\.element.minX)
            .min() ?? (bounds.width - trailingInset)
        let addressX = siteInfo.maxX + addressLeadingSpacing
        let addressWidth = max(0, trailingLeft - addressLeadingSpacing - addressX)
        let address = NSRect(x: addressX, y: 0, width: addressWidth, height: bounds.height)
        return Frames(siteInfo: siteInfo, address: address, trailing: trailing,
                      divider: divider, hiddenTrailing: hiddenTrailing)
    }
}

/// Pane and Peek developer/browser strip frames used to skip forced
/// `layoutSubtreeIfNeeded` in `refreshDeveloperToolbars` when chrome is
/// already current. Heights are the laid-out strip heights (0 when hidden).
enum DeveloperChromeGeometry {
    /// BrowserPane.layout: developer and browser bars share the top edge;
    /// content starts below `max(developer, browser)`.
    static func paneIsCurrent(
        bounds: NSRect,
        developerHeight: CGFloat,
        browserHeight: CGFloat,
        developerFrame: NSRect,
        browserFrame: NSRect,
        contentFrame: NSRect
    ) -> Bool {
        let headerHeight = max(developerHeight, browserHeight)
        return developerFrame == NSRect(x: 0, y: 0, width: bounds.width, height: developerHeight)
            && browserFrame == NSRect(x: 0, y: 0, width: bounds.width, height: browserHeight)
            && contentFrame == NSRect(x: 0, y: headerHeight, width: bounds.width,
                                      height: bounds.height - headerHeight)
    }

    /// PeekHostView.layout: strip sits on the card below the 30-point title band.
    static func peekIsCurrent(
        bounds: NSRect,
        developerHeight: CGFloat,
        browserHeight: CGFloat,
        developerFrame: NSRect,
        browserFrame: NSRect,
        contentFrame: NSRect
    ) -> Bool {
        let width = min(max(0, bounds.width - 80), bounds.width * 0.8)
        let card = NSRect(x: (bounds.width - width) / 2, y: 12, width: width,
                          height: max(0, bounds.height - 24))
        let stripHeight = max(developerHeight, browserHeight)
        return developerFrame == NSRect(x: card.minX, y: card.minY + 30, width: width,
                                        height: developerHeight)
            && browserFrame == NSRect(x: card.minX, y: card.minY + 30, width: width,
                                      height: browserHeight)
            && contentFrame == NSRect(x: card.minX, y: card.minY + 30 + stripHeight,
                                      width: width,
                                      height: max(0, card.height - 30 - stripHeight))
    }
}
