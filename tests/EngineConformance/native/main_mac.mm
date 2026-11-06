// Copyright 2026 Parc contributors.
// Uses the upstream CEF macOS application/message-loop contract.
#import <AppKit/AppKit.h>

#include <cstdio>
#include <list>
#include <string>
#include <utility>
#include <unistd.h>

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

class HostClient final : public CefClient, public CefLifeSpanHandler {
 public:
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    CHECK_EQ(browser->GetHost()->GetRuntimeStyle(), CEF_RUNTIME_STYLE_CHROME);
    browsers_.push_back(browser);
    std::fprintf(stdout, "parc-native-host created cefBrowserId=%d\n",
                 browser->GetIdentifier());
    std::fflush(stdout);
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    browsers_.remove_if([&browser](const CefRefPtr<CefBrowser>& candidate) {
      return candidate->IsSame(browser);
    });
    std::fprintf(stdout, "parc-native-host closed cefBrowserId=%d remaining=%zu\n",
                 browser->GetIdentifier(), browsers_.size());
    std::fflush(stdout);
    if (browsers_.empty()) {
      CefQuitMessageLoop();
    }
  }

  void RequestQuit() {
    CEF_REQUIRE_UI_THREAD();
    // CloseBrowser(false) uses each real tab's native consent path. Copy first:
    // close callbacks can mutate browsers_. A cancelled tab keeps the loop alive.
    const auto pending = browsers_;
    for (const auto& browser : pending) {
      browser->GetHost()->CloseBrowser(false);
    }
  }

 private:
  std::list<CefRefPtr<CefBrowser>> browsers_;
  IMPLEMENT_REFCOUNTING(HostClient);
};

class HostApp final : public CefApp, public CefBrowserProcessHandler {
 public:
  HostApp(CefRefPtr<HostClient> client, std::string initial_url)
      : client_(client), initial_url_(std::move(initial_url)) {}

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }
  CefRefPtr<CefClient> GetDefaultClient() override { return client_; }

  void OnContextInitialized() override {
    CEF_REQUIRE_UI_THREAD();
    CefWindowInfo window_info;
    window_info.runtime_style = CEF_RUNTIME_STYLE_CHROME;
    // No parent_view and no CefBrowserView: real Chrome BrowserWindow ownership.
    CefBrowserSettings browser_settings;
    auto extra = CefDictionaryValue::Create();
    extra->SetBool("parc.native_host.v1", true);
    CHECK(CefBrowserHost::CreateBrowser(window_info, client_, initial_url_,
                                        browser_settings, extra, nullptr));
  }

 private:
  const CefRefPtr<HostClient> client_;
  const std::string initial_url_;
  IMPLEMENT_REFCOUNTING(HostApp);
};

}  // namespace

@interface ParcHostApplicationDelegate : NSObject <NSApplicationDelegate>
- (instancetype)initWithClient:(CefRefPtr<HostClient>)client;
- (void)requestQuit;
@end

@interface ParcHostApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end

@implementation ParcHostApplication
@synthesize handlingSendEvent = _handlingSendEvent;
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent sending_event;
  [super sendEvent:event];
}
- (void)terminate:(id)sender {
  [(ParcHostApplicationDelegate*)self.delegate requestQuit];
}
@end

@implementation ParcHostApplicationDelegate {
  CefRefPtr<HostClient> _client;
}
- (instancetype)initWithClient:(CefRefPtr<HostClient>)client {
  self = [super init];
  if (self) _client = client;
  return self;
}
- (void)requestQuit { _client->RequestQuit(); }
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication*)application {
  return YES;
}
@end

