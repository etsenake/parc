#include "pane_compositor.h"

#import <QuartzCore/QuartzCore.h>

#include <map>
#include <memory>
#include <optional>
#include <tuple>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/ref_counted.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "content/public/browser/context_factory.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#import "page_host.h"
#include "pane_compositor_policy.h"
#import "pane_compositor_view.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/accelerated_widget_mac/accelerated_widget_mac.h"
#include "ui/accelerated_widget_mac/display_ca_layer_tree.h"
#include "ui/base/cocoa/views_hostable.h"
#include "ui/compositor/compositor.h"
#include "ui/compositor/layer.h"
#include "ui/compositor/recyclable_compositor_mac.h"
#include "ui/display/display.h"
#include "ui/display/display_observer.h"
#include "ui/display/screen.h"
#include "ui/gfx/geometry/dip_util.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/geometry/size_conversions.h"
#include "ui/gfx/geometry/size_f.h"

namespace parc {

class NativePaneCompositor;

namespace {

// A sweep marks an idle compositor and retires it at the next one.
constexpr base::TimeDelta kSweepDelay = base::Seconds(2);
// One idle compositor per window stays for the next switch, such as docked
// DevTools coming back with its page.
constexpr size_t kSpareCompositors = 1;

std::vector<NativePaneCompositorPool*>& Pools() {
  static base::NoDestructor<std::vector<NativePaneCompositorPool*>> pools;
  return *pools;
}

std::map<const content::WebContents*, base::WeakPtr<NativePaneCompositor>>&
Attachments() {
  static base::NoDestructor<
      std::map<const content::WebContents*,
               base::WeakPtr<NativePaneCompositor>>>
      attachments;
  return *attachments;
}

// Set by ShutDownPaneCompositors; nothing is attached or scheduled after.
bool& ShutDown() {
  static bool shut_down = false;
  return shut_down;
}

ui::ViewsHostableView* HostableView(NSView* view) {
  if (![view conformsToProtocol:@protocol(ViewsHostable)]) {
    return nullptr;
  }
  return [(id<ViewsHostable>)view viewsHostableView];
}

std::optional<PaneRect> WindowRect(NSView* view) {
  if (!view.window) {
    return std::nullopt;
  }
  const NSRect rect = [view convertRect:view.bounds toView:nil];
  return PaneRect{rect.origin.x, rect.origin.y, rect.size.width,
                  rect.size.height};
}

// Undoes the removal in WebContentsViewMac::ViewsHostableDetach, which hides
// the WebContents view and takes it out of its superview. Parc owns that
// hierarchy: a page host or, for first-docked tools, the DevTools pane view.
void RestoreNativeView(NSView* view,
                       NSView* superview,
                       NSView* above,
                       BOOL hidden,
                       NSRect frame) {
  if ([superview isMemberOfClass:PCNativePageHost.class]) {
    if (![(PCNativePageHost*)superview restoreContentView:view]) {
      return;
    }
  } else {
    if (above && above.superview == superview) {
      [superview addSubview:view positioned:NSWindowBelow relativeTo:above];
    } else {
      [superview addSubview:view];
    }
    if (view.superview != superview) {
      return;
    }
    if (!NSEqualRects(view.frame, frame)) {
      view.frame = frame;
    }
  }
  if (view.superview == superview && view.hidden != hidden) {
    view.hidden = hidden;
  }
}

}  // namespace

// One compositor and the view it draws into. While attached it is the
// ViewsHostableView::Host of one page's WebContents view, so Chromium draws
// every renderer of that page into its root layer.
class NativePaneCompositor final : public ui::ViewsHostableView::Host,
                                   public ui::AcceleratedWidgetMacNSView {
 public:
  explicit NativePaneCompositor(NativePaneCompositorPool& pool);
  NativePaneCompositor(const NativePaneCompositor&) = delete;
  NativePaneCompositor& operator=(const NativePaneCompositor&) = delete;
  ~NativePaneCompositor();

  NativePaneCompositorPool& pool() const { return *pool_; }
  bool attached() const { return hostable_ != nullptr; }
  // Mid hand-off or detachment: neither chosen nor retired.
  bool busy() const { return reserved_ || detaching_; }
  bool on_screen() const { return overlay_.onScreen; }
  ui::ViewsHostableView* hostable() const { return hostable_; }
  NSView* contents_view() const { return contents_view_; }
  void set_reserved(bool reserved) { reserved_ = reserved; }
  void set_marked(bool marked) { marked_ = marked; }
  void set_role(PaneRole role) { role_ = role; }
  base::WeakPtr<NativePaneCompositor> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

  PaneCompositorSlot Slot() const;
  void RecordRectIfOnScreen();
  // `view` is `contents`' WebContents view, shown or not yet shown.
  bool Attach(content::WebContents& contents,
              NSView* view,
              ui::ViewsHostableView& hostable);
  void Show(uint64_t use);
  void Hide(uint64_t use);
  // Gives up the page; `restore_view` puts its WebContents view back.
  void Detach(bool restore_view);
  // Conceals an incompatible held frame until the arriving page presents.
  void ClearDisplay();
  void UpdateSurface();
  void NotifyPresented(base::OnceClosure presented);

  // ui::ViewsHostableView::Host:
  ui::Layer* GetUiLayer() const override;
  remote_cocoa::mojom::Application* GetRemoteCocoaApplication() const override;
  uint64_t GetNSViewId() const override;
  void OnHostableViewDestroying() override;
  base::ScopedClosureRunner CreateVideoCaptureLock() override;

 private:
  // ui::AcceleratedWidgetMacNSView:
  void AcceleratedWidgetCALayerParamsUpdated(
      gfx::CALayerParams params) override;

  NSView* RendererView() const;
  void Place();
  void GeometryChanged();
  void ScreenChanged();
  void SuspendDrawing();
  void ResumeDrawing();
  void AllowProtectedLayers();
  void RequestPresentation();
  void DropPresentation();
  void ReleaseCaptureLock();
  void ReleasePool();

  const raw_ref<NativePaneCompositorPool> pool_;
  CALayer* __strong hosted_layer_;
  std::unique_ptr<ui::DisplayCALayerTree> tree_;
  PCNativePaneCompositorView* __strong overlay_;
  std::unique_ptr<ui::RecyclableCompositorMac> compositor_;
  // Viz may send a changed connection only once. Keep it while suspended;
  // expose it after the resumed page presents, rather than dropping it.
  std::optional<gfx::CALayerParams> deferred_ca_layer_params_;
  std::unique_ptr<ui::Layer> root_;
  base::WeakPtr<content::WebContents> contents_;
  raw_ptr<const content::WebContents> contents_key_ = nullptr;
  raw_ptr<ui::ViewsHostableView> hostable_ = nullptr;
  NSView* __strong contents_view_ = nil;
  // An attached page keeps its window's pool alive.
  scoped_refptr<NativePaneCompositorPool> keep_pool_;
  std::optional<PaneRect> rect_;
  PaneRole role_ = PaneRole::kPage;
  uint64_t last_used_ = 0;
  int capture_locks_ = 0;
  bool page_shown_ = false;
  bool drawing_ = false;
  bool marked_ = false;
  bool reserved_ = false;
  bool detaching_ = false;
  // The page whose frame this display holds: the one it last drew while it
  // could show FairPlay layers. An identity, never dereferenced.
  raw_ptr<const content::WebContents, DisableDanglingPtrDetection>
      held_frame_page_ = nullptr;
  // Advanced by each suspend and resume, cancelling a pending re-allow.
  uint64_t protected_layers_generation_ = 0;
  // Waiting for this page's next frame on screen; requested while drawing.
  std::vector<base::OnceClosure> presented_;
  // Advanced when the page is hidden or detached, so a frame requested for
  // an earlier showing reports nothing.
  uint64_t presentation_generation_ = 0;
  base::WeakPtrFactory<NativePaneCompositor> weak_factory_{this};
};

// The compositors of one NSWindow, shared by every Profile's browser host in
// that window. Held by the hosts' claims and by attached compositors.
class NativePaneCompositorPool final
    : public base::RefCounted<NativePaneCompositorPool>,
      public display::DisplayObserver {
 public:
  static scoped_refptr<NativePaneCompositorPool> ForWindow(NSWindow* window);
  NativePaneCompositorPool(const NativePaneCompositorPool&) = delete;
  NativePaneCompositorPool& operator=(const NativePaneCompositorPool&) = delete;

  void AddHost() { ++hosts_; }
  void RemoveHost();
  uint64_t NextUse() { return ++uses_; }
  PaneCompositorShow Show(content::WebContents& contents,
                          NSView* view,
                          ui::ViewsHostableView& hostable,
                          PaneRole role);
  void ScheduleSweep();
  void DestroyCompositors();

  // display::DisplayObserver: a same-screen refresh-rate, colour-space or
  // HDR change, which the display views' own notifications miss.
  void OnDisplayMetricsChanged(const display::Display& display,
                               uint32_t changed_metrics) override;

 private:
  friend class base::RefCounted<NativePaneCompositorPool>;
  struct Taken {
    raw_ptr<NativePaneCompositor> compositor;
    bool keeps_frame = false;
    bool created = false;
  };

  explicit NativePaneCompositorPool(NSWindow* window);
  ~NativePaneCompositorPool() override;

  Taken Take(NSView* view, PaneRole role);
  bool RetiresHiddenPages() const;
  void Sweep();
  void Retire(NativePaneCompositor& compositor);

  NSWindow* __weak window_;
  std::vector<std::unique_ptr<NativePaneCompositor>> compositors_;
  size_t hosts_ = 0;
  uint64_t uses_ = 0;
  bool sweep_pending_ = false;
  display::ScopedOptionalDisplayObserver display_observer_{this};
  base::WeakPtrFactory<NativePaneCompositorPool> weak_factory_{this};
};

namespace {

NativePaneCompositor* AttachedCompositor(const content::WebContents& contents) {
  auto& attachments = Attachments();
  auto found = attachments.find(&contents);
  if (found == attachments.end()) {
    return nullptr;
  }
  if (!found->second) {
    attachments.erase(found);
    return nullptr;
  }
  return found->second.get();
}

}  // namespace

NativePaneCompositor::NativePaneCompositor(NativePaneCompositorPool& pool)
    : pool_(pool), hosted_layer_([CALayer layer]) {
  // DisplayCALayerTree adds its autoresizing child before AppKit sizes the
  // hosted layer, as the video Picture-in-Picture view does.
  tree_ = std::make_unique<ui::DisplayCALayerTree>(hosted_layer_);
  overlay_ =
      [[PCNativePaneCompositorView alloc] initWithHostedLayer:hosted_layer_];
  // Created suspended, as Chromium's window compositors are.
  compositor_ = std::make_unique<ui::RecyclableCompositorMac>(
      content::GetContextFactory());
  root_ = ui::Layer::Create(ui::LAYER_NOT_DRAWN);
  root_->SetName("ParcPaneCompositor");
  root_->SetFillsBoundsOpaquely(false);
  compositor_->compositor()->SetRootLayer(root_.get());
  // Pixels no renderer drew show the pane behind, as the page's own view did.
  compositor_->compositor()->SetBackgroundColor(SK_ColorTRANSPARENT);
  compositor_->widget()->SetNSView(this);
  // Receive connection changes even while drawing is suspended. Dropping one
  // here can leave the display pointing at a retired CAContext until Viz's
  // next forced resend. The callback below defers its display instead.
  compositor_->widget()->SetSuspended(false);
  compositor_->compositor()->SetProtectedLayersAllowed(false);
  auto weak = weak_factory_.GetWeakPtr();
  overlay_.geometryHandler = ^{
    if (weak) {
      weak->GeometryChanged();
    }
  };
  overlay_.screenHandler = ^{
    if (weak) {
      weak->ScreenChanged();
    }
  };
}

NativePaneCompositor::~NativePaneCompositor() {
  CHECK(!hostable_);
  weak_factory_.InvalidateWeakPtrs();
  overlay_.geometryHandler = nil;
  overlay_.screenHandler = nil;
  [overlay_ removeFromSuperview];
  // The video Picture-in-Picture teardown order.
  compositor_->Suspend();
  compositor_->widget()->ResetNSView();
  compositor_->compositor()->SetRootLayer(nullptr);
  root_.reset();
  tree_.reset();
  compositor_.reset();
}

PaneCompositorSlot NativePaneCompositor::Slot() const {
  PaneCompositorSlot slot;
  slot.on_screen = on_screen();
  slot.attached = attached();
  slot.marked = marked_;
  slot.role = role_;
  slot.rect = rect_;
  if (root_ && !root_->bounds().IsEmpty()) {
    slot.size = PaneSize{static_cast<double>(root_->bounds().width()),
                         static_cast<double>(root_->bounds().height())};
  }
  slot.last_used = last_used_;
  return slot;
}

void NativePaneCompositor::RecordRectIfOnScreen() {
  if (on_screen()) {
    rect_ = WindowRect(overlay_);
  }
}

bool NativePaneCompositor::Attach(content::WebContents& contents,
                                  NSView* view,
                                  ui::ViewsHostableView& hostable) {
  CHECK(!hostable_ && !detaching_);
  contents_ = contents.GetWeakPtr();
  contents_key_ = &contents;
  hostable_ = &hostable;
  contents_view_ = view;
  keep_pool_ = base::WrapRefCounted(&pool_.get());
  Attachments()[&contents] = weak_factory_.GetWeakPtr();
  marked_ = false;
  // Where the page is, though it may not be shown yet.
  rect_ = WindowRect(view);
  Place();
  auto weak = weak_factory_.GetWeakPtr();
  // Chromium parents the page's renderers, and any it creates later, into
  // GetUiLayer (BrowserCompositorMac's UseParentLayerCompositor state).
  hostable.ViewsHostableAttach(this);
  return weak && hostable_ == &hostable && contents_view_ == view;
}

void NativePaneCompositor::Show(uint64_t use) {
  if (!page_shown_) {
    page_shown_ = true;
    last_used_ = use;
  }
  marked_ = false;
  Place();
  // A page about to be unhidden starts drawing from its display view's
  // viewDidUnhide (ScreenChanged).
  if (on_screen()) {
    ResumeDrawing();
  }
}

void NativePaneCompositor::Hide(uint64_t use) {
  if (page_shown_) {
    page_shown_ = false;
    last_used_ = use;
  }
  DropPresentation();
  if (!capture_locks_) {
    SuspendDrawing();
  }
}

void NativePaneCompositor::Detach(bool restore_view) {
  if (!hostable_ || detaching_) {
    return;
  }
  // The last frame stays on screen until the next page's first frame.
  SuspendDrawing();
  DropPresentation();
  detaching_ = true;
  page_shown_ = false;
  ui::ViewsHostableView* hostable = std::exchange(hostable_, nullptr).get();
  NSView* view = std::exchange(contents_view_, nil);
  const content::WebContents* key = std::exchange(contents_key_, nullptr);
  contents_.reset();
  NSView* superview = view.superview;
  NSView* above = nil;
  if (superview) {
    NSArray<NSView*>* siblings = superview.subviews;
    const NSUInteger index = [siblings indexOfObjectIdenticalTo:view];
    if (index != NSNotFound && index + 1 < siblings.count) {
      above = siblings[index + 1];
    }
  }
  const BOOL hidden = view.hidden;
  const NSRect frame = view.frame;
  auto weak = weak_factory_.GetWeakPtr();
  // Hides and removes the WebContents view, then unparents its renderers (now
  // hidden, their frames can be evicted). Its visibility callbacks find this
  // page's attachment busy, so none can reattach the page before Chromium
  // clears its host.
  hostable->ViewsHostableDetach();
  if (!weak) {
    return;
  }
  auto found = Attachments().find(key);
  if (found != Attachments().end() && found->second.get() == this) {
    Attachments().erase(found);
  }
  if (overlay_.superview) {
    [overlay_ removeFromSuperview];
  }
  if (restore_view && superview && view && !view.superview) {
    RestoreNativeView(view, superview, above, hidden, frame);
  }
  if (!weak) {
    return;
  }
  detaching_ = false;
  pool_->ScheduleSweep();
  ReleasePool();
}

void NativePaneCompositor::ReleasePool() {
  // Releasing here could destroy the pool, and this compositor, mid-call. A
  // dropped task leaks the reference (DeleteOrReleaseSoonInternal binds a raw
  // pointer), and ShutDownPaneCompositors has destroyed every compositor
  // before CefShutdown, so nothing outlives ImageTransportFactory.
  if (!ShutDown() && base::SingleThreadTaskRunner::HasCurrentDefault()) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->ReleaseSoon(
        FROM_HERE, std::move(keep_pool_));
  } else {
    std::ignore = keep_pool_.release();
  }
}

