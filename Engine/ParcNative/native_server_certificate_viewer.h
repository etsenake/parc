// Copyright 2026 Parc contributors.
#ifndef CHROME_BROWSER_NATIVE_SERVER_CERTIFICATE_VIEWER_H_
#define CHROME_BROWSER_NATIVE_SERVER_CERTIFICATE_VIEWER_H_
#include <memory>

#include "base/supports_user_data.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/native_ui_types.h"
namespace net {
class X509Certificate;
}
// An installed native route handles even a refusal. It must never fall back to
// an unrelated Views window when its page is detached or stale.
class NativeServerCertificateViewer : public base::SupportsUserData::Data {
 public:
  static NativeServerCertificateViewer* Get(content::WebContents* contents) {
    return contents ? static_cast<NativeServerCertificateViewer*>(
                          contents->GetUserData(kKey))
                    : nullptr;
  }
  static void Set(content::WebContents& contents,
                  std::unique_ptr<NativeServerCertificateViewer> viewer) {
    contents.SetUserData(kKey, std::move(viewer));
  }
  virtual void Show(content::WebContents&,
                    gfx::NativeWindow,
                    net::X509Certificate*) = 0;

 private:
  inline static constexpr char kKey[] = "native-server-certificate-viewer";
};
#endif
