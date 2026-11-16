// Copyright 2026 Parc contributors.
#include "native_page_capture.h"

#include "testing/gtest/include/gtest/gtest.h"

namespace parc {
namespace {

constexpr PageCapturePurpose kPurposes[] = {PageCapturePurpose::kPerson,
                                            PageCapturePurpose::kPlaceholder};

PageCaptureWindow WindowFromBits(int bits) {
  return {.app_active = (bits & 1) != 0,
          .visible = (bits & 2) != 0,
          .miniaturized = (bits & 4) != 0,
          .key = (bits & 8) != 0,
          .attached_sheet = (bits & 16) != 0,
          .security_reservation = (bits & 32) != 0};
}

bool Admits(PageCapturePurpose purpose, const PageCaptureWindow& window) {
  return PageCaptureWindowAdmits(window, PageCaptureNeedsKeyWindow(purpose));
}

TEST(NativePageCaptureTest, PersonCaptureStillNeedsTheKeyWindow) {
  PageCaptureWindow front = {.app_active = true, .visible = true, .key = true};
  EXPECT_TRUE(Admits(PageCapturePurpose::kPerson, front));
  PageCaptureWindow background = front;
  background.key = false;
  EXPECT_FALSE(Admits(PageCapturePurpose::kPerson, background));
}

TEST(NativePageCaptureTest, PlaceholderCopyTakesABackgroundWindow) {
  PageCaptureWindow background = {.app_active = true, .visible = true};
  EXPECT_TRUE(Admits(PageCapturePurpose::kPlaceholder, background));
}

TEST(NativePageCaptureTest, PlaceholderRelaxesOnlyTheKeyWindow) {
  for (int bits = 0; bits < 64; ++bits) {
    const PageCaptureWindow window = WindowFromBits(bits);
    PageCaptureWindow as_key = window;
    as_key.key = true;
    EXPECT_EQ(Admits(PageCapturePurpose::kPlaceholder, window),
              Admits(PageCapturePurpose::kPerson, as_key))
        << bits;
    EXPECT_EQ(Admits(PageCapturePurpose::kPerson, window),
              window.key && Admits(PageCapturePurpose::kPlaceholder, window))
        << bits;
  }
}

TEST(NativePageCaptureTest, EveryOtherWindowRuleStillRefusesBothPurposes) {
  const PageCaptureWindow ready = {.app_active = true, .visible = true, .key = true};
  for (PageCapturePurpose purpose : kPurposes) {
    EXPECT_TRUE(Admits(purpose, ready));
    PageCaptureWindow inactive = ready;
    inactive.app_active = false;
    EXPECT_FALSE(Admits(purpose, inactive));
    PageCaptureWindow hidden = ready;
    hidden.visible = false;
    EXPECT_FALSE(Admits(purpose, hidden));
    PageCaptureWindow minimized = ready;
    minimized.miniaturized = true;
    EXPECT_FALSE(Admits(purpose, minimized));
    PageCaptureWindow sheet = ready;
    sheet.attached_sheet = true;
    EXPECT_FALSE(Admits(purpose, sheet));
    PageCaptureWindow reserved = ready;
    reserved.security_reservation = true;
    EXPECT_FALSE(Admits(purpose, reserved));
  }
}

TEST(NativePageCaptureTest, PlaceholderCopiesOnlyTheVisiblePage) {
  EXPECT_TRUE(PageCaptureViewportOnly(PageCapturePurpose::kPlaceholder));
  EXPECT_FALSE(PageCaptureViewportOnly(PageCapturePurpose::kPerson));
  EXPECT_FALSE(PageCaptureNeedsKeyWindow(PageCapturePurpose::kPlaceholder));
  EXPECT_TRUE(PageCaptureNeedsKeyWindow(PageCapturePurpose::kPerson));
}

}
}
