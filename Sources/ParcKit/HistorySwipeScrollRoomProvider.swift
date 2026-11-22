import AppKit
import ParcCore

@MainActor
package protocol HistorySwipeScrollRoomProvider: AnyObject {
    var historySwipeScrollRoom: HistorySwipeTargets.ScrollRoom? { get }
}