void NativePaneCompositor::ClearDisplay() {
  // Keep the CAContext connection. Viz suppresses unchanged CALayerParams
  // for ten seconds, and only resends them with another frame. Replacing
  // DisplayCALayerTree here disconnected a reused compositor even while its
  // new page rendered successfully; a static page stayed blank until input
  // caused a later frame. Conceal the incompatible picture instead, then
  // reveal the same live connection after the arriving page presents.
  overlay_.frameConcealed = YES;
}

ui::Layer* NativePaneCompositor::GetUiLayer() const {
  return root_.get();
}

remote_cocoa::mojom::Application*
NativePaneCompositor::GetRemoteCocoaApplication() const {
  return nullptr;
}

uint64_t NativePaneCompositor::GetNSViewId() const {
  // In-process only: WebContentsViewMac reads this for a remote application.
  return 0;
}

void NativePaneCompositor::OnHostableViewDestroying() {
  // WebContentsViewMac's destructor requires its host to have detached; the
  // view goes with its WebContents.
  Detach(/*restore_view=*/false);
}

base::ScopedClosureRunner NativePaneCompositor::CreateVideoCaptureLock() {
  // A captured page keeps its compositor drawing, as Chromium keeps a Views
  // window's compositor visible for capture.
  ++capture_locks_;
  ResumeDrawing();
  return base::ScopedClosureRunner(
      base::BindOnce(&NativePaneCompositor::ReleaseCaptureLock,
                     weak_factory_.GetWeakPtr()));
}

