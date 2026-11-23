import AppKit
import Combine
import ParcCore
import ParcEngine
import ParcKit
import ParcNotes
import ParcEasels
import ParcLibrary
import ParcCommandBar
import ParcSidebar
import ParcSettings

extension BrowserWindowController {
    private func embeddedCaptureOwner(_ identity: UUID) -> (UUID, EmbeddedPagePool, PCBrowserView)? {
        for (tabID, pool) in embeddedPagePools {
            if let view = pool.ownedViews[identity] { return (tabID, pool, view) }
        }
        return nil
    }
    private func canUseCaptureOwner(_ id: UUID) -> Bool {
        let parent = embeddedCaptureOwner(id)?.0 ?? id
        return ownership.canUse(parent, owner: presentationID) && !transferringTabIDs.contains(parent)
    }
    private func captureBrowser(_ id: UUID) -> PCBrowserView? {
        browsers[id] ?? peeks.values.first(where: { $0.identity == id })?.browser ?? embeddedCaptureOwner(id)?.2
    }
    func refreshMiniPlayers(force: Bool = false) {
        let (signature, pendingAdmission) = miniPlayerSourceSignature()
        if !force, !pendingAdmission, signature == lastMiniPlayerSourceSignature { return }
        lastMiniPlayerSourceSignature = signature
        onMiniPlayerSourceChange?()
    }

