import AppKit
import ParcCore
import SwiftUI

struct ParcButtonSpinner: View {
    var body: some View {
        ProgressView().progressViewStyle(.circular).scaleEffect(0.5).frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