void NativePaneCompositor::ReleaseCaptureLock() {
  if (capture_locks_ > 0 && --capture_locks_ == 0 &&
      !(page_shown_ && on_screen())) {
    SuspendDrawing();
  }
}

void NativePaneCompositor::AcceleratedWidgetCALayerParamsUpdated(
    gfx::CALayerParams params) {
  if (!drawing_) {
    deferred_ca_layer_params_ = params.CloneWithoutFence();
    return;
  }
  deferred_ca_layer_params_.reset();
  tree_->UpdateCALayerTree(std::move(params));
}

NSView* NativePaneCompositor::RendererView() const {
  content::RenderWidgetHostView* view =
      contents_ ? contents_->GetRenderWidgetHostView() : nullptr;
  return view ? view->GetNativeView().GetNativeNSView() : nil;
}

void NativePaneCompositor::Place() {
  NSView* view = contents_view_;
  if (!view) {
    return;
  }
  // Above the renderer, which Chromium inserts at the bottom of the
  // WebContents view, and below anything else installed over it.
  NSView* renderer = RendererView();
  NSArray<NSView*>* subviews = view.subviews;
  const NSUInteger overlay_index = [subviews indexOfObjectIdenticalTo:overlay_];
  const NSUInteger renderer_index =
      renderer ? [subviews indexOfObjectIdenticalTo:renderer] : NSNotFound;
  if (overlay_index == NSNotFound ||
      (renderer_index != NSNotFound && overlay_index < renderer_index)) {
    if (renderer_index != NSNotFound) {
      [view addSubview:overlay_ positioned:NSWindowAbove relativeTo:renderer];
    } else {
      [view addSubview:overlay_ positioned:NSWindowBelow relativeTo:nil];
    }
  }
  if (overlay_.superview != view) {
    return;
  }
  if (!NSEqualRects(overlay_.frame, view.bounds)) {
    overlay_.frame = view.bounds;
  }
  UpdateSurface();
}

