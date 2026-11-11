// Copyright 2016 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "third_party/blink/renderer/modules/remoteplayback/remote_playback.h"

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "mojo/public/cpp/bindings/receiver_set.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/mojom/frame/user_activation_notification_type.mojom-blink.h"
#include "third_party/blink/public/mojom/presentation/presentation.mojom-blink.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/parc_web_media_player_extension.h"
#include "third_party/blink/renderer/bindings/core/v8/script_function.h"
#include "third_party/blink/renderer/bindings/core/v8/script_promise_tester.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_testing.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_remote_playback_availability_callback.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_remote_playback_state.h"
#include "third_party/blink/renderer/core/dom/events/native_event_listener.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/core/html/media/html_media_test_helper.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/testing/dummy_page_holder.h"
#include "third_party/blink/renderer/core/testing/mock_function_scope.h"
#include "third_party/blink/renderer/core/testing/page_test_base.h"
#include "third_party/blink/renderer/modules/presentation/mock_presentation_service.h"
#include "third_party/blink/renderer/modules/presentation/presentation_controller.h"
#include "third_party/blink/renderer/modules/remoteplayback/html_media_element_remote_playback.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/scheduler/public/page_scheduler.h"
#include "third_party/blink/renderer/platform/testing/empty_web_media_player.h"
#include "third_party/blink/renderer/platform/testing/runtime_enabled_features_test_helpers.h"
#include "third_party/blink/renderer/platform/testing/task_environment.h"
#include "third_party/blink/renderer/platform/testing/unit_test_helpers.h"

namespace blink {

namespace {

class MockFunction : public ScriptFunction {
 public:
  MockFunction() = default;
  MOCK_METHOD2(Call, ScriptValue(ScriptState*, ScriptValue));
};

class MockEventListenerForRemotePlayback : public NativeEventListener {
 public:
  MOCK_METHOD2(Invoke, void(ExecutionContext* executionContext, Event*));
};

class MockPresentationController final : public PresentationController {
 public:
  explicit MockPresentationController(LocalDOMWindow& window)
      : PresentationController(window) {}
  ~MockPresentationController() override = default;

