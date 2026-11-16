// Copyright 2026 Parc contributors.
#import <AppKit/AppKit.h>
#include "native_page_info.h"
#include <optional>

#include <algorithm>
#include <memory>
#include <variant>
#include "base/callback_list.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/certificate_viewer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/page_info/chrome_page_info_delegate.h"
#include "chrome/browser/ui/page_info/chrome_page_info_ui_delegate.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/content_settings/core/browser/content_settings_utils.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/dom_distiller/core/url_constants.h"
#include "components/page_info/page_info.h"
#include "components/page_info/page_info_ui.h"
#include "components/permissions/permission_util.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/ssl_status.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "native_appkit_page.h"
#include "native_page_retirement.h"
#include "site_permissions.h"
#include "net/cert/x509_certificate.h"
#include "ui/base/base_window.h"
#include "url/url_constants.h"
#import "window_security_reservation.h"

@interface PCNativeSiteButton : NSButton
@property(nonatomic) uint64_t revision;
@end
@implementation PCNativeSiteButton
@synthesize revision = _revision;
@end

@interface PCNativeSiteActions : NSObject <NSPopoverDelegate> {
 @public
  base::RepeatingCallback<void(NSInteger, uint64_t)> action;
}
- (void)perform:(PCNativeSiteButton*)sender;
@end
@implementation PCNativeSiteActions
- (void)perform:(PCNativeSiteButton*)sender {
  auto callback = action;
  if (callback) callback.Run(sender.tag, sender.revision);
}
- (void)popoverDidClose:(NSNotification*)notification {
  auto callback = action;
  if (callback) callback.Run(-1, 0);
}
@end

@interface PCNativeSiteDocument : NSView
@end
@implementation PCNativeSiteDocument
- (BOOL)isFlipped { return YES; }
@end

namespace parc {
namespace {
enum Action {
  kDone = -1, kCertificate, kSiteSettings, kCookiesSettings, kCookieToggle,
  kRevokeSSL, kChangePassword, kAllowPasswordReuse, kSafety,
  kQualifiedCertificate,
  kTogglePermission = 1000, kResetPermission = 2000,
  kRememberPermission = 3000, kSystemPermission = 4000, kRevokeObject = 5000,
};

bool HasPageInfo(content::WebContents* contents) {
  auto* entry = contents ? contents->GetController().GetVisibleEntry() : nullptr;
  if (!entry || entry->IsInitialEntry()) return false;
  for (const GURL& url : {entry->GetVirtualURL(), contents->GetLastCommittedURL()}) {
    if (PageInfo::IsFileOrInternalPage(url) || url.SchemeIs(content_settings::kExtensionScheme) ||
        url.SchemeIs(dom_distiller::kDomDistillerScheme) ||
        (url.SchemeIs(url::kAboutScheme) && url.spec() != url::kAboutBlankURL)) return false;
  }
  return true;
}

bool SystemLocationOff(const PageInfo::PermissionInfo& permission) {
  return (permission.type == ContentSettingsType::GEOLOCATION ||
          permission.type == ContentSettingsType::GEOLOCATION_WITH_OPTIONS) &&
      PageInfoUI::IsToggleOn(permission) && IsSystemLocationOff();
}

class SiteInfo final : public content::WebContentsObserver,
                       public content::WebContentsUserData<SiteInfo>,
                       public PageInfoUI {
 public:
  ~SiteInfo() override { Close(); }

  bool Current() const {
    auto* contents = web_contents();
    PCNativePage* page = ExistingNativePage(contents);
    return active_ && contents && !contents->IsBeingDestroyed() &&
        !contents->IsCrashed() && page && !page.closed && !IsNativePageRetiring(page) && browser_ &&
        !browser_->IsDeleteScheduled() && window_ && window_.visible &&
        page.nativeView.window == window_ &&
        !page.nativeView.hiddenOrHasHiddenAncestor &&
        contents->GetVisibility() != content::Visibility::HIDDEN &&
        GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) == browser_.get() &&
        browser_->GetWindow() &&
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window_ &&
        document_.AsRenderFrameHostIfValid() == contents->GetPrimaryMainFrame() &&
        !window_.attachedSheet && !PCNativeWindowHasSecurityReservation(window_);
  }