void NativePaneCompositor::UpdateSurface() {
  NSWindow* window = overlay_.window;
  const NSSize size = overlay_.bounds.size;
  if (!window || size.width < 1 || size.height < 1) {
    return;
  }
  const display::Display display =
      display::Screen::Get()->GetDisplayNearestWindow(
          gfx::NativeWindow(window));
  const float scale = display.device_scale_factor();
  const gfx::Size dip = gfx::ToFlooredSize(gfx::SizeF(
      static_cast<float>(size.width), static_cast<float>(size.height)));
  root_->SetBounds(gfx::Rect(dip));
  compositor_->UpdateSurface(
      gfx::ToRoundedSize(gfx::ConvertSizeToPixels(dip, scale)), scale,
      display.GetColorSpaces(), display.id(), display.display_frequency());
}

void NativePaneCompositor::GeometryChanged() {
  RecordRectIfOnScreen();
  UpdateSurface();
}

void NativePaneCompositor::ScreenChanged() {
  // The display view leaving the screen stops drawing at once, so no frame
  // without the page replaces the one held for the next page; rejoining it
  // with the page shown resumes.
  if (!attached()) {
    return;
  }
  if (on_screen()) {
    RecordRectIfOnScreen();
    if (page_shown_) {
      ResumeDrawing();
    }
  } else if (!capture_locks_) {
    SuspendDrawing();
  }
}

