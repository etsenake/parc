#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "pane_compositor_view.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <functional>
#include <memory>
#include <optional>
#include <tuple>
#include <utility>
#include <vector>

static unsigned checks;
static void Check(bool value, const char* message) {
  ++checks;
  if (!value) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}

namespace viz {
struct FrameTimingDetails {};
}
namespace base {
template <typename T> using WeakPtr = T*;
struct OnceClosure {
  std::function<void()> function;
  void Run() { std::exchange(function, {})(); }
};
template <typename F, typename... Args>
auto BindOnce(F fn, Args&&... args) {
  return [fn, bound = std::make_tuple(std::forward<Args>(args)...)](
             const viz::FrameTimingDetails& details) mutable {
    std::apply([&](auto&... values) { fn(std::move(values)..., details); }, bound);
  };
}
}
namespace gfx {
struct CALayerParams {
  CALayer* __strong picture;
};
}
namespace ui {
class DisplayCALayerTree {
 public:
  explicit DisplayCALayerTree(CALayer* root) : container_([CALayer layer]) {
    container_.frame = root.bounds;
    [root addSublayer:container_];
  }
  ~DisplayCALayerTree() { [container_ removeFromSuperlayer]; }
  void UpdateCALayerTree(gfx::CALayerParams params) {
    container_.sublayers = params.picture ? @[params.picture] : @[];
  }
 private:
  CALayer* __strong container_;
};
}

struct Widget {
  bool suspended = false;
  void SetSuspended(bool value) { suspended = value; }
};
struct Compositor {
  Widget widget_;
  bool suspended = false;
  unsigned redraws = 0;
  std::deque<std::function<void(const viz::FrameTimingDetails&)>> callbacks;
  Widget* widget() { return &widget_; }
  Compositor* compositor() { return this; }
  void Suspend() { suspended = true; }
  void Unsuspend() { suspended = false; }
  void SetProtectedLayersAllowed(bool) {}
  void ScheduleFullRedraw() { ++redraws; }
  void RequestSuccessfulPresentationTimeForNextFrame(
      std::function<void(const viz::FrameTimingDetails&)> callback) {
    callbacks.push_back(std::move(callback));
  }
  void Present() {
    if (!callbacks.empty()) {
      auto callback = std::move(callbacks.front());
      callbacks.pop_front();
      callback({});
    }
  }
};

class NativePaneCompositor {
 public:
  NativePaneCompositor() : hosted_layer_([CALayer layer]),
      tree_(std::make_unique<ui::DisplayCALayerTree>(hosted_layer_)),
      overlay_([[PCNativePaneCompositorView alloc]
          initWithHostedLayer:hosted_layer_]),
      compositor_(std::make_unique<Compositor>()) {
    overlay_.frame = NSMakeRect(0, 0, 640, 480);
  }
  void ClearDisplay();
  void AcceleratedWidgetCALayerParamsUpdated(gfx::CALayerParams);
  void SuspendDrawing();
  void ResumeDrawing();
  void Hide(uint64_t);
  void NotifyPresented(base::OnceClosure);
  void RequestPresentation();
  void DropPresentation();
  void AllowProtectedLayers() { ++protected_layers_generation_; }
  void Receive(gfx::CALayerParams params) {
    if (!compositor_->widget()->suspended)
      AcceleratedWidgetCALayerParamsUpdated(std::move(params));
  }
  bool Shows(NSString* frame) {
    for (CALayer* container in hosted_layer_.sublayers)
      if (!container.hidden)
        for (CALayer* picture in container.sublayers)
          if ([picture.name isEqualToString:frame]) return true;
    return false;
  }

  CALayer* __strong hosted_layer_;
  std::unique_ptr<ui::DisplayCALayerTree> tree_;
  PCNativePaneCompositorView* __strong overlay_;
  std::unique_ptr<Compositor> compositor_;
  std::optional<gfx::CALayerParams> deferred_ca_layer_params_;
  bool drawing_ = true;
  bool page_shown_ = true;
  int capture_locks_ = 0;
  uint64_t last_used_ = 0;
  uint64_t protected_layers_generation_ = 0;
  uint64_t presentation_generation_ = 0;
  std::vector<base::OnceClosure> presented_;
  struct WeakFactory {
    NativePaneCompositor* owner;
    NativePaneCompositor* GetWeakPtr() { return owner; }
  } weak_factory_{this};
};

#include "handoff.inc"

