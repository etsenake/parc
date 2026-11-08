// Copyright 2026 Parc contributors.
#import "native_appkit_page.h"
#include <algorithm>
#include <cmath>
#include <map>
#include <optional>
#include <vector>
#include "base/functional/bind.h"
#include "cef/libcef/browser/parc_native/native_internal_urls.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/picture_in_picture/auto_picture_in_picture_tab_helper.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "content/browser/media/session/media_session_impl.h"
#include "content/browser/web_contents/web_contents_impl.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/favicon_status.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "url/gurl.h"
#include "url/url_constants.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "native_airplay.h"
#include "native_appkit_host.h"
#include "native_background_picture_in_picture.h"
#include "native_background_picture_in_picture_api.h"
#include "native_gmc_presentation.h"
#include "native_media_episode_store.h"
#include "native_media_notify.h"
#include "native_page_retirement.h"
#include "native_profile_removal.h"
#include "tab_transfer.h"
#include "ui/base/base_window.h"
#import "window_security_reservation.h"

@interface PCNativeMediaState () {
 @public
  base::WeakPtr<content::WebContents> contents_;
  content::WeakDocumentPtr document_;
  base::WeakPtr<Profile> profile_;
  base::WeakPtr<BrowserWindowInterface> browser_;
}
- (instancetype)initWithContents:(content::WebContents*)contents
                        browser:(BrowserWindowInterface*)browser
                       identity:(NSString*)identity
              admissionSequence:(uint64_t)sequence;
@end

@interface PCNativeMediaPresentationLease : NSObject {
 @public
  base::WeakPtr<content::WebContents> contents_;
  content::WeakDocumentPtr document_;
  base::WeakPtr<Profile> profile_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  std::optional<parc::NativeMediaSuppressionFence::Lease> fence_;
}
@end
@implementation PCNativeMediaPresentationLease
@end

@interface PCNativeTabAudioState : NSObject {
 @public
  base::WeakPtr<content::WebContents> contents_;
  content::WeakDocumentPtr document_;
  base::WeakPtr<Profile> profile_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  uint64_t mute_revision_;
}
@property(nonatomic, readonly) BOOL audible;
@property(nonatomic, readonly) BOOL muted;
- (instancetype)initWithContents:(content::WebContents*)contents browser:(BrowserWindowInterface*)browser
                   muteRevision:(uint64_t)revision;
@end