void NativePaneCompositor::SuspendDrawing() {
  if (!drawing_) {
    return;
  }
  drawing_ = false;
  // Hold the last frame without losing connection changes: stop commits and
  // defer in-flight CALayerParams in our callback until drawing resumes.
  compositor_->Suspend();
  // Its display still redraws when a surface the held frame embeds changes.
  // It must not take a FairPlay video's layer from the compositor that shows
  // the page now (a page dragged to another window): it draws such a video
  // black instead. Nothing else in a frame changes, so the held frame of a
  // page without FairPlay video is exactly as before.
  compositor_->compositor()->SetProtectedLayersAllowed(false);
  ++protected_layers_generation_;
}

void NativePaneCompositor::ResumeDrawing() {
  if (!drawing_) {
    drawing_ = true;
    AllowProtectedLayers();
    compositor_->widget()->SetSuspended(false);
    compositor_->Unsuspend();
  }
  // A capture lock can keep drawing across Hide, which cancels presentation
  // callbacks. Showing again must still arrange to reveal a concealed frame.
  if (!presented_.empty() || overlay_.frameConcealed ||
      deferred_ca_layer_params_) {
    RequestPresentation();
  }
}

void NativePaneCompositor::NotifyPresented(base::OnceClosure presented) {
  presented_.push_back(std::move(presented));
  if (drawing_) {
    RequestPresentation();
  }
}

