// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_EXTENSION_ACTION_BRIDGE_H_
#define PARC_NATIVE_EXTENSION_ACTION_BRIDGE_H_
#include <map>
#include <memory>
#include <string>

#include "base/callback_list.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/scoped_observation.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "extensions/browser/extension_registry_observer.h"
#import "native_appkit_bridge.h"

class BrowserWindowInterface;
class ExtensionActionViewModel;
namespace extensions { class Extension; }
namespace gfx { class Image; }
namespace tabs { class TabInterface; }
namespace parc {
class NativeExtensionActionContainer;
struct NativeExtensionActionToken;
// Browser-owned, above genuine model/controller objects. Queries supplied by
// the shell must be side-effect-free and validate the actual attached page.
// BeginShutdown prevents new operations immediately; Shutdown reports ready
// only after every synchronous model dispatch scope has actually unwound.
class NativeExtensionActionBridge final : public content::WebContentsObserver,
                                          public extensions::ExtensionRegistryObserver {
 public:
  NativeExtensionActionBridge(
      BrowserWindowInterface&,
      NativeExtensionActionContainer&,
      base::RepeatingCallback<bool(content::WebContents&)> validate,
      base::RepeatingClosure changed);
  ~NativeExtensionActionBridge() override;
  NSArray<PCNativeExtensionAction*>* Snapshot(content::WebContents&,
                                              NSString* page_id,
                                              NSString* profile_path);
  bool HasEnabledExtensions(content::WebContents&) const;
  NSArray<PCNativeEnabledExtension*>* EnabledSnapshot(content::WebContents&);
  bool ExecuteEnabled(PCNativeEnabledExtension*, content::WebContents&);
  bool ShowEnabledContextMenu(PCNativeEnabledExtension*, content::WebContents&);
  bool Execute(PCNativeExtensionAction*,
               content::WebContents&,
               bool menu_entry = false);
  bool ShowContextMenu(PCNativeExtensionAction*,
                       content::WebContents&,
                       id<PCNativeMenuPresenter> presenter = nil);
  bool SetPinned(PCNativeExtensionAction*, content::WebContents&, bool);
  // Called after real model/icon/pin or selected-page ownership changes.
  void Changed();
  void BeginShutdown();
  void Shutdown(base::OnceClosure);

 private:
  struct DispatchState;
  class Operation;
  std::shared_ptr<ExtensionActionViewModel> Validate(
      PCNativeExtensionAction*,
      content::WebContents&) const;
  bool ValidPage(content::WebContents&) const;
  std::shared_ptr<ExtensionActionViewModel> ValidateEnabled(
      PCNativeEnabledExtension*, content::WebContents&) const;
  void ManifestIconLoaded(std::string, uint64_t,
                          base::WeakPtr<tabs::TabInterface>,
                          content::WeakDocumentPtr, const gfx::Image&);
  void SyncObservers();
  void DeliverChanged();
  void DidFinishNavigation(content::NavigationHandle*) override;
  void TitleWasSet(content::NavigationEntry*) override;
  void WebContentsDestroyed() override;
  void OnExtensionLoaded(content::BrowserContext*, const extensions::Extension*) override;
  void OnExtensionUnloaded(content::BrowserContext*, const extensions::Extension*,
                           extensions::UnloadedExtensionReason) override;
  void OnShutdown(extensions::ExtensionRegistry*) override;
  BrowserWindowInterface& browser_;
  NativeExtensionActionContainer& container_;
  base::RepeatingCallback<bool(content::WebContents&)> validate_;
  base::RepeatingClosure changed_;
  struct IconObservation {
    std::weak_ptr<ExtensionActionViewModel> model;
    base::CallbackListSubscription subscription;
  };
  std::map<std::string, IconObservation> icons_;
  struct ManifestIcon {
    scoped_refptr<const extensions::Extension> extension;
    uint64_t request;
    NSImage* __strong image = nil;
  };
  std::map<std::string, ManifestIcon> manifest_icons_;
  uint64_t next_icon_request_ = 0;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
  std::shared_ptr<DispatchState> dispatch_;
  uint64_t generation_ = 1;
  bool stopped_ = false;
  bool change_posted_ = false;
  base::WeakPtrFactory<NativeExtensionActionBridge> weak_factory_{this};
};
}  // namespace parc
#endif
