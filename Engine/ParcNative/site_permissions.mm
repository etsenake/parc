#include "site_permissions.h"

#import <UserNotifications/UserNotifications.h>

#include <algorithm>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "base/barrier_callback.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/mac/mac_util.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/permissions/system/system_permission_settings.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/custom_handlers/register_protocol_handler_permission_request.h"
#include "components/permissions/embedded_permission_prompt_flow_model.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_util.h"
#include "components/permissions/request_type.h"
#include "components/strings/grit/components_strings.h"
#include "components/tabs/public/tab_interface.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#import "dialog_style.h"
#include "native_auxiliary_page.h"
#import "site_permission_presenter.h"
#include "ui/base/base_window.h"
#include "ui/base/l10n/l10n_util.h"
#include "url/origin.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
using Delegate = permissions::PermissionPrompt::Delegate;
using Variant = permissions::EmbeddedPermissionPromptFlowModel::Variant;
using Result = base::OnceCallback<void(PCSitePermissionChoice, PromptOptions)>;
bool IsSiteConsentStage(Delegate& delegate) {
  auto* flow = delegate.GetEmbeddedPromptFlowModel();
  return !flow ||
         flow->prompt_variant() ==
             permissions::EmbeddedPermissionPromptFlowModel::Variant::kAsk;
}
//
// siteTitle, with "this website" as its fallback).
NSString* SiteLabel(const GURL& origin) {
  NSString* site = base::SysUTF16ToNSString(
      url_formatter::FormatOriginForSecurityDisplay(
          url::Origin::Create(origin),
          url_formatter::SchemeDisplay::OMIT_HTTP_AND_HTTPS));
  return site.length ? site : @"this website";
}

//
//
//
// display name and gear symbol.
struct PArcPermissionType {
  NSString* name;
  NSString* symbol;
  CGFloat size;
  bool bold;
  CGFloat offset;
};
PArcPermissionType PArcType(permissions::RequestType type) {
  using T = permissions::RequestType;
  switch (type) {
    case T::kArSession:
      return {@"AR", @"bubbles.and.sparkles.fill", 14, false, 0};
    case T::kVrSession:
      return {@"VR", @"bubbles.and.sparkles.fill", 14, false, 0};
    case T::kCameraPanTiltZoom:
      return {@"camera pan and tilt", @"camera.fill", 14, false, -1};
    case T::kCameraStream:
      return {@"camera", @"camera.fill", 14, false, -1};
    case T::kCapturedSurfaceControl:
      return {@"captured surface control", @"gearshape.fill", 14, false, 0};
    case T::kClipboard:
      return {@"clipboard", @"clipboard.fill", 14, false, -0.5};
    case T::kTopLevelStorageAccess:
      return {@"topLevelStorageAccess", @"externaldrive.fill", 15, false, -1};
    case T::kDiskQuota:
      return {@"quota", @"externaldrive.fill", 14, false, 0};
    case T::kFileSystemAccess:
      return {@"file system access", @"gearshape.fill", 14, false, 0};
    case T::kGeolocation:
      return {@"location", @"location.fill", 14, false, 0};
    case T::kHandTracking:
      return {@"hand tracking", @"gearshape.fill", 14, false, 0};
    case T::kIdentityProvider:
      return {@"identity provider", @"gearshape.fill", 14, false, 0};
    case T::kIdleDetection:
      return {@"idle detection", @"zzz", 14, true, 0};
    case T::kLocalFonts:
      return {@"font", @"textformat.alt", 14, true, 0};
    case T::kLocalNetwork:
    case T::kLoopbackNetwork:
      return {@"local network", @"gearshape.fill", 14, false, 0};
    case T::kMicStream:
      return {@"microphone", @"mic.fill", 14, false, 0};
    case T::kMidiSysex:
      return {@"MIDI devices", @"pianokeys", 14, false, 0};
    case T::kMultipleDownloads:
      return {@"download", @"arrow.down", 15, true, 0};
    case T::kNotifications:
      return {@"notifications", @"bell.fill", 14, false, -0.5};
    case T::kKeyboardLock:
      return {@"keyboard lock", @"gearshape.fill", 14, false, 0};
    case T::kPointerLock:
      return {@"pointer lock", @"gearshape.fill", 14, false, 0};
    case T::kRegisterProtocolHandler:
      return {@"protocol handler", @"gearshape.fill", 14, false, 0};
    case T::kStorageAccess:
      return {@"storage", @"externaldrive.fill", 15, false, -1};
    case T::kWebAppInstallation:
      return {@"web app installation", @"gearshape.fill", 14, false, 0};
    case T::kWindowManagement:
      return {@"window management", @"macwindow.on.rectangle", 14, false, 0};
    default:
      return {@"unknown", @"gearshape.fill", 14, false, 0};
  }
}

