// Copyright 2026 Parc contributors.
// Arc142 0x68a30a4 owns the real VideoOverlayWindow controller and supplied
// compositor surface; 0xa89c328/a889c90 use RecyclableCompositorMac. This is
// source-owned adaptation to Chromium156, not a binary wrapper.
#include "cef/libcef/browser/parc_native/video_overlay_window.h"

#import <QuartzCore/QuartzCore.h>

#include <cstdio>

#include "base/check.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "cef/libcef/browser/chrome/browser_delegate.h"
#import "cef/libcef/browser/parc_native/native_appkit_bridge.h"
#include "cef/libcef/browser/parc_native/native_appkit_page.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_occlusion_tracker.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/tabs/public/tab_interface.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "content/public/browser/context_factory.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/overlay_window.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "services/media_session/public/cpp/media_image_manager.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkColorType.h"
#include "third_party/skia/include/core/SkImageInfo.h"
#include "ui/accelerated_widget_mac/accelerated_widget_mac.h"
#include "ui/accelerated_widget_mac/display_ca_layer_tree.h"
#include "ui/compositor/layer.h"
#include "ui/compositor/layer_surface.h"
#include "ui/compositor/recyclable_compositor_mac.h"
#include "ui/display/display.h"
#include "ui/display/screen.h"
#include "ui/gfx/geometry/dip_util.h"
#include "ui/gfx/geometry/size_conversions.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/mac/coordinate_conversion.h"

