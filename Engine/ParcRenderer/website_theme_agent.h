// Copyright 2026 Parc contributors.
#ifndef PARC_RENDERER_WEBSITE_THEME_AGENT_H_
#define PARC_RENDERER_WEBSITE_THEME_AGENT_H_

#include <optional>
#include <string>

#include "base/unguessable_token.h"
#include "parc/common/mojom/parc_theme.mojom.h"
#include "content/public/renderer/render_frame_observer.h"
#include "mojo/public/cpp/bindings/associated_receiver_set.h"
#include "third_party/blink/public/common/tokens/tokens.h"

namespace parc {
// Self-owned for the lifetime of the original RenderFrame. Only a browser-side
// PageBinding publishes; unowned frames never receive a stylesheet.
class WebsiteThemeAgent final : public content::RenderFrameObserver,
                                public mojom::WebsiteThemeAgent {
 public:
  explicit WebsiteThemeAgent(content::RenderFrame*);
  ~WebsiteThemeAgent() override;

 private:
  void Bind(mojo::PendingAssociatedReceiver<mojom::WebsiteThemeAgent>);
  void SetTheme(const blink::DocumentToken&, const base::UnguessableToken&,
                const std::string&) override;
  void RemoveTheme(const blink::DocumentToken&,
                   const base::UnguessableToken&) override;
  void Apply();
  void DidCreateNewDocument() override;
  void DidCreateDocumentElement() override;
  void OnDestruct() override;

  mojo::AssociatedReceiverSet<mojom::WebsiteThemeAgent> receivers_;
  std::optional<blink::DocumentToken> document_;
  std::optional<base::UnguessableToken> owner_;
  std::string stylesheet_;
};
}  // namespace parc
#endif