  MOCK_METHOD1(AddAvailabilityObserver,
               void(PresentationAvailabilityObserver*));
  MOCK_METHOD1(RemoveAvailabilityObserver,
               void(PresentationAvailabilityObserver*));
};

class MockWebMediaPlayerForRemotePlayback final
    : public EmptyWebMediaPlayer,
      public ParcWebMediaPlayerExtension {
 public:
  MOCK_METHOD0(RequestMediaRemoting, void());
  ParcWebMediaPlayerExtension* GetParcExtension() override { return this; }
  MOCK_METHOD1(ParcSetCastPrompted, void(bool));
  void ParcFastSeek(double seconds, double tolerance_before) override {
    Seek(seconds);
  }
  void ParcEnabledAudioTracksChanged(
      const std::vector<TrackId>& enabled_track_ids) override {}
};
}  // namespace

class ParcRemotePlaybackTest : public testing::Test,
                               private ScopedRemotePlaybackBackendForTest {
 public:
  ParcRemotePlaybackTest() : ScopedRemotePlaybackBackendForTest(true) {}

  void SetUp() override {
    page_holder_ = std::make_unique<DummyPageHolder>();
    element_ =
        MakeGarbageCollected<HTMLVideoElement>(page_holder_->GetDocument());
    ChangeMediaElementDuration(60);
  }

 protected:
  void SetState(RemotePlayback& remote_playback,
                mojom::blink::PresentationConnectionState state) {
    remote_playback.StateChanged(state);
  }

  bool IsListening(RemotePlayback& remote_playback) {
    return remote_playback.is_listening_;
  }

  void ChangeMediaElementDuration(double duration) {
    element_->DurationChanged(duration, false);
  }

  RemotePlayback& get_remote_playback() {
    return RemotePlayback::From(*element_);
  }

  DummyPageHolder* page_holder() { return page_holder_.get(); }

  // Parc: moves the element to |page|'s document, as a Safari-identity page
  // moves it with its player.
  void MoveElementTo(DummyPageHolder& page) {
    page.GetDocument().adoptNode(element_, ASSERT_NO_EXCEPTION);
    get_remote_playback().ParcDidMoveToDocument();
  }
  void DestroyPage() { page_holder_.reset(); }

 private:
  test::TaskEnvironment task_environment_;
  std::unique_ptr<DummyPageHolder> page_holder_;
  Persistent<HTMLVideoElement> element_ = nullptr;
};

// Parc: a moved element watches availability through its new document's
// frame, which its prompt and events use too.
TEST_F(ParcRemotePlaybackTest, ParcMovedElementWatchesThroughItsNewDocument) {
  V8TestingScope scope;
  RemotePlayback& remote_playback = get_remote_playback();
  auto new_page = std::make_unique<DummyPageHolder>();
  LocalDOMWindow& old_window = *page_holder()->GetFrame().DomWindow();
  LocalDOMWindow& new_window = *new_page->GetFrame().DomWindow();
  auto* old_controller =
      MakeGarbageCollected<MockPresentationController>(old_window);
  Supplement<LocalDOMWindow>::ProvideTo(
      old_window, static_cast<PresentationController*>(old_controller));
  auto* new_controller =
      MakeGarbageCollected<MockPresentationController>(new_window);
  Supplement<LocalDOMWindow>::ProvideTo(
      new_window, static_cast<PresentationController*>(new_controller));
  EXPECT_CALL(*old_controller,
              AddAvailabilityObserver(testing::Eq(&remote_playback)));
  EXPECT_CALL(*old_controller,
              RemoveAvailabilityObserver(testing::Eq(&remote_playback)));
  EXPECT_CALL(*new_controller,
              AddAvailabilityObserver(testing::Eq(&remote_playback)));

  MockFunction* callback_function = MakeGarbageCollected<MockFunction>();
  EXPECT_CALL(*callback_function, Call(testing::_, testing::_))
      .Times(testing::AnyNumber());
  remote_playback.watchAvailability(
      scope.GetScriptState(),
      V8RemotePlaybackAvailabilityCallback::Create(
          callback_function->ToV8Function(scope.GetScriptState())),
      scope.GetExceptionState());
  remote_playback.SourceChanged(WebURL(KURL("http://www.example.com")), true);
  ASSERT_TRUE(IsListening(remote_playback));

  MoveElementTo(*new_page);
  EXPECT_EQ(&new_window, remote_playback.GetExecutionContext());
  EXPECT_TRUE(IsListening(remote_playback));

  testing::Mock::VerifyAndClear(callback_function);
  testing::Mock::VerifyAndClear(old_controller);
  testing::Mock::VerifyAndClear(new_controller);
}

// Parc: a session in progress stays with the frame that started it, and the
// element's document takes over once it ends.
TEST_F(ParcRemotePlaybackTest, ParcSessionStaysWithTheFrameThatStartedIt) {
  RemotePlayback& remote_playback = get_remote_playback();
  auto new_page = std::make_unique<DummyPageHolder>();
  SetState(remote_playback,
           mojom::blink::PresentationConnectionState::CONNECTED);

  MoveElementTo(*new_page);
  EXPECT_EQ(page_holder()->GetFrame().DomWindow(),
            remote_playback.GetExecutionContext());

  SetState(remote_playback, mojom::blink::PresentationConnectionState::CLOSED);
  EXPECT_EQ(new_page->GetFrame().DomWindow(),
            remote_playback.GetExecutionContext());
}

// Parc: when the frame that started the session goes first, the session ends
// with it and the element's new document hears so.
TEST_F(ParcRemotePlaybackTest,
       ParcSessionEndsInTheNewDocumentWhenItsFrameGoes) {
  RemotePlayback& remote_playback = get_remote_playback();
  auto new_page = std::make_unique<DummyPageHolder>();
  auto* disconnect_handler = MakeGarbageCollected<
      testing::StrictMock<MockEventListenerForRemotePlayback>>();
  remote_playback.addEventListener(event_type_names::kDisconnect,
                                   disconnect_handler);
  SetState(remote_playback,
           mojom::blink::PresentationConnectionState::CONNECTED);
  MoveElementTo(*new_page);

  EXPECT_CALL(*disconnect_handler, Invoke(testing::_, testing::_)).Times(0);
  DestroyPage();
  testing::Mock::VerifyAndClear(disconnect_handler);
  EXPECT_CALL(*disconnect_handler, Invoke(testing::_, testing::_)).Times(1);
  test::RunPendingTasks();
  EXPECT_EQ(mojom::blink::PresentationConnectionState::CLOSED,
            remote_playback.GetState());
  EXPECT_EQ(new_page->GetFrame().DomWindow(),
            remote_playback.GetExecutionContext());
  testing::Mock::VerifyAndClear(disconnect_handler);
}

// Parc: a cast whose connection comes while its page is in the back/forward
// cache.
class ParcRemotePlaybackBackForwardCacheTest
    : public PageTestBase,
      private ScopedRemotePlaybackBackendForTest {
 public:
  ParcRemotePlaybackBackForwardCacheTest()
      : ScopedRemotePlaybackBackendForTest(true) {}

  void SetUp() override {
    auto player = std::make_unique<MockWebMediaPlayerForRemotePlayback>();
    player_ = player.get();
    SetupPageWithClients(nullptr,
                         MakeGarbageCollected<test::MediaStubLocalFrameClient>(
                             std::move(player)),
                         nullptr);
    GetFrame().GetBrowserInterfaceBroker().SetBinderForTesting(
        mojom::blink::PresentationService::Name_,
        base::BindRepeating(
            &ParcRemotePlaybackBackForwardCacheTest::BindPresentationService,
            base::Unretained(this)));
    EXPECT_CALL(presentation_service_, StartPresentationInternal)
        .WillRepeatedly(
            [this](const Vector<KURL>&,
                   MockPresentationService::StartPresentationCallback&
                       callback) { start_callback_ = std::move(callback); });

    video_ = MakeGarbageCollected<HTMLVideoElement>(GetDocument());
    GetDocument().body()->appendChild(video_);
    video_->SetSrc(AtomicString("http://example.com/foo.mp4"));
    test::RunPendingTasks();
    ASSERT_EQ(player_, video_->GetWebMediaPlayer());
    video_->DurationChanged(60, false);
    remote_playback().SourceChanged(KURL("http://example.com/foo.mp4"), true);

    connecting_ = MakeGarbageCollected<
        testing::StrictMock<MockEventListenerForRemotePlayback>>();
    remote_playback().addEventListener(event_type_names::kConnecting,
                                       connecting_);
  }

  void TearDown() override {
    GetFrame().GetBrowserInterfaceBroker().SetBinderForTesting(
        mojom::blink::PresentationService::Name_, {});
    PageTestBase::TearDown();
  }

 protected:
  RemotePlayback& remote_playback() { return RemotePlayback::From(*video_); }

  // The user picks a receiver; the browser then connects to it.
  ScriptPromise<IDLUndefined> Prompt(V8TestingScope& scope) {
    LocalFrame::NotifyUserActivation(
        &GetFrame(), mojom::UserActivationNotificationType::kTest);
    ScriptPromise<IDLUndefined> promise = remote_playback().prompt(
        scope.GetScriptState(), scope.GetExceptionState());
    base::RunLoop().RunUntilIdle();
    EXPECT_TRUE(start_callback_);
    return promise;
  }

  void Connect() {
    mojo::PendingRemote<mojom::blink::PresentationConnection> connection;
    receiver_end_ = connection.InitWithNewPipeAndPassReceiver();
    std::move(start_callback_)
        .Run(mojom::blink::PresentationConnectionResult::New(
                 mojom::blink::PresentationInfo::New(
                     KURL("remote-playback:media-element"), "id"),
                 std::move(connection),
                 sender_end_.InitWithNewPipeAndPassReceiver()),
             nullptr);
    base::RunLoop().RunUntilIdle();
  }

  void EnterBackForwardCache() {
    PageScheduler* scheduler = GetPage().GetPageScheduler();
    scheduler->SetPageVisible(false);
    scheduler->SetPageBackForwardCached(true);
    scheduler->SetPageFrozen(true);
  }

  // A background tab frozen without leaving its page.
  void FreezePage(bool frozen) {
    PageScheduler* scheduler = GetPage().GetPageScheduler();
    if (frozen) {
      scheduler->SetPageVisible(false);
      scheduler->SetPageFrozen(true);
    } else {
      scheduler->SetPageFrozen(false);
      scheduler->SetPageVisible(true);
      base::RunLoop().RunUntilIdle();
    }
  }

  void RestoreFromBackForwardCache() {
    PageScheduler* scheduler = GetPage().GetPageScheduler();
    scheduler->SetPageFrozen(false);
    scheduler->SetPageBackForwardCached(false);
    scheduler->SetPageVisible(true);
    base::RunLoop().RunUntilIdle();
  }

  V8RemotePlaybackState::Enum State() {
    return remote_playback().state().AsEnum();
  }

  MockWebMediaPlayerForRemotePlayback* player_ = nullptr;
  testing::NiceMock<MockPresentationService> presentation_service_;
  MockPresentationService::StartPresentationCallback start_callback_;
  Persistent<MockEventListenerForRemotePlayback> connecting_;

 private:
  void BindPresentationService(mojo::ScopedMessagePipeHandle handle) {
    receivers_.Add(&presentation_service_,
                   mojo::PendingReceiver<mojom::blink::PresentationService>(
                       std::move(handle)));
  }

  mojo::ReceiverSet<mojom::blink::PresentationService> receivers_;
  mojo::PendingReceiver<mojom::blink::PresentationConnection> receiver_end_;
  mojo::PendingRemote<mojom::blink::PresentationConnection> sender_end_;
  Persistent<HTMLVideoElement> video_;
};

TEST_F(ParcRemotePlaybackBackForwardCacheTest,
       ConnectionCastsBeforePageIsShown) {
  V8TestingScope scope;
  ScriptPromiseTester prompt(scope.GetScriptState(), Prompt(scope));

  EnterBackForwardCache();
  EXPECT_CALL(*player_, RequestMediaRemoting());
  Connect();
  testing::Mock::VerifyAndClearExpectations(player_);
  scope.PerformMicrotaskCheckpoint();
  EXPECT_FALSE(prompt.IsFulfilled());
  EXPECT_EQ(V8RemotePlaybackState::Enum::kDisconnected, State());

  // The page sees the connection, in order, when it is shown.
  EXPECT_CALL(*player_, RequestMediaRemoting()).Times(0);
  EXPECT_CALL(*connecting_, Invoke);
  RestoreFromBackForwardCache();
  EXPECT_EQ(V8RemotePlaybackState::Enum::kConnecting, State());
  scope.PerformMicrotaskCheckpoint();
  EXPECT_TRUE(prompt.IsFulfilled());
}

TEST_F(ParcRemotePlaybackBackForwardCacheTest,
       ConnectionCastsBeforeFrozenPageResumes) {
  V8TestingScope scope;
  ScriptPromiseTester prompt(scope.GetScriptState(), Prompt(scope));

  FreezePage(true);
  EXPECT_CALL(*player_, RequestMediaRemoting());
  Connect();
  testing::Mock::VerifyAndClearExpectations(player_);
  scope.PerformMicrotaskCheckpoint();
  EXPECT_FALSE(prompt.IsFulfilled());
  EXPECT_EQ(V8RemotePlaybackState::Enum::kDisconnected, State());

  EXPECT_CALL(*player_, RequestMediaRemoting()).Times(0);
  EXPECT_CALL(*connecting_, Invoke);
  FreezePage(false);
  EXPECT_EQ(V8RemotePlaybackState::Enum::kConnecting, State());
  scope.PerformMicrotaskCheckpoint();
  EXPECT_TRUE(prompt.IsFulfilled());
}

// A frozen page that isn't casting stays frozen.
TEST_F(ParcRemotePlaybackBackForwardCacheTest,
       FailedConnectionWaitsForFrozenPage) {
  V8TestingScope scope;
  ScriptPromiseTester prompt(scope.GetScriptState(), Prompt(scope));

  FreezePage(true);
  EXPECT_CALL(*player_, RequestMediaRemoting()).Times(0);
  std::move(start_callback_)
      .Run(nullptr,
           mojom::blink::PresentationError::New(
               mojom::blink::PresentationErrorType::UNKNOWN, "failed"));
  base::RunLoop().RunUntilIdle();
  scope.PerformMicrotaskCheckpoint();
  EXPECT_FALSE(prompt.IsRejected());

  FreezePage(false);
  scope.PerformMicrotaskCheckpoint();
  EXPECT_TRUE(prompt.IsRejected());
}

// The player's loads feed a prompted cast until its request takes over.
TEST_F(ParcRemotePlaybackBackForwardCacheTest, PromptedCastHandsOverToRequest) {
  V8TestingScope scope;
  EXPECT_CALL(*player_, ParcSetCastPrompted(true));
  ScriptPromiseTester prompt(scope.GetScriptState(), Prompt(scope));
  testing::Mock::VerifyAndClearExpectations(player_);

  EnterBackForwardCache();
  {
    testing::InSequence sequence;
    EXPECT_CALL(*player_, RequestMediaRemoting());
    EXPECT_CALL(*player_, ParcSetCastPrompted(false));
  }
  Connect();
  testing::Mock::VerifyAndClearExpectations(player_);
}

// A failed prompt stops them at once, without waiting for the page.
TEST_F(ParcRemotePlaybackBackForwardCacheTest, FailedPromptEndsWhileCached) {
  V8TestingScope scope;
  EXPECT_CALL(*player_, ParcSetCastPrompted(true));
  ScriptPromiseTester prompt(scope.GetScriptState(), Prompt(scope));
  testing::Mock::VerifyAndClearExpectations(player_);

  EnterBackForwardCache();
  EXPECT_CALL(*player_, RequestMediaRemoting()).Times(0);
  EXPECT_CALL(*player_, ParcSetCastPrompted(false));
  std::move(start_callback_)
      .Run(nullptr,
           mojom::blink::PresentationError::New(
               mojom::blink::PresentationErrorType::UNKNOWN, "failed"));
  base::RunLoop().RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(player_);
  scope.PerformMicrotaskCheckpoint();
  EXPECT_FALSE(prompt.IsRejected());
}

// A shown page's prompt hands over to the request, or ends with its failure.
TEST_F(ParcRemotePlaybackBackForwardCacheTest,
       ShownPagePromptEndsWithResponse) {
  V8TestingScope scope;
  {
    testing::InSequence sequence;
    EXPECT_CALL(*player_, ParcSetCastPrompted(true));
    EXPECT_CALL(*player_, RequestMediaRemoting());
    EXPECT_CALL(*player_, ParcSetCastPrompted(false));
  }
  EXPECT_CALL(*connecting_, Invoke);
  ScriptPromiseTester prompt(scope.GetScriptState(), Prompt(scope));
  Connect();
  testing::Mock::VerifyAndClearExpectations(player_);
}

TEST_F(ParcRemotePlaybackBackForwardCacheTest, ShownPagePromptEndsWithFailure) {
  V8TestingScope scope;
  {
    testing::InSequence sequence;
    EXPECT_CALL(*player_, ParcSetCastPrompted(true));
    EXPECT_CALL(*player_, ParcSetCastPrompted(false));
  }
  EXPECT_CALL(*player_, RequestMediaRemoting()).Times(0);
  ScriptPromiseTester prompt(scope.GetScriptState(), Prompt(scope));
  std::move(start_callback_)
      .Run(nullptr, mojom::blink::PresentationError::New(
                        mojom::blink::PresentationErrorType::
                            PRESENTATION_REQUEST_CANCELLED,
                        "cancelled"));
  base::RunLoop().RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(player_);
}

TEST_F(ParcRemotePlaybackBackForwardCacheTest, ShownPageConnectsAtOnce) {
  V8TestingScope scope;
  ScriptPromiseTester prompt(scope.GetScriptState(), Prompt(scope));

  EXPECT_CALL(*player_, RequestMediaRemoting());
  EXPECT_CALL(*connecting_, Invoke);
  Connect();
  EXPECT_EQ(V8RemotePlaybackState::Enum::kConnecting, State());
  scope.PerformMicrotaskCheckpoint();
  EXPECT_TRUE(prompt.IsFulfilled());
}

// A cached page that isn't casting stays frozen.
TEST_F(ParcRemotePlaybackBackForwardCacheTest, FailedConnectionWaitsForPage) {
  V8TestingScope scope;
  ScriptPromiseTester prompt(scope.GetScriptState(), Prompt(scope));

  EnterBackForwardCache();
  EXPECT_CALL(*player_, RequestMediaRemoting()).Times(0);
  std::move(start_callback_)
      .Run(nullptr,
           mojom::blink::PresentationError::New(
               mojom::blink::PresentationErrorType::UNKNOWN, "failed"));
  base::RunLoop().RunUntilIdle();
  scope.PerformMicrotaskCheckpoint();
  EXPECT_FALSE(prompt.IsRejected());

  RestoreFromBackForwardCache();
  scope.PerformMicrotaskCheckpoint();
  EXPECT_TRUE(prompt.IsRejected());
}

}  // namespace blink