namespace parc {
namespace {
// Favicon downloads can arrive as non-N32; CreateFrom1xBitmap CHECKs kN32.
// Match chrome/browser/ui/views/overlay/video_overlay_window_views.cc.
gfx::ImageSkia ImageSkiaFromFaviconBitmap(const SkBitmap& bitmap) {
  if (bitmap.empty()) {
    return gfx::ImageSkia();
  }
  if (bitmap.info().colorType() == kN32_SkColorType) {
    return gfx::ImageSkia::CreateFrom1xBitmap(bitmap);
  }
  SkImageInfo color_type_info = bitmap.info().makeColorType(kN32_SkColorType);
  SkBitmap color_type_copy;
  if (!color_type_copy.tryAllocPixels(color_type_info)) {
    return gfx::ImageSkia();
  }
  if (!bitmap.readPixels(color_type_info, color_type_copy.getPixels(),
                         color_type_copy.rowBytes(), 0, 0)) {
    return gfx::ImageSkia();
  }
  return gfx::ImageSkia::CreateFrom1xBitmap(color_type_copy);
}

// Read-only diagnostics stay with the original WebContents across native PiP
// disposal and reload. They neither retain a Browser nor create a page wrapper.
const char kPiPInputDiagnosticsKey = 0;
class PiPInputDiagnostics final : public content::WebContentsObserver,
                                  public base::SupportsUserData::Data {
 public:
  static void Begin(content::WebContents* contents, NSWindow* pip_window) {
    if (!contents || !base::CommandLine::InitializedForCurrentProcess()) {
      return;
    }
    const auto* command = base::CommandLine::ForCurrentProcess();
    if (!command->HasSwitch("parc-diagnostics") &&
        !command->HasSwitch("parc-smoke")) {
      return;
    }
    auto* self = Get(contents);
    if (!self) {
      auto diagnostic = std::make_unique<PiPInputDiagnostics>(contents);
      self = diagnostic.get();
      contents->SetUserData(&kPiPInputDiagnosticsKey, std::move(diagnostic));
    }
    ++self->generation_;
    self->returned_ = false;
    self->reload_navigation_ = 0;
    self->waiting_reload_load_ = false;
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    self->tab_ = tab ? tab->GetWeakPtr() : nullptr;
    self->browser_ = browser ? browser->GetWeakPtr() : nullptr;
    self->window_ = ExistingNativePage(contents).nativeView.window;
    self->pip_window_ = pip_window;
    auto* frame = contents->GetPrimaryMainFrame();
    self->frame_ =
        frame ? frame->GetGlobalId() : content::GlobalRenderFrameHostId();
    self->Snapshot("before-entry");
  }
  static void WillReturn(content::WebContents* contents) {
    if (auto* self = Get(contents)) {
      self->returned_ = true;
      self->Snapshot("before-return");
      // Queue before the terminal controller action. That action can destroy
      // the overlay, page, or Browser. Only the original live observer can run.
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
          FROM_HERE,
          base::BindOnce(&PiPInputDiagnostics::AfterReturn,
                         self->weak_factory_.GetWeakPtr(), self->generation_));
    }
  }
  explicit PiPInputDiagnostics(content::WebContents* contents)
      : content::WebContentsObserver(contents) {}
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (!returned_ || !handle->IsInPrimaryMainFrame()) {
      return;
    }
    // A later primary navigation supersedes the observed reload's completion.
    reload_navigation_ = 0;
    waiting_reload_load_ = false;
    if (handle->GetReloadType() != content::ReloadType::NONE) {
      reload_navigation_ = handle->GetNavigationId();
      Snapshot("reload-start");
    }
  }
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    if (reload_navigation_ && handle->GetNavigationId() == reload_navigation_) {
      reload_navigation_ = 0;
      waiting_reload_load_ = handle->HasCommitted();
      Snapshot(handle->HasCommitted() ? "reload-committed"
                                      : "reload-not-committed");
    }
  }
  void DidStopLoading() override {
    if (waiting_reload_load_) {
      waiting_reload_load_ = false;
      Snapshot("reload-loaded");
    }
  }
  void WebContentsDestroyed() override {
    fprintf(stderr,
            "Parc PiP input: phase=contents-destroyed generation=%llu\n",
            static_cast<unsigned long long>(generation_));
    weak_factory_.InvalidateWeakPtrs();
    Observe(nullptr);
  }

 private:
  static PiPInputDiagnostics* Get(content::WebContents* contents) {
    return contents ? static_cast<PiPInputDiagnostics*>(
                          contents->GetUserData(&kPiPInputDiagnosticsKey))
                    : nullptr;
  }
  void AfterReturn(uint64_t generation) {
    if (generation == generation_) {
      Snapshot("after-return");
    }
  }
  void Snapshot(const char* phase) {
    auto* contents = web_contents();
    if (!contents || contents->IsBeingDestroyed()) {
      return;
    }
    auto* frame = contents->GetPrimaryMainFrame();
    auto* view = contents->GetRenderWidgetHostView();
    auto* modal =
        web_modal::WebContentsModalDialogManager::FromWebContents(contents);
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    NSView* page = ExistingNativePage(contents).nativeView;
    NSView* renderer = view ? view->GetNativeView().GetNativeNSView() : nil;
    NSWindow* window = page.window;
    NSResponder* responder = window.firstResponder;
    const bool responder_in_page = [responder isKindOfClass:NSView.class] &&
                                   [(NSView*)responder isDescendantOf:page];
    // Only state, engine frame/window IDs and native class names. Never URLs, titles,
    // DOM text, field values or credentials. All queries are observational.
    const auto id =
        frame ? frame->GetGlobalId() : content::GlobalRenderFrameHostId();
    fprintf(stderr,
            "Parc PiP input: phase=%s generation=%llu frame=%d:%d "
            "same_frame=%d frame_live=%d frame_active=%d loading=%d "
            "ignore_input=%d primary_process_blocked=%d modal_active=%d "
            "visibility=%d pip_video=%d "
            "rwh_focus=%d rwh_ax_focus=%d tab_active=%d same_tab=%d "
            "same_browser=%d "
            "page_present=%d renderer_present=%d same_window=%d "
            "renderer_same_window=%d renderer_in_page=%d page_hidden=%d "
            "renderer_hidden=%d "
            "window_visible=%d window_miniaturized=%d window_key=%d "
            "window_main=%d app_active=%d "
            "source_window_number=%ld pip_window_number=%ld "
            "first_responder_in_page=%d first_responder_class=%s\n",
            phase, static_cast<unsigned long long>(generation_),
            id.child_id.GetUnsafeValue(), id.frame_routing_id, id == frame_,
            frame && frame->IsRenderFrameLive(), frame && frame->IsActive(),
            contents->IsLoading(),
            contents->ShouldIgnoreInputEventsForTesting(),
            frame && frame->GetProcess()->IsBlocked(),
            modal && modal->IsDialogActive(),
            static_cast<int>(contents->GetVisibility()),
            contents->HasPictureInPictureVideo(), view && view->HasFocus(),
            view && view->AccessibilityHasFocus(), tab && tab->IsActivated(),
            tab && tab == tab_.get(), browser && browser == browser_.get(),
            page != nil, renderer != nil, window && window == window_,
            window && renderer.window == window,
            renderer && page && [renderer isDescendantOf:page],
            page.hiddenOrHasHiddenAncestor, renderer.hiddenOrHasHiddenAncestor,
            window.visible, window.miniaturized, window.keyWindow,
            window.mainWindow, NSApp.active,
            static_cast<long>(window ? window.windowNumber : 0),
            static_cast<long>(pip_window_ ? pip_window_.windowNumber : 0),
            responder_in_page,
            responder ? NSStringFromClass(responder.class).UTF8String : "nil");
  }
  base::WeakPtr<tabs::TabInterface> tab_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  NSWindow* __weak window_ = nil;
  NSWindow* __weak pip_window_ = nil;
  content::GlobalRenderFrameHostId frame_;
  uint64_t generation_ = 0;
  int64_t reload_navigation_ = 0;
  bool returned_ = false;
  bool waiting_reload_load_ = false;
  base::WeakPtrFactory<PiPInputDiagnostics> weak_factory_{this};
};