int main(int argc, char* argv[]) {
  @autoreleasepool {
    std::string profile_argument;
    for (int index = 1; index < argc; ++index) {
      const std::string argument(argv[index]);
      constexpr char prefix[] = "--parc-profile=";
      if (argument.starts_with(prefix)) {
        if (!profile_argument.empty()) {
          std::fprintf(stderr, "Repeated --parc-profile is not permitted.\n");
          return 2;
        }
        profile_argument = argument.substr(sizeof(prefix) - 1);
      }
    }
    NSString* profile = [NSString stringWithUTF8String:profile_argument.c_str()];
    NSFileManager* files = [NSFileManager defaultManager];
    NSDictionary* attributes = [files attributesOfItemAtPath:profile error:nil];
    NSString* marker_path =
        [profile stringByAppendingPathComponent:@".parc-native-host-profile"];
    NSDictionary* marker_attributes =
        [files attributesOfItemAtPath:marker_path error:nil];
    NSString* marker = [NSString stringWithContentsOfFile:marker_path
        encoding:NSUTF8StringEncoding error:nil];
    if (!profile.isAbsolutePath ||
        ![profile isEqualToString:profile.stringByStandardizingPath] ||
        ![profile isEqualToString:profile.stringByResolvingSymlinksInPath] ||
        ![attributes[NSFileType] isEqual:NSFileTypeDirectory] ||
        [attributes[NSFileOwnerAccountID] unsignedIntValue] != getuid() ||
        [attributes[NSFilePosixPermissions] unsignedIntegerValue] != 0700 ||
        ![marker_attributes[NSFileType] isEqual:NSFileTypeRegular] ||
        [marker_attributes[NSFileOwnerAccountID] unsignedIntValue] != getuid() ||
        ![marker isEqualToString:@"Parc native host fixture profile v1\n"]) {
      std::fprintf(stderr,
          "Use launch.py with a new disposable profile; refusing an unowned profile.\n");
      return 2;
    }

    // Same dynamic-loader/helper contract as upstream CEF on macOS. Never call
    // a CEF function before LoadInMain succeeds and never bypass the sandbox.
    CefScopedLibraryLoader library_loader;
    if (!library_loader.LoadInMain()) return 1;
    CefRefPtr<CefCommandLine> command = CefCommandLine::CreateCommandLine();
    command->InitFromArgv(argc, argv);
    std::string initial_url = command->GetSwitchValue("url");
    if (initial_url.empty()) initial_url = "about:blank";

    [ParcHostApplication sharedApplication];
    CHECK([NSApp isKindOfClass:[ParcHostApplication class]]);
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Parc Host"];
    NSMenuItem* application_item = [[NSMenuItem alloc] initWithTitle:@"Parc Host"
                                                            action:NULL keyEquivalent:@""];
    NSMenu* application_menu = [[NSMenu alloc] initWithTitle:@"Parc Host"];
    [application_menu addItemWithTitle:@"Quit Parc Host" action:@selector(terminate:)
                        keyEquivalent:@"q"];
    application_item.submenu = application_menu;
    [menu addItem:application_item];
    NSMenuItem* edit_item = [[NSMenuItem alloc] initWithTitle:@"Edit"
                                                    action:NULL keyEquivalent:@""];
    NSMenu* edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    edit_item.submenu = edit;
    [menu addItem:edit_item];
    NSApp.mainMenu = menu;

    CefSettings settings;
#if !defined(CEF_USE_SANDBOX)
#error The Parc native host harness requires the normal CEF macOS sandbox.
#endif
    settings.no_sandbox = false;
    const std::string engine_path = profile_argument + "/ChromiumData";
    CefString(&settings.root_cache_path) = engine_path;
    CefString(&settings.cache_path) = engine_path;
    CefString(&settings.log_file) = profile_argument + "/chromium.log";
    CefString(&settings.keychain_service_name) = "Parc Native Host Safe Storage";
    CefString(&settings.keychain_account_name) = "Parc Native Host";

    CefRefPtr<HostClient> client(new HostClient);
    CefRefPtr<HostApp> app(new HostApp(client, initial_url));
    ParcHostApplicationDelegate* delegate =
        [[ParcHostApplicationDelegate alloc] initWithClient:client];
    NSApp.delegate = delegate;
    CefMainArgs main_args(argc, argv);
    if (!CefInitialize(main_args, settings, app, nullptr)) {
      return CefGetExitCode();
    }
    [NSApp activateIgnoringOtherApps:YES];
    CefRunMessageLoop();
    // This is reached only after actual close callbacks remove the last page.
    CefShutdown();
    NSApp.delegate = nil;
  }
  return 0;
}