//
//
// camera with microphone reads "camera, microphone"; any other group is
//
// (WebContentPermissionProtocolHandlerType); only mailto has its own title.
NSString* PArcTitle(NSString* site,
                   const std::vector<permissions::RequestType>& types,
                   bool mailto,
                   PArcPermissionType* icon) {
  using T = permissions::RequestType;
  if (types.size() == 1) {
    *
    if (types[0] == T::kRegisterProtocolHandler && mailto) {
      return [NSString stringWithFormat:@"Make %@ your default mail app?", site];
    }
    switch (types[0]) {
      case T::kNotifications:
        return [NSString
            stringWithFormat:@"Allow %@ to send you notifications?", site];
      case T::kDiskQuota:
        return [NSString
            stringWithFormat:@"Allow %@ to store files on your device?", site];
      case T::kMultipleDownloads:
        return [NSString
            stringWithFormat:@"Allow %@ to download multiple files?", site];
      case T::kIdleDetection:
        return [NSString
            stringWithFormat:
                @"Allow %@ to know when you’re actively using this device?",
                site];
      default:
        return [NSString stringWithFormat:@"Allow %@ to access your %@?", site,
                                          icon->name];
    }
  }
  const bool camera_and_mic =
      types.size() == 2 &&
      std::find(types.begin(), types.end(), T::kCameraStream) != types.end() &&
      std::find(types.begin(), types.end(), T::kMicStream) != types.end();
  *
                         : PArcPermissionType{@"unknown", @"gearshape.fill", 14,
                                             false, 0};
  return [NSString stringWithFormat:@"Allow %@ to access your %@?", site,
                                    camera_and_mic ? @"camera, microphone"
                                                   : @"unknown"];
}

//
//
// inline Swift string, drawn as Parc's dialog. It opens Parc's own
// Notifications pane.
void ShowSystemNotificationsDeniedSheet(NSWindow* window) {
  if (!window || !window.visible || window.attachedSheet ||
      PCNativeWindowHasSecurityReservation(window)) {
    return;
  }
  PCDialogPrompt* alert = [[PCDialogPrompt alloc]
      initWithTitle:@"Parc Needs Notifications Permission"
            message:@"You need to open System Preferences to give Parc "
                    @"permission to show you Notifications."];
  [alert addButtonWithTitle:@"Open System Preferences"
                       role:PCDialogPromptPrimary
                   response:NSAlertFirstButtonReturn];
  [alert addButtonWithTitle:@"Never Mind"
                       role:PCDialogPromptCancel
                   response:NSAlertSecondButtonReturn];
  NSString* bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
  [alert beginSheetModalForWindow:window
                completionHandler:^(NSModalResponse response) {
                  if (response == NSAlertFirstButtonReturn) {
                    base::mac::OpenSystemSettingsPane(
                        base::mac::SystemSettingsPane::kNotifications,
                        base::SysNSStringToUTF8(bundle));
                  }
                }];
}

//
// sure macOS lets Parc show notifications at all. Chromium checks this only
// for installed web apps, so a denied browser drops every banner silently.
void EnsureSystemNotificationsAllowed(NSWindow* window) {
  // Genuine-controller tests share this adapter; only a real app bundle has a
  // notification center.
  if (![NSBundle.mainBundle.bundlePath hasSuffix:@".app"]) {
    return;
  }
  // Built on main so the weak window is only ever touched there.
  __weak NSWindow* weak = window;
  void (^denied)(void) = ^{
    ShowSystemNotificationsDeniedSheet(weak);
  };
  UNUserNotificationCenter* center =
      UNUserNotificationCenter.currentNotificationCenter;
  void (^decide)(UNAuthorizationStatus) = ^(UNAuthorizationStatus status) {
    if (status == UNAuthorizationStatusDenied) {
      denied();
    } else if (status == UNAuthorizationStatusNotDetermined) {
      [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert |
                                              UNAuthorizationOptionSound |
                                              UNAuthorizationOptionBadge
                            completionHandler:^(BOOL granted, NSError*) {
                              if (!granted) {
                                dispatch_async(dispatch_get_main_queue(), denied);
                              }
                            }];
    }
  };
  [center getNotificationSettingsWithCompletionHandler:^(
              UNNotificationSettings* settings) {
    const UNAuthorizationStatus status = settings.authorizationStatus;
    dispatch_async(dispatch_get_main_queue(), ^{
      decide(status);
    });
  }];
}

