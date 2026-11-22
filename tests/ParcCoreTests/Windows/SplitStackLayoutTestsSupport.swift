import Foundation
import Testing
@testable import ParcCore

enum SplitStackLayoutTestsSupport {
    static func close(_ left: [Double], _ right: [Double], _ tolerance: Double = 1e-9) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < tolerance }
    }

    static func stacks(_ sizes: [Int], _ slots: [Double], _ inner: [[Double]]) -> BrowserSplitStacks {
        BrowserSplitStacks(slotSizes: sizes, slotFactors: slots, stackFactors: inner)
    }

    static func frames(_ value: BrowserSplitStacks, _ orientation: SplitOrientation = .horizontal,
                               size: CGSize = CGSize(width: 1010, height: 710), scale: CGFloat = 2) -> [CGRect] {
        SplitStackGeometry.paneFrames(size: size, orientation: orientation, stacks: value,
                                      thickness: 10, minimum: 220, scale: scale)
    }

    static func flat(_ factors: [Double], _ orientation: SplitOrientation, _ size: CGSize) -> [CGRect] {
        SplitStackGeometry.flatFrames(size: size, orientation: orientation, factors: factors, thickness: 10, minimum: 220, scale: 2)
    }

    static func fits(_ frames: [CGRect], _ size: CGSize) -> Bool {
        frames.allSatisfy { CGRect(origin: .zero, size: size).contains($0) }
    }

    static let columnStacks = stacks([2, 1], [0.5, 0.5], [[0.5, 0.5], [1]])
    static let roomy = CGSize(width: 1010, height: 710)
    static let page = CGSize(width: 500, height: 520)
}
