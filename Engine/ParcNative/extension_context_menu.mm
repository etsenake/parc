// Copyright 2026 Parc contributors.
#include "extension_context_menu.h"

#import <AppKit/AppKit.h>

#include <set>
#include <vector>

#include "base/auto_reset.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/tab_list/tab_list_interface_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/side_panel/side_panel_entry_key.h"
#include "chrome/browser/ui/side_panel/side_panel_ui.h"
#include "chrome/browser/ui/views/extensions/security_dialog_tracker.h"
#include "chrome/grit/generated_resources.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "extension_action_container.h"
#include "extension_security_context.h"
#include "extension_uninstall.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/common/extension.h"
#import "native_appkit_bridge.h"
#include "ui/base/base_window.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/base/models/image_model.h"
#include "ui/base/models/menu_model.h"
#import "ui/menus/cocoa/menu_controller.h"
#import "window_security_reservation.h"

@interface PCNativeExtensionMenuTarget : NSObject <NSUserInterfaceValidations>
- (instancetype)initWithItem:(NSMenuItem*)item
                  controller:(MenuControllerCocoa*)controller
                   canInvoke:(BOOL (^)(void))canInvoke;
- (void)itemSelected:(NSMenuItem*)item;
@end

@implementation PCNativeExtensionMenuTarget {
  __weak MenuControllerCocoa* _controller;
  SEL _originalAction;
  BOOL (^_canInvoke)(void);
  BOOL _invoked;
}
- (instancetype)initWithItem:(NSMenuItem*)item
                  controller:(MenuControllerCocoa*)controller
                   canInvoke:(BOOL (^)(void))canInvoke {
  if ((self = [super init])) {
    _controller = controller;
    _originalAction = item.action;
    _canInvoke = [canInvoke copy];
  }
  return self;
}
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  MenuControllerCocoa* controller = _controller;
  return !_invoked && controller && _canInvoke() &&
         [controller validateUserInterfaceItem:item];
}
- (void)itemSelected:(NSMenuItem*)item {
  __attribute__((objc_precise_lifetime)) PCNativeExtensionMenuTarget* keep =
      self;
  MenuControllerCocoa* controller = _controller;
  if (!_invoked && controller && _canInvoke() &&
      [controller validateUserInterfaceItem:item] && !item.hidden) {
    _invoked = YES;
    [NSApp sendAction:_originalAction to:controller from:item];
  }
  (void)keep;
}
@end

@interface PCNativeExtensionMenuBuilder : NSObject <MenuControllerCocoaDelegate>
@property(nonatomic, copy) void (^prepareItem)
    (NSMenuItem*, ui::MenuModel*, size_t);
@end
@implementation PCNativeExtensionMenuBuilder
@synthesize prepareItem = _prepareItem;
- (void)controllerWillAddItem:(NSMenuItem*)item
                    fromModel:(ui::MenuModel*)model
                      atIndex:(size_t)index {
  if (_prepareItem) {
    _prepareItem(item, model, index);
  }
}
- (void)controllerWillAddMenu:(NSMenu*)menu fromModel:(ui::MenuModel*)model {
}
@end

namespace parc {
namespace {
class ScopedModelUse final {
 public:
  explicit ScopedModelUse(const ExtensionActionViewModel& model)
      : model_(&model), acquired_(Models().insert(model_).second) {}
  ~ScopedModelUse() {
    if (acquired_) {
      Models().erase(model_);
    }
  }
  ScopedModelUse(const ScopedModelUse&) = delete;
  ScopedModelUse& operator=(const ScopedModelUse&) = delete;
  bool acquired() const { return acquired_; }