class NativeVideoOverlayWindow final : public content::VideoOverlayWindow,
                                       public content::WebContentsObserver,
                                       public ui::AcceleratedWidgetMacNSView {
 public:
  explicit NativeVideoOverlayWindow(
      content::VideoPictureInPictureWindowController* controller)
      : content::WebContentsObserver(controller->GetWebContents()),
        controller_(controller) {
    CHECK(controller_);
    CHECK(web_contents());
    CHECK(!controller_->IsImmersive());
    NSView* video = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 180)];
    // DisplayCALayerTree adds an initially zero-sized autoresizing child.
    // Install it before AppKit sizes the explicit hosting layer to the view;
    // adding it to an already sized backing layer leaves its width at zero.
    // This is the Arc142 PiPNSView and current Chromium macOS host ordering.
    CALayer* background = [CALayer layer];
    background.backgroundColor = NSColor.blackColor.CGColor;
    tree_ = std::make_unique<ui::DisplayCALayerTree>(background);
    video.layer = background;
    video.wantsLayer = YES;
    compositor_ = std::make_unique<ui::RecyclableCompositorMac>(
        content::GetContextFactory());
    surface_layer_ = std::make_unique<ui::LayerSurface>();
    surface_layer_->SetName("ParcVideoPictureInPicture");
    surface_layer_->SetFillsBoundsOpaquely(true);
    surface_layer_->SetFallbackBackgroundColor(SkColors::kBlack);
    compositor_->compositor()->SetRootLayer(surface_layer_.get());
    compositor_->compositor()->SetBackgroundColor(SK_ColorBLACK);
    // Draws only while shown (ShowInactive). A suspended compositor only defers
    // its own commits; its display still redraws when the embedded video
    // surface changes. A hidden window drawing a FairPlay video would take the
    // video's protected layer back from the page (COMPOSITING.md).
    compositor_->compositor()->SetVisible(false);
    compositor_->widget()->SetNSView(this);
    auto weak = weak_factory_.GetWeakPtr();
    gfx::Rect source = web_contents()->GetContainerBounds();
    if (!controller_->GetSourceBounds().IsEmpty()) {
      source.set_size(controller_->GetSourceBounds().size());
      source.Offset(controller_->GetSourceBounds().OffsetFromOrigin());
    }
    presenter_ = CreateAppKitVideoPiPWindow(
        video, gfx::ScreenRectToNSRect(source),
        ^(PCVideoPiPAction action, double value) {
          if (weak) {
            weak->Action(action, value);
          }
        },
        ^{
          if (weak) {
            weak->Update();
          }
        },
        &application_);
    tracker_ =
        PictureInPictureWindowManager::GetInstance()->GetOcclusionTracker();
    if (tracker_) {
      native_id_ = tracker_->RegisterNativePictureInPictureWindow(
          gfx::NativeWindow(presenter_.panel));
    }
  }
  ~NativeVideoOverlayWindow() override {
    weak_factory_.InvalidateWeakPtrs();
    controller_ = nullptr;
    Observe(nullptr);
    //
    // invalidate native view, then release compositor. Notifications can
    // reenter.
    compositor_->Suspend();
    compositor_->widget()->ResetNSView();
    if (surface_id_.is_valid()) {
      compositor_->compositor()->RemoveChildFrameSink(
          surface_id_.frame_sink_id());
    }
    compositor_->compositor()->SetRootLayer(nullptr);
    surface_layer_.reset();
    tree_.reset();
    ReleaseAppKitVideoPiPWindow(presenter_, application_);
    compositor_.reset();
    if (tracker_ && native_id_) {
      tracker_->RemoveNativePictureInPictureWindow(native_id_);
    }
  }
  bool IsActive() const override { return presenter_.panel.isKeyWindow; }
  bool IsVisible() const override {
    return !presenter_.invalidated && presenter_.panel.isVisible;
  }
  gfx::Rect GetBounds() override {
    return gfx::ScreenRectFromNSRect(presenter_.panel.frame);
  }
  void Close() override { Hide(); }
  void Hide() override {
    if (controller_) controller_->SetScrubbing(false);
    compositor_->Suspend();
    compositor_->widget()->SetSuspended(true);
    // Stop drawing, as NativeWidgetMacNSWindowHost does for a hidden window.
    compositor_->compositor()->SetVisible(false);
    [presenter_ hide];  // Last access: occlusion observers can delete this.
  }
  void ShowInactive() override {
    // The real controller reuses its hidden overlay for subsequent sessions.
    PiPInputDiagnostics::Begin(web_contents(), presenter_.panel);
    compositor_->compositor()->SetVisible(true);
    compositor_->widget()->SetSuspended(false);
    [presenter_
        showInactive];  // Last access: real native callbacks may delete.
  }
  void UpdateNaturalSize(const gfx::Size& size) override {
    [presenter_ setNaturalSize:NSMakeSize(size.width(), size.height())];
  }
  void SetSurfaceId(const viz::SurfaceId& surface) override {
    if (surface == surface_id_) {
      return;
    }
    if (surface_id_.is_valid()) {
      compositor_->compositor()->RemoveChildFrameSink(
          surface_id_.frame_sink_id());
    }
    surface_id_ = surface;
    if (surface_id_.is_valid()) {
      compositor_->compositor()->AddChildFrameSink(surface_id_.frame_sink_id());
    }
    Update();
  }
  void SetPlaybackState(PlaybackState state) override {
    [presenter_ setAction:PCVideoPiPPlayPause
                    title:state == kPlaying ? @"Pause" : @"Play"];
  }