namespace parc {
namespace {
using Action = media_session::mojom::MediaSessionAction;
using Info = media_session::mojom::MediaSessionInfo;

bool Has(content::MediaSession* session, Action action) {
  if (!session) return false;
  const auto actions = session->GetMediaSessionActionsSync();
  return std::ranges::find(actions, action) != actions.end();
}
// This is an in-window player for background pages. Selection/renderer focus
// is intentionally not required; exact owner and security admission still are.
BrowserWindowInterface* Owner(content::WebContents* contents, bool action, bool allow_crashed = false) {
  PCNativePage* page = contents ? ExistingNativePage(contents) : nil;
  auto* browser = contents ? GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) : nullptr;
  auto* profile = contents ? Profile::FromBrowserContext(contents->GetBrowserContext()) : nullptr;
  if (!page || page.closed || !profile || !browser || browser->IsDeleteScheduled() ||
      !AppKitBrowserAcceptsNewPages(*browser) || IsNativePageRetiring(page) ||
      IsLiveTabTransferTarget(contents) || IsNativeProfileRemovalBlocked(profile->GetPath()) ||
      !browser->GetWindow() || !contents->GetPrimaryMainFrame() || (!allow_crashed && contents->IsCrashed())) return nullptr;
  NSWindow* window = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
  if (!window || ![PCNativeBrowserApplication windowForNativeWindow:window]) return nullptr;
  if (action && (!window.visible || window.miniaturized || !window.keyWindow || !NSApp.active ||
      window.attachedSheet || PCNativeWindowHasSecurityReservation(window))) return nullptr;
  return browser;
}
bool Eligible(content::MediaSession* session) {
  if (!session) return false;
  const auto info = session->GetMediaSessionInfoSync();
  return info && ((info->is_controllable && info->state != Info::SessionState::kInactive) ||
      Has(session, Action::kToggleMicrophone) || Has(session, Action::kToggleCamera));
}
bool ValidHost(NSWindow* window, Profile* profile, bool action) {
  PCNativeBrowserWindow* binding = window ? [PCNativeBrowserApplication windowForNativeWindow:window] : nil;
  if (!binding || !profile) return false;
  const auto kind = binding.browsingContextKind;
  const auto expected = profile->IsOffTheRecord() ? PCNativeBrowsingContextKindOffTheRecord : PCNativeBrowsingContextKindRegular;
  return binding.window == window && binding.client &&
      [binding.client nativeBrowserWindow] == window &&
      (!action || (window.keyWindow && binding.canParticipateInPageTransfer)) &&
      (kind == PCNativeBrowsingContextKindUnavailable || kind == expected) &&
      binding.isPrivateBrowsing == profile->IsOffTheRecord() &&
      (!profile->IsOffTheRecord() ||
       NativePrivateProfileForWindow(binding, base::SysUTF8ToNSString(profile->GetPath().value())) == profile);
}
BackgroundPipVisibility PipVisibility(content::Visibility visibility) {
  switch (visibility) {
    case content::Visibility::VISIBLE: return BackgroundPipVisibility::kVisible;
    case content::Visibility::OCCLUDED: return BackgroundPipVisibility::kOccluded;
    case content::Visibility::HIDDEN: return BackgroundPipVisibility::kHidden;
  }
  return BackgroundPipVisibility::kOccluded;
}
bool AutoPictureInPictureAllowed(content::WebContents* contents) {
  if (!contents) return false;
  auto* map = HostContentSettingsMapFactory::GetForProfile(
      Profile::FromBrowserContext(contents->GetBrowserContext()));
  if (!map) return false;
  const GURL url = contents->GetLastCommittedURL();
  if (!url.SchemeIs(url::kHttpsScheme) && !url.SchemeIsFile()) return false;
  ContentSetting setting = map->GetContentSetting(
      url, url, ContentSettingsType::AUTO_PICTURE_IN_PICTURE);
  // ASK counts as allowed, matching Site Control Center / PageInfo toggle-on.
  return setting == CONTENT_SETTING_ALLOW || setting == CONTENT_SETTING_ASK;
}

class MediaState final : public content::WebContentsObserver,
                         public content::WebContentsUserData<MediaState>,
                         public media_session::mojom::MediaSessionObserver {
 public:
  ~MediaState() override { Registry().Remove(this); }
  PCNativeMediaState* Snapshot(bool admit = false) {
    auto* contents = web_contents();
    auto* browser = Owner(contents, false);
    auto* session = contents ? content::MediaSession::GetIfExists(contents) : nullptr;
    ObserveSession(session);
    // Presentation ownership can disappear temporarily during transfer or
    // window teardown. It is not a media-session transition and must not
    // resurrect a control that the user dismissed on the original page.
    if (!Eligible(session)) { Registry().Remove(this); active_ = false; dismissed_ = false; return nil; }
    if (!browser) return nil;
    if (dismissed_) return nil;
    if (!active_) {
      if (!admit) return nil;
      const auto info = session->GetMediaSessionInfoSync();
      using AudioVideoState = media_session::mojom::MediaAudioVideoState;
      if (!info || !CanAdmitNewMediaEpisode(
              Has(session, Action::kToggleMicrophone) || Has(session, Action::kToggleCamera),
              info->is_controllable, info->state == Info::SessionState::kActive,
              contents->IsAudioMuted(), info->audio_video_states,
              AudioVideoState::kAudioOnly, AudioVideoState::kAudioVideo)) return nil;
      auto removed = Registry().RemoveIf([](MediaState* source) { return !source->CanRemainAdmitted(); });
      for (const auto& source : removed) if (source) source->WithdrawAfterRemoval();
      auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
      identity_ = NSUUID.UUID.UUIDString; active_ = true;
      auto evicted = Registry().Admit(weak_factory_.GetWeakPtr(), profile->GetWeakPtr(),
                                      profile->IsOffTheRecord());
      if (evicted) evicted->Evicted();
    }
    return [[PCNativeMediaState alloc] initWithContents:contents browser:browser identity:identity_
                                    admissionSequence:Registry().Sequence(this)];
  }
  // Chromium's own session state for this exact page. It never consults
  // Eligible() or the dismissed episode, and never changes either; every
  // transition already republishes through MediaSessionInfoChanged.
  PCNativeMediaSessionStatus Status() {
    auto* contents = web_contents();
    auto* session = contents ? content::MediaSession::GetIfExists(contents) : nullptr;
    ObserveSession(session);
    if (!session || !Owner(contents, false)) return PCNativeMediaSessionStatusInactive;
    const auto info = session->GetMediaSessionInfoSync();
    if (!info) return PCNativeMediaSessionStatusInactive;
    // GetMediaSessionInfoSync already reports ducking ahead of the focus state.
    //
    switch (info->state) {
      case Info::SessionState::kActive: return PCNativeMediaSessionStatusActive;
      case Info::SessionState::kDucking: return PCNativeMediaSessionStatusDucking;
      case Info::SessionState::kSuspended: return PCNativeMediaSessionStatusSuspended;
      case Info::SessionState::kInactive: break;
    }
    return PCNativeMediaSessionStatusInactive;
  }
  bool Validate(PCNativeMediaState* state, NSWindow* host = nil, bool action = true) {
    auto* contents = web_contents();
    auto* browser = Owner(contents, action && host == nil);
    NSWindow* source = browser ? browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() : nil;
    return state && active_ && !dismissed_ && [state.identifier isEqualToString:identity_] && browser &&
        source && (!action || (!source.attachedSheet && !PCNativeWindowHasSecurityReservation(source))) &&
        state->contents_.get() == contents && state->browser_.get() == browser &&
        state->profile_ && state->profile_.get() == contents->GetBrowserContext() &&
        (!host || ValidHost(host, state->profile_.get(), action)) &&
        state->document_.AsRenderFrameHostIfValid() == contents->GetPrimaryMainFrame() &&
        Eligible(content::MediaSession::GetIfExists(contents));
  }
  bool CanContinueReveal(PCNativeMediaState* state, NSWindow* host) {
    if (!host || !Validate(state, host, false)) return false;
    auto* browser = Owner(web_contents(), false);
    NSWindow* source = browser ? browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() : nil;
    PCNativeBrowserWindow* binding = [PCNativeBrowserApplication windowForNativeWindow:host];
    return source && browser == state->browser_.get() && binding && binding.canParticipateInPageTransfer &&
        NSApp.active && (host.keyWindow || source.keyWindow) &&
        !source.attachedSheet && !PCNativeWindowHasSecurityReservation(source);
  }
  bool Perform(PCNativeMediaAction action, PCNativeMediaState* state, NSWindow* host = nil) {
    if (!Validate(state, host)) return false;
    auto* contents = web_contents();
    auto* session = content::MediaSession::GetIfExists(contents);
    const auto info = session->GetMediaSessionInfoSync();
    switch (action) {
      case PCNativeMediaActionPlay:
      case PCNativeMediaActionPause:
        if (!info || !info->is_controllable || info->state == Info::SessionState::kInactive) return false;
        if (action == PCNativeMediaActionPlay) session->Resume(content::MediaSession::SuspendType::kUI);
        else session->Suspend(content::MediaSession::SuspendType::kUI);
        break;
      case PCNativeMediaActionPreviousTrack:
        if (!Has(session, Action::kPreviousTrack)) return false;
        session->PreviousTrack(); break;
      case PCNativeMediaActionNextTrack:
        if (!Has(session, Action::kNextTrack)) return false;
        session->NextTrack(); break;
      case PCNativeMediaActionToggleMuted:
        contents->SetAudioMuted(!contents->IsAudioMuted()); break;
      case PCNativeMediaActionToggleMicrophone:
        if (!Has(session, Action::kToggleMicrophone)) return false;
        session->ToggleMicrophone(); break;
      case PCNativeMediaActionToggleCamera:
        if (!Has(session, Action::kToggleCamera)) return false;
        session->ToggleCamera(); break;
      case PCNativeMediaActionEnterPictureInPicture:
        session->EnterPictureInPicture(); break;
      default: return false;
    }
    // Commands can synchronously replace their owner. Never read it afterwards.
    return true;
  }
  PCNativeMediaPresentationLease* CapturePresentationLease() {
    auto* contents = web_contents();
    auto* browser = Owner(contents, false);
    if (!browser) return nil;
    auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
    auto* lease = [[PCNativeMediaPresentationLease alloc] init];
    lease->contents_ = contents->GetWeakPtr();
    lease->document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    lease->profile_ = profile->GetWeakPtr();
    lease->browser_ = browser->GetWeakPtr();
    lease->fence_ = suppression_fence_.Capture();
    return lease;
  }
  void PresentationDidRemove(PCNativeMediaPresentationLease* lease) {
    if (!lease || !lease->fence_) return;
    auto* contents = web_contents();
    const bool valid = contents && lease->contents_.get() == contents && lease->profile_ &&
        lease->profile_.get() == contents->GetBrowserContext() && lease->browser_ &&
        Owner(contents, false) == lease->browser_.get() &&
        lease->document_.AsRenderFrameHostIfValid() == contents->GetPrimaryMainFrame();
    if (!lease->fence_->Consume(suppression_fence_, valid)) return;
    if (!Eligible(content::MediaSession::GetIfExists(contents))) {
      Snapshot(true);  // Preserve the existing inactive-episode reset.
      return;
    }
    if (AdmitAfterPresentationRemoval(active_, dismissed_, [this] { return Snapshot(true) != nil; }))
      Changed();
  }
  bool Dismiss(PCNativeMediaState* state, NSWindow* host = nil) {
    if (!Validate(state, host)) return false;
    Registry().Remove(this); dismissed_ = true; suppression_fence_.Suppress(); Changed(); return true;
  }
  bool ShowAirPlayPicker(PCNativeMediaState* state, NSView* view, NSRect rect, NSWindow* host,
                         void (^dismissed)(void)) {
    if (!host || view.window != host || !Validate(state, host)) return false;
    return ShowNativeAirPlayPicker(web_contents(), view, rect, dismissed);
  }
  bool ShowCastChooser(PCNativeMediaState* state, NSView* view, NSRect rect, NSWindow* host,
                       void (^dismissed)(void)) {
    if (!host || view.window != host || !Validate(state, host)) return false;
    __weak NSWindow* weak_host = host;
    base::WeakPtr<MediaState> weak = weak_factory_.GetWeakPtr();
    auto valid = base::BindRepeating(^bool {
      NSWindow* window = weak_host;
      return weak && window && weak->Validate(state, window);
    });
    return ShowNativeMediaCastChooser(web_contents(), view, rect, std::move(valid), dismissed);
  }
  void RouteChanged() { Changed(); }
  void Withdraw() {
    if (!active_ || dismissed_) return;
    Registry().Remove(this);
    WithdrawAfterRemoval();
  }
  bool Volume(double value, PCNativeMediaState* state, NSWindow* host = nil) {
    if (!std::isfinite(value) || !Validate(state, host)) return false;
    auto* session = content::MediaSession::GetIfExists(web_contents());
    auto info = session->GetMediaSessionInfoSync();
    if (!info || !info->is_controllable || info->state == Info::SessionState::kInactive) return false;
    auto weak = weak_factory_.GetWeakPtr();
    auto* implementation = content::MediaSessionImpl::Get(web_contents());
    if (!implementation->has_user_volume_players()) return false;
    implementation->SetUserVolumeMultiplier(value);
    if (weak) weak->Changed();
    return true;
  }
  void MediaSessionCreated(content::MediaSession* session) override { ObserveSession(session); Changed(); }
  void PrimaryPageChanged(content::Page&) override {
    Registry().Remove(this);
    active_ = false; dismissed_ = false;
    background_pip_ = BackgroundPipSessionState::kIdle;
    pending_enter_at_ = std::nullopt;
    silent_enter_retries_remaining_ = 0;
    shell_visibility_.reset();
    identity_ = NSUUID.UUID.UUIDString;
    // A replacement document does not inherit a previous document's UI volume.
    if (content::MediaSession::GetIfExists(web_contents()))
      content::MediaSessionImpl::Get(web_contents())->SetUserVolumeMultiplier(1.0);
    Changed();
  }
  void WebContentsDestroyed() override {
    Registry().Remove(this); receiver_.reset();
    background_pip_ = BackgroundPipSessionState::kIdle;
    pending_enter_at_ = std::nullopt;
    silent_enter_retries_remaining_ = 0;
    shell_visibility_.reset();
    weak_factory_.InvalidateWeakPtrs();
  }
  void OnAudioStateChanged(bool) override { Changed(); }
  void DidUpdateAudioMutingState(bool) override { ++mute_revision_; Changed(); }
  uint64_t mute_revision() const { return mute_revision_; }
  uint64_t ControlsRevision() const { return controls_revision_; }
  void TitleWasSet(content::NavigationEntry*) override { Changed(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    // Prefer shell policy when the host has reported it; paint visibility can
    // stay VISIBLE while resign-active is treated as occluded for auto-PiP.
    ApplyBackgroundPictureInPicture(shell_visibility_.value_or(
        PipVisibility(visibility)));
  }
  void SyncBackgroundPictureInPictureForVisibility(
      content::Visibility visibility) {
    shell_visibility_.reset();
    ApplyBackgroundPictureInPicture(PipVisibility(visibility));
  }
  void SyncBackgroundPictureInPictureForShell(
      BackgroundPipVisibility shell_visibility) {
    shell_visibility_ = shell_visibility;
    auto weak = weak_factory_.GetWeakPtr();
    ApplyBackgroundPictureInPicture(shell_visibility);
    if (weak) ReportHostOcclusion(shell_visibility);
  }
  void MediaPictureInPictureChanged(bool is_picture_in_picture) override {
    ApplyBackgroundPictureInPicture(CurrentShellVisibility(),
                                    is_picture_in_picture,
                                    BackgroundPipSignal::kPictureInPictureChanged);
  }
  void MediaSessionInfoChanged(media_session::mojom::MediaSessionInfoPtr) override {
    // Read authoritative current state; an older queued Mojo notification must
    // not end a newer episode. A real inactive interval permits a new row.
    ReconcileEligibility();
    ApplyBackgroundPictureInPicture(CurrentShellVisibility());
    Changed();
  }
  void MediaSessionMetadataChanged(const std::optional<media_session::MediaMetadata>&) override { Changed(); }
  void MediaSessionActionsChanged(const std::vector<Action>&) override { ReconcileEligibility(); Changed(); }
  void MediaSessionImagesChanged(const base::flat_map<media_session::mojom::MediaSessionImageType,
      std::vector<media_session::MediaImage>>&) override { Changed(); }
  // Cast needs more than 15 seconds of media (CastSource()).
  void MediaSessionPositionChanged(const std::optional<media_session::MediaPosition>&) override { Changed(); }
 private:
  BackgroundPipVisibility CurrentShellVisibility() const {
    if (shell_visibility_) return *shell_visibility_;
    if (auto* contents = web_contents()) {
      return PipVisibility(contents->GetVisibility());
    }
    return BackgroundPipVisibility::kHidden;
  }
  bool ChromiumInPictureInPicture() const {
    auto* contents = web_contents();
    return contents && (contents->HasPictureInPictureVideo() ||
                        contents->HasPictureInPictureDocument());
  }
  bool BackgroundPipMediaIsEligible() const {
    auto* contents = web_contents();
    if (!contents) return false;
    auto* session = content::MediaSession::GetIfExists(contents);
    if (!session) return false;
    const auto info = session->GetMediaSessionInfoSync();
    using AudioVideoState = media_session::mojom::MediaAudioVideoState;
    const bool has_video = info && HasBackgroundPipVideoTrack(
        info->audio_video_states, AudioVideoState::kAudioVideo,
        AudioVideoState::kVideoOnly);
    const bool controllable = info && info->is_controllable &&
                              info->state != Info::SessionState::kInactive;
    const bool playing =
        info && info->playback_state ==
                    media_session::mojom::MediaPlaybackState::kPlaying;
    return BackgroundPipMediaEligible(AutoPictureInPictureAllowed(contents),
                                      controllable, playing,
                                      contents->IsAudioMuted(), has_video);
  }
  // Chromium often completes Enter asynchronously without a false edge on
  // failure. After this wait, pending re-issues Enter (or drops if ineligible).
  static constexpr base::TimeDelta kPendingEnterTimeout = base::Milliseconds(750);

  void ApplyBackgroundPictureInPicture(
      BackgroundPipVisibility shell,
      std::optional<bool> chromium_in_pip = std::nullopt,
      BackgroundPipSignal signal = BackgroundPipSignal::kReconcile) {
    auto* contents = web_contents();
    if (!contents || !Owner(contents, false)) return;
    if (PictureInPictureWindowManager::GetInstance()
            ->IsPictureInPictureDisabled()) {
      return;
    }
    ObserveSession(content::MediaSession::GetIfExists(contents));
    const bool in_pip =
        chromium_in_pip.value_or(ChromiumInPictureInPicture());
    const bool awaiting_enter =
        background_pip_ == BackgroundPipSessionState::kPendingActive ||
        background_pip_ == BackgroundPipSessionState::kCancelPending;
    if (signal == BackgroundPipSignal::kReconcile && awaiting_enter && !in_pip &&
        pending_enter_at_ &&
        base::TimeTicks::Now() - *pending_enter_at_ >= kPendingEnterTimeout) {
      signal = BackgroundPipSignal::kEnterTimedOut;
    }
    const auto prior_state = background_pip_;
    const auto step = ReduceBackgroundPipSession(
        background_pip_, shell, in_pip, BackgroundPipMediaIsEligible(), signal,
        silent_enter_retries_remaining_);
    background_pip_ = step.state;
    if (background_pip_ != BackgroundPipSessionState::kPendingActive &&
        background_pip_ != BackgroundPipSessionState::kCancelPending) {
      pending_enter_at_ = std::nullopt;
      silent_enter_retries_remaining_ = 0;
    }
    if (step.command == BackgroundPipCommand::kNone) return;
    auto* session = content::MediaSession::GetIfExists(contents);
    if (!session) {
      if (step.command == BackgroundPipCommand::kEnter) {
        background_pip_ = BackgroundPipSessionState::kIdle;
        pending_enter_at_ = std::nullopt;
        silent_enter_retries_remaining_ = 0;
      }
      return;
    }
    auto weak = weak_factory_.GetWeakPtr();
    if (step.command == BackgroundPipCommand::kExit) {
      pending_enter_at_ = std::nullopt;
      silent_enter_retries_remaining_ = 0;
      session->ExitPictureInPicture();
    } else if (step.command == BackgroundPipCommand::kEnter) {
      // Fresh attempt from Idle or resumed after CancelPending settle.
      if (prior_state == BackgroundPipSessionState::kIdle ||
          prior_state == BackgroundPipSessionState::kCancelPending) {
        silent_enter_retries_remaining_ = 1;
      } else if (signal == BackgroundPipSignal::kEnterTimedOut &&
                 silent_enter_retries_remaining_ > 0) {
        --silent_enter_retries_remaining_;
      }
      pending_enter_at_ = base::TimeTicks::Now();
      session->EnterPictureInPicture();
      // Silent Enter failures often never flip the PiP bit. Reconcile after the
      // timeout so pending can retry once (or CancelPending can settle).
      base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
          FROM_HERE,
          base::BindOnce(&MediaState::OnPendingEnterTimeout,
                         weak_factory_.GetWeakPtr()),
          kPendingEnterTimeout);
    }
    if (!weak) return;
  }
  // Chromium's auto-PiP (calls through Meet's handler, registered video) learns
  // window occlusion only from Views windows, and only its own entry may open a
  // document PiP without a gesture. Leaving Parc counts as occluded, as for
  // video; video the rule above is already entering is not entered twice.
  void ReportHostOcclusion(BackgroundPipVisibility shell) {
    auto* helper = AutoPictureInPictureTabHelper::FromWebContents(web_contents());
    if (!helper || !Owner(web_contents(), false)) return;
    using Occlusion = AutoPictureInPictureWindowOcclusionHelperBase::OcclusionState;
    switch (shell) {
      case BackgroundPipVisibility::kVisible:
        helper->SetHostOcclusionState(Occlusion::kVisible);
        break;
      case BackgroundPipVisibility::kOccluded:
        if (background_pip_ == BackgroundPipSessionState::kIdle) {
          helper->SetHostOcclusionState(Occlusion::kOccluded);
        }
        break;
      case BackgroundPipVisibility::kHidden:
        helper->SetHostOcclusionState(Occlusion::kHidden);
        break;
    }
  }
  void OnPendingEnterTimeout() {
    if (background_pip_ != BackgroundPipSessionState::kPendingActive &&
        background_pip_ != BackgroundPipSessionState::kCancelPending) {
      return;
    }
    ApplyBackgroundPictureInPicture(CurrentShellVisibility());
  }
  using EpisodeStore = NativeMediaEpisodeStore<base::WeakPtr<MediaState>, base::WeakPtr<Profile>>;
  static EpisodeStore& Registry() {
    static base::NoDestructor<EpisodeStore> store;
    return *store;
  }
  void Evicted() {
    active_ = false; dismissed_ = true; suppression_fence_.Suppress();
    Changed();
  }
  bool CanRemainAdmitted() {
    auto* contents = web_contents();
    PCNativePage* page = contents ? ExistingNativePage(contents) : nil;
    auto* profile = contents ? Profile::FromBrowserContext(contents->GetBrowserContext()) : nullptr;
    return active_ && !dismissed_ && contents && !contents->IsBeingDestroyed() && page && !page.closed &&
        !IsNativePageRetiring(page) && profile &&
        !IsNativeProfileRemovalBlocked(profile->GetOriginalProfile()->GetPath()) &&
        Eligible(content::MediaSession::GetIfExists(contents));
  }
  void WithdrawAfterRemoval() {
    active_ = false;
    auto* contents = web_contents();
    if (!contents || !Eligible(content::MediaSession::GetIfExists(contents))) dismissed_ = false;
    if (contents) Changed();
  }
  void ReconcileEligibility() {
    if (!Eligible(content::MediaSession::GetIfExists(web_contents()))) {
      Registry().Remove(this);
      active_ = false; dismissed_ = false;
    }
  }
  friend class content::WebContentsUserData<MediaState>;
  explicit MediaState(content::WebContents* contents)
      : WebContentsObserver(contents), content::WebContentsUserData<MediaState>(*contents) {
    ObserveSession(content::MediaSession::GetIfExists(contents));
  }
  void ObserveSession(content::MediaSession* session) {
    if (session && !receiver_.is_bound()) session->AddObserver(receiver_.BindNewPipeAndPassRemote());
  }
  NativeMediaNotifyState CurrentMediaNotifyState() {
    NativeMediaNotifyState state;
    auto* contents = web_contents();
    if (!contents) {
      return state;
    }
    auto* session = content::MediaSession::GetIfExists(contents);
    state.eligible = Eligible(session);
    state.active = active_;
    state.dismissed = dismissed_;
    if (identity_) {
      state.identity = base::SysNSStringToUTF8(identity_);
    }
    if (active_) {
      state.admission_sequence = Registry().Sequence(this);
    }
    state.title = contents->GetTitle();
    state.source_url =
        PublicInternalURL(contents->GetLastCommittedURL()).spec();
    if (auto* entry = contents->GetController().GetLastCommittedEntry()) {
      const auto& favicon = entry->GetFavicon();
      state.artwork_present = favicon.valid && !favicon.image.IsEmpty();
      if (favicon.url.is_valid()) {
        state.artwork_url = favicon.url.spec();
      }
    }
    state.audible = contents->IsCurrentlyAudible();
    state.muted = contents->IsAudioMuted();
    state.mute_revision = mute_revision_;
    if (auto* profile =
            Profile::FromBrowserContext(contents->GetBrowserContext())) {
      state.off_the_record = profile->IsOffTheRecord();
    }
    state.session_status =
        static_cast<uint8_t>(PCNativeMediaSessionStatusInactive);
    if (!session) {
      return state;
    }
    const auto info = session->GetMediaSessionInfoSync();
    if (!info) {
      return state;
    }
    switch (info->state) {
      case Info::SessionState::kActive:
        state.session_status =
            static_cast<uint8_t>(PCNativeMediaSessionStatusActive);
        break;
      case Info::SessionState::kDucking:
        state.session_status =
            static_cast<uint8_t>(PCNativeMediaSessionStatusDucking);
        break;
      case Info::SessionState::kSuspended:
        state.session_status =
            static_cast<uint8_t>(PCNativeMediaSessionStatusSuspended);
        break;
      case Info::SessionState::kInactive:
        break;
    }
    state.session_controllable = info->is_controllable;
    state.session_state_active = info->state == Info::SessionState::kActive;
    const bool toggle_supported = Has(session, Action::kToggleMicrophone) ||
                                  Has(session, Action::kToggleCamera);
    using AudioVideoState = media_session::mojom::MediaAudioVideoState;
    state.can_admit = CanAdmitNewMediaEpisode(
        toggle_supported, info->is_controllable,
        info->state == Info::SessionState::kActive, contents->IsAudioMuted(),
        info->audio_video_states, AudioVideoState::kAudioOnly,
        AudioVideoState::kAudioVideo);
    state.playing =
        info->playback_state == media_session::mojom::MediaPlaybackState::kPlaying;
    state.can_play_pause =
        info->is_controllable && info->state != Info::SessionState::kInactive;
    state.has_previous_track = Has(session, Action::kPreviousTrack);
    state.has_next_track = Has(session, Action::kNextTrack);
    auto* implementation = content::MediaSessionImpl::Get(contents);
    state.volume_hundredths =
        static_cast<int>(std::lround(implementation->user_volume_multiplier() * 100.0));
    state.can_set_volume =
        state.can_play_pause && implementation->has_user_volume_players();
    state.can_toggle_microphone = Has(session, Action::kToggleMicrophone);
    state.can_toggle_camera = Has(session, Action::kToggleCamera);
    state.microphone_on =
        info->microphone_state == media_session::mojom::MicrophoneState::kUnmuted;
    state.camera_on =
        info->camera_state == media_session::mojom::CameraState::kTurnedOn;
    const NativeAirPlayState airplay = NativeAirPlayStateForContents(contents);
    state.airplay_state = airplay.state;
    state.airplay_device_name = airplay.device_name;
    const NativeMediaCastState cast = NativeMediaCastStateForContents(contents);
    state.cast_state = cast.state;
    state.cast_device_name = cast.device_name;
    return state;
  }
  void Changed() {
    if (pending_) return;
    pending_ = true;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce(&MediaState::Publish, weak_factory_.GetWeakPtr()));
  }
  void Publish() {
    pending_ = false;
    auto* contents = web_contents();
    if (!contents) {
      return;
    }
    // ObserveSession so Mojo keeps delivering; same as Snapshot/Status reads.
    ObserveSession(content::MediaSession::GetIfExists(contents));
    NativeMediaNotifyState current = CurrentMediaNotifyState();
    if (!ShouldNotifyMediaPayloadChange(last_media_notify_, current)) {
      return;
    }
    last_media_notify_ = current;
    last_media_notify_.published = true;
    ++controls_revision_;
    NotifyNativePageChanged(contents);
  }
  uint64_t mute_revision_ = 0;
  uint64_t controls_revision_ = 0;
  bool active_ = false;
  bool dismissed_ = false;
  bool pending_ = false;
  NativeMediaNotifyState last_media_notify_;
  BackgroundPipSessionState background_pip_ = BackgroundPipSessionState::kIdle;
  std::optional<base::TimeTicks> pending_enter_at_;
  unsigned silent_enter_retries_remaining_ = 0;
  std::optional<BackgroundPipVisibility> shell_visibility_;
  NSString* __strong identity_ = nil;
  NativeMediaSuppressionFence suppression_fence_;
  mojo::Receiver<media_session::mojom::MediaSessionObserver> receiver_{this};
  base::WeakPtrFactory<MediaState> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(MediaState);
MediaState* State(PCNativePage* page) {
  auto* contents = ContentsForNativePage(page);
  if (!contents || page.closed) return nullptr;
  MediaState::CreateForWebContents(contents);
  return MediaState::FromWebContents(contents);
}
void SyncBackgroundPictureInPictureContents(
    content::WebContents* contents,
    std::optional<BackgroundPipVisibility> shell_visibility) {
  if (!contents || contents->IsBeingDestroyed()) return;
  MediaState::CreateForWebContents(contents);
  if (auto* state = MediaState::FromWebContents(contents)) {
    if (shell_visibility) {
      state->SyncBackgroundPictureInPictureForShell(*shell_visibility);
    } else {
      state->SyncBackgroundPictureInPictureForVisibility(
          contents->GetVisibility());
    }
  }
}
}  // namespace

