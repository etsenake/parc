import AppKit
import Combine
import ParcCore

package final class FlippedStackView: NSStackView {
    package override var isFlipped: Bool { true }
}
