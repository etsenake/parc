#import <AppKit/AppKit.h>
#import "browser_window.h"

#include <functional>
#include <memory>

#include "testing/gtest/include/gtest/gtest.h"

namespace parc {
namespace {

class Delegate final : public NativeModalDialogHostDelegate {
 public:
  gfx::NativeView GetActivePageHostView() const override {
    ++view_queries;
    return gfx::NativeView(active_host);
  }
  gfx::Size GetBrowserWindowSize() const override {
    ++window_queries;
    return window_size;
  }
  gfx::Size GetContentsSize() const override {
    ++contents_queries;
    return contents_size;
  }

  NSView* __strong active_host = nil;
  gfx::Size window_size{800, 600};
  gfx::Size contents_size{720, 510};
  mutable int view_queries = 0;
  mutable int window_queries = 0;
  mutable int contents_queries = 0;
};

class Observer final : public web_modal::ModalDialogHostObserver {
 public:
  void OnPositionRequiresUpdate() override {
    ++positions;
    if (on_position) on_position();
  }
  void OnHostDestroying() override {
    ++destructions;
    auto callback = on_destroying;
    if (callback) callback();
  }
  int positions = 0;
  int destructions = 0;
  std::function<void()> on_position;
  std::function<void()> on_destroying;
};

TEST(NativeModalDialogHostTest, ResolvesActualActiveWrapperOnEveryQuery) {
  @autoreleasepool {
    Delegate delegate;
    NativeModalDialogHost host(delegate);
    EXPECT_EQ(nil, host.GetHostView().GetNativeNSView());
    NSView* first = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 510)];
    NSView* second = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 510)];
    delegate.active_host = first;
    EXPECT_EQ(first, host.GetHostView().GetNativeNSView());
    delegate.active_host = second;
    EXPECT_EQ(second, host.GetHostView().GetNativeNSView());
    EXPECT_EQ(3, delegate.view_queries);
    EXPECT_TRUE(host.ShouldActivateDialog());
    EXPECT_TRUE(host.ShouldConstrainDialogBoundsByHost());
    EXPECT_EQ(gfx::kNullAcceleratedWidget, host.GetAcceleratedWidget());
  }
}

TEST(NativeModalDialogHostTest, PreservesRecoveredCenterArithmeticAndMaximum) {
  Delegate delegate;
  NativeModalDialogHost host(delegate);
  EXPECT_EQ(gfx::Point(250, 200), host.GetDialogPosition(gfx::Size(301, 201)));
  EXPECT_EQ(gfx::Point(400, 300), host.GetDialogPosition(gfx::Size()));
  // The recovered primary method does not clamp oversized dialogs.
  EXPECT_EQ(gfx::Point(-100, -100), host.GetDialogPosition(gfx::Size(1001, 801)));
  delegate.window_size = gfx::Size(801, 601);
  EXPECT_EQ(gfx::Point(250, 200), host.GetDialogPosition(gfx::Size(301, 201)));
  EXPECT_EQ(delegate.contents_size, host.GetMaximumDialogSize());
  delegate.contents_size = gfx::Size(359, 507);
  EXPECT_EQ(gfx::Size(359, 507), host.GetMaximumDialogSize());
  EXPECT_EQ(4, delegate.window_queries);
  EXPECT_EQ(2, delegate.contents_queries);
}

TEST(NativeModalDialogHostTest, RemovedAndNewObserversRespectDeliveryBoundary) {
  Delegate delegate;
  Observer first, removed, added;
  NativeModalDialogHost host(delegate);
  host.AddObserver(&first);
  host.AddObserver(&removed);
  bool did_mutate = false;
  first.on_position = [&] {
    if (did_mutate) return;
    did_mutate = true;
    host.RemoveObserver(&removed);
    host.AddObserver(&added);
    host.NotifyPositionRequiresUpdate();  // Nested update is coalesced.
  };
  host.NotifyPositionRequiresUpdate();
  EXPECT_EQ(1, first.positions);
  EXPECT_EQ(0, removed.positions);
  EXPECT_EQ(0, added.positions);
  host.NotifyPositionRequiresUpdate();
  EXPECT_EQ(2, first.positions);
  EXPECT_EQ(1, added.positions);
  host.Invalidate();
  EXPECT_EQ(1, first.destructions);
  EXPECT_EQ(0, removed.destructions);
  EXPECT_EQ(1, added.destructions);
}

