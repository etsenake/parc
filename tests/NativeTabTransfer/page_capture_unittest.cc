// Copyright 2026 Parc contributors.
#include "native_page_capture.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

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

std::vector<int> RowsCovered(const PageCapturePlan& plan, int x) {
  std::vector<int> rows(plan.height, 0);
  auto add = [&](const PageCaptureSlice& slice) {
    if (x < slice.left || x >= slice.left + slice.width) {
      return;
    }
    for (int y = slice.dest_y; y < slice.dest_y + slice.height; ++y) {
      EXPECT_GE(y, 0);
      EXPECT_LT(y, plan.height);
      if (y >= 0 && y < plan.height) {
        ++rows[y];
      }
    }
  };
  for (const PageCaptureFrame& frame : plan.frames) {
    for (const PageCaptureSlice& slice : frame.slices) {
      add(slice);
    }
  }
  for (const PageCaptureSlice& fill : plan.fills) {
    add(fill);
  }
  return rows;
}

void ExpectEveryRowOnce(const PageCapturePlan& plan) {
  for (int x : {0, plan.width / 3, plan.width / 2, plan.width - 1}) {
    const std::vector<int> rows = RowsCovered(plan, x);
    for (int y = 0; y < plan.height; ++y) {
      ASSERT_EQ(rows[y], 1) << "column " << x << " row " << y;
    }
  }
}

