import CoreGraphics
import Foundation

@MainActor
final class PagePlaceholderImages {
    private var images: [UUID: CGImage] = [:]
    private var shown: [UUID: Set<UUID>] = [:]
    private var observers: [UUID: () -> Void] = [:]

    func image(for tab: UUID, in window: UUID) -> CGImage? {
        shown[window]?.contains(tab) == true ? images[tab] : nil
    }
    func isShown(_ tab: UUID) -> Bool { shown.values.contains { $0.contains(tab) } }

    func setShown(_ tabs: Set<UUID>, in window: UUID) {
        let released = (shown[window] ?? []).subtracting(tabs)
        shown[window] = tabs.isEmpty ? nil : tabs
        for tab in released where !isShown(tab) { images.removeValue(forKey: tab) }
    }

    func observe(in window: UUID, _ handler: @escaping () -> Void) { observers[window] = handler }

    func removeWindow(_ window: UUID) {
        setShown([], in: window)
        observers.removeValue(forKey: window)
    }

    func store(_ image: CGImage, for tab: UUID) {
        guard isShown(tab) else { return }
        images[tab] = image
        for window in shown.filter({ $0.value.contains(tab) }).keys { observers[window]?() }
    }
}

enum PagePlaceholderCaptureOrder {
    static func mayCapture(_ tab: UUID, pending: Set<UUID>, focused: UUID?) -> Bool {
        guard let focused, focused != tab else { return true }
        return !pending.contains(focused)
    }
}
