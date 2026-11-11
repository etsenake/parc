// Copyright 2015 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "third_party/blink/renderer/modules/media_controls/media_controls_impl.h"

#include <limits>
#include <memory>

#include "base/run_loop.h"
#include "base/test/metrics/histogram_tester.h"
#include "build/build_config.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/common/input/web_mouse_event.h"
#include "third_party/blink/public/mojom/frame/user_activation_notification_type.mojom-blink.h"
#include "third_party/blink/public/mojom/input/focus_type.mojom-blink.h"
#include "third_party/blink/public/platform/parc_web_media_player_extension.h"
#include "third_party/blink/renderer/bindings/core/v8/script_promise_tester.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_testing.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_gc_controller.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_mouse_event_init.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_pointer_event_init.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_remote_playback_state.h"
#include "third_party/blink/renderer/core/css/css_property_value_set.h"
#include "third_party/blink/renderer/core/css/document_style_environment_variables.h"
#include "third_party/blink/renderer/core/css/style_engine.h"
#include "third_party/blink/renderer/core/dom/document.h"
#include "third_party/blink/renderer/core/dom/document_parser.h"
#include "third_party/blink/renderer/core/dom/dom_token_list.h"
#include "third_party/blink/renderer/core/dom/element_traversal.h"
#include "third_party/blink/renderer/core/dom/events/event.h"
#include "third_party/blink/renderer/core/dom/shadow_root.h"
#include "third_party/blink/renderer/core/dom/text.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/settings.h"
#include "third_party/blink/renderer/core/geometry/dom_rect.h"
#include "third_party/blink/renderer/core/html/html_head_element.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element_air_play.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element_names.h"
#include "third_party/blink/renderer/core/html/shadow/shadow_element_names.h"
#include "third_party/blink/renderer/core/html/track/text_track.h"
#include "third_party/blink/renderer/core/html/track/vtt/vtt_cue.h"
#include "third_party/blink/renderer/core/html_names.h"
#include "third_party/blink/renderer/core/input/event_handler.h"
#include "third_party/blink/renderer/core/layout/layout_object.h"
#include "third_party/blink/renderer/core/loader/empty_clients.h"
#include "third_party/blink/renderer/core/pointer_type_names.h"
#include "third_party/blink/renderer/core/style/computed_style.h"
#include "third_party/blink/renderer/core/testing/page_test_base.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_cast_button_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_current_time_display_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_download_button_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_fullscreen_button_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_mute_button_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_overflow_menu_button_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_overflow_menu_list_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_overlay_play_button_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_play_button_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_playback_speed_button_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_remaining_time_display_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_timeline_element.h"
#include "third_party/blink/renderer/modules/media_controls/elements/media_control_volume_slider_element.h"
#include "third_party/blink/renderer/modules/remoteplayback/remote_playback.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/thread_state.h"
#include "third_party/blink/renderer/platform/media/remote_playback_client.h"
#include "third_party/blink/renderer/platform/testing/empty_web_media_player.h"
#include "third_party/blink/renderer/platform/testing/runtime_enabled_features_test_helpers.h"
#include "third_party/blink/renderer/platform/testing/unit_test_helpers.h"
#include "third_party/blink/renderer/platform/web_test_support.h"
#include "third_party/blink/renderer/platform/wtf/text/string_to_number.h"
#include "ui/display/mojom/screen_orientation.mojom-blink.h"
#include "ui/display/screen_info.h"

namespace blink {

namespace {

class FakeChromeClient : public EmptyChromeClient {
 public:
  FakeChromeClient() {
    screen_info_.orientation_type =
        display::mojom::blink::ScreenOrientation::kLandscapePrimary;
  }

  // ChromeClient overrides.
  const display::ScreenInfo& GetScreenInfo(LocalFrame&) const override {
    return screen_info_;
  }

 private:
  display::ScreenInfo screen_info_;
};

class MockWebMediaPlayerForImpl : public EmptyWebMediaPlayer,
                                  public ParcWebMediaPlayerExtension {
 public:
  // WebMediaPlayer overrides:
  WebTimeRanges Seekable() const override { return seekable_; }
  bool HasVideo() const override { return true; }
  ParcWebMediaPlayerExtension* GetParcExtension() override { return this; }

  // ParcWebMediaPlayerExtension overrides:
  bool ParcSupportsPlaybackTarget() const override {
    return parc_supports_playback_target_;
  }
  void ParcFastSeek(double seconds, double tolerance_before) override {
    Seek(seconds);
  }
  void ParcEnabledAudioTracksChanged(
      const std::vector<TrackId>& enabled_track_ids) override {}

  bool parc_supports_playback_target_ = false;
  WebTimeRanges seekable_;
};

class StubLocalFrameClientForImpl : public EmptyLocalFrameClient {
 public:
  std::unique_ptr<WebMediaPlayer> CreateWebMediaPlayer(
      HTMLMediaElement&,
      const WebMediaPlayerSource&,
      WebMediaPlayerClient*) override {
    return std::make_unique<MockWebMediaPlayerForImpl>();
  }

