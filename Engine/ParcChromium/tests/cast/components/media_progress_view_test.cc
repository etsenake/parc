// Copyright 2026 Parc contributors.
// Fixture support is derived from Chromium tests (Chromium Authors; BSD-style
// license in Chromium's LICENSE); this file contains only Parc regressions.

#include "components/global_media_controls/public/views/media_progress_view.h"

#include <memory>

#include "base/functional/callback_helpers.h"
#include "base/timer/mock_timer.h"
#include "services/media_session/public/mojom/media_session.mojom.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "ui/events/base_event_utils.h"
#include "ui/views/test/views_test_base.h"

namespace global_media_controls {

class ParcMediaProgressViewTest : public views::ViewsTestBase {
 public:
  ParcMediaProgressViewTest() = default;
  ParcMediaProgressViewTest(const ParcMediaProgressViewTest&) = delete;
  ParcMediaProgressViewTest& operator=(const ParcMediaProgressViewTest&) = delete;
  ~ParcMediaProgressViewTest() override = default;

  void SetUp() override {
    ViewsTestBase::SetUp();
    widget_ = CreateTestWidget(views::Widget::InitParams::CLIENT_OWNS_WIDGET);
    // This test just needs to construct a progress view, without caring about
    // what specific color IDs are used, so just use an arbitrary value.
    ui::ColorId id = ui::kUiColorsStart;
    view_ = widget_->SetContentsView(std::make_unique<MediaProgressView>(
        true, id, id, id, id, id,
        base::BindRepeating(&ParcMediaProgressViewTest::OnProgressDragStateChange,
                            base::Unretained(this)),
        base::BindRepeating(
            &ParcMediaProgressViewTest::OnPlaybackStateChangeForProgressDrag,
            base::Unretained(this)),
        base::BindRepeating(&ParcMediaProgressViewTest::SeekTo,
                            base::Unretained(this)),
        base::BindRepeating(&ParcMediaProgressViewTest::OnProgressUpdated,
                            base::Unretained(this))));

    widget_->SetBounds(gfx::Rect(500, 500));
    widget_->Show();

    view_->set_update_progress_timer_for_testing(
        std::make_unique<base::MockOneShotTimer>());
    view_->set_switch_progress_colors_delay_timer_for_testing(
        std::make_unique<base::MockOneShotTimer>());

    auto mock_timer = std::make_unique<base::MockOneShotTimer>();
    progress_drag_started_delay_timer_ = mock_timer.get();
    view_->set_progress_drag_started_delay_timer_for_testing(
        std::move(mock_timer));
  }

  void TearDown() override {
    progress_drag_started_delay_timer_ = nullptr;
    view_ = nullptr;
    widget_->Close();
    ViewsTestBase::TearDown();
  }

  MediaProgressView* view() const { return view_; }
  base::MockOneShotTimer* progress_drag_started_delay_timer() const {
    return progress_drag_started_delay_timer_;
  }

  MOCK_METHOD1(OnProgressDragStateChange, void(DragState));
  MOCK_METHOD1(OnPlaybackStateChangeForProgressDrag,
               void(PlaybackStateChangeForDragging));
  MOCK_METHOD1(SeekTo, void(double));
  MOCK_METHOD1(OnProgressUpdated, void(base::TimeDelta));

 private:
  std::unique_ptr<views::Widget> widget_;
  raw_ptr<MediaProgressView> view_ = nullptr;
  raw_ptr<base::MockOneShotTimer> progress_drag_started_delay_timer_ = nullptr;
};

TEST_F(ParcMediaProgressViewTest, CaptureLossEndsScrubbingWithoutSeekingOrPlaying) {
  view()->SetParcSafariPlaybackControls(true);
  media_session::MediaPosition position(1, base::Seconds(600), base::Seconds(100), false);
  EXPECT_CALL(*this, OnProgressUpdated(testing::_));
  view()->UpdateProgress(position);
  gfx::Point point(view()->width() / 2, view()->height() / 2);
  ui::MouseEvent press(ui::EventType::kMousePressed, point, point,
                       ui::EventTimeForNow(), ui::EF_LEFT_MOUSE_BUTTON,
                       ui::EF_LEFT_MOUSE_BUTTON);
  EXPECT_CALL(*this, OnProgressDragStateChange(DragState::kDragStarted));
  EXPECT_CALL(*this, OnPlaybackStateChangeForProgressDrag(
                        PlaybackStateChangeForDragging::kPauseForDraggingStarted));
  EXPECT_CALL(*this, SeekTo(0.5));
  view()->OnMousePressed(press);
  progress_drag_started_delay_timer()->Fire();
  testing::Mock::VerifyAndClearExpectations(this);
  EXPECT_CALL(*this, OnProgressDragStateChange(DragState::kDragEnded));
  EXPECT_CALL(*this, SeekTo(testing::_)).Times(0);
  EXPECT_CALL(*this, OnPlaybackStateChangeForProgressDrag(testing::_)).Times(0);
  view()->OnMouseCaptureLost();
  testing::Mock::VerifyAndClearExpectations(this);
  media_session::MediaPosition paused(0, base::Seconds(600), base::Seconds(100), false);
  EXPECT_CALL(*this, OnProgressUpdated(testing::_));
  view()->UpdateProgress(paused);
  EXPECT_CALL(*this, OnProgressDragStateChange(DragState::kDragStarted));
  EXPECT_CALL(*this, OnProgressDragStateChange(DragState::kDragEnded));
  EXPECT_CALL(*this, OnPlaybackStateChangeForProgressDrag(testing::_)).Times(0);
  EXPECT_CALL(*this, SeekTo(0.5)).Times(2);
  view()->OnMousePressed(press);
  progress_drag_started_delay_timer()->Fire();
  ui::MouseEvent release(ui::EventType::kMouseReleased, point, point,
                         ui::EventTimeForNow(), ui::EF_LEFT_MOUSE_BUTTON,
                         ui::EF_LEFT_MOUSE_BUTTON);
  view()->OnMouseReleased(release);
}

TEST_F(ParcMediaProgressViewTest, ChromeCaptureLossKeepsPendingDrag) {
  media_session::MediaPosition position(1, base::Seconds(600), base::Seconds(100), false);
  EXPECT_CALL(*this, OnProgressUpdated(testing::_));
  view()->UpdateProgress(position);
  gfx::Point point(view()->width() / 2, view()->height() / 2);
  ui::MouseEvent press(ui::EventType::kMousePressed, point, point,
                       ui::EventTimeForNow(), ui::EF_LEFT_MOUSE_BUTTON,
                       ui::EF_LEFT_MOUSE_BUTTON);
  view()->OnMousePressed(press);
  EXPECT_TRUE(progress_drag_started_delay_timer()->IsRunning());
  EXPECT_CALL(*this, OnProgressDragStateChange(testing::_)).Times(0);
  view()->OnMouseCaptureLost();
  EXPECT_TRUE(progress_drag_started_delay_timer()->IsRunning());
}

}  // namespace global_media_controls
