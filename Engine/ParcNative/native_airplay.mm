// Copyright 2026 Parc contributors.
#include "native_airplay.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#include <dlfcn.h>

#include <algorithm>
#include <cmath>
#include <map>
#include <optional>
#include <string>
#include <utility>

#include "base/check.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "content/public/browser/media_player_id.h"
#include "content/public/browser/parc_playback_target.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/web_contents.h"
#import "native_appkit_bridge.h"

// AVKit SPI WebKit declares (AVKitSPI.h) for its Mac route picker
// (AVRoutePickerViewTargetPicker): the route list shown for an output
// context. AVOutputContext and AVOutputDevice (AVFoundation SPI) are read by
// key, each key checked first.
@interface AVRoutePickerView (ParcAirPlay)
- (void)showRoutePickingControlsForOutputContext:(id)outputContext
                                  relativeToRect:(NSRect)rect
                                          ofView:(NSView*)view;
- (void)setRouteListAlwaysHasDarkAppearance:(BOOL)dark;
@end

namespace parc {
class NativeAirPlay;
}

@interface PCAirPlayObserver : NSObject <AVRoutePickerViewDelegate>
- (instancetype)initWithOwner:(parc::NativeAirPlay*)owner;
@end

namespace parc {
namespace {

// AVOutputDeviceFeatureAudio and AVOutputDeviceFeatureVideo.
constexpr NSUInteger kDeviceFeatureAudio = 1 << 0;
constexpr NSUInteger kDeviceFeatureVideo = 1 << 1;

NSString* OutputDevicesDidChangeNotification() {
  static NSString* name = [] () -> NSString* {
    void* symbol =
        dlsym(RTLD_DEFAULT, "AVOutputContextOutputDevicesDidChangeNotification");
    return symbol ? *static_cast<NSString* __unsafe_unretained*>(symbol) : nil;
  }();
  return name;
}

id Read(id object, NSString* key) {
  return [object respondsToSelector:NSSelectorFromString(key)]
             ? [object valueForKey:key]
             : nil;
}

NSUInteger DeviceFeatures(id device) {
  return [Read(device, @"deviceFeatures") unsignedIntegerValue];
}

bool IsDark(NSView* view) {
  return [view.effectiveAppearance bestMatchFromAppearancesWithNames:@[
           NSAppearanceNameAqua, NSAppearanceNameDarkAqua
         ]] == NSAppearanceNameDarkAqua;
}

}  // namespace

class NativeAirPlay final : public content::ParcPlaybackTargetHandler {
 public:
  static NativeAirPlay& Get() {
    static base::NoDestructor<NativeAirPlay> instance;
    return *instance;
  }

  // content::ParcPlaybackTargetHandler:
  void OnPlaybackTargetStateChanged(
      content::WebContents* contents,
      const content::MediaPlayerId& player_id,
      const content::ParcPlaybackTargetState& state) override {
    Player& player = players_[player_id];
    const bool began_monitoring =
        state.requires_monitoring && !player.state.requires_monitoring;
    if (state.supports_target && !player.state.supports_target) {
      player.order = ++order_;
    }
    player.contents = contents->GetWeakPtr();
    player.was_wireless |= state.wireless;
    player.state = state;
    // A new load of the element playing to the route keeps it
    // (MediaElementSession::mediaEngineUpdated).
    if (state.plays_to_target && HasActiveRoute() &&
        !(active_client_ && Alive(*active_client_) &&
          players_[*active_client_].state.plays_to_target)) {
      active_client_ = player_id;
    }
    UpdateMonitoring();
    if (began_monitoring || player.told_available != available_) {
      player.told_available = available_;
      content::SetParcPlaybackTargetAvailability(contents, player_id, available_);
    }
    NativeMediaAirPlayChanged(contents);
  }

  void OnShowPlaybackTargetPicker(content::WebContents* contents,
                                  const content::MediaPlayerId& player_id,
                                  const gfx::Point& position) override {
    content::RenderWidgetHostView* rwhv =
        contents ? contents->GetRenderWidgetHostView() : nullptr;
    NSView* view = rwhv ? rwhv->GetNativeView().GetNativeNSView() : nil;
    // Only the page the user sees: its window key in the active app.
    // A list that can't open is dismissed at once.
    if (!view || !players_.contains(player_id) || !NSApp.active ||
        !view.window.keyWindow ||
        contents->GetVisibility() != content::Visibility::VISIBLE) {
      content::SetParcPlaybackTargetPickerDismissed(contents, player_id);
      return;
    }
    const CGFloat y =
        view.isFlipped ? position.y() : NSHeight(view.bounds) - position.y();
    if (!Show(player_id, view, NSMakeRect(position.x(), y, 1, 1), nil)) {
      content::SetParcPlaybackTargetPickerDismissed(contents, player_id);
    }
  }

