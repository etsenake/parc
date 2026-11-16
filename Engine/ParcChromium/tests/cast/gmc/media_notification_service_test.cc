// Copyright 2026 Parc contributors.
#include "parc/native/native_cast_route.h"

#include "chrome/browser/ui/global_media_controls/media_notification_service.h"

#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/run_loop.h"
#include "base/test/scoped_feature_list.h"
#include "base/time/time.h"
#include "base/unguessable_token.h"
#include "chrome/browser/media/router/chrome_media_router_factory.h"
#include "chrome/browser/media/router/media_router_feature.h"
#include "chrome/browser/sessions/session_tab_helper_factory.h"
#include "chrome/browser/ui/global_media_controls/test_helper.h"
#include "chrome/test/base/chrome_render_view_host_test_harness.h"
#include "components/global_media_controls/public/media_item_manager.h"
#include "components/global_media_controls/public/media_session_item_producer.h"
#include "components/global_media_controls/public/media_session_notification_item.h"
#include "components/media_router/browser/media_router_factory.h"
#include "components/media_router/browser/presentation/start_presentation_context.h"
#include "components/media_router/browser/test/mock_media_router.h"
#include "components/media_router/common/media_route.h"
#include "components/media_router/common/media_sink.h"
#include "components/media_router/common/media_source.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/back_forward_cache.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/presentation_request.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/back_forward_cache_util.h"
#include "media/base/audio_codecs.h"
#include "media/base/video_codecs.h"
#include "services/media_session/public/mojom/audio_focus.mojom.h"
#include "services/media_session/public/mojom/media_session.mojom.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "url/gurl.h"
#include "url/origin.h"

using global_media_controls::MediaSessionNotificationItem;
using media_router::MediaRoute;
using media_router::StartPresentationContext;
using media_session::mojom::AudioFocusRequestState;
using media_session::mojom::AudioFocusRequestStatePtr;
using media_session::mojom::MediaSessionInfo;
using media_session::mojom::MediaSessionInfoPtr;
using testing::_;
using testing::NiceMock;
using testing::Return;

class ParcMediaNotificationServiceTest
    : public ChromeRenderViewHostTestHarness {
 public:
  ParcMediaNotificationServiceTest()
      : ChromeRenderViewHostTestHarness(
            base::test::TaskEnvironment::TimeSource::MOCK_TIME,
            base::test::TaskEnvironment::MainThreadType::UI) {}

  void SetUp() override {
    ChromeRenderViewHostTestHarness::SetUp();
    media_router::ChromeMediaRouterFactory::GetInstance()->SetTestingFactory(
        profile(), base::BindRepeating(&media_router::MockMediaRouter::Create));
    service_ = std::make_unique<MediaNotificationService>(profile(), false);
  }

  void TearDown() override {
    SimulateCloseDialog();
    service_.reset();
    ChromeRenderViewHostTestHarness::TearDown();
  }

 protected:
  base::UnguessableToken SimulatePlayingControllableMedia(
      base::UnguessableToken id) {
    SimulateFocusGained(id, true);
    SimulateNecessaryMetadata(id);
    return id;
  }

  base::UnguessableToken SimulatePlayingControllableMediaForWebContents(
      content::WebContents* contents) {
    content::MediaSession::Get(contents);
    auto id = content::MediaSession::GetRequestIdFromWebContents(contents);
    SimulatePlayingControllableMedia(id);
    base::RunLoop().RunUntilIdle();
    return id;
  }

  AudioFocusRequestStatePtr CreateFocusRequest(const base::UnguessableToken& id,
                                               bool controllable) {
    MediaSessionInfoPtr session_info(MediaSessionInfo::New());
    session_info->is_controllable = controllable;

    AudioFocusRequestStatePtr focus(AudioFocusRequestState::New());
    focus->request_id = id;
    focus->session_info = std::move(session_info);
    return focus;
  }

  void SimulateFocusGained(const base::UnguessableToken& id,
                           bool controllable) {
    service_->media_session_item_producer_->OnFocusGained(
        CreateFocusRequest(id, controllable));
  }

  void SimulateFocusLost(const base::UnguessableToken& id) {
    AudioFocusRequestStatePtr focus(AudioFocusRequestState::New());
    focus->request_id = id;
    service_->media_session_item_producer_->OnFocusLost(std::move(focus));
  }

  void SimulateCloseDialog() {
    service_->media_item_manager()->SetDialogDelegate(nullptr);
    base::RunLoop().RunUntilIdle();
  }

  void SimulateNecessaryMetadata(const base::UnguessableToken& id) {
    auto* session_item = GetNotificationSessionItem(id);
    ASSERT_NE(nullptr, session_item);

    media_session::MediaMetadata metadata;
    metadata.title = u"title";
    metadata.artist = u"artist";
    session_item->MediaSessionMetadataChanged(std::move(metadata));
  }

  MediaSessionNotificationItem* GetNotificationSessionItem(
      const base::UnguessableToken& id) {
    return static_cast<MediaSessionNotificationItem*>(
        service_->media_session_item_producer_->GetMediaItem(id.ToString())
            .get());
  }

  MediaNotificationService* service() { return service_.get(); }

 private:
  std::unique_ptr<MediaNotificationService> service_;
};

