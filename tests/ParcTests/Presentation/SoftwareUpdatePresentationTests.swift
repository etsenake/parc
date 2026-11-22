import AppKit
import SwiftUI
import Testing
@testable import ParcCore
@testable import Parc

struct SoftwareUpdateBannerTests {
    private let old = AppVersion(version: "1.8.2", build: "22")
    private let new = AppVersion(version: "1.9.0", build: "23")

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @MainActor private func upgraded(in directory: URL) -> SoftwareUpdateBanner {
        SoftwareUpdateBanner().launch(in: directory, existingData: false, current: old)
        return launch(in: directory)
    }

    @MainActor private func launch(in directory: URL) -> SoftwareUpdateBanner {
        let banner = SoftwareUpdateBanner()
        banner.launch(in: directory, existingData: true, current: new)
        return banner
    }

    @Test @MainActor func theFirstLaunchHasNoCompletedUpdate() throws {
        try withDirectory { directory in
            let banner = SoftwareUpdateBanner()
            banner.launch(in: directory, existingData: false, current: new)
            #expect(banner.completedUpdate == nil)
        }
    }

    @Test @MainActor func anUnshownBannerReturnsOnRelaunch() throws {
        try withDirectory { directory in
            _ = upgraded(in: directory)
            #expect(launch(in: directory).completedUpdate == new)
        }
    }

    @Test @MainActor func markingTheBannerShownKeepsItAvailableForThisRun() throws {
        try withDirectory { directory in
            let banner = upgraded(in: directory)
            banner.markCompletedUpdateShown()
            #expect(banner.completedUpdate == new)
            #expect(banner.updatedFrom == old)
        }
    }

    @Test @MainActor func aShownBannerDoesNotReturnOnRelaunch() throws {
        try withDirectory { directory in
            upgraded(in: directory).markCompletedUpdateShown()
            #expect(launch(in: directory).completedUpdate == nil)
        }
    }

    @Test @MainActor func openingTheCompletedUpdateHandsOffItsVersionRange() throws {
        try withDirectory { directory in
            let banner = upgraded(in: directory)
            var opened: [String] = []
            banner.openCompletedReleaseNotes(available: true) { opened.append($0) }
            #expect(opened == ["parc://whats-new/#from=1.8.2&to=1.9.0"])
            #expect(banner.completedUpdate == nil)
        }
    }

    @Test @MainActor func openingReleaseNotesFromTheMenuUsesThePlainPage() {
        var opened: [String] = []
        SoftwareUpdateBanner.openReleaseNotes(available: true) { opened.append($0) }
        #expect(opened == ["parc://whats-new/"])
    }

    @Test @MainActor func missingReleaseNotesDoNotOpenATab() {
        SoftwareUpdateBanner.openReleaseNotes(available: false) { _ in Issue.record("Opened unavailable release notes") }
    }
}

struct SoftwareUpdateWindowTests {
    private let info = ["CFBundleName": "Parc", "CFBundleShortVersionString": "1.8.2", "CFBundleVersion": "22"]

    @Test @MainActor func anUpToDateWindowOffersOnlyClose() {
        let (_, primary, secondary) = SoftwareUpdateWindow.content(style: .upToDate, info: info, icon: NSImage())
        #expect(primary.title == "Close")
        #expect(secondary == nil)
    }

    @Test @MainActor func theUpToDateWindowShowsTheRunningVersion() {
        let (content, _, _) = SoftwareUpdateWindow.content(style: .upToDate, info: info, icon: NSImage())
        let labels = content.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }.map(\.stringValue)
        #expect(labels == ["Parc", "1.8.2 (22)", "Your browser is up to date"])
    }

    @Test @MainActor func theUpToDateWindowCentersTheCloseButton() {
        let (content, primary, _) = SoftwareUpdateWindow.content(style: .upToDate, info: info, icon: NSImage())
        content.frame.size = content.fittingSize
        content.layoutSubtreeIfNeeded()
        #expect(primary.frame.size == NSSize(width: 170, height: 48))
        #expect(primary.frame.midX == content.bounds.midX)
    }

    @Test @MainActor func anAvailableUpdateOffersDownloadAndADeferredReminder() {
        let (_, primary, secondary) = SoftwareUpdateWindow.content(
            style: .update(prompt: "Would you like to download v1.9.0?", action: "Download", title: nil, notes: nil),
            info: info, icon: NSImage())
        #expect(primary.title == "Download")
        #expect(secondary?.title == "Remind me Later")
    }
}

struct UpdateReadyCardTests {
    @Test @MainActor func theCollapsedBannerLeavesOnlyTheTitleInTheKeyLoop() {
        let card = UpdateReadyCard(frame: .zero)
        #expect(card.keyViewControls.map { $0.accessibilityLabel() } == ["New Parc Version Available"])
        #expect(card.keyViewControls.allSatisfy { !$0.acceptsFirstResponder })
    }

    @Test @MainActor func pressingTheTitleRevealsTheUpdateActions() throws {
        let card = UpdateReadyCard(frame: .zero)
        card.setInteractionEnabled(true)
        let title = try #require(card.keyViewControls.first as? UpdateBannerKeyStop)
        var heightChanged = false
        card.onHeightChange = { heightChanged = true }
        title.press()
        #expect(card.keyViewControls.map { $0.accessibilityLabel() } == ["Automatic Updates", "Restart and Update"])
        #expect(heightChanged)
        #expect(!title.isAccessibilityElement())
    }

    @Test @MainActor func collapsingTheCardReturnsTheTitleToTheKeyLoop() throws {
        let card = UpdateReadyCard(frame: .zero)
        card.setInteractionEnabled(true)
        let title = try #require(card.keyViewControls.first as? UpdateBannerKeyStop)
        title.press()
        card.collapse()
        #expect(card.keyViewControls.first === title)
        #expect(title.isEnabled)
    }