  void OnPlaybackTargetPlayerGone(content::WebContents* contents,
                                  const content::MediaPlayerId& player_id) override {
    if (!players_.erase(player_id)) {
      return;
    }
    if (active_client_ == player_id) {
      active_client_.reset();
    }
    if (picker_client_ == player_id) {
      picker_client_.reset();
    }
    UpdateMonitoring();
    if (contents) {
      NativeMediaAirPlayChanged(contents);
    }
  }

  NativeAirPlayState StateFor(content::WebContents* contents) {
    NativeAirPlayState result;
    bool supported = false;
    bool connecting = false;
    for (const auto& [player_id, player] : players_) {
      if (player.contents.get() != contents) {
        continue;
      }
      if (player.state.wireless) {
        result.state = PCNativeAirPlayStateConnected;
        result.device_name = DeviceName();
        return result;
      }
      // Not after playback left the device by itself (it dropped or
      // refused the stream): that element plays here again.
      connecting |= active_client_ == player_id && player.state.supports_target &&
                    player.state.plays_to_target && !player.was_wireless;
      supported |= player.state.supports_target;
    }
    if (connecting) {
      result.state = PCNativeAirPlayStateConnecting;
      result.device_name = DeviceName();
    } else if (supported && available_) {
      result.state = PCNativeAirPlayStateAvailable;
    }
    return result;
  }

  bool ShowFor(content::WebContents* contents,
               NSView* view,
               NSRect rect,
               void (^dismissed)(void)) {
    // The element playing to the route, else the latest that can.
    std::optional<content::MediaPlayerId> chosen;
    uint64_t latest = 0;
    for (const auto& [player_id, player] : players_) {
      if (player.contents.get() != contents || !player.state.supports_target) {
        continue;
      }
      if (player.state.plays_to_target || player.state.wireless) {
        chosen = player_id;
        break;
      }
      if (player.order > latest) {
        latest = player.order;
        chosen = player_id;
      }
    }
    return chosen && view && Show(*chosen, view, rect, dismissed);
  }

  // From PCAirPlayObserver.
  void RoutesChanged() {
    // setRouteDetectionEnabled:NO posts a change that reads no routes; the
    // devices nearby haven't changed (WebKit ignores it the same way).
    if (ignore_next_routes_change_) {
      ignore_next_routes_change_ = false;
      return;
    }
    const bool available = detector_.multipleRoutesDetected;
    if (available == available_) {
      return;
    }
    available_ = available;
    for (auto& [player_id, player] : players_) {
      if (player.state.requires_monitoring && player.contents &&
          player.told_available != available_) {
        player.told_available = available_;
        content::SetParcPlaybackTargetAvailability(player.contents.get(), player_id,
                                                   available_);
      }
      if (player.contents) {
        NativeMediaAirPlayChanged(player.contents.get());
      }
    }
  }

  void DevicesChanged() { ConfigureClients(); }

