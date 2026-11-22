import AppKit
import Combine
import ParcCore

extension NSColor {
    convenience init(parcHex: String) {
        let raw = parcHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(raw, radix: 16) ?? 0xCAD5E2
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    static let parcInk = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.28, alpha: 1)
}