class Request final : public content::WebContentsObserver,
                      public std::enable_shared_from_this<Request> {
 public:
  Request(content::WebContents& contents,
          Delegate& delegate,
          const permissions::PermissionPrompt* prompt,
          Result result)
      : content::WebContentsObserver(&contents),
        delegate_(delegate.GetWeakPtr()),
        prompt_(prompt),
        result_(std::move(result)) {
    auxiliary_route_ = !tabs::TabInterface::MaybeGetFromContents(&contents) &&
                       HasNativeAuxiliaryRoute(contents);
    if (auxiliary_route_) {
      auxiliary_ = GetNativeAuxiliaryPage(contents);
    }
  }
  ~Request() override {
    [presenter_ invalidate];
    [reservation_ invalidate];
    if (window_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:window_observer_];
    }
    for (id observer in system_observers_) {
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
  }
  void Start() {
    auto keep = shared_from_this();
    if (closed_) {
      return;
    }
    auto* contents = web_contents();
    if (!contents || !IsCurrent() || delegate_->Requests().empty() ||
        delegate_->ShouldCurrentRequestUseQuietUI()) {
      Cancel();
      return;
    }
    auto* flow = delegate_->GetEmbeddedPromptFlowModel();
    embedded_ = flow != nullptr;
    variant_ = flow ? flow->prompt_variant() : Variant::kAsk;
    if (variant_ == Variant::kUninitialized) {
      Cancel();
      return;
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    if (auxiliary_route_ && (!auxiliary_ || !auxiliary_->IsValid())) {
      Cancel();
      return;
    }
    auto* browser = tab          ? tab->GetBrowserWindowInterface()
                    : auxiliary_ ? auxiliary_->browser()
                                 : nullptr;
    origin_ = delegate_->GetRequestingOrigin();
    embedding_ = delegate_->GetEmbeddingOrigin();
    if (!browser || browser->IsDeleteScheduled() || !browser->GetWindow() ||
        url::Origin::Create(origin_).opaque()) {
      Cancel();
      return;
    }
    if (auxiliary_) {
      std::weak_ptr<Request> weak = keep;
      auxiliary_cancel_ = auxiliary_->OnInvalidated(base::BindRepeating(
          [](std::weak_ptr<Request> weak) {
            if (auto self = weak.lock()) {
              self->Cancel();
            }
          },
          weak));
    }
    browser_ = browser->GetWeakPtr();
    profile_ = browser->GetProfile()->GetWeakPtr();
    window_ = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    page_ = contents->GetNativeView().GetNativeNSView();
    document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    std::vector<permissions::RequestType> types;
    bool mailto = false;
    //
    // ordinary prompt always reads Allow.
    NSString* allow = @"Allow";
    std::u16string permission_name;
    offers_one_time_ = true;
    for (const auto& request : delegate_->Requests()) {
      auto* frame =
          content::RenderFrameHost::FromID(request->get_requesting_frame_id());
      // Permission delegation can canonicalize the origin. Trust the actual
      // manager origin, while binding each actual requesting frame document.
      if (!frame ||
          content::WebContents::FromRenderFrameHost(frame) != contents ||
          request->requesting_origin() != origin_) {
        Cancel();
        return;
      }
      auto type = permissions::RequestTypeToContentSettingsType(
          request->request_type());
      offers_one_time_ &=
          type &&
          permissions::PermissionUtil::DoesSupportTemporaryGrants(*type);
      const auto actual_type = request->GetContentSettingsType();
      if (std::find(system_types_.begin(), system_types_.end(), actual_type) ==
          system_types_.end()) {
        system_types_.push_back(actual_type);
      }
      if (variant_ != Variant::kAsk) {
        if (!permission_name.empty()) permission_name += u", ";
        // The embedded flow supports camera, microphone and geolocation.
        // Ordinary requests must never call this narrower name accessor.
        permission_name += request->GetPermissionNameTextFragment();
      }
      typed_geolocation_ |= request->GetContentSettingsType() ==
                            ContentSettingsType::GEOLOCATION_WITH_OPTIONS;
      auto text = request->GetMessageTextFragment();
      if (text.empty()) {
        Cancel();
        return;
      }
      // Opaque identity comparisons only; never dereferenced after this loop.
      // The owning prompt identity is also checked before every decision.
      requests_.push_back(request.get());
      frames_.push_back(frame->GetWeakDocumentPtr());
      types.push_back(request->request_type());
      if (request->request_type() ==
          permissions::RequestType::kRegisterProtocolHandler) {
        // Only Chromium's protocol-handler request carries this type.
        mailto = static_cast<custom_handlers::
                                 RegisterProtocolHandlerPermissionRequest*>(
                     request.get())
                     ->handler()
                     .protocol() == "mailto";
      }
      if (delegate_->Requests().size() == 1) {
        if (auto label = request->GetAllowAlwaysText();
            label && !label->empty()) {
          allow = base::SysUTF16ToNSString(*label);
        }
      }
    }
    if (system_types_.size() == 2 &&
        std::find(system_types_.begin(), system_types_.end(),
                  ContentSettingsType::MEDIASTREAM_CAMERA) != system_types_.end() &&
        std::find(system_types_.begin(), system_types_.end(),
                  ContentSettingsType::MEDIASTREAM_MIC) != system_types_.end()) {
      permission_name = l10n_util::GetStringUTF16(
          IDS_CAMERA_AND_MICROPHONE_PERMISSION_NAME_FRAGMENT);
    }
    PCSiteLocationMode location = PCSiteLocationNone;
    bool precise = false;
    if (typed_geolocation_ && (variant_ == Variant::kAsk ||
                              variant_ == Variant::kPreviouslyDenied)) {
      // Actual current Chromium policy selects the allowed accuracy controls.
      // Do not translate the old generic CEF result into a fabricated option.
      if (delegate_->Requests().size() != 1) {
        Cancel();
        return;
      }
      auto type = delegate_->GetGeolocationPromptType();
      if (!type) {
        Cancel();
        return;
      }
      switch (*type) {
        case permissions::GeolocationPromptType::kApproximateOrPrecise:
          location = PCSiteLocationApproximateOrPrecise;
          precise = delegate_->GetInitialGeolocationAccuracySelection() ==
                    GeolocationAccuracy::kPrecise;
          break;
        case permissions::GeolocationPromptType::kApproximateOnly:
          location = PCSiteLocationApproximate;
          break;
        case permissions::GeolocationPromptType::kUpgradeToPrecise:
          location = PCSiteLocationUpgradeToPrecise;
          precise = true;
          break;
      }
    }
    started_ = true;
    if (!Valid() || PCNativeWindowHasSecurityReservation(window_)) {
      Cancel();
      return;
    }
    std::weak_ptr<Request> weak = keep;
    window_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock()) {
                    self->Cancel();
                  }
                }];
    PCNativeWindowSecurityReservation* reservation =
        [PCNativeWindowSecurityReservation acquireForWindow:window_];
    if (closed_ || !reservation.active) {
      [reservation invalidate];
      Cancel();
      return;
    }
    reservation_ = reservation;
    if (!Valid()) {
      Cancel();
      return;
    }
    PArcPermissionType icon;
    NSString* title = PArcTitle(SiteLabel(origin_), types, mailto, &icon);
    presenter_ = [[PCSitePermissionPresenter alloc] initWithPage:page_
        window:window_
        title:title
        locationMode:location
        initialPrecise:precise
        validate:^BOOL {
          auto self = weak.lock();
          return self && self->Valid();
        }
        presented:^{
          if (auto self = weak.lock(); self && self->Valid()) {
            self->delegate_->SetPromptShown();
            if (self->Valid() && self->variant_ == Variant::kOsPrompt) {
              base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
                  FROM_HERE, base::BindOnce([](std::weak_ptr<Request> weak) {
                    if (auto self = weak.lock()) self->RequestSystemPermissions();
                  }, weak));
            }
          }
        }
        result:^(PCSitePermissionChoice choice, BOOL selected_precise) {
          if (auto self = weak.lock()) {
            self->Complete(choice, selected_precise);
          }
        }];
    [presenter_ configureSymbol:icon.symbol
                      pointSize:icon.size
                           bold:icon.bold
                        offsetY:icon.offset];
    if (variant_ != Variant::kAsk) {
      ConfigureFollowUp(permission_name, allow, weak);
    }
    if (variant_ == Variant::kOsSystemSettings) {
      // AppKit equivalent of the engine's host-widget activation observer.
      // A settings handoff may occlude this page; it must not decide its grant.
      system_observers_ = [NSMutableArray array];
      for (NSNotificationName name in @[ NSApplicationDidBecomeActiveNotification,
                                         NSWindowDidBecomeKeyNotification ]) {
        id observer = [NSNotificationCenter.defaultCenter
            addObserverForName:name object:nil queue:nil
            usingBlock:^(NSNotification* notification) {
              if (auto self = weak.lock()) {
                if ([notification.name isEqualToString:NSApplicationDidBecomeActiveNotification] ||
                    notification.object == self->window_ ||
                    notification.object == self->presenter_.sheet) {
                  self->RefreshSystemPermissions(false);
                }
              }
            }];
        [system_observers_ addObject:observer];
      }
    }
    [presenter_ start];
  }
  void Revalidate() {
    if (started_ && !Valid()) {
      Cancel();
    }
  }
  void Cancel(bool silently = false) {
    auto keep = shared_from_this();
    interrupted_ = true;
    if (silently) {
      result_.Reset();
    }
    if (closed_) {
      return;
    }
    closed_ = true;
    [presenter_ invalidate];
    presenter_ = nil;
    [reservation_ invalidate];
    reservation_ = nil;
    auto result = std::move(result_);
    // The manager may still be installing its factory result. Never resolve
    // on that creation stack, nor decide a later prompt after replacement.
    if (result) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE,
          base::BindOnce(std::move(result), PCSitePermissionInterrupted,
                         PromptOptions(std::monostate{})));
    }
  }

 private:
  void ConfigureFollowUp(const std::u16string& permission_name,
                         NSString* allow,
                         std::weak_ptr<Request> weak) {
    NSMutableArray<NSString*>* labels = [NSMutableArray array];
    NSMutableArray<NSNumber*>* choices = [NSMutableArray array];
    auto add = [&](int message, PCSitePermissionChoice choice) {
      [labels addObject:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(message))];
      [choices addObject:@(choice)];
    };
    std::u16string title;
    switch (variant_) {
      case Variant::kAdministratorGranted:
      case Variant::kAdministratorDenied:
        title = l10n_util::GetStringFUTF16(
            variant_ == Variant::kAdministratorGranted
                ? IDS_EMBEDDED_PROMPT_ADMIN_ALLOWED
                : IDS_EMBEDDED_PROMPT_ADMIN_BLOCKED, permission_name);
        add(IDS_EMBEDDED_PROMPT_OK_LABEL, PCSitePermissionDismiss);
        break;
      case Variant::kPreviouslyGranted:
        title = l10n_util::GetStringFUTF16(
            IDS_EMBEDDED_PROMPT_PREVIOUSLY_ALLOWED, permission_name);
        add(IDS_EMBEDDED_PROMPT_CONTINUE_ALLOWING, PCSitePermissionDismiss);
        add(IDS_EMBEDDED_PROMPT_STOP_ALLOWING, PCSitePermissionBlock);
        break;
      case Variant::kPreviouslyDenied:
        title = l10n_util::GetStringFUTF16(
            IDS_EMBEDDED_PROMPT_PREVIOUSLY_NOT_ALLOWED, permission_name);
        add(IDS_EMBEDDED_PROMPT_CONTINUE_NOT_ALLOWING, PCSitePermissionDismiss);
        if (offers_one_time_) {
          add(IDS_PERMISSION_ALLOW_THIS_TIME, PCSitePermissionAllowOnce);
        } else {
          // An allowed non-temporary request uses its own real grant label.
          [labels addObject:allow];
          [choices addObject:@(PCSitePermissionAllow)];
        }
        break;
      case Variant::kOsSystemSettings:
        title = l10n_util::GetStringFUTF16(
            IDS_PERMISSION_OFF_FOR_CHROME, permission_name, u"Parc");
        [labels addObject:@"Not Now"];
        [choices addObject:@(PCSitePermissionDismiss)];
        [labels addObject:base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
            IDS_EMBEDDED_PROMPT_OPEN_SYSTEM_SETTINGS,
            l10n_util::GetStringUTF16(IDS_MACOS_NAME_FRAGMENT)))];
        [choices addObject:@(PCSitePermissionOpenSystemSettings)];
        break;
      case Variant::kOsPrompt:
        title = l10n_util::GetStringFUTF16(
            IDS_PERMISSION_CHROME_NEEDS_PERMISSION, u"Parc", permission_name);
        [labels addObjectsFromArray:@[ @"Cancel", @"Continue" ]];
        [choices addObjectsFromArray:@[ @(PCSitePermissionDismiss),
                                        @(PCSitePermissionRequestSystem) ]];
        break;
      case Variant::kAsk:
      case Variant::kUninitialized:
        return;
    }
    [presenter_ configureFollowUpWithTitle:base::SysUTF16ToNSString(title)
        labels:labels choices:choices systemAction:^(PCSitePermissionChoice choice) {
          if (auto self = weak.lock()) {
            if (choice == PCSitePermissionOpenSystemSettings)
              self->RefreshSystemPermissions(true);
            else if (choice == PCSitePermissionRequestSystem)
              self->RequestSystemPermissions();
          }
        }];
  }
  bool IsSystemStage() const {
    return variant_ == Variant::kOsPrompt || variant_ == Variant::kOsSystemSettings;
  }
  bool IsSameStage() const {
    auto* flow = delegate_->GetEmbeddedPromptFlowModel();
    return embedded_ ? flow && flow->prompt_variant() == variant_ : !flow;
  }
  bool HasSystemSurface() const {
    // Native completion is deferred. Once a user closes the prompt, a late OS
    // response must not win that gap and advance instead of their dismissal.
    return Valid() && presenter_.shown;
  }
  void RequestSystemPermissions() {
    auto keep = shared_from_this();
    if (!HasSystemSurface() || variant_ != Variant::kOsPrompt) return;
    if (pending_system_requests_) return;
    std::vector<ContentSettingsType> pending;
    for (auto type : system_types_) {
      if (system_permission_settings::CanPrompt(type)) pending.push_back(type);
    }
    if (pending.empty()) {
      AdvanceFlow();
      return;
    }
    pending_system_requests_ = pending.size();
    [presenter_ setSystemRequestPending:YES];
    std::weak_ptr<Request> weak = keep;
    for (auto type : pending) {
      if (!Valid()) { Cancel(); return; }
      system_permission_settings::Request(type, base::BindOnce(
          [](std::weak_ptr<Request> weak) {
            auto self = weak.lock();
            if (!self || !self->HasSystemSurface() || !self->pending_system_requests_) return;
            if (--self->pending_system_requests_) return;
            for (auto type : self->system_types_) {
              if (system_permission_settings::CanPrompt(type)) {
                // An undetermined response is not an allow or a deny. Keep
                // the current sheet and let the user retry or dismiss it.
                [self->presenter_ setSystemRequestPending:NO];
                return;
              }
            }
            self->AdvanceFlow();
          }, weak));
    }
  }
  void RefreshSystemPermissions(bool open_settings) {
    auto keep = shared_from_this();
    if (!HasSystemSurface() || variant_ != Variant::kOsSystemSettings) return;
    open_system_settings_ |= open_settings;
    if (refreshing_system_) return;
    refreshing_system_ = true;
    std::weak_ptr<Request> weak = keep;
    // Preserve type identity: asynchronous cache refreshes can finish in any
    // order. The resulting vector's order is deliberately not used as an ID.
    using State = std::pair<ContentSettingsType, bool>;
    auto barrier = base::BarrierCallback<State>(system_types_.size(),
        base::BindOnce([](std::weak_ptr<Request> weak, std::vector<State> states) {
          auto self = weak.lock();
          if (!self || !self->HasSystemSurface()) return;
          self->refreshing_system_ = false;
          const bool open = std::exchange(self->open_system_settings_, false);
          auto denied = std::find_if(states.begin(), states.end(),
                                    [](const State& state) { return state.second; });
          if (denied == states.end()) {
            // Avoid replacing a sheet within AppKit's activation stack.
            base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
                FROM_HERE, base::BindOnce([](std::weak_ptr<Request> weak) {
                  if (auto self = weak.lock(); self && self->Valid()) self->AdvanceFlow();
                }, weak));
          } else if (open) {
            system_permission_settings::OpenSystemSettings(self->web_contents(),
                                                           denied->first);
          }
        }, weak));
    for (auto type : system_types_) {
      system_permission_settings::IsDeniedFresh(type, base::BindOnce(
          [](base::RepeatingCallback<void(State)> barrier,
             ContentSettingsType type, bool denied) {
            barrier.Run({type, denied});
          }, barrier, type));
    }
  }
  void AdvanceFlow() {
    auto keep = shared_from_this();
    if (!HasSystemSurface() || !IsSystemStage()) return;
    auto delegate = delegate_;
    // This is a model transition, not a user permission decision. Silence the
    // old native sheet before the manager replaces/finalizes its exact prompt.
    closed_ = true;
    result_.Reset();
    [presenter_ invalidate];
    presenter_ = nil;
    [reservation_ invalidate];
    reservation_ = nil;
    if (Valid(/*completing=*/true)) {
      delegate->AdvanceOrFinalizeEmbeddedPromptFlow();
    } else if (IsCurrent()) {
      // Release observers can move or close the page. Finalize that same
      // prompt as ignored; never leave its engine request suspended.
      delegate->Ignore(std::monostate{});
    }
  }
  bool IsCurrent() const {
    return delegate_ &&
           delegate_->GetAssociatedWebContents() == web_contents() &&
           delegate_->GetCurrentPrompt() == prompt_;
  }
  bool Valid(bool completing = false) const {
    if (interrupted_ || (closed_ && !completing) || !IsCurrent() ||
        !web_contents() || !IsSameStage() ||
        web_contents()->IsBeingDestroyed() || !browser_ ||
        browser_->IsDeleteScheduled() || !profile_ ||
        browser_->GetProfile() != profile_.get() ||
        web_contents()->GetBrowserContext() != profile_.get() || !window_ ||
        !window_.visible || window_.miniaturized || !page_ ||
        page_.window != window_ || page_.hiddenOrHasHiddenAncestor ||
        web_contents()->GetVisibility() == content::Visibility::HIDDEN ||
        document_.AsRenderFrameHostIfValid() !=
            web_contents()->GetPrimaryMainFrame() ||
        !browser_->GetWindow() ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_ ||
        (window_.attachedSheet && window_.attachedSheet != presenter_.sheet) ||
        (reservation_ ? !reservation_.isOnlyReservation
                      : PCNativeWindowHasSecurityReservation(window_))) {
      return false;
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(web_contents());
    const bool owner =
        auxiliary_
            ? auxiliary_->IsValid() && auxiliary_->browser() == browser_.get()
            : tab && tab->GetBrowserWindowInterface() == browser_.get();
    if (!owner || delegate_->Requests().size() != requests_.size() ||
        delegate_->GetRequestingOrigin() != origin_ ||
        delegate_->GetEmbeddingOrigin() != embedding_) {
      return false;
    }
    for (size_t i = 0; i < requests_.size(); ++i) {
      if (delegate_->Requests()[i].get() != requests_[i] ||
          !frames_[i].AsRenderFrameHostIfValid()) {
        return false;
      }
    }
    return true;
  }
  void Complete(PCSitePermissionChoice choice, bool precise) {
    auto keep = shared_from_this();
    if (closed_) {
      return;
    }
    bool valid = Valid();
    closed_ = true;
    presenter_ = nil;
    [reservation_ invalidate];
    reservation_ = nil;
    valid = valid && Valid(/*completing=*/true);
    // Only controls offered by this exact model stage may change settings.
    if (choice == PCSitePermissionAllowOnce) {
      valid &= offers_one_time_ && (variant_ == Variant::kAsk ||
                                    variant_ == Variant::kPreviouslyDenied);
    } else if (choice == PCSitePermissionAllow) {
      valid &= variant_ == Variant::kAsk ||
               (variant_ == Variant::kPreviouslyDenied && !offers_one_time_);
    } else if (choice == PCSitePermissionBlock) {
      valid &= variant_ == Variant::kAsk || variant_ == Variant::kPreviouslyGranted;
    } else if (choice == PCSitePermissionOpenSystemSettings ||
               choice == PCSitePermissionRequestSystem) {
      valid = false;
    }
    PromptOptions options = std::monostate{};
    if (valid && typed_geolocation_ &&
        (choice == PCSitePermissionAllow ||
         choice == PCSitePermissionAllowOnce)) {
      options =
          GeolocationPromptOptions{precise ? GeolocationAccuracy::kPrecise
                                           : GeolocationAccuracy::kApproximate};
    }
    const bool allows_notifications =
        valid &&
        (choice == PCSitePermissionAllow ||
         choice == PCSitePermissionAllowOnce) &&
        std::find(system_types_.begin(), system_types_.end(),
                  ContentSettingsType::NOTIFICATIONS) != system_types_.end();
    NSWindow* window = window_;
    auto result = std::move(result_);
    // No member access after callback: the manager can destroy this prompt,
    // this page, or synchronously replace its request and UI.
    if (result) {
      std::move(result).Run(valid ? choice : PCSitePermissionInterrupted,
                            std::move(options));
    }
    if (allows_notifications) {
      EnsureSystemNotificationsAllowed(window);
    }
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsSameDocument()) {
      return;
    }
    if (navigation->IsInPrimaryMainFrame()) {
      Cancel();
      return;
    }
    for (const auto& document : frames_) {
      auto* frame = document.AsRenderFrameHostIfValid();
      if (!frame ||
          frame->GetFrameTreeNodeId() == navigation->GetFrameTreeNodeId()) {
        Cancel();
        return;
      }
    }
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    // A covered window leaves the page OCCLUDED; the prompt stays, as in
    // Chrome's PermissionRequestManager, which reacts only to HIDDEN.
    if (visibility == content::Visibility::HIDDEN) {
      Cancel();
    }
  }
  void WebContentsDestroyed() override {
    Cancel();
    Observe(nullptr);
  }
  base::WeakPtr<Delegate> delegate_;
  const permissions::PermissionPrompt* const prompt_;
  Result result_;
  bool closed_ = false;
  bool interrupted_ = false;
  bool started_ = false;
  bool offers_one_time_ = false;
  bool typed_geolocation_ = false;
  bool auxiliary_route_ = false;
  bool embedded_ = false;
  bool refreshing_system_ = false;
  bool open_system_settings_ = false;
  size_t pending_system_requests_ = 0;
  Variant variant_ = Variant::kAsk;
  std::vector<ContentSettingsType> system_types_;
  NSMutableArray* __strong system_observers_;
  std::shared_ptr<NativeAuxiliaryPage> auxiliary_;
  base::CallbackListSubscription auxiliary_cancel_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr document_;
  GURL origin_;
  GURL embedding_;
  std::vector<const permissions::PermissionRequest*> requests_;
  std::vector<content::WeakDocumentPtr> frames_;
  NSWindow* __weak window_;
  NSView* __weak page_;
  PCSitePermissionPresenter* __strong presenter_;
  PCNativeWindowSecurityReservation* __strong reservation_;
  ::id __strong window_observer_;
};

