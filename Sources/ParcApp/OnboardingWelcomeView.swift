import AppKit
import SwiftUI

struct OnboardingWelcomeView: View {
    let stage: OnboardingDraft.Stage
    let reduceMotion: Bool
    let onContinue: () -> Void
    var isLeaving = false
    @State private var contentStarted = false

    var body: some View {
        ZStack {
            if contentStarted || OnboardingExperience.welcomeShowsContent(stage: stage, reduceMotion: reduceMotion) {
                OnboardingWelcomeContent(reduceMotion: reduceMotion, isLeaving: isLeaving, onContinue: onContinue)
                    .onAppear { contentStarted = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(isLeaving)
    }
}

private struct OnboardingWelcomeContent: View {
    let reduceMotion: Bool
    let isLeaving: Bool
    let onContinue: () -> Void
    @State private var opacity = 0.0
    @State private var blur = 25.0
    @State private var scale = 0.5
    @State private var offset = 250.0
    @State private var motionSettled = false
    @State private var headlineVisible = false
    @State private var buttonVisible = false
    @State private var advancing = false
    @State private var advanceTask: Task<Void, Never>?

    private let spring = Animation.spring(response: 1.25, dampingFraction: 0.9, blendDuration: 0)
    private var logo: NSImage {
        ParcBrandMark.image(.borderless) ?? NSApp.applicationIconImage
    }

    var body: some View {
        ZStack {
            Image(nsImage: logo).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 101)
                .opacity(opacity).blur(radius: blur).scaleEffect(scale).offset(y: offset)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                OnboardingHeadline(visible: headlineVisible, reduceMotion: reduceMotion)
                Spacer().frame(height: 24)
                Button(action: continuePressed) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .blendMode(.destinationOut)
                        .padding(.horizontal, 24)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.8)))
                        .compositingGroup()
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(OnboardingProgressionButtonStyle(reduceMotion: reduceMotion))
                .disabled(!buttonVisible || advancing || isLeaving)
                .accessibilityLabel("Get started")
                .keyboardShortcut(.defaultAction)
                .opacity(buttonVisible ? 1 : 0)
                .blur(radius: buttonVisible ? 0 : 30)
                .offset(y: buttonVisible ? 0 : 125)
                .animation(reduceMotion ? nil : spring, value: buttonVisible)
                .allowsHitTesting(buttonVisible && !advancing)
                .accessibilityHidden(!buttonVisible)
                .accessibilityHint("Continue to setup")
            }.foregroundStyle(.white).padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if reduceMotion { settleMotion(); return }
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard !motionSettled else { return }
                withAnimation(spring) { opacity = 1; blur = 1; scale = 1; offset = 0 }
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard !motionSettled else { return }
                withAnimation(.linear(duration: 1.25)) { offset = -20 }
                try await Task.sleep(nanoseconds: 1_150_000_000)
                guard !motionSettled else { return }
                withAnimation(spring) { opacity = -1; blur = 25; scale = 0.5; offset = -350 }
                try await Task.sleep(nanoseconds: 850_000_000)
                headlineVisible = true
                try await Task.sleep(nanoseconds: 1_600_000_000)
                buttonVisible = true
            } catch { }
        }
        .onChange(of: reduceMotion) { reduced in
            if reduced { settleMotion() }
        }
        .onDisappear { advanceTask?.cancel(); advanceTask = nil }
    }

    private func settleMotion() {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            motionSettled = true
            opacity = 0; blur = 0; scale = 1; offset = 0
            headlineVisible = true; buttonVisible = true
        }
    }

    private func continuePressed() {
        guard buttonVisible, !advancing else { return }
        advancing = true
        advanceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                try Task.checkCancellation()
                onContinue()
                advancing = false
            } catch { advancing = false }
        }
    }
}

private struct OnboardingHeadline: View {
    let visible: Bool
    let reduceMotion: Bool
    private let title = "A browser for you."
    private let font = OnboardingArtwork.headlineFont

    var body: some View {
        HStack(spacing: -3) {
            ForEach(Array(title.enumerated()), id: \.offset) { index, character in
                Text(String(character)).font(Font(font))
                    .opacity(visible ? 1 : 0)
                    .blur(radius: visible ? 0 : 30)
                    .offset(y: visible ? 0 : 75 + font.ascender - font.descender + font.leading)
                    .animation(reduceMotion ? nil : .spring(response: 1.25, dampingFraction: 0.9, blendDuration: 0)
                        .delay(character == "." ? 0.65 : Double(index) * 0.03), value: visible)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHidden(!visible)
    }
}