class ParcMediaNotificationServiceCastTest
    : public ParcMediaNotificationServiceTest {
 public:
  void SetUp() override {
    presentation_manager_ =
        std::make_unique<NiceMock<MockWebContentsPresentationManager>>();
    media_router::WebContentsPresentationManager::SetTestInstance(
        presentation_manager_.get());
    ParcMediaNotificationServiceTest::SetUp();
  }

  void TearDown() override {
    media_router::WebContentsPresentationManager::SetTestInstance(nullptr);
    ParcMediaNotificationServiceTest::TearDown();
  }

 protected:
  content::PresentationRequest CreatePresentationRequest() {
    return content::PresentationRequest(main_rfh()->GetGlobalId(),
                                        {GURL(), GURL()},
                                        url::Origin::Create(GURL()));
  }

  std::unique_ptr<StartPresentationContext> CreateStartPresentationContext(
      content::PresentationRequest presentation_request,
      StartPresentationContext::PresentationConnectionCallback success_cb =
          base::DoNothing(),
      StartPresentationContext::PresentationConnectionErrorCallback error_cb =
          base::DoNothing()) {
    return std::make_unique<StartPresentationContext>(
        presentation_request, std::move(success_cb), std::move(error_cb));
  }

  void SetMediaRoutesManagedByPresentationManager(
      std::vector<MediaRoute> routes) {
    ON_CALL(*presentation_manager_, GetMediaRoutes())
        .WillByDefault(Return(routes));
  }

  base::OnceCallback<void(bool)> ParcRequestMediaRemoting(
      const std::string& item_id) {
    return MediaNotificationService::ParcRequestMediaRemoting(item_id);
  }

  void SetDefaultPresentationRequest(
      const content::PresentationRequest& request) {
    presentation_manager_->SetDefaultPresentationRequest(request);
  }

  bool HasPresentationContext() { return service()->context_ != nullptr; }

 private:
  std::unique_ptr<MockWebContentsPresentationManager> presentation_manager_;
};

