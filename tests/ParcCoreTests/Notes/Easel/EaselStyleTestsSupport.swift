import Foundation
import Testing
@testable import ParcCore

enum EaselStyleTestsSupport {
    static func item(_ kind: EaselItemKind) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: 0, y: 0, width: 120, height: 80))
    }
}