 private:
  static std::set<const ExtensionActionViewModel*>& Models() {
    static base::NoDestructor<std::set<const ExtensionActionViewModel*>> models;
    return *models;
  }
  const ExtensionActionViewModel* const model_;
  const bool acquired_;
};

NSString* DefaultUnavailableReason(int command) {
  using Model = extensions::ExtensionContextMenuModel;
  switch (command) {
    case Model::UNINSTALL:
      return @"Removing extensions is currently unavailable.";
    default:
      return nil;
  }
}

NSString* SidePanelUnavailableReason(BrowserWindowInterface* browser) {
  auto* panel = browser ? SidePanelUI::From(browser) : nullptr;
  if (!panel || !panel->UsesNativeExtensionContent()) {
    return @"Side panels are not available in this window.";
  }
  if (browser->GetType() == BrowserWindowInterface::TYPE_POPUP ||
      browser->GetType() == BrowserWindowInterface::TYPE_APP_POPUP) {
    return @"Side panels are not available in pop-up windows.";
  }
  return nil;
}

bool SidePanelLoading(BrowserWindowInterface* browser,
                      const std::string& extension_id) {
  auto* panel = browser ? SidePanelUI::From(browser) : nullptr;
  if (!panel || !panel->UsesNativeExtensionContent()) {
    return false;
  }
  const SidePanelEntryKey key(SidePanelEntryId::kExtension, extension_id);
  return panel->IsSidePanelEntryPending(key, false) ||
         panel->IsSidePanelEntryPending(key, true);
}

bool SupportedMenu(ui::MenuModel& model) {
  for (size_t i = 0; i < model.GetItemCount(); ++i) {
    switch (model.GetTypeAt(i)) {
      case ui::MenuModel::TYPE_COMMAND:
      case ui::MenuModel::TYPE_CHECK:
      case ui::MenuModel::TYPE_RADIO:
      case ui::MenuModel::TYPE_TITLE:
      case ui::MenuModel::TYPE_SEPARATOR:
        break;
      case ui::MenuModel::TYPE_SUBMENU: {
        auto* child = model.GetSubmenuModelAt(i);
        if (!child || !SupportedMenu(*child)) {
          return false;
        }
        break;
      }
      default:
        return false;
    }
    if (model.GetIconAt(i).IsImageGenerator()) {
      return false;
    }
  }
  return true;
}
}

class NativeExtensionContextMenu::Session final
    : public std::enable_shared_from_this<Session>,
      public TabListInterfaceObserver,
      public content::WebContentsObserver,
      public extensions::ExtensionRegistryObserver,
      public extensions::SecurityDialogTracker::Observer {
 public:
  Session(BrowserWindowInterface& browser,
          NativeExtensionActionHost& host,
          ExtensionActionViewModel& action,
          id<PCNativeMenuPresenter> app_presenter)
      : browser_(browser.GetWeakPtr()),
        shell_(&host),
        action_(&action),
        id_(action.GetId()),
        extension_(action.GetExtension()),
        window_(host.PopupParentWindow()),
        app_presenter_(app_presenter) {}
  ~Session() override { StopObserving(); }

  bool active() const { return active_; }
  bool Valid() const {
    if (cancelled_ || !shell_ || !browser_ || !extension_ || !window_ ||
        !window_.visible || !shell_->IsSelectedBrowser() ||
        shell_->HasVisibleBrowserSecurityUI() ||
        extensions::SecurityDialogTracker::GetInstance()
            ->BrowserHasVisibleSecurityDialogs(browser_.get()) ||
        PCNativeWindowHasSecurityReservation(window_) ||
        shell_->PopupParentWindow() != window_ || !browser_->GetWindow() ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_) {
      return false;
    }
    auto* container = ExtensionsContainer::From(*browser_);
    if (!container || container->GetActionForId(id_) != action_) {
      return false;
    }
    auto* registry = extensions::ExtensionRegistry::Get(browser_->GetProfile());
    if (!registry ||
        registry->enabled_extensions().GetByID(id_) != extension_.get()) {
      return false;
    }
    auto* tabs = TabListInterface::From(browser_.get());
    auto* current = tabs && tabs->GetActiveTab()
                        ? tabs->GetActiveTab()->GetContents()
                        : nullptr;
    return current && current == web_contents() &&
           current->GetBrowserContext() == browser_->GetProfile();
  }

  bool Run(extensions::ExtensionContextMenuModel::ContextMenuSource source) {
    auto keep = shared_from_this();
    base::AutoReset<bool> running(&active_, true);
    if (!browser_ || !shell_ || !extension_) {
      return false;
    }
    tabs_ = TabListInterface::From(browser_.get());
    if (!tabs_ || !tabs_->GetActiveTab()) {
      return false;
    }
    Observe(tabs_->GetActiveTab()->GetContents());
    if (!Valid()) {
      Observe(nullptr);
      return false;
    }
    tabs_->AddTabListInterfaceObserver(this);
    registry_ = extensions::ExtensionRegistry::Get(browser_->GetProfile());
    registry_->AddObserver(this);
    observing_ = true;
    extensions::SecurityDialogTracker::GetInstance()->AddObserver(this);
    auto* model = action_->GetContextMenu(source);
    if (!model || !SupportedMenu(*model)) {
      Cancel();
      return false;
    }
    model_ = model->AsWeakPtr();
    builder_ = [[PCNativeExtensionMenuBuilder alloc] init];
    targets_ = [[NSMutableArray alloc] init];
    std::weak_ptr<Session> weak = keep;
    builder_.prepareItem =
        ^(NSMenuItem* item, ui::MenuModel* item_model, size_t index) {
          if (auto state = weak.lock()) {
            state->PrepareItem(item, item_model, index);
          }
        };
    controller_ = [[MenuControllerCocoa alloc] initWithModel:model
                                               isContextMenu:YES
                                                    delegate:builder_];
    BindTargets(controller_.menu);
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    began_ = [center addObserverForName:NSMenuDidBeginTrackingNotification
                                 object:controller_.menu
                                  queue:nil
                             usingBlock:^(NSNotification*) {
                               if (auto state = weak.lock()) {
                                 state->opened_ = true;
                               }
                             }];
    closed_ = [center addObserverForName:NSWindowWillCloseNotification
                                  object:window_
                                   queue:nil
                              usingBlock:^(NSNotification*) {
                                if (auto state = weak.lock()) {
                                  state->Cancel();
                                }
                              }];
    security_ = [center addObserverForName:PCNativeWindowSecurityStateChanged
                                    object:window_
                                     queue:nil
                                usingBlock:^(NSNotification*) {
                                  if (auto state = weak.lock()) {
                                    state->StateChanged();
                                  }
                                }];
    if (!Valid() || !model_) {
      Cancel();
      return false;
    }
    bool opened;
    if (app_presenter_) {
      opened = [app_presenter_ presentMenu:controller_.menu];
    } else {
      NSView* root = window_.contentView;
      NSPoint point = [root
          convertPoint:[window_ convertPointFromScreen:NSEvent.mouseLocation]
              fromView:nil];
      [controller_.menu popUpMenuPositioningItem:nil
                                      atLocation:point
                                          inView:root];
      opened = opened_;
    }
    Cancel();
    return opened;
  }

  void Cancel() {
    auto keep = shared_from_this();
    if (cancelled_) {
      return;
    }
    cancelled_ = true;
    shell_ = nullptr;
    StopObserving();
    [controller_ cancel];
    [app_presenter_ cancelMenu];
  }
  void StateChanged() {
    if (!Valid()) {
      Cancel();
    }
  }

 private:
  NSString* UnavailableReason(int command) const {
    using Model = extensions::ExtensionContextMenuModel;
    if (command == Model::TOGGLE_SIDE_PANEL_VISIBILITY) {
      return SidePanelUnavailableReason(browser_.get());
    }
    if (command == Model::UNINSTALL && browser_ && extension_) {
      auto* host = NativeExtensionUninstallService::Get(
          browser_->GetUnownedUserDataHost());
      if (host && host->CanPresent(*extension_)) {
        return nil;
      }
    }
    return DefaultUnavailableReason(command);
  }
  struct Item {
    NSMenuItem* __weak native;
    base::WeakPtr<ui::MenuModel> model;
    size_t index;
    int command;
  };
  void PrepareItem(NSMenuItem* item, ui::MenuModel* model, size_t index) {
    if (model->GetTypeAt(index) == ui::MenuModel::TYPE_SUBMENU) {
      return;
    }
    const int command = model->GetCommandIdAt(index);
    item.toolTip = UnavailableReason(command);
    if (command ==
        extensions::ExtensionContextMenuModel::TOGGLE_SIDE_PANEL_VISIBILITY) {
      item.identifier = @"extension-menu:side-panel";
      if (SidePanelLoading(browser_.get(), id_)) {
        item.title = l10n_util::GetNSString(
            IDS_EXTENSIONS_SUBMENU_CLOSE_SIDE_PANEL_ITEM);
      }
    }
    items_.push_back({item, model->AsWeakPtr(), index, command});
  }
  void BindTargets(NSMenu*) {
    std::weak_ptr<Session> weak = shared_from_this();
    for (const auto& item : items_) {
      const auto model = item.model;
      const size_t index = item.index;
      const int command = item.command;
      auto* target = [[PCNativeExtensionMenuTarget alloc]
          initWithItem:item.native
            controller:controller_
             canInvoke:^BOOL {
               auto state = weak.lock();
               return state && state->active_ && state->Valid() &&
                      state->model_ && model && index < model->GetItemCount() &&
                      model->GetCommandIdAt(index) == command &&
                      !state->UnavailableReason(command);
             }];
      item.native.target = target;
      [targets_ addObject:target];
    }
  }
  void OnSecurityDialogAdded(views::Widget* widget) override {
    if (SecurityWidgetBelongsToWindow(widget, window_)) {
      Cancel();
    }
  }
  void StopObserving() {
    Observe(nullptr);
    if (observing_) {
      observing_ = false;
      extensions::SecurityDialogTracker::GetInstance()->RemoveObserver(this);
      if (tabs_) {
        tabs_->RemoveTabListInterfaceObserver(this);
      }
      if (registry_) {
        registry_->RemoveObserver(this);
      }
    }
    tabs_ = nullptr;
    registry_ = nullptr;
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    if (security_) {
      [center removeObserver:security_];
      security_ = nil;
    }
    if (began_) {
      [center removeObserver:began_];
      began_ = nil;
    }
    if (closed_) {
      [center removeObserver:closed_];
      closed_ = nil;
    }
  }
  void OnActiveTabChanged(TabListInterface&, tabs::TabInterface*) override {
    Cancel();
  }
  void OnAllTabsAreClosing(TabListInterface&) override { Cancel(); }
  void OnTabRemoved(TabListInterface&,
                    tabs::TabInterface* tab,
                    TabRemovedReason) override {
    if (tab && tab->GetContents() == web_contents()) {
      Cancel();
    }
  }
  void OnWebContentsReplaced(TabListInterface&,
                             tabs::TabInterface*,
                             content::WebContents* old_contents,
                             content::WebContents*) override {
    if (old_contents == web_contents()) {
      Cancel();
    }
  }
  void OnTabListDestroyed(TabListInterface&) override {
    tabs_ = nullptr;
    Cancel();
  }
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && !handle->IsSameDocument()) {
      Cancel();
    }
  }
  void WebContentsDestroyed() override { Cancel(); }
  void OnExtensionUnloaded(content::BrowserContext*,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason) override {
    if (extension == extension_.get()) {
      Cancel();
    }
  }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    registry_ = nullptr;
    Cancel();
  }
  base::WeakPtr<BrowserWindowInterface> browser_;
  NativeExtensionActionHost* shell_;
  ExtensionActionViewModel* action_;
  const std::string id_;
  scoped_refptr<const extensions::Extension> extension_;
  NSWindow* __weak window_;
  id<PCNativeMenuPresenter> __strong app_presenter_;
  TabListInterface* tabs_ = nullptr;
  extensions::ExtensionRegistry* registry_ = nullptr;
  bool observing_ = false;
  bool active_ = false;
  bool cancelled_ = false;
  bool opened_ = false;
  base::WeakPtr<ui::MenuModel> model_;
  MenuControllerCocoa* __strong controller_;
  PCNativeExtensionMenuBuilder* __strong builder_;
  NSMutableArray* __strong targets_;
  std::vector<Item> items_;
  id __strong began_;
  id __strong closed_;
  id __strong security_;
};