TEST_F(ParcMediaNotificationServiceCastTest, ParcCastRouteForWebContents) {
  CreateSessionServiceTabHelper(web_contents());
  const GURL url("cast:233637DE");
  MediaRoute launching("launching",
                       media_router::MediaSource::ForPresentationUrl(url),
                       "sink_id", "description", true);
  launching.set_is_connecting(true);
  EXPECT_FALSE(parc::CastRouteForWebContents(
      web_contents(), {launching}));

  SetDefaultPresentationRequest(content::PresentationRequest(
      main_rfh()->GetGlobalId(), {url},
      url::Origin::Create(GURL("https://example.test"))));
  auto route = parc::CastRouteForWebContents(
      web_contents(), {launching});
  ASSERT_TRUE(route);
  EXPECT_TRUE(route->is_connecting());

  MediaRoute connected = launching;
  connected.set_is_connecting(false);
  EXPECT_FALSE(parc::CastRouteForWebContents(
      web_contents(), {connected}));
  SetMediaRoutesManagedByPresentationManager({launching});
  route = parc::CastRouteForWebContents(
      web_contents(), {connected});
  ASSERT_TRUE(route);
  EXPECT_EQ("launching", route->media_route_id());
  EXPECT_FALSE(route->is_connecting());
  EXPECT_FALSE(
      parc::CastRouteForWebContents(web_contents(), {}));

  SetMediaRoutesManagedByPresentationManager({});
  MediaRoute remote(
      "remote",
      media_router::MediaSource::ForRemotePlayback(
          sessions::SessionTabHelper::IdForTab(web_contents()).id(),
          media::VideoCodec::kH264, media::AudioCodec::kAAC),
      "sink_id", "description", true);
  route = parc::CastRouteForWebContents(
      web_contents(), {connected, remote});
  ASSERT_TRUE(route);
  EXPECT_EQ("remote", route->media_route_id());
}

namespace {
media_router::MediaSink ParcCastSink(media_router::SinkIconType icon) {
  return media_router::MediaSink(
      "sink_id", "sink", icon, media_router::mojom::MediaRouteProviderId::CAST);
}
}

TEST_F(ParcMediaNotificationServiceCastTest, ParcCastSpeakerAvailability) {
  CreateSessionServiceTabHelper(web_contents());
  const auto tv = ParcCastSink(media_router::SinkIconType::CAST);
  const auto speaker = ParcCastSink(media_router::SinkIconType::CAST_AUDIO);
  const auto group = ParcCastSink(media_router::SinkIconType::CAST_AUDIO_GROUP);

  EXPECT_FALSE(parc::CastSpeakerSourceForWebContents(web_contents()));
  EXPECT_FALSE(parc::HasCastSpeaker({}));
  EXPECT_FALSE(parc::HasCastSpeaker({tv}));
  EXPECT_FALSE(parc::HasCastSpeaker(
      {ParcCastSink(media_router::SinkIconType::GENERIC),
       ParcCastSink(media_router::SinkIconType::WIRED_DISPLAY)}));
  EXPECT_TRUE(parc::HasCastSpeaker({speaker}));
  EXPECT_TRUE(parc::HasCastSpeaker({group}));
  EXPECT_TRUE(parc::HasCastSpeaker({tv, speaker}));

  SetDefaultPresentationRequest(content::PresentationRequest(
      main_rfh()->GetGlobalId(), {GURL("cast:233637DE")},
      url::Origin::Create(GURL("https://example.test"))));
  const auto source = parc::CastSpeakerSourceForWebContents(web_contents());
  ASSERT_TRUE(source);
  EXPECT_TRUE(source->IsTabMirroringSource());
  EXPECT_EQ(sessions::SessionTabHelper::IdForTab(web_contents()).id(),
            source->TabId());
  EXPECT_FALSE(parc::HasCastSpeaker({tv}));
}

TEST_F(ParcMediaNotificationServiceCastTest,
       ParcCastSpeakerNeedsTabIdentity) {
  SetDefaultPresentationRequest(content::PresentationRequest(
      main_rfh()->GetGlobalId(), {GURL("cast:233637DE")},
      url::Origin::Create(GURL("https://example.test"))));
  EXPECT_FALSE(parc::CastSpeakerSourceForWebContents(web_contents()));
}

class ParcWithoutAudioTabMirroring {
 protected:
  ParcWithoutAudioTabMirroring() {
    features_.InitAndDisableFeature(media_router::kFallbackToAudioTabMirroring);
  }

 private:
  base::test::ScopedFeatureList features_;
};

class ParcMediaNotificationServiceNoSpeakerFallbackTest
    : private ParcWithoutAudioTabMirroring,
      public ParcMediaNotificationServiceCastTest {};