std::vector<double> Offsets(const PageCapturePlan& plan) {
  std::vector<double> offsets;
  for (const PageCaptureFrame& frame : plan.frames) {
    offsets.push_back(frame.offset);
  }
  return offsets;
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

TEST(NativePageCaptureTest, ALongDocumentWithoutBarsTilesWholeViewports) {
  const PageCapturePlan plan = PlanPageCapture(
      {.frame_width = 1600, .frame_height = 1000, .scale = 2, .area_right = 800,
       .area_bottom = 500, .content_height = 2000, .client_height = 500});
  EXPECT_EQ(plan.width, 1600);
  EXPECT_EQ(plan.height, 4000);
  EXPECT_EQ(Offsets(plan), (std::vector<double>{0, 500, 1000, 1500}));
  for (size_t i = 0; i < plan.frames.size(); ++i) {
    EXPECT_EQ(plan.frames[i].slices,
              (std::vector<PageCaptureSlice>{
                  {0, 1600, 0, static_cast<int>(i) * 1000, 1000}}));
  }
  EXPECT_TRUE(plan.fills.empty());
  ExpectEveryRowOnce(plan);
}

TEST(NativePageCaptureTest, TopAndBottomBarsAppearOnceAtTheirEnds) {
  const PageCapturePlan plan = PlanPageCapture(
      {.frame_width = 1600, .frame_height = 900, .scale = 2, .area_right = 800,
       .area_bottom = 450, .top_bar = 64, .bottom_bar = 80,
       .content_height = 3000, .client_height = 450});
  EXPECT_EQ(plan.height, 6000);
  ASSERT_GE(plan.frames.size(), 3u);
  EXPECT_EQ(plan.frames.front().slices,
            (std::vector<PageCaptureSlice>{{0, 1600, 0, 0, 740}}));
  for (size_t i = 1; i + 1 < plan.frames.size(); ++i) {
    ASSERT_EQ(plan.frames[i].slices.size(), 1u);
    EXPECT_EQ(plan.frames[i].slices[0].source_y, 128);
    EXPECT_EQ(plan.frames[i].slices[0].height, 612);
  }
  const PageCaptureFrame& last = plan.frames.back();
  EXPECT_EQ(last.offset, 2550);
  ASSERT_EQ(last.slices.size(), 2u);
  EXPECT_EQ(last.slices[1], (PageCaptureSlice{0, 1600, 740, 5840, 160}));
  int bar_rows = 0;
  for (const PageCaptureFrame& frame : plan.frames) {
    for (const PageCaptureSlice& slice : frame.slices) {
      bar_rows += std::max(0, std::min(slice.source_y + slice.height, 900) -
                                  std::max(slice.source_y, 740));
    }
  }
  EXPECT_EQ(bar_rows, 160);
  ExpectEveryRowOnce(plan);
}

TEST(NativePageCaptureTest, AnInnerPanelKeepsItsHeaderOnTopAndFooterAtTheEnd) {
  const PageCapturePlan plan = PlanPageCapture(
      {.frame_width = 800, .frame_height = 600, .scale = 1, .area_top = 60,
       .area_right = 800, .area_bottom = 540, .content_height = 2400,
       .client_height = 480});
  EXPECT_EQ(plan.height, 2520);
  EXPECT_EQ(Offsets(plan), (std::vector<double>{0, 480, 960, 1440, 1920}));
  EXPECT_EQ(plan.frames.front().slices,
            (std::vector<PageCaptureSlice>{{0, 800, 0, 0, 540}}));
  EXPECT_EQ(plan.frames[1].slices,
            (std::vector<PageCaptureSlice>{{0, 800, 60, 540, 480}}));
  EXPECT_EQ(plan.frames.back().slices,
            (std::vector<PageCaptureSlice>{{0, 800, 60, 1980, 480},
                                           {0, 800, 540, 2460, 60}}));
  ExpectEveryRowOnce(plan);
}

TEST(NativePageCaptureTest, ASidebarBesideANarrowerPanelComesFromTheFirstFrame) {
  const PageCapturePlan plan = PlanPageCapture(
      {.frame_width = 1000, .frame_height = 600, .scale = 1, .area_left = 240,
       .area_right = 1000, .area_bottom = 600, .content_height = 1800,
       .client_height = 600});
  EXPECT_EQ(plan.height, 1800);
  EXPECT_EQ(plan.frames.front().slices,
            (std::vector<PageCaptureSlice>{{0, 1000, 0, 0, 600}}));
  for (size_t i = 1; i < plan.frames.size(); ++i) {
    for (const PageCaptureSlice& slice : plan.frames[i].slices) {
      EXPECT_GE(slice.left, 240);
    }
  }
  EXPECT_EQ(plan.fills,
            (std::vector<PageCaptureSlice>{{0, 240, 599, 600, 1200}}));
  ExpectEveryRowOnce(plan);
}

TEST(NativePageCaptureTest, TheLastFrameTakesOnlyItsNewRows) {
  const PageCapturePlan plan = PlanPageCapture(
      {.frame_width = 800, .frame_height = 600, .scale = 1, .area_right = 800,
       .area_bottom = 600, .content_height = 1500, .client_height = 600});
  EXPECT_EQ(Offsets(plan), (std::vector<double>{0, 600, 900}));
  EXPECT_EQ(plan.frames.back().slices,
            (std::vector<PageCaptureSlice>{{0, 800, 300, 1200, 300}}));
  EXPECT_EQ(plan.height, 1500);
  ExpectEveryRowOnce(plan);
}

TEST(NativePageCaptureTest, ASnappedOffsetIsReplannedFromWhereThePageLanded) {
  const PageCaptureGeometry geometry = {
      .frame_width = 800, .frame_height = 600, .scale = 1, .area_right = 800,
      .area_bottom = 600, .top_bar = 50, .content_height = 3000,
      .client_height = 600};
  const PageCaptureStep first = PageCaptureTakeFrame(geometry, 0, 0, true, true);
  EXPECT_EQ(first.covered, 600);
  ASSERT_TRUE(first.next_offset);
  EXPECT_EQ(*first.next_offset, 550);

  const PageCaptureStep past = PageCaptureTakeFrame(geometry, 600, 580, false, true);
  EXPECT_TRUE(past.slices.empty());
  ASSERT_TRUE(past.retry_offset);
  EXPECT_EQ(*past.retry_offset, 550);

  const PageCaptureStep stuck = PageCaptureTakeFrame(geometry, 600, 580, false, false);
  EXPECT_EQ(stuck.slices,
            (std::vector<PageCaptureSlice>{{0, 800, 20, 600, 580}}));
  EXPECT_EQ(stuck.covered, 1180);
  ASSERT_TRUE(stuck.next_offset);
  EXPECT_EQ(*stuck.next_offset, 1130);

  const PageCaptureStep short_of = PageCaptureTakeFrame(geometry, 600, 520, false, true);
  EXPECT_FALSE(short_of.retry_offset);
  EXPECT_EQ(short_of.slices,
            (std::vector<PageCaptureSlice>{{0, 800, 80, 600, 520}}));
  EXPECT_EQ(short_of.covered, 1120);
  ASSERT_TRUE(short_of.next_offset);
  EXPECT_EQ(*short_of.next_offset, 1070);

  const PageCaptureStep refused = PageCaptureTakeFrame(geometry, 0, 30, true, true);
  ASSERT_TRUE(refused.retry_offset);
  EXPECT_EQ(*refused.retry_offset, 0);
}

TEST(NativePageCaptureTest, RetinaRoundingNeverLeavesASeam) {
  const PageCapturePlan plan = PlanPageCapture(
      {.frame_width = 1600, .frame_height = 1001, .scale = 2, .area_right = 800,
       .area_bottom = 500.5, .top_bar = 56.25, .content_height = 2345.7,
       .client_height = 500.5});
  EXPECT_EQ(plan.height, 1001 + 3690);
  ASSERT_GE(plan.frames.size(), 2u);
  for (size_t i = 1; i + 1 < plan.frames.size(); ++i) {
    EXPECT_EQ(plan.frames[i].offset, std::floor(plan.frames[i].offset));
    EXPECT_EQ(plan.frames[i].slices[0].source_y, 113);
  }
  EXPECT_DOUBLE_EQ(plan.frames.back().offset, 2345.7 - 500.5);
  ExpectEveryRowOnce(plan);

  const PageCapturePlan zoomed = PlanPageCapture(
      {.frame_width = 1760, .frame_height = 1100, .scale = 2.2,
       .area_right = 800, .area_bottom = 500, .top_bar = 30, .bottom_bar = 20,
       .content_height = 2345.7, .client_height = 500});
  EXPECT_EQ(zoomed.height, 1100 + PageCapturePixels(2345.7 - 500, 2.2));
  ExpectEveryRowOnce(zoomed);
}

TEST(NativePageCaptureTest, APageTallerThanTheCapStopsAtTheCap) {
  const PageCapturePlan plan = PlanPageCapture(
      {.frame_width = 1600, .frame_height = 1000, .scale = 2, .area_right = 800,
       .area_bottom = 500, .bottom_bar = 40, .content_height = 20000,
       .client_height = 500});
  EXPECT_EQ(plan.height, kPageCaptureMaxSide);
  const PageCaptureSlice& end = plan.frames.back().slices.back();
  EXPECT_EQ(end.dest_y + end.height, kPageCaptureMaxSide);
  for (const PageCaptureFrame& frame : plan.frames) {
    for (const PageCaptureSlice& slice : frame.slices) {
      EXPECT_LE(slice.source_y + slice.height, 920);
    }
  }
  ExpectEveryRowOnce(plan);

  const PageCapturePlan wide = PlanPageCapture(
      {.frame_width = 6000, .frame_height = 1000, .scale = 2,
       .area_right = 3000, .area_bottom = 500, .content_height = 20000,
       .client_height = 500});
  EXPECT_EQ(wide.height, kPageCaptureMaxPixels / 6000);
  EXPECT_LE(static_cast<int64_t>(wide.width) * wide.height, kPageCaptureMaxPixels);
  ExpectEveryRowOnce(wide);
}

TEST(NativePageCaptureTest, APageThatDoesNotScrollPlansExactlyOneFrame) {
  const PageCapturePlan plan = PlanPageCapture(
      {.frame_width = 1600, .frame_height = 1000, .scale = 2, .area_right = 800,
       .area_bottom = 500, .top_bar = 40, .content_height = 500,
       .client_height = 500});
  ASSERT_EQ(plan.frames.size(), 1u);
  EXPECT_EQ(plan.frames[0].offset, 0);
  EXPECT_EQ(plan.frames[0].slices,
            (std::vector<PageCaptureSlice>{{0, 1600, 0, 0, 1000}}));
  EXPECT_EQ(plan.height, 1000);
  EXPECT_TRUE(plan.fills.empty());
}
}
}
