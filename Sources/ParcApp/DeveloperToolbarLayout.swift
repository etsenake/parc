import AppKit

enum DeveloperToolbarLayout {
    static let height: CGFloat = 40
    static let leadingInset: CGFloat = 8
    static let trailingInset: CGFloat = 5
    static let buttonSize: CGFloat = 28
    static let addressLeadingSpacing: CGFloat = 8
    static let addressMinWidth: CGFloat = 20
    static let dividerWidth: CGFloat = 1.5
    static let dividerHeight: CGFloat = 20
    static let dividerPadding: CGFloat = 7.5
    static let dividerAfterTrailingIndex = 2
    static let siteControlsTrailingIndex = 6
    static let trailingCount = 8

    static let stripeDegrees: Double = -45
    static let stripeBarWidth: CGFloat = 15
    static let stripeBarSpacing: CGFloat = 15
    static let stripeForegroundAlphaLight: CGFloat = 0.3
    static let stripeForegroundAlphaDark: CGFloat = 0.02
    static let fallbackTint = NSColor(calibratedRed: 0.05, green: 0.33, blue: 0.43, alpha: 1)

    struct Frames: Equatable {
        var siteInfo: NSRect
        var address: NSRect
        var trailing: [NSRect]
        var divider: NSRect
        var hiddenTrailing: [Bool]
        var blocked: NSRect?
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

    static func scheduleFirstEditSelection(_ field: NSTextField) {
        DispatchQueue.main.async {
            field.currentEditor()?.selectAll(field)
        }
    }

    static func frames(in bounds: NSRect, blockedTitleRoom: CGFloat? = nil) -> Frames {
        var hidden = Array(repeating: false, count: trailingCount)
        var result = pack(in: bounds, hiddenTrailing: hidden)
        while result.address.width + 0.5 < addressMinWidth {
            guard let index = hidden.firstIndex(of: false) else { break }
            hidden[index] = true
            result = pack(in: bounds, hiddenTrailing: hidden)
        }
        guard let room = blockedTitleRoom else { return result }
        let signed = pack(in: bounds, hiddenTrailing: hidden, blocked: true)
        if signed.address.width + 0.5 >= room { return signed }
        let card = siteControlsTrailingIndex
        guard !hidden[card], result.address.width + 0.5 >= room else { return result }
        result.blocked = result.trailing[card]
        result.trailing[card] = .zero
        result.hiddenTrailing[card] = true
        return result
    }

    private static func pack(in bounds: NSRect, hiddenTrailing: [Bool], blocked: Bool = false) -> Frames {
        let y = (bounds.height - buttonSize) / 2
        let siteInfo = NSRect(x: leadingInset, y: y, width: buttonSize, height: buttonSize)
        var trailing = Array(repeating: NSRect.zero, count: trailingCount)
        var divider = NSRect.zero
        var blockedFrame: NSRect?
        var right = bounds.width - trailingInset
        for index in stride(from: trailingCount - 1, through: 0, by: -1) {
            if !hiddenTrailing[index] {
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
            if blocked, index == siteControlsTrailingIndex {
                right -= buttonSize
                blockedFrame = NSRect(x: right, y: y, width: buttonSize, height: buttonSize)
            }
        }
        let trailingLeft = (trailing.enumerated()
            .filter { !hiddenTrailing[$0.offset] && $0.element.width > 0 }
            .map(\.element.minX) + [blockedFrame?.minX].compactMap { $0 })
            .min() ?? (bounds.width - trailingInset)
        let addressX = siteInfo.maxX + addressLeadingSpacing
        let addressWidth = max(0, trailingLeft - addressLeadingSpacing - addressX)
        let address = NSRect(x: addressX, y: 0, width: addressWidth, height: bounds.height)
        return Frames(siteInfo: siteInfo, address: address, trailing: trailing,
                      divider: divider, hiddenTrailing: hiddenTrailing, blocked: blockedFrame)
    }
}

enum DeveloperChromeGeometry {
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

    static func peekIsCurrent(
        card: NSRect,
        developerHeight: CGFloat,
        browserHeight: CGFloat,
        developerFrame: NSRect,
        browserFrame: NSRect,
        contentFrame: NSRect
    ) -> Bool {
        let stripHeight = max(developerHeight, browserHeight)
        return developerFrame == NSRect(x: 0, y: 0, width: card.width, height: developerHeight)
            && browserFrame == NSRect(x: 0, y: 0, width: card.width, height: browserHeight)
            && contentFrame == NSRect(x: 0, y: stripHeight, width: card.width,
                                      height: max(0, card.height - stripHeight))
    }
}
