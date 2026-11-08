// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_APPKIT_HOST_H_
#define PARC_NATIVE_NATIVE_APPKIT_HOST_H_
#include <memory>

#include "base/functional/callback.h"
#include "cef/include/cef_app.h"
#include "cef/include/cef_request_context.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#import "native_appkit_bridge.h"
namespace input {
struct NativeWebKeyboardEvent;
}
namespace content {
class WebContents;
}
class BrowserFocusController;
class DevtoolsUIController;
class Profile;
namespace parc {
// Uses the application-owned exact-path registry and retains its genuine CEF
// context through callback delivery; never creates an independent Profile.
CefRefPtr<CefRequestContext> NativeContextForProfile(Profile& profile);
// Exact private identity of an existing native owner; never resolves a path to normal.
Profile* NativePrivateProfileForWindow(PCNativeBrowserWindow*, NSString* path);
void WithNativeProfile(NSString* path,
    base::OnceCallback<void(Profile*, CefRefPtr<CefRequestContext>, NSError*)> callback);
// Materialize only an empty real Browser in an already-prepared exact native
// window. Original request execution remains in BrowserWebContentsDelegate.
void WithNativeRoutingBrowser(PCNativeBrowserWindow* binding, NSString* path,
    base::OnceCallback<void(BrowserWindowInterface*, bool, NSError*)> callback);
void AbandonEmptyNativeRoutingWindow(PCNativeBrowserWindow* binding);
class NativeBrowserWindowHost;
class NativeWindowProvider;
std::unique_ptr<NativeBrowserWindowHost> CreateAppKitBrowserHost(
    BrowserWindowInterface&,
    PCNativeBrowserWindow*,
    NSString* profile_path);
std::unique_ptr<BrowserFocusController> CreateAppKitFocusController(
    BrowserWindowInterface&);
std::unique_ptr<DevtoolsUIController> CreateAppKitDevtoolsController(
    BrowserWindowInterface&);
bool HandleAppKitDevtoolsKey(content::WebContents*,
                             content::WebContents&,
                             const input::NativeWebKeyboardEvent&);
// True means the actual DevTools controller accepted the request, not that its
// asynchronously loaded frontend is already visible. Policy refusal is false.
bool RequestAppKitDevtools(content::WebContents&);
// Exact external shell container, never the native page's interior superview.
NSView* AppKitPageContainer(BrowserWindowInterface&, PCNativePage*);
void AppKitPageOwnerChanged(BrowserWindowInterface*, content::WebContents&);
void SynchronizeAppKitBrowser(BrowserWindowInterface&);
// Applies the shell's current page visibility now, for a shell request made
// after it rearranged its panes. It may run inside a TabStripModel change
// (closing a Peek reaches it), so it only reads the tab strip.
void SynchronizeAppKitBrowserVisibility(BrowserWindowInterface&);
void SetAppKitWebsiteTheme(BrowserWindowInterface&, NSString* stylesheet);
bool AttachAppKitPage(BrowserWindowInterface&, PCNativePage*, NSView*);
void DetachAppKitPage(BrowserWindowInterface&, PCNativePage*);
bool ParkAppKitPage(BrowserWindowInterface&, PCNativePage*);
void ReportAppKitPageFrame(BrowserWindowInterface&, PCNativePage*);
void PrepareAppKitBrowserForDeletion(BrowserWindowInterface&,
                                     base::OnceClosure);
void RequestAppKitBrowserClose(BrowserWindowInterface&);
bool AppKitBrowserAcceptsNewPages(BrowserWindowInterface&);
PCNativeBrowserWindow* AppKitBindingForBrowser(const BrowserWindowInterface*);
std::shared_ptr<NativeWindowProvider> CreateAppKitWindowProvider();
CefRefPtr<CefApp> CreateNativeApplication();
void PrepareNativeApplicationShutdown();
bool HasPendingNativeApplicationWork();
bool HasLoadingNativeProfiles();
// Used only by the application-owned window coordinator. Browser references
// are removed synchronously before adapter teardown can run external callbacks.
void RegisterAppKitBrowser(PCNativeBrowserWindow*, BrowserWindowInterface&);
void UnregisterAppKitBrowser(PCNativeBrowserWindow*, BrowserWindowInterface&);
void AppKitBrowserCloseResult(PCNativeBrowserWindow*,
                              BrowserWindowInterface&,
                              bool approved);
}  // namespace parc
#endif
