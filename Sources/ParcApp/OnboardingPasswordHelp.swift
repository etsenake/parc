import AppKit
import SwiftUI

/// AuthFeature owns this presentation above its setup card. Closing help must
/// never close, advance or replace the retained browser-import controller.
@MainActor
final class OnboardingPasswordHelp: NSView {
    private let presentation = Presentation()
    private var host: NSHostingView<Content>!
    private weak var previousResponder: NSResponder?
    var onDismiss: (() -> Void)?
    var isPresented: Bool { presentation.isPresented }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        host = NSHostingView(rootView: Content(presentation: presentation, dismiss: { [weak self] in self?.dismiss() }))
        host.frame = bounds; host.autoresizingMask = [.width, .height]
        addSubview(host)
        // This overlay has one actionable control. Keep native Tab traversal
        // inside its host instead of returning to the covered setup controls.
        host.nextKeyView = host
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        guard !isPresented, let window else { return }
        previousResponder = window.firstResponder
        setPresented(true, animated: true)
        window.makeFirstResponder(host)
    }

    func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        let owner = window
        let responder = previousResponder
        previousResponder = nil
        setPresented(false, animated: animated)
        onDismiss?()
        // Never pull focus back from another app/window, or into a retired view.
        if owner?.isKeyWindow == true, let view = responder as? NSView, view.window === owner {
            owner?.makeFirstResponder(view)
        }
    }

    private func setPresented(_ value: Bool, animated: Bool) {
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(animate ? .default : nil) { presentation.isPresented = value }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isPresented ? super.hitTest(point) : nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { dismiss(animated: false) }
        super.viewWillMove(toWindow: newWindow)
    }

    private final class Presentation: ObservableObject {
        @Published var isPresented = false
    }

    private struct Content: View {
        @ObservedObject var presentation: Presentation
        let dismiss: () -> Void
        @FocusState private var focused: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { geometry in
                if presentation.isPresented {
                    ZStack {
                        Color.black.opacity(0.1).contentShape(Rectangle()).onTapGesture(perform: dismiss)
                            .accessibilityHidden(true)
                        card
                            .scaleEffect(min(1, max(0, geometry.size.width - 48) / 950,
                                             max(0, geometry.size.height - 48) / 680))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .transition(.opacity.animation(reduceMotion ? nil : .default))
                    .onAppear { focused = true }
                    .onExitCommand(perform: dismiss)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Password export help")
                }
            }
        }

        private var card: some View {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold))
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(HelpCloseButtonStyle()).focused($focused)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close password export help")
                    .padding(.trailing, 24)
                }
                .frame(height: 56)
                Text(title).font(.system(size: 36, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 85)
                instructions.padding(.top, 24).frame(width: 793, height: 492)
                Spacer(minLength: 0)
            }
            .foregroundColor(Color(nsColor: OnboardingSetupPalette.title))
            .frame(width: 950, height: 680)
            .background(Color(nsColor: Self.background))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16)
        }

        private var title: String {
            if #available(macOS 15, *) { return "Exporting Your Passwords" }
            return "Exporting Safari Passwords"
        }

        @ViewBuilder private var instructions: some View {
            if #available(macOS 15, *) {
                // macOS 15 moved password export out of Safari. Keep the same
                // help owner and three-step composition, with current commands;
                // do not present Ventura's screenshot as the current interface.
                VStack(alignment: .leading, spacing: 32) {
                    instruction(1, title: "Open Passwords", detail: "Open Apple’s Passwords app and unlock it yourself.")
                    instruction(2, title: "Export your passwords", detail: "Choose File → Export All Passwords to File, then save the CSV.")
                    instruction(3, title: "Bring the file to Parc", detail: "Close this help and drop the exported CSV onto the password-import area, or click it to choose the file.")
                    Text("The exported CSV contains readable passwords. Parc can move it to Trash after supported passwords are confirmed. Passkeys and verification codes are not imported.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 24)
            } else {
                SafariIllustration()
            }
        }

        private func instruction(_ number: Int, title: String, detail: String) -> some View {
            HStack(alignment: .top, spacing: 16) {
                Text(String(number)).font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .background(Color(nsColor: OnboardingPasswordPalette.background), in: Circle())
                    .foregroundColor(Color(nsColor: OnboardingPasswordPalette.foreground))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 20, weight: .semibold))
                    Text(detail).font(.system(size: 14, weight: .light)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }

        private static let background = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(displayP3Red: 0.082, green: 0.110, blue: 0.188, alpha: 1)
                : NSColor(displayP3Red: 0.980, green: 0.984, blue: 1, alpha: 1)
        }
    }

    ///
    /// Its GrayA4/GrayA5 surfaces change on hover/press without a scale effect.
    private struct HelpCloseButtonStyle: ButtonStyle {
        @Environment(\.colorScheme) private var colorScheme
        @State private var hovered = false

        func makeBody(configuration: Configuration) -> some View {
            let dark = colorScheme == .dark
            let opacity = configuration.isPressed ? (dark ? 0.103 : 0.090)
                : hovered ? (dark ? 0.077 : 0.071) : 0
            return configuration.label
                .background((dark ? Color.white : Color.black).opacity(opacity),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .onHover { hovered = $0 }
        }
    }

    private struct SafariIllustration: View {
        @Environment(\.colorScheme) private var colorScheme
        var body: some View {
            if let url = Bundle.main.url(forResource: colorScheme == .dark ? "safari-passwords-dark" : "safari-passwords-light",
                                         withExtension: "png", subdirectory: "Onboarding"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable()
                    .accessibilityLabel("In Safari, open Settings, select Passwords and unlock, then use the options menu to Export All Passwords.")
            } else {
                Text("In Safari, open Settings → Passwords and unlock. Use the options menu to Export All Passwords, save the CSV, then return to Parc.")
                    .font(.system(size: 20)).padding(24)
            }
        }
    }
}