  // devicePickerWasDismissed: the clients change only if the route did.
  void PickerDismissed() {
    if (void (^dismissed)(void) = dismissed_) {
      dismissed_ = nil;
      dismissed();
    }
    if (Route() != route_at_show_) {
      ConfigureClients();
      return;
    }
    // Closed without a change: the request lapses, after the moment the
    // choice's own device change may still take to arrive, and its element
    // hears the list was dismissed (playbackTargetPickerWasDismissed).
    const uint64_t presentation = presentation_;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                     if (presentation_ == presentation) {
                       TellPickerDismissed();
                     }
                   });
  }

 private:
  friend class base::NoDestructor<NativeAirPlay>;

  struct Player {
    base::WeakPtr<content::WebContents> contents;
    content::ParcPlaybackTargetState state;
    // When it last became able to play to a target, for the Mini Player.
    uint64_t order = 0;
    bool told_available = false;
    // It played to the device since it was last given the target, and the
    // device it was given.
    bool was_wireless = false;
    std::string given_device;
    // The Space tint of the window it was last seen in (SpaceTint()); a
    // background tab's page is in no window.
    uint32_t tint = 0;
  };

  NativeAirPlay() {
    observer_ = [[PCAirPlayObserver alloc] initWithOwner:this];
    content::SetParcPlaybackTargetHandler(this);
  }

  id Context() {
    if (!context_) {
      context_ = Read(NSClassFromString(@"AVOutputContext"),
                      @"iTunesAudioContext");
      if (context_ && OutputDevicesDidChangeNotification()) {
        [NSNotificationCenter.defaultCenter
            addObserver:observer_
               selector:@selector(devicesChanged:)
                   name:OutputDevicesDidChangeNotification()
                 object:context_];
      }
    }
    return context_;
  }

  // MediaPlaybackTargetCocoa::hasActiveRoute.
  bool HasActiveRoute() {
    id context = context_;
    if (!context) {
      return false;
    }
    const NSUInteger features = kDeviceFeatureAudio | kDeviceFeatureVideo;
    if ([Read(context, @"supportsMultipleOutputDevices") boolValue]) {
      for (id device in Read(context, @"outputDevices")) {
        if (DeviceFeatures(device) & features) {
          return true;
        }
      }
      return false;
    }
    if (id device = Read(context, @"outputDevice")) {
      return DeviceFeatures(device) & features;
    }
    return [Read(context, @"deviceName") length] > 0;
  }

  // MediaPlaybackTargetCocoa::deviceName: the devices' names joined by " + ".
  std::string DeviceName() {
    id context = context_;
    if (!context) {
      return std::string();
    }
    if ([Read(context, @"supportsMultipleOutputDevices") boolValue]) {
      NSMutableArray* names = [NSMutableArray array];
      for (id device in Read(context, @"outputDevices")) {
        if (NSString* name = Read(device, @"name")) {
          [names addObject:name];
        }
      }
      return base::SysNSStringToUTF8([names componentsJoinedByString:@" + "]);
    }
    NSString* name = Read(context, @"deviceName");
    return base::SysNSStringToUTF8(name ?: @"");
  }

  bool Show(const content::MediaPlayerId& player_id,
            NSView* view,
            NSRect rect,
            void (^dismissed)(void)) {
    id context = Context();
    if (!context || !view.window) {
      return false;
    }
    if (!picker_) {
      picker_ = [[AVRoutePickerView alloc] initWithFrame:NSZeroRect];
      picker_.delegate = observer_;
    }
    if (![picker_ respondsToSelector:@selector
                  (showRoutePickingControlsForOutputContext:relativeToRect:ofView:)]) {
      return false;
    }
    if (void (^previous)(void) = dismissed_) {
      dismissed_ = nil;
      previous();
    }
    if (picker_client_ != player_id) {
      TellPickerDismissed();
    }
    picker_client_ = player_id;
    if (const uint32_t tint = SpaceTint(view.window)) {
      players_[player_id].tint = tint;
    }
    ++presentation_;
    route_at_show_ = Route();
    dismissed_ = dismissed;
    if ([picker_ respondsToSelector:@selector(setRouteListAlwaysHasDarkAppearance:)]) {
      [picker_ setRouteListAlwaysHasDarkAppearance:IsDark(view)];
    }
    [picker_ showRoutePickingControlsForOutputContext:context
                                       relativeToRect:rect
                                               ofView:view];
    return true;
  }

  // Whether the context routes anywhere, and to what.
  std::pair<bool, std::string> Route() {
    return {HasActiveRoute(), DeviceName()};
  }

  // WebMediaSessionManager::configurePlaybackTargetClients: with a route, the
  // element that opened the list plays to it (its request is then spent),
  // else the one already playing; every other element holding the target,
  // and the one that opened the list, stops. Without a route none plays to
  // it.
  void ConfigureClients() {
    std::optional<content::MediaPlayerId> client;
    if (HasActiveRoute()) {
      if (picker_client_ && Alive(*picker_client_)) {
        client = picker_client_;
      } else if (active_client_ && Alive(*active_client_)) {
        client = active_client_;
      }
    }
    const std::optional<content::MediaPlayerId> picker_client = picker_client_;
    picker_client_.reset();
    const std::string context_id =
        client ? base::SysNSStringToUTF8(Read(context_, @"contextID") ?: @"")
               : std::string();
    for (auto& [player_id, player] : players_) {
      if (player.contents && player_id != client &&
          (player.state.plays_to_target || player_id == active_client_ ||
           player_id == picker_client)) {
        content::SetParcPlaybackTarget(player.contents.get(), player_id,
                                       std::string(), std::string(), false, 0);
        NativeMediaAirPlayChanged(player.contents.get());
      }
    }
    const std::optional<content::MediaPlayerId> previous_client = active_client_;
    active_client_ = client;
    if (client) {
      Player& player = players_[*client];
      // A new pick (another element, or another device) connects anew; the
      // same route given again keeps what the element did with it.
      const std::string device = DeviceName();
      if (client != previous_client || device != player.given_device) {
        player.was_wireless = false;
        player.given_device = device;
      }
      if (const uint32_t tint = SpaceTint(player.contents.get())) {
        player.tint = tint;
      }
      content::SetParcPlaybackTarget(player.contents.get(), *client,
                                     context_id, DeviceName(), true,
                                     player.tint);
      NativeMediaAirPlayChanged(player.contents.get());
    }
  }

  // The tint a window gives AirPlay (the Mini Player's), as ARGB in sRGB; 0
  // when it has none.
  static uint32_t SpaceTint(NSWindow* window) {
    id delegate = window.delegate;
    if (![delegate respondsToSelector:@selector(airPlayThemeTintColor)]) {
      return 0;
    }
    NSColor* color =
        [[(id<PCNativeAirPlayThemeSource>)delegate airPlayThemeTintColor]
            colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!color) {
      return 0;
    }
    auto channel = [](CGFloat value) {
      return static_cast<uint32_t>(
          std::lround(std::clamp(value, 0.0, 1.0) * 255));
    };
    return channel(color.alphaComponent) << 24 |
           channel(color.redComponent) << 16 |
           channel(color.greenComponent) << 8 | channel(color.blueComponent);
  }
  static uint32_t SpaceTint(content::WebContents* contents) {
    content::RenderWidgetHostView* rwhv =
        contents ? contents->GetRenderWidgetHostView() : nullptr;
    NSView* view = rwhv ? rwhv->GetNativeView().GetNativeNSView() : nil;
    return SpaceTint(view.window);
  }

  void TellPickerDismissed() {
    if (picker_client_ && Alive(*picker_client_)) {
      content::SetParcPlaybackTargetPickerDismissed(
          players_[*picker_client_].contents.get(), *picker_client_);
    }
    picker_client_.reset();
  }

  bool Alive(const content::MediaPlayerId& player_id) {
    auto it = players_.find(player_id);
    return it != players_.end() && it->second.contents;
  }

  // AVRouteDetector watches while an element needs it (WebKit's
  // startingMonitoringPlaybackTargets and stopMonitoringPlaybackTargets).
  void UpdateMonitoring() {
    bool monitoring = false;
    for (const auto& [player_id, player] : players_) {
      monitoring |= player.contents && player.state.requires_monitoring;
    }
    if (monitoring == monitoring_) {
      return;
    }
    monitoring_ = monitoring;
    if (!detector_) {
      detector_ = [[AVRouteDetector alloc] init];
      [NSNotificationCenter.defaultCenter
          addObserver:observer_
             selector:@selector(routesChanged:)
                 name:AVRouteDetectorMultipleRoutesDetectedDidChangeNotification
               object:detector_];
    }
    // Enabling posts a change, which reads the routes once they're known.
    ignore_next_routes_change_ = !monitoring;
    detector_.routeDetectionEnabled = monitoring;
  }

  PCAirPlayObserver* __strong observer_ = nil;
  AVRouteDetector* __strong detector_ = nil;
  AVRoutePickerView* __strong picker_ = nil;
  id __strong context_ = nil;
  void (^__strong dismissed_)(void) = nil;
  std::map<content::MediaPlayerId, Player> players_;
  std::optional<content::MediaPlayerId> picker_client_;
  std::optional<content::MediaPlayerId> active_client_;
  // The route when the list opened (WebKit's m_hadActiveRoute).
  std::pair<bool, std::string> route_at_show_;
  uint64_t order_ = 0;
  // Each Show, so a lapsed request doesn't clear a later one.
  uint64_t presentation_ = 0;
  bool monitoring_ = false;
  bool available_ = false;
  bool ignore_next_routes_change_ = false;
};