  bool Show(NSView* anchor, std::optional<ContentSettingsType> permission = std::nullopt) {
    auto alive = lifetime_.GetWeakPtr();
    Close();
    if (!alive) return false;
    auto* contents = web_contents();
    auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    PCNativePage* page = ExistingNativePage(contents);
    if (!browser || !tab || !page || !anchor || !contents->GetPrimaryMainFrame() ||
        !contents->GetPrimaryMainFrame()->IsRenderFrameLive() || !HasPageInfo(contents)) return false;
    browser_ = browser->GetWeakPtr();
    window_ = page.nativeView.window;
    document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    active_ = true;
    focused_permission_ = permission;
    if (!Current() || !window_.keyWindow || anchor.window != window_ ||
        anchor.hiddenOrHasHiddenAncestor) { Close(); return false; }
    const GURL url = contents->GetLastCommittedURL();
    model_ = std::make_shared<PageInfo>(std::make_unique<ChromePageInfoDelegate>(contents), contents, url);
    ui_delegate_ = std::make_unique<ChromePageInfoUiDelegate>(contents, url);
    actions_ = [PCNativeSiteActions new];
    auto weak = callbacks_.GetWeakPtr();
    actions_->action = base::BindRepeating(&SiteInfo::Perform, weak);
    popover_ = [NSPopover new];
    popover_.behavior = NSPopoverBehaviorTransient;
    popover_.delegate = actions_;
    popover_.contentViewController = [NSViewController new];
    deactivated_ = tab->RegisterWillDeactivate(base::BindRepeating(
        [](base::WeakPtr<SiteInfo> self, tabs::TabInterface*) { if (self) self->Close(); }, weak));
    detached_ = tab->RegisterWillDetach(base::BindRepeating(
        [](base::WeakPtr<SiteInfo> self, tabs::TabInterface*, tabs::TabInterface::DetachReason) {
          if (self) self->Close();
        }, weak));
    discarded_ = tab->RegisterWillDiscardContents(base::BindRepeating(
        [](base::WeakPtr<SiteInfo> self, tabs::TabInterface*, content::WebContents*, content::WebContents*) {
          if (self) self->Close();
        }, weak));
    observers_ = [NSMutableArray array];
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
          NSWindowDidMiniaturizeNotification, PCNativeWindowSecurityStateChanged]) {
      [observers_ addObject:[NSNotificationCenter.defaultCenter addObserverForName:name
          object:window_ queue:nil usingBlock:^(NSNotification*) { if (weak) weak->Close(); }]];
    }
    [observers_ addObject:[NSNotificationCenter.defaultCenter
        addObserverForName:NSApplicationDidResignActiveNotification object:NSApp queue:nil
        usingBlock:^(NSNotification*) { if (weak) weak->Close(); }]];
    auto model = model_;
    model->InitializeUiState(this, base::DoNothing());
    if (!weak) return false;
    if (!Current()) { Close(); return false; }
    Render();
    [popover_ showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
    if (!weak) return false;
    if (!popover_.shown) { Close(); return false; }
    return true;
  }

  void Close() {
    if (!active_) return;
    active_ = false;
    callbacks_.InvalidateWeakPtrs();
    auto model = std::move(model_);
    if (actions_) actions_->action.Reset();
    popover_.delegate = nil;
    [popover_ close]; popover_ = nil; actions_ = nil;
    for (id observer in observers_) [NSNotificationCenter.defaultCenter removeObserver:observer];
    observers_ = nil;
    deactivated_ = {}; detached_ = {}; discarded_ = {};
    ui_delegate_.reset(); permissions_.clear(); objects_.clear();
    certificate_.reset(); two_qwac_.reset();
    title_ = nil; summary_ = nil; details_ = nil;
    cookie_count_ = -1; cookie_state_ = CookieControlsState::kHidden;
    danger_ = false; revoke_ssl_ = false; password_warning_ = false;
    safe_browsing_warning_ = false;
    focused_permission_.reset();
    browser_.reset(); window_ = nil; render_pending_ = false;
    if (model) model->OnUIClosing(nullptr);
  }