  RemotePlaybackClient* CreateRemotePlaybackClient(
      HTMLMediaElement& element) override {
    return &RemotePlayback::From(element);
  }
};

// Parc: a Safari-identity page whose players play to AirPlay targets, as
// the native HLS player does.
class StubSafariLocalFrameClientForImpl : public StubLocalFrameClientForImpl {
 public:
  explicit StubSafariLocalFrameClientForImpl(const char* user_agent)
      : user_agent_(user_agent) {}

  std::unique_ptr<WebMediaPlayer> CreateWebMediaPlayer(
      HTMLMediaElement& element,
      const WebMediaPlayerSource& source,
      WebMediaPlayerClient* client) override {
    auto player = std::make_unique<MockWebMediaPlayerForImpl>();
    player->parc_supports_playback_target_ = true;
    return player;
  }
  String UserAgent() override { return user_agent_; }

 private:
  String user_agent_;
};

Element* GetElementByShadowPseudoId(Node& root_node,
                                    const char* shadow_pseudo_id) {
  for (Element& element : ElementTraversal::DescendantsOf(root_node)) {
    if (element.ShadowPseudoId() == shadow_pseudo_id)
      return &element;
  }
  return nullptr;
}

bool IsElementVisible(Element& element) {
  const CSSPropertyValueSet* inline_style = element.InlineStyle();

  if (!inline_style)
    return element.getAttribute(html_names::kClassAttr) != "transparent";

  if (inline_style->GetPropertyValue(CSSPropertyID::kDisplay) == "none")
    return false;

  if (inline_style->HasProperty(CSSPropertyID::kOpacity) &&
      StringToDouble(inline_style->GetPropertyValue(CSSPropertyID::kOpacity))
              .value_or(0) == 0.0) {
    return false;
  }

  if (inline_style->GetPropertyValue(CSSPropertyID::kVisibility) == "hidden")
    return false;

  if (Element* parent = element.parentElement())
    return IsElementVisible(*parent);

  return true;
}

}  // namespace

class ParcMediaControlsImplTest
    : public PageTestBase,
      private ScopedMediaControlsOverlayPlayButtonForTest {
 public:
  ParcMediaControlsImplTest()
      : ScopedMediaControlsOverlayPlayButtonForTest(true) {}

 protected:
  void SetMediaControlsFromElement(HTMLMediaElement& element) {
    media_controls_ =
        static_cast<MediaControlsImpl*>(element.GetMediaControls());
  }

  void SimulateRemotePlaybackAvailable() {
    RemotePlayback::From(media_controls_->MediaElement())
        .AvailabilityChangedForTesting(/*screen_is_available=*/true);
  }

  void EnsureSizing() {
    media_controls_->NotifyElementSizeChanged(
        media_controls_->MediaElement().GetBoundingClientRect());
  }

  void SetElementSize(int width, int height) {
    media_controls_->NotifyElementSizeChanged(
        DOMRectReadOnly::FromRect(gfx::Rect(0, 0, width, height)));
    test::RunPendingTasks();
  }

  MediaControlsImpl& MediaControls() { return *media_controls_; }
  MediaControlCastButtonElement* CastButtonElement() const {
    return media_controls_->cast_button_.Get();
  }

  bool IsOverflowElementVisible(MediaControlInputElement& element) {
    MediaControlInputElement* overflow_element =
        element.OverflowElementForTests();
    if (!overflow_element) {
      return false;
    }

    Element* overflow_parent_label = overflow_element->parentElement();
    if (!overflow_parent_label) {
      return false;
    }

    const CSSPropertyValueSet* inline_style =
        overflow_parent_label->InlineStyle();
    return inline_style->GetPropertyValue(CSSPropertyID::kDisplay) != "none";
  }

  MockWebMediaPlayerForImpl* WebMediaPlayer() {
    return static_cast<MockWebMediaPlayerForImpl*>(
        MediaControls().MediaElement().GetWebMediaPlayer());
  }

  void LoadMediaWithDuration(double duration) {
    MediaControls().MediaElement().SetSrc(
        AtomicString("https://example.com/foo.mp4"));
    test::RunPendingTasks();
    WebMediaPlayer()->seekable_ = WebTimeRanges(0.0, duration);
    MediaControls().MediaElement().DurationChanged(duration,
                                                   /*request_seek=*/false);
    media_controls_->OnLoadedMetadata();
  }

  void SetReady() {
    MediaControls().MediaElement().SetReadyState(
        HTMLMediaElement::kHaveEnoughData);
  }

  void SetReadyState(HTMLMediaElement::ReadyState state) {
    MediaControls().MediaElement().SetReadyState(state);
  }

  void SetPlayerWireless(bool wireless) {
    ParcMediaElementAirPlay::From(MediaControls().MediaElement())
        .PlaybackTargetIsWirelessChanged(wireless);
  }

 private:
  Persistent<MediaControlsImpl> media_controls_;
};

// AirPlay controls shown to Safari-identity pages.
class ParcMediaControlsImplAirPlayTest : public ParcMediaControlsImplTest {
 protected:
  static constexpr char kSafariUserAgent[] =
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/27.2 Safari/605.1.15";
  static constexpr char kChromeUserAgent[] =
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";

