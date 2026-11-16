#include "site_permissions.h"

#import <UserNotifications/UserNotifications.h>

#include <algorithm>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/barrier_callback.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/mac/mac_util.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/notifications/notification_display_service.h"
#include "chrome/browser/notifications/notification_display_service_factory.h"
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
#include "content/public/browser/notification_database_data.h"
#include "content/public/browser/platform_notification_context.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/storage_partition.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_capability_type.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#import "dialog_style.h"
#include "native_auxiliary_page.h"
#import "site_permission_presenter.h"
#include "ui/base/base_window.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/message_center/public/cpp/notification.h"
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
NSString* SiteLabel(const GURL& origin) {
  NSString* site = base::SysUTF16ToNSString(
      url_formatter::FormatOriginForSecurityDisplay(
          url::Origin::Create(origin),
          url_formatter::SchemeDisplay::OMIT_HTTP_AND_HTTPS));
  return site.length ? site : @"this website";
}

struct PermissionPresentation {
  NSString* name;
  NSString* symbol;
  CGFloat size;
  bool bold;
  CGFloat offset;
};
PermissionPresentation PresentationFor(permissions::RequestType type) {
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

NSString* PermissionTitle(NSString* site,
                   const std::vector<permissions::RequestType>& types,
                   bool mailto,
                   PermissionPresentation* icon) {
  using T = permissions::RequestType;
  if (types.size() == 1) {
    *icon = PresentationFor(types[0]);
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
  *icon = camera_and_mic ? PresentationFor(T::kCameraStream)
                         : PermissionPresentation{@"unknown", @"gearshape.fill", 14,
                                             false, 0};
  return [NSString stringWithFormat:@"Allow %@ to access your %@?", site,
                                    camera_and_mic ? @"camera, microphone"
                                                   : @"unknown"];
}

base::RepeatingClosureList& SystemPermissionObservers() {
  static base::NoDestructor<base::RepeatingClosureList> observers;
  return *observers;
}

std::optional<UNAuthorizationStatus> g_system_notifications;
bool g_system_notifications_requested = false;

bool HasNotificationCenter() {
  return [NSBundle.mainBundle.bundlePath hasSuffix:@".app"];
}

void FetchSystemNotifications(void (^done)(UNAuthorizationStatus)) {
  if (!HasNotificationCenter()) {
    return;
  }
  [UNUserNotificationCenter.currentNotificationCenter
      getNotificationSettingsWithCompletionHandler:^(
          UNNotificationSettings* settings) {
        const UNAuthorizationStatus status = settings.authorizationStatus;
        dispatch_async(dispatch_get_main_queue(), ^{
          const bool changed = g_system_notifications != status;
          g_system_notifications = status;
          if (changed) {
            SystemPermissionObservers().Notify();
          }
          if (done) {
            done(status);
          }
        });
      }];
}

void RequestSystemNotifications(void (^denied)(void)) {
  g_system_notifications_requested = true;
  [UNUserNotificationCenter.currentNotificationCenter
      requestAuthorizationWithOptions:UNAuthorizationOptionAlert |
                                      UNAuthorizationOptionSound |
                                      UNAuthorizationOptionBadge
                    completionHandler:^(BOOL granted, NSError*) {
                      dispatch_async(dispatch_get_main_queue(), ^{
                        g_system_notifications_requested = false;
                        FetchSystemNotifications(nil);
                        if (!granted && denied) {
                          denied();
                        }
                      });
                    }];
}

void RequestSystemNotificationsIfUndetermined() {
  if (g_system_notifications_requested) {
    return;
  }
  FetchSystemNotifications(^(UNAuthorizationStatus status) {
    if (status == UNAuthorizationStatusNotDetermined &&
        !g_system_notifications_requested) {
      RequestSystemNotifications(nil);
    }
  });
}

void OpenSystemNotificationSettings() {
  base::mac::OpenSystemSettingsPane(
      base::mac::SystemSettingsPane::kNotifications,
      base::SysNSStringToUTF8(NSBundle.mainBundle.bundleIdentifier ?: @""));
}

constexpr base::TimeDelta kHeldNotificationWindow = base::Minutes(1);

bool IsSystemNotificationsPending() {
  return g_system_notifications_requested ||
         g_system_notifications == UNAuthorizationStatusNotDetermined;
}

std::unique_ptr<NotificationCommon::Metadata> CopyNotificationMetadata(
    const NotificationCommon::Metadata* metadata) {
  if (auto* persistent = PersistentNotificationMetadata::From(metadata)) {
    auto copy = std::make_unique<PersistentNotificationMetadata>();
    copy->service_worker_scope = persistent->service_worker_scope;
    copy->is_suspicious = persistent->is_suspicious;
    copy->skip_ua_buttons = persistent->skip_ua_buttons;
    return copy;
  }
  if (auto* page = NonPersistentNotificationMetadata::From(metadata)) {
    auto copy = std::make_unique<NonPersistentNotificationMetadata>();
    copy->document_url = page->document_url;
    return copy;
  }
  return nullptr;
}

class HeldSystemNotifications final
    : public NotificationDisplayService::Observer {
 public:
  HeldSystemNotifications(Profile& profile,
                          NotificationDisplayService& service)
      : profile_(profile.GetWeakPtr()), service_(&service) {
    observation_.Observe(&service);
  }

  NotificationDisplayService* service() const { return service_; }

  void Confirm() {
    for (auto& held : held_) {
      held.confirmed = true;
    }
  }

  void Drop() { held_.clear(); }

  void Show() {
    auto held = std::exchange(held_, {});
    for (auto& entry : held) {
      if (!entry.confirmed || !service_ || !profile_ ||
          base::TimeTicks::Now() - entry.held_at > kHeldNotificationWindow) {
        continue;
      }
      entry.notification.set_renotify(true);
      if (entry.type != NotificationHandler::Type::WEB_PERSISTENT) {
        Display(std::move(entry), true, content::NotificationDatabaseData());
        continue;
      }
      const GURL origin = entry.notification.origin_url();
      const std::string id = entry.notification.id();
      profile_->GetStoragePartitionForUrl(origin)
          ->GetPlatformNotificationContext()
          ->ReadNotificationDataAndRecordInteraction(
              id, origin,
              content::PlatformNotificationContext::Interaction::NONE,
              base::BindOnce(&HeldSystemNotifications::Display,
                             weak_factory_.GetWeakPtr(), std::move(entry)));
    }
  }

 private:
  struct Held {
    NotificationHandler::Type type;
    message_center::Notification notification;
    std::unique_ptr<NotificationCommon::Metadata> metadata;
    base::TimeTicks held_at;
    bool confirmed;
  };

  void Display(Held entry,
               bool still_open,
               const content::NotificationDatabaseData&) {
    if (still_open && service_) {
      service_->Display(entry.type, entry.notification,
                        std::move(entry.metadata));
    }
  }

  void Forget(const std::string& id) {
    const base::TimeTicks now = base::TimeTicks::Now();
    std::erase_if(held_, [&](const Held& held) {
      return held.notification.id() == id ||
             now - held.held_at > kHeldNotificationWindow;
    });
  }

  void OnNotificationDisplayed(
      const message_center::Notification& notification,
      const NotificationCommon::Metadata* const metadata) override {
    if (notification.notifier_id().type !=
        message_center::NotifierType::WEB_PAGE) {
      return;
    }
    Forget(notification.id());
    auto copy = CopyNotificationMetadata(metadata);
    if (copy && !notification.notifier_id().web_app_id &&
        !notification.never_timeout() &&
        notification.type() != message_center::NOTIFICATION_TYPE_PROGRESS &&
        (IsSystemNotificationsPending() || !g_system_notifications)) {
      const NotificationHandler::Type type = copy->type;
      held_.push_back({type, notification, std::move(copy),
                       base::TimeTicks::Now(), IsSystemNotificationsPending()});
    }
    RequestSystemNotificationsIfUndetermined();
  }
  void OnNotificationClosed(const std::string& id) override { Forget(id); }
  void OnNotificationDisplayServiceDestroyed(
      NotificationDisplayService*) override {
    observation_.Reset();
    held_.clear();
    service_ = nullptr;
  }

  base::WeakPtr<Profile> profile_;
  raw_ptr<NotificationDisplayService> service_;
  std::vector<Held> held_;
  base::ScopedObservation<NotificationDisplayService,
                          NotificationDisplayService::Observer>
      observation_{this};
  base::WeakPtrFactory<HeldSystemNotifications> weak_factory_{this};
};

class SystemNotificationRequests final {
 public:
  static SystemNotificationRequests& Get() {
    static base::NoDestructor<SystemNotificationRequests> requests;
    return *requests;
  }

  void Watch(Profile* profile) {
    if (!profile || profile->IsOffTheRecord()) {
      return;
    }
    auto* service = NotificationDisplayServiceFactory::GetForProfile(profile);
    if (!service) {
      return;
    }
    std::erase_if(watches_,
                  [](const auto& watch) { return !watch->service(); });
    if (std::ranges::none_of(watches_, [service](const auto& watch) {
          return watch->service() == service;
        })) {
      watches_.push_back(
          std::make_unique<HeldSystemNotifications>(*profile, *service));
    }
  }

 private:
  friend base::NoDestructor<SystemNotificationRequests>;
  SystemNotificationRequests()
      : subscription_(SystemPermissionObservers().Add(base::BindRepeating(
            &SystemNotificationRequests::Settle, base::Unretained(this)))) {}

  void Settle() {
    if (!g_system_notifications) {
      return;
    }
    for (auto& watch : watches_) {
      switch (*g_system_notifications) {
        case UNAuthorizationStatusNotDetermined:
          watch->Confirm();
          break;
        case UNAuthorizationStatusAuthorized:
        case UNAuthorizationStatusProvisional:
          watch->Show();
          break;
        default:
          watch->Drop();
          break;
      }
    }
  }

  std::vector<std::unique_ptr<HeldSystemNotifications>> watches_;
  base::CallbackListSubscription subscription_;
};

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
  [alert beginSheetModalForWindow:window
                completionHandler:^(NSModalResponse response) {
                  if (response == NSAlertFirstButtonReturn) {
                    OpenSystemNotificationSettings();
                  }
                }];
}

void EnsureSystemNotificationsAllowed(NSWindow* window) {
  __weak NSWindow* weak = window;
  void (^denied)(void) = ^{
    ShowSystemNotificationsDeniedSheet(weak);
  };
  FetchSystemNotifications(^(UNAuthorizationStatus status) {
    if (status == UNAuthorizationStatusDenied) {
      denied();
    } else if (status == UNAuthorizationStatusNotDetermined &&
               !g_system_notifications_requested) {
      RequestSystemNotifications(denied);
    }
  });
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
    NSString* allow = @"Allow";
    std::u16string permission_name;
    offers_one_time_ = true;
    for (const auto& request : delegate_->Requests()) {
      auto* frame =
          content::RenderFrameHost::FromID(request->get_requesting_frame_id());
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
        permission_name += request->GetPermissionNameTextFragment();
      }
      typed_geolocation_ |= request->GetContentSettingsType() ==
                            ContentSettingsType::GEOLOCATION_WITH_OPTIONS;
      auto text = request->GetMessageTextFragment();
      if (text.empty()) {
        Cancel();
        return;
      }
      requests_.push_back(request.get());
      frames_.push_back(frame->GetWeakDocumentPtr());
      types.push_back(request->request_type());
      if (request->request_type() ==
          permissions::RequestType::kRegisterProtocolHandler) {
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
    PermissionPresentation icon;
    NSString* title = PermissionTitle(SiteLabel(origin_), types, mailto, &icon);
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
    closed_ = true;
    result_.Reset();
    [presenter_ invalidate];
    presenter_ = nil;
    [reservation_ invalidate];
    reservation_ = nil;
    if (Valid(true)) {
      delegate->AdvanceOrFinalizeEmbeddedPromptFlow();
    } else if (IsCurrent()) {
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
    valid = valid && Valid(true);
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
    request_->Cancel(true);
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
}

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
bool g_system_location_requested = false;

bool CanRequestSystemLocation() {
  return !g_system_location_requested &&
         system_permission_settings::CanPrompt(ContentSettingsType::GEOLOCATION);
}

void RequestSystemLocation() {
  g_system_location_requested = true;
  system_permission_settings::Request(
      ContentSettingsType::GEOLOCATION,
      base::BindOnce([] { g_system_location_requested = false; }));
}

ContentSettingsType SystemPermissionType(ContentSettingsType type) {
  switch (type) {
    case ContentSettingsType::GEOLOCATION_WITH_OPTIONS:
      return ContentSettingsType::GEOLOCATION;
    case ContentSettingsType::CAMERA_PAN_TILT_ZOOM:
      return ContentSettingsType::MEDIASTREAM_CAMERA;
    default:
      return type;
  }
}

void RefreshSystemPermissions() {
  for (auto type : {ContentSettingsType::MEDIASTREAM_CAMERA,
                    ContentSettingsType::MEDIASTREAM_MIC}) {
    system_permission_settings::IsDeniedFresh(
        type, base::BindOnce(
                  [](ContentSettingsType type, bool was_off, bool) {
                    if (IsSystemPermissionOff(type) != was_off) {
                      SystemPermissionObservers().Notify();
                    }
                  },
                  type, IsSystemPermissionOff(type)));
  }
  FetchSystemNotifications(nil);
}

void WatchSystemPermissions() {
  static bool watching = false;
  if (watching) {
    return;
  }
  watching = true;
  FetchSystemNotifications(nil);
  [NSNotificationCenter.defaultCenter
      addObserverForName:NSApplicationDidBecomeActiveNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification*) {
                RefreshSystemPermissions();
              }];
}

class NativeSitePermissions final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<NativeSitePermissions> {
 public:
  ~NativeSitePermissions() override { StopAwaitingWindow(); }

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
      StopAwaitingWindow();
      auto detach = std::move(detach_);
      if (detach) {
        detach.Run();
      }
      return;
    }
    RequestSystemLocationIfUsed();
  }

 private:
  friend WebContentsUserData;
  explicit NativeSitePermissions(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<NativeSitePermissions>(*contents) {
    WatchSystemPermissions();
    SystemNotificationRequests::Get().Watch(
        Profile::FromBrowserContext(contents->GetBrowserContext()));
  }

  void OnCapabilityTypesChanged(content::WebContentsCapabilityType type,
                                bool used) override {
    if (type != content::WebContentsCapabilityType::kGeolocation) {
      return;
    }
    if (used) {
      RequestSystemLocationIfUsed();
    } else {
      StopAwaitingWindow();
    }
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::VISIBLE) {
      RequestSystemLocationIfUsed();
    }
  }
  void WebContentsDestroyed() override { StopAwaitingWindow(); }

  void RequestSystemLocationIfUsed() {
    auto* contents = web_contents();
    if (!attached_ || !contents || contents->IsBeingDestroyed() ||
        !contents->IsCapabilityActive(
            content::WebContentsCapabilityType::kGeolocation) ||
        !CanRequestSystemLocation()) {
      StopAwaitingWindow();
      return;
    }
    NSView* view = contents->GetNativeView().GetNativeNSView();
    NSWindow* window = view.window;
    if (!window || contents->GetVisibility() != content::Visibility::VISIBLE) {
      StopAwaitingWindow();
      return;
    }
    if (NSApp.active && window.visible && !window.miniaturized &&
        !view.hiddenOrHasHiddenAncestor &&
        (window.keyWindow || window.mainWindow)) {
      StopAwaitingWindow();
      RequestSystemLocation();
      return;
    }
    AwaitWindow(window);
  }

  void AwaitWindow(NSWindow* window) {
    if (awaited_window_ == window && window_observers_.count) {
      return;
    }
    StopAwaitingWindow();
    awaited_window_ = window;
    window_observers_ = [NSMutableArray array];
    base::WeakPtr<NativeSitePermissions> weak = weak_factory_.GetWeakPtr();
    void (^retry)(NSNotification*) = ^(NSNotification*) {
      if (weak) {
        weak->RequestSystemLocationIfUsed();
      }
    };
    for (NSNotificationName name in @[ NSWindowDidBecomeKeyNotification,
                                       NSWindowDidBecomeMainNotification,
                                       NSWindowDidDeminiaturizeNotification ]) {
      [window_observers_
          addObject:[NSNotificationCenter.defaultCenter
                        addObserverForName:name
                                    object:window
                                     queue:nil
                                usingBlock:retry]];
    }
    [window_observers_
        addObject:[NSNotificationCenter.defaultCenter
                      addObserverForName:NSApplicationDidBecomeActiveNotification
                                  object:nil
                                   queue:nil
                              usingBlock:retry]];
  }

  void StopAwaitingWindow() {
    for (id observer in window_observers_) {
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
    window_observers_ = nil;
    awaited_window_ = nil;
  }

  bool attached_ = false;
  base::RepeatingClosure detach_;
  NSWindow* __weak awaited_window_ = nil;
  NSMutableArray* __strong window_observers_ = nil;
  base::WeakPtrFactory<NativeSitePermissions> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(NativeSitePermissions);
}

std::unique_ptr<permissions::PermissionPrompt> CreateSitePermissionPrompt(
    content::WebContents* contents,
    Delegate* delegate) {
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

bool IsSystemPermissionOff(ContentSettingsType type) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  type = SystemPermissionType(type);
  switch (type) {
    case ContentSettingsType::GEOLOCATION:
    case ContentSettingsType::MEDIASTREAM_CAMERA:
    case ContentSettingsType::MEDIASTREAM_MIC:
    case ContentSettingsType::CLIPBOARD_READ_WRITE:
      return !system_permission_settings::IsAllowed(type) &&
             !system_permission_settings::CanPrompt(type);
    case ContentSettingsType::NOTIFICATIONS:
      return g_system_notifications == UNAuthorizationStatusDenied;
    default:
      return false;
  }
}

std::vector<ContentSettingsType> SystemDeniedPermissions() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  std::vector<ContentSettingsType> denied;
  for (auto type : {ContentSettingsType::GEOLOCATION,
                    ContentSettingsType::MEDIASTREAM_CAMERA,
                    ContentSettingsType::MEDIASTREAM_MIC,
                    ContentSettingsType::NOTIFICATIONS}) {
    if (IsSystemPermissionOff(type)) {
      denied.push_back(type);
    }
  }
  return denied;
}

void OpenSystemPermissionSettings(content::WebContents& contents,
                                  ContentSettingsType type) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!IsSystemPermissionOff(type)) {
    return;
  }
  type = SystemPermissionType(type);
  if (type == ContentSettingsType::NOTIFICATIONS) {
    OpenSystemNotificationSettings();
    return;
  }
  system_permission_settings::OpenSystemSettings(&contents, type);
}

base::CallbackListSubscription ObserveSystemPermissions(
    base::RepeatingClosure changed) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  static base::NoDestructor<
      std::unique_ptr<system_permission_settings::ScopedObservation>>
      observation;
  if (!*observation) {
    *observation = system_permission_settings::Observe(base::BindRepeating(
        [](ContentSettingsType, bool) { SystemPermissionObservers().Notify(); }));
  }
  WatchSystemPermissions();
  auto subscription = SystemPermissionObservers().Add(std::move(changed));
  RefreshSystemPermissions();
  return subscription;
}
}