  void SetIdentityInfo(const IdentityInfo& info) override {
    title_ = base::SysUTF8ToNSString(info.site_identity);
    auto description = GetSecurityDescription(info);
    summary_ = base::SysUTF16ToNSString(description->summary);
    details_ = base::SysUTF16ToNSString(description->details);
    danger_ = description->summary_style == SecuritySummaryColor::RED;
    safe_browsing_warning_ = description->type == SecurityDescriptionType::SAFE_BROWSING;
    certificate_ = info.certificate; two_qwac_ = info.two_qwac;
    revoke_ssl_ = info.show_ssl_decision_revoke_button;
    password_warning_ = info.show_change_password_buttons;
    ScheduleRender();
  }
  void SetPermissionInfo(const PermissionInfoList& permissions, ChosenObjectInfoList objects) override {
    permissions_ = permissions; objects_ = std::move(objects); ScheduleRender();
  }
  void SetCookieInfo(const CookiesInfo& cookies) override {
    cookie_count_ = cookies.allowed_sites_count;
    cookie_state_ = cookies.controls_state; cookie_enforcement_ = cookies.enforcement;
    ScheduleRender();
  }
  void DidChangeVisibleSecurityState() override {
    if (model_ && Current()) { auto model = model_; model->UpdateSecurityState(); }
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) Close();
  }
  void PrimaryPageChanged(content::Page&) override { Close(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) Close();
  }
  void WebContentsDestroyed() override { Close(); }

 private:
  friend class content::WebContentsUserData<SiteInfo>;
  explicit SiteInfo(content::WebContents* contents)
      : WebContentsObserver(contents), content::WebContentsUserData<SiteInfo>(*contents) {}
  bool Mutable(const PageInfo::PermissionInfo& permission) const {
    int text = 0, link = 0;
    return permission.source == content_settings::SettingSource::kUser &&
        !ui_delegate_->ShouldShowSettingsLinkForPermission(permission.type, &text, &link) &&
        (ui_delegate_->ShouldShowAllow(permission.type) || ui_delegate_->ShouldShowAsk(permission.type));
  }
  void ScheduleRender() {
    ++revision_;
    if (!active_ || render_pending_) return;
    render_pending_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(FROM_HERE,
        base::BindOnce([](base::WeakPtr<SiteInfo> self) {
          if (!self) return;
          self->render_pending_ = false;
          if (self->Current()) self->Render(); else self->Close();
        }, callbacks_.GetWeakPtr()));
  }
  void Perform(NSInteger command, uint64_t revision) {
    if (command == kDone) { Close(); return; }
    if (!model_ || !Current() || revision != revision_) return;
    auto weak = callbacks_.GetWeakPtr();
    auto model = model_;
    if (command >= kRevokeObject) {
      size_t index = command - kRevokeObject;
      if (index >= objects_.size()) return;
      auto& item = *objects_[index];
      if (item.chooser_object->source != content_settings::SettingSource::kUser) return;
      auto info = item.ui_info.get();
      base::Value object(item.chooser_object->value.Clone());
      model->OnSiteChosenObjectDeleted(info, object);
      return;
    }
    if (command >= kTogglePermission) {
      size_t index = command % 1000;
      if (index >= permissions_.size()) return;
      auto permission = permissions_[index];
      model->UpdatePermissions();
      if (!weak || !Current()) return;
      auto found = std::find_if(permissions_.begin(), permissions_.end(), [&](const auto& current) {
        return current.type == permission.type && current.requesting_origin == permission.requesting_origin;
      });
      if (found == permissions_.end()) return;
      permission = *found;
      if (command >= kSystemPermission) {
        int text = 0, link = 0;
        if (ui_delegate_->ShouldShowSettingsLinkForPermission(permission.type, &text, &link))
          ui_delegate_->SettingsLinkClicked(permission.type);
        else if (SystemLocationOff(permission))
          OpenSystemLocationSettings(*web_contents());
        return;
      }
      if (!Mutable(permission)) return;
      if (command >= kRememberPermission) {
        if (!std::holds_alternative<ContentSetting>(permission.default_setting) ||
            !permissions::PermissionUtil::DoesSupportTemporaryGrants(permission.type)) return;
        PageInfoUI::ToggleBetweenRememberAndForget(permission);
      } else if (command >= kResetPermission) {
        permission.setting.reset(); permission.is_one_time = false;
      } else {
        if (!std::holds_alternative<ContentSetting>(permission.default_setting)) return;
        PageInfoUI::ToggleBetweenAllowAndBlock(permission);
      }
      model->OnSitePermissionChanged(permission.type, permission.setting,
                                    permission.requesting_origin, permission.is_one_time);
      return;
    }
    if (command == kCookieToggle) {
      if (cookie_enforcement_ == CookieControlsEnforcement::kNoEnforcement &&
          cookie_state_ != CookieControlsState::kHidden)
        model->OnThirdPartyToggleClicked(cookie_state_ == CookieControlsState::kAllowed3pc);
      return;
    }
    if (command == kRevokeSSL) {
      if (revoke_ssl_) { model->OnRevokeSSLErrorBypassButtonPressed(); if (weak) model->UpdateSecurityState(); }
      return;
    }
    auto contents = web_contents()->GetWeakPtr();
    auto document = document_;
    auto browser = browser_;
    NSWindow* window = window_;
    auto certificate = command == kQualifiedCertificate ? two_qwac_ : certificate_;
    bool password_warning = password_warning_;
    Close();
    if (!contents || !browser || browser->IsDeleteScheduled() ||
        document.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame() ||
        GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents.get()) != browser.get() ||
        ExistingNativePage(contents.get()).nativeView.window != window) return;
    switch (command) {
      case kCertificate: if (certificate) model->OpenCertificateDialog(certificate.get()); break;
      case kQualifiedCertificate: if (certificate) model->OpenCertificateDialog(certificate.get()); break;
      case kSiteSettings: model->OpenSiteSettingsView(); break;
      case kCookiesSettings: model->OpenCookiesSettingsView(); break;
      case kChangePassword: if (password_warning) model->OnChangePasswordButtonPressed(); break;
      case kAllowPasswordReuse: if (password_warning) model->OnAllowlistPasswordReuseButtonPressed(); break;
      case kSafety: model->OpenSafeBrowsingHelpCenterPage(); break;
      default: break;
    }
  }

  void Render() {
    if (!popover_ || !ui_delegate_) return;
    NSView* permission_heading = nil;
    NSStackView* root = [NSStackView new];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading; root.spacing = 9;
    auto label = [&](NSString* text, bool heading = false, bool warning = false) {
      if (!text.length) return;
      NSTextField* field = [NSTextField wrappingLabelWithString:text];
      field.font = [NSFont systemFontOfSize:heading ? 15 : 12
          weight:heading ? NSFontWeightSemibold : NSFontWeightRegular];
      if (warning) field.textColor = NSColor.systemRedColor;
      [field.widthAnchor constraintEqualToConstant:340].active = YES;
      [root addArrangedSubview:field];
    };
    auto button = [&](NSString* text, NSInteger tag, bool enabled = true) {
      PCNativeSiteButton* control = [PCNativeSiteButton buttonWithTitle:text
          target:actions_ action:@selector(perform:)];
      control.tag = tag; control.revision = revision_; control.enabled = enabled;
      control.bezelStyle = NSBezelStyleRounded;
      [root addArrangedSubview:control]; return control;
    };
    label(title_, true); label(summary_, true, danger_); label(details_);
    if (certificate_) button(@"View Certificate…", kCertificate);
    if (two_qwac_) button(@"View Qualified Certificate…", kQualifiedCertificate);
    if (revoke_ssl_) button(@"Restore certificate warnings", kRevokeSSL);
    if (password_warning_) {
      button(@"Change password…", kChangePassword);
      button(@"Mark this site as legitimate", kAllowPasswordReuse);
    }
    if (safe_browsing_warning_) button(@"Learn about this warning…", kSafety);
    for (size_t i = 0; i < permissions_.size() && i < 1000; ++i) {
      const auto& permission = permissions_[i];
      label(base::SysUTF16ToNSString(PermissionTypeToUIString(permission.type)), true);
      if (focused_permission_ == permission.type) permission_heading = root.arrangedSubviews.lastObject;
      label(base::SysUTF16ToNSString(PermissionStateToUIString(ui_delegate_.get(), permission)));
      if (permission.requesting_origin) label(base::SysUTF8ToNSString(permission.requesting_origin->Serialize()));
      label(base::SysUTF16ToNSString(ui_delegate_->GetPermissionDetail(permission.type)));
      label(base::SysUTF16ToNSString(PermissionManagedTooltipToUIString(ui_delegate_.get(), permission)));
      bool mutable_permission = Mutable(permission);
      if (std::holds_alternative<ContentSetting>(permission.default_setting)) {
        bool enabled = PageInfoUI::IsToggleOn(permission);
        bool guard = permissions::PermissionUtil::IsGuardContentSetting(permission.type);
        button(enabled ? @"Block" : guard ? @"Ask before accessing" : @"Allow",
               kTogglePermission + i, mutable_permission);
        if (permissions::PermissionUtil::DoesSupportTemporaryGrants(permission.type) && enabled)
          button(permission.is_one_time ? @"Remember this permission" : @"Allow this time only",
                 kRememberPermission + i, mutable_permission);
      } else {
        button(@"Change in Site Settings…", kSiteSettings);
      }
      if (permission.setting) button(@"Reset to default", kResetPermission + i, mutable_permission);
      int text = 0, link = 0;
      if (ui_delegate_->ShouldShowSettingsLinkForPermission(permission.type, &text, &link)) {
        button(@"Open System Settings…", kSystemPermission + i);
      } else if (SystemLocationOff(permission)) {
        label(@"Location is off for Parc in macOS System Settings.", false, true);
        button(@"Open System Settings…", kSystemPermission + i);
      }
    }
    for (size_t i = 0; i < objects_.size(); ++i) {
      const auto& item = *objects_[i];
      auto* context = model_->GetChooserContextFromUIInfo(item.ui_info.get());
      if (!context) continue;
      label(base::SysUTF16ToNSString(context->GetObjectDisplayNameForUI(item.chooser_object->value)));
      button(@"Remove access", kRevokeObject + i,
             item.chooser_object->source == content_settings::SettingSource::kUser);
    }
    if (cookie_count_ >= 0) label([NSString stringWithFormat:@"%d sites storing data", cookie_count_]);
    if (cookie_state_ != CookieControlsState::kHidden) {
      button(cookie_state_ == CookieControlsState::kAllowed3pc ? @"Block third-party cookies" : @"Allow third-party cookies",
             kCookieToggle, cookie_enforcement_ == CookieControlsEnforcement::kNoEnforcement);
    }
    button(@"Cookie Settings…", kCookiesSettings);
    int settings_text = 0, settings_tooltip = 0;
    if (ui_delegate_->ShouldShowSiteSettings(&settings_text, &settings_tooltip))
      button(@"Site Settings…", kSiteSettings);
    PCNativeSiteButton* done = button(@"Done", kDone); done.keyEquivalent = @"\r";
    root.frame = NSMakeRect(18, 18, 340, root.fittingSize.height);
    PCNativeSiteDocument* document = [[PCNativeSiteDocument alloc]
        initWithFrame:NSMakeRect(0, 0, 376, root.fittingSize.height + 36)];
    [document addSubview:root];
    NSScrollView* scroll = [NSScrollView new]; scroll.documentView = document;
    scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES; scroll.drawsBackground = NO;
    popover_.contentViewController.view = scroll;
    popover_.contentSize = NSMakeSize(376, std::min<CGFloat>(520, document.frame.size.height));
    if (permission_heading) {
      [root layoutSubtreeIfNeeded];
      [permission_heading scrollRectToVisible:permission_heading.bounds];
    }
  }

  bool active_ = false, render_pending_ = false, danger_ = false;
  bool revoke_ssl_ = false, password_warning_ = false, safe_browsing_warning_ = false;
  std::optional<ContentSettingsType> focused_permission_;
  uint64_t revision_ = 0;
  int cookie_count_ = -1;
  CookieControlsState cookie_state_ = CookieControlsState::kHidden;
  CookieControlsEnforcement cookie_enforcement_ = CookieControlsEnforcement::kNoEnforcement;
  std::shared_ptr<PageInfo> model_;
  std::unique_ptr<ChromePageInfoUiDelegate> ui_delegate_;
  PermissionInfoList permissions_;
  ChosenObjectInfoList objects_;
  scoped_refptr<net::X509Certificate> certificate_, two_qwac_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  content::WeakDocumentPtr document_;
  NSWindow* __weak window_;
  NSString* __strong title_; NSString* __strong summary_; NSString* __strong details_;
  NSPopover* __strong popover_;
  PCNativeSiteActions* __strong actions_;
  NSMutableArray* __strong observers_;
  base::CallbackListSubscription deactivated_, detached_, discarded_;
  base::WeakPtrFactory<SiteInfo> callbacks_{this};
  base::WeakPtrFactory<SiteInfo> lifetime_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(SiteInfo);

