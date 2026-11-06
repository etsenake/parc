import Foundation

///
/// current key window. The caller supplies live window ownership and order.
enum DockReopen {
    struct Window {
        var available: Bool
        var isMiniaturized: Bool
    }
    enum Decision: Equatable {
        case none
        case makeKey(Int)
        case makeKeyAndOrderFront(Int)
        case createWindow
    }

    static func decision(hasKeyWindow: Bool, windows: [Window], lastKeyIndex: Int?) -> Decision {
        guard !hasKeyWindow else { return .none }
        if windows.isEmpty { return .createWindow }
        let last = lastKeyIndex.flatMap { windows.indices.contains($0) && windows[$0].available ? $0 : nil }
        guard let index = last ?? windows.indices.first(where: { windows[$0].available }) else { return .none }
        return windows[index].isMiniaturized ? .makeKey(index) : .makeKeyAndOrderFront(index)
    }
}