void NativePaneCompositor::RequestPresentation() {
  std::vector<base::OnceClosure> presented = std::exchange(presented_, {});
  compositor_->compositor()->RequestSuccessfulPresentationTimeForNextFrame(
      base::BindOnce(
          [](base::WeakPtr<NativePaneCompositor> self, uint64_t generation,
             std::vector<base::OnceClosure> presented,
             const viz::FrameTimingDetails&) {
            if (!self || generation != self->presentation_generation_) {
              return;
            }
            if (self->drawing_) {
              if (self->deferred_ca_layer_params_) {
                self->tree_->UpdateCALayerTree(
                    std::move(*self->deferred_ca_layer_params_));
                self->deferred_ca_layer_params_.reset();
              }
              self->overlay_.frameConcealed = NO;
            }
            for (auto& callback : presented) {
              std::move(callback).Run();
            }
          },
          weak_factory_.GetWeakPtr(), presentation_generation_,
          std::move(presented)));
  // The page may have nothing new to commit (its saved frame is current), and
  // the request alone makes no frame.
  compositor_->compositor()->ScheduleFullRedraw();
}

void NativePaneCompositor::DropPresentation() {
  presented_.clear();
  ++presentation_generation_;
}

void NativePaneCompositor::AllowProtectedLayers() {
  const uint64_t generation = ++protected_layers_generation_;
  if (!held_frame_page_ || held_frame_page_ == contents_key_) {
    // The held frame is this page's, or there is none: show its FairPlay video
    // again at once (viz redraws a frame that had one).
    held_frame_page_ = contents_key_;
    compositor_->compositor()->SetProtectedLayersAllowed(true);
    return;
  }
  // The held frame is another page's. Redrawing it now would place that page's
  // FairPlay video here, taking it from the compositor that shows the page, so
  // wait until this page's first frame is on screen. Requesting the feedback
  // doesn't make a frame; the page's first commit does.
  compositor_->compositor()->RequestSuccessfulPresentationTimeForNextFrame(
      base::BindOnce(
          [](base::WeakPtr<NativePaneCompositor> self, uint64_t generation,
             uintptr_t page, const viz::FrameTimingDetails&) {
            // `page` identifies the page that asked; it is never dereferenced.
            if (!self || reinterpret_cast<uintptr_t>(
                             self->contents_key_.get()) != page) {
              return;
            }
            // The display now holds this page's frame, even if it was parked
            // again before this arrived.
            self->held_frame_page_ = self->contents_key_;
            if (generation == self->protected_layers_generation_) {
              self->compositor_->compositor()->SetProtectedLayersAllowed(true);
            }
          },
          weak_factory_.GetWeakPtr(), generation,
          reinterpret_cast<uintptr_t>(contents_key_.get())));
}

scoped_refptr<NativePaneCompositorPool> NativePaneCompositorPool::ForWindow(
    NSWindow* window) {
  CHECK(window);
  for (NativePaneCompositorPool* pool : Pools()) {
    if (pool->window_ == window) {
      return base::WrapRefCounted(pool);
    }
  }
  return base::WrapRefCounted(new NativePaneCompositorPool(window));
}

NativePaneCompositorPool::NativePaneCompositorPool(NSWindow* window)
    : window_(window) {
  Pools().push_back(this);
}

NativePaneCompositorPool::~NativePaneCompositorPool() {
  std::erase(Pools(), this);
  weak_factory_.InvalidateWeakPtrs();
  // Every compositor is free here: an attached one keeps the pool alive.
  compositors_.clear();
}

void NativePaneCompositorPool::RemoveHost() {
  CHECK(hosts_);
  --hosts_;
  ScheduleSweep();
}

void NativePaneCompositorPool::OnDisplayMetricsChanged(
    const display::Display& display,
    uint32_t changed_metrics) {
  for (const auto& compositor : compositors_) {
    compositor->UpdateSurface();
  }
}