using SiteControlsHandler = void (^)(NSArray<NSDictionary<NSString*, id>*>* _Nullable);
class SiteControls final : public content::WebContentsObserver,
                           public content::WebContentsUserData<SiteControls>,
                           public PageInfoUI {
 public:
  ~SiteControls() override { End(); }

  bool Begin(SiteControlsHandler handler) {
    auto alive = lifetime_.GetWeakPtr();
    End();
    if (!alive) return false;
    auto* contents = web_contents();
    if (!handler || !contents || contents->IsBeingDestroyed() || contents->IsCrashed() ||
        !contents->GetPrimaryMainFrame() || !contents->GetPrimaryMainFrame()->IsRenderFrameLive()) return false;
    PCNativePage* page = ExistingNativePage(contents);
    if (!page || page.closed || IsNativePageRetiring(page)) return false;
    const GURL url = contents->GetLastCommittedURL();
    document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    handler_ = [handler copy];
    active_ = true;
    if (!HasPageInfo(contents)) return true;
    system_location_ = ObserveSystemLocation(
        base::BindRepeating(&SiteControls::Refresh, callbacks_.GetWeakPtr()));
    model_ = std::make_shared<PageInfo>(std::make_unique<ChromePageInfoDelegate>(contents), contents, url);
    ui_delegate_ = std::make_unique<ChromePageInfoUiDelegate>(contents, url);
    auto model = model_;
    model->InitializeUiState(this, base::DoNothing());
    return alive && active_;
  }

  bool Toggle(NSInteger index, NSUInteger revision) {
    if (index == -2) return ToggleAutoPictureInPicture();
    if (!Current() || revision != revision_ || index < 0 ||
        static_cast<size_t>(index) >= permissions_.size()) return false;
    const auto wanted = permissions_[index];
    auto weak = callbacks_.GetWeakPtr();
    auto model = model_;
    model->UpdatePermissions();
    if (!weak || !Current()) return false;
    auto found = std::find_if(permissions_.begin(), permissions_.end(), [&](const auto& current) {
      return current.type == wanted.type && current.requesting_origin == wanted.requesting_origin;
    });
    if (found == permissions_.end() || !Changeable(*found)) return false;
    auto permission = *found;
    PageInfoUI::ToggleBetweenAllowAndBlock(permission);
    model->OnSitePermissionChanged(permission.type, permission.setting,
                                  permission.requesting_origin, permission.is_one_time);
    return true;
  }

  void Refresh() {
    if (!Current()) return;
    auto model = model_;
    model->UpdatePermissions();
  }

  bool OpenSystemSettings(NSInteger index, NSUInteger revision) {
    if (!Current() || revision != revision_ || index < 0 ||
        static_cast<size_t>(index) >= permissions_.size() ||
        !SystemLocationOff(permissions_[index])) return false;
    OpenSystemLocationSettings(*web_contents());
    return true;
  }

  void End() {
    if (!active_) return;
    active_ = false;
    callbacks_.InvalidateWeakPtrs();
    system_location_ = {};
    auto model = std::move(model_);
    SiteControlsHandler handler = handler_;
    handler_ = nil;
    ui_delegate_.reset(); permissions_.clear(); document_ = {};
    publish_pending_ = false;
    if (handler) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
          base::BindOnce([](SiteControlsHandler handler) { handler(nil); }, handler));
    }
    if (model) model->OnUIClosing(nullptr);
  }

  void SetPermissionInfo(const PermissionInfoList& permissions, ChosenObjectInfoList) override {
    permissions_ = permissions;
    ++revision_;
    if (!active_ || publish_pending_) return;
    publish_pending_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(FROM_HERE,
        base::BindOnce([](base::WeakPtr<SiteControls> self) {
          if (!self) return;
          self->publish_pending_ = false;
          if (self->Current()) self->Publish(); else self->End();
        }, callbacks_.GetWeakPtr()));
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) End();
  }
  void PrimaryPageChanged(content::Page&) override { End(); }
  void WebContentsDestroyed() override { End(); }

 private:
  friend class content::WebContentsUserData<SiteControls>;
  explicit SiteControls(content::WebContents* contents)
      : WebContentsObserver(contents), content::WebContentsUserData<SiteControls>(*contents) {}

  bool ListsAutoPictureInPicture() const {
    return std::any_of(permissions_.begin(), permissions_.end(), [](const auto& permission) {
      return permission.type == ContentSettingsType::AUTO_PICTURE_IN_PICTURE;
    });
  }
  std::optional<std::pair<bool, bool>> AutoPictureInPicture() const {
    auto* contents = web_contents();
    if (!contents) return std::nullopt;
    auto* map = HostContentSettingsMapFactory::GetForProfile(
        Profile::FromBrowserContext(contents->GetBrowserContext()));
    if (!map) return std::nullopt;
    const GURL url = contents->GetLastCommittedURL();
    content_settings::SettingInfo info;
    ContentSetting setting = map->GetContentSetting(url, url, ContentSettingsType::AUTO_PICTURE_IN_PICTURE, &info);
    return std::make_pair(setting == CONTENT_SETTING_ALLOW || setting == CONTENT_SETTING_ASK,
                          info.source == content_settings::SettingSource::kUser);
  }
  bool ToggleAutoPictureInPicture() {
    if (!Current()) return false;
    auto weak = callbacks_.GetWeakPtr();
    auto model = model_;
    model->UpdatePermissions();
    if (!weak || !Current() || ListsAutoPictureInPicture()) return false;
    auto state = AutoPictureInPicture();
    if (!state || !state->second) return false;
    model->OnSitePermissionChanged(ContentSettingsType::AUTO_PICTURE_IN_PICTURE,
        PermissionSetting(state->first ? CONTENT_SETTING_BLOCK : CONTENT_SETTING_ALLOW), std::nullopt, false);
    return true;
  }
  bool Current() const {
    auto* contents = web_contents();
    PCNativePage* page = ExistingNativePage(contents);
    return active_ && model_ && ui_delegate_ && contents && !contents->IsBeingDestroyed() &&
        !contents->IsCrashed() && page && !page.closed && !IsNativePageRetiring(page) &&
        document_.AsRenderFrameHostIfValid() == contents->GetPrimaryMainFrame();
  }
  bool Changeable(const PageInfo::PermissionInfo& permission) const {
    int text = 0, link = 0;
    return std::holds_alternative<ContentSetting>(permission.default_setting) &&
        permission.source == content_settings::SettingSource::kUser &&
        !ui_delegate_->ShouldShowSettingsLinkForPermission(permission.type, &text, &link) &&
        (ui_delegate_->ShouldShowAllow(permission.type) || ui_delegate_->ShouldShowAsk(permission.type));
  }
  void Publish() {
    NSMutableArray<NSDictionary<NSString*, id>*>* rows = [NSMutableArray array];
    NSNumber* revision = @(static_cast<NSUInteger>(revision_));
    if (!ListsAutoPictureInPicture()) {
      if (auto state = AutoPictureInPicture()) {
        [rows addObject:@{
          @"title" : base::SysUTF16ToNSString(PermissionTypeToUIString(ContentSettingsType::AUTO_PICTURE_IN_PICTURE)),
          @"allowed" : @(state->first),
          @"changeable" : @(state->second),
          @"autoPictureInPicture" : @YES,
          @"key" : [NSString stringWithFormat:@"%d", static_cast<int>(ContentSettingsType::AUTO_PICTURE_IN_PICTURE)],
          @"index" : @(-2),
          @"revision" : revision,
        }];
      }
    }
    for (size_t i = 0; i < permissions_.size(); ++i) {
      const auto& permission = permissions_[i];
      NSString* title = base::SysUTF16ToNSString(PermissionTypeToUIString(permission.type));
      if (permission.requesting_origin) {
        title = [NSString stringWithFormat:@"%@ (%@)", title,
            base::SysUTF8ToNSString(permission.requesting_origin->host())];
      }
      [rows addObject:@{
        @"title" : title,
        @"allowed" : @(PageInfoUI::IsToggleOn(permission)),
        @"changeable" : @(Changeable(permission)),
        @"systemSettings" : @(SystemLocationOff(permission)),
        @"autoPictureInPicture" : @(permission.type == ContentSettingsType::AUTO_PICTURE_IN_PICTURE),
        @"key" : [NSString stringWithFormat:@"%d %@", static_cast<int>(permission.type),
            permission.requesting_origin ? base::SysUTF8ToNSString(permission.requesting_origin->Serialize()) : @""],
        @"index" : @(static_cast<NSInteger>(i)),
        @"revision" : revision,
      }];
    }
    SiteControlsHandler handler = handler_;
    if (handler) handler(rows);
  }

  bool active_ = false, publish_pending_ = false;
  uint64_t revision_ = 0;
  std::shared_ptr<PageInfo> model_;
  std::unique_ptr<ChromePageInfoUiDelegate> ui_delegate_;
  PermissionInfoList permissions_;
  content::WeakDocumentPtr document_;
  SiteControlsHandler __strong handler_;
  base::CallbackListSubscription system_location_;
  base::WeakPtrFactory<SiteControls> callbacks_{this};
  base::WeakPtrFactory<SiteControls> lifetime_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(SiteControls);
}
bool ShowNativePageInfoPermission(content::WebContents* contents, ContentSettingsType type) {
  PCNativePage* page = ExistingNativePage(contents);
  if (!page || !page.canShowSiteInfo) return false;
  SiteInfo::CreateForWebContents(contents);
  return SiteInfo::FromWebContents(contents)->Show(page.nativeView, type);
}
void RefreshNativeSiteControls(content::WebContents* contents) {
  if (auto* controls = contents ? SiteControls::FromWebContents(contents) : nullptr) controls->Refresh();
}
}