class NativePrompt final : public permissions::PermissionPrompt {
 public:
  NativePrompt(content::WebContents& contents, Delegate& delegate)
      : delegate_(delegate.GetWeakPtr()) {
    request_ = std::make_shared<Request>(
        contents, delegate, this,
        base::BindOnce(&NativePrompt::Decide, weak_factory_.GetWeakPtr()));
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&Request::Start, request_));
  }
  ~NativePrompt() override {
    weak_factory_.InvalidateWeakPtrs();
    request_->Cancel(/*silently=*/true);
  }
  base::RepeatingClosure DetachCallback() {
    return base::BindRepeating(&NativePrompt::PageWillDetach,
                               weak_factory_.GetWeakPtr());
  }
  bool UpdateAnchor() override {
    request_->Revalidate();
    return true;
  }
  TabSwitchingBehavior GetTabSwitchingBehavior() override {
    return kDestroyPromptAndIgnoreRequest;
  }
  permissions::PermissionPromptDisposition GetPromptDisposition()
      const override {
    return permissions::PermissionPromptDisposition::CUSTOM_MODAL_DIALOG;
  }
  bool IsAskPrompt() const override {
    return delegate_ && IsSiteConsentStage(*delegate_);
  }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override {
    return std::nullopt;
  }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants()
      const override {
    auto* flow = delegate_ ? delegate_->GetEmbeddedPromptFlowModel() : nullptr;
    return flow ? flow->GetPromptVariants()
                : std::vector<permissions::ElementAnchoredBubbleVariant>{};
  }
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override {
    return std::nullopt;
  }

 private:
  void PageWillDetach() { request_->Cancel(); }
  void Decide(PCSitePermissionChoice choice, PromptOptions options) {
    if (!delegate_ || delegate_->GetCurrentPrompt() != this) {
      return;
    }
    // These genuine manager operations own content settings, one-time expiry,
    // metrics and downstream OS policy. No synthetic content setting is
    // written.
    auto delegate = delegate_;
    delegate->SetDecisionTime();
    switch (choice) {
      case PCSitePermissionAllow:
        delegate->Accept(options);
        return;
      case PCSitePermissionAllowOnce:
        delegate->AcceptThisTime(options);
        return;
      case PCSitePermissionBlock:
        delegate->Deny(std::monostate{});
        return;
      case PCSitePermissionDismiss:
        delegate->Dismiss(std::monostate{});
        return;
      case PCSitePermissionOpenSystemSettings:
      case PCSitePermissionRequestSystem:
      case PCSitePermissionInterrupted:
        delegate->Ignore(std::monostate{});
        return;
    }
  }
  base::WeakPtr<Delegate> delegate_;
  std::shared_ptr<Request> request_;
  base::WeakPtrFactory<NativePrompt> weak_factory_{this};
};
}  // namespace

