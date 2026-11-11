// Copyright 2026 Parc contributors.
// Installed at //content/renderer/media/parc_tests. The fixture is derived
// from Chromium's inspector_media_event_handler_unittest.cc (Chromium Authors;
// BSD-style license in Chromium's LICENSE) and contains only Parc regressions.

#include <memory>
#include <vector>

#include "content/renderer/media/inspector_media_event_handler.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/web/web_media_inspector.h"

using ::testing::_;

namespace content {

class ParcMockMediaInspectorContext : public blink::MediaInspectorContext {
 public:
  virtual ~ParcMockMediaInspectorContext() = default;

  void SetDomNodeIdForPlayer(const blink::WebString& player_id,
                             int dom_node_id) override {
    MockSetDomNodeIdForPlayer(dom_node_id);
  }

  blink::WebString CreatePlayer() override { return "TestPlayer"; }

  void DestroyPlayer(const blink::WebString& player_id) override {
    MockDestroyPlayer();
  }

  void NotifyPlayerEvents(blink::WebString id,
                          const blink::InspectorPlayerEvents& events) override {
    MockNotifyPlayerEvents(events);
  }

  void SetPlayerProperties(
      blink::WebString id,
      const blink::InspectorPlayerProperties& props) override {}

  void NotifyPlayerErrors(blink::WebString id,
                          const blink::InspectorPlayerErrors& errors) override {
  }

  void NotifyPlayerMessages(
      blink::WebString id,
      const blink::InspectorPlayerMessages& messages) override {}

  MOCK_METHOD(void, MockNotifyPlayerEvents, (blink::InspectorPlayerEvents));
  MOCK_METHOD(void, MockDestroyPlayer, ());
  MOCK_METHOD(void, MockSetDomNodeIdForPlayer, (int));
};

class ParcInspectorMediaEventHandlerTest : public testing::Test {
 public:
  ParcInspectorMediaEventHandlerTest()
      : mock_context_(std::make_unique<ParcMockMediaInspectorContext>()),
        handler_(
            std::make_unique<InspectorMediaEventHandler>(mock_context_.get(),
                                                         123)) {}

 protected:
  template <media::MediaLogEvent T>
  media::MediaLogRecord CreateEvent() {
    media::MediaLogRecord event;
    event.id = media::MediaPlayerLoggingID(0);
    event.type = media::MediaLogRecord::Type::kMediaEventTriggered;
    event.time = base::TimeTicks();
    event.params.Set("event", media::MediaLogEventTypeSupport<T>::TypeName());
    return event;
  }

  std::unique_ptr<ParcMockMediaInspectorContext> mock_context_;
  std::unique_ptr<InspectorMediaEventHandler> handler_;
};

// Parc: a player a Safari-identity element moved to another frame leaves the
// old frame's inspector and appears in the new one's, with its element.
TEST_F(ParcInspectorMediaEventHandlerTest, ParcMovesToInspectorContext) {
  ParcMockMediaInspectorContext new_context;
  EXPECT_CALL(*mock_context_, MockDestroyPlayer());
  EXPECT_CALL(new_context, MockSetDomNodeIdForPlayer(123));
  handler_->ParcMoveToInspectorContext(&new_context);

  std::vector<media::MediaLogRecord> events = {
      CreateEvent<media::MediaLogEvent::kPlay>()};
  EXPECT_CALL(*mock_context_, MockNotifyPlayerEvents(_)).Times(0);
  EXPECT_CALL(new_context, MockNotifyPlayerEvents(_));
  handler_->SendQueuedMediaEvents(events);

  EXPECT_CALL(new_context, MockDestroyPlayer());
  handler_->OnWebMediaPlayerDestroyed();
}

}  // namespace content