    private func miniPlayerSourceSignature() -> (String, Bool) {
        var parts: [String] = [
            canPresentMiniPlayers ? "P1" : "P0",
            (isClosing || wholeWindowClose || windowClosePending || windowCloseApproved) ? "W1" : "W0",
            "H\(canPresentMiniPlayer(offTheRecord: false) ? 1 : 0)\(canPresentMiniPlayer(offTheRecord: true) ? 1 : 0)",
        ]
        func appendGate(_ prefix: String, _ ids: Set<UUID>) {
            parts.append(prefix + ids.map(\.uuidString).sorted().joined(separator: ","))
        }
        appendGate("C", closingTabIDs)
        appendGate("T", transferringTabIDs)
        appendGate("R", modelRetirementIDs)
        appendGate("K", peekRetirementParents)
        let statusSel = #selector(getter: PCNativePage.mediaSessionStatus)
        let revisionSel = #selector(getter: PCNativePage.mediaControlsRevision)
        let audioSel = #selector(getter: PCNativePage.tabAudioState)
        var pendingAdmission = false
        for id in browsers.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let view = browsers[id], view.window === window,
                  let profileID = browserProfiles[id],
                  let page = view.nativePage, !page.isClosed else { continue }
            let pageSig = miniPlayerPageSignature(kind: "b", id: id, profileID: profileID,
                                                  page: page, statusSel: statusSel,
                                                  revisionSel: revisionSel, audioSel: audioSel)
            if pageSig.pendingAdmission { pendingAdmission = true }
            parts.append(pageSig.token)
        }
        for peek in peeks.values.sorted(by: { $0.identity.uuidString < $1.identity.uuidString }) {
            guard peek.browser.window === window, !peek.page.isClosed,
                  let profileID = peekProfileID(peek) else { continue }
            let parentPage = browsers[peek.parentTabID]?.nativePage
            let pageSig = miniPlayerPageSignature(kind: "p", id: peek.identity, profileID: profileID,
                                                  page: peek.page, statusSel: statusSel,
                                                  revisionSel: revisionSel, audioSel: audioSel)
            if pageSig.pendingAdmission { pendingAdmission = true }
            parts.append(pageSig.token
                + "|parent:\(peek.parentTabID.uuidString)|pending:\(peek.closePending ? 1 : 0)"
                + "|ppage:\(parentPage?.identifier ?? "-")|pmatch:\(parentPage === peek.parentPage ? 1 : 0)")
        }
        return (parts.joined(separator: ";"), pendingAdmission)
    }

    private func miniPlayerPageSignature(kind: String, id: UUID, profileID: UUID,
                                         page: PCNativePage, statusSel: Selector,
                                         revisionSel: Selector, audioSel: Selector)
        -> (token: String, pendingAdmission: Bool) {
        let status = page.responds(to: statusSel) ? page.mediaSessionStatus.rawValue : -1
        let revision = page.responds(to: revisionSel) ? page.mediaControlsRevision : 0
        var part = "\(kind):\(id.uuidString)|\(profileID.uuidString)|\(page.identifier)|s\(status)|g\(revision)"
        if page.responds(to: audioSel), let audio = page.tabAudioState,
           page.responds(to: #selector(PCNativePage.tabAudioIsMuted(_:))),
           page.responds(to: #selector(PCNativePage.tabAudioIsAudible(_:))) {
            part += "|tm\(page.tabAudioIsMuted(audio) ? 1 : 0)|ta\(page.tabAudioIsAudible(audio) ? 1 : 0)"
        } else {
            part += "|tm-|ta-"
        }
        if let media = page.mediaState {
            part += "|m\(media.identifier)|a\(media.admissionSequence)|o\(media.isOffTheRecord ? 1 : 0)"
            part += "|play\(media.playing ? 1 : 0)|mute\(media.muted ? 1 : 0)|vol\(Int((media.volume * 100).rounded()))"
            part += "|t\(media.title)|u\(media.sourceURL)"
            part += "|pp\(media.canPlayPause ? 1 : 0)|pv\(media.hasPreviousTrack ? 1 : 0)|nx\(media.hasNextTrack ? 1 : 0)"
            part += "|sv\(media.canSetVolume ? 1 : 0)|mic\(media.canToggleMicrophone ? 1 : 0)|cam\(media.canToggleCamera ? 1 : 0)"
            part += "|mo\(media.microphoneOn ? 1 : 0)|co\(media.cameraOn ? 1 : 0)"
            part += "|pip\(media.canEnterPictureInPicture ? 1 : 0)"
            if let icon = media.icon, let data = icon.tiffRepresentation {
                var hasher = Hasher()
                hasher.combine(data.count)
                hasher.combine(data)
                part += "|icon\(hasher.finalize())"
            } else {
                part += "|icon0"
            }
            return (part, false)
        }
        part += "|m-"
        let pending = status != PCNativeMediaSessionStatus.inactive.rawValue && status >= 0
        return (part, pending)
    }
    func prepareMiniPlayerSourcesForAdmission() {
        let closingWindow = isClosing || wholeWindowClose || windowClosePending || windowCloseApproved
        for (id, view) in browsers where !transferringTabIDs.contains(id) {
            if closingWindow || closingTabIDs.contains(id) || modelRetirementIDs.contains(id) {
                view.nativePage?.withdrawMediaState()
            }
        }
        for peek in peeks.values where !transferringTabIDs.contains(peek.parentTabID) {
            if closingWindow || peek.closePending || closingTabIDs.contains(peek.parentTabID) ||
                modelRetirementIDs.contains(peek.parentTabID) || peekRetirementParents.contains(peek.parentTabID) ||
                browsers[peek.parentTabID]?.nativePage !== peek.parentPage {
                peek.page.withdrawMediaState()
            }
        }
    }
    func applyMiniPlayers(_ items: [MiniPlayerItem]) {
        let current = canPresentMiniPlayers ? items.filter { $0.valid() }.sorted {
            $0.state.admissionSequence < $1.state.admissionSequence
        } : []
        sidebar.updateMiniPlayers(current)
    }
    private var canPresentMiniPlayers: Bool {
        !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose &&
            !windowClosePending && !windowCloseApproved && window != nil
    }
    private func canPresentMiniPlayer(offTheRecord: Bool) -> Bool {
        guard canPresentMiniPlayers, let window, let binding = nativeBinding,
              binding.window === window, PCNativeBrowserApplication.window(forNativeWindow: window) === binding,
              binding.browsingContextKind != .mixed, binding.isPrivateBrowsing == offTheRecord else { return false }
        let kind = binding.browsingContextKind
        return kind == .unavailable || kind == (offTheRecord ? .offTheRecord : .regular)
    }
    func miniPlayerItems(for host: BrowserWindowController) -> [MiniPlayerItem] {
        guard canPresentMiniPlayers, host.canPresentMiniPlayers,
              let hostWindow = host.window else { return [] }
        let hostLease = MiniPlayerHostLease(hostWindow)
        var items: [MiniPlayerItem] = []
        for id in browsers.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let view = browsers[id], view.window === window,
                  let profileID = browserProfiles[id],
                  liveTabModels[id]?.profileID == profileID,
                  ownership.canUse(id, owner: presentationID),
                  !transferringTabIDs.contains(id), !closingTabIDs.contains(id), !modelRetirementIDs.contains(id),
                  let page = view.nativePage, !page.isClosed, let state = page.admitMediaState(),
                  host.canPresentMiniPlayer(offTheRecord: state.isOffTheRecord),
                  page.canPresentMediaState(state, in: hostWindow) else { continue }
            let offTheRecord = state.isOffTheRecord
            let episodeID = state.identifier
            let valid = { [weak self, weak host, weak view, weak page, weak hostWindow] in
                guard let self, let host, let hostWindow, let view, let page,
                      host.window === hostWindow, host.canPresentMiniPlayer(offTheRecord: offTheRecord),
                      self.canPresentMiniPlayers,
                      !self.isClosing, !self.wholeWindowClose,
                      !self.windowClosePending, !self.windowCloseApproved,
                      self.browsers[id] === view, self.liveTabModels[id]?.profileID == profileID,
                      self.browserProfiles[id] == profileID, view.nativePage === page,
                      view.window === self.window, !page.isClosed,
                      self.ownership.canUse(id, owner: self.presentationID),
                      !self.transferringTabIDs.contains(id), !self.closingTabIDs.contains(id),
                      !self.modelRetirementIDs.contains(id), let current = page.mediaState,
                      current.identifier == episodeID,
                      page.canPresentMediaState(current, in: hostWindow) else { return false }
                return true
            }
            items.append(MiniPlayerItem(page: page, state: state, icon: state.icon, host: hostLease,
                valid: valid, reveal: { [weak self, weak page, weak hostWindow] in
                    guard valid(), let self, let page, let state = page.mediaState, let hostWindow, hostWindow.isKeyWindow,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: hostWindow),
                          page.canRevealMediaState(state, in: hostWindow), let window = self.window else { return }
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    guard valid(), page.canContinueMediaReveal(state, in: hostWindow) else { return }
                    window.makeKeyAndOrderFront(nil)
                    guard valid(), page.canContinueMediaReveal(state, in: hostWindow), window.isKeyWindow, NSApp.isActive,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
                    self.closeLibrary(restoreFocus: false)
                    guard valid(), page.canContinueMediaReveal(state, in: hostWindow), window.isKeyWindow,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
                    _ = self.selectTab(id)
                }))
        }
        for peek in peeks.values.sorted(by: { $0.identity.uuidString < $1.identity.uuidString }) {
            guard let profileID = peekProfileID(peek),
                  peek.browser.window === window, !peek.closePending, !peek.page.isClosed,
                  peeks[peek.page.identifier] === peek,
                  browsers[peek.parentTabID]?.nativePage === peek.parentPage,
                  ownership.canUse(peek.parentTabID, owner: presentationID),
                  !closingTabIDs.contains(peek.parentTabID), !modelRetirementIDs.contains(peek.parentTabID),
                  !peekRetirementParents.contains(peek.parentTabID), !transferringTabIDs.contains(peek.parentTabID),
                  let state = peek.page.admitMediaState(),
                  host.canPresentMiniPlayer(offTheRecord: state.isOffTheRecord),
                  peek.page.canPresentMediaState(state, in: hostWindow) else { continue }
            let offTheRecord = state.isOffTheRecord
            let episodeID = state.identifier
            let valid = { [weak self, weak host, weak hostWindow, weak peek] in
                guard let self, let host, let hostWindow, let peek,
                      host.window === hostWindow, host.canPresentMiniPlayer(offTheRecord: offTheRecord),
                      self.canPresentMiniPlayers,
                      !self.isClosing, !self.wholeWindowClose,
                      !self.windowClosePending, !self.windowCloseApproved,
                      !peek.closePending, !peek.page.isClosed,
                      self.peeks[peek.page.identifier] === peek,
                      self.browsers[peek.parentTabID]?.nativePage === peek.parentPage,
                      self.peekProfileID(peek) == profileID,
                      peek.browser.window === self.window,
                      self.ownership.canUse(peek.parentTabID, owner: self.presentationID),
                      !self.closingTabIDs.contains(peek.parentTabID),
                      !self.modelRetirementIDs.contains(peek.parentTabID),
                      !self.peekRetirementParents.contains(peek.parentTabID),
                      !self.transferringTabIDs.contains(peek.parentTabID),
                      let current = peek.page.mediaState, current.identifier == episodeID,
                      peek.page.canPresentMediaState(current, in: hostWindow) else { return false }
                return true
            }
            items.append(MiniPlayerItem(page: peek.page, state: state, icon: state.icon, host: hostLease,
                valid: valid, reveal: { [weak self, weak peek, weak hostWindow] in
                    guard valid(), let self, let peek, let state = peek.page.mediaState, let hostWindow, hostWindow.isKeyWindow,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: hostWindow),
                          peek.page.canRevealMediaState(state, in: hostWindow), let window = self.window else { return }
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    guard valid(), peek.page.canContinueMediaReveal(state, in: hostWindow) else { return }
                    window.makeKeyAndOrderFront(nil)
                    guard valid(), peek.page.canContinueMediaReveal(state, in: hostWindow), window.isKeyWindow, NSApp.isActive,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
                    self.closeLibrary(restoreFocus: false)
                    guard valid(), peek.page.canContinueMediaReveal(state, in: hostWindow), window.isKeyWindow,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
                    if self.revealPeekHost(peek), valid(),
                       peek.page.canContinueMediaReveal(state, in: hostWindow) { peek.focus() }
                }))
        }
        return items
    }

    private func liveShareableTabs() -> Set<UUID> {
        Set(browsers.compactMap { id, browser in
            ownership.canUse(id, owner: presentationID) && browser.window === window
                && browser.canShareThisTabInstead ? id : nil
        })
    }

    private func liveTabAudio() -> [UUID: SidebarTabAudio] {
        browsers.reduce(into: [UUID: SidebarTabAudio]()) { result, pair in
            let (id, browser) = pair
            guard browser.window === window, ownership.canUse(id, owner: presentationID),
                  browserProfiles[id] == activeProfileID, let page = browser.nativePage,
                  page.responds(to: #selector(getter: PCNativePage.tabAudioState)),
                  page.responds(to: #selector(PCNativePage.tabAudioIsAudible(_:))),
                  page.responds(to: #selector(PCNativePage.tabAudioIsMuted(_:))),
                  page.responds(to: #selector(PCNativePage.toggleTabAudioMuted(_:))),
                  let state = page.tabAudioState else { return }
            result[id] = SidebarTabAudio(lease: state, audible: page.tabAudioIsAudible(state),
                                         muted: page.tabAudioIsMuted(state))
        }
    }

    private func shareableAudioFingerprint(shareable: Set<UUID>,
                                           audio: [UUID: SidebarTabAudio]) -> String {
        let sharePart = shareable.map(\.uuidString).sorted().joined(separator: ",")
        let audioPart = audio.keys.sorted { $0.uuidString < $1.uuidString }.map { id in
            guard let entry = audio[id] else { return id.uuidString }
            return [
                id.uuidString,
                String(describing: ObjectIdentifier(entry.lease)),
                entry.audible ? "1" : "0",
                entry.muted ? "1" : "0",
            ].joined(separator: "\u{1f}")
        }.joined(separator: ";")
        return sharePart + "\u{1e}" + audioPart
    }

    func publishedShareableAndAudio()
        -> (shareable: Set<UUID>, audio: [UUID: SidebarTabAudio], changed: Bool) {
        let shareable = liveShareableTabs()
        let audio = liveTabAudio()
        let fingerprint = shareableAudioFingerprint(shareable: shareable, audio: audio)
        if fingerprint == lastShareableAudioFingerprint {
            return (lastAppliedShareable, lastAppliedAudio, false)
        }
        return (shareable, audio, true)
    }

    func rememberAppliedShareableAudio(shareable: Set<UUID>,
                                               audio: [UUID: SidebarTabAudio]) {
        lastShareableAudioFingerprint = shareableAudioFingerprint(shareable: shareable, audio: audio)
        lastAppliedShareable = shareable
        lastAppliedAudio = audio
    }

    private func capturePresentationFingerprint(
        _ presentations: [UUID: CaptureIndicatorPresentation]
    ) -> String {
        presentations.keys.sorted { $0.uuidString < $1.uuidString }.map { id in
            guard let p = presentations[id] else { return id.uuidString }
            return [
                id.uuidString,
                p.camera ? "1" : "0",
                p.microphone ? "1" : "0",
                p.tab ? "1" : "0",
                p.window ? "1" : "0",
                p.display ? "1" : "0",
                p.mirrored ? "1" : "0",
                p.shared ? "1" : "0",
            ].joined(separator: "\u{1f}")
        }.joined(separator: ";")
    }

    func refreshCaptureIndicators() {
        var next: [UUID: CaptureIndicatorPresentation] = [:]
        for (id, browser) in browsers {
            guard ownership.canUse(id, owner: presentationID),
                  !transferringTabIDs.contains(id), browser.window === window,
                  browserProfiles[id] == liveTabModels[id]?.profileID,
                  let state = browser.captureState, state.active else { continue }
            next[id] = CaptureIndicatorPresentation(state)
        }
        for peek in peeks.values where !peek.page.isClosed && peek.browser.window === window {
            if let state = peek.browser.captureState, state.active { next[peek.identity] = CaptureIndicatorPresentation(state) }
        }
        for pool in embeddedPagePools.values {
            for (identity, view) in pool.ownedViews {
                if view.window === window, let state = view.captureState, state.active {
                    next[identity] = CaptureIndicatorPresentation(state)
                }
            }
        }
        let fingerprint = capturePresentationFingerprint(next)
        if fingerprint == lastCapturePresentationFingerprint {
            return
        }
        capturePresentations = next
        lastCapturePresentationFingerprint = fingerprint
    }

    func refreshFavoriteOverlays(from state: BrowserState) {
        let fingerprint = favoriteOverlayPresentationFingerprint(state)
        if FavoriteOverlayPresentationSkip.shouldSkip(previous: lastFavoriteOverlayFingerprint,
                                                      next: fingerprint) {
            return
        }
        lastFavoriteOverlayFingerprint = fingerprint
        sidebar.updateFavoriteOverlays(favoriteOverlayStates(state))
    }

    private func favoriteOverlayPresentationFingerprint(_ state: BrowserState) -> String {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose else {
            return FavoriteOverlayPresentationSkip.gatedToken
        }
        let profileID = activeProfileID
        let splitIDs = Set(SidebarSplitItems.groups(in: state, spaceID: state.activeSpaceID).flatMap(\.tabIDs))
        let sessionStatus = #selector(getter: PCNativePage.mediaSessionStatus)
        var parts: [String] = []
        for tab in state.openTabs where tab.kind == .favorite && tab.profileID == profileID && !splitIDs.contains(tab.id) {
            let id = tab.id
            guard let view = browsers[id], view.window === window, browserProfiles[id] == profileID,
                  ownership.canUse(id, owner: presentationID),
                  !transferringTabIDs.contains(id), !closingTabIDs.contains(id),
                  let page = view.nativePage, !page.isClosed else { continue }
            var recording = false
            if let capture = capturePresentations[id] {
                recording = FavoriteTileOverlayRules.isRecording(camera: capture.camera,
                    microphone: capture.microphone, tab: capture.tab, window: capture.window,
                    display: capture.display, mirrored: capture.mirrored, shared: capture.shared)
            }
            var badge: String?
            if !peekRetirementParents.contains(id), let peek = peeks.values
                .filter({ $0.parentTabID == id && $0.parentPage === page && !$0.page.isClosed
                    && !$0.closePending && $0.browser.window === window })
                .min(by: { $0.identity.uuidString < $1.identity.uuidString }) {
                badge = FavoriteOverlayPresentationSkip.badgeToken(
                    peekID: peek.identity, tiffData: peek.page.favicon?.tiffRepresentation)
            }
            var developerTab = false
            if let host = page.developerModeSiteHost {
                developerTab = DeveloperModePreferences.shared.isEnabled(host: host)
            }
            let music: Bool
            if FavoriteOverlayPresentationSkip.needsMediaSessionRead(
                savedURL: tab.savedURL, engineRespondsToStatus: page.responds(to: sessionStatus)) {
                let status = FavoriteMediaSessionStatus(rawStatus: page.mediaSessionStatus.rawValue)
                music = FavoriteTileOverlayRules.showsMusic(singlePage: true, status: status,
                                                            savedURL: tab.savedURL)
            } else {
                music = false
            }
            parts.append(FavoriteOverlayPresentationSkip.tileToken(
                id: id, pageIdentifier: page.identifier, recording: recording,
                badge: badge, developerTab: developerTab, music: music))
        }
        return parts.sorted().joined(separator: ";")
    }

    private func favoriteOverlayStates(_ state: BrowserState) -> [UUID: FavoriteTileOverlayState] {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose else {
            favoriteBadgeIcons = [:]; return [:]
        }
        let profileID = activeProfileID
        let splitIDs = Set(SidebarSplitItems.groups(in: state, spaceID: state.activeSpaceID).flatMap(\.tabIDs))
        let sessionStatus = #selector(getter: PCNativePage.mediaSessionStatus)
        var overlays: [UUID: FavoriteTileOverlayState] = [:]
        var badgeIcons: [UUID: (image: NSImage, data: Data)] = [:]
        defer { favoriteBadgeIcons = badgeIcons }
        for tab in state.openTabs where tab.kind == .favorite && tab.profileID == profileID && !splitIDs.contains(tab.id) {
            let id = tab.id
            guard let view = browsers[id], view.window === window, browserProfiles[id] == profileID,
                  ownership.canUse(id, owner: presentationID),
                  !transferringTabIDs.contains(id), !closingTabIDs.contains(id),
                  let page = view.nativePage, !page.isClosed else { continue }
            var overlay = FavoriteTileOverlayState()
            if let capture = capturePresentations[id] {
                overlay.recording = FavoriteTileOverlayRules.isRecording(camera: capture.camera,
                    microphone: capture.microphone, tab: capture.tab, window: capture.window,
                    display: capture.display, mirrored: capture.mirrored, shared: capture.shared)
            }
            if !peekRetirementParents.contains(id), let peek = peeks.values
                .filter({ $0.parentTabID == id && $0.parentPage === page && !$0.page.isClosed
                    && !$0.closePending && $0.browser.window === window })
                .min(by: { $0.identity.uuidString < $1.identity.uuidString }) {
                var favicon = peek.page.favicon
                if let icon = favicon, let data = icon.tiffRepresentation {
                    if let shown = favoriteBadgeIcons[peek.identity], shown.data == data { favicon = shown.image }
                    badgeIcons[peek.identity] = (favicon ?? icon, data)
                }
                overlay.badge = FavoriteTileBadge(favicon: favicon)
            }
            if let host = page.developerModeSiteHost {
                overlay.developerTab = DeveloperModePreferences.shared.isEnabled(host: host)
            }
            let listed = FavoriteTileOverlayRules.isMusicHost(URL(string: tab.savedURL)?.host)
            let status = listed && page.responds(to: sessionStatus)
                ? FavoriteMediaSessionStatus(rawStatus: page.mediaSessionStatus.rawValue) : nil
            overlay.music = FavoriteTileOverlayRules.showsMusic(singlePage: true, status: status, savedURL: tab.savedURL)
            if overlay != .none { overlays[id] = overlay }
        }
        return overlays
    }

    func captureOwnerIDs(of tabID: UUID) -> [UUID] {
        [tabID] + peeks.values.filter { $0.parentTabID == tabID }.map(\.identity)
            + Array(embeddedPagePool(forTabID: tabID)?.ownedViews.keys ?? Dictionary<UUID, PCBrowserView>().keys)
    }

    func showCaptureMenu(tabID: UUID, anchor: NSView) {
        guard let parent = window, anchor.window === parent, !isClosing,
              !wholeWindowClose, parent.attachedSheet == nil else { return }
        let menu = NSMenu()
        for id in captureOwnerIDs(of: tabID) {
            guard let browser = captureBrowser(id), browser.window === parent,
                  canUseCaptureOwner(id),
                  !transferringTabIDs.contains(id),
                  let page = browser.nativePage,
                  let state = browser.captureState, state.active else { continue }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let label = NSMenuItem(title: browser.title.isEmpty ? "Untitled tab" : browser.title, action: nil, keyEquivalent: "")
            menu.addItem(label)
            if let origin = browser.url?.host {
                menu.addItem(NSMenuItem(title: origin, action: nil, keyEquivalent: ""))
            }
            for detail in CaptureIndicatorPresentation(state).details {
                menu.addItem(NSMenuItem(title: detail, action: nil, keyEquivalent: ""))
            }
            func stopItem(_ title: String, sharing: Bool) {
                menu.addItem(MenuAction.item(title) { [weak self, weak browser, weak parent] in
                    guard let self, let browser, let parent,
                          self.window === parent, browser.window === parent,
                          self.captureBrowser(id) === browser, browser.nativePage === page,
                          self.canUseCaptureOwner(id),
                          !self.transferringTabIDs.contains(id), !self.isClosing,
                          !self.wholeWindowClose else { return }
                    _ = browser.stopCapture(state, sharing: sharing)
                    self.updateNavigation()
                })
            }
            if state.canStopSharing { stopItem("Stop sharing", sharing: true) }
            if state.canStopDevices {
                stopItem(state.camera && state.microphone ? "Stop camera and microphone" : state.camera ? "Stop camera" : "Stop microphone", sharing: false)
            }
            if !state.canStopSharing && !state.canStopDevices {
                menu.addItem(NSMenuItem(title: "Stop is controlled by the capture owner", action: nil, keyEquivalent: ""))
            }
            menu.addItem(MenuAction.item("Go to tab") { [weak self, weak browser] in
                guard let self, let browser, self.captureBrowser(id) === browser,
                      browser.nativePage === page, self.canUseCaptureOwner(id) else { return }
                if let owner = self.embeddedCaptureOwner(id) {
                    if self.selectTab(owner.0) { owner.1.reveal(page) }
                } else { self.selectTab(id) }
            })
        }
        guard !menu.items.isEmpty else { refreshCaptureIndicators(); return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
    }

    func prepareCaptureGesture(at point: NSPoint) -> PageCaptureGesture.Admission? {
        guard privateCaptureContextIsValid, pageCapture == nil, commandBar == nil, libraryView == nil,
              canOwnDownloadDialog(for: activeProfileID), let window, window.isKeyWindow,
              NSApp.isActive, window.attachedSheet == nil,
              let hit = rootView.hitTest(rootView.superview?.convert(point, from: nil) ?? point) else { return nil }
        let candidates: [PCBrowserView] = activePeek.map { _ in activePagePeek.map { [$0.browser] } ?? [] }
            ?? selectedTabIDs.compactMap { browsers[$0] }
        guard let browser = candidates.first(where: { browser in
            guard let native = browser.nativePage?.nativeView as? PCNativePageHost,
                  let content = native.contentView, !content.isHiddenOrHasHiddenAncestor else { return false }
            return hit === content || hit.isDescendant(of: content)
        }), let page = browser.nativePage else { return nil }
        let revision = browser.readerRevision, profileID = activeProfileID, spaceID = activeSpaceID
        guard (currentBrowser === browser || activateDeveloperPage(browser, page: page, revision: revision)),
              page.canCapture(in: window) else { return nil }
        let current: () -> Bool = { [weak self, weak browser, weak page, weak window] in
            guard let self, let browser, let page, let window else { return false }
            return self.window === window && window.isKeyWindow && NSApp.isActive
                && self.privateCaptureContextIsValid && self.pageCapture == nil && self.commandBar == nil && self.libraryView == nil
                && self.activeProfileID == profileID && self.activeSpaceID == spaceID
                && self.canOwnDownloadDialog(for: profileID) && window.attachedSheet == nil
                && browser.nativePage === page && browser.readerRevision == revision && !page.isClosed
                && page.nativeView.window === window && !page.nativeView.isHiddenOrHasHiddenAncestor
                && page.profilePath == self.store.independentEngineProfilePath(for: profileID)
                && PCNativeBrowserApplication.owner(of: page) === self.nativeBinding
                && (self.activePeek.map { ($0 as? PeekController)?.browser === browser && !$0.closePending }
                    ?? self.selectedTabIDs.contains { self.browsers[$0] === browser })
                && page.canCapture(in: window)
        }
        guard current() else { return nil }
        return PageCaptureGesture.Admission(isCurrent: current, begin: { [weak self, weak browser] in
            guard current(), let self, let browser,
                  self.currentBrowser === browser else { return nil }
            self.capturePage(.region)
            return self.pageCapture
        })
    }
    var privateCaptureContextIsValid: Bool {
        !isPrivateBrowsing || (nativeBinding?.isPrivateBrowsing == true && nativeBinding?.browsingContextKind == .offTheRecord)
    }
    var canCapturePage: Bool {
        guard privateCaptureContextIsValid else { return false }
        guard pageCapture == nil, let window, NSApp.isActive,
              window.isKeyWindow || (commandBar != nil && NSApp.mainWindow === window),
              canOwnDownloadDialog(for: activeProfileID), window.attachedSheet == nil,
              libraryView == nil, let id = currentTabID,
              !closingTabIDs.contains(id), !modelRetirementIDs.contains(id),
              !store.retiringTabIDs.contains(id),
              let browser = currentBrowser, let page = browser.nativePage, !page.isClosed,
              page.nativeView.window === window,
              page.profilePath == store.independentEngineProfilePath(for: activeProfileID),
              PCNativeBrowserApplication.owner(of: page) === nativeBinding else { return false }
        return page.canCapture(in: window)
    }
    func preparePageCaptureMenuItem(_ item: NSMenuItem, mode: PageCaptureController.Mode) -> Bool {
        item.representedObject = nil
        guard canCapturePage, let page = currentBrowser?.nativePage else { return false }
        item.representedObject = CaptureMenuRequest(owner: self, page: page, mode: mode)
        return true
    }
    func capturePage(from item: NSMenuItem) {
        guard let request = item.representedObject as? CaptureMenuRequest, request.owner === self,
              request.page === currentBrowser?.nativePage, request.profileID == activeProfileID,
              request.spaceID == activeSpaceID else { return }
        capturePage(request.mode)
    }
    func capturePage(_ mode: PageCaptureController.Mode) {
        guard canCapturePage, let parent = window, let browser = currentBrowser,
              let page = browser.nativePage, let tabID = currentTabID else { return }
        commandBar?.dismiss(); navigationHistory?.dismiss()
        sidebarPreviews?.dismiss(); tabSwitcher?.cancel(); dismissSiteControlCenter()
        settleSidebarMotion(); layoutChrome(); rootView.layoutSubtreeIfNeeded()
        Self.yieldPlaceholderCapture(of: page)
        guard let lease = page.beginCapture(in: parent) else { return }
        let profileID = activeProfileID, spaceID = activeSpaceID
        let privateCatalog = isPrivateBrowsing && canShowMedia ? downloadCatalog : nil
        let privateParent = privateCatalog == nil ? nil : store.privateParentProfileID
        let destination = CaptureLibraryDestination.make(store: store, parent: privateCatalog,
                                                         profileID: profileID, spaceID: spaceID)
        let valid: () -> Bool = { [weak self, weak browser, weak page, weak parent, weak privateCatalog] in
            guard let self, let browser, let page, let parent else { return false }
            return self.window === parent && parent.isVisible && !parent.isMiniaturized
                && self.privateCaptureContextIsValid && self.canOwnDownloadDialog(for: profileID) && self.activeSpaceID == spaceID
                && (privateParent == nil || (privateCatalog != nil && self.downloadCatalog === privateCatalog
                    && self.store.privateParentProfileID == privateParent && self.canShowMedia))
                && self.currentTabID == tabID && self.currentBrowser === browser
                && browser.nativePage === page && !page.isClosed
                && !self.closingTabIDs.contains(tabID) && !self.modelRetirementIDs.contains(tabID)
                && !self.store.retiringTabIDs.contains(tabID)
                && self.browserProfiles[tabID] == profileID && self.libraryView == nil
                && page.profilePath == self.store.independentEngineProfilePath(for: profileID)
                && PCNativeBrowserApplication.owner(of: page) === self.nativeBinding
        }
        let controller = PageCaptureController(lease: lease, sourceView: page.nativeView, containerView: browser,
            host: rootView, parent: parent, valid: valid,
            destination: destination,
            easelDestinations: { [weak self] in
                guard let self, valid() else { throw CocoaError(.userCancelled) }
                let directory = self.store.easelsDirectory(for: profileID)
                let documents = await Task.detached(priority: .userInitiated) { EaselStore.summaries(directory: directory) }.value
                guard valid() else { throw CocoaError(.userCancelled) }
                EaselTabIcons.shared.learn(documents, directory: directory)
                let activity = self.store.state.openTabs.flatMap { tab in
                    [InternalPage(urlString: tab.url)?.easelID, InternalPage(urlString: tab.savedURL)?.easelID]
                        .compactMap { $0 }.map {
                            CaptureEaselDestination.Activity(id: $0, profileID: tab.profileID, date: tab.lastAccessed)
                        }
                }
                return CaptureEaselDestination.catalog(documents: documents, activity: activity, profileID: profileID)
            }, addToEasel: { [weak self, weak parent] image, destinationID in
                guard let self, let parent else { throw CaptureSendRefusal.captureExpired }
                if let refusal = CaptureSendRefusal.check(parent) { throw refusal }
                guard valid(), image.isValid else { throw CaptureSendRefusal.captureExpired }
                guard self.presentation.isReady, !self.isClosing, !self.wholeWindowClose,
                      self.transferringTabIDs.isEmpty else { throw CaptureSendRefusal.windowBusy }
                self.easelImageDestination?.dismiss()
                let destinationStore = try EaselEditorViewController.sharedStore(directory:
                    self.store.easelsDirectory(for: profileID))
                let result = try EaselImagePlacement.place(image, in: destinationStore,
                    destinationID: destinationID, newTitle: image.pageTitle,
                    page: destinationID.flatMap { self.shownEaselPage($0, profileID: profileID) })
                self.pageCapture?.dismiss(restoreFocus: false)
                withExtendedLifetime(result) { self.openEasel(id: result.id, title: result.title) }
                self.revealEaselObject(result.itemID, in: result.id)
            }, noteDestinations: allowsCaptureNoteDestinations ? { [weak self] in
                guard let self, valid() else { throw CocoaError(.userCancelled) }
                return try self.captureNoteDestinations(profileID: profileID)
            } : nil, addToNote: allowsCaptureNoteDestinations ? { [weak self, weak parent] image, target in
                guard let self, let parent else { throw CaptureSendRefusal.captureExpired }
                if let refusal = CaptureSendRefusal.check(parent) { throw refusal }
                guard valid() else { throw CaptureSendRefusal.captureExpired }
                try self.placeCaptureInNote(image, target: target, profileID: profileID)
            } : nil, easelDirectory: store.easelsDirectory(for: profileID), finished: { [weak self, weak browser, weak parent] restoreFocus in
                guard let self else { return }
                self.pageCapture = nil
                self.sharedQuotes.bind(self.selectedNativePage(), window: self.window)
                self.easelImageDestination?.dismissIfInvalid()
                if restoreFocus, valid(), let browser, let parent, parent.isKeyWindow, parent.attachedSheet == nil {
                    parent.makeFirstResponder(browser.nativePage?.nativeView ?? browser)
                }
            })
        sharedQuotes.invalidate()
        controller.onCopied = { [weak self] in self?.showToast(.copiedImage) }
        pageCapture = controller; controller.present(mode)
    }
    func captureMenuItem(_ title: String, mode: PageCaptureController.Mode) -> NSMenuItem {
        let page = currentBrowser?.nativePage, profileID = activeProfileID, spaceID = activeSpaceID
        let item = MenuAction.item(title) { [weak self, weak page] in
            guard let self, let page, self.currentBrowser?.nativePage === page,
                  self.activeProfileID == profileID, self.activeSpaceID == spaceID else { return }
            self.capturePage(mode)
        }
        let binding: String?
        switch mode {
        case .region: binding = "capturePage:"
        case .viewport: binding = "captureVisiblePage:"
        case .fullPage: binding = "captureFullPage:"
        case .portrait: binding = nil
        }
        if let binding { KeyboardShortcuts.shared.showBinding(on: item, for: binding) }
        item.isEnabled = canCapturePage; return item
    }

    var canToggleToolbar: Bool {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !BrowserToolbarPreferences.shared.loadError,
              ownsSpaceCommandFocus, let window else { return false }
        return commandBar != nil || PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
    }
    func prepareToolbarMenuItem(_ item: NSMenuItem) -> Bool {
        item.title = BrowserToolbarPreferences.shared.state.isVisible ? "Hide Toolbar" : "Show Toolbar"
        item.representedObject = canToggleToolbar ? ToolbarMenuRequest(self) : nil
        return canToggleToolbar
    }
    func toggleToolbar(from item: NSMenuItem) {
        guard let request = item.representedObject as? ToolbarMenuRequest,
              request.owner === self, canToggleToolbar else { return }
        commandBar?.dismiss(restoreFocus: true)
        guard canToggleToolbar else { return }
        do { try BrowserToolbarPreferences.shared.setVisible(!BrowserToolbarPreferences.shared.state.isVisible) }
        catch { showError(error) }
    }
    var selectedBrowserToolbar: BrowserToolbarView? {
        if let peek = activePeek, !peek.view.browserToolbar.isHidden { return peek.view.browserToolbar }
        if let id = currentTabID, let toolbar = panes[id]?.browserToolbar, !toolbar.isHidden { return toolbar }
        return nil
    }
    var sidebarShowsAddressBar: Bool {
        PaneTopBarAdmission.sidebarAddressBarShown(focusedHasTopBar: selectedBrowserToolbar != nil,
                                                   toolbarVisible: BrowserToolbarPreferences.shared.state.isVisible)
    }
}
