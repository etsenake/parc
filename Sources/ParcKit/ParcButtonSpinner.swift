import AppKit
import ParcCore
import SwiftUI

package struct ParcButtonSpinner: View {
    package init() {}
    package var body: some View {
        ProgressView().progressViewStyle(.circular).scaleEffect(0.5).frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