void SyncBackgroundPictureInPicture(content::WebContents* contents) {
  SyncBackgroundPictureInPictureContents(contents, std::nullopt);
}

void SyncBackgroundPictureInPicture(content::WebContents* contents,
                                    BackgroundPipVisibility shell_visibility) {
  SyncBackgroundPictureInPictureContents(contents, shell_visibility);
}

void NativeMediaAirPlayChanged(content::WebContents* contents) {
  if (auto* state = contents ? MediaState::FromWebContents(contents) : nullptr) {
    state->RouteChanged();
  }
}

void NativeMediaCastChanged(content::WebContents* contents) {
  if (auto* state = contents ? MediaState::FromWebContents(contents) : nullptr) {
    state->RouteChanged();
  }
}
}  // namespace parc

@implementation PCNativeTabAudioState
@synthesize audible = _audible, muted = _muted;
- (instancetype)initWithContents:(content::WebContents*)contents browser:(BrowserWindowInterface*)browser
                   muteRevision:(uint64_t)revision {
  if ((self = [super init])) {
    mute_revision_ = revision;
    contents_ = contents->GetWeakPtr();
    document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    profile_ = Profile::FromBrowserContext(contents->GetBrowserContext())->GetWeakPtr();
    browser_ = browser->GetWeakPtr();
    _audible = contents->IsCurrentlyAudible();
    _muted = contents->IsAudioMuted();
  }
  return self;
}
@end
@implementation PCNativeMediaState
@synthesize icon = _icon;
@synthesize identifier = _identifier, title = _title, sourceURL = _sourceURL;
@synthesize offTheRecord = _offTheRecord;
@synthesize admissionSequence = _admissionSequence;
@synthesize playing = _playing, canPlayPause = _canPlayPause;
@synthesize hasPreviousTrack = _hasPreviousTrack, hasNextTrack = _hasNextTrack;
@synthesize muted = _muted, volume = _volume, canSetVolume = _canSetVolume;
@synthesize canToggleMicrophone = _canToggleMicrophone, canToggleCamera = _canToggleCamera;
@synthesize microphoneOn = _microphoneOn, cameraOn = _cameraOn;
@synthesize airPlayState = _airPlayState, airPlayDeviceName = _airPlayDeviceName;
@synthesize castState = _castState, castDeviceName = _castDeviceName;
- (instancetype)initWithContents:(content::WebContents*)contents
                        browser:(BrowserWindowInterface*)browser identity:(NSString*)identity
              admissionSequence:(uint64_t)sequence {
  if ((self = [super init])) {
    contents_ = contents->GetWeakPtr();
    document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    profile_ = Profile::FromBrowserContext(contents->GetBrowserContext())->GetWeakPtr();
    _offTheRecord = profile_->IsOffTheRecord();
    _admissionSequence = sequence;
    browser_ = browser->GetWeakPtr();
    _identifier = [identity copy];
    _title = base::SysUTF16ToNSString(contents->GetTitle());
    _sourceURL = base::SysUTF8ToNSString(parc::PublicInternalURL(contents->GetLastCommittedURL()).spec());
    if (auto* entry = contents->GetController().GetLastCommittedEntry()) {
      const auto& favicon = entry->GetFavicon();
      if (favicon.valid && !favicon.image.IsEmpty()) _icon = [favicon.image.ToNSImage() copy];
    }
    auto* session = content::MediaSession::GetIfExists(contents);
    auto info = session->GetMediaSessionInfoSync();
    _playing = info->playback_state == media_session::mojom::MediaPlaybackState::kPlaying;
    _canPlayPause = info->is_controllable && info->state != parc::Info::SessionState::kInactive;
    _hasPreviousTrack = parc::Has(session, parc::Action::kPreviousTrack);
    _hasNextTrack = parc::Has(session, parc::Action::kNextTrack);
    _muted = contents->IsAudioMuted();
    _volume = content::MediaSessionImpl::Get(contents)->user_volume_multiplier();
    _canSetVolume = _canPlayPause && content::MediaSessionImpl::Get(contents)->has_user_volume_players();
    _canToggleMicrophone = parc::Has(session, parc::Action::kToggleMicrophone);
    _canToggleCamera = parc::Has(session, parc::Action::kToggleCamera);
    _microphoneOn = info->microphone_state == media_session::mojom::MicrophoneState::kUnmuted;
    _cameraOn = info->camera_state == media_session::mojom::CameraState::kTurnedOn;
    const parc::NativeAirPlayState airplay = parc::NativeAirPlayStateForContents(contents);
    _airPlayState = static_cast<PCNativeAirPlayState>(airplay.state);
    _airPlayDeviceName = airplay.device_name.empty() ? nil : base::SysUTF8ToNSString(airplay.device_name);
    const parc::NativeMediaCastState cast = parc::NativeMediaCastStateForContents(contents);
    _castState = static_cast<PCNativeCastState>(cast.state);
    _castDeviceName = cast.device_name.empty() ? nil : base::SysUTF8ToNSString(cast.device_name);
  }
  return self;
}
@end
@implementation PCNativePage (MediaControls)
- (NSObject*)tabAudioState {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self);
  auto* contents = state ? state->web_contents() : nullptr;
  auto* browser = parc::Owner(contents, false);
  return browser ? [[PCNativeTabAudioState alloc] initWithContents:contents browser:browser
                                                          muteRevision:state->mute_revision()] : nil;
}
- (BOOL)tabAudioIsAudible:(NSObject*)snapshot {
  CHECK(NSThread.isMainThread);
  return [snapshot isKindOfClass:PCNativeTabAudioState.class] && ((PCNativeTabAudioState*)snapshot).audible;
}
- (BOOL)tabAudioIsMuted:(NSObject*)snapshot {
  CHECK(NSThread.isMainThread);
  return [snapshot isKindOfClass:PCNativeTabAudioState.class] && ((PCNativeTabAudioState*)snapshot).muted;
}
- (BOOL)toggleTabAudioMuted:(NSObject*)object {
  CHECK(NSThread.isMainThread);
  if (![object isKindOfClass:PCNativeTabAudioState.class]) return NO;
  PCNativeTabAudioState* snapshot = (PCNativeTabAudioState*)object;
  auto* state = parc::State(self);
  auto* contents = state ? state->web_contents() : nullptr;
  auto* browser = parc::Owner(contents, true);
  if (!snapshot || !browser || snapshot->contents_.get() != contents ||
      snapshot->browser_.get() != browser || !snapshot->profile_ ||
      snapshot->profile_.get() != contents->GetBrowserContext() ||
      snapshot->document_.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame() ||
      snapshot->mute_revision_ != state->mute_revision() ||
      snapshot.muted != contents->IsAudioMuted()) return NO;
  contents->SetAudioMuted(!snapshot.muted);
  return YES;
}
- (PCNativeMediaSessionStatus)mediaSessionStatus {
  CHECK(NSThread.isMainThread);
  // The first read creates this page's observer, so later transitions reach
  // nativePageDidChange even if the Mini Player never read mediaState.
  auto* state = parc::State(self);
  return state ? state->Status() : PCNativeMediaSessionStatusInactive;
}
- (uint64_t)mediaControlsRevision {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self);
  return state ? state->ControlsRevision() : 0;
}
- (PCNativeMediaState*)mediaState {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return state ? state->Snapshot() : nil;
}
- (PCNativeMediaState*)admitMediaState {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return state ? state->Snapshot(true) : nil;
}
- (NSObject*)captureMediaPresentationLease {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return state ? state->CapturePresentationLease() : nil;
}
- (void)mediaPresentationDidRemove:(NSObject*)lease {
  CHECK(NSThread.isMainThread);
  if (![lease isKindOfClass:PCNativeMediaPresentationLease.class]) return;
  auto* state = parc::State(self);
  if (state) state->PresentationDidRemove((PCNativeMediaPresentationLease*)lease);
}
- (void)withdrawMediaState {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents ? parc::MediaState::FromWebContents(contents) : nullptr;
  if (state) state->Withdraw();
}
- (BOOL)dismissMediaState:(PCNativeMediaState*)snapshot {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return state && state->Dismiss(snapshot);
}
- (BOOL)performMediaAction:(PCNativeMediaAction)action state:(PCNativeMediaState*)snapshot {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return state && state->Perform(action, snapshot);
}
- (BOOL)setMediaVolume:(double)volume state:(PCNativeMediaState*)snapshot {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return state && state->Volume(volume, snapshot);
}
- (BOOL)canPresentMediaState:(PCNativeMediaState*)snapshot inWindow:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return window && state && state->Validate(snapshot, window, false);
}
- (BOOL)canRevealMediaState:(PCNativeMediaState*)snapshot inWindow:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return window && state && state->Validate(snapshot, window);
}
- (BOOL)canContinueMediaReveal:(PCNativeMediaState*)snapshot inWindow:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return window && state && state->CanContinueReveal(snapshot, window);
}
- (BOOL)dismissMediaState:(PCNativeMediaState*)snapshot inWindow:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return window && state && state->Dismiss(snapshot, window);
}
- (BOOL)performMediaAction:(PCNativeMediaAction)action state:(PCNativeMediaState*)snapshot
                  inWindow:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return window && state && state->Perform(action, snapshot, window);
}
- (BOOL)setMediaVolume:(double)volume state:(PCNativeMediaState*)snapshot inWindow:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self); return window && state && state->Volume(volume, snapshot, window);
}
- (BOOL)showAirPlayPickerForMediaState:(PCNativeMediaState*)snapshot
                        relativeToRect:(NSRect)rect
                                ofView:(NSView*)view
                              inWindow:(NSWindow*)window
                             dismissed:(void (^)(void))dismissed {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self);
  return state && state->ShowAirPlayPicker(snapshot, view, rect, window, dismissed);
}
- (BOOL)showCastChooserForMediaState:(PCNativeMediaState*)snapshot
                      relativeToRect:(NSRect)rect
                              ofView:(NSView*)view
                            inWindow:(NSWindow*)window
                           dismissed:(void (^)(void))dismissed {
  CHECK(NSThread.isMainThread);
  auto* state = parc::State(self);
  return state && state->ShowCastChooser(snapshot, view, rect, window, dismissed);
}
@end