PaneCompositorShow NativePaneCompositorPool::Show(
    content::WebContents& contents,
    NSView* view,
    ui::ViewsHostableView& hostable,
    PaneRole role) {
  if (ShutDown()) {
    return PaneCompositorShow::kRefused;
  }
  scoped_refptr<NativePaneCompositorPool> keep(this);
  auto weak_contents = contents.GetWeakPtr();
  const auto still_current = [&] {
    return weak_contents &&
           weak_contents->GetNativeView().GetNativeNSView() == view &&
           HostableView(view) == &hostable && view.window &&
           view.window == window_;
  };
  if (NativePaneCompositor* current = AttachedCompositor(contents)) {
    if (current->busy()) {
      return PaneCompositorShow::kBusy;
    }
    if (&current->pool() == this && current->hostable() == &hostable &&
        current->contents_view() == view) {
      current->set_role(role);
      current->Show(NextUse());
      ScheduleSweep();
      return PaneCompositorShow::kShown;
    }
    // Another window's compositor, or one bound to a replaced native view.
    current->Detach(/*restore_view=*/true);
    if (!still_current()) {
      return PaneCompositorShow::kRefused;
    }
    if (AttachedCompositor(*weak_contents)) {
      return PaneCompositorShow::kBusy;
    }
  }
  const Taken taken = Take(view, role);
  NativePaneCompositor* target = taken.compositor;
  auto weak_target = target->GetWeakPtr();
  target->set_reserved(true);
  if (target->attached()) {
    target->Detach(/*restore_view=*/true);
  }
  if (!weak_target) {
    return PaneCompositorShow::kBusy;
  }
  target->set_reserved(false);
  if (!still_current()) {
    ScheduleSweep();
    return PaneCompositorShow::kRefused;
  }
  if (target->attached() || AttachedCompositor(*weak_contents)) {
    ScheduleSweep();
    return PaneCompositorShow::kBusy;
  }
  if (!taken.keeps_frame && !taken.created) {
    // Another pane's last frame: show the pane's own backing instead.
    target->ClearDisplay();
  }
  target->set_role(role);
  if (!target->Attach(*weak_contents, view, hostable) || !weak_target) {
    ScheduleSweep();
    return PaneCompositorShow::kBusy;
  }
  target->Show(NextUse());
  ScheduleSweep();
  return PaneCompositorShow::kShown;
}

NativePaneCompositorPool::Taken NativePaneCompositorPool::Take(NSView* view,
                                                              PaneRole role) {
  std::vector<PaneCompositorSlot> slots;
  std::vector<NativePaneCompositor*> candidates;
  for (const auto& compositor : compositors_) {
    if (compositor->busy()) {
      continue;
    }
    compositor->RecordRectIfOnScreen();
    slots.push_back(compositor->Slot());
    candidates.push_back(compositor.get());
  }
  // The size the page will be drawn at: UpdateSurface floors the display
  // view's bounds, which Place sets to the page view's, the same way.
  std::optional<PaneSize> size;
  const gfx::Size dip = gfx::ToFlooredSize(
      gfx::SizeF(static_cast<float>(view.bounds.size.width),
                 static_cast<float>(view.bounds.size.height)));
  if (!dip.IsEmpty()) {
    size = PaneSize{static_cast<double>(dip.width()),
                    static_cast<double>(dip.height())};
  }
  if (const auto choice =
          ChoosePaneCompositor(slots, role, WindowRect(view), size)) {
    return {candidates[choice->index], choice->keeps_frame, false};
  }
  compositors_.push_back(std::make_unique<NativePaneCompositor>(*this));
  return {compositors_.back().get(), false, true};
}

void NativePaneCompositorPool::ScheduleSweep() {
  if (sweep_pending_ || ShutDown() ||
      !base::SingleThreadTaskRunner::HasCurrentDefault()) {
    return;
  }
  sweep_pending_ = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE,
      base::BindOnce(&NativePaneCompositorPool::Sweep,
                     weak_factory_.GetWeakPtr()),
      kSweepDelay);
}

bool NativePaneCompositorPool::RetiresHiddenPages() const {
  NSWindow* window = window_;
  return !hosts_ || !window || (window.visible && !window.miniaturized);
}

