// Copyright 2026 Parc contributors.
#include "extension_action_bridge.h"

#include <algorithm>
#include <set>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/color/chrome_color_id.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "extension_action_container.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/image_loader.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest_handlers/icons_handler.h"
#include "ui/base/resource/resource_scale_factor.h"
#include "ui/color/color_provider.h"
#include "ui/display/display.h"
#include "ui/display/screen.h"
#include "ui/gfx/color_utils.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia_util_mac.h"
#include "ui/gfx/geometry/size_conversions.h"

namespace parc {
struct NativeExtensionActionToken {
  base::WeakPtr<NativeExtensionActionBridge> owner;
  std::weak_ptr<ExtensionActionViewModel> model;
  base::WeakPtr<tabs::TabInterface> tab;
  content::WeakDocumentPtr document;
  uint64_t generation;
};
struct NativeEnabledExtensionToken {
  base::WeakPtr<NativeExtensionActionBridge> owner;
  scoped_refptr<const extensions::Extension> extension;
  base::WeakPtr<tabs::TabInterface> tab;
  content::WeakDocumentPtr document;
  uint64_t generation;
};
}  // namespace parc

@interface PCNativeEnabledExtension () {
 @package
  std::shared_ptr<parc::NativeEnabledExtensionToken> _token;
}
@property(nonatomic, readwrite, copy) NSString* identifier;
@property(nonatomic, readwrite, copy) NSString* name;
@property(nonatomic, readwrite, copy) NSImage* icon;
- (instancetype)initWithToken:(std::shared_ptr<parc::NativeEnabledExtensionToken>)token;
@end
@implementation PCNativeEnabledExtension
@synthesize identifier = _identifier, name = _name, icon = _icon;
- (instancetype)initWithToken:(std::shared_ptr<parc::NativeEnabledExtensionToken>)token {
  if ((self = [super init]))
    _token = std::move(token);
  return self;
}
@end

@interface PCNativeExtensionAction () {
 @package
  std::shared_ptr<parc::NativeExtensionActionToken> _token;
}
@property(nonatomic, readwrite, copy) NSString* identifier;
@property(nonatomic, readwrite, copy) NSString* pageIdentifier;
@property(nonatomic, readwrite, copy) NSString* profilePath;
@property(nonatomic, readwrite) NSUInteger generation;
@property(nonatomic, readwrite) NSUInteger modelIndex;
@property(nonatomic, readwrite) NSUInteger pinnedIndex;
@property(nonatomic, readwrite, copy) NSString* name;
@property(nonatomic, readwrite, copy) NSString* title;
@property(nonatomic, readwrite, copy) NSString* tooltip;
@property(nonatomic, readwrite, copy) NSString* accessibilityLabel;
@property(nonatomic, readwrite, copy) NSImage* icon;
@property(nonatomic, readwrite, copy) NSImage* iconWithoutBadge;
@property(nonatomic, readwrite, copy) NSString* badgeText;
@property(nonatomic, readwrite, copy) NSColor* badgeTextColor;
@property(nonatomic, readwrite, copy) NSColor* badgeBackgroundColor;
@property(nonatomic, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, readwrite, getter=isPinned) BOOL pinned;
@property(nonatomic, readwrite) BOOL canChangePin;
- (instancetype)initWithToken:
    (std::shared_ptr<parc::NativeExtensionActionToken>)token;
@end
@implementation PCNativeExtensionAction
@synthesize identifier = _identifier, pageIdentifier = _pageIdentifier;
@synthesize profilePath = _profilePath, generation = _generation;
@synthesize modelIndex = _modelIndex, pinnedIndex = _pinnedIndex;
@synthesize name = _name, title = _title, tooltip = _tooltip;
@synthesize accessibilityLabel = _accessibilityLabel, icon = _icon;
@synthesize iconWithoutBadge = _iconWithoutBadge;
@synthesize badgeText = _badgeText, badgeTextColor = _badgeTextColor;
@synthesize badgeBackgroundColor = _badgeBackgroundColor;
@synthesize enabled = _enabled, pinned = _pinned, canChangePin = _canChangePin;
- (instancetype)initWithToken:
    (std::shared_ptr<parc::NativeExtensionActionToken>)token {
  if ((self = [super init])) {
    _token = std::move(token);
  }
  return self;
}
@end

