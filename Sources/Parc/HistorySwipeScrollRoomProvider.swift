import AppKit
import ParcCore

@MainActor
protocol HistorySwipeScrollRoomProvider: AnyObject {
    var historySwipeScrollRoom: HistorySwipeTargets.ScrollRoom? { get }
}