TEST(NativeModalDialogHostTest, InvalidationDuringPositionIsSafeAndTerminal) {
  Delegate delegate;
  Observer first, second;
  NativeModalDialogHost host(delegate);
  host.AddObserver(&first);
  host.AddObserver(&second);
  first.on_position = [&] { host.Invalidate(); };
  first.on_destroying = [&] {
    // Delegate is severed before observers are called; they may reenter,
    // remove themselves and invalidate again, without querying dead owners.
    EXPECT_EQ(nil, host.GetHostView().GetNativeNSView());
    EXPECT_EQ(gfx::Point(), host.GetDialogPosition(gfx::Size(10, 10)));
    EXPECT_EQ(gfx::Size(), host.GetMaximumDialogSize());
    host.Invalidate();
    host.RemoveObserver(&first);
  };
  host.NotifyPositionRequiresUpdate();
  EXPECT_EQ(1, first.positions);
  EXPECT_EQ(0, second.positions);
  EXPECT_EQ(1, first.destructions);
  EXPECT_EQ(1, second.destructions);
  host.NotifyPositionRequiresUpdate();
  host.Invalidate();
  EXPECT_EQ(1, first.positions);
  EXPECT_EQ(1, first.destructions);
  EXPECT_EQ(1, second.destructions);
  EXPECT_EQ(0, delegate.view_queries);
  EXPECT_EQ(0, delegate.window_queries);
  EXPECT_EQ(0, delegate.contents_queries);
}

TEST(NativeModalDialogHostTest, DestructionCallbackCanReleaseItsObserver) {
  Delegate delegate;
  NativeModalDialogHost host(delegate);
  auto observer = std::make_unique<Observer>();
  Observer remaining;
  int delivered = 0;
  observer->on_destroying = [&] {
    EXPECT_FALSE(observer->IsInObserverList());
    ++delivered;
    observer.reset();
  };
  host.AddObserver(observer.get());
  host.AddObserver(&remaining);
  host.Invalidate();
  EXPECT_EQ(1, delivered);
  EXPECT_EQ(nullptr, observer);
  EXPECT_EQ(1, remaining.destructions);
  EXPECT_FALSE(remaining.IsInObserverList());
  host.Invalidate();
  EXPECT_EQ(1, remaining.destructions);
}

TEST(NativeModalDialogHostTest, DestructionNotifiesRemainingObserversExactlyOnce) {
  Delegate delegate;
  Observer observer;
  {
    NativeModalDialogHost host(delegate);
    host.AddObserver(&observer);
  }
  EXPECT_EQ(1, observer.destructions);
  {
    NativeModalDialogHost host(delegate);
    host.AddObserver(&observer);
    host.Invalidate();
  }
  EXPECT_EQ(2, observer.destructions);
}

TEST(NativeModalDialogHostTest, InvalidateBeforeDelegateDestructionSeversAccess) {
  auto delegate = std::make_unique<Delegate>();
  NativeModalDialogHost host(*delegate);
  host.Invalidate();
  delegate.reset();
  EXPECT_EQ(nil, host.GetHostView().GetNativeNSView());
  EXPECT_EQ(gfx::Point(), host.GetDialogPosition(gfx::Size(100, 200)));
  EXPECT_EQ(gfx::Size(), host.GetMaximumDialogSize());
}

}  // namespace
}  // namespace parc