struct NativeExtensionContextMenu::RunState {
  bool running = false;
  bool stopping = false;
  size_t cancel_depth = 0;
  std::vector<base::OnceClosure> completions;
  void MaybeComplete() {
    if (running || cancel_depth) {
      return;
    }
    auto callbacks = std::move(completions);
    for (auto& callback : callbacks) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
          FROM_HERE, std::move(callback));
    }
  }
  void DidReturn() {
    CHECK(running);
    running = false;
    MaybeComplete();
  }
};

NativeExtensionContextMenu::NativeExtensionContextMenu(
    BrowserWindowInterface& browser,
    NativeExtensionActionHost& host)
    : browser_(browser),
      host_(host),
      run_state_(std::make_shared<RunState>()) {}
NativeExtensionContextMenu::~NativeExtensionContextMenu() {
  Cancel();
}
bool NativeExtensionContextMenu::Show(
    ExtensionActionViewModel& model,
    id<PCNativeMenuPresenter> app_presenter,
    extensions::ExtensionContextMenuModel::ContextMenuSource source) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (run_state_->stopping || (session_ && session_->active())) {
    return false;
  }
  auto state = run_state_;
  CHECK(!state->running);
  state->running = true;
  base::ScopedClosureRunner returned(base::BindOnce(
      [](std::shared_ptr<RunState> state) { state->DidReturn(); }, state));
  ScopedModelUse model_use(model);
  if (!model_use.acquired()) {
    return false;
  }
  session_ = std::make_shared<Session>(browser_, host_, model, app_presenter);
  auto keep = session_;
  return keep->Run(source);
}
void NativeExtensionContextMenu::Cancel() {
  if (auto keep = session_) {
    keep->Cancel();
  }
}
void NativeExtensionContextMenu::CancelAndWait(base::OnceClosure ready) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto state = run_state_;
  state->stopping = true;
  if (ready) {
    state->completions.push_back(std::move(ready));
  }
  ++state->cancel_depth;
  Cancel();
  CHECK(state->cancel_depth);
  --state->cancel_depth;
  state->MaybeComplete();
}
void NativeExtensionContextMenu::HostStateChanged() {
  if (auto keep = session_) {
    keep->StateChanged();
  }
}
}