    @Test(arguments: [true, false]) @MainActor func automaticUpdateStateReachesVoiceOver(enabled: Bool) throws {
        let card = UpdateReadyCard(frame: .zero)
        card.setInteractionEnabled(true)
        let title = try #require(card.keyViewControls.first as? UpdateBannerKeyStop)
        title.press()
        card.setAutomaticUpdates(enabled)
        let stop = try #require(card.keyViewControls.first)
        #expect(stop.accessibilityValue() as? String == (enabled ? "On" : "Off"))
    }
}

struct UpdateCompleteCardTests {
    @Test @MainActor func theCompletedUpdateOffersDismissAndReleaseNotesInOrder() {
        let card = UpdateCompleteCard(frame: .zero)
        #expect(card.keyViewControls.map { $0.accessibilityLabel() } == ["Dismiss", "See What’s New"])
    }

    @Test(arguments: [false, true]) @MainActor func bannerVisibilityControlsKeyboardAndHover(enabled: Bool) {
        let card = UpdateCompleteCard(frame: .zero)
        card.setInteractionEnabled(!enabled)
        card.setInteractionEnabled(enabled)
        #expect(card.model.interactive == enabled)
        #expect(card.keyViewControls.allSatisfy { ($0 as? NSControl)?.isEnabled == enabled })
    }

    @Test(arguments: [false, true]) @MainActor func theReleaseNotesRowUsesTheSpacesHoverColor(dark: Bool) throws {
        let card = UpdateCompleteCard(frame: .zero)
        let color = try #require(ThemeColor(hex: "B9B5D4"))
        let palette = ThemeChromePalette(theme: .singleColor(color), isDark: dark)
        card.applyPalette(palette)
        #expect(card.model.hover == Color(nsColor: palette.hover))
    }

    @Test @MainActor func aSaturatedThemeKeepsItsOwnGradientColor() throws {
        let theme = SpaceTheme.singleColor(try #require(ThemeColor(hex: "0000FF")))
        #expect(UpdateCompleteModel.gradientBase(ThemeChromePalette(theme: theme, isDark: false)) != .controlAccentColor)
    }
}

struct SoftwareUpdateDownloadProgressTests {
    @MainActor private final class ProgressIndicator: NSProgressIndicator {
        var starts = 0
        var stops = 0
        var modeWrites = 0
        override var isIndeterminate: Bool {
            get { super.isIndeterminate }
            set { modeWrites += 1; super.isIndeterminate = newValue }
        }
        override func startAnimation(_ sender: Any?) { starts += 1 }
        override func stopAnimation(_ sender: Any?) { stops += 1 }
    }

    @MainActor private func show(_ received: UInt64, in view: SoftwareUpdateStatusView) {
        var download = SoftwareUpdateDownloadProgress()
        download.expect(227_500_000)
        download.receive(received)
        let display = download.display
        view.show(status: display.text, action: "Cancel", progress: display.fraction, widthTemplate: display.widthTemplate)
        view.layoutSubtreeIfNeeded()
    }

    @Test(arguments: [UInt64(100_000), 9_900_000, 10_000_000, 99_900_000, 100_000_000, 202_800_000, 227_500_000])
    @MainActor func advancingTheDownloadKeepsTheLabelAndBarInPlace(received: UInt64) {
        let view = SoftwareUpdateStatusView(icon: NSImage())
        show(0, in: view)
        let counter = view.status.frame
        let bar = view.progress.frame
        show(received, in: view)
        #expect(view.status.frame == counter)
        #expect(view.progress.frame == bar)
        #expect(view.status.alignment == .right)
        #expect(view.progress.doubleValue == Double(received) / 227_500_000)
    }

    @Test @MainActor func repeatingUnknownProgressDoesNotRestartItsAnimation() {
        let indicator = ProgressIndicator()
        let view = SoftwareUpdateStatusView(icon: NSImage(), progress: indicator)
        view.show(status: "Downloading...", action: "Cancel", progress: nil)
        view.show(status: "Downloading...", action: "Cancel", progress: nil)
        #expect(indicator.starts == 1)
    }

    @Test(arguments: [0.1, 0.4, 202.8 / 227.5, 1.0])
    @MainActor func measuredProgressUpdatesWithoutResettingTheIndicator(value: Double) {
        let indicator = ProgressIndicator()
        let view = SoftwareUpdateStatusView(icon: NSImage(), progress: indicator)
        view.show(status: "Downloading", action: "Cancel", progress: 0)
        let writes = indicator.modeWrites
        let stops = indicator.stops
        view.show(status: "Downloading", action: "Cancel", progress: value)
        #expect(indicator.doubleValue == value)
        #expect(indicator.modeWrites == writes)
        #expect(indicator.stops == stops)
    }

    @Test @MainActor func preparationStartsItsOwnUnmeasuredStage() {
        let indicator = ProgressIndicator()
        let view = SoftwareUpdateStatusView(icon: NSImage(), progress: indicator)
        view.show(status: "Downloading", action: "Cancel", progress: 1)
        view.show(status: "Preparing…", action: "Cancel", progress: nil, enabled: false)
        #expect(indicator.isIndeterminate)
        #expect(!view.action.isEnabled)
    }

    @Test @MainActor func readinessFillsTheBarAndEnablesInstallation() {
        let view = SoftwareUpdateStatusView(icon: NSImage(), progress: ProgressIndicator())
        view.show(status: "Ready to Install", action: "Install and Relaunch", progress: 1)
        #expect(view.progress.doubleValue == 1)
        #expect(view.action.isEnabled)
    }
}
