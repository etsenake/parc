import AppKit
import SwiftUI

@MainActor final class SidebarPlusButtonState: ObservableObject {
    @Published var hovered = false
    @Published var pressed = false
    @Published var open = false
    @Published var colors = TranslucentButtonColors.standard(dark: false)

    func install(in button: NSButton) {
        let host = LibraryRenderingHostingView(rootView: SidebarPlusButtonFace(state: self))
        host.sizingOptions = []
        host.frame = button.bounds
        host.autoresizingMask = [.width, .height]
        button.addSubview(host)
    }
}

struct SidebarPlusButtonFace: View {
    @ObservedObject var state: SidebarPlusButtonState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PlusGlyph()
            .frame(width: 14, height: 14)
            .rotationEffect(.radians(state.open ? .pi / 4 : 0))
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.5, blendDuration: 0), value: state.open)
            .padding(.all, 8)
            .frame(width: 32, height: 32, alignment: .center)
            .background(Color(nsColor: state.colors.background(hovered: state.hovered, pressed: state.pressed, enabled: true)))
            .foregroundColor(Color(nsColor: state.colors.foreground(pressed: state.pressed, enabled: true)))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(state.pressed ? 0.95 : 1, anchor: .center)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: state.pressed)
            .animation(.easeIn(duration: 0.1), value: state.hovered)
    }

    private struct PlusGlyph: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let corner = CGSize(width: 1, height: 1)
            path.addRoundedRect(in: CGRect(x: rect.midX - 7, y: rect.midY - 1, width: 14, height: 2), cornerSize: corner, style: .continuous)
            path.addRoundedRect(in: CGRect(x: rect.midX - 1, y: rect.midY - 7, width: 2, height: 14), cornerSize: corner, style: .continuous)
            return path
        }
    }
}