std::unique_ptr<permissions::PermissionPrompt> CreateNativeSitePermissionPrompt(
    content::WebContents& contents,
    Delegate* delegate,
    base::RepeatingClosure* on_page_detach) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(delegate);
  CHECK_EQ(delegate->GetAssociatedWebContents(), &contents);
  auto prompt = std::make_unique<NativePrompt>(contents, *delegate);
  if (on_page_detach) {
    *on_page_detach = prompt->DetachCallback();
  }
  return prompt;
}

namespace {
// The page's attachment gate and the cancellation of its one live prompt.
class NativeSitePermissions final
    : public content::WebContentsUserData<NativeSitePermissions> {
 public:
  std::unique_ptr<permissions::PermissionPrompt> CreatePrompt(
      Delegate* delegate) {
    auto prompt =
        CreateNativeSitePermissionPrompt(GetWebContents(), delegate, &detach_);
    if (!attached_) {
      auto detach = std::move(detach_);
      detach.Run();
    }
    return prompt;
  }

  void SetAttached(bool attached) {
    attached_ = attached;
    if (!attached) {
      // The prompt's cancellation may reenter and create the next prompt.
      auto detach = std::move(detach_);
      if (detach) {
        detach.Run();
      }
    }
  }

 private:
  friend WebContentsUserData;
  explicit NativeSitePermissions(content::WebContents* contents)
      : content::WebContentsUserData<NativeSitePermissions>(*contents) {}

  bool attached_ = false;
  base::RepeatingClosure detach_;
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(NativeSitePermissions);
}  // namespace

std::unique_ptr<permissions::PermissionPrompt> CreateSitePermissionPrompt(
    content::WebContents* contents,
    Delegate* delegate) {
  // Chrome's own prompts need a BrowserView, which no Parc page has.
  if (!contents) {
    return nullptr;
  }
  if (HasNativeAuxiliaryRoute(*contents)) {
    return CreateNativeSitePermissionPrompt(*contents, delegate);
  }
  auto* page = NativeSitePermissions::FromWebContents(contents);
  return page ? page->CreatePrompt(delegate) : nullptr;
}

void InstallNativeSitePermissions(content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  NativeSitePermissions::CreateForWebContents(&contents);
}

void SetNativeSitePermissionsAttached(content::WebContents& contents,
                                      bool attached) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (auto* page = NativeSitePermissions::FromWebContents(&contents)) {
    page->SetAttached(attached);
  }
}
}  // namespace parc
