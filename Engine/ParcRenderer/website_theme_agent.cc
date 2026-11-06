// Copyright 2026 Parc contributors.
#include "cef/libcef/renderer/website_theme_agent.h"

#include <utility>

#include "base/functional/bind.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"

namespace parc {
namespace {
blink::WebString StyleKey() { return blink::WebString::FromAscii("__parc_theme_css"); }
}  // namespace
WebsiteThemeAgent::WebsiteThemeAgent(content::RenderFrame* frame)
    : content::RenderFrameObserver(frame) {
  frame->GetAssociatedInterfaceRegistry()->AddInterface<mojom::WebsiteThemeAgent>(
      base::BindRepeating(&WebsiteThemeAgent::Bind, base::Unretained(this)));
}
WebsiteThemeAgent::~WebsiteThemeAgent() = default;
void WebsiteThemeAgent::Bind(
    mojo::PendingAssociatedReceiver<mojom::WebsiteThemeAgent> receiver) {
  receivers_.Add(this, std::move(receiver));
}
void WebsiteThemeAgent::SetTheme(const blink::DocumentToken& token,
                                const base::UnguessableToken& owner,
                                const std::string& stylesheet) {
  auto document = render_frame()->GetWebFrame()->GetDocument();
  if (document.IsNull() || document.Token() != token || owner.is_empty()) return;
  document_ = token;
  owner_ = owner;
  stylesheet_ = stylesheet;
  Apply();
}
void WebsiteThemeAgent::RemoveTheme(const blink::DocumentToken& token,
                                   const base::UnguessableToken& owner) {
  auto document = render_frame()->GetWebFrame()->GetDocument();
  if (document.IsNull() || document.Token() != token || document_ != token ||
      owner_ != owner) return;
  document.RemoveInsertedStyleSheet(StyleKey(), blink::WebCssOrigin::kAuthor);
  stylesheet_.clear();
  owner_.reset();
}
void WebsiteThemeAgent::Apply() {
  auto document = render_frame()->GetWebFrame()->GetDocument();
  if (document.IsNull() || document_ != document.Token() || !owner_) return;
  const auto key = StyleKey();
  // Blink's same-key InsertStyleSheet appends; remove exactly our prior sheet
  // first so repeated theme publications cannot accumulate stale palettes.
  document.RemoveInsertedStyleSheet(key, blink::WebCssOrigin::kAuthor);
  if (!stylesheet_.empty())
    document.InsertStyleSheet(blink::WebString::FromUtf8(stylesheet_), &key,
                             blink::WebCssOrigin::kAuthor,
                             blink::BackForwardCacheAware::kAllow);
}
void WebsiteThemeAgent::DidCreateNewDocument() {
  auto document = render_frame()->GetWebFrame()->GetDocument();
  if (document.IsNull() || document_ != document.Token()) {
    document_.reset();
    owner_.reset();
    stylesheet_.clear();
  }
}
void WebsiteThemeAgent::DidCreateDocumentElement() { Apply(); }
void WebsiteThemeAgent::OnDestruct() { delete this; }
}  // namespace parc