void NativePaneCompositorPool::Sweep() {
  sweep_pending_ = false;
  if (ShutDown()) {
    return;
  }
  scoped_refptr<NativePaneCompositorPool> keep(this);
  std::vector<PaneCompositorSlot> slots;
  std::vector<base::WeakPtr<NativePaneCompositor>> candidates;
  bool again = false;
  for (const auto& compositor : compositors_) {
    if (compositor->busy()) {
      again = true;
      continue;
    }
    compositor->RecordRectIfOnScreen();
    slots.push_back(compositor->Slot());
    candidates.push_back(compositor->GetWeakPtr());
  }
  NSWindow* window = window_;
  const auto plan =
      PlanPaneCompositorSweep(slots, RetiresHiddenPages(),
                              hosts_ && window ? kSpareCompositors : 0);
  std::vector<base::WeakPtr<NativePaneCompositor>> retiring;
  for (size_t index = 0; index < plan.size(); ++index) {
    switch (plan[index]) {
      case PaneCompositorSweep::kKeep:
        candidates[index]->set_marked(false);
        break;
      case PaneCompositorSweep::kMark:
        candidates[index]->set_marked(true);
        again = true;
        break;
      case PaneCompositorSweep::kRetire:
        retiring.push_back(candidates[index]);
        break;
    }
  }
  for (const auto& compositor : retiring) {
    if (compositor && !compositor->busy() && !compositor->on_screen()) {
      Retire(*compositor);
    }
  }
  if (again) {
    ScheduleSweep();
  }
}

void NativePaneCompositorPool::Retire(NativePaneCompositor& compositor) {
  auto weak = compositor.GetWeakPtr();
  compositor.Detach(/*restore_view=*/true);
  if (!weak || weak->attached() || weak->busy()) {
    return;
  }
  std::erase_if(compositors_, [&](const auto& candidate) {
    return candidate.get() == weak.get();
  });
}

void NativePaneCompositorPool::DestroyCompositors() {
  scoped_refptr<NativePaneCompositorPool> keep(this);
  weak_factory_.InvalidateWeakPtrs();
  sweep_pending_ = false;
  std::vector<base::WeakPtr<NativePaneCompositor>> all;
  for (const auto& compositor : compositors_) {
    all.push_back(compositor->GetWeakPtr());
  }
  for (const auto& compositor : all) {
    if (compositor) {
      compositor->Detach(/*restore_view=*/true);
    }
  }
  // One a native callback left attached is leaked rather than destroyed with
  // a page still parented to it; the process is exiting.
  for (auto& compositor : compositors_) {
    if (compositor->attached() || compositor->busy()) {
      std::ignore = compositor.release();
    }
  }
  compositors_.clear();
}

NativePaneCompositorClaim::NativePaneCompositorClaim(NSWindow* window)
    : pool_(NativePaneCompositorPool::ForWindow(window)) {
  CHECK(NSThread.isMainThread);
  pool_->AddHost();
}

NativePaneCompositorClaim::~NativePaneCompositorClaim() {
  pool_->RemoveHost();
}

PaneCompositorShow ShowInPaneCompositor(content::WebContents& contents,
                                        NSWindow* window,
                                        PaneRole role) {
  CHECK(NSThread.isMainThread);
  NSView* view = contents.GetNativeView().GetNativeNSView();
  ui::ViewsHostableView* hostable = HostableView(view);
  if (ShutDown() || !window || !hostable || view.window != window ||
      contents.IsBeingDestroyed()) {
    return PaneCompositorShow::kRefused;
  }
  return NativePaneCompositorPool::ForWindow(window)->Show(contents, view,
                                                           *hostable, role);
}

void HidePaneCompositor(content::WebContents& contents) {
  CHECK(NSThread.isMainThread);
  NativePaneCompositor* compositor = AttachedCompositor(contents);
  if (!compositor || compositor->busy() || compositor->on_screen()) {
    return;
  }
  NativePaneCompositorPool& pool = compositor->pool();
  compositor->Hide(pool.NextUse());
  pool.ScheduleSweep();
}

bool NotifyPaneCompositorPresented(content::WebContents& contents,
                                   base::OnceClosure presented) {
  CHECK(NSThread.isMainThread);
  NativePaneCompositor* compositor = AttachedCompositor(contents);
  if (compositor && compositor->busy()) {
    return false;
  }
  if (!compositor) {
    if (!ShutDown() && base::SingleThreadTaskRunner::HasCurrentDefault()) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, std::move(presented));
    }
    return true;
  }
  compositor->NotifyPresented(std::move(presented));
  return true;
}

void ShutDownPaneCompositors() {
  CHECK(NSThread.isMainThread);
  if (ShutDown()) {
    return;
  }
  ShutDown() = true;
  std::vector<scoped_refptr<NativePaneCompositorPool>> pools;
  for (NativePaneCompositorPool* pool : Pools()) {
    pools.push_back(base::WrapRefCounted(pool));
  }
  for (const auto& pool : pools) {
    pool->DestroyCompositors();
  }
}

}  // namespace parc
