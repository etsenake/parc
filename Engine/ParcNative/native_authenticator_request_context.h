// Copyright 2026 Parc contributors.
// Typed, optional native embedding boundary. Default Chrome behavior is intact.
#ifndef CHROME_BROWSER_WEBAUTHN_NATIVE_AUTHENTICATOR_REQUEST_CONTEXT_H_
#define CHROME_BROWSER_WEBAUTHN_NATIVE_AUTHENTICATOR_REQUEST_CONTEXT_H_
#include <memory>

#include "base/memory/weak_ptr.h"
#include "base/supports_user_data.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/native_ui_types.h"
class AuthenticatorRequestDialogViewController;
class ChromeAuthenticatorRequestDelegate;
struct AuthenticatorRequestDialogModel;
namespace content {
class RenderFrameHost;
}
namespace ambient_signin {
class AmbientSigninController;
}
// Owns only the native presentation lease. Chromium retains the recovery
// Browser, WebContents, navigations, RAPT/reset observers and model callbacks.
class NativeAuthenticatorRequestWindow {
 public:
  virtual ~NativeAuthenticatorRequestWindow() = default;
  virtual bool IsValid() const = 0;
  virtual bool Attach(content::WebContents&, gfx::NativeWindow) = 0;
  virtual void Cancel() = 0;
};
class NativeAuthenticatorRequestContext : public base::SupportsUserData::Data {
 public:
  static NativeAuthenticatorRequestContext* Get(
      content::WebContents* contents) {
    return contents ? static_cast<NativeAuthenticatorRequestContext*>(
                          contents->GetUserData(kKey))
                    : nullptr;
  }
  static void Set(content::WebContents& contents,
                  std::unique_ptr<NativeAuthenticatorRequestContext> context) {
    contents.SetUserData(kKey, std::move(context));
  }
  virtual void Created(content::RenderFrameHost&,
                       base::WeakPtr<ChromeAuthenticatorRequestDelegate>) = 0;
  virtual void Ready(base::WeakPtr<ChromeAuthenticatorRequestDelegate>) = 0;
  virtual gfx::NativeWindow AuthenticatorWindow(
      base::WeakPtr<ChromeAuthenticatorRequestDelegate>) = 0;
  virtual bool BeginSettings(content::RenderFrameHost&,
                             AuthenticatorRequestDialogModel&) = 0;
  virtual void PrepareForStepChange(AuthenticatorRequestDialogModel&) = 0;
  virtual std::unique_ptr<NativeAuthenticatorRequestWindow> CreateWindow(
      AuthenticatorRequestDialogModel&) = 0;
  virtual void ShowAmbient(
      AuthenticatorRequestDialogModel&,
      base::WeakPtr<ambient_signin::AmbientSigninController>) = 0;
  virtual void HideAmbient() = 0;
  virtual std::unique_ptr<AuthenticatorRequestDialogViewController>
  CreateDialog(AuthenticatorRequestDialogModel&) = 0;

 private:
  inline static constexpr char kKey[] = "native-authenticator-request-context";
};
#endif