#define PARC_PIP_VISIBILITY(method, action)        \
  void method(bool visible) override {             \
    [presenter_ setAction:action visible:visible]; \
  }
  PARC_PIP_VISIBILITY(SetPlayPauseButtonVisibility, PCVideoPiPPlayPause)
  PARC_PIP_VISIBILITY(SetSkipAdButtonVisibility, PCVideoPiPSkipAd)
  PARC_PIP_VISIBILITY(SetNextTrackButtonVisibility, PCVideoPiPNextTrack)
  PARC_PIP_VISIBILITY(SetPreviousTrackButtonVisibility, PCVideoPiPPreviousTrack)
  PARC_PIP_VISIBILITY(SetHidePictureInPictureButtonVisibility,
                      PCVideoPiPMinimize)
  PARC_PIP_VISIBILITY(SetToggleMicrophoneButtonVisibility, PCVideoPiPMicrophone)
  PARC_PIP_VISIBILITY(SetToggleCameraButtonVisibility, PCVideoPiPCamera)
  PARC_PIP_VISIBILITY(SetHangUpButtonVisibility, PCVideoPiPHangUp)
  PARC_PIP_VISIBILITY(SetNextSlideButtonVisibility, PCVideoPiPNextSlide)
  PARC_PIP_VISIBILITY(SetPreviousSlideButtonVisibility, PCVideoPiPPreviousSlide)