@implementation PCNativePage (SiteInfo)
- (BOOL)canShowSiteInfo {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || self.closed || contents->IsBeingDestroyed() || contents->IsCrashed() ||
      parc::IsNativePageRetiring(self) || !contents->GetPrimaryMainFrame() ||
      !contents->GetPrimaryMainFrame()->IsRenderFrameLive()) return NO;
  NSWindow* window = self.nativeView.window;
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  return parc::HasPageInfo(contents) && browser && !browser->IsDeleteScheduled() &&
      window && window.keyWindow && window.visible && !window.miniaturized &&
      !self.nativeView.hiddenOrHasHiddenAncestor && !window.attachedSheet &&
      !PCNativeWindowHasSecurityReservation(window);
}
- (BOOL)showSiteInfoFromView:(NSView*)anchor {
  auto* contents = parc::ContentsForNativePage(self);
  if (!self.canShowSiteInfo) return NO;
  parc::SiteInfo::CreateForWebContents(contents);
  return parc::SiteInfo::FromWebContents(contents)->Show(anchor);
}
@end

@implementation PCNativePage (SiteControls)
- (BOOL)openSiteControlsWithHandler:(void (^)(NSArray<NSDictionary<NSString*, id>*>* _Nullable))handler {
  auto* contents = parc::ContentsForNativePage(self);
  if (!handler || !contents || self.closed || contents->IsBeingDestroyed() || contents->IsCrashed() ||
      parc::IsNativePageRetiring(self)) return NO;
  auto* entry = contents->GetController().GetVisibleEntry();
  if (!entry || entry->IsInitialEntry()) return NO;
  parc::SiteControls::CreateForWebContents(contents);
  return parc::SiteControls::FromWebContents(contents)->Begin(handler);
}
- (BOOL)toggleSiteControlsPermission:(NSInteger)index revision:(NSUInteger)revision {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || self.closed || parc::IsNativePageRetiring(self)) return NO;
  auto* controls = parc::SiteControls::FromWebContents(contents);
  return controls && controls->Toggle(index, revision);
}
- (BOOL)openSiteControlsSystemSettings:(NSInteger)index revision:(NSUInteger)revision {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || self.closed || parc::IsNativePageRetiring(self)) return NO;
  auto* controls = parc::SiteControls::FromWebContents(contents);
  return controls && controls->OpenSystemSettings(index, revision);
}
- (void)closeSiteControls {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents) return;
  if (auto* controls = parc::SiteControls::FromWebContents(contents)) controls->End();
}
- (BOOL)canShowCertificate {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || self.closed || contents->IsBeingDestroyed() || contents->IsCrashed() ||
      parc::IsNativePageRetiring(self)) return NO;
  auto* entry = contents->GetController().GetVisibleEntry();
  return entry && !entry->IsInitialEntry() && entry->GetSSL().certificate &&
      contents->GetTopLevelNativeWindow();
}
- (BOOL)showCertificate {
  if (!self.canShowCertificate) return NO;
  auto* contents = parc::ContentsForNativePage(self);
  ShowCertificateViewer(contents, contents->GetTopLevelNativeWindow(),
                        contents->GetController().GetVisibleEntry()->GetSSL().certificate.get());
  return YES;
}
@end