class FrameSource {
 public:
  void NewConnection() { picture_ = [CALayer layer]; }
  void Frame(NativePaneCompositor& pane, double time, NSString* name) {
    picture_.name = name;
    if (last_sent_ != picture_ || time >= next_send_) {
      ++messages;
      last_sent_ = picture_;
      next_send_ = time + 10;
      pane.Receive({picture_});
    }
  }
  unsigned messages = 0;
 private:
  CALayer* __strong picture_ = [CALayer layer];
  CALayer* __strong last_sent_;
  double next_send_ = 0;
};

static void TestFreshPageWithoutAnotherConnectionMessage() {
  NativePaneCompositor pane;
  FrameSource source;
  source.Frame(pane, -5.229, @"previous page");
  Check(pane.Shows(@"previous page"), "the prior page has a connected picture");
  pane.SuspendDrawing();
  pane.ClearDisplay();
  Check(!pane.Shows(@"previous page"), "an incompatible old picture is concealed");
  pane.ResumeDrawing();
  source.Frame(pane, 0.106, @"What's New");
  Check(source.messages == 1, "the first frame needs no repeated connection message");
  pane.compositor_->Present();
  Check(pane.Shows(@"What's New"),
        "the first new frame appears before the ten-second metadata resend");
  source.Frame(pane, 4.068, @"What's New");
  Check(source.messages == 1 && pane.Shows(@"What's New"),
        "a static page stays visible without a focus event or another message");
}

static void TestChangedConnectionWhileSuspended() {
  NativePaneCompositor pane;
  FrameSource source;
  source.Frame(pane, 0, @"held frame");
  pane.SuspendDrawing();
  source.NewConnection();
  source.Frame(pane, 1, @"replacement frame");
  Check(pane.Shows(@"held frame"), "suspended drawing keeps its held picture");
  pane.ResumeDrawing();
  source.Frame(pane, 1.1, @"replacement frame");
  Check(source.messages == 2, "the changed connection is sent only once");
  pane.compositor_->Present();
  Check(pane.Shows(@"replacement frame"), "resuming uses the deferred connection");

  pane.SuspendDrawing();
  source.NewConnection();
  source.Frame(pane, 2, @"superseded connection");
  pane.ResumeDrawing();
  source.NewConnection();
  source.Frame(pane, 3, @"newest connection");
  pane.compositor_->Present();
  Check(pane.Shows(@"newest connection"), "deferred metadata cannot replace a newer connection");
}

static void TestCancelledAndSuspendedPresentation() {
  NativePaneCompositor pane;
  FrameSource source;
  source.Frame(pane, 0, @"old page");
  pane.SuspendDrawing();
  pane.ClearDisplay();
  pane.ResumeDrawing();
  pane.Hide(1);
  source.NewConnection();
  source.Frame(pane, 1, @"next page");
  pane.ResumeDrawing();
  pane.compositor_->Present();
  Check(!pane.Shows(@"next page"), "an old callback cannot reveal a later owner");
  pane.compositor_->Present();
  Check(pane.Shows(@"next page"), "the new owner's callback reveals its frame");

  pane.ClearDisplay();
  pane.ResumeDrawing();
  pane.SuspendDrawing();
  source.NewConnection();
  source.Frame(pane, 2, @"after ancestor hiding");
  pane.compositor_->Present();
  Check(!pane.Shows(@"after ancestor hiding"), "a callback while suspended keeps the picture concealed");
  pane.ResumeDrawing();
  pane.compositor_->Present();
  Check(pane.Shows(@"after ancestor hiding"), "ancestor unhiding renews the reveal request");

  pane.ClearDisplay();
  pane.ResumeDrawing();
  pane.capture_locks_ = 1;
  pane.Hide(2);
  Check(pane.drawing_, "capture keeps drawing while the page is hidden");
  pane.ResumeDrawing();
  pane.compositor_->Present();
  Check(!pane.Shows(@"after ancestor hiding"), "capture does not validate a cancelled reveal");
  pane.compositor_->Present();
  Check(pane.Shows(@"after ancestor hiding"), "showing a captured page renews its reveal request");
}

int main(int argc, char** argv) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    const char* selection = argc > 1 ? argv[1] : "all";
    if (!std::strcmp(selection, "all") || !std::strcmp(selection, "reuse"))
      TestFreshPageWithoutAnotherConnectionMessage();
    if (!std::strcmp(selection, "all") || !std::strcmp(selection, "suspended"))
      TestChangedConnectionWhileSuspended();
    if (!std::strcmp(selection, "all") || !std::strcmp(selection, "callbacks"))
      TestCancelledAndSuspendedPresentation();
    std::printf("PASS: %u display handoff assertions with production methods and real CALayers\n", checks);
  }
}