#undef PARC_PIP_VISIBILITY
  void SetMicrophoneMuted(bool muted) override {
    [presenter_ setAction:PCVideoPiPMicrophone
                    title:muted ? @"Unmute Microphone" : @"Mute Microphone"];
  }
  void SetCameraState(bool on) override {
    [presenter_ setAction:PCVideoPiPCamera
                    title:on ? @"Turn Camera Off" : @"Turn Camera On"];
  }
  void SetMediaMuted(bool muted) override {
    muted_ = muted;
    [presenter_ setAction:PCVideoPiPMute title:muted ? @"Unmute" : @"Mute"];
  }
  void SetMediaPosition(const media_session::MediaPosition& position) override {
    [presenter_ setPosition:position.GetPosition().InSecondsF()
                   duration:position.duration().InSecondsF()];
  }
  void SetSourceTitle(const std::u16string& title) override {
    [presenter_ setSourceTitle:base::SysUTF16ToNSString(title)];
  }
  void SetFaviconImages(
      const std::vector<media_session::MediaImage>& images) override {
    const uint64_t generation = ++image_generation_;
    [presenter_ setFavicon:nil];
    media_session::MediaImageManager image_manager(16, 32);
    auto image = image_manager.SelectImage(images);
    if (!image || !controller_) {
      return;
    }
    controller_->GetMediaImage(
        *image, 16, 32,
        base::BindOnce(
            [](base::WeakPtr<NativeVideoOverlayWindow> self,
               uint64_t generation, const SkBitmap& bitmap) {
              if (!self || generation != self->image_generation_) {
                return;
              }
              gfx::ImageSkia image = ImageSkiaFromFaviconBitmap(bitmap);
              if (image.isNull()) {
                return;
              }
              [self->presenter_
                  setFavicon:gfx::Image(image).AsNSImage()];
            },
            weak_factory_.GetWeakPtr(), generation));
  }
  void SetPlaybackControlsVisibility(bool visible) override {
    [presenter_ setControlsVisible:visible];
  }
  void SetImmersiveVideoOptions(const content::ImmersiveOptions&) override {
    // Chrome macOS does not enable immersive playback. Native entry
    // additionally rejects it before session creation; silently flattening
    // immersive video would misrepresent its projection and stereo contract.
    CHECK(false) << "Native macOS PiP does not accept immersive sessions";
  }

 private:
  void AcceleratedWidgetCALayerParamsUpdated(
      gfx::CALayerParams params) override {
    tree_->UpdateCALayerTree(std::move(params));
  }
  void WebContentsDestroyed() override {
    controller_ = nullptr;
    Hide();
  }
  void Update() {
    NSView* view = presenter_.videoView;
    const gfx::Size size(NSWidth(view.bounds), NSHeight(view.bounds));
    const display::Display display =
        display::Screen::Get()->GetDisplayNearestWindow(
            gfx::NativeWindow(presenter_.panel));
    const float scale = display.device_scale_factor();
    compositor_->UpdateSurface(
        gfx::ToRoundedSize(gfx::ConvertSizeToPixels(size, scale)), scale,
        display.GetColorSpaces(), display.id(), display.display_frequency());
    surface_layer_->SetBounds(gfx::Rect(size));
    if (surface_id_.is_valid()) {
      surface_layer_->SetShowSurface(
          surface_id_, size, cc::DeadlinePolicy::UseDefaultDeadline(), true);
    }
    if (IsVisible()) {
      compositor_->Unsuspend();
    } else {
      compositor_->Suspend();
    }
    const bool resized = size != last_size_;
    last_size_ = size;
    auto weak = weak_factory_.GetWeakPtr();
    if (tracker_ && native_id_) {
      tracker_->UpdateNativePictureInPictureWindow(native_id_, GetBounds(),
                                                   IsVisible());
    }
    // Occlusion observers can synchronously delete the overlay or source.
    // The genuine controller notifies the current session/JS PiPWindow; this
    // call is terminal because its callback can also destroy the controller.
    if (weak && resized && weak->controller_) {
      weak->controller_->UpdateLayerBounds();
    }
  }
  void Action(PCVideoPiPAction action, double value) {
    if (!controller_ || !web_contents()) {
      return;
    }
    // Every call below is terminal for this frame: actual engine callbacks can
    // reset controller.window_ and synchronously delete this implementation.
    using Behavior = PictureInPictureWindowManager::UiBehavior;
    auto* manager = PictureInPictureWindowManager::GetInstance();
    if (action != PCVideoPiPSystemClose && action != PCVideoPiPEndScrubbing &&
        (!IsVisible() || manager->GetWebContents() != web_contents())) {
      return;
    }
    switch (action) {
      case PCVideoPiPClose:
        manager->ExitPictureInPictureViaWindowUi(
            Behavior::kCloseWindowAndPauseVideo);
        return;
      case PCVideoPiPReturn:
        PiPInputDiagnostics::WillReturn(web_contents());
        manager->ExitPictureInPictureViaWindowUi(
            Behavior::kCloseWindowAndFocusOpener);
        return;
      case PCVideoPiPMinimize:
        manager->ExitPictureInPictureViaWindowUi(Behavior::kCloseWindowOnly);
        return;
      case PCVideoPiPSystemClose:
        controller_->OnWindowDestroyed(true);
        return;
      case PCVideoPiPPlayPause:
        controller_->TogglePlayPause();
        return;
      case PCVideoPiPSkipAd:
        controller_->SkipAd();
        return;
      case PCVideoPiPNextTrack:
        controller_->NextTrack();
        return;
      case PCVideoPiPPreviousTrack:
        controller_->PreviousTrack();
        return;
      case PCVideoPiPMicrophone:
        controller_->ToggleMicrophone();
        return;
      case PCVideoPiPCamera:
        controller_->ToggleCamera();
        return;
      case PCVideoPiPHangUp:
        controller_->HangUp();
        return;
      case PCVideoPiPNextSlide:
        controller_->NextSlide();
        return;
      case PCVideoPiPPreviousSlide:
        controller_->PreviousSlide();
        return;
      case PCVideoPiPMute:
        controller_->RequestMute(!muted_);
        return;
      case PCVideoPiPBeginScrubbing:
        controller_->SetScrubbing(true);
        return;
      case PCVideoPiPEndScrubbing:
        controller_->SetScrubbing(false);
        return;
      case PCVideoPiPSeek:
        controller_->SeekTo(base::Seconds(value));
        return;
    }
  }
  raw_ptr<content::VideoPictureInPictureWindowController> controller_;
  id<PCNativeVideoPiPWindow> __strong presenter_;
  id<PCNativeBrowserApplicationClient> __strong application_;
  std::unique_ptr<ui::RecyclableCompositorMac> compositor_;
  std::unique_ptr<ui::LayerSurface> surface_layer_;
  std::unique_ptr<ui::DisplayCALayerTree> tree_;
  viz::SurfaceId surface_id_;
  gfx::Size last_size_;
  raw_ptr<PictureInPictureOcclusionTracker> tracker_ = nullptr;
  uint64_t native_id_ = 0;
  uint64_t image_generation_ = 0;
  bool muted_ = false;
  base::WeakPtrFactory<NativeVideoOverlayWindow> weak_factory_{this};
};
}  // namespace
bool UsesNativeVideoPictureInPicture(content::WebContents* contents) {
  auto* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  return browser && browser->cef_delegate() &&
         browser->cef_delegate()->IsNativeWindow();
}
std::unique_ptr<content::VideoOverlayWindow> CreateNativeVideoOverlayWindow(
    content::VideoPictureInPictureWindowController* controller) {
  CHECK(controller);
  return std::make_unique<NativeVideoOverlayWindow>(controller);
}
}  // namespace parc
