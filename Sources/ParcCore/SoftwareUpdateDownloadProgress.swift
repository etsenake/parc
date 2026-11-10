import Foundation

/// Sparkle reports byte increments, not a running total. Keep the count and
/// its presentation together so the label and bar describe the same download.
struct SoftwareUpdateDownloadProgress {
    struct Display {
        let text: String
        let fraction: Double?
        /// Reserve the completed count's width, so changing digits grow left
        /// without moving the decimal point or the "of …" suffix.
        let widthTemplate: String?
    }

    private(set) var receivedLength: UInt64 = 0
    private(set) var expectedLength: UInt64 = 0

    mutating func expect(_ length: UInt64) {
        // Sparkle can report the size more than once, including invalid sizes.
        // An unknown size must not erase one we already know.
        if length > 0 { expectedLength = length }
    }

    mutating func receive(_ length: UInt64) {
        let (sum, overflow) = receivedLength.addingReportingOverflow(length)
        receivedLength = overflow ? .max : sum
    }

    var display: Display {
        let total = max(expectedLength, receivedLength)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.zeroPadsFractionDigits = true
        // Use the total's unit throughout the transfer. Otherwise the count
        // switches between KB and MB and drops trailing zeroes as it grows.
        switch total {
        case 0..<1_000: formatter.allowedUnits = .useBytes
        case 1_000..<1_000_000: formatter.allowedUnits = .useKB
        case 1_000_000..<1_000_000_000: formatter.allowedUnits = .useMB
        case 1_000_000_000..<1_000_000_000_000: formatter.allowedUnits = .useGB
        case 1_000_000_000_000..<1_000_000_000_000_000: formatter.allowedUnits = .useTB
        case 1_000_000_000_000_000..<1_000_000_000_000_000_000: formatter.allowedUnits = .usePB
        default: formatter.allowedUnits = .useEB
        }
        let received = formatter.string(fromByteCount: Int64(clamping: receivedLength))
        guard expectedLength > 0 else {
            return Display(text: receivedLength == 0 ? "Downloading..." : "\(received) downloaded",
                           fraction: nil, widthTemplate: nil)
        }
        let expected = formatter.string(fromByteCount: Int64(clamping: total))
        return Display(text: "\(received) of \(expected)",
                       fraction: min(1, Double(receivedLength) / Double(expectedLength)),
                       widthTemplate: "\(expected) of \(expected)")
    }
}
