// Copyright 2026 Parc contributors.
#include "native_page_retirement.h"

#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/tabs/public/tab_interface.h"
#include "native_appkit_host.h"
#include "native_appkit_page.h"
#include "native_engine_entry.h"
#include "tab_retirement.h"

namespace parc {
bool HasNativePageRetirementWork() {
  return HasTabRetirementWork();
}
bool IsNativePageRetiring(PCNativePage* page) {
  return IsTabRetiring(ContentsForNativePage(page));
}
}  // namespace parc

@implementation PCNativeBrowserApplication (PageRetirement)
+ (void)requestClosePages:(NSArray<PCNativePage*>*)pages
             shouldCommit:(BOOL (^)(void))shouldCommit
               completion:(void (^)(BOOL))completion {
  CHECK(NSThread.isMainThread);
  CHECK(completion && shouldCommit);
  if (parc::HasPendingNativeApplicationWork()) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(NO);
    });
    return;
  }
  NSArray<PCNativePage*>* requested = [pages copy];
  NSMutableArray<PCNativeBrowserWindow*>* bindings = [NSMutableArray array];
  std::vector<content::WebContents*> contents;
  for (PCNativePage* page in requested) {
    auto* value = parc::ContentsForNativePage(page);
    auto* tab =
        value ? tabs::TabInterface::MaybeGetFromContents(value) : nullptr;
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    auto* binding = parc::AppKitBindingForBrowser(browser);
    if (!value || !browser || !binding || !binding.window ||
        page.nativeView.window != binding.window ||
        !parc::AppKitBrowserAcceptsNewPages(*browser)) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(NO);
      });
      return;
    }
    [bindings addObject:binding];
    contents.push_back(value);
  }
  parc::RequestTabRetirement(
      std::move(contents), base::BindRepeating(^bool {
        for (NSUInteger index = 0; index < requested.count; ++index) {
          PCNativePage* page = requested[index];
          auto* value = parc::ContentsForNativePage(page);
          auto* tab =
              value ? tabs::TabInterface::MaybeGetFromContents(value) : nullptr;
          auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
          PCNativeBrowserWindow* binding = bindings[index];
          if (!value || !browser || !binding.window ||
              parc::AppKitBindingForBrowser(browser) != binding ||
              page.nativeView.window != binding.window) {
            return false;
          }
        }
        return true;
      }),
      base::BindOnce(^bool {
        return shouldCommit();
      }),
      base::BindOnce(^(bool success) {
        completion(success);
        parc::NotifyNativeEngineOwnershipChanged();
      }));
}
@end