  void SetUp() override { InitializePage(kSafariUserAgent); }

  void InitializePage(const char* user_agent) {
    SetupPageWithClients(
        MakeGarbageCollected<FakeChromeClient>(),
        MakeGarbageCollected<StubSafariLocalFrameClientForImpl>(user_agent));
    GetDocument().write("<video controls></video>");
    SetMediaControlsFromElement(To<HTMLVideoElement>(
        *GetDocument().QuerySelector(AtomicString("video"))));
    GetFrame().GetSettings()->SetScriptEnabled(true);
    LoadMediaWithDuration(60);
    SetReady();
  }

  HTMLVideoElement& Video() {
    return To<HTMLVideoElement>(MediaControls().MediaElement());
  }
  media::mojom::blink::MediaPlayer& Player() { return Video(); }
  RemotePlayback& Remote() { return RemotePlayback::From(Video()); }

  void Play() {
    LocalFrame::NotifyUserActivation(
        &GetFrame(), mojom::UserActivationNotificationType::kTest);
    Video().Play();
    base::RunLoop().RunUntilIdle();
  }

  // The element's media element tasks, then the events they queue.
  void SetWireless(bool wireless) {
    SetPlayerWireless(wireless);
    base::RunLoop().RunUntilIdle();
  }

  ScriptPromise<IDLUndefined> Prompt(ScriptState* script_state,
                                     ExceptionState& exception_state) {
    LocalFrame::NotifyUserActivation(
        &GetFrame(), mojom::UserActivationNotificationType::kTest);
    return Remote().prompt(script_state, exception_state);
  }

  bool HasClass(Element& element, const char* name) {
    return element.classList().contains(AtomicString(name));
  }

