// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_APPKIT_HOST_H_
#define PARC_NATIVE_NATIVE_APPKIT_HOST_H_
#include <memory>
#include <optional>

#include <string>

#include "base/functional/callback.h"
#include "base/types/expected.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#import "native_appkit_bridge.h"
#include "native_profiles.h"
#include "ui/base/resource/resource_bundle.h"
namespace base {
class CommandLine;
class FilePath;
}
namespace input {
struct NativeWebKeyboardEvent;
}
namespace content {
class WebContents;
}
namespace ui {
class BaseWindow;
}
class BrowserFocusController;
class DevtoolsUIController;
class Profile;
class SessionID;
namespace parc {
struct NativeWindowRequest;
class PreparedNativeWindow;
// Exact private identity of an existing native owner; never resolves a path to normal.
Profile* NativePrivateProfileForWindow(PCNativeBrowserWindow*, NSString* path);
// Materialize only an empty real Browser in an already-prepared exact native
// window. Original request execution remains in BrowserWebContentsDelegate.
void WithNativeRoutingBrowser(PCNativeBrowserWindow* binding, NSString* path,
    base::OnceCallback<void(BrowserWindowInterface*, bool, NSError*)> callback);
void AbandonEmptyNativeRoutingWindow(PCNativeBrowserWindow* binding);
class NativeBrowserWindowHost;
// The shell's one-use window for this request, or why it refused one.
base::expected<std::unique_ptr<PreparedNativeWindow>, std::string>
PrepareAppKitWindow(const NativeWindowRequest& request);
// Exact application error path for a refused native Browser creation.
void NativeCreationFailed(Profile& profile, const std::string& reason);
std::unique_ptr<NativeBrowserWindowHost> CreateAppKitBrowserHost(
    BrowserWindowInterface&,
    PCNativeBrowserWindow*,
    NSString* profile_path);
std::unique_ptr<BrowserFocusController> CreateAppKitFocusController(
    BrowserWindowInterface&);
bool RotateAppKitPaneFocus(ui::BaseWindow*, bool forward);
// The controller and the hooks that give it Parc's presentation; a controller
// made elsewhere gets none.
std::unique_ptr<DevtoolsUIController> CreateAppKitDevtoolsController(
    BrowserWindowInterface&);
std::optional<bool> UpdateAppKitDevtools(DevtoolsUIController&,
                                         content::WebContents*,
                                         bool update_contents);
bool SetAppKitDevtoolsScrim(DevtoolsUIController&,
                            content::WebContents* tools,
                            bool visible);
void TearDownAppKitDevtools(DevtoolsUIController&);
bool HandleAppKitDevtoolsKey(content::WebContents*,
                             content::WebContents&,
                             const input::NativeWebKeyboardEvent&);
// True means the actual DevTools controller accepted the request, not that its
// asynchronously loaded frontend is already visible. Policy refusal is false.
bool RequestAppKitDevtools(content::WebContents&);
// Exact external shell container, never the native page's interior superview.
NSView* AppKitPageContainer(BrowserWindowInterface&, PCNativePage*);
void AppKitPageOwnerChanged(BrowserWindowInterface*, content::WebContents&);
// An Easel-owned page keeps its real tab and window identity but is never
// recorded for session or tab restore.
bool IsSessionOmittedFromRestore(SessionID session_id);
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
// The startup runner owns this for the whole session, on the main thread.
class NativeApplication {
 public:
  virtual ~NativeApplication() = default;
  // ConfigureNativeProfiles' initializer and change notification.
  virtual void ProfileInitializer(Profile& profile) = 0;
  virtual void ProfilesChanged() = 0;
  // Product branding; exists before content startup.
  virtual ui::ResourceBundle::Delegate* ResourceBundleDelegate() = 0;
  // The process-singleton handoff. the legacy result is ignored; native launches are always consumed, also while quitting.
  virtual bool AlreadyRunningRelaunch(const base::CommandLine& command_line,
                                      const base::FilePath& current_directory) = 0;
  // Browser startup finished with Chrome's initial Profile.
  virtual void BrowserReady(Profile& initial_profile) = 0;
};
std::unique_ptr<NativeApplication> CreateNativeApplication();
void PrepareNativeApplicationShutdown();
bool HasPendingNativeApplicationWork();
// Used only by the application-owned window coordinator. Browser references
// are removed synchronously before adapter teardown can run external callbacks.
void RegisterAppKitBrowser(PCNativeBrowserWindow*, BrowserWindowInterface&);
void UnregisterAppKitBrowser(PCNativeBrowserWindow*, BrowserWindowInterface&);
void AppKitBrowserCloseResult(PCNativeBrowserWindow*,
                              BrowserWindowInterface&,
                              bool approved);
}  // namespace parc
#endif