@interface PCNativeExtensionPopupAnchor ()
- (instancetype)initWithKind:(PCNativeExtensionPopupAnchorKind)kind
                        view:(NSView*)view
                       width:(CGFloat)width;
@end
@implementation PCNativeExtensionPopupAnchor
@synthesize kind = _kind, focusedView = _focusedView,
            sidebarWidth = _sidebarWidth;
- (instancetype)initWithKind:(PCNativeExtensionPopupAnchorKind)kind
                        view:(NSView*)view
                       width:(CGFloat)width {
  if ((self = [super init])) {
    _kind = kind;
    _focusedView = view;
    _sidebarWidth = width;
  }
  return self;
}
+ (instancetype)windowAnchor {
  return [[self alloc] initWithKind:PCNativeExtensionPopupAnchorWindow
                               view:nil
                              width:0];
}
+ (instancetype)sidebarAnchorWithWidth:(CGFloat)width {
  return [[self alloc] initWithKind:PCNativeExtensionPopupAnchorSidebar
                               view:nil
                              width:width];
}
+ (instancetype)focusedViewAnchor:(NSView*)view {
  return [[self alloc] initWithKind:PCNativeExtensionPopupAnchorFocusedView
                               view:view
                              width:0];
}
@end

namespace parc {
namespace {
NSColor* NativeColor(SkColor color) {
  return [NSColor colorWithSRGBRed:SkColorGetR(color) / 255.0
                             green:SkColorGetG(color) / 255.0
                              blue:SkColorGetB(color) / 255.0
                             alpha:SkColorGetA(color) / 255.0];
}
std::vector<extensions::ImageLoader::ImageRepresentation> ManifestRepresentations(
    const extensions::Extension& extension) {
  std::set<float> scales;
  for (auto scale : ui::GetSupportedResourceScaleFactors())
    scales.insert(ui::GetScaleForResourceScaleFactor(scale));
  if (auto* screen = display::Screen::Get())
    for (const auto& display : screen->GetAllDisplays())
      scales.insert(display.device_scale_factor());
  std::vector<extensions::ImageLoader::ImageRepresentation> result;
  for (float scale : scales) {
    const auto size = gfx::ScaleToFlooredSize(gfx::Size(32, 32), scale);
    auto resource = extensions::IconsInfo::GetIconResource(
        &extension, size.width(), ExtensionIconSet::Match::kBigger);
    if (resource.empty())
      resource = extensions::IconsInfo::GetIconResource(
          &extension, size.width(), ExtensionIconSet::Match::kSmaller);
    result.emplace_back(resource, extensions::ImageLoader::ImageRepresentation::ALWAYS_RESIZE,
                        size, scale);
  }
  return result;
}
}  // namespace
struct NativeExtensionActionBridge::DispatchState {
  size_t active = 0;
  bool stopped = false;
  std::vector<base::OnceClosure> ready;
  void Flush() {
    if (active || !stopped)
      return;
    auto callbacks = std::move(ready);
    for (auto& callback : callbacks) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
          FROM_HERE, std::move(callback));
    }
  }
};
class NativeExtensionActionBridge::Operation {
 public:
  explicit Operation(std::shared_ptr<DispatchState> state)
      : state_(std::move(state)) {
    CHECK(!state_->stopped);
    ++state_->active;
  }
  ~Operation() {
    CHECK(state_->active);
    --state_->active;
    state_->Flush();
  }