TEST_F(ParcMediaNotificationServiceNoSpeakerFallbackTest,
       ParcCastSpeakerFollowsDeviceListFallback) {
  CreateSessionServiceTabHelper(web_contents());
  SetDefaultPresentationRequest(content::PresentationRequest(
      main_rfh()->GetGlobalId(), {GURL("cast:233637DE")},
      url::Origin::Create(GURL("https://example.test"))));
  EXPECT_FALSE(parc::CastSpeakerSourceForWebContents(web_contents()));
}

TEST_F(ParcMediaNotificationServiceCastTest,
       ParcFrozenSessionForWebContents) {
  EXPECT_FALSE(service()->ParcHasFrozenSessionForWebContents(web_contents()));
  auto id = SimulatePlayingControllableMediaForWebContents(web_contents());
  EXPECT_TRUE(service()->HasActiveNotificationsForWebContents(web_contents()));
  EXPECT_FALSE(service()->ParcHasFrozenSessionForWebContents(web_contents()));

  SimulateFocusLost(id);
  EXPECT_FALSE(service()->HasActiveNotificationsForWebContents(web_contents()));
  EXPECT_TRUE(service()->ParcHasFrozenSessionForWebContents(web_contents()));

  task_environment()->FastForwardBy(base::Seconds(3));
  EXPECT_EQ(nullptr, GetNotificationSessionItem(id));
  EXPECT_FALSE(service()->HasActiveNotificationsForWebContents(web_contents()));
  EXPECT_FALSE(service()->ParcHasFrozenSessionForWebContents(web_contents()));
}

TEST_F(ParcMediaNotificationServiceCastTest,
       ParcRemotingLaunchedAfterNavigation) {
  NavigateAndCommit(GURL("https://example.test/"));
  content::DisableBackForwardCacheForTesting(
      web_contents(), content::BackForwardCache::TEST_REQUIRES_NO_CACHING);
  CreateSessionServiceTabHelper(web_contents());
  auto id = SimulatePlayingControllableMediaForWebContents(web_contents());
  auto* router = static_cast<media_router::MockMediaRouter*>(
      media_router::MediaRouterFactory::GetApiForBrowserContext(profile()));
  MediaRoute remote(
      "remote",
      media_router::MediaSource::ForRemotePlayback(
          sessions::SessionTabHelper::IdForTab(web_contents()).id(),
          media::VideoCodec::kH264, media::AudioCodec::kAAC),
      "sink_id", "description", true);
  ON_CALL(*router, GetCurrentRoutes())
      .WillByDefault(Return(std::vector<MediaRoute>{remote}));
  EXPECT_CALL(*router, TerminateRoute(_)).Times(0);
  ParcRequestMediaRemoting(id.ToString()).Run(true);
  testing::Mock::VerifyAndClearExpectations(router);

  auto launched = ParcRequestMediaRemoting(id.ToString());
  NavigateAndCommit(GURL("https://other.test/"));
  EXPECT_CALL(*router, TerminateRoute("remote"));
  std::move(launched).Run(true);
}

TEST_F(ParcMediaNotificationServiceCastTest,
       ReplacementRequestCancelsIfOldCallbackDestroysItsPage) {
  SimulatePlayingControllableMediaForWebContents(web_contents());
  std::unique_ptr<content::WebContents> second(CreateTestWebContents());
  SimulatePlayingControllableMediaForWebContents(second.get());
  auto old = CreateStartPresentationContext(
      CreatePresentationRequest(), base::DoNothing(),
      base::BindOnce([](std::unique_ptr<content::WebContents>* page,
                        const blink::mojom::PresentationError&) { page->reset(); },
                     &second));
  service()->OnStartPresentationContextCreated(std::move(old));
  content::PresentationRequest request(
      second->GetPrimaryMainFrame()->GetGlobalId(), {GURL(), GURL()},
      url::Origin::Create(GURL()));
  bool canceled = false;
  auto replacement = CreateStartPresentationContext(
      request, base::DoNothing(),
      base::BindOnce([](bool* canceled, const blink::mojom::PresentationError&) {
        *canceled = true;
      }, &canceled));
  service()->OnStartPresentationContextCreated(std::move(replacement));
  EXPECT_FALSE(second);
  EXPECT_TRUE(canceled);
  EXPECT_FALSE(HasPresentationContext());
}
