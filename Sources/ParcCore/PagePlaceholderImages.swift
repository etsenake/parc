import CoreGraphics
import Foundation

///
/// ContentPlaceholderClient). The frame belongs to the tab: one copy, taken as
/// the page leaves, that every window showing the tab's placeholder reads and
/// scales to its own pane. It lives only while some window shows that
/// placeholder. A store owns one, so a private window's frames never reach a
/// regular window, nor the reverse.
@MainActor
final class PagePlaceholderImages {
    private var images: [UUID: CGImage] = [:]
    private var shown: [UUID: Set<UUID>] = [:]
    private var observers: [UUID: () -> Void] = [:]

    /// The frame of a tab `window` shows as a placeholder.
    func image(for tab: UUID, in window: UUID) -> CGImage? {
        shown[window]?.contains(tab) == true ? images[tab] : nil
    }
    func isShown(_ tab: UUID) -> Bool { shown.values.contains { $0.contains(tab) } }

    /// `tabs` is everything `window` shows as a placeholder; a frame no window
    /// shows any longer is dropped.
    func setShown(_ tabs: Set<UUID>, in window: UUID) {
        let released = (shown[window] ?? []).subtracting(tabs)
        shown[window] = tabs.isEmpty ? nil : tabs
        for tab in released where !isShown(tab) { images.removeValue(forKey: tab) }
    }

    /// Runs when a frame arrives for a tab `window` shows.
    func observe(in window: UUID, _ handler: @escaping () -> Void) { observers[window] = handler }

    func removeWindow(_ window: UUID) {
        setShown([], in: window)
        observers.removeValue(forKey: window)
    }

    /// A new frame replaces the old one in every window showing the tab.
    func store(_ image: CGImage, for tab: UUID) {
        guard isShown(tab) else { return }
        images[tab] = image
        for window in shown.filter({ $0.value.contains(tab) }).keys { observers[window]?() }
    }
}

enum PagePlaceholderCaptureOrder {
    struct Step: Equatable {
        let tab: UUID
        /// The engine copies only the selected page of a window, so any other
        /// pane is copied with the selection lent to it for the copy.
        let lendsSelection: Bool
    }

    /// The order a window takes the copies of its arrived pages: the selected
    /// pane's first, then each other pane in arrival order, one at a time.
    static func steps(_ pending: [UUID], selected: UUID?) -> [Step] {
        let first = pending.filter { $0 == selected }
        return (first + pending.filter { $0 != selected }).map { Step(tab: $0, lendsSelection: $0 != selected) }
    }
}
