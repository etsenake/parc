import Foundation

package struct SoftwareUpdateDownloadProgress {
    package struct Display {
        package let text: String
        package let fraction: Double?
        package let widthTemplate: String?

        package init(text: String, fraction: Double?, widthTemplate: String?) {
            self.text = text
            self.fraction = fraction
            self.widthTemplate = widthTemplate
        }
    }

    package private(set) var receivedLength: UInt64 = 0
    package private(set) var expectedLength: UInt64 = 0

    package init(receivedLength: UInt64 = 0, expectedLength: UInt64 = 0) {
        self.receivedLength = receivedLength
        self.expectedLength = expectedLength
    }

    package mutating func expect(_ length: UInt64) {
        if length > 0 { expectedLength = length }
    }

    package mutating func receive(_ length: UInt64) {
        let (sum, overflow) = receivedLength.addingReportingOverflow(length)
        receivedLength = overflow ? .max : sum
    }

    package var display: Display {
        let total = max(expectedLength, receivedLength)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.zeroPadsFractionDigits = true
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