void InstallNativeAirPlay() {
  CHECK(NSThread.isMainThread);
  NativeAirPlay::Get();
}

NativeAirPlayState NativeAirPlayStateForContents(
    content::WebContents* contents) {
  return NativeAirPlay::Get().StateFor(contents);
}

bool ShowNativeAirPlayPicker(content::WebContents* contents,
                             NSView* view,
                             NSRect rect,
                             void (^dismissed)(void)) {
  CHECK(NSThread.isMainThread);
  return NativeAirPlay::Get().ShowFor(contents, view, rect, dismissed);
}

}  // namespace parc

@implementation PCAirPlayObserver {
  parc::NativeAirPlay* _owner;
}

- (instancetype)initWithOwner:(parc::NativeAirPlay*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

// AVFoundation may post these off the main thread.
- (void)routesChanged:(NSNotification*)notification {
  dispatch_async(dispatch_get_main_queue(), ^{
    self->_owner->RoutesChanged();
  });
}

- (void)devicesChanged:(NSNotification*)notification {
  dispatch_async(dispatch_get_main_queue(), ^{
    self->_owner->DevicesChanged();
  });
}

// At once on the main thread, so a list shown again in the meantime can't
// take this one's dismissal.
- (void)routePickerViewDidEndPresentingRoutes:(AVRoutePickerView*)routePickerView {
  if (NSThread.isMainThread) {
    _owner->PickerDismissed();
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    self->_owner->PickerDismissed();
  });
}

@end
