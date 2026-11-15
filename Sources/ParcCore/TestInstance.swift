import CoreGraphics
import Foundation

struct TestInstance: Equatable {
    static let current = TestInstance(arguments: ProcessInfo.processInfo.arguments)

    let isActive: Bool
    let windowSize: CGSize?
    let windowPosition: CGPoint?
    let perfMarksPath: String?

    init(arguments: [String]) {
        var active = false
        var size: CGSize?
        var position: CGPoint?
        var marks: String?
        var index = 1
        while index < arguments.count {
            let value = arguments[index]
            index += 1
            if value == "--" { break }
            if value == "--parc-test-instance" {
                active = true
            } else if value == "--parc-perf-marks" {
                if index < arguments.count, !arguments[index].hasPrefix("-") { marks = arguments[index]; index += 1 }
            } else if value.hasPrefix("--parc-perf-marks=") {
                marks = String(value.dropFirst("--parc-perf-marks=".count))
            } else if let pair = Self.pair(value, named: "--window-size") {
                if pair.0 > 0, pair.1 > 0 { size = CGSize(width: pair.0, height: pair.1) }
            } else if let pair = Self.pair(value, named: "--window-position") {
                position = CGPoint(x: pair.0, y: pair.1)
            }
        }
        isActive = active
        windowSize = size
        windowPosition = position
        perfMarksPath = marks?.isEmpty == false ? marks : nil
    }

    var placesFirstWindow: Bool { isActive && (windowSize != nil || windowPosition != nil) }

    func firstWindowFrame(from frame: CGRect, primaryScreen screen: CGRect) -> CGRect {
        let size = windowSize ?? frame.size
        let left = windowPosition.map { screen.minX + $0.x } ?? frame.minX
        let top = windowPosition.map { screen.maxY - $0.y } ?? frame.maxY
        return CGRect(x: left, y: top - size.height, width: size.width, height: size.height)
    }

    private static func pair(_ value: String, named name: String) -> (CGFloat, CGFloat)? {
        guard value.hasPrefix(name + "=") else { return nil }
        let parts = value.dropFirst(name.count + 1).split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let first = Int(parts[0]), let second = Int(parts[1]) else { return nil }
        return (CGFloat(first), CGFloat(second))
    }
}
