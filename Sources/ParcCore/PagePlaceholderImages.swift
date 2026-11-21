import CoreGraphics
import Foundation

@MainActor
package final class PagePlaceholderImages {
    private var images: [UUID: CGImage] = [:]
    private var shown: [UUID: Set<UUID>] = [:]
    private var observers: [UUID: () -> Void] = [:]

    package func image(for tab: UUID, in window: UUID) -> CGImage? {
        shown[window]?.contains(tab) == true ? images[tab] : nil
    }
    package func isShown(_ tab: UUID) -> Bool { shown.values.contains { $0.contains(tab) } }

    package func setShown(_ tabs: Set<UUID>, in window: UUID) {
        let released = (shown[window] ?? []).subtracting(tabs)
        shown[window] = tabs.isEmpty ? nil : tabs
        for tab in released where !isShown(tab) { images.removeValue(forKey: tab) }
    }

    package func observe(in window: UUID, _ handler: @escaping () -> Void) { observers[window] = handler }

    package func removeWindow(_ window: UUID) {
        setShown([], in: window)
        observers.removeValue(forKey: window)
    }

    package func store(_ image: CGImage, for tab: UUID) {
        guard isShown(tab) else { return }
        images[tab] = image
        for window in shown.filter({ $0.value.contains(tab) }).keys { observers[window]?() }
    }
}

package enum PagePlaceholderCaptureOrder {
    package static let orderedAttempts = 3
    package static let lastAttempt = 5

    package static func mayCapture(_ tab: UUID, pending: Set<UUID>, focused: UUID?) -> Bool {
        guard let focused, focused != tab else { return true }
        return !pending.contains(focused)
    }
    package static func waits(_ tab: UUID, attempt: Int, pending: Set<UUID>, focused: UUID?) -> Bool {
        attempt < orderedAttempts && !mayCapture(tab, pending: pending, focused: focused)
    }
    package static func retries(after attempt: Int) -> Bool { attempt < lastAttempt }
    package static func delay(before attempt: Int) -> TimeInterval { 0.05 + Double(attempt) * 0.15 }
}
