// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_WEBSITE_THEME_H_
#define PARC_NATIVE_NATIVE_WEBSITE_THEME_H_

#include <optional>
#include <string>

#include "base/functional/callback.h"
#include "base/unguessable_token.h"
#include "parc/common/mojom/parc_theme.mojom.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/weak_document_ptr.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "third_party/blink/public/common/tokens/tokens.h"

namespace parc {
// Owned by one actual attached/parked AppKit PageBinding, never selected-page
// state. Detachment destroys this lease before the page can change windows.
class NativeWebsiteTheme final : public content::WebContentsObserver {
 public:
  NativeWebsiteTheme(content::WebContents&, base::RepeatingCallback<bool()>);
  ~NativeWebsiteTheme() override;
  void SetStylesheet(const std::string&);

 private:
  void Publish();
  void Revoke();
  void PrimaryPageChanged(content::Page&) override;
  void PrimaryPageWillBeDeactivated(content::Page&) override;
  void RenderFrameCreated(content::RenderFrameHost*) override;
  void DidFinishNavigation(content::NavigationHandle*) override;
  void WebContentsDestroyed() override;

  const base::UnguessableToken owner_ = base::UnguessableToken::Create();
  base::RepeatingCallback<bool()> valid_owner_;
  std::string stylesheet_;
  // Last stylesheet bytes actually sent on the current live document/channel.
  // Distinct from stylesheet_, which can be assigned before a successful
  // publish (and after revoke/rebind, which must send again).
  std::optional<std::string> published_stylesheet_;
  content::WeakDocumentPtr document_;
  std::optional<blink::DocumentToken> document_token_;
  mojo::AssociatedRemote<mojom::WebsiteThemeAgent> remote_;
};
}  // namespace parc
#endif
