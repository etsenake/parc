import Foundation

package enum DockReopen {
    package struct Window {
        package var available: Bool
        package var isMiniaturized: Bool

        package init(available: Bool, isMiniaturized: Bool) {
            self.available = available
            self.isMiniaturized = isMiniaturized
        }
    }
    package enum Decision: Equatable {
        case none
        case makeKey(Int)
        case makeKeyAndOrderFront(Int)
        case createWindow
    }

    package static func decision(hasKeyWindow: Bool, windows: [Window], lastKeyIndex: Int?) -> Decision {
        guard !hasKeyWindow else { return .none }
        if windows.isEmpty { return .createWindow }
        let last = lastKeyIndex.flatMap { windows.indices.contains($0) && windows[$0].available ? $0 : nil }
        guard let index = last ?? windows.indices.first(where: { windows[$0].available }) else { return .none }
        return windows[index].isMiniaturized ? .makeKey(index) : .makeKeyAndOrderFront(index)
    }
}
