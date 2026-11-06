// Copyright 2026 Parc contributors.
#import <Cocoa/Cocoa.h>

#include "base/test/bind.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_occlusion_observer.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_occlusion_tracker.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_occlusion_tracker_observer.h"
#include "chrome/test/views/chrome_views_test_base.h"
#include "ui/gfx/mac/coordinate_conversion.h"

class NativePiPOcclusionTest : public ChromeViewsTestBase {};
namespace {
class Observer : public PictureInPictureOcclusionObserver {
 public:
  void OnOcclusionStateChanged(bool value) override {
    occluded = value;
    ++changes;
  }
  bool occluded = false;
  int changes = 0;
};
}  // namespace
TEST_F(NativePiPOcclusionTest,
       ActualNativeIdentityProtectsNativeAndViewsTargets) {
  PictureInPictureOcclusionTracker tracker;
  auto widget = CreateTestWidget(views::Widget::InitParams::CLIENT_OWNS_WIDGET);
  widget->SetBounds({100, 100, 200, 200});
  widget->Show();
  Observer observer;
  PictureInPictureOcclusionTrackerObserver observation(widget.get(), &observer);
  tracker.AddObserver(&observation);
  NSPanel* panel = [[NSPanel alloc]
      initWithContentRect:gfx::ScreenRectToNSRect({100, 100, 200, 200})
                styleMask:NSWindowStyleMaskNonactivatingPanel
                  backing:NSBackingStoreBuffered
                    defer:NO];
  panel.releasedWhenClosed = NO;
  uint64_t token =
      tracker.RegisterNativePictureInPictureWindow(gfx::NativeWindow(panel));
  EXPECT_FALSE(tracker.IsNativeRectangleOccluded({110, 110, 20, 20}));
  [panel orderFront:nil];
  tracker.UpdateNativePictureInPictureWindow(
      token, gfx::ScreenRectFromNSRect(panel.frame), panel.visible);
  EXPECT_TRUE(tracker.IsNativeRectangleOccluded({110, 110, 20, 20}));
  EXPECT_TRUE(observer.occluded);
  [panel orderOut:nil];
  tracker.UpdateNativePictureInPictureWindow(
      token, gfx::ScreenRectFromNSRect(panel.frame), panel.visible);
  EXPECT_FALSE(tracker.IsNativeRectangleOccluded({110, 110, 20, 20}));
  EXPECT_FALSE(observer.occluded);
  tracker.RemoveNativePictureInPictureWindow(token);
  tracker.UpdateNativePictureInPictureWindow(token, {100, 100, 200, 200}, true);
  EXPECT_FALSE(tracker.IsNativeRectangleOccluded({110, 110, 20, 20}));
  tracker.RemoveObserver(&observation);
  [panel close];
}
TEST_F(NativePiPOcclusionTest, ReentrantRemovalCannotReviveOldToken) {
  PictureInPictureOcclusionTracker tracker;
  NSPanel* panel = [NSPanel new];
  panel.releasedWhenClosed = NO;
  uint64_t token =
      tracker.RegisterNativePictureInPictureWindow(gfx::NativeWindow(panel));
  bool removed = false;
  auto subscription =
      tracker.ObserveNativeOccluderChanges(base::BindLambdaForTesting([&] {
        if (!removed) {
          removed = true;
          tracker.RemoveNativePictureInPictureWindow(token);
        }
      }));
  tracker.UpdateNativePictureInPictureWindow(token, {0, 0, 50, 50}, true);
  EXPECT_TRUE(removed);
  EXPECT_FALSE(tracker.IsNativeRectangleOccluded({0, 0, 5, 5}));
  task_environment()->RunUntilIdle();
  EXPECT_FALSE(tracker.IsNativeRectangleOccluded({0, 0, 5, 5}));
  [panel close];
}