  String PlacardText() {
    Node* interstitial = Video().UserAgentShadowRoot()->firstChild();
    return interstitial && interstitial->IsMediaRemotingInterstitial()
               ? interstitial->textContent()
               : String();
  }
};

TEST_F(ParcMediaControlsImplAirPlayTest, ButtonFollowsDevicesAndPlayback) {
  MediaControlCastButtonElement* button = CastButtonElement();
  ASSERT_TRUE(Remote().ParcUsesAirPlay());
  EXPECT_TRUE(HasClass(*button, "parc-airplay"));
  EXPECT_EQ(button->getAttribute(html_names::kAriaLabelAttr), "AirPlay");
  EXPECT_FALSE(button->IsWanted());

  // Devices nearby: shown once the media has played, in the bar.
  Player().ParcSetPlaybackTargetAvailability(true);
  EXPECT_TRUE(Remote().RemotePlaybackAvailable());
  EXPECT_FALSE(button->IsWanted());
  Play();
  EXPECT_TRUE(button->IsWanted());
  SetElementSize(800, 450);
  EXPECT_TRUE(button->DoesFit());
  EXPECT_FALSE(IsOverflowElementVisible(*button));

  // x-webkit-airplay="deny" takes it away.
  Video().setAttribute(parc_media_element_names::XWebkitAirplayAttr(),
                       AtomicString("deny"));
  test::RunPendingTasks();
  EXPECT_FALSE(Remote().RemotePlaybackAvailable());
  EXPECT_FALSE(button->IsWanted());
}

TEST_F(ParcMediaControlsImplAirPlayTest, NoOverlayButton) {
  Video().SetBooleanAttribute(html_names::kControlsAttr, false);
  Element* overlay = GetElementByShadowPseudoId(
      MediaControls(), "-internal-media-controls-overlay-cast-button");
  ASSERT_NE(nullptr, overlay);
  Player().ParcSetPlaybackTargetAvailability(true);
  Play();
  EXPECT_FALSE(IsElementVisible(*overlay));
}

// prompt() opens the AirPlay list; a pick settles it and the state follows
// the route: connecting, connected once the player plays to the device,
// disconnected when the route ends. The button and the placard follow.
TEST_F(ParcMediaControlsImplAirPlayTest, PromptAndStateFollowTheRoute) {
  V8TestingScope scope;
  EnsureSizing();
  Player().ParcSetPlaybackTargetAvailability(true);
  Play();
  MediaControlCastButtonElement* button = CastButtonElement();

  ScriptPromiseTester prompt(scope.GetScriptState(),
                             Prompt(scope.GetScriptState(),
                                    scope.GetExceptionState()));
  EXPECT_FALSE(scope.GetExceptionState().HadException());
  scope.PerformMicrotaskCheckpoint();
  EXPECT_FALSE(prompt.IsFulfilled());
  EXPECT_FALSE(prompt.IsRejected());

  Player().ParcSetPlaybackTarget("6F1B3B57-0D0B-4B4A-9C55-3C3E2E3B1A11",
                                 "Living Room", true, /*tint_argb=*/0,
                                 /*tint_on_light_argb=*/0);
  scope.PerformMicrotaskCheckpoint();
  EXPECT_TRUE(prompt.IsFulfilled());
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(V8RemotePlaybackState::Enum::kConnecting,
            Remote().state().AsEnum());
  EXPECT_TRUE(HasClass(*button, "parc-connecting"));
  EXPECT_FALSE(HasClass(*button, "on"));
  EXPECT_EQ(button->getAttribute(html_names::kAriaLabelAttr),
            "Connecting to Living Room");

  SetWireless(true);
  EXPECT_EQ(V8RemotePlaybackState::Enum::kConnected,
            Remote().state().AsEnum());
  EXPECT_TRUE(HasClass(*button, "on"));
  EXPECT_FALSE(HasClass(*button, "parc-connecting"));
  EXPECT_EQ(button->getAttribute(html_names::kAriaLabelAttr),
            "Playing on Living Room");
  EXPECT_TRUE(Video().IsRemotingInterstitialVisible());
  EXPECT_EQ(PlacardText(),
            String(u"AirPlayThis video is playing on \u201CLiving Room\u201D."));

  Player().ParcSetPlaybackTarget(String(), String(), false, /*tint_argb=*/0,
                                 /*tint_on_light_argb=*/0);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(V8RemotePlaybackState::Enum::kDisconnected,
            Remote().state().AsEnum());
  EXPECT_FALSE(HasClass(*button, "on"));
  EXPECT_FALSE(Video().IsRemotingInterstitialVisible());
}

// The placard names "Apple TV" when the device has no name.
TEST_F(ParcMediaControlsImplAirPlayTest, PlacardWithoutDeviceName) {
  Player().ParcSetPlaybackTarget("6F1B3B57-0D0B-4B4A-9C55-3C3E2E3B1A11",
                                 String(), true, /*tint_argb=*/0,
                                 /*tint_on_light_argb=*/0);
  SetWireless(true);
  EXPECT_TRUE(Video().IsRemotingInterstitialVisible());
  EXPECT_EQ(PlacardText(),
            String(u"AirPlayThis video is playing on \u201CApple TV\u201D."));
}

// The window's Space tint (the Mini Player's) colours the connecting and
// connected button and the placard's glyph; without one, the CSS accent.
TEST_F(ParcMediaControlsImplAirPlayTest, SpaceTintColoursButtonAndPlacard) {
  Player().ParcSetPlaybackTargetAvailability(true);
  Play();
  MediaControlCastButtonElement* button = CastButtonElement();
  auto background = [](Element& element) {
    const CSSPropertyValueSet* style = element.InlineStyle();
    return style ? style->GetPropertyValue(CSSPropertyID::kBackgroundImage)
                 : String();
  };
  EXPECT_TRUE(background(*button).empty());

  Player().ParcSetPlaybackTarget("6F1B3B57-0D0B-4B4A-9C55-3C3E2E3B1A11",
                                 "Living Room", true, 0xFF4D3B8A, 0xFF1C5B84);
  base::RunLoop().RunUntilIdle();
  EXPECT_TRUE(background(*button).contains("rgba(77,59,138,1)"));

  SetWireless(true);
  EXPECT_TRUE(background(*button).contains("rgba(77,59,138,1)"));
  Element* icon = GetElementByShadowPseudoId(
      *Video().UserAgentShadowRoot(), "-internal-media-remoting-cast-icon");
  ASSERT_NE(nullptr, icon);
  EXPECT_TRUE(background(*icon).contains("rgba(77,59,138,1)"));

  // The overflow menu's item takes the tint for the menu's light or dark
  // background.
  MediaControlInputElement* item = button->OverflowElementForTests();
  ASSERT_NE(nullptr, item);
  EXPECT_TRUE(background(*item).starts_with("light-dark("));
  EXPECT_TRUE(background(*item).contains("rgba(28,91,132,1)"));
  EXPECT_TRUE(background(*item).contains("rgba(77,59,138,1)"));

  // The Space changes while connected: both recolour at once.
  Player().ParcSetPlaybackTarget("6F1B3B57-0D0B-4B4A-9C55-3C3E2E3B1A11",
                                 "Living Room", true, 0xFFA487D6, 0xFF1C5B84);
  EXPECT_TRUE(background(*button).contains("rgba(164,135,214,1)"));
  EXPECT_TRUE(background(*icon).contains("rgba(164,135,214,1)"));
  EXPECT_TRUE(background(*item).contains("rgba(164,135,214,1)"));

  Player().ParcSetPlaybackTarget(String(), String(), false, /*tint_argb=*/0,
                                 /*tint_on_light_argb=*/0);
  base::RunLoop().RunUntilIdle();
  EXPECT_TRUE(background(*button).empty());
}

// playbackTargetPickerWasDismissed rejects the prompt with NotAllowedError.
TEST_F(ParcMediaControlsImplAirPlayTest, DismissedListRejectsPrompt) {
  V8TestingScope scope;
  Player().ParcSetPlaybackTargetAvailability(true);
  ScriptPromiseTester prompt(scope.GetScriptState(),
                             Prompt(scope.GetScriptState(),
                                    scope.GetExceptionState()));
  Player().ParcPlaybackTargetPickerDismissed();
  scope.PerformMicrotaskCheckpoint();
  EXPECT_TRUE(prompt.IsRejected());
  EXPECT_EQ(V8RemotePlaybackState::Enum::kDisconnected,
            Remote().state().AsEnum());
}

// RemotePlayback::prompt() on macOS: NotSupportedError before metadata and
// without devices while disconnected.
TEST_F(ParcMediaControlsImplAirPlayTest, PromptNeedsMetadataAndDevices) {
  V8TestingScope scope;
  Player().ParcSetPlaybackTargetAvailability(true);
  SetReadyState(HTMLMediaElement::kHaveNothing);
  {
    DummyExceptionStateForTesting exception_state;
    Prompt(scope.GetScriptState(), exception_state);
    EXPECT_EQ(exception_state.CodeAs<DOMExceptionCode>(),
              DOMExceptionCode::kNotSupportedError);
  }
  SetReady();
  Player().ParcSetPlaybackTargetAvailability(false);
  {
    DummyExceptionStateForTesting exception_state;
    Prompt(scope.GetScriptState(), exception_state);
    EXPECT_EQ(exception_state.CodeAs<DOMExceptionCode>(),
              DOMExceptionCode::kNotSupportedError);
  }
}

class ParcMediaControlsImplAirPlayChromeTest
    : public ParcMediaControlsImplAirPlayTest {
 protected:
  void SetUp() override { InitializePage(kChromeUserAgent); }
};

// A Chrome-identity page keeps Chrome's Cast button and Remote Playback.
TEST_F(ParcMediaControlsImplAirPlayChromeTest, ChromePageKeepsCast) {
  EnsureSizing();
  EXPECT_FALSE(Remote().ParcUsesAirPlay());
  EXPECT_FALSE(HasClass(*CastButtonElement(), "parc-airplay"));
  Player().ParcSetPlaybackTargetAvailability(true);
  EXPECT_FALSE(Remote().RemotePlaybackAvailable());
  SimulateRemotePlaybackAvailable();
  EXPECT_TRUE(IsOverflowElementVisible(*CastButtonElement()));
}

}  // namespace blink