 private:
  std::shared_ptr<DispatchState> state_;
};
NativeExtensionActionBridge::NativeExtensionActionBridge(
    BrowserWindowInterface& browser,
    NativeExtensionActionContainer& container,
    base::RepeatingCallback<bool(content::WebContents&)> validate,
    base::RepeatingClosure changed)
    : browser_(browser),
      container_(container),
      validate_(std::move(validate)),
      changed_(std::move(changed)),
      dispatch_(std::make_shared<DispatchState>()) {
  CHECK(validate_ && changed_);
  registry_observation_.Observe(extensions::ExtensionRegistry::Get(browser_.GetProfile()));
  SyncObservers();
}
NativeExtensionActionBridge::~NativeExtensionActionBridge() {
  BeginShutdown();
}
bool NativeExtensionActionBridge::ValidPage(
    content::WebContents& contents) const {
  if (stopped_ || container_.shutdown_ || !container_.model_ ||
      contents.GetBrowserContext() != browser_.GetProfile() ||
      container_.GetActiveWebContents() != &contents ||
      !container_.shell_.IsSelectedBrowser())
    return false;
  auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
  return tab && tab->GetBrowserWindowInterface() == &browser_ &&
         contents.GetPrimaryMainFrame() && validate_.Run(contents);
}
bool NativeExtensionActionBridge::HasEnabledExtensions(
    content::WebContents& contents) const {
  if (!ValidPage(contents) || !registry_observation_.IsObserving())
    return false;
  for (const auto& extension : extensions::ExtensionRegistry::Get(browser_.GetProfile())
                                   ->enabled_extensions()) {
    if (extensions::ui_util::ShouldDisplayInExtensionSettings(*extension))
      return true;
  }
  return false;
}
void NativeExtensionActionBridge::OnExtensionLoaded(
    content::BrowserContext*, const extensions::Extension* extension) {
  manifest_icons_.erase(extension->id());
  Changed();
}
void NativeExtensionActionBridge::OnExtensionUnloaded(
    content::BrowserContext*, const extensions::Extension* extension,
    extensions::UnloadedExtensionReason) {
  manifest_icons_.erase(extension->id());
  Changed();
}
void NativeExtensionActionBridge::OnShutdown(extensions::ExtensionRegistry*) {
  registry_observation_.Reset();
  Changed();
}
std::shared_ptr<ExtensionActionViewModel> NativeExtensionActionBridge::Validate(
    PCNativeExtensionAction* value,
    content::WebContents& contents) const {
  if (!value || !value->_token || !ValidPage(contents))
    return nullptr;
  const auto& token = *value->_token;
  if (token.owner.get() != this || token.generation != generation_ ||
      !token.tab ||
      token.tab.get() != tabs::TabInterface::MaybeGetFromContents(&contents) ||
      token.document.AsRenderFrameHostIfValid() !=
          contents.GetPrimaryMainFrame())
    return nullptr;
  auto model = token.model.lock();
  return model && container_.Find(model->GetId()) == model ? model : nullptr;
}
void NativeExtensionActionBridge::SyncObservers() {
  if (stopped_)
    return;
  auto* active = container_.GetActiveWebContents();
  if (web_contents() != active)
    Observe(active);
  for (auto it = icons_.begin(); it != icons_.end();) {
    if (it->second.model.lock() != container_.Find(it->first))
      it = icons_.erase(it);
    else
      ++it;
  }
  for (const auto& [id, model] : container_.actions_) {
    if (icons_.contains(id))
      continue;
    const std::weak_ptr<ExtensionActionViewModel> model_weak = model;
    auto weak = weak_factory_.GetWeakPtr();
    auto subscription = model->RegisterIconUpdateObserver(base::BindRepeating(
        [](base::WeakPtr<NativeExtensionActionBridge> self, std::string id,
           std::weak_ptr<ExtensionActionViewModel> exact) {
          if (self && self->container_.Find(id) == exact.lock())
            self->Changed();
        },
        weak, id, model_weak));
    icons_.emplace(id, IconObservation{model_weak, std::move(subscription)});
  }
}
void NativeExtensionActionBridge::Changed() {
  if (stopped_)
    return;
  ++generation_;
  SyncObservers();
  if (change_posted_)
    return;
  change_posted_ = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
      FROM_HERE, base::BindOnce(&NativeExtensionActionBridge::DeliverChanged,
                                weak_factory_.GetWeakPtr()));
}
void NativeExtensionActionBridge::DeliverChanged() {
  if (stopped_)
    return;
  change_posted_ = false;
  auto callback = changed_;
  callback.Run();  // Last operation: shell can destroy this bridge.
}
void NativeExtensionActionBridge::DidFinishNavigation(
    content::NavigationHandle* handle) {
  if (handle->IsInPrimaryMainFrame() && handle->HasCommitted())
    Changed();
}
void NativeExtensionActionBridge::TitleWasSet(content::NavigationEntry*) {
  Changed();
}
void NativeExtensionActionBridge::WebContentsDestroyed() {
  Observe(nullptr);
  ++generation_;
  // The TabList may still name this destroying contents during its observer
  // stack. Reconcile only after that genuine owner has updated membership.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
      FROM_HERE, base::BindOnce(&NativeExtensionActionBridge::Changed,
                                weak_factory_.GetWeakPtr()));
}
void NativeExtensionActionBridge::BeginShutdown() {
  if (stopped_)
    return;
  stopped_ = true;
  dispatch_->stopped = true;
  ++generation_;
  weak_factory_.InvalidateWeakPtrs();
  registry_observation_.Reset();
  Observe(nullptr);
  icons_.clear();
  manifest_icons_.clear();
  dispatch_->Flush();
}
void NativeExtensionActionBridge::Shutdown(base::OnceClosure ready) {
  CHECK(ready);
  auto state = dispatch_;
  BeginShutdown();
  state->ready.push_back(std::move(ready));
  state->Flush();
}
void NativeExtensionActionBridge::ManifestIconLoaded(
    std::string id, uint64_t request, base::WeakPtr<tabs::TabInterface> tab,
    content::WeakDocumentPtr document, const gfx::Image& image) {
  auto it = manifest_icons_.find(id);
  if (stopped_ || it == manifest_icons_.end() || it->second.request != request)
    return;
  auto* contents = tab ? tab->GetContents() : nullptr;
  if (!contents || !ValidPage(*contents) ||
      document.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame() ||
      !registry_observation_.IsObserving() ||
      extensions::ExtensionRegistry::Get(browser_.GetProfile())
              ->enabled_extensions().GetByID(id) != it->second.extension.get()) {
    manifest_icons_.erase(it);
    Changed();
    return;
  }
  auto weak = weak_factory_.GetWeakPtr();
  NSImage* native = image.IsEmpty() ? nil : gfx::NSImageFromImageSkia(*image.ToImageSkia());
  if (!weak) return;
  it = manifest_icons_.find(id);
  if (it == manifest_icons_.end() || it->second.request != request) return;
  contents = tab ? tab->GetContents() : nullptr;
  if (!contents || !ValidPage(*contents) ||
      document.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame() ||
      !registry_observation_.IsObserving() ||
      extensions::ExtensionRegistry::Get(browser_.GetProfile())
              ->enabled_extensions().GetByID(id) != it->second.extension.get()) {
    manifest_icons_.erase(it);
    Changed();
    return;
  }
  it->second.image = native;
  Changed();
}
NSArray<PCNativeEnabledExtension*>* NativeExtensionActionBridge::EnabledSnapshot(
    content::WebContents& contents) {
  if (!ValidPage(contents) || !registry_observation_.IsObserving())
    return @[];
  Operation operation(dispatch_);
  auto weak = weak_factory_.GetWeakPtr();
  const uint64_t generation = generation_;
  auto document = contents.GetPrimaryMainFrame()->GetWeakDocumentPtr();
  auto tab = tabs::TabInterface::MaybeGetFromContents(&contents)->GetWeakPtr();
  std::vector<scoped_refptr<const extensions::Extension>> extensions;
  for (const auto& extension : extensions::ExtensionRegistry::Get(browser_.GetProfile())
                                   ->enabled_extensions()) {
    if (extensions::ui_util::ShouldDisplayInExtensionSettings(*extension))
      extensions.push_back(extension);
  }
  NSMutableArray<PCNativeEnabledExtension*>* result = [NSMutableArray array];
  for (const auto& extension : extensions) {
    if (!weak || generation != generation_ || !ValidPage(contents) ||
        document.AsRenderFrameHostIfValid() != contents.GetPrimaryMainFrame())
      return @[];
    const auto& id = extension->id();
    auto it = manifest_icons_.find(id);
    if (it != manifest_icons_.end() && it->second.extension != extension) {
      manifest_icons_.erase(it);
      it = manifest_icons_.end();
    }
    if (it == manifest_icons_.end()) {
      const uint64_t request = ++next_icon_request_;
      manifest_icons_.emplace(id, ManifestIcon{extension, request, nil});
      if (auto* loader = extensions::ImageLoader::Get(browser_.GetProfile()))
        loader->LoadImagesAsync(
              extension.get(), ManifestRepresentations(*extension),
              base::BindOnce(&NativeExtensionActionBridge::ManifestIconLoaded,
                             weak, id, request, tab, document));
      if (!weak || generation != generation_ || !ValidPage(contents))
        return @[];
      it = manifest_icons_.find(id);
    }
    auto token = std::make_shared<NativeEnabledExtensionToken>(
        NativeEnabledExtensionToken{weak, extension, tab, document, generation});
    PCNativeEnabledExtension* value = [[PCNativeEnabledExtension alloc] initWithToken:token];
    value.identifier = base::SysUTF8ToNSString(id);
    value.name = base::SysUTF8ToNSString(extension->name());
    value.icon = it == manifest_icons_.end() ? nil : it->second.image;
    [result addObject:value];
  }
  return weak && generation == generation_ && ValidPage(contents) &&
                 document.AsRenderFrameHostIfValid() == contents.GetPrimaryMainFrame()
             ? [result copy] : @[];
}
std::shared_ptr<ExtensionActionViewModel> NativeExtensionActionBridge::ValidateEnabled(
    PCNativeEnabledExtension* value, content::WebContents& contents) const {
  if (!value || !value->_token || !ValidPage(contents) ||
      !registry_observation_.IsObserving())
    return nullptr;
  const auto& token = *value->_token;
  if (token.owner.get() != this || token.generation != generation_ || !token.tab ||
      token.tab.get() != tabs::TabInterface::MaybeGetFromContents(&contents) ||
      token.document.AsRenderFrameHostIfValid() != contents.GetPrimaryMainFrame() ||
      extensions::ExtensionRegistry::Get(browser_.GetProfile())
              ->enabled_extensions().GetByID(token.extension->id()) != token.extension.get())
    return nullptr;
  return container_.Find(token.extension->id());
}
bool NativeExtensionActionBridge::ExecuteEnabled(PCNativeEnabledExtension* value,
                                                  content::WebContents& contents) {
  if (container_.shell_.HasVisibleBrowserSecurityUI()) return false;
  auto model = ValidateEnabled(value, contents);
  if (!model) return false;
  Operation operation(dispatch_);
  model->ExecuteUserAction(ToolbarActionViewModel::InvocationSource::kMenuEntry);
  return true;
}
bool NativeExtensionActionBridge::ShowEnabledContextMenu(
    PCNativeEnabledExtension* value, content::WebContents& contents) {
  if (container_.shell_.HasVisibleBrowserSecurityUI()) return false;
  auto model = ValidateEnabled(value, contents);
  if (!model) return false;
  Operation operation(dispatch_);
  return container_.shell_.ShowActionContextMenu(*model);
}
NSArray<PCNativeExtensionAction*>* NativeExtensionActionBridge::Snapshot(
    content::WebContents& contents,
    NSString* page_id,
    NSString* profile_path) {
  if (!ValidPage(contents))
    return @[];
  Operation operation(dispatch_);
  SyncObservers();
  const uint64_t generation = generation_;
  auto weak = weak_factory_.GetWeakPtr();
  auto document = contents.GetPrimaryMainFrame()->GetWeakDocumentPtr();
  auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
  const auto tab_weak = tab->GetWeakPtr();
  // Keep real model objects while copying. No renderer/model pointer escapes.
  std::vector<std::shared_ptr<ExtensionActionViewModel>> models;
  for (const auto& id : container_.model_->action_ids()) {
    if (auto model = container_.Find(id))
      models.push_back(std::move(model));
  }
  NSMutableArray<PCNativeExtensionAction*>* result = [NSMutableArray array];
  NSUInteger index = 0;
  for (const auto& model : models) {
    if (!weak || generation != generation_ || !ValidPage(contents) ||
        !document.AsRenderFrameHostIfValid())
      return @[];
    auto token =
        std::make_shared<NativeExtensionActionToken>(NativeExtensionActionToken{
            weak, model, tab_weak, document, generation});
    PCNativeExtensionAction* value =
        [[PCNativeExtensionAction alloc] initWithToken:token];
    value.identifier = base::SysUTF8ToNSString(model->GetId());
    value.pageIdentifier = page_id;
    value.profilePath = profile_path;
    value.generation = generation;
    value.modelIndex = index++;
    const auto& pins = container_.model_->pinned_action_ids();
    const auto pin = std::ranges::find(pins, model->GetId());
    value.pinnedIndex = pin == pins.end()
                            ? NSNotFound
                            : static_cast<NSUInteger>(pin - pins.begin());
    value.pinned = pin != pins.end();
    value.canChangePin =
        !browser_.GetProfile()->IsOffTheRecord() &&
        !container_.model_->IsActionForcePinned(model->GetId());
    value.name = base::SysUTF16ToNSString(model->GetActionName());
    value.title = base::SysUTF16ToNSString(model->GetActionTitle(&contents));
    value.tooltip = base::SysUTF16ToNSString(model->GetTooltip(&contents));
    value.accessibilityLabel =
        base::SysUTF16ToNSString(model->GetAccessibleName(&contents));
    value.enabled = model->IsEnabled(&contents);
    //
    // the 16-point icon in that canvas; the shell shows it at its own size.
    const auto image = model->GetIcon(&contents, gfx::Size(32, 32));
    if (image.IsImage()) {
      // Eager native bitmap representations outlive the ImageSkia source's
      // Browser/Profile dependency. Never retain the lazy model-backed source.
      value.icon = gfx::NSImageFromImageSkia(*image.GetImage().ToImageSkia());
    }
    const auto unbadged =
        model->GetIconWithoutBadge(&contents, gfx::Size(32, 32));
    if (unbadged.IsImage()) {
      value.iconWithoutBadge =
          gfx::NSImageFromImageSkia(*unbadged.GetImage().ToImageSkia());
    }
    // Rasterization calls the real model's color-provider closure. Revalidate
    // before reading further page/profile state, even if rendering reentered.
    if (!weak || generation != generation_ ||
        !document.AsRenderFrameHostIfValid() || !ValidPage(contents)) {
      return @[];
    }
    value.badgeText = @"";
    const auto* extension =
        extensions::ExtensionRegistry::Get(browser_.GetProfile())
            ->enabled_extensions()
            .GetByID(model->GetId());
    if (extension) {
      auto* action =
          extensions::ExtensionActionManager::Get(browser_.GetProfile())
              ->GetExtensionAction(*extension);
      if (action) {
        const int tab_id = sessions::SessionTabHelper::IdForTab(&contents).id();
        value.badgeText =
            base::SysUTF8ToNSString(action->GetDisplayBadgeText(tab_id));
        // IconWithBadgeImageSource's resolution: an unset background is the
        // theme default and is otherwise opaque; unset text has max contrast.
        const SkColor set_background = action->GetBadgeBackgroundColor(tab_id);
        const SkColor background =
            SkColorGetA(set_background) == SK_AlphaTRANSPARENT
                ? contents.GetColorProvider().GetColor(
                      kColorExtensionIconBadgeBackgroundDefault)
                : SkColorSetA(set_background, SK_AlphaOPAQUE);
        const SkColor set_text = action->GetBadgeTextColor(tab_id);
        value.badgeTextColor = NativeColor(
            SkColorGetA(set_text) == SK_AlphaTRANSPARENT
                ? color_utils::GetColorWithMaxContrast(background)
                : set_text);
        value.badgeBackgroundColor = NativeColor(background);
      }
    }
    [result addObject:value];
  }
  return weak && generation == generation_ &&
                 document.AsRenderFrameHostIfValid() && ValidPage(contents)
             ? [result copy]
             : @[];
}
bool NativeExtensionActionBridge::Execute(PCNativeExtensionAction* value,
                                          content::WebContents& contents,
                                          bool menu_entry) {
  if (!Validate(value, contents) ||
      container_.shell_.HasVisibleBrowserSecurityUI())
    return false;
  Operation operation(dispatch_);
  auto model = Validate(value, contents);
  if (!model)
    return false;
  // Disabled is presentation state, not a refusal. The upstream model invokes
  //
  model->ExecuteUserAction(
      menu_entry ? ToolbarActionViewModel::InvocationSource::kMenuEntry
                 : ToolbarActionViewModel::InvocationSource::kToolbarButton);
  return true;
}
bool NativeExtensionActionBridge::ShowContextMenu(
    PCNativeExtensionAction* value,
    content::WebContents& contents) {
  if (!Validate(value, contents) ||
      container_.shell_.HasVisibleBrowserSecurityUI())
    return false;
  Operation operation(dispatch_);
  auto model = Validate(value, contents);
  return model && container_.shell_.ShowActionContextMenu(*model);
}
bool NativeExtensionActionBridge::SetPinned(PCNativeExtensionAction* value,
                                            content::WebContents& contents,
                                            bool pinned) {
  if (!Validate(value, contents) ||
      container_.shell_.HasVisibleBrowserSecurityUI() ||
      browser_.GetProfile()->IsOffTheRecord() ||
      container_.model_->IsActionForcePinned(
          base::SysNSStringToUTF8(value.identifier)))
    return false;
  Operation operation(dispatch_);
  auto model = Validate(value, contents);
  if (!model)
    return false;
  container_.SetPinned(model->GetId(), pinned);
  // Accepted real model operation; synchronous observers may have replaced
  // this owner. Do not dereference owner/model membership after dispatch.
  return true;
}
}  // namespace parc