@implementation PCNativeBrowserApplication (TabAudioBatch)
+ (BOOL)setAllTabAudioMuted:(BOOL)muted inWindow:(NSWindow*)window {
  CHECK(NSThread.isMainThread);
  PCNativeBrowserWindow* binding = window ? [PCNativeBrowserApplication windowForNativeWindow:window] : nil;
  auto valid_source = ^BOOL {
    return binding && window && window.visible && !window.miniaturized && window.keyWindow && NSApp.active &&
        !window.attachedSheet && !PCNativeWindowHasSecurityReservation(window) &&
        [PCNativeBrowserApplication windowForNativeWindow:window] == binding;
  };
  if (!valid_source()) return NO;
  struct Target {
    base::WeakPtr<content::WebContents> contents;
    content::WeakDocumentPtr document;
    base::WeakPtr<Profile> profile;
    base::WeakPtr<BrowserWindowInterface> browser;
  };
  std::vector<Target> targets;
  for (auto& pointer : content::WebContentsImpl::GetAllWebContents()) {
    auto* contents = pointer.get();
    auto* browser = parc::Owner(contents, false, true);
    if (!browser) continue;
    auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
    targets.push_back({contents->GetWeakPtr(), contents->GetPrimaryMainFrame()->GetWeakDocumentPtr(),
                       profile->GetWeakPtr(), browser->GetWeakPtr()});
  }
  for (const auto& target : targets) {
    if (!valid_source()) return NO;
    auto* contents = target.contents.get();
    if (!contents || !target.browser || !target.profile || parc::Owner(contents, false, true) != target.browser.get() ||
        target.profile.get() != contents->GetBrowserContext() ||
        target.document.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame()) continue;
    contents->SetAudioMuted(muted);
  }
  return YES;
}
@end
