import Foundation
import Combine
import CoreGraphics
import ParcCore

@MainActor
package final class WindowFramePreferences: ObservableObject {
    package static let shared = WindowFramePreferences()
    package static let previewBounds: ClosedRange<CGFloat> = 2.6...13.4
    package struct State: Codable, Equatable {
        var version = 1
        package var thickness = WindowFrameThickness.standard
    }
    @Published package private(set) var state: State
    @Published private(set) var preview: CGFloat?
    package private(set) var loadError = false
    private let defaults: UserDefaults
    private let key = "parc.windowFrame.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: key) {
            guard let data = stored as? Data,
                  let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.version == 1,
                  WindowFrameThickness.range.contains(decoded.thickness) else {
                state = State(); loadError = true; return
            }
            state = decoded
        } else { state = State() }
    }

    package var thickness: CGFloat { preview ?? CGFloat(state.thickness) }
    package var isAdjusting: Bool { preview != nil }

    package func setPreview(_ value: CGFloat?) {
        let next = value.map { min(Self.previewBounds.upperBound, max(Self.previewBounds.lowerBound, $0)) }
        guard next != preview else { return }
        preview = next
    }

    package func setThickness(_ value: Int) throws {
        guard !loadError else { throw Failure.unavailable }
        let clamped = WindowFrameThickness.clamped(value)
        guard clamped != state.thickness else { return }
        var next = state; next.thickness = clamped
        defaults.set(try JSONEncoder().encode(next), forKey: key)
        state = next
    }

    package enum Failure: LocalizedError {
        case unavailable
        package var errorDescription: String? {
            "The saved window frame preference could not be read. It has been preserved."
        }
    }
}
